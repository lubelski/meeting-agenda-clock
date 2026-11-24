import Foundation

/// An HTTP/1.1 request, as much of one as the phone clock needs.
public struct HTTPRequest: Sendable, Equatable {
    public var method: String
    public var path: String
    public var query: [String: String]
    public var headers: [String: String]
    public var body: Data

    public init(method: String, path: String, query: [String: String] = [:], headers: [String: String] = [:], body: Data = Data()) {
        self.method = method
        self.path = path
        self.query = query
        self.headers = headers
        self.body = body
    }

    /// The largest request read. The page sends only small JSON commands.
    public static let maximumSize = 64 * 1024

    public enum Parse: Equatable, Sendable {
        /// More bytes are needed.
        case incomplete
        case complete(HTTPRequest)
        case invalid
    }

    /// Reads a request from the bytes received so far.
    public static func parse(_ data: Data) -> Parse {
        guard let headerEnd = data.firstRange(of: Data("\r\n\r\n".utf8)) else {
            return data.count > maximumSize ? .invalid : .incomplete
        }
        guard let head = String(data: data[data.startIndex..<headerEnd.lowerBound], encoding: .utf8) else { return .invalid }
        var lines = head.components(separatedBy: "\r\n")
        let requestLine = lines.removeFirst().split(separator: " ", omittingEmptySubsequences: true)
        guard requestLine.count == 3, requestLine[2].hasPrefix("HTTP/1.") else { return .invalid }
        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { return .invalid }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            headers[name] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let length = headers["content-length"].flatMap(Int.init) ?? 0
        guard length >= 0, length <= maximumSize else { return .invalid }
        let bodyStart = headerEnd.upperBound
        guard data.count - (bodyStart - data.startIndex) >= length else { return .incomplete }
        let body = Data(data[bodyStart..<(bodyStart + length)])

        let target = String(requestLine[1])
        guard let components = URLComponents(string: target) else { return .invalid }
        var query: [String: String] = [:]
        for item in components.queryItems ?? [] {
            query[item.name] = item.value ?? ""
        }
        return .complete(HTTPRequest(
            method: String(requestLine[0]).uppercased(), path: components.path.isEmpty ? "/" : components.path,
            query: query, headers: headers, body: body))
    }
}

/// What the server sends back: a whole response, or the start of an event stream that it keeps open.
public struct HTTPResponse: Sendable, Equatable {
    public var status: Int
    public var contentType: String
    public var body: Data
    public var extraHeaders: [(String, String)]
    /// True for `/events`: the server sends the headers, keeps the connection, and writes
    /// events to it as the run changes.
    public var isEventStream: Bool

    public init(status: Int, contentType: String = "text/plain; charset=utf-8", body: Data = Data(),
                extraHeaders: [(String, String)] = [], isEventStream: Bool = false) {
        self.status = status
        self.contentType = contentType
        self.body = body
        self.extraHeaders = extraHeaders
        self.isEventStream = isEventStream
    }

    public static func == (a: HTTPResponse, b: HTTPResponse) -> Bool {
        a.status == b.status && a.contentType == b.contentType && a.body == b.body && a.isEventStream == b.isEventStream
            && a.extraHeaders.map { "\($0.0)=\($0.1)" } == b.extraHeaders.map { "\($0.0)=\($0.1)" }
    }

    public static func text(_ status: Int, _ text: String) -> HTTPResponse {
        HTTPResponse(status: status, body: Data((text + "\n").utf8))
    }

    static func reason(_ status: Int) -> String {
        switch status {
        case 200: "OK"
        case 400: "Bad Request"
        case 403: "Forbidden"
        case 404: "Not Found"
        case 405: "Method Not Allowed"
        case 409: "Conflict"
        default: "Error"
        }
    }

    /// The bytes on the wire. An event stream has no length and stays open.
    public func serialized() -> Data {
        var head = "HTTP/1.1 \(status) \(Self.reason(status))\r\n"
        head += "Content-Type: \(contentType)\r\n"
        head += "Cache-Control: no-store\r\n"
        head += "Referrer-Policy: no-referrer\r\n"
        head += "X-Content-Type-Options: nosniff\r\n"
        for (name, value) in extraHeaders { head += "\(name): \(value)\r\n" }
        if isEventStream {
            head += "Connection: keep-alive\r\n\r\n"
            return Data(head.utf8)
        }
        head += "Content-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        return Data(head.utf8) + body
    }
}

/// One Server-Sent Event carrying `data`.
public func serverSentEvent(_ data: Data) -> Data {
    let text = String(decoding: data, as: UTF8.self)
    let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map { "data: \($0)" }
    return Data((lines.joined(separator: "\n") + "\n\n").utf8)
}
