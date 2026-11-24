import AppKit
import MeetingAgendaClockCore

// `--render-previews <folder>` draws the key views to PNG files and exits, without starting the
// app: no windows, no menu bar item, no focus.
let arguments = CommandLine.arguments
if let index = arguments.firstIndex(of: PreviewRenderer.argument) {
    guard index + 1 < arguments.count else {
        print("\(PreviewRenderer.argument) needs an output folder.")
        exit(2)
    }
    let folder = URL(filePath: (arguments[index + 1] as NSString).expandingTildeInPath, directoryHint: .isDirectory)
    MainActor.assumeIsolated { PreviewRenderer.render(to: folder) }
    exit(0)
}

MeetingAgendaClockApp.main()
