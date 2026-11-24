import Foundation
import Testing
@testable import MeetingAgendaClockCore

/// A fixed calendar and start, so tests read the same anywhere.
let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

/// 2026-11-23 10:00:00 UTC.
let tenOClock = utc.date(from: DateComponents(year: 2026, month: 11, day: 23, hour: 10, minute: 0))!

func minutes(_ value: Double) -> TimeInterval { value * 60 }

extension Run {
    func state(_ minutesIn: Double) -> ClockState {
        ClockEngine.state(for: self, at: startedAt.addingTimeInterval(minutes(minutesIn)))
    }

    @discardableResult
    mutating func tap(_ kind: RunEvent.Kind, at minutesIn: Double) -> Bool {
        record(kind, at: startedAt.addingTimeInterval(minutes(minutesIn)))
    }

    /// Records `kind` and expects it to be allowed.
    mutating func accept(_ kind: RunEvent.Kind, at minutesIn: Double, sourceLocation: SourceLocation = #_sourceLocation) {
        let recorded = tap(kind, at: minutesIn)
        #expect(recorded, "\(kind) at \(minutesIn) was refused", sourceLocation: sourceLocation)
    }

    /// Tries `kind` and expects it to be refused.
    mutating func refuse(_ kind: RunEvent.Kind, at minutesIn: Double, sourceLocation: SourceLocation = #_sourceLocation) {
        let recorded = tap(kind, at: minutesIn)
        #expect(!recorded, "\(kind) at \(minutesIn) was allowed", sourceLocation: sourceLocation)
    }
}

/// Weekly demo: Intro 5, Context 5, Demo 20, Q&A 10, set by length.
func lengthRun(at start: Date = tenOClock) -> Run {
    Run.start(SampleAgendas.weeklyDemo, at: start, calendar: utc)
}

/// The same sections, ending at 10:40 on the wall clock.
func fixedRun(startingAt start: Date = tenOClock, endHour: Int = 10, endMinute: Int = 40) -> Run {
    var agenda = SampleAgendas.weeklyDemo
    agenda.endRule = .fixedEnd
    agenda.fixedEndTime = ClockTime(hour: endHour, minute: endMinute)
    return Run.start(agenda, at: start, calendar: utc)
}

@Suite struct ScheduleDrivenTests {
    @Test func freshRunShowsTheWholePlan() {
        let state = lengthRun().state(0)
        #expect(state.remaining == minutes(40))
        #expect(state.currentIndex == 0)
        #expect(state.currentSectionName == "Intro")
        #expect(state.sectionRemaining == minutes(5))
        #expect(!state.isOvertime)
        #expect(state.primaryText == "40:00")
        #expect(state.endsAt == tenOClock.addingTimeInterval(minutes(40)))
    }

    @Test func sectionsMoveOnByTheClockWithNoInput() {
        let run = lengthRun()
        #expect(run.state(7).currentSectionName == "Context")
        #expect(run.state(7).sectionRemaining == minutes(3))
        #expect(run.state(7).remaining == minutes(33))
        #expect(run.state(12).currentSectionName == "Demo")
        #expect(run.state(12).sectionRemaining == minutes(18))
        #expect(run.state(39.5).currentSectionName == "Q&A")
    }

    @Test func aBoundaryBelongsToTheNextSection() {
        #expect(lengthRun().state(5).currentSectionName == "Context")
        #expect(lengthRun().state(5).sectionRemaining == minutes(5))
    }

    @Test func atZeroItIsNotYetOvertime() {
        let state = lengthRun().state(40)
        #expect(state.remaining == 0)
        #expect(state.overtime == 0)
        #expect(!state.isOvertime)
        #expect(state.primaryText == "0:00")
        #expect(state.currentSectionName == "Q&A")
    }

    @Test func afterZeroItCountsUp() {
        let state = lengthRun().state(41 + 20.0 / 60)
        #expect(state.isOvertime)
        #expect(state.overtime == 80)
        #expect(state.primaryText == "+1:20")
        #expect(state.currentSectionName == "Q&A")
        #expect(state.sectionRemaining == 0)
        #expect(state.endsAt == tenOClock.addingTimeInterval(minutes(40)))
        #expect(state.sections.allSatisfy { $0.filled == 1 })
    }

