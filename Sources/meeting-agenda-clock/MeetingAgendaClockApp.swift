import AppKit
import MeetingAgendaClockCore
import SwiftUI

/// The app's scenes: the Agendas window, the clock window, Settings, and the menu bar item.
/// Started from `main.swift`, which handles `--render-previews` first.
struct MeetingAgendaClockApp: App {
    @State private var model = AppModel.live()
    @State private var updater = AppUpdater()

    var body: some Scene {
        Window("Agendas", id: WindowID.agendas) {
            AgendasRootView(model: model)
                .frame(minWidth: 760, minHeight: 520)
        }
        .defaultSize(width: 900, height: 640)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(after: .appInfo) {
                if updater.isAvailable {
                    Button("Check for Updates…") { updater.checkForUpdates() }
                        .disabled(!updater.canCheck)
                }
            }
        }

        Window("Clock", id: WindowID.clock) {
            ClockWindowView(model: model)
        }
        .defaultSize(width: 960, height: 560)
        .windowStyle(.hiddenTitleBar)
        // Opens when asked for, not at launch.
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)

        Settings {
            SettingsRootView(dataFolder: model.store.folder, updater: updater)
        }

        MenuBarExtra {
            MenuBarMenu(model: model, updater: updater)
        } label: {
            Image(systemName: model.run == nil ? "clock" : "clock.fill")
                .accessibilityLabel("Meeting Agenda Clock")
        }
        .menuBarExtraStyle(.menu)
    }
}
