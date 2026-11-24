#!/usr/bin/env bash
# Builds meeting-agenda-clock.app into ./build. It installs nothing and launches nothing.
#
# Environment, all optional:
#   MEETING_AGENDA_CLOCK_APP_STORE         1 builds without Sparkle, for a future Mac App Store
#                                          build: no Sparkle code, framework, or update UI. It
#                                          uses its own .build-app-store scratch folder.
#   MEETING_AGENDA_CLOCK_FEED_URL          The Sparkle feed. Set by scripts/release.sh, together
#   MEETING_AGENDA_CLOCK_PUBLIC_KEY        with the public key that updates are signed with. A
#                                          build without these two never updates itself.
#   MEETING_AGENDA_CLOCK_BUNDLE_DIR        The folder the app goes in. Defaults to build. Use
#                                          another to check a build while a copy from build runs.
#   MEETING_AGENDA_CLOCK_VERSION           The version to show, such as 1.2.0. Defaults to the
#                                          latest v* tag, or 0.1 without one.
#   MEETING_AGENDA_CLOCK_SIGNING_IDENTITY  The signing identity. See "Sign" below for the default.
set -euo pipefail
cd "$(dirname "$0")/.."

# Use full Xcode for SwiftUI without changing the global xcode-select setting.
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

APP_STORE=false
SWIFT_ARGS=(-c release --arch arm64)
if [[ "${MEETING_AGENDA_CLOCK_APP_STORE:-}" == "1" ]]; then
  APP_STORE=true
  # Its own scratch folder, so SwiftPM never reuses the Sparkle build's manifest.
  SWIFT_ARGS+=(--scratch-path .build-app-store)
fi
swift build "${SWIFT_ARGS[@]}"
BIN="$(swift build "${SWIFT_ARGS[@]}" --show-bin-path)/meeting-agenda-clock"

BUNDLE_DIR="${MEETING_AGENDA_CLOCK_BUNDLE_DIR:-build}"
mkdir -p "$BUNDLE_DIR"
APP="$BUNDLE_DIR/meeting-agenda-clock.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/meeting-agenda-clock"

# Sparkle, the updater, in the Developer ID build only. SwiftPM builds it next to the binary
# but does not know about app bundles, so copy it in and tell the binary where to find it.
if ! $APP_STORE; then
  mkdir -p "$APP/Contents/Frameworks"
  ditto "$(dirname "$BIN")/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
  install_name_tool -add_rpath @executable_path/../Frameworks "$APP/Contents/MacOS/meeting-agenda-clock"
elif otool -L "$APP/Contents/MacOS/meeting-agenda-clock" | grep -q Sparkle; then
  echo "error: the App Store build links Sparkle" >&2
  exit 1
fi

# SwiftPM writes the deployment target into the binary's SDK field. macOS reads that field
# to decide whether to run the app in a compatibility mode for older apps, so stamp the
# SDK the app was really built with.
MIN_OS=27.0
SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version)"
xcrun vtool -set-build-version macos "$MIN_OS" "$SDK_VERSION" -replace \
  -output "$APP/Contents/MacOS/meeting-agenda-clock" "$APP/Contents/MacOS/meeting-agenda-clock"
STAMPED="$(xcrun vtool -show-build "$APP/Contents/MacOS/meeting-agenda-clock" | awk '$1 == "sdk" { print $2 }')"
if [[ "$STAMPED" != "$SDK_VERSION" ]]; then
  echo "error: the binary is stamped with SDK '$STAMPED', expected '$SDK_VERSION'" >&2
  exit 1
fi

GIT_COMMIT="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
  GIT_COMMIT="$GIT_COMMIT-dirty"
fi
LATEST_TAG="$(git describe --tags --abbrev=0 --match 'v*' 2>/dev/null || true)"
VERSION="${MEETING_AGENDA_CLOCK_VERSION:-${LATEST_TAG#v}}"
VERSION="${VERSION:-0.1}"
BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null || echo 1)"

# The app is sandboxed, so Sparkle installs through its Installer XPC service and, having no
# network entitlement of its own, downloads through its Downloader XPC service. Both are
# turned on here. The feed and key come only from scripts/release.sh.
UPDATER_KEYS=""
ENTITLEMENTS=Resources/meeting-agenda-clock.entitlements
if ! $APP_STORE; then
  ENTITLEMENTS=Resources/meeting-agenda-clock-sparkle.entitlements
  UPDATER_KEYS="<key>SUEnableInstallerLauncherService</key><true/>
  <key>SUEnableDownloaderService</key><true/>"
  if [[ -n "${MEETING_AGENDA_CLOCK_FEED_URL:-}" && -n "${MEETING_AGENDA_CLOCK_PUBLIC_KEY:-}" ]]; then
    UPDATER_KEYS="$UPDATER_KEYS
  <key>SUFeedURL</key><string>$MEETING_AGENDA_CLOCK_FEED_URL</string>
  <key>SUPublicEDKey</key><string>$MEETING_AGENDA_CLOCK_PUBLIC_KEY</string>
  <key>SUEnableAutomaticChecks</key><true/>
  <key>SUAutomaticallyUpdate</key><true/>"
  fi
