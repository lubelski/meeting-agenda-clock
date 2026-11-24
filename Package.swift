// swift-tools-version: 6.4
import Foundation
import PackageDescription

// The Developer ID build updates itself with Sparkle. The Mac App Store does not allow
// Sparkle, so `MEETING_AGENDA_CLOCK_APP_STORE=1` builds without it: no Sparkle package, no
// `SPARKLE` compile condition, so no Sparkle code, no framework in the bundle, and no update
// UI. Every Sparkle reference lives in `Sources/meeting-agenda-clock/AppUpdater.swift`, behind
// `#if SPARKLE`. Build the App Store variant with its own `--scratch-path`, so SwiftPM does not
// reuse the other build's manifest.
let appStore = ProcessInfo.processInfo.environment["MEETING_AGENDA_CLOCK_APP_STORE"] == "1"

let package = Package(
    name: "meeting-agenda-clock",
    platforms: [.macOS(.v27)],
    dependencies: appStore ? [] : [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.10.1"),
    ],
    targets: [
        // Pure logic: the object model, the timing rules, the one-line parser, and storage.
        // No UI. Every timing rule lives here and is tested.
        .target(name: "MeetingAgendaClockCore"),
        // The phone clock: a small HTTP server on the local network, its request handling, and
        // the page it serves. No UI, so it is tested without one.
        .target(name: "MeetingAgendaClockServer", dependencies: ["MeetingAgendaClockCore"]),
        .executableTarget(
            name: "meeting-agenda-clock",
            dependencies: ["MeetingAgendaClockCore", "MeetingAgendaClockServer"]
                + (appStore ? [] : [.product(name: "Sparkle", package: "Sparkle")]),
            swiftSettings: appStore ? [] : [.define("SPARKLE")]
        ),
        .testTarget(name: "MeetingAgendaClockCoreTests", dependencies: ["MeetingAgendaClockCore"]),
        .testTarget(
            name: "MeetingAgendaClockServerTests",
            dependencies: ["MeetingAgendaClockServer", "MeetingAgendaClockCore"]),
    ]
)
