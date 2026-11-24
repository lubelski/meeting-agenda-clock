import Foundation

/// The run as a schedule of wall-clock instants, for a client that draws the clock itself
/// (the phone page). It is computed from (run, now) by the same replay as `ClockState`, so the
/// client never needs the timing rules: it counts down from these instants until the next
/// snapshot arrives.
///
/// Instants are milliseconds since 1970, so JavaScript can use them as they are. Every instant
/// assumes the run is not paused from `serverNow` on. While it is paused, a client holds the
/// clock at `serverNow` instead of moving it.
public struct ScheduleSnapshot: Codable, Hashable, Sendable {
    public struct Section: Codable, Hashable, Sendable {
        public var name: String
        public var plannedSeconds: Double
        /// When the section's current span starts and ends, as now planned (after squeezes,
        /// taps, and +1 min). A section left by a tap has `start == end` at the moment it was left.
        public var start: Double
        public var end: Double
        /// Seconds spent in it on earlier visits, before `start`.
        public var spentSeconds: Double
    }

    public var agendaName: String
    public var isFixedEnd: Bool
    public var isPaused: Bool
    /// Whether Pause or Resume applies: only set-by-length agendas pause.
    public var canPause: Bool
    /// The server's clock when the snapshot was made. A client subtracts its own clock from this
    /// to correct for the difference between them.
    public var serverNow: Double
    /// When the run ends, as now planned.
    public var end: Double
    /// When the plan said it would end, for "over plan".
    public var plannedEnd: Double
    public var sections: [Section]

    /// The snapshot of `run` at `now`.
    public static func make(_ run: Run, at now: Date) -> ScheduleSnapshot {
        let (layout, t, isPaused) = ClockEngine.replay(run, at: now)
        let nowMs = (now.timeIntervalSince1970 * 1000).rounded()
        // Whole milliseconds: finer means nothing to a clock, and it keeps the JSON short.
        func instant(_ active: TimeInterval) -> Double { (nowMs + (active - t) * 1000).rounded() }
        let sections = (0..<layout.count).map { j in
            Section(
                name: layout.names[j],
                plannedSeconds: layout.planned[j],
                start: instant(layout.starts[j]),
                end: instant(layout.ends[j]),
                spentSeconds: layout.spent[j])
        }
        return ScheduleSnapshot(
            agendaName: run.agenda.name,
            isFixedEnd: run.isFixedEnd,
            isPaused: isPaused,
            canPause: !run.isFixedEnd,
            serverNow: nowMs,
            end: instant(layout.end),
            plannedEnd: instant(layout.plannedEnd),
            sections: sections)
    }
}
