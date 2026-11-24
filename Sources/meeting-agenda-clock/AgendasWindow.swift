import MeetingAgendaClockCore
import SwiftUI

/// The main window, laid out like System Settings: a sidebar of agendas at a fixed width, and
/// the selected agenda beside it. The running agenda's pane is the live view.
struct AgendasRootView: View {
    static let sidebarWidth: CGFloat = 230

    @Bindable var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        // A plain row rather than a split view, so the sidebar keeps its width: it cannot be
        // dragged or collapsed.
        HStack(spacing: 0) {
            AgendaSidebar(model: model)
                .frame(width: Self.sidebarWidth)
            Divider()
            detail
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        }
        .navigationTitle(model.selectedAgenda?.name ?? "Agendas")
    }

    @ViewBuilder private var detail: some View {
        if let index = model.index(of: model.selection) {
            let agenda = model.agendas[index]
            if let run = model.run, run.agendaID == agenda.id {
                RunPane(model: model, run: run)
            } else {
                AgendaEditor(model: model, agenda: $model.agendas[index], start: { start(agenda.id) })
            }
        } else {
            ContentUnavailableView {
                Label("No Agenda", systemImage: "list.bullet.rectangle")
            } description: {
                Text("Choose New Agenda to plan one.")
            }
        }
    }

    private func start(_ id: Agenda.ID) {
        if model.start(id), model.opensClockWindowOnStart {
            openWindow(id: WindowID.clock)
        }
    }
}

struct AgendaSidebar: View {
    @Bindable var model: AppModel
    @Environment(\.isRenderingPreview) private var rendering