fi

# The app icon. actool compiles the Icon Composer file into Assets.car, which macOS draws
# with the system's glass, and AppIcon.icns, a flat copy for places that read only that.
# Info.plist names both below. scripts/render-icon.sh redraws the icon's artwork.
ICON_PLIST_DIR="$(mktemp -d)"
xcrun actool Resources/AppIcon.icon --compile "$APP/Contents/Resources" \
  --platform macosx --minimum-deployment-target "$MIN_OS" --app-icon AppIcon \
  --output-partial-info-plist "$ICON_PLIST_DIR/icon.plist" --errors --warnings \
  --output-format human-readable-text >/dev/null
rm -rf "$ICON_PLIST_DIR"
for f in Assets.car AppIcon.icns; do
  if [[ ! -f "$APP/Contents/Resources/$f" ]]; then
    echo "error: actool did not produce $f from Resources/AppIcon.icon" >&2
    exit 1
  fi
done

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>meeting-agenda-clock</string>
  <key>CFBundleDisplayName</key><string>meeting-agenda-clock</string>
  <key>CFBundleIdentifier</key><string>dev.lubelski.meeting-agenda-clock</string>
  <key>CFBundleExecutable</key><string>meeting-agenda-clock</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleIconName</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
  <key>MeetingAgendaClockGitCommit</key><string>$GIT_COMMIT</string>
  <key>LSMinimumSystemVersion</key><string>$MIN_OS</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSLocalNetworkUsageDescription</key><string>With the phone clock experiment on, a phone on the same Wi-Fi opens the clock in its browser.</string>
  $UPDATER_KEYS
</dict>
</plist>
PLIST

# Sign. The identity is the first of these that exists, as in mac-os-agent:
#   1. MEETING_AGENDA_CLOCK_SIGNING_IDENTITY, when it is set.
#   2. A Developer ID Application certificate in the keychain.
#   3. This Mac's self-signed "meeting-agenda-clock development" certificate, if the owner
#      made one. This script never makes one.
#   4. Ad hoc.
DEVELOPER_ID="$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Developer ID Application/ { print $2; exit }')"
if [[ -n "${MEETING_AGENDA_CLOCK_SIGNING_IDENTITY:-}" ]]; then
  IDENTITY="$MEETING_AGENDA_CLOCK_SIGNING_IDENTITY"
elif [[ -n "$DEVELOPER_ID" ]]; then
  IDENTITY="$DEVELOPER_ID"
elif security find-certificate -c "meeting-agenda-clock development" >/dev/null 2>&1; then
  IDENTITY="meeting-agenda-clock development"
else
  IDENTITY="-"
fi
SIGN=(codesign --force --sign "$IDENTITY")
if [[ "$IDENTITY" == *"Developer ID Application"* ]]; then
  # Notarization needs the hardened runtime and a secure timestamp.
  SIGN+=(--options runtime --timestamp)
fi
# Sparkle's helpers are signed one at a time, innermost first, as its documentation says, and
# never with --deep: the Downloader keeps its own entitlements.
if ! $APP_STORE; then
  SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
  "${SIGN[@]}" "$SPARKLE/Versions/B/XPCServices/Installer.xpc"
  "${SIGN[@]}" --preserve-metadata=entitlements "$SPARKLE/Versions/B/XPCServices/Downloader.xpc"
  "${SIGN[@]}" "$SPARKLE/Versions/B/Autoupdate"
  "${SIGN[@]}" "$SPARKLE/Versions/B/Updater.app"
  "${SIGN[@]}" "$SPARKLE"
fi
# The App Sandbox, plus Sparkle's mach-lookup exceptions in the Developer ID build.
"${SIGN[@]}" --entitlements "$ENTITLEMENTS" "$APP"
codesign --verify --deep --strict "$APP"
if [[ "$IDENTITY" == "-" ]]; then
  echo "Signed ad hoc."
else
  echo "Signed with \"$IDENTITY\""
fi
$APP_STORE && echo "App Store variant: no Sparkle."
echo "Built $APP, version $VERSION ($BUILD_NUMBER), commit $GIT_COMMIT"
