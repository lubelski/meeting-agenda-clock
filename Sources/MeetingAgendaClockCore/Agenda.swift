import Foundation

/// One part of an agenda: a name and the minutes planned for it.
public struct AgendaSection: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var minutes: Double

    public init(id: UUID = UUID(), name: String, minutes: Double) {
        self.id = id
        self.name = name
        self.minutes = minutes
    }

    public var seconds: TimeInterval { max(0, minutes) * 60 }
}

/// A time of day, such as 10:40, with no date.
public struct ClockTime: Codable, Hashable, Sendable {
    public var hour: Int
    public var minute: Int

    public init(hour: Int, minute: Int) {
        self.hour = min(max(hour, 0), 23)
        self.minute = min(max(minute, 0), 59)
    }

    /// The date this time falls on that a run starting at `start` ends at. Today's, unless
    /// it passed more than an hour before the start, in which case tomorrow's. So a run
    /// started a few minutes after its end time is simply in overtime, and an exam started at
    /// 23:00 that ends at 01:00 ends tomorrow.
    public func endDate(forStart start: Date, calendar: Calendar = .current) -> Date {
        let today = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: start) ?? start
        if today.addingTimeInterval(3600) < start {
            return calendar.date(byAdding: .day, value: 1, to: today) ?? today
        }
        return today
    }
}

/// How an agenda decides when it ends.
public enum EndRule: String, Codable, CaseIterable, Hashable, Sendable {
    /// The sum of its sections. A run can pause, and +1 min makes it longer.
    case setByLength
    /// A wall-clock time. There is no pause, because the wall clock does not stop, and the
    /// sections squeeze or stretch to fit the time that is left.
    case fixedEnd

    public var title: String {
        switch self {
        case .setByLength: "Set by length"
        case .fixedEnd: "Fixed end time"
        }
    }
}

/// A saved plan. A plain countdown or an exam is an agenda with one section.
public struct Agenda: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var sections: [AgendaSection]
    public var endRule: EndRule
    /// Used when `endRule` is `.fixedEnd`. Kept when the rule changes, so switching back and
    /// forth does not lose it.
    public var fixedEndTime: ClockTime

    public init(
        id: UUID = UUID(), name: String, sections: [AgendaSection], endRule: EndRule = .setByLength,
        fixedEndTime: ClockTime = ClockTime(hour: 10, minute: 0)
    ) {
        self.id = id
        self.name = name
        self.sections = sections
        self.endRule = endRule
        self.fixedEndTime = fixedEndTime
    }

    public var totalMinutes: Double { sections.reduce(0) { $0 + max(0, $1.minutes) } }

    /// Whether it can start: at least one section and some time in it.
    public var canStart: Bool { !sections.isEmpty && totalMinutes > 0 }

    /// The sidebar's subtitle, such as "40 min · 4 sections", or "ends 10:40 · 4 sections".
    public var summary: String {
        let count = sections.count == 1 ? "1 section" : "\(sections.count) sections"
        switch endRule {
        case .setByLength:
            return "\(TimeFormat.minutes(totalMinutes)) · \(count)"
        case .fixedEnd:
            return "ends \(TimeFormat.clockTime(fixedEndTime)) · \(count)"
        }
    }

    /// A new agenda, as "New Agenda" makes it.
    public static func blank(endRule: EndRule = .setByLength, name: String = "New Agenda") -> Agenda {
        Agenda(name: name, sections: [AgendaSection(name: "Section 1", minutes: 10)], endRule: endRule)
    }
}
