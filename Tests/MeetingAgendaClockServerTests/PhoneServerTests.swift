import Foundation
import Testing
import MeetingAgendaClockCore
@testable import MeetingAgendaClockServer

/// A stand-in for the app: the sample agendas and a run, changed only through `perform`, as the
/// app's own controls change it.
@MainActor
final class StandInHost: PhoneClockHost {
    var agendas = SampleAgendas.all
    var run: Run?
    var server: PhoneServer?

    func phoneState(at now: Date) -> PhoneState {
        PhoneState.make(run: run, agendas: agendas, at: now)
    }

    func perform(_ command: PhoneCommand) -> Bool {
        defer { server?.broadcast() }
        switch command {
        case .start(let id):
            guard run == nil, let agenda = agendas.first(where: { $0.id == id }) else { return false }
            run = Run.start(agenda, at: Date())
            return true
        case .run(let kind):
            guard var current = run, current.record(kind, at: Date()) else { return false }
            run = current
            return true
        case .end:
            guard run != nil else { return false }
            run = nil
            return true
        }
    }
}

@Suite struct HTTPParsingTests {
    @Test func readsARequestWithAQueryAndBody() {
        let raw = "POST /command?t=abc HTTP/1.1\r\nHost: x\r\nContent-Length: 2\r\n\r\n{}"
        guard case .complete(let request) = HTTPRequest.parse(Data(raw.utf8)) else {
            Issue.record("not parsed")
            return
        }
        #expect(request.method == "POST")
        #expect(request.path == "/command")
        #expect(request.query["t"] == "abc")
        #expect(request.body == Data("{}".utf8))
    }

    @Test func waitsForTheRestOfTheBody() {
        let raw = "POST /command HTTP/1.1\r\nContent-Length: 10\r\n\r\n{}"
        #expect(HTTPRequest.parse(Data(raw.utf8)) == .incomplete)
        #expect(HTTPRequest.parse(Data("GET / HTTP/1.1\r\n".utf8)) == .incomplete)
    }

    @Test func rejectsGarbage() {
        #expect(HTTPRequest.parse(Data("hello\r\n\r\n".utf8)) == .invalid)
    }

    @Test func commandsDecode() {
        #expect(PhoneCommand.decode(Data(#"{"command":"nextSection"}"#.utf8)) == .run(.nextSection))
        #expect(PhoneCommand.decode(Data(#"{"command":"end"}"#.utf8)) == .end)
        let id = SampleAgendas.weeklyDemo.id
        #expect(PhoneCommand.decode(Data(#"{"command":"start","agendaID":"\#(id.uuidString)"}"#.utf8)) == .start(id))
        #expect(PhoneCommand.decode(Data(#"{"command":"format disk"}"#.utf8)) == nil)
    }

    @Test func eventsSplitLines() {
        #expect(String(decoding: serverSentEvent(Data("a\nb".utf8)), as: UTF8.self) == "data: a\ndata: b\n\n")
    }
}

