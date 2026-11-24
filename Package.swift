// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "meeting-agenda-clock",
    platforms: [.macOS(.v27)],
    targets: [
        // Pure logic: the object model, the timing rules, the one-line parser, and storage.
        // No UI. Every timing rule lives here and is tested.
        .target(name: "MeetingAgendaClockCore"),
        .executableTarget(name: "meeting-agenda-clock", dependencies: ["MeetingAgendaClockCore"]),
        .testTarget(name: "MeetingAgendaClockCoreTests", dependencies: ["MeetingAgendaClockCore"]),
    ]
)
