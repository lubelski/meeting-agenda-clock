import AppKit
import MeetingAgendaClockCore
import SwiftUI

/// The menu bar item's menu. While a run is going it says where the run is and has its
/// controls. With none it lists the agendas to start.
struct MenuBarMenu: View {
    let model: AppModel
    let updater: AppUpdater
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @AppStorage(Experiment.phoneClock.key) private var phoneOn = false

    var body: some View {
        if let run = model.run, let state = model.state(at: model.now) {
            Text(run.agenda.name)
            Text(state.isOvertime ? "\(state.primaryText) over" : "\(TimeFormat.countdown(state.remaining)) left")
                .monospacedDigit()
            if let name = state.currentSectionName {
                Text(state.isOvertime ? name : "\(name) · \(TimeFormat.countdown(state.sectionRemaining)) left")
                    .monospacedDigit()
            }
            Divider()
            if !run.isFixedEnd {
                Button(run.isPaused ? "Resume" : "Pause") {
                    model.perform(run.isPaused ? .resume : .pause)
                }
            }
            Button("Next Section") { model.perform(.nextSection) }
                .disabled(!state.canGoToNextSection)
            Button("Previous Section") { model.perform(.previousSection) }
                .disabled(!state.canGoToPreviousSection)
            Button("Add 1 Minute") { model.perform(.addMinute) }
            Button("End Run") { model.endRun() }
            Divider()
        } else {
            Text("Start an Agenda")
            ForEach(model.agendas) { agenda in
                Button("\(agenda.name) (\(agenda.summary))") {
                    if model.start(agenda.id), model.opensClockWindowOnStart {
                        open(WindowID.clock)
                    }
                }
                .disabled(!agenda.canStart)
            }
            Divider()
        }
        Button("Show Clock Window") { open(WindowID.clock) }
        Button("Agendas…") { open(WindowID.agendas) }
        if updater.isAvailable {
            Button("Check for Updates…") {
                NSApp.activate()
                updater.checkForUpdates()
            }
            .disabled(!updater.canCheck)
        }
        if phoneOn {
            Button("Show Phone Link…") {
                UserDefaults.standard.set(SettingsSection.phone.rawValue, forKey: SettingsRootView.selectedSectionKey)
                NSApp.activate()
                openSettings()
            }
        }
        SettingsLink { Text("Settings…") }
            .keyboardShortcut(",")
        Divider()
        Button("Quit") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private func open(_ id: String) {
        // Coming from the menu bar, the app may not be active, and its window would open behind
        // the app in front. The person asked for the window, so bring the app forward.
        NSApp.activate()
        openWindow(id: id)
    }
}
