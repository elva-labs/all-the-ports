import Foundation

/// One listening TCP socket, as reported by `lsof`.
public struct PortEntry: Identifiable, Hashable, Sendable {
    public let port: Int
    public let pid: Int32
    public let processName: String
    /// Bind address with wildcards resolved per IP version ("0.0.0.0" / "::").
    public let address: String
    /// "IPv4", "IPv6", or "" when lsof did not report a type.
    public let ipVersion: String
    public let user: String

    public var id: String { "\(pid):\(port)" }

    /// True when the socket is bound to all interfaces and therefore
    /// reachable from the local network, not just this machine.
    public var isExposed: Bool { address == "0.0.0.0" || address == "::" || address == "*" }

    public init(port: Int, pid: Int32, processName: String, address: String, ipVersion: String, user: String) {
        self.port = port
        self.pid = pid
        self.processName = processName
        self.address = address
        self.ipVersion = ipVersion
        self.user = user
    }
}
