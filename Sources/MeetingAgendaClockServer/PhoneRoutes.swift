import Foundation
import MeetingAgendaClockCore

/// What the page shows: the run as a schedule, or with none, the agendas to start.
public struct PhoneState: Codable, Sendable, Equatable {
    public struct AgendaItem: Codable, Sendable, Equatable {
        public var id: String
        public var name: String
        public var summary: String
        public var canStart: Bool

        public init(id: String, name: String, summary: String, canStart: Bool) {
            self.id = id
            self.name = name
            self.summary = summary
            self.canStart = canStart
        }
    }

    public var run: ScheduleSnapshot?
    public var agendas: [AgendaItem]

    public init(run: ScheduleSnapshot?, agendas: [AgendaItem]) {
        self.run = run
        self.agendas = agendas
    }

    /// The state for `run` (if any) and `agendas` at `now`. Only one run exists at a time, so an
    /// agenda can start only when there is none.
    public static func make(run: Run?, agendas: [Agenda], at now: Date) -> PhoneState {
        PhoneState(
            run: run.map { ScheduleSnapshot.make($0, at: now) },
            agendas: agendas.map {
                AgendaItem(id: $0.id.uuidString, name: $0.name, summary: $0.summary, canStart: run == nil && $0.canStart)
            })
    }

    public func json() -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(self)) ?? Data("{}".utf8)
    }
}

/// A command from the page. Each goes through the same code path as the Mac's own controls.
public enum PhoneCommand: Equatable, Sendable {
    case start(Agenda.ID)
    case run(RunEvent.Kind)
    case end

    /// Reads `{"command": "nextSection"}`, or `{"command": "start", "agendaID": "…"}`.
    public static func decode(_ body: Data) -> PhoneCommand? {
        guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let name = object["command"] as? String
        else { return nil }
        switch name {
        case "start":
            return (object["agendaID"] as? String).flatMap(UUID.init(uuidString:)).map(PhoneCommand.start)
        case "end":
            return .end
        case "nextSection", "previousSection", "addMinute", "pause", "resume", "restartSection":
            return RunEvent.Kind(rawValue: name).map(PhoneCommand.run)
        default:
            return nil
        }
    }
}

/// The app side of the phone clock: what to show, and how to carry out a command.
@MainActor
public protocol PhoneClockHost: AnyObject {
    func phoneState(at now: Date) -> PhoneState
    /// Carries out `command` as the Mac's own control would, and says whether it did anything.
    func perform(_ command: PhoneCommand) -> Bool
}

/// The routes. Every request needs the access token, as `?t=` in the URL.
///
/// - `GET /` the page.
/// - `GET /state` the state as JSON.
/// - `GET /events` Server-Sent Events: the state now, then again whenever it changes.
/// - `POST /command` a command as JSON. Answers with the state after it, or 409 if it did nothing.
public enum PhoneRoutes {
    @MainActor
    public static func respond(to request: HTTPRequest, token: String, host: PhoneClockHost, now: Date = Date()) -> HTTPResponse {
        guard tokensMatch(request.query["t"], token) else {
            return .text(403, "This link does not work. Open the current link from the Mac.")
        }
        switch (request.method, request.path) {
        case ("GET", "/"), ("GET", "/index.html"):
            return HTTPResponse(
                status: 200, contentType: "text/html; charset=utf-8", body: Data(PhonePage.html().utf8),
                extraHeaders: [("Content-Security-Policy", PhonePage.contentSecurityPolicy)])
        case ("GET", "/state"):
            return json(host.phoneState(at: now))
        case ("GET", "/events"):
            return HTTPResponse(status: 200, contentType: "text/event-stream", isEventStream: true)
        case ("POST", "/command"):
            guard let command = PhoneCommand.decode(request.body) else { return .text(400, "Unknown command.") }
            let changed = host.perform(command)
            var response = json(host.phoneState(at: Date()))
            if !changed { response.status = 409 }
            return response
        case (_, "/"), (_, "/state"), (_, "/events"), (_, "/command"):
            return .text(405, "Method not allowed.")
        default:
            return .text(404, "Not found.")
        }
    }

    static func json(_ state: PhoneState) -> HTTPResponse {
        HTTPResponse(status: 200, contentType: "application/json", body: state.json())
    }

    /// Compares in time that does not depend on where the strings differ.
    static func tokensMatch(_ given: String?, _ token: String) -> Bool {
        guard let given, !token.isEmpty else { return false }
        let a = Array(given.utf8), b = Array(token.utf8)
        guard a.count == b.count else { return false }
        var difference: UInt8 = 0
        for i in 0..<a.count { difference |= a[i] ^ b[i] }
        return difference == 0
    }
}

/// The access token: 128 random bits as 32 hex digits.
public enum PhoneToken {
    public static func make() -> String {
        var generator = SystemRandomNumberGenerator()
        return (0..<16).map { _ in String(format: "%02x", UInt8.random(in: 0...255, using: &generator)) }.joined()
    }
}
