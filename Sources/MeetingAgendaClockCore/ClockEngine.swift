import Foundation

/// One section as the clock sees it at a moment.
public struct SectionState: Hashable, Sendable, Identifiable {
    public enum Status: String, Sendable {
        case done
        case current
        case upcoming
    }

    public var index: Int
    public var name: String
    /// What the agenda planned for it.
    public var plannedSeconds: TimeInterval
    /// What it has now: the time it took if it is done, or the time it is given if it is
    /// current or upcoming. Differs from the plan after a tap, +1 min, or a squeeze.
    public var scheduledSeconds: TimeInterval
    /// How much of the section's share of the bar is filled, from 0 to 1.
    public var filled: Double
    public var status: Status

    public var id: Int { index }
}

/// What the clock shows at a moment: everything the views need, computed from a run and the time.
public struct ClockState: Hashable, Sendable {
    public var agendaName: String
    public var isFixedEnd: Bool
    public var isPaused: Bool
    /// Seconds of the run that have counted, which leaves out pauses.
    public var elapsed: TimeInterval
    /// Seconds until the end. Zero in overtime.
    public var remaining: TimeInterval
    /// Seconds past the end. Zero before it.
    public var overtime: TimeInterval
    /// When the run ends on the wall clock, as things stand. In overtime, when it ended.
    public var endsAt: Date
    /// The section the plan says is happening now. In overtime, the last one.
    public var currentIndex: Int?
    /// Seconds left in the current section. Zero in overtime.
    public var sectionRemaining: TimeInterval
    public var sections: [SectionState]
    /// How far the end has moved from the plan: positive when it is later than planned (over),
    /// negative when earlier (under).
    public var overPlan: TimeInterval
    public var canGoToNextSection: Bool
    public var canGoToPreviousSection: Bool

    public var isOvertime: Bool { overtime > 0 }

    public var currentSectionName: String? {
        currentIndex.map { sections[$0].name }
    }

    /// The big number: the time left, or the overtime with a plus.
    public var primaryText: String {
        isOvertime ? TimeFormat.overtime(overtime) : TimeFormat.countdown(remaining)
    }
}

/// The timing rules. Pure functions of (run, now): the run's events are replayed in order to
/// lay out the sections, then read at `now`.
///
/// Times inside are "active" seconds since the start, which leave out pauses. A fixed-end run
/// never pauses, so for it active time is wall-clock time.
public enum ClockEngine {
    public static func state(for run: Run, at now: Date) -> ClockState {
        let (layout, t, isPaused) = replay(run, at: now)
        return layout.state(at: t, now: now, isPaused: isPaused, agendaName: run.agenda.name)
    }

    /// Replays the run's events, and returns the layout, the active time at `now`, and whether
    /// the run is paused.
    static func replay(_ run: Run, at now: Date) -> (Layout, TimeInterval, Bool) {
        var layout = Layout(run: run)
        var pausedTotal: TimeInterval = 0
        var pausedSince: Date?
        var last: TimeInterval = 0

        func active(_ date: Date) -> TimeInterval {
            var value = date.timeIntervalSince(run.startedAt) - pausedTotal
            if let pausedSince { value -= max(0, date.timeIntervalSince(pausedSince)) }
            // Events are replayed in the order they were recorded. A clock change cannot move
            // the run backwards.
            return max(last, value, 0)
        }

        for event in run.events {
            switch event.kind {
            case .pause:
                guard !run.isFixedEnd, pausedSince == nil else { continue }
                last = active(event.at)
                pausedSince = event.at
            case .resume:
                guard let since = pausedSince else { continue }
                pausedTotal += max(0, event.at.timeIntervalSince(since))
                pausedSince = nil
            default:
                let t = active(event.at)
                last = t
                layout.apply(event.kind, at: t)
            }
        }
        return (layout, active(now), pausedSince != nil)
    }
}

/// The sections laid out on the run's active timeline.
///
/// Each section has a start and an end. A section that is left by a tap keeps the time it took
/// in `spent` and has its start and end set to the same moment, so a section's share of the bar
/// is always `spent + (end - start)`.
struct Layout {
    let isFixedEnd: Bool
    let names: [String]
    /// The planned seconds, from the agenda.
    let planned: [TimeInterval]
    /// The seconds each section is meant to have: the plan plus any +1 min. On a fixed-end
    /// run these are weights: the sections left share the time left in this proportion.
    var allotted: [TimeInterval]
    var starts: [TimeInterval]
    var ends: [TimeInterval]
    var spent: [TimeInterval]
    /// The time a section had left when a tap left it, for Previous Section.
    var leftWith: [TimeInterval?]
    /// For a fixed-end run, where the end is on the active timeline.
    var endOffset: TimeInterval
    /// Where the plan put the end, for `overPlan`.
    let plannedEnd: TimeInterval

    var count: Int { names.count }

