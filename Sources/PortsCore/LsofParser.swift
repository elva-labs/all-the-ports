import Foundation

/// Parses `lsof -nP -iTCP -sTCP:LISTEN -FpcLnPt` field output.
///
/// Field output (`-F`) is used instead of columnar output because command
/// names can contain spaces. Each line is a single-letter tag followed by a
/// value:
///   p  pid            (starts a process block)
///   c  command name
///   L  login name
///   f  file descriptor (starts a file block; resets per-file state)
///   t  file type ("IPv4" / "IPv6")
///   P  protocol
///   n  name, e.g. "*:3000", "127.0.0.1:8080", "[::1]:5000"
public enum LsofParser {

    /// Pure function: lsof stdout in, sorted entries out.
    ///
    /// Entries are deduplicated by pid:port (a process often holds both an
    /// IPv4 and an IPv6 socket for the same port). When duplicates differ in
    /// exposure, the all-interfaces bind wins so the UI never under-reports
    /// network exposure.
    public static func parse(_ output: String) -> [PortEntry] {
        var byKey: [String: PortEntry] = [:]

        var pid: Int32 = 0
        var command = ""
        var user = ""
        var fileType = ""

        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            let tag = line.first!
            let value = String(line.dropFirst())

            switch tag {
            case "p":
                pid = Int32(value) ?? 0
                command = ""
                user = ""
                fileType = ""
            case "c":
                command = value
            case "L":
                user = value
            case "f": // new file block — reset per-file state
                fileType = ""
            case "t":
                fileType = value
            case "n":
                guard pid > 0, let (address, port) = parseAddress(value, ipVersion: fileType) else { break }
                let entry = PortEntry(
                    port: port,
                    pid: pid,
                    processName: command.isEmpty ? "unknown" : command,
                    address: address,
                    ipVersion: fileType,
                    user: user
                )
                let key = entry.id
                if let existing = byKey[key] {
                    if entry.isExposed && !existing.isExposed { byKey[key] = entry }
                } else {
                    byKey[key] = entry
                }
            default:
                break
            }
        }

        return byKey.values.sorted { ($0.port, $0.pid) < ($1.port, $1.pid) }
    }

    /// Splits an lsof network name like "*:3000", "127.0.0.1:8080" or
    /// "[::1]:5000" into a display address and a port.
    ///
    /// Wildcard binds are resolved per IP version: "*" means 0.0.0.0 for an
    /// IPv4 socket and :: for an IPv6 socket.
    public static func parseAddress(_ name: String, ipVersion: String) -> (address: String, port: Int)? {
        guard let idx = name.lastIndex(of: ":") else { return nil }
        guard let port = Int(name[name.index(after: idx)...]), (1...65535).contains(port) else { return nil }

        var address = String(name[..<idx])
        if address.hasPrefix("["), address.hasSuffix("]") {
            address = String(address.dropFirst().dropLast())
        }
        if address == "*" {
            switch ipVersion {
            case "IPv4": address = "0.0.0.0"
            case "IPv6": address = "::"
            default: break
            }
        }
        return (address, port)
    }
}
