import AppKit
import MeetingAgendaClockCore
import ServiceManagement
import SwiftUI

/// The sections of the Settings window, in sidebar order.
///
/// Debugging is always last and Experiments just above it. A new section goes above
/// Experiments, with its view in `SettingsRootView.detail`.
enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    /// Only while the phone clock experiment is on.
    case phone
    case experiments
    case debugging

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .phone: "Phone"
        case .experiments: "Experiments"
        case .debugging: "Debugging"
        }
    }

    var symbolName: String {
        switch self {
        case .general: "gearshape"
        case .phone: "iphone"
        case .experiments: "flask"
        case .debugging: "ladybug"
        }
    }

    /// The sections in the sidebar. Phone shows only with its experiment on.
    static func visible(phoneOn: Bool) -> [SettingsSection] {
        allCases.filter { $0 != .phone || phoneOn }
    }
}

/// The Settings window's content: a fixed-width sidebar of sections, and the section beside it.
struct SettingsRootView: View {
    static let sidebarWidth: CGFloat = 180
    static let size = CGSize(width: 720, height: 560)
    static let selectedSectionKey = "SettingsSelectedSection"

    let dataFolder: URL
    let updater: AppUpdater
    let phone: PhoneClockController?
    @AppStorage(Self.selectedSectionKey) private var storedSection: SettingsSection = .general
    @AppStorage(Experiment.phoneClock.key) private var phoneOn = false

    /// The section showing. A remembered Phone section with the experiment off shows Experiments,
    /// where its switch is.
    private var section: SettingsSection {
        get { storedSection == .phone && !phoneOn ? .experiments : storedSection }
        nonmutating set { storedSection = newValue }
    }
    @Environment(\.isRenderingPreview) private var rendering

    var body: some View {
        // A plain row rather than a split view, so the sidebar keeps its width: it cannot be
        // dragged or collapsed, and there is no sidebar button.
        HStack(spacing: 0) {
            List(selection: Binding<SettingsSection?>(
                get: { rendering ? nil : section },
                set: { if let new = $0 { section = new } }
            )) {
                ForEach(SettingsSection.visible(phoneOn: phoneOn)) { section in
                    // The sidebar draws the selected row's title heavier, which widens it. A
                    // weight on the title's own Text overrides that, so the row keeps one
                    // weight across hover and selection.
                    Label {
                        Text(section.title).fontWeight(.regular)
                    } icon: {
                        Image(systemName: section.symbolName)
                    }
                    .tag(section)
                    .previewSelection(self.section == section, rendering: rendering)
                }
            }
            .listStyle(.sidebar)
            .frame(width: Self.sidebarWidth)
            Divider()
            detail
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .standardTitleBar()
        // Turning the experiment off while its section shows lands on Experiments.
        .onChange(of: phoneOn) { _, on in
            if !on, storedSection == .phone { storedSection = .experiments }
        }
    }

    @ViewBuilder private var detail: some View {
        switch section {
        case .general: GeneralSettingsView(updater: updater)
        case .phone:
            if let phone {
                PhoneSettingsView(phone: phone)
            }
        case .experiments: ExperimentsSettingsView()
        case .debugging: DebuggingSettingsView(dataFolder: dataFolder)
        }
    }
}

struct GeneralSettingsView: View {
    let updater: AppUpdater
    /// Shows the Updates group as a release build would, for `--render-previews`.
    var showsUpdatesForPreview = false
    @State private var updatesAutomatically = false
    @AppStorage(GeneralPreference.openAtLoginKey) private var openAtLogin = false
    @AppStorage(GeneralPreference.defaultEndRuleKey) private var defaultEndRule: EndRule = .setByLength
    @AppStorage(GeneralPreference.openClockWindowOnStartKey)
    private var openClockWindow = GeneralPreference.openClockWindowOnStartDefault
    @State private var loginProblem: String?

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $openAtLogin) {
                    Text("Open at login")
                    if let loginProblem {
                        Text(loginProblem)
                    } else {
                        Text("The app starts when you log in, with its menu bar item.")
                    }
                }
                // Only the person flipping the switch registers or removes the login item.
                .onChange(of: openAtLogin) { _, on in applyOpenAtLogin(on) }
            }
            Section {
                Picker(selection: $defaultEndRule) {
                    ForEach(EndRule.allCases, id: \.self) { rule in
                        Text(rule.title).tag(rule)
                    }
                } label: {
                    Text("New agendas end")
                    Text("Set by length ends when the sections add up. A fixed end time ends on the wall clock.")
                }
                Toggle(isOn: $openClockWindow) {
                    Text("Open the clock window when an agenda starts")
                    Text("The big countdown, for the display you are not sharing.")
                }
            }
            // Only a release build with Sparkle updates itself. An App Store build updates
            // through the store and shows nothing here.
            if updater.isAvailable || showsUpdatesForPreview {
                Section {
                    Toggle(isOn: Binding(
                        get: { updatesAutomatically },
                        set: {
                            updatesAutomatically = $0
                            updater.updatesAutomatically = $0
                        })) {
                        Text("Update automatically")
                        Text("Checks about once a day, downloads a newer release, and installs it when the app quits. Check for Updates is also in the app menu and the menu bar menu.")
                    }
                    HStack {
                        Spacer()
                        Button("Check for Updates…") { updater.checkForUpdates() }
                            .disabled(!updater.canCheck)
                    }
                } header: {
                    Text("Updates")
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { updatesAutomatically = showsUpdatesForPreview || updater.updatesAutomatically }
    }

    private func applyOpenAtLogin(_ on: Bool) {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginProblem = SMAppService.mainApp.status == .requiresApproval
                ? "Allow it in System Settings, General, Login Items."
                : nil
        } catch {
            loginProblem = "Could not change the login item: \(error.localizedDescription)"
        }
    }
}

/// Features being tried, each a switch, off until the owner turns it on. See `Experiment`.
struct ExperimentsSettingsView: View {
    var body: some View {
        Form {
            Section {
                ForEach(Experiment.allCases) { experiment in
                    ExperimentToggle(experiment: experiment)
                }
            } header: {
                Text("Features being tried. They may change or go.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .textCase(nil)
            }
        }
        .formStyle(.grouped)
    }
}

struct ExperimentToggle: View {
    let experiment: Experiment
    @AppStorage private var isOn: Bool

    init(experiment: Experiment) {
        self.experiment = experiment
        _isOn = AppStorage(wrappedValue: false, experiment.key)
    }

    var body: some View {
        Toggle(isOn: $isOn) {
            Text(experiment.title)
            Text(experiment.description)
        }
    }
}

struct DebuggingSettingsView: View {
    let dataFolder: URL
    private let build = BuildInfo.current()

    var body: some View {
        Form {
            Section("Data") {
                LabeledContent("Data folder") {
                    Text(dataFolder.path)
                        .textSelection(.enabled)
                        .multilineTextAlignment(.trailing)
                }
                HStack {
                    Spacer()
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([dataFolder])
                    }
                }
            }
            Section("Build") {
                LabeledContent("Version", value: "\(build.version) (\(build.build))")
                LabeledContent("Commit", value: build.commit)
                LabeledContent("Signing") {
                    Text(build.signing).multilineTextAlignment(.trailing)
                }
            }
        }
        .formStyle(.grouped)
    }
}