    init(run: Run) {
        isFixedEnd = run.isFixedEnd
        names = run.agenda.sections.map(\.name)
        planned = run.agenda.sections.map(\.seconds)
        allotted = planned
        let n = names.count
        starts = Array(repeating: 0, count: n)
        ends = Array(repeating: 0, count: n)
        spent = Array(repeating: 0, count: n)
        leftWith = Array(repeating: nil, count: n)
        if let fixedEnd = run.fixedEnd {
            // Negative when the run started after its end time.
            endOffset = fixedEnd.timeIntervalSince(run.startedAt)
            plannedEnd = endOffset
        } else {
            endOffset = 0
            plannedEnd = planned.reduce(0, +)
        }
        relay(from: 0, at: 0)
    }

    /// Lays out sections `index` onward, starting at `t`. On a set-by-length run each gets its
    /// allotted time, one after another. On a fixed-end run they share what is left before the
    /// end in proportion to their allotted time, so a late start or a slow section squeezes
    /// them, and an early tap gives them more.
    mutating func relay(from index: Int, at t: TimeInterval) {
        guard index < count else { return }
        var cursor = t
        if isFixedEnd {
            // Past the end, the sections left have no time. They sit at the end, so the end
            // stays where the wall clock put it and the overtime counts from there.
            if t >= endOffset {
                for j in index..<count {
                    starts[j] = endOffset
                    ends[j] = endOffset
                }
                return
            }
            let available = endOffset - t
            let weight = allotted[index...].reduce(0, +)
            for j in index..<count {
                let share = weight > 0 ? allotted[j] / weight : 1 / Double(count - index)
                starts[j] = cursor
                cursor += available * share
                ends[j] = cursor
            }
            // Exactly on the end, whatever the rounding on the way.
            ends[count - 1] = endOffset
        } else {
            for j in index..<count {
                starts[j] = cursor
                cursor += allotted[j]
                ends[j] = cursor
            }
        }
    }

    /// The section the plan has running at `t`, or nil past the end.
    func current(at t: TimeInterval) -> Int? {
        (0..<count).first { ends[$0] > t && ends[$0] > starts[$0] }
    }

    var end: TimeInterval { ends.max() ?? 0 }

    /// Leaves section `i` at `t`, keeping the time it took.
    mutating func leave(_ i: Int, at t: TimeInterval) {
        spent[i] += max(0, t - starts[i])
        starts[i] = t
        ends[i] = t
    }

    mutating func apply(_ kind: RunEvent.Kind, at t: TimeInterval) {
        guard count > 0 else { return }
        let i = current(at: t) ?? count - 1
        switch kind {
        case .nextSection:
            guard let i = current(at: t), i < count - 1 else { return }
            leftWith[i] = max(0, ends[i] - t)
            leave(i, at: t)
            relay(from: i + 1, at: t)
        case .previousSection:
            guard i > 0 else { return }
            let back = i - 1
            leave(i, at: t)
            let time = max(leftWith[back] ?? 0, 60)
            leftWith[back] = nil
            starts[back] = t
            ends[back] = t + time
            relay(from: i, at: ends[back])
        case .restartSection:
            leave(i, at: t)
            if isFixedEnd {
                relay(from: i, at: t)
            } else {
                ends[i] = t + allotted[i]
                relay(from: i + 1, at: ends[i])
            }
        case .addMinute:
            allotted[i] += 60
            // In overtime the last section's end is behind `t`. The minute still counts from
            // that end, so +1 min three minutes over leaves two minutes over.
            ends[i] += 60
            if isFixedEnd && i == count - 1 {
                endOffset += 60
            } else {
                relay(from: i + 1, at: ends[i])
            }
        case .pause, .resume:
            break
        }
    }

    func state(at t: TimeInterval, now: Date, isPaused: Bool, agendaName: String) -> ClockState {
        let end = end
        let live = current(at: t)
        let shown = count == 0 ? nil : (live ?? count - 1)
        var sections: [SectionState] = []
        for j in 0..<count {
            let width = spent[j] + (ends[j] - starts[j])
            let status: SectionState.Status
            let filledSeconds: TimeInterval
            if let shown, j < shown {
                status = .done
                filledSeconds = width
            } else if j == shown {
                status = .current
                filledSeconds = spent[j] + max(0, min(t, ends[j]) - starts[j])
            } else {
                status = .upcoming
                filledSeconds = spent[j]
            }
            sections.append(SectionState(
                index: j, name: names[j], plannedSeconds: planned[j], scheduledSeconds: width,
                filled: width > 0 ? min(1, max(0, filledSeconds / width)) : (status == .done ? 1 : 0),
                status: status))
        }
        return ClockState(
            agendaName: agendaName,
            isFixedEnd: isFixedEnd,
            isPaused: isPaused,
            elapsed: t,
            remaining: max(0, end - t),
            overtime: max(0, t - end),
            endsAt: now.addingTimeInterval(end - t),
            currentIndex: shown,
            sectionRemaining: live.map { max(0, ends[$0] - t) } ?? 0,
            sections: sections,
            overPlan: end - plannedEnd,
            canGoToNextSection: live.map { $0 < count - 1 } ?? false,
            canGoToPreviousSection: (shown ?? 0) > 0)
    }
}
