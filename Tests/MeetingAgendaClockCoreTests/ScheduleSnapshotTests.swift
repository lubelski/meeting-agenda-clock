import Foundation
import Testing
@testable import MeetingAgendaClockCore

@Suite struct ScheduleSnapshotTests {
    func ms(_ date: Date) -> Double { date.timeIntervalSince1970 * 1000 }
    func at(_ minutesIn: Double) -> Date { tenOClock.addingTimeInterval(minutes(minutesIn)) }

    @Test func freshRunIsThePlanOnTheWallClock() {
        let snapshot = ScheduleSnapshot.make(lengthRun(), at: at(4))
        #expect(snapshot.agendaName == "Weekly demo")
        #expect(snapshot.serverNow == ms(at(4)))
        #expect(snapshot.end == ms(at(40)))
        #expect(snapshot.plannedEnd == ms(at(40)))
        #expect(snapshot.sections.map(\.start) == [0, 5, 10, 30].map { ms(at($0)) })
        #expect(snapshot.sections.map(\.end) == [5, 10, 30, 40].map { ms(at($0)) })
        #expect(snapshot.canPause)
        #expect(!snapshot.isPaused)
    }

    @Test func agreesWithTheClockState() {
        var run = lengthRun()
        run.accept(.nextSection, at: 3)
        run.accept(.addMinute, at: 6)
        let now = at(7)
        let snapshot = ScheduleSnapshot.make(run, at: now)
        let state = ClockEngine.state(for: run, at: now)
        #expect(snapshot.end == ms(state.endsAt))
        // Context runs 3 to 9 after the tap and the extra minute.
        #expect(snapshot.sections[1].start == ms(at(3)))
        #expect(snapshot.sections[1].end == ms(at(9)))
        // Intro was left by a tap at 3, after 3 minutes.
        #expect(snapshot.sections[0].start == snapshot.sections[0].end)
        #expect(snapshot.sections[0].spentSeconds == minutes(3))
        #expect(abs((snapshot.sections[1].end - snapshot.serverNow) / 1000 - state.sectionRemaining) < 0.001)
    }

    @Test func pausedInstantsAssumeTheClockMovesAgainNow() {
        var run = lengthRun()
        run.accept(.pause, at: 10)
        let snapshot = ScheduleSnapshot.make(run, at: at(15))
        #expect(snapshot.isPaused)
        // 30 minutes were left at the pause, so resuming at 15 ends at 45.
        #expect(snapshot.end == ms(at(45)))
        #expect(snapshot.sections[2].end == ms(at(35)))
    }

    @Test func fixedEndSqueezeShowsInTheInstants() {
        let run = fixedRun(startingAt: at(5))
        let snapshot = ScheduleSnapshot.make(run, at: at(5))
        #expect(!snapshot.canPause)
        #expect(snapshot.end == ms(at(40)))
        let durations = snapshot.sections.map { ($0.end - $0.start) / 1000 }
        #expect(abs(durations[2] - minutes(20 * 35.0 / 40)) < 0.01)
    }

    @Test func encodesAsPlainJSONNumbers() throws {
        let data = try JSONEncoder().encode(ScheduleSnapshot.make(lengthRun(), at: at(1)))
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(object?["end"] is Double)
        #expect((object?["sections"] as? [Any])?.count == 4)
    }
}
