import Foundation

/// Where the app keeps its data: `~/Library/Application Support/meeting-agenda-clock/`, or
/// the folder `--data-folder <path>` names. Under the App Sandbox, Application Support is the
/// app's container, so the real path is inside `~/Library/Containers/`.
public enum AppPaths {
    public static let folderName = "meeting-agenda-clock"
    public static let dataFolderArgument = "--data-folder"

    public static func dataFolder(arguments: [String] = CommandLine.arguments) -> URL {
        if let folder = dataFolderOverride(arguments: arguments) { return folder }
        return URL.applicationSupportDirectory.appending(path: folderName, directoryHint: .isDirectory)
    }

    public static func dataFolderOverride(arguments: [String]) -> URL? {
        guard let index = arguments.firstIndex(of: dataFolderArgument), index + 1 < arguments.count else { return nil }
        return URL(filePath: (arguments[index + 1] as NSString).expandingTildeInPath, directoryHint: .isDirectory)
    }
}

/// Reads and writes the agendas and the current run as JSON in one folder:
/// `agendas.json` and `run.json`. The run file exists only while a run is going, so a run
/// survives quitting and relaunching.
public struct AgendaStore: Sendable {
    public let folder: URL

    public init(folder: URL) {
        self.folder = folder
    }

    public var agendasFile: URL { folder.appending(path: "agendas.json") }
    public var runFile: URL { folder.appending(path: "run.json") }

    /// The saved agendas, or nil when nothing has been saved yet (a first launch).
    public func loadAgendas() throws -> [Agenda]? {
        guard FileManager.default.fileExists(atPath: agendasFile.path) else { return nil }
        let data = try Data(contentsOf: agendasFile)
        return try Self.decoder.decode(AgendaFile.self, from: data).agendas
    }

    public func save(_ agendas: [Agenda]) throws {
        try write(AgendaFile(agendas: agendas), to: agendasFile)
    }

    public func loadRun() throws -> Run? {
        guard FileManager.default.fileExists(atPath: runFile.path) else { return nil }
        return try Self.decoder.decode(Run.self, from: Data(contentsOf: runFile))
    }

    /// Saves the run, or removes the file when there is none.
    public func save(_ run: Run?) throws {
        guard let run else {
            if FileManager.default.fileExists(atPath: runFile.path) {
                try FileManager.default.removeItem(at: runFile)
            }
            return
        }
        try write(run, to: runFile)
    }

    private func write(_ value: some Encodable, to url: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Self.encoder.encode(value).write(to: url, options: .atomic)
    }

    /// The file's top level, with a version so the format can change later.
    struct AgendaFile: Codable {
        var version = 1
        var agendas: [Agenda]
    }

    static let dateStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.formatted(Self.dateStyle))
        }
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            if let date = try? Date(text, strategy: Self.dateStyle) {
                return date
            }
            if let date = try? Date(text, strategy: .iso8601) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not an ISO 8601 date: \(text)")
        }
        return decoder
    }()
}
