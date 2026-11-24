import Foundation

/// How times are written on screen.
public enum TimeFormat {
    /// A countdown, rounded up so it reads 0:01 until the last second is gone:
    /// "36:00", "4:05", "1:02:03".
    public static func countdown(_ seconds: TimeInterval) -> String {
        clock(Int(max(0, seconds).rounded(.up)))
    }

    /// Time past the end, rounded down, with a plus: "+1:20".
    public static func overtime(_ seconds: TimeInterval) -> String {
        "+" + clock(Int(max(0, seconds).rounded(.down)))
    }

    /// A signed difference from the plan, for "2:00 over plan". Whole seconds, rounded to nearest.
    public static func duration(_ seconds: TimeInterval) -> String {
        clock(Int(abs(seconds).rounded()))
    }

    static func clock(_ total: Int) -> String {
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// Minutes as the sidebar writes them: "40 min", "2.5 min".
    public static func minutes(_ value: Double) -> String {
        "\(number(value)) min"
    }

    /// A number of minutes without a unit: "5", "2.5".
    public static func number(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded == rounded.rounded() { return String(Int(rounded)) }
        return String(format: "%.1f", rounded)
    }

    /// A time of day without AM or PM, as the clock window writes it: "10:40", "9:05".
    public static func clockTime(_ time: ClockTime, twentyFourHour: Bool = false) -> String {
        let hour = twentyFourHour ? time.hour : (time.hour % 12 == 0 ? 12 : time.hour % 12)
        return String(format: "%d:%02d", hour, time.minute)
    }

    /// The time of day of `date`, without AM or PM.
    public static func clockTime(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return clockTime(ClockTime(hour: parts.hour ?? 0, minute: parts.minute ?? 0))
    }
}
