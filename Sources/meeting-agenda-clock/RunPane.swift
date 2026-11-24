import MeetingAgendaClockCore
import SwiftUI

/// The running agenda's pane: the live clock, the controls, and the sections with the current
/// one highlighted.
struct RunPane: View {
    let model: AppModel
    let run: Run

    var body: some View {
        Ticking(paused: run.isPaused) { now in
            let state = ClockEngine.state(for: run, at: now)
            Form {
                Section {
                    LiveClockView(state: state, style: .pane)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                    controls(state)
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 4)
                } header: {
                    HStack(spacing: 6) {
                        Circle().fill(ClockColors.running).frame(width: 8, height: 8)
                        Text(state.isPaused ? "Paused" : "Running")
                        Text("·")
                        Text(planText(state)).monospacedDigit()
                    }
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .textCase(nil)
                }

                Section("Sections") {
                    ForEach(state.sections) { section in
                        RunSectionRow(section: section, state: state)
                    }
                }
            }
            .formStyle(.grouped)
        }
    }

    private func planText(_ state: ClockState) -> String {
        let base = state.isFixedEnd ? "fixed end" : "set by length"
        if abs(state.overPlan) < 1 { return "\(base) · on plan" }
        let amount = TimeFormat.duration(state.overPlan)
        return state.overPlan > 0 ? "\(base) · \(amount) over plan" : "\(base) · \(amount) under plan"
    }

    private func controls(_ state: ClockState) -> some View {
        HStack(spacing: 10) {
            if !run.isFixedEnd {
                if run.isPaused {
                    Button { model.perform(.resume) } label: { Label("Resume", systemImage: "play.fill") }
                } else {
                    Button { model.perform(.pause) } label: { Label("Pause", systemImage: "pause.fill") }
                }
            }
            Button { model.perform(.nextSection) } label: { Label("Next Section", systemImage: "forward.end.fill") }
                .disabled(!state.canGoToNextSection)
            Button { model.perform(.addMinute) } label: { Label("+1 min", systemImage: "plus") }
            Button { model.perform(.restartSection) } label: { Label("Restart Section", systemImage: "arrow.counterclockwise") }
            Button(role: .destructive) { model.endRun() } label: { Label("End", systemImage: "stop.fill") }
        }
        .controlSize(.large)
        .labelStyle(.titleAndIcon)
    }
}

struct RunSectionRow: View {
    let section: SectionState
    let state: ClockState

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(section.status == .current ? Color.accentColor : .secondary)
                .frame(width: 16)
            Text(section.name)
                .fontWeight(.regular)
            Spacer()
            Text(timeText)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .listRowBackground(section.status == .current ? Color.accentColor.opacity(0.14) : nil)
    }

    private var symbol: String {
        switch section.status {
        case .done: "checkmark.circle.fill"
        case .current: "play.circle.fill"
        case .upcoming: "circle"
        }
    }

    private var timeText: String {
        let planned = TimeFormat.duration(section.plannedSeconds)
        switch section.status {
        case .done:
            return "took \(TimeFormat.duration(section.scheduledSeconds))"
        case .current:
            if state.isOvertime { return "\(state.primaryText) over" }
            return "\(TimeFormat.countdown(state.sectionRemaining)) left of \(TimeFormat.duration(section.scheduledSeconds))"
        case .upcoming:
            let scheduled = TimeFormat.duration(section.scheduledSeconds)
            return scheduled == planned ? planned : "\(scheduled), planned \(planned)"
        }
    }
}
