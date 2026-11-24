import Foundation
import Observation
#if SPARKLE
import Sparkle
#endif

// The one seam for Sparkle. Every Sparkle reference in the app is in this file, behind
// `#if SPARKLE`, which `Package.swift` sets for the Developer ID build only. An App Store
// build (`MEETING_AGENDA_CLOCK_APP_STORE=1`) compiles the stand-in below, which is never
// available, so no update UI shows.

/// Keeps the app up to date.
///
/// Only a release build updates itself. `scripts/release.sh` writes the feed address and the
/// public signing key into Info.plist. A build without them, such as one from
/// `scripts/bundle.sh` alone, has no updater, so a development copy is never replaced.
@MainActor
@Observable
final class AppUpdater {
    /// Whether this build can update itself.
    let isAvailable: Bool

    /// Whether the Info.plist names a feed and a public key, which only a release has.
    static func hasFeed(_ info: [String: Any]?) -> Bool {
        guard let info,
              let feed = info["SUFeedURL"] as? String, !feed.isEmpty,
              let key = info["SUPublicEDKey"] as? String, !key.isEmpty
        else { return false }
        return true
    }

    #if SPARKLE
    @ObservationIgnored private let controller: SPUStandardUpdaterController?

    init(info: [String: Any]? = Bundle.main.infoDictionary) {
        guard Self.hasFeed(info) else {
            isAvailable = false
            controller = nil
            return
        }
        isAvailable = true
        // The app is sandboxed. Sparkle reaches the network through its Downloader service and
        // installs through its Installer service, which Info.plist turns on
        // (SUEnableDownloaderService, SUEnableInstallerLauncherService), and the entitlements
        // let the app look up (Resources/meeting-agenda-clock-sparkle.entitlements).
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    }

    /// False while a check is already running.
    var canCheck: Bool { controller?.updater.canCheckForUpdates ?? false }

    /// Whether Sparkle looks for, downloads, and installs updates without asking.
    var updatesAutomatically: Bool {
        get {
            guard let updater = controller?.updater else { return false }
            return updater.automaticallyChecksForUpdates && updater.automaticallyDownloadsUpdates
        }
        set {
            controller?.updater.automaticallyChecksForUpdates = newValue
            controller?.updater.automaticallyDownloadsUpdates = newValue
        }
    }

    /// Checks now and shows Sparkle's own windows with the result.
    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }
    #else
    /// A build without Sparkle, such as one for the App Store, which updates through the store.
    init(info: [String: Any]? = Bundle.main.infoDictionary) {
        isAvailable = false
    }

    var canCheck: Bool { false }
    var updatesAutomatically: Bool {
        get { false }
        set {}
    }

    func checkForUpdates() {}
    #endif

    /// A build with no feed, for previews.
    static func unavailable() -> AppUpdater {
        AppUpdater(info: nil)
    }
}
