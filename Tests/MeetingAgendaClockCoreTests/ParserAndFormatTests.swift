import Foundation
import Testing
@testable import MeetingAgendaClockCore

@Suite struct AgendaParserTests {
    func summary(_ text: String) -> [String] {
        AgendaParser.parse(text).sections.map { "\($0.name)=\(TimeFormat.number($0.minutes))" }
    }

    @Test func readsTheExampleFromTheBrief() {
        #expect(summary("5 intro, 5 context, 20 demo, 10 q&a") == ["Intro=5", "Context=5", "Demo=20", "Q&A=10"])
    }

    @Test func readsTheLengthAtEitherEnd() {
        #expect(summary("intro 5, demo: 20, wrap-up (3)") == ["Intro=5", "Demo=20", "Wrap-up=3"])
    }

    @Test func readsUnits() {
        #expect(summary("5m intro, 1h deep dive, 90s close, 2.5 min recap, review 1.5 h")
            == ["Intro=5", "Deep Dive=60", "Close=1.5", "Recap=2.5", "Review=90"])
    }

    @Test func aNameStartingWithAUnitLetterIsStillAName() {
        #expect(summary("5 metrics, 10 setup, 3 housekeeping") == ["Metrics=5", "Setup=10", "Housekeeping=3"])
    }

    @Test func keepsMixedCaseAsTyped() {
        #expect(summary("10 API walkthrough") == ["API walkthrough=10"])
    }

    @Test func acceptsSemicolonsAndNewLines() {
        #expect(summary("5 intro; 10 demo\n5 close") == ["Intro=5", "Demo=10", "Close=5"])
    }

    @Test func aBareNumberIsANamelessSection() {
        #expect(summary("90") == ["Section 1=90"])
    }

    @Test func reportsWhatItCannotRead() {
        let result = AgendaParser.parse("5 intro, demo, 0 nothing, , 10 q&a")
        #expect(result.sections.map(\.name) == ["Intro", "Q&A"])
        #expect(result.problems.count == 2)
        #expect(result.problems[0].contains("demo"))
    }

    @Test func emptyTextIsEmpty() {
        #expect(AgendaParser.parse("  ").isEmpty)
        #expect(AgendaParser.parse("  ").problems.isEmpty)
    }

    @Test func formatReadsBackTheSame() {
        let sections = SampleAgendas.weeklyDemo.sections
        let line = AgendaParser.format(sections)
        #expect(line == "5 Intro, 5 Context, 20 Demo, 10 Q&A")
        let back = AgendaParser.parse(line).sections
        #expect(back.map(\.name) == sections.map(\.name))
        #expect(back.map(\.minutes) == sections.map(\.minutes))
    }
}

@Suite struct TimeFormatTests {
    @Test func countdownRoundsUp() {
        #expect(TimeFormat.countdown(2160) == "36:00")
        #expect(TimeFormat.countdown(2159.2) == "36:00")
        #expect(TimeFormat.countdown(0.3) == "0:01")
        #expect(TimeFormat.countdown(0) == "0:00")
        #expect(TimeFormat.countdown(-5) == "0:00")
        #expect(TimeFormat.countdown(3723) == "1:02:03")
    }

    @Test func overtimeRoundsDown() {
        #expect(TimeFormat.overtime(80.9) == "+1:20")
        #expect(TimeFormat.overtime(3600) == "+1:00:00")
    }

    @Test func minutesAndClockTimes() {
        #expect(TimeFormat.minutes(40) == "40 min")
        #expect(TimeFormat.minutes(2.5) == "2.5 min")
        #expect(TimeFormat.clockTime(ClockTime(hour: 10, minute: 40)) == "10:40")
        #expect(TimeFormat.clockTime(ClockTime(hour: 13, minute: 5)) == "1:05")
        #expect(TimeFormat.clockTime(ClockTime(hour: 0, minute: 0)) == "12:00")
        #expect(TimeFormat.clockTime(tenOClock.addingTimeInterval(minutes(40)), calendar: utc) == "10:40")
    }
}

@Suite struct AgendaTests {
    @Test func summaryForTheSidebar() {
        #expect(SampleAgendas.weeklyDemo.summary == "40 min · 4 sections")
        #expect(SampleAgendas.practiceExam.summary == "90 min · 1 section")
        #expect(SampleAgendas.q4PlatformReview.summary == "ends 11:00 · 4 sections")
    }

    @Test func anEmptyAgendaCannotStart() {
        #expect(!Agenda(name: "Empty", sections: []).canStart)
        #expect(!Agenda(name: "Zero", sections: [AgendaSection(name: "A", minutes: 0)]).canStart)
        #expect(SampleAgendas.weeklyDemo.canStart)
    }

    @Test func experimentsAreOffAndOnlyEdgeLineIsBuilt() {
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        #expect(Experiment.allCases.count == 6)
        #expect(Experiment.allCases.allSatisfy { !$0.isOn(defaults) })
        #expect(Experiment.allCases.filter(\.isBuilt) == [.edgeLine])
        for experiment in Experiment.allCases where !experiment.isBuilt {
            #expect(experiment.description.hasSuffix("Not built yet."))
        }
        Experiment.menuBarRing.set(true, defaults)
        #expect(Experiment.menuBarRing.isOn(defaults))
    }

    @Test func generalDefaults() {
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        #expect(GeneralPreference.defaultEndRule(defaults) == .setByLength)
        #expect(GeneralPreference.opensClockWindowOnStart(defaults))
        defaults.set(EndRule.fixedEnd.rawValue, forKey: GeneralPreference.defaultEndRuleKey)
        #expect(GeneralPreference.defaultEndRule(defaults) == .fixedEnd)
    }
}

@Suite struct AgendaStoreTests {
    func temporaryStore() -> AgendaStore {
        AgendaStore(folder: FileManager.default.temporaryDirectory
            .appending(path: "meeting-agenda-clock-tests-\(UUID().uuidString)", directoryHint: .isDirectory))
    }

    @Test func nothingSavedReadsAsNil() throws {
        let store = temporaryStore()
        #expect(try store.loadAgendas() == nil)
        #expect(try store.loadRun() == nil)
    }

    @Test func agendasRoundTrip() throws {
        let store = temporaryStore()
        try store.save(SampleAgendas.all)
        #expect(try store.loadAgendas() == SampleAgendas.all)
    }

    @Test func runRoundTripsAndEndingRemovesIt() throws {
        let store = temporaryStore()
        var run = fixedRun()
        run.accept(.addMinute, at: 3.25)
        try store.save(run)
        #expect(try store.loadRun() == run)
        try store.save(nil as Run?)
        #expect(try store.loadRun() == nil)
        #expect(!FileManager.default.fileExists(atPath: store.runFile.path))
    }

    @Test func dataFolderArgument() {
        let url = AppPaths.dataFolder(arguments: ["app", "--data-folder", "/tmp/somewhere"])
        #expect(url.path == "/tmp/somewhere")
        #expect(AppPaths.dataFolder(arguments: ["app"]).path.hasSuffix("Application Support/meeting-agenda-clock"))
    }
}
