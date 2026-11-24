import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import MeetingAgendaClockCore
import MeetingAgendaClockServer
import Observation
import SwiftUI

/// The phone clock experiment's app side: starts the server while the experiment is on, stops
/// it when it goes off, and keeps the port and the access token in the preferences so a
/// bookmarked link keeps working.
@MainActor
@Observable
final class PhoneClockController {
    static let portKey = "PhoneClockPort"
    static let tokenKey = "PhoneClockToken"

    private(set) var port: UInt16?
    private(set) var token: String
    private(set) var problem: String?
    private(set) var ipv4: String?
    private(set) var hostName: String?
    var isListening: Bool { port != nil }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var server: PhoneServer?
    @ObservationIgnored private weak var host: PhoneClockHost?
    @ObservationIgnored private var starting: Task<Void, Never>?

    init(defaults: UserDefaults, host: PhoneClockHost?) {
        self.defaults = defaults
        self.host = host
        if let saved = defaults.string(forKey: Self.tokenKey), !saved.isEmpty {
            token = saved
        } else {
            token = PhoneToken.make()
            defaults.set(token, forKey: Self.tokenKey)
        }
    }

    /// A controller that shows fixed values and never listens, for `--render-previews`.
    static func preview(port: UInt16, token: String, ipv4: String, hostName: String) -> PhoneClockController {
        let controller = PhoneClockController(defaults: UserDefaults(suiteName: "preview-\(UUID().uuidString)")!, host: nil)
        controller.port = port
        controller.token = token
        controller.ipv4 = ipv4
        controller.hostName = hostName
        return controller
    }

    /// The link the QR code holds: the Mac's local IPv4 address.
    var url: String? {
        guard let port, let ipv4 else { return nil }
        return LocalAddress.url(host: ipv4, port: port, token: token)
    }

    /// The same link by the Mac's `.local` name.
    var hostURL: String? {
        guard let port, let hostName else { return nil }
        return LocalAddress.url(host: hostName, port: port, token: token)
    }

    /// Starts or stops the server to match the experiment switch.
    func update(enabled: Bool) {
        if enabled {
            guard server == nil, let host else { return }
            let server = PhoneServer(token: token, host: host)
            server.onStop = { [weak self] reason in
                self?.port = nil
                self?.problem = reason.map { "Stopped listening: \($0)" }
            }
            self.server = server
            starting = Task { await start(server) }
        } else {
            starting?.cancel()
            starting = nil
            server?.stop()
            server = nil
            port = nil
            problem = nil
        }
    }

    private func start(_ server: PhoneServer) async {
        do {
            let actual = try await server.start(port: Self.chosenPort(defaults))
            guard self.server === server else { server.stop(); return }
            // A taken port falls back to another, which is kept from now on.
            defaults.set(Int(actual), forKey: Self.portKey)
            port = actual
            problem = nil
            refreshAddresses()
        } catch {
            guard self.server === server else { return }
            port = nil
            problem = "Could not listen: \(error)"
        }
    }

    /// The saved port, or on the first start a new one, which is saved.
    static func chosenPort(_ defaults: UserDefaults) -> UInt16 {
        let saved = defaults.integer(forKey: portKey)
        if (1024...65535).contains(saved) { return UInt16(saved) }
        let port = UInt16.random(in: 50000...59999)
        defaults.set(Int(port), forKey: portKey)
        return port
    }

    /// Replaces the token. The old link stops working at once, and pages open with it say so.
    func newLink() {
        token = PhoneToken.make()
        defaults.set(token, forKey: Self.tokenKey)
        server?.token = token
    }

    /// Reads the Mac's address and name again, as the network may have changed.
    func refreshAddresses() {
        guard server != nil else { return }
        ipv4 = LocalAddress.primaryIPv4()
        hostName = LocalAddress.localHostName()
    }

    /// Sends the run's state to open pages.
    func broadcast() {
        server?.broadcast()
    }
}

/// Settings, Phone: the link as a QR code and as text, whether the server is listening, and
/// New Link. Shows only while the phone clock experiment is on.
struct PhoneSettingsView: View {
    let phone: PhoneClockController

    var body: some View {
        Form {
            Section {
                HStack(alignment: .top, spacing: 20) {
                    QRCodeView(text: phone.url)
                        .frame(width: 168, height: 168)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Scan with the phone’s camera, or type the link into its browser. The phone must be on the same Wi-Fi as this Mac.")
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Anyone with the link on the same Wi-Fi can control the run.")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 4)
            }
            Section {
                LabeledContent("Status") {
                    HStack(spacing: 6) {
                        Circle().fill(phone.isListening ? ClockColors.running : Color.secondary).frame(width: 8, height: 8)
                        Text(statusText)
                    }
                }
                LabeledContent("Link") {
                    Text(phone.url ?? "None yet").textSelection(.enabled).monospaced().multilineTextAlignment(.trailing)
                }
                if let hostURL = phone.hostURL {
                    LabeledContent("By name") {
                        Text(hostURL).textSelection(.enabled).monospaced().multilineTextAlignment(.trailing)
                    }
                }
                HStack {
                    Text("A new link stops the old one at once.").foregroundStyle(.secondary)
                    Spacer()
                    Button("Copy Link") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(phone.url ?? "", forType: .string)
                    }
                    .disabled(phone.url == nil)
                    Button("New Link") { phone.newLink() }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { phone.refreshAddresses() }
    }

    private var statusText: String {
        if let port = phone.port {
            return phone.ipv4 == nil ? "Listening on port \(port), but this Mac has no network address" : "Listening on port \(port)"
        }
        return phone.problem ?? "Starting…"
    }
}

/// A QR code for `text`, drawn with CoreImage's generator, square pixels kept sharp.
struct QRCodeView: View {
    let text: String?

    var body: some View {
        if let text, let image = Self.image(for: text) {
            Image(nsImage: image)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .padding(10)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 10))
                .accessibilityLabel("QR code for the phone link")
        } else {
            RoundedRectangle(cornerRadius: 10).fill(.quaternary)
                .overlay(Text("No link yet").foregroundStyle(.secondary))
        }
    }

    static func image(for text: String) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage,
              let cgImage = CIContext().createCGImage(output, from: output.extent)
        else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: output.extent.width, height: output.extent.height))
    }
}