    @Test func aLongSleepCannotDrift() {
        // Nothing ticks, so waking two hours later reads the same as having watched the whole time.
        let state = lengthRun().state(120)
        #expect(state.overtime == minutes(80))
    }

    @Test func theSameMomentAlwaysGivesTheSameState() {
        let run = lengthRun()
        let first = run.state(17.25)
        _ = run.state(3)
        _ = run.state(30)
        #expect(run.state(17.25) == first)
    }

    @Test func barFillsUpToNow() {
        let fill = lengthRun().state(12.5).sections.map(\.filled)
        #expect(fill == [1, 1, 0.125, 0])
        let statuses = lengthRun().state(12.5).sections.map(\.status)
        #expect(statuses == [.done, .done, .current, .upcoming])
    }

    @Test func aPlainCountdownIsOneSection() {
        let run = Run.start(SampleAgendas.practiceExam, at: tenOClock, calendar: utc)
        #expect(run.state(30).remaining == minutes(60))
        #expect(run.state(30).currentSectionName == "Exam")
        #expect(run.state(30).sections.map(\.filled) == [1.0 / 3])
        #expect(!run.allows(.nextSection, at: tenOClock.addingTimeInterval(60)))
        #expect(!run.allows(.previousSection, at: tenOClock.addingTimeInterval(60)))
    }

    @Test func eventsRecordedOutOfOrderCannotMoveTheRunBack() {
        var run = lengthRun()
        run.events = [
            RunEvent(.nextSection, at: tenOClock.addingTimeInterval(minutes(3))),
            RunEvent(.addMinute, at: tenOClock.addingTimeInterval(minutes(1))),
        ]
        // The +1 min counts at minute 3, in Context, which now runs 3 to 9.
        let state = run.state(4)
        #expect(state.currentSectionName == "Context")
        #expect(state.sectionRemaining == minutes(5))
    }
}

@Suite struct PauseTests {
    @Test func pauseStopsTheClockAndMovesTheEnd() {
        var run = lengthRun()
        run.accept(.pause, at: 10)
        #expect(run.isPaused)
        let paused = run.state(13)
        #expect(paused.isPaused)
        #expect(paused.elapsed == minutes(10))
        #expect(paused.remaining == minutes(30))
        #expect(paused.endsAt == tenOClock.addingTimeInterval(minutes(43)))

        run.accept(.resume, at: 15)
        let resumed = run.state(20)
        #expect(!resumed.isPaused)
        #expect(resumed.elapsed == minutes(15))
        #expect(resumed.remaining == minutes(25))
        #expect(resumed.endsAt == tenOClock.addingTimeInterval(minutes(45)))
    }

    @Test func pauseTwiceOrResumeUnpausedIsRefused() {
        var run = lengthRun()
        run.refuse(.resume, at: 1)
        run.accept(.pause, at: 2)
        run.refuse(.pause, at: 3)
        #expect(run.events.count == 1)
    }

    @Test func aFixedEndAgendaHasNoPause() {
        var run = fixedRun()
        #expect(!run.allows(.pause, at: tenOClock))
        run.refuse(.pause, at: 10)
        #expect(run.events.isEmpty)
    }

    @Test func aPauseInAFixedEndFileIsIgnored() {
        var run = fixedRun()
        run.events = [
            RunEvent(.pause, at: tenOClock.addingTimeInterval(minutes(10))),
            RunEvent(.resume, at: tenOClock.addingTimeInterval(minutes(20))),
        ]
        #expect(!run.isPaused)
        #expect(run.state(25).remaining == minutes(15))
    }

    @Test func tapsWhilePausedCountAtThePausedMoment() {
        var run = lengthRun()
        run.accept(.pause, at: 3)
        run.accept(.nextSection, at: 6)
        run.accept(.resume, at: 8)
        // Intro was left at 3 active minutes. At 10 wall minutes, 5 are active.
        let state = run.state(10)
        #expect(state.currentSectionName == "Context")
        #expect(state.sectionRemaining == minutes(3))
    }
}

