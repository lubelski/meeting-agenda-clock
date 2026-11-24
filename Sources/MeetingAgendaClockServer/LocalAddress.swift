import Darwin
import Foundation
import SystemConfiguration

/// The Mac's addresses on the local network, for the phone link. Reading them sends nothing on
/// the network.
public enum LocalAddress {
    /// The IPv4 address of the primary network interface, such as Wi-Fi, or of the first other
    /// interface that is up, if the primary one has none.
    public static func primaryIPv4() -> String? {
        let addresses = interfaceIPv4Addresses()
        if let primary = primaryInterface(), let address = addresses.first(where: { $0.interface == primary }) {
            return address.address
        }
        return addresses.first(where: { $0.interface.hasPrefix("en") })?.address ?? addresses.first?.address
    }

    /// The Mac's Bonjour name with `.local`, such as `studio-mac.local`.
    public static func localHostName() -> String? {
        guard let name = SCDynamicStoreCopyLocalHostName(nil) as String?, !name.isEmpty else { return nil }
        return name + ".local"
    }

    /// The URL for `host` and `port` with the token.
    public static func url(host: String, port: UInt16, token: String) -> String {
        "http://\(host):\(port)/?t=\(token)"
    }

    private static func primaryInterface() -> String? {
        guard let store = SCDynamicStoreCreate(nil, "meeting-agenda-clock" as CFString, nil, nil),
              let global = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any]
        else { return nil }
        return global["PrimaryInterface"] as? String
    }

    private static func interfaceIPv4Addresses() -> [(interface: String, address: String)] {
        var first: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&first) == 0, let first else { return [] }
        defer { freeifaddrs(first) }
        var result: [(String, String)] = []
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let entry = pointer.pointee
            let flags = Int32(entry.ifa_flags)
            guard let address = entry.ifa_addr, address.pointee.sa_family == UInt8(AF_INET),
                  flags & IFF_UP != 0, flags & IFF_RUNNING != 0, flags & IFF_LOOPBACK == 0
            else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let text = String(decoding: host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            // Skip link-local addresses, which a phone on Wi-Fi cannot reach reliably.
            guard !text.hasPrefix("169.254.") else { continue }
            result.append((String(cString: entry.ifa_name), text))
        }
        return result
    }
}
