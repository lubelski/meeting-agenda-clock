import Foundation

/// A feature being tried, behind a switch in Settings, Experiments. Every experiment is off
/// until the owner turns it on, and may change or go. Kept in the app's preferences.
public enum Experiment: String, CaseIterable, Sendable, Identifiable {
    /// A thin segmented line along the bottom of the main screen. See `EdgeLineController`.
    case edgeLine
    case menuBarSegmentsAndMinutes
    case menuBarRing
    case floatingPanel
    case paceByTaps
    case countQuestions
    /// The Mac serves a page that a phone on the same Wi-Fi opens to show the clock and control
    /// the run. See `PhoneServer` and `PhoneClockController`.
    case phoneClock

    public var id: String { rawValue }

    public var key: String {
        switch self {
        case .edgeLine: "ExperimentEdgeLine"
        case .menuBarSegmentsAndMinutes: "ExperimentMenuBarSegmentsAndMinutes"
        case .menuBarRing: "ExperimentMenuBarRing"
        case .floatingPanel: "ExperimentFloatingPanel"
        case .paceByTaps: "ExperimentPaceByTaps"
        case .countQuestions: "ExperimentCountQuestions"
        case .phoneClock: "ExperimentPhoneClock"
        }
    }

    /// Whether turning it on does anything yet.
    public var isBuilt: Bool { self == .edgeLine || self == .phoneClock }

    public var title: String {
        switch self {
        case .edgeLine: "Edge line"
        case .menuBarSegmentsAndMinutes: "Menu bar segments and minutes"
        case .menuBarRing: "Menu bar ring"
        case .floatingPanel: "Floating panel"
        case .paceByTaps: "Pace by taps"
        case .countQuestions: "Count questions"
        case .phoneClock: "Phone clock over Wi-Fi"
        }
    }

    public var description: String {
        let text = switch self {
        case .edgeLine:
            "While an agenda runs, a thin line along the bottom of the main screen fills with the time, one segment per section. It shows over full-screen apps, and people watching your shared screen see it too."
        case .menuBarSegmentsAndMinutes:
            "The menu bar shows the minutes left and a small bar of the sections in place of the icon."
        case .menuBarRing:
            "The menu bar icon becomes a ring that fills as the agenda runs."
        case .floatingPanel:
            "A small panel that stays above other windows with the countdown and the current section, for when you have one display."
        case .paceByTaps:
            "Sections move on only when you choose Next Section, and the clock says how far ahead of or behind the plan you are."
        case .countQuestions:
            "For an exam, say how many questions it has, and the clock shows which question you should be on."
        case .phoneClock:
            "The Mac serves a page that a phone opens in its browser to show the clock and control the run. Anyone with the link on the same Wi-Fi can control the run."
        }
        return isBuilt ? text : text + " Not built yet."
    }

    public func isOn(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: key)
    }

    public func set(_ on: Bool, _ defaults: UserDefaults = .standard) {
        defaults.set(on, forKey: key)
    }
}

/// The General settings, as keys and defaults, so views and the app read them the same way.
public enum GeneralPreference {
    /// Whether the app opens at login. The switch registers or removes the login item when the
    /// owner flips it. Nothing else turns it on.
    public static let openAtLoginKey = "OpenAtLogin"
    /// The end rule a new agenda gets.
    public static let defaultEndRuleKey = "DefaultEndRule"
    /// Whether starting an agenda opens the clock window.
    public static let openClockWindowOnStartKey = "OpenClockWindowOnStart"
    public static let openClockWindowOnStartDefault = true

    public static func defaultEndRule(_ defaults: UserDefaults = .standard) -> EndRule {
        defaults.string(forKey: defaultEndRuleKey).flatMap(EndRule.init(rawValue:)) ?? .setByLength
    }

    public static func opensClockWindowOnStart(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: openClockWindowOnStartKey) as? Bool ?? openClockWindowOnStartDefault
    }
}