@Suite struct FixedEndTests {
    @Test func startedOnTimeMatchesThePlan() {
        let state = fixedRun().state(12)
        #expect(state.remaining == minutes(28))
        #expect(state.currentSectionName == "Demo")
        #expect(state.sections.map(\.scheduledSeconds) == [5, 5, 20, 10].map { minutes($0) })
        #expect(state.overPlan == 0)
    }

    @Test func startedLateSqueezesEverySectionInProportion() {
        let run = fixedRun(startingAt: tenOClock.addingTimeInterval(minutes(5)))
        let state = run.state(0)
        #expect(state.remaining == minutes(35))
        let scheduled = state.sections.map(\.scheduledSeconds)
        let expected = [5.0, 5, 20, 10].map { minutes($0 * 35 / 40) }
        for (a, b) in zip(scheduled, expected) { #expect(abs(a - b) < 0.001) }
        #expect(state.endsAt == tenOClock.addingTimeInterval(minutes(40)))
    }

    @Test func startedAfterTheEndIsOvertimeAtOnce() {
        let run = fixedRun(startingAt: tenOClock.addingTimeInterval(minutes(45)))
        let state = run.state(0)
        #expect(state.remaining == 0)
        #expect(state.overtime == minutes(5))
        #expect(state.primaryText == "+5:00")
    }

    @Test func endTimeEarlierInTheDayMeansTomorrow() {
        let late = utc.date(from: DateComponents(year: 2026, month: 11, day: 23, hour: 23, minute: 0))!
        let end = ClockTime(hour: 1, minute: 0).endDate(forStart: late, calendar: utc)
        #expect(end == late.addingTimeInterval(minutes(120)))
    }

    @Test func endTimeJustPassedMeansToday() {
        let start = tenOClock.addingTimeInterval(minutes(5))
        let end = ClockTime(hour: 10, minute: 0).endDate(forStart: start, calendar: utc)
        #expect(end == tenOClock)
    }

    @Test func nextEarlyGivesTheTimeToTheSectionsLeft() {
        var run = fixedRun()
        run.accept(.nextSection, at: 3)
        let state = run.state(3)
        #expect(state.remaining == minutes(37))
        #expect(state.currentSectionName == "Context")
        // Context, Demo, and Q&A share 37 minutes as 5 : 20 : 10.
        #expect(abs(state.sectionRemaining - minutes(37.0 * 5 / 35)) < 0.001)
        #expect(state.sections[0].scheduledSeconds == minutes(3))
        #expect(state.sections[0].status == .done)
        #expect(state.endsAt == tenOClock.addingTimeInterval(minutes(40)))
    }

    @Test func addMinuteSqueezesTheLaterSections() {
        var run = fixedRun()
        run.accept(.addMinute, at: 2)
        let state = run.state(2)
        #expect(state.sectionRemaining == minutes(4))
        #expect(state.remaining == minutes(38))
        let later = state.sections[1...].map(\.scheduledSeconds).reduce(0, +)
        #expect(abs(later - minutes(34)) < 0.001)
        #expect(abs(state.sections[2].scheduledSeconds - minutes(34.0 * 20 / 35)) < 0.001)
        #expect(state.overPlan == 0)
    }

    @Test func addMinuteOnTheLastSectionMovesTheEnd() {
        var run = fixedRun()
        run.accept(.addMinute, at: 35)
        let state = run.state(35)
        #expect(state.currentSectionName == "Q&A")
        #expect(state.remaining == minutes(6))
        #expect(state.overPlan == 60)
    }

    @Test func restartSqueezesWhatIsLeft() {
        var run = fixedRun()
        run.accept(.restartSection, at: 8)
        let state = run.state(8)
        #expect(state.currentSectionName == "Context")
        #expect(state.remaining == minutes(32))
        // Context, Demo, and Q&A share the 32 minutes left as 5 : 20 : 10.
        #expect(abs(state.sectionRemaining - minutes(32.0 * 5 / 35)) < 0.001)
    }
}

@Suite struct SetByLengthTests {
    @Test func nextEarlyMovesTheEndEarlier() {
        var run = lengthRun()
        run.accept(.nextSection, at: 3)
        let state = run.state(3)
        #expect(state.currentSectionName == "Context")
        #expect(state.sectionRemaining == minutes(5))
        #expect(state.remaining == minutes(35))
        #expect(state.overPlan == -minutes(2))
        #expect(state.sections[0].scheduledSeconds == minutes(3))
    }

