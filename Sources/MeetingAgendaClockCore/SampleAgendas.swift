import Foundation

/// Stand-in agendas for a first launch, previews, and tests. Placeholder names only.
public enum SampleAgendas {
    public static let weeklyDemo = Agenda(
        id: UUID(uuidString: "6A1D0E52-0000-4000-8000-000000000001")!,
        name: "Weekly demo",
        sections: [
            AgendaSection(name: "Intro", minutes: 5),
            AgendaSection(name: "Context", minutes: 5),
            AgendaSection(name: "Demo", minutes: 20),
            AgendaSection(name: "Q&A", minutes: 10),
        ])

    public static let q4PlatformReview = Agenda(
        id: UUID(uuidString: "6A1D0E52-0000-4000-8000-000000000002")!,
        name: "Q4 platform review",
        sections: [
            AgendaSection(name: "Goals", minutes: 10),
            AgendaSection(name: "Metrics", minutes: 15),
            AgendaSection(name: "Roadmap", minutes: 20),
            AgendaSection(name: "Decisions", minutes: 15),
        ],
        endRule: .fixedEnd,
        fixedEndTime: ClockTime(hour: 11, minute: 0))

    public static let practiceExam = Agenda(
        id: UUID(uuidString: "6A1D0E52-0000-4000-8000-000000000003")!,
        name: "Practice exam",
        sections: [AgendaSection(name: "Exam", minutes: 90)])

    public static let all = [weeklyDemo, q4PlatformReview, practiceExam]
}
