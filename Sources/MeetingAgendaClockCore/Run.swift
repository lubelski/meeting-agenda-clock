import Foundation

/// Something the presenter did during a run, at a moment on the wall clock.
public struct RunEvent: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case pause
        case resume
        /// The current section is done. The next one starts now.
        case nextSection
        /// Back to the section before, with the time it had left when it was left (at least a minute).
        case previousSection
        /// One more minute for the current section.
        case addMinute
        /// The current section starts over from now.
        case restartSection
    }

    public var kind: Kind
    public var at: Date

    public init(_ kind: Kind, at: Date) {
        self.kind = kind
        self.at = at
    }
}

/// One live pass through an agenda. Only one exists at a time.
///
/// A run holds facts only: when it started, the agenda as it was then, and what the presenter
/// did and when. Everything on screen is computed from these and the current time by
/// `ClockEngine`, never counted up by a timer, so sleep and lag cannot make it drift.
public struct Run: Codable, Hashable, Sendable {
    /// The agenda as it was when the run started. Editing the saved agenda does not change it.
    public var agenda: Agenda
    public var startedAt: Date
    /// For a fixed-end agenda, the moment it ends, worked out once at the start.
    public var fixedEnd: Date?
    public var events: [RunEvent]

    public init(agenda: Agenda, startedAt: Date, fixedEnd: Date?, events: [RunEvent] = []) {
        self.agenda = agenda
        self.startedAt = startedAt
        self.fixedEnd = fixedEnd
        self.events = events
    }

    /// Starts a run of `agenda` at `date`.
    public static func start(_ agenda: Agenda, at date: Date, calendar: Calendar = .current) -> Run {
        let end: Date? = agenda.endRule == .fixedEnd
            ? agenda.fixedEndTime.endDate(forStart: date, calendar: calendar)
            : nil
        return Run(agenda: agenda, startedAt: date, fixedEnd: end)
    }

    public var agendaID: Agenda.ID { agenda.id }
    public var isFixedEnd: Bool { fixedEnd != nil }

    /// Whether the last pause has not been resumed.
    public var isPaused: Bool {
        var paused = false
        for event in events {
            switch event.kind {
            case .pause: if !isFixedEnd { paused = true }
            case .resume: paused = false
            default: break
            }
        }
        return paused
    }

    /// Whether `kind` would do anything at `date`. The controls are enabled from this.
    public func allows(_ kind: RunEvent.Kind, at date: Date) -> Bool {
        let state = ClockEngine.state(for: self, at: date)
        switch kind {
        case .pause: return !isFixedEnd && !isPaused
        case .resume: return isPaused
        case .nextSection: return state.canGoToNextSection
        case .previousSection: return state.canGoToPreviousSection
        case .addMinute, .restartSection: return !agenda.sections.isEmpty
        }
    }

    /// Records `kind` at `date` if it is allowed, and says whether it was.
    @discardableResult
    public mutating func record(_ kind: RunEvent.Kind, at date: Date) -> Bool {
        guard allows(kind, at: date) else { return false }
        events.append(RunEvent(kind, at: date))
        return true
    }
}