    var body: some View {
        VStack(spacing: 0) {
            List(selection: rendering ? .constant(nil) : $model.selection) {
                ForEach(model.agendas) { agenda in
                    AgendaSidebarRow(agenda: agenda, run: model.isRunning(agenda.id) ? model.run : nil)
                        .tag(agenda.id)
                        .previewSelection(model.selection == agenda.id, rendering: rendering)
                        .contextMenu {
                            Button("Delete", role: .destructive) { model.deleteAgenda(agenda.id) }
                                .disabled(model.isRunning(agenda.id))
                        }
                }
            }
            .listStyle(.sidebar)
            Divider()
            HStack {
                Button {
                    model.addAgenda()
                } label: {
                    Label("New Agenda", systemImage: "plus")
                }
                .buttonStyle(.borderless)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }
}

struct AgendaSidebarRow: View {
    let agenda: Agenda
    let run: Run?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // One weight across hover and selection: the sidebar would otherwise draw the
            // selected row heavier, which widens it.
            Text(agenda.name.isEmpty ? "Untitled" : agenda.name)
                .fontWeight(.regular)
                .lineLimit(1)
            if let run {
                Ticking { now in
                    let state = ClockEngine.state(for: run, at: now)
                    HStack(spacing: 5) {
                        Circle().fill(ClockColors.running).frame(width: 7, height: 7)
                        Text(runningText(state)).monospacedDigit()
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            } else {
                Text(agenda.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }

    private func runningText(_ state: ClockState) -> String {
        if state.isOvertime { return "Running · \(state.primaryText) over" }
        if state.isPaused { return "Paused · \(TimeFormat.countdown(state.remaining)) left" }
        return "Running · \(TimeFormat.countdown(state.remaining)) left"
    }
}

/// An agenda that is not running: its name, Start, the end rule, the sections, and one-line entry.
struct AgendaEditor: View {
    let model: AppModel
    @Binding var agenda: Agenda
    let start: () -> Void

    @State private var line = ""
    @State private var problems: [String] = []

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    TextField("Name", text: $agenda.name, prompt: Text("Agenda name"))
                        .labelsHidden()
                        .font(.title2)
                        .textFieldStyle(.plain)
                    Spacer()
                    Button(action: start) {
                        Label("Start", systemImage: "play.fill")
                            .padding(.horizontal, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!model.canStart(agenda.id))
                    .help(startHelp)
                }
                if model.run != nil {
                    Text("“\(model.run?.agenda.name ?? "")” is running. End it to start this one.")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Ends") {
                Picker("End rule", selection: $agenda.endRule) {
                    Text("Set by length").tag(EndRule.setByLength)
                    Text("Fixed end time").tag(EndRule.fixedEnd)
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
                switch agenda.endRule {
                case .setByLength:
                    LabeledContent("Length", value: TimeFormat.minutes(agenda.totalMinutes))
                    Text("Ends when its sections add up. A run can pause, and +1 min makes it longer.")
                        .font(.callout).foregroundStyle(.secondary)
                case .fixedEnd:
                    DatePicker("Ends at", selection: endTime, displayedComponents: .hourAndMinute)
                    Text("Ends on the wall clock, so there is no pause. A late start or a long section squeezes the sections left to fit. The sections plan \(TimeFormat.minutes(agenda.totalMinutes)).")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }

            Section {
                ForEach($agenda.sections) { $section in
                    SectionRow(
                        section: $section,
                        canMoveUp: section.id != agenda.sections.first?.id,
                        canMoveDown: section.id != agenda.sections.last?.id,
                        move: { move(section.id, by: $0) },
                        delete: { agenda.sections.removeAll { $0.id == section.id } })
                }
                .onMove { agenda.sections.move(fromOffsets: $0, toOffset: $1) }
                Button {
                    agenda.sections.append(AgendaSection(name: "Section \(agenda.sections.count + 1)", minutes: 5))
                } label: {
                    Label("Add Section", systemImage: "plus")
                }
                .buttonStyle(.borderless)
            } header: {
                Text("Sections")
            }

            Section {
                HStack {
                    TextField("One line", text: $line, prompt: Text("5 intro, 5 context, 20 demo, 10 q&a"))
                        .labelsHidden()
                        .onSubmit(applyLine)
                    Button("Replace Sections", action: applyLine)
                        .disabled(line.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                ForEach(problems, id: \.self) { problem in
                    Label(problem, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Type the agenda in one line")
            } footer: {
                Text("Minutes then a name, separated by commas. 90s and 1h work too.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { line = AgendaParser.format(agenda.sections) }
        .onChange(of: agenda.id) { line = AgendaParser.format(agenda.sections); problems = [] }
    }

    private var startHelp: String {
        if model.run != nil { return "Another agenda is running." }
        if !agenda.canStart { return "Add a section with some minutes first." }
        return "Start this agenda now."
    }

    private var endTime: Binding<Date> {
        Binding {
            Calendar.current.date(bySettingHour: agenda.fixedEndTime.hour, minute: agenda.fixedEndTime.minute, second: 0, of: Date()) ?? Date()
        } set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            agenda.fixedEndTime = ClockTime(hour: parts.hour ?? 0, minute: parts.minute ?? 0)
        }
    }

    private func move(_ id: AgendaSection.ID, by offset: Int) {
        guard let from = agenda.sections.firstIndex(where: { $0.id == id }) else { return }
        let to = from + offset
        guard agenda.sections.indices.contains(to) else { return }
        agenda.sections.swapAt(from, to)
    }

    private func applyLine() {
        let result = AgendaParser.parse(line)
        problems = result.problems
        if !result.sections.isEmpty {
            agenda.sections = result.sections
        }
    }
}

/// One editable section: its name, its minutes, and buttons to move or delete it.
struct SectionRow: View {
    @Binding var section: AgendaSection
    let canMoveUp: Bool
    let canMoveDown: Bool
    let move: (Int) -> Void
    let delete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            TextField("Name", text: $section.name, prompt: Text("Section name"))
                .labelsHidden()
                .textFieldStyle(.plain)
            TextField("Minutes", value: $section.minutes, format: .number.precision(.fractionLength(0...1)))
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .frame(width: 48)
                .monospacedDigit()
            Stepper("Minutes", value: $section.minutes, in: 0.5...600, step: 1)
                .labelsHidden()
            Text("min").foregroundStyle(.secondary)
            HStack(spacing: 2) {
                Button { move(-1) } label: { Image(systemName: "chevron.up") }
                    .disabled(!canMoveUp)
                    .help("Move up")
                Button { move(1) } label: { Image(systemName: "chevron.down") }
                    .disabled(!canMoveDown)
                    .help("Move down")
                Button(role: .destructive, action: delete) { Image(systemName: "minus.circle") }
                    .help("Delete section")
            }
            .buttonStyle(.borderless)
        }
    }
}
