import Foundation

/// Reads a one-line agenda such as `5 intro, 5 context, 20 demo, 10 q&a` into sections.
///
/// Items are separated by commas, semicolons, or new lines. Each has a length at its start or
/// its end, in minutes unless it says otherwise (`90s`, `1h`, `1.5 h`, `5m`, `5 min`), and the
/// rest is the name. A name typed all in lower case is capitalized: `q&a` becomes `Q&A`.
public enum AgendaParser {
    public struct Result: Equatable, Sendable {
        public var sections: [AgendaSection]
        /// Items that could not be read, each with why.
        public var problems: [String]

        public var isEmpty: Bool { sections.isEmpty }
    }

    public static func parse(_ text: String) -> Result {
        var sections: [AgendaSection] = []
        var problems: [String] = []
        let items = text
            .split(whereSeparator: { $0 == "," || $0 == ";" || $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        for item in items {
            guard let (minutes, rawName) = split(item) else {
                problems.append("“\(item)” has no length in minutes.")
                continue
            }
            guard minutes > 0 else {
                problems.append("“\(item)” needs more than 0 minutes.")
                continue
            }
            let name = tidy(rawName)
            sections.append(AgendaSection(
                name: name.isEmpty ? "Section \(sections.count + 1)" : name,
                minutes: minutes))
        }
        return Result(sections: sections, problems: problems)
    }

    /// Writes sections back as one line, which `parse` reads back to the same sections.
    public static func format(_ sections: [AgendaSection]) -> String {
        sections.map { "\(TimeFormat.number($0.minutes)) \($0.name)" }.joined(separator: ", ")
    }

    // A length with an optional unit, such as "5", "2.5", "90s", "1 h", "10 min".
    private static let unit = #"(h|hr|hrs|hour|hours|m|min|mins|minute|minutes|s|sec|secs|second|seconds)?"#
    nonisolated(unsafe) private static let leading = try! Regex(#"^(\d+(?:\.\d+)?)\s*"# + unit + #"(?:\s+|$|[:\-–—]\s*)(.*)$"#)
        .ignoresCase()
    nonisolated(unsafe) private static let trailing = try! Regex(#"^(.*?)[\s:\-–—(]+(\d+(?:\.\d+)?)\s*"# + unit + #"\)?$"#)
        .ignoresCase()

    private static func split(_ item: String) -> (Double, String)? {
        if let match = try? leading.wholeMatch(in: item),
           let number = match.output[1].substring.flatMap({ Double($0) })
        {
            let unit = match.output[2].substring.map(String.init)
            let name = match.output[3].substring.map(String.init) ?? ""
            return (minutes(number, unit), name)
        }
        if let match = try? trailing.wholeMatch(in: item),
           let number = match.output[2].substring.flatMap({ Double($0) })
        {
            let unit = match.output[3].substring.map(String.init)
            let name = match.output[1].substring.map(String.init) ?? ""
            return (minutes(number, unit), name)
        }
        return nil
    }

    private static func minutes(_ number: Double, _ unit: String?) -> Double {
        switch unit?.lowercased().first {
        case "h": number * 60
        case "s": number / 60
        default: number
        }
    }

    private static func tidy(_ raw: String) -> String {
        let name = raw.trimmingCharacters(in: CharacterSet(charactersIn: " :-–—()"))
        guard name == name.lowercased() else { return name }
        return name.split(separator: " ", omittingEmptySubsequences: true).map { word in
            word.contains("&") ? word.uppercased() : word.prefix(1).uppercased() + word.dropFirst()
        }.joined(separator: " ")
    }
}
