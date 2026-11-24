import MeetingAgendaClockCore
import SwiftUI

enum WindowID {
    static let agendas = "agendas"
    static let clock = "clock"
}

/// The clock window, for the second display: dark, one huge countdown, and the section bar.
struct ClockWindowView: View {
    let model: AppModel

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let run = model.run {
                Ticking(paused: run.isPaused) { now in
                    ClockRoomView(state: ClockEngine.state(for: run, at: now))
                }
            } else {
                VStack(spacing: 8) {
                    Text("No agenda running")
                        .font(.system(size: 34, weight: .regular, design: .rounded))
                    Text("Start one from the menu bar or the Agendas window.")
                        .font(.title3)
                }
                .foregroundStyle(.secondary)
            }
        }
        .environment(\.colorScheme, .dark)
        .frame(minWidth: 480, minHeight: 300)
    }
}

/// The room-sized clock on black, also used for the clock window's previews.
struct ClockRoomView: View {
    let state: ClockState

    var body: some View {
        ZStack {
            Color.black
            LiveClockView(state: state, style: .room)
        }
        .environment(\.colorScheme, .dark)
    }
}
