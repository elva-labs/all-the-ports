import AppKit
import Foundation

public enum PortServiceError: LocalizedError, Equatable {
    case lsofNotFound
    case lsofFailed(String)
    case timedOut
    case notListening
    case nothingOnPort(Int)
    case permissionDenied(String)
    case processGone
    case killFailed(String, Int32)

    public var errorDescription: String? {
        switch self {
        case .lsofNotFound:
            return "lsof was not found at /usr/sbin/lsof."
        case .lsofFailed(let detail):
            return "lsof failed: \(detail)"
        case .timedOut:
            return "Scanning ports took too long and was cancelled."
        case .notListening:
            return "That process is no longer holding a listening port. Refresh and try again."
        case .nothingOnPort(let port):
            return "Nothing is listening on port \(port)."
        case .permissionDenied(let name):
            return "Permission denied — \(name) is owned by another user."
        case .processGone:
            return "Process no longer exists."
        case .killFailed(let name, let code):
            return "Failed to terminate \(name) (errno \(code))."
        }
    }
}

public struct KillOutcome: Sendable {
    public let pid: Int32
    public let processName: String
    public let success: Bool
    public let message: String?
}

public enum PortService {

    // Absolute paths: apps launched from Finder get a minimal PATH, and a
    // bare name is "whatever is first on PATH".
    private static let lsofPath = "/usr/sbin/lsof"
    private static let lsofTimeout: TimeInterval = 5

    /// All TCP sockets currently in the LISTEN state.
    public static func listPorts() async throws -> [PortEntry] {
        let output = try await runLsof()
        return LsofParser.parse(output)
    }

    /// Send SIGTERM to `pid`, but only if it currently holds a listening
    /// socket. Re-resolving the live set here (instead of trusting the UI's
    /// possibly-stale list) means we never signal an arbitrary process, and it
    /// narrows the PID-reuse window. The residual sub-millisecond TOCTOU gap
    /// before kill(2) is irreducible.
    @discardableResult
    public static func kill(pid: Int32) async throws -> PortEntry {
        let listening = try await listPorts()
        guard let entry = listening.first(where: { $0.pid == pid }) else {
            throw PortServiceError.notListening
        }
        try sendSigterm(to: entry)
        return entry
    }

    /// Kill every process listening on `port`. With SO_REUSEPORT workers, or
    /// separate IPv4/IPv6 listeners from different processes, one port can
    /// have several owners — killing only the first and reporting success
    /// would be a lie, so all of them are signalled and reported individually.
    public static func killAll(onPort port: Int) async throws -> [KillOutcome] {
        let listening = try await listPorts()
        let matches = listening.filter { $0.port == port }
        guard !matches.isEmpty else { throw PortServiceError.nothingOnPort(port) }

        var outcomes: [KillOutcome] = []
        var seen = Set<Int32>()
        for entry in matches where seen.insert(entry.pid).inserted {
            do {
                try sendSigterm(to: entry)
                outcomes.append(KillOutcome(pid: entry.pid, processName: entry.processName, success: true, message: nil))
            } catch {
                outcomes.append(KillOutcome(pid: entry.pid, processName: entry.processName, success: false,
                                            message: error.localizedDescription))
            }
        }
        return outcomes
    }

    /// SIGTERM, not SIGKILL — dev servers get a chance to shut down cleanly.
    private static func sendSigterm(to entry: PortEntry) throws {
        guard Darwin.kill(entry.pid, SIGTERM) == 0 else {
            switch errno {
            case EPERM: throw PortServiceError.permissionDenied(entry.processName)
            case ESRCH: throw PortServiceError.processGone
            default: throw PortServiceError.killFailed(entry.processName, errno)
            }
        }
    }

    @discardableResult
    public static func openInBrowser(port: Int) -> Bool {
        guard (1...65535).contains(port), let url = URL(string: "http://localhost:\(port)") else { return false }
        return NSWorkspace.shared.open(url)
    }

    // MARK: - lsof plumbing

    private static func runLsof() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    continuation.resume(returning: try runLsofBlocking())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func runLsofBlocking() throws -> String {
        guard FileManager.default.isExecutableFile(atPath: lsofPath) else {
            throw PortServiceError.lsofNotFound
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: lsofPath)
        process.arguments = ["-nP", "-iTCP", "-sTCP:LISTEN", "-FpcLnPt"]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            throw PortServiceError.lsofNotFound
        }

        // lsof can hang for many seconds on a stale network mount; without a
        // timeout the UI would just spin.
        let timedOut = LockedFlag()
        let killer = DispatchWorkItem {
            timedOut.set()
            process.terminate()
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + lsofTimeout, execute: killer)

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        killer.cancel()

        if timedOut.isSet { throw PortServiceError.timedOut }

        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""

        // lsof exits non-zero when some processes are inaccessible but still
        // prints everything it could read — salvage stdout in that case.
        // A genuinely empty result with an error on stderr is surfaced as an
        // error instead of masquerading as "no listening ports", except for
        // lsof's literal "nothing matched" message, which is a real empty.
        if stdout.isEmpty, process.terminationStatus != 0, !stderr.isEmpty,
           !stderr.localizedCaseInsensitiveContains("no internet files") {
            throw PortServiceError.lsofFailed(stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return stdout
    }
}

/// Tiny thread-safe flag for the timeout race.
private final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func set() { lock.lock(); value = true; lock.unlock() }
    var isSet: Bool { lock.lock(); defer { lock.unlock() }; return value }
}
