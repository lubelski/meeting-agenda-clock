import AppKit
import MeetingAgendaClockCore
import SwiftUI

/// `--render-previews <folder>`: draws each key view offscreen with sample data, writes PNG
/// files, and exits. It never shows a window, never takes focus, and never reads or writes the
/// real data folder or preferences.
@MainActor
enum PreviewRenderer {
    static let argument = "--render-previews"

    static func render(to folder: URL) {
        let app = NSApplication.shared
        // No Dock icon, no menu bar, and no activation.
        app.setActivationPolicy(.prohibited)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            print("Could not create \(folder.path): \(error.localizedDescription)")
            exit(1)
        }

        let suite = "dev.lubelski.meeting-agenda-clock.preview"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let calendar = Calendar.current
        let ten = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: Date())!
        func at(_ minutes: Double) -> Date { ten.addingTimeInterval(minutes * 60) }
        let scratch = FileManager.default.temporaryDirectory
            .appending(path: "meeting-agenda-clock-preview-\(UUID().uuidString)", directoryHint: .isDirectory)
        let store = AgendaStore(folder: scratch)

        func model(run: Run?, selection: Agenda.ID) -> AppModel {
            let model = AppModel(store: store, defaults: defaults, agendas: SampleAgendas.all, run: run, persists: false)
            model.selection = selection
            return model
        }

        var written: [URL] = []
        func save(_ name: String, _ image: NSBitmapImageRep?) {
            guard let image, let data = image.representation(using: .png, properties: [:]) else {
                print("Could not render \(name)")
                return
            }
            let url = folder.appending(path: "\(name).png")
            do {
                try data.write(to: url)
                written.append(url)
            } catch {
                print("Could not write \(url.path): \(error.localizedDescription)")
            }
        }

        // The Agendas window, not running.
        let demo = SampleAgendas.weeklyDemo
        save("agendas-not-running", window(
            AgendasRootView(model: model(run: nil, selection: demo.id)),
            size: CGSize(width: 900, height: 820), now: at(0), defaults: defaults))

        // The Agendas window in a run, four minutes in: "Running · 36:00 left".
        var demoRun = Run.start(demo, at: ten)
        save("agendas-running", window(
            AgendasRootView(model: model(run: demoRun, selection: demo.id)),
            size: CGSize(width: 900, height: 760), now: at(4), defaults: defaults))

        // A fixed-end agenda started five minutes late, so its sections are squeezed.
        let review = SampleAgendas.q4PlatformReview
        var reviewAgenda = review
        reviewAgenda.fixedEndTime = ClockTime(hour: 11, minute: 0)
        let reviewRun = Run.start(reviewAgenda, at: at(5))
        save("agendas-running-fixed-end-started-late", window(
            AgendasRootView(model: model(run: reviewRun, selection: review.id)),
            size: CGSize(width: 900, height: 760), now: at(17), defaults: defaults))

        // The clock window early in a run, and in overtime.
        save("clock-early", image(
            ClockRoomView(state: ClockEngine.state(for: demoRun, at: at(2))),
            size: CGSize(width: 1280, height: 720)))
        save("clock-overtime", image(
            ClockRoomView(state: ClockEngine.state(for: demoRun, at: at(41 + 20.0 / 60))),
            size: CGSize(width: 1280, height: 720)))
        // A small clock window, to check the digits scale down.
        demoRun.record(.addMinute, at: at(12))
        save("clock-small-demo-section", image(
            ClockRoomView(state: ClockEngine.state(for: demoRun, at: at(13.5))),
            size: CGSize(width: 560, height: 320)))

        // Settings, each section.
        for section in SettingsSection.allCases {
            defaults.set(section.rawValue, forKey: "SettingsSelectedSection")
            save("settings-\(section.rawValue)", window(
                SettingsRootView(dataFolder: AppPaths.dataFolder(arguments: []), updater: .unavailable()),
                size: SettingsRootView.size, now: at(0), defaults: defaults))
        }

        // General as a release build shows it, with the Updates group.
        save("settings-general-release-build", window(
            GeneralSettingsView(updater: .unavailable(), showsUpdatesForPreview: true)
                .frame(width: SettingsRootView.size.width - SettingsRootView.sidebarWidth),
            size: CGSize(width: SettingsRootView.size.width - SettingsRootView.sidebarWidth, height: 400),
            now: at(0), defaults: defaults))

        // The edge line along the bottom of a stand-in screen, at its real 2 pt, and magnified.
        let lineState = ClockEngine.state(for: Run.start(demo, at: ten), at: at(12.5))
        save("edge-line-screen", image(
            ZStack(alignment: .bottom) {
                LinearGradient(colors: [Color(white: 0.32), Color(white: 0.16)], startPoint: .top, endPoint: .bottom)
                EdgeLineStrip(state: lineState).frame(height: EdgeLineController.thickness)
            },
            size: CGSize(width: 1440, height: 120)))
        save("edge-line-zoomed", image(
            ZStack(alignment: .bottom) {
                Color(white: 0.2)
                EdgeLineStrip(state: lineState).frame(height: EdgeLineController.thickness)
            },
            size: CGSize(width: 720, height: 12), scale: 6))

        for url in written { print(url.path) }
        try? FileManager.default.removeItem(at: scratch)
    }

    /// A view made of AppKit-backed controls (lists, forms, fields), drawn in a window that is
    /// never put on screen.
    private static func window(_ view: some View, size: CGSize, now: Date, defaults: UserDefaults) -> NSBitmapImageRep? {
        let root = view
            .environment(\.frozenNow, now)
            .environment(\.isRenderingPreview, true)
            .defaultAppStorage(defaults)
            .frame(width: size.width, height: size.height)
        let hosting = NSHostingView(rootView: root)
        hosting.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(
            contentRect: CGRect(origin: CGPoint(x: -20000, y: -20000), size: size),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = hosting
        // Give SwiftUI a moment to lay out and fill the lists. The window stays off screen.
        for _ in 0..<5 {
            hosting.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return nil }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        window.contentView = nil
        return rep
    }

    /// A pure SwiftUI view, drawn with `ImageRenderer`.
    private static func image(_ view: some View, size: CGSize, scale: CGFloat = 2) -> NSBitmapImageRep? {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
        renderer.scale = scale
        guard let cgImage = renderer.cgImage else { return nil }
        return NSBitmapImageRep(cgImage: cgImage)
    }
}
