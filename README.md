# meeting-agenda-clock

A clock for presenting remotely with a timed agenda, or taking a timed exam. Share one screen and
keep the timing on the other: a big countdown, the sections, and where you should be by now.

- **Agendas window**: plan agendas (sections with minutes, ended by their length or at a fixed
  time), type one in a line (`5 intro, 5 context, 20 demo, 10 q&a`), and start one. The running
  agenda's pane becomes the live view with its controls.
- **Clock window**: a dark window with one huge countdown, for the second display.
- **Menu bar item**: the run's state and controls, or a list of agendas to start.
- **Settings**: General, Experiments (Edge line and Phone clock over Wi-Fi are built so far),
  Debugging.
- **Phone clock over Wi-Fi** (an experiment): the Mac serves a small page on the local network
  that a phone opens in its browser to show the clock and control the run. Turn it on in
  Settings, Experiments, then scan the code in Settings, Phone.

## Build and run

Needs macOS 27 and Xcode.

```sh
swift build
swift test
scripts/bundle.sh            # builds build/meeting-agenda-clock.app, installs and launches nothing
open build/meeting-agenda-clock.app
```

A release build updates itself with Sparkle (`scripts/release.sh`, see the top of that file).
`MEETING_AGENDA_CLOCK_APP_STORE=1 scripts/bundle.sh` builds the variant for a future Mac App
Store submission, with no Sparkle in it.

Launch arguments:

- `--data-folder <path>` keeps agendas and the run in that folder instead of
  `~/Library/Application Support/meeting-agenda-clock/`. The bundled app is sandboxed, so there
  Application Support is inside `~/Library/Containers/dev.lubelski.meeting-agenda-clock/`, and a
  `--data-folder` outside the container cannot be written. Use the unbundled build for checks:

  ```sh
  .build/debug/meeting-agenda-clock --data-folder /tmp/meeting-agenda-clock-check
  ```

- `--render-previews <folder>` draws the key views offscreen to PNG files with sample data and
  exits. It shows no window and takes no focus:

  ```sh
  .build/debug/meeting-agenda-clock --render-previews /tmp/meeting-agenda-clock-previews
  ```