    @Test func addMinuteExtendsTheSectionAndTheTotal() {
        var run = lengthRun()
        run.accept(.addMinute, at: 2)
        let state = run.state(2)
        #expect(state.sectionRemaining == minutes(4))
        #expect(state.remaining == minutes(39))
        #expect(state.overPlan == 60)
        #expect(state.sections.map(\.scheduledSeconds) == [6, 5, 20, 10].map { minutes($0) })
        #expect(run.state(5.5).currentSectionName == "Intro")
    }

    @Test func addMinuteInOvertimeTakesAMinuteOff() {
        var run = lengthRun()
        run.accept(.addMinute, at: 43)
        let state = run.state(43)
        #expect(state.overtime == minutes(2))
        #expect(state.primaryText == "+2:00")
    }

    @Test func addMinuteJustPastZeroBringsTimeBack() {
        var run = lengthRun()
        run.accept(.addMinute, at: 40.5)
        let state = run.state(40.5)
        #expect(!state.isOvertime)
        #expect(state.remaining == 30)
    }

    @Test func restartGivesTheSectionItsTimeAgain() {
        var run = lengthRun()
        run.accept(.restartSection, at: 8)
        let state = run.state(8)
        #expect(state.currentSectionName == "Context")
        #expect(state.sectionRemaining == minutes(5))
        #expect(state.remaining == minutes(35))
        #expect(state.overPlan == minutes(3))
        // The bar keeps the three minutes already spent in Context.
        #expect(state.sections[1].scheduledSeconds == minutes(8))
    }

    @Test func previousUndoesAnAccidentalNext() {
        var run = lengthRun()
        run.accept(.nextSection, at: 2)
        run.accept(.previousSection, at: 2.5)
        let state = run.state(2.5)
        #expect(state.currentSectionName == "Intro")
        #expect(state.sectionRemaining == minutes(3))
        #expect(state.canGoToNextSection)
        #expect(!state.canGoToPreviousSection)
    }

    @Test func previousIntoASectionTheClockLeftGivesAMinute() {
        var run = lengthRun()
        run.accept(.previousSection, at: 7)
        let state = run.state(7)
        #expect(state.currentSectionName == "Intro")
        #expect(state.sectionRemaining == 60)
        #expect(run.state(8).currentSectionName == "Context")
    }

    @Test func previousInOvertimeGoesBackFromTheLastSection() {
        var run = lengthRun()
        run.accept(.previousSection, at: 42)
        let state = run.state(42)
        #expect(state.currentSectionName == "Demo")
        #expect(!state.isOvertime)
        #expect(state.remaining == minutes(11))
    }

    @Test func nextOnTheLastSectionAndPreviousOnTheFirstAreRefused() {
        var run = lengthRun()
        run.refuse(.previousSection, at: 1)
        run.refuse(.nextSection, at: 35)
        run.refuse(.nextSection, at: 45)
        #expect(run.events.isEmpty)
    }

    @Test func aRunOfTapsAddsUp() {
        var run = lengthRun()
        run.accept(.nextSection, at: 4)     // Intro took 4, Context runs 4 to 9
        run.accept(.nextSection, at: 8)     // Context took 4, Demo runs 8 to 28
        run.accept(.addMinute, at: 25)      // Demo now ends at 29
        run.accept(.nextSection, at: 27)    // Demo took 19, Q&A runs 27 to 37
        let state = run.state(30)
        #expect(state.currentSectionName == "Q&A")
        #expect(state.sectionRemaining == minutes(7))
        #expect(state.sections.map(\.scheduledSeconds) == [4, 4, 19, 10].map { minutes($0) })
        #expect(state.overPlan == -minutes(3))
    }
}
