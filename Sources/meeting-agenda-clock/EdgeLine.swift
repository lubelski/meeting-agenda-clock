import AppKit
import MeetingAgendaClockCore
import SwiftUI

/// The edge line experiment: a 2 pt segmented line along the bottom edge of the main screen
/// while a run is going.
///
/// It is a borderless panel that clicks pass through, above other windows, on every Space and
/// over full-screen apps. It is meant to be seen by people watching a shared screen, so it does
/// nothing to hide from screen capture.
@MainActor
final class EdgeLineController {
    static let thickness: CGFloat = 2

    private var panel: NSPanel?
    private var hosting: NSHostingView<EdgeLineView>?
    private var screenObserver: NSObjectProtocol?

    func update(run: Run?, enabled: Bool) {
        guard enabled, let run else {
            hide()
            return
        }
        show(run)
    }

    private func show(_ run: Run) {
        if let hosting {
            hosting.rootView = EdgeLineView(run: run)
            place()
            return
        }
        let panel = NSPanel(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        // Clicks go to whatever is under the line.
        panel.ignoresMouseEvents = true
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        // Above the Dock and ordinary windows.
        panel.level = .statusBar
        // On every Space, over full-screen apps, and left out of Mission Control and Command-Tab.
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        let hosting = NSHostingView(rootView: EdgeLineView(run: run))
        hosting.sizingOptions = []
        panel.contentView = hosting
        self.panel = panel
        self.hosting = hosting
        place()
        // Never takes focus: a borderless, non-activating panel that ignores the mouse.
        panel.orderFrontRegardless()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.place() }
        }
    }

    /// Along the bottom edge of the main screen, the one with the menu bar.
    private func place() {
        guard let panel, let screen = NSScreen.screens.first else { return }
        let frame = screen.frame
        panel.setFrame(
            NSRect(x: frame.minX, y: frame.minY, width: frame.width, height: Self.thickness),
            display: true)
    }

    private func hide() {
        panel?.orderOut(nil)
        panel = nil
        hosting = nil
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
    }
}

/// The line itself: segments with 6 pt gaps, a faint track, and a fill that grows with time.
/// No blinking and no ticking: the fill moves a fraction of a point at a time.
struct EdgeLineView: View {
    let run: Run

    var body: some View {
        Ticking(paused: run.isPaused) { now in
            EdgeLineStrip(state: ClockEngine.state(for: run, at: now))
        }
    }
}

struct EdgeLineStrip: View {
    let state: ClockState

    var body: some View {
        SegmentBar(
            state: state, height: EdgeLineController.thickness, gap: 6, trackOpacity: 0.22,
            fill: .accentColor, track: .white, cornerRadius: 0)
            .frame(maxHeight: .infinity, alignment: .bottom)
    }
}
