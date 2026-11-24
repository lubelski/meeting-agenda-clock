# meeting-agenda-clock

Read `README.md` first for what the app is and how to build it.

## Product rules

- Agenda, Section, Run are the only objects. A plain countdown or an exam is an agenda with one
  section. Do not add a second object type for it.
- An agenda ends "set by length" (the sum of its sections) or at a "fixed end time" (a wall-clock
  time). Only one run exists at a time.
- Clock state is computed from (agenda, run events, now) by `ClockEngine` in the core target.
  Never keep a ticking counter: sleep and lag must not drift the clock. Timers only redraw.
- The default is schedule-driven: the display shows where you should be by the plan, with no input.
- Pause exists only for set-by-length agendas. A fixed-end agenda has no Pause.
- A fixed-end agenda started late or running behind squeezes the remaining sections in proportion
  to fit the time left.
- "+1 min" extends the current section. Set by length: the total grows. Fixed end: the later
  sections squeeze (on the last section, the end moves).
- After 0:00 the clock counts up as overtime ("+1:20") in the overtime color. The app never
  makes a sound.
- All timing logic lives in `MeetingAgendaClockCore` with tests. The app target has no timing rules.
- Agendas persist as JSON (`agendas.json`, `run.json`) in the data folder. `--data-folder <path>`
  points elsewhere. Use it, or `--render-previews`, for every check, never the owner's real data.
- Experiments are switches in Settings, off by default, backed by the `Experiment` enum. Edge
  line and Phone clock over Wi-Fi are built. The others say "Not built yet." and do nothing.
- The edge line is meant to be seen by screen-share viewers. Never set `sharingType = .none` or
  hide it from capture.
- Settings: Debugging is always last, Experiments just above it. Keep font weight constant across
  hover and selection.
- Target the current macOS only. SwiftUI first, AppKit only where needed (the edge line panel,
  window levels). No third-party dependencies unless truly needed.
- The App Sandbox entitlement stays on, so the App Store stays possible. A new capability needs
  its entitlement in `Resources/meeting-agenda-clock.entitlements`.
- Use placeholder names in fixtures and samples ("Q4 platform review", "Weekly demo",
  "Practice exam"). No real names or emails.

## Working here

- The owner works on this Mac. Do not launch the app in a way that opens a window, takes focus,
  or adds a login item. Use `--render-previews <folder>` for evidence, and look at the PNGs.
- `scripts/bundle.sh` builds `build/meeting-agenda-clock.app` and installs nothing. It signs
  with `MEETING_AGENDA_CLOCK_SIGNING_IDENTITY`, else a Developer ID, else a
  `meeting-agenda-clock development` certificate, else ad hoc. Do not create certificates.
- Run `swift build` and `swift test` before committing.

## Updates and the App Store

- The Developer ID build updates itself with Sparkle. The Mac App Store does not allow Sparkle,
  so every Sparkle reference stays behind one seam: `Sources/meeting-agenda-clock/AppUpdater.swift`,
  inside `#if SPARKLE`. No other file imports Sparkle or uses its types. Views ask
  `AppUpdater.isAvailable` and show no update UI when it is false.
- `Package.swift` adds the Sparkle package and defines `SPARKLE` unless
  `MEETING_AGENDA_CLOCK_APP_STORE=1`. Build that variant with its own scratch folder:
  `MEETING_AGENDA_CLOCK_APP_STORE=1 swift build --scratch-path .build-app-store`, or
  `MEETING_AGENDA_CLOCK_APP_STORE=1 scripts/bundle.sh`, which fails if the binary links Sparkle.
  Build both ways after touching updates.
- The app is sandboxed, so Sparkle runs through its XPC services. Info.plist sets
  `SUEnableInstallerLauncherService` and `SUEnableDownloaderService` (the app has no network
  entitlement of its own), and `Resources/meeting-agenda-clock-sparkle.entitlements` adds the
  mach-lookup exceptions `<bundle id>-spks` and `<bundle id>-spki`. The App Store variant signs
  with `Resources/meeting-agenda-clock.entitlements`, which has none of these. Sign Sparkle's
  helpers one by one, never with `--deep`.
- Only a build from `scripts/release.sh` has a feed URL and public key, so only it updates.
  `scripts/release.sh --check` and `--dry-run` exist; run a real release only when the owner asks.
  Do not generate Sparkle keys or touch the Keychain.

## Phone clock over Wi-Fi

- `MeetingAgendaClockServer` holds the server (`NWListener` with a hand-written HTTP handler),
  the routes, and the page. No UI, no third-party code. The app target only wires it up
  (`PhoneClockController`) and draws Settings, Phone.
- Nothing listens while the experiment is off. No Bonjour advertising yet.
- Every request needs the token (`?t=`), or gets 403. The port and token persist in the
  preferences; New Link replaces the token and closes open event streams.
- The page is one self-contained HTML document: inline CSS and JS, no external resources, no
  `confirm()`, neutral white fill and the overtime color, no blue.
- Do not port timing rules to JavaScript. The page draws from `ScheduleSnapshot` (core), which
  the server sends over Server-Sent Events, and corrects for the clock difference.
- Phone commands go through `AppModel.perform`, `start`, and `endRun`, the same methods as the
  Mac's controls.
- Both entitlements files have `com.apple.security.network.server`. Listening for and accepting
  TCP connections does not need the Local Network privilege (TN3179), so there is no prompt.