@Suite struct PhoneRoutesTests {
    @MainActor @Test func everyRouteNeedsTheToken() {
        let host = StandInHost()
        for path in ["/", "/state", "/events"] {
            #expect(PhoneRoutes.respond(to: HTTPRequest(method: "GET", path: path), token: "secret", host: host).status == 403)
            #expect(PhoneRoutes.respond(to: HTTPRequest(method: "GET", path: path, query: ["t": "wrong"]), token: "secret", host: host).status == 403)
        }
        let post = HTTPRequest(method: "POST", path: "/command", body: Data(#"{"command":"end"}"#.utf8))
        #expect(PhoneRoutes.respond(to: post, token: "secret", host: host).status == 403)
        #expect(PhoneRoutes.respond(to: HTTPRequest(method: "GET", path: "/", query: ["t": ""]), token: "", host: host).status == 403)
    }

    @MainActor @Test func aRefusedCommandIsAConflict() {
        let host = StandInHost()
        let post = HTTPRequest(method: "POST", path: "/command", query: ["t": "s"], body: Data(#"{"command":"nextSection"}"#.utf8))
        #expect(PhoneRoutes.respond(to: post, token: "s", host: host).status == 409)
    }

    @Test func pageIsSelfContained() {
        let html = PhonePage.html()
        #expect(!html.contains("http://") && !html.contains("https://"))
        #expect(!html.contains("<link"))
        #expect(!html.contains("src="))
        #expect(!html.contains("confirm("))
        #expect(html.contains("To keep this screen on, set Auto-Lock to Never."))
    }

    @Test func tokensAreRandomHex() {
        let a = PhoneToken.make(), b = PhoneToken.make()
        #expect(a.count == 32 && a != b)
        let isHex = a.allSatisfy { $0.isHexDigit }
        #expect(isHex)
    }
}

/// The real server on loopback, on a port the system picks, reached with URLSession.
@Suite(.serialized) struct PhoneServerLoopbackTests {
    @MainActor
    func withServer(_ body: (StandInHost, URL) async throws -> Void) async throws {
        let host = StandInHost()
        let server = PhoneServer(token: "test-token", host: host)
        host.server = server
        let port = try await server.start(port: 0, loopbackOnly: true)
        #expect(port != 0)
        defer { server.stop() }
        try await body(host, URL(string: "http://127.0.0.1:\(port)")!)
        server.stop()
        #expect(!server.isListening)
    }

    static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 5
        return URLSession(configuration: configuration)
    }()

    func get(_ url: URL) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await Self.session.data(from: url)
        return (data, response as! HTTPURLResponse)
    }

    func post(_ url: URL, _ json: String) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(json.utf8)
        let (data, response) = try await Self.session.data(for: request)
        return (data, response as! HTTPURLResponse)
    }

    @MainActor @Test func withoutTheTokenIs403() async throws {
        try await withServer { _, base in
            let noToken = try await get(base.appending(path: "state"))
            #expect(noToken.1.statusCode == 403)
            let wrongToken = try await get(URL(string: base.absoluteString + "/?t=nope")!)
            #expect(wrongToken.1.statusCode == 403)
        }
    }

    @MainActor @Test func servesThePageWithTheToken() async throws {
        try await withServer { _, base in
            let (data, response) = try await get(URL(string: base.absoluteString + "/?t=test-token")!)
            #expect(response.statusCode == 200)
            #expect(response.value(forHTTPHeaderField: "Content-Type") == "text/html; charset=utf-8")
            #expect(String(decoding: data, as: UTF8.self).contains("<title>Agenda Clock</title>"))
        }
    }

    @MainActor @Test func stateIsTheSnapshotOfTheRun() async throws {
        try await withServer { host, base in
            let started = Date(timeIntervalSince1970: (Date().timeIntervalSince1970 - 240).rounded())
            host.run = Run.start(SampleAgendas.weeklyDemo, at: started)
            let (data, response) = try await get(URL(string: base.absoluteString + "/state?t=test-token")!)
            #expect(response.statusCode == 200)
            let state = try JSONDecoder().decode(PhoneState.self, from: data)
            let run = try #require(state.run)
            #expect(run.agendaName == "Weekly demo")
            #expect(run.end == started.addingTimeInterval(40 * 60).timeIntervalSince1970 * 1000)
            #expect(run.sections.map(\.name) == ["Intro", "Context", "Demo", "Q&A"])
            #expect(run.sections[2].start == started.addingTimeInterval(10 * 60).timeIntervalSince1970 * 1000)
            #expect(state.agendas.count == 3)
            #expect(state.agendas.allSatisfy { !$0.canStart })
        }
    }

    @MainActor @Test func aCommandChangesTheRun() async throws {
        try await withServer { host, base in
            let url = URL(string: base.absoluteString + "/command?t=test-token")!
            let id = SampleAgendas.weeklyDemo.id.uuidString
            let (_, started) = try await post(url, #"{"command":"start","agendaID":"\#(id)"}"#)
            #expect(started.statusCode == 200)
            #expect(host.run?.agenda.name == "Weekly demo")
            let (data, added) = try await post(url, #"{"command":"addMinute"}"#)
            #expect(added.statusCode == 200)
            #expect(host.run?.events.map(\.kind) == [.addMinute])
            let state = try JSONDecoder().decode(PhoneState.self, from: data)
            #expect(state.run?.sections[0].end == state.run.map { $0.sections[0].start + 6 * 60 * 1000 })
            let result2 = try await post(url, #"{"command":"end"}"#)
            #expect(result2.1.statusCode == 200)
            #expect(host.run == nil)
            let result3 = try await post(url, #"{"command":"end"}"#)
            #expect(result3.1.statusCode == 409)
        }
    }

    @MainActor @Test func eventsArriveOnTheStream() async throws {
        try await withServer { host, base in
            let events = URL(string: base.absoluteString + "/events?t=test-token")!
            let (bytes, response) = try await Self.session.bytes(from: events)
            #expect((response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type") == "text/event-stream")
            var lines = bytes.lines.makeAsyncIterator()
            func nextEvent() async throws -> PhoneState? {
                while let line = try await lines.next() {
                    if line.hasPrefix("data: ") {
                        return try JSONDecoder().decode(PhoneState.self, from: Data(line.dropFirst(6).utf8))
                    }
                }
                return nil
            }
            // The state now, with no run.
            let first = try await nextEvent()
            #expect(first?.run == nil)
            // A command from somewhere else reaches the stream.
            let id = SampleAgendas.practiceExam.id.uuidString
            _ = try await post(URL(string: base.absoluteString + "/command?t=test-token")!, #"{"command":"start","agendaID":"\#(id)"}"#)
            let second = try await nextEvent()
            #expect(second?.run?.agendaName == "Practice exam")
            #expect(host.server?.openStreamCount == 1)
        }
    }

    @MainActor @Test func aTakenPortFallsBackToAnother() async throws {
        let host = StandInHost()
        let first = PhoneServer(token: "a", host: host)
        let port = try await first.start(port: 0, loopbackOnly: true)
        defer { first.stop() }
        let second = PhoneServer(token: "b", host: host)
        let other = try await second.start(port: port, loopbackOnly: true)
        defer { second.stop() }
        #expect(other != port)
        #expect(other != 0)
    }
}
