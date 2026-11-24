import Foundation
import Network

/// The phone clock's HTTP server: an `NWListener` on the local network with a small
/// hand-written HTTP handler. It serves the page, the state, commands, and an event stream.
///
/// It listens only between `start` and `stop`. It does not advertise itself over Bonjour.
@MainActor
public final class PhoneServer {
    public enum ServerError: Error, Equatable {
        case failed(String)
    }

    /// The access token every request needs. Changing it closes the open event streams, so a
    /// page with the old link stops getting updates and shows that the link no longer works.
    public var token: String {
        didSet { if token != oldValue { closeStreams() } }
    }

    public private(set) var port: UInt16?
    public var isListening: Bool { port != nil }
    /// Called when the listener stops on its own, such as when the network goes away.
    public var onStop: ((String?) -> Void)?

    private weak var host: PhoneClockHost?
    private var listener: NWListener?
    private var streams: [ObjectIdentifier: NWConnection] = [:]
    private var keepAlive: Timer?
    private let queue = DispatchQueue(label: "meeting-agenda-clock.phone-server")

    public init(token: String, host: PhoneClockHost) {
        self.token = token
        self.host = host
    }

    /// Starts listening on `port`, or if that port is taken, on one the system picks. Returns the
    /// port it listens on. `loopbackOnly` listens on 127.0.0.1 only, for tests.
    public func start(port: UInt16, loopbackOnly: Bool = false) async throws -> UInt16 {
        stop()
        do {
            return try await listen(on: port, loopbackOnly: loopbackOnly)
        } catch {
            guard port != 0 else { throw error }
            return try await listen(on: 0, loopbackOnly: loopbackOnly)
        }
    }

    public func stop() {
        keepAlive?.invalidate()
        keepAlive = nil
        listener?.stateUpdateHandler = nil
        listener?.cancel()
        listener = nil
        port = nil
        closeStreams()
    }

    /// Sends the current state to every open event stream. Call it whenever the run or the
    /// agendas change.
    public func broadcast() {
        guard !streams.isEmpty, let host else { return }
        let event = serverSentEvent(host.phoneState(at: Date()).json())
        for connection in streams.values {
            connection.send(content: event, completion: .contentProcessed { _ in })
        }
    }

    public var openStreamCount: Int { streams.count }

    // MARK: - Listening

    private func listen(on port: UInt16, loopbackOnly: Bool) async throws -> UInt16 {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        let requested = NWEndpoint.Port(rawValue: port) ?? .any
        let listener: NWListener
        do {
            if loopbackOnly {
                parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: requested)
                listener = try NWListener(using: parameters)
            } else {
                listener = try NWListener(using: parameters, on: requested)
            }
        } catch {
            throw ServerError.failed(String(describing: error))
        }
        listener.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in self?.accept(connection) }
        }
        let ready = ReadySignal()
        listener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                ready.finish(.success(listener.port?.rawValue ?? 0))
            case .failed(let error), .waiting(let error):
                ready.finish(.failure(ServerError.failed(String(describing: error))))
                listener.cancel()
                Task { @MainActor in self?.listenerStopped(listener, reason: String(describing: error)) }
            case .cancelled:
                ready.finish(.failure(ServerError.failed("cancelled")))
            default:
                break
            }
        }
        self.listener = listener
        listener.start(queue: queue)
        let actual = try await ready.value()
        self.port = actual
        keepAlive = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sendKeepAlive() }
        }
        return actual
    }

    private func listenerStopped(_ stopped: NWListener, reason: String) {
        guard stopped === listener, port != nil else { return }
        stop()
        onStop?(reason)
    }

    // MARK: - Connections

    private func accept(_ connection: NWConnection) {
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                Task { @MainActor in self?.streams[ObjectIdentifier(connection)] = nil }
            default:
                break
            }
        }
        connection.start(queue: queue)
        Self.receive(on: connection, buffer: Data()) { [weak self] request in
            Task { @MainActor in self?.handle(request, on: connection) }
        }
    }

    /// Reads until a whole request has arrived, then calls `done` with it, or with nil for a
    /// request that cannot be read.
    nonisolated private static func receive(
        on connection: NWConnection, buffer: Data, done: @escaping @Sendable (HTTPRequest?) -> Void
    ) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { data, _, isComplete, error in
            var buffer = buffer
            if let data { buffer.append(data) }
            switch HTTPRequest.parse(buffer) {
            case .complete(let request):
                done(request)
            case .invalid:
                done(nil)
            case .incomplete:
                if isComplete || error != nil {
                    connection.cancel()
                } else {
                    receive(on: connection, buffer: buffer, done: done)
                }
            }
        }
    }

    private func handle(_ request: HTTPRequest?, on connection: NWConnection) {
        guard let request, let host else {
            send(.text(400, "Bad request."), on: connection)
            return
        }
        let response = PhoneRoutes.respond(to: request, token: token, host: host)
        guard response.isEventStream else {
            send(response, on: connection)
            return
        }
        // The headers, then the state now. Later states follow from `broadcast`.
        streams[ObjectIdentifier(connection)] = connection
        var opening = response.serialized()
        opening.append(Data("retry: 2000\n\n".utf8))
        opening.append(serverSentEvent(host.phoneState(at: Date()).json()))
        connection.send(content: opening, completion: .contentProcessed { _ in })
    }

    private func send(_ response: HTTPResponse, on connection: NWConnection) {
        connection.send(content: response.serialized(), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func sendKeepAlive() {
        let ping = Data(": keep-alive\n\n".utf8)
        for connection in streams.values {
            connection.send(content: ping, completion: .contentProcessed { _ in })
        }
    }

    private func closeStreams() {
        for connection in streams.values { connection.cancel() }
        streams.removeAll()
    }
}

/// A one-time result the listener's state handler hands to `listen`.
private final class ReadySignal: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<UInt16, Error>?
    private var continuation: CheckedContinuation<UInt16, Error>?

    func finish(_ value: Result<UInt16, Error>) {
        lock.lock()
        guard result == nil else { lock.unlock(); return }
        result = value
        let waiting = continuation
        continuation = nil
        lock.unlock()
        waiting?.resume(with: value)
    }

    func value() async throws -> UInt16 {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            if let result {
                lock.unlock()
                continuation.resume(with: result)
            } else {
                self.continuation = continuation
                lock.unlock()
            }
        }
    }
}
