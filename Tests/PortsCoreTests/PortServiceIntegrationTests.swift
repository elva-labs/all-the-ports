import XCTest
@testable import PortsCore

/// End-to-end tests against the real system: they spawn a listener, find it
/// via lsof, and SIGTERM it. Opt-in (they touch real processes):
///
///     PORTS_INTEGRATION=1 swift test
final class PortServiceIntegrationTests: XCTestCase {

    override func setUpWithError() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["PORTS_INTEGRATION"] == "1",
            "Set PORTS_INTEGRATION=1 to run integration tests"
        )
    }

    func testListFindsRealListenerAndKillAllTerminatesIt() async throws {
        let port = 39217

        let server = Process()
        server.executableURL = URL(fileURLWithPath: "/usr/bin/nc")
        server.arguments = ["-l", String(port)]
        try server.run()
        defer { if server.isRunning { server.terminate() } }

        // Give the socket a moment to reach LISTEN.
        var entry: PortEntry?
        for _ in 0..<20 {
            entry = try await PortService.listPorts().first { $0.port == port }
            if entry != nil { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }

        let found = try XCTUnwrap(entry, "listener on \(port) should appear in listPorts()")
        XCTAssertEqual(found.pid, server.processIdentifier)

        let outcomes = try await PortService.killAll(onPort: port)
        XCTAssertEqual(outcomes.count, 1)
        XCTAssertTrue(outcomes[0].success)

        // The process should die and the port should free up.
        for _ in 0..<20 {
            if try await PortService.listPorts().first(where: { $0.port == port }) == nil { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        server.waitUntilExit()
        XCTAssertFalse(server.isRunning)
    }

    func testKillRefusesPidNotHoldingAListeningPort() async throws {
        // Spawn a process that does NOT listen on anything.
        let sleeper = Process()
        sleeper.executableURL = URL(fileURLWithPath: "/bin/sleep")
        sleeper.arguments = ["30"]
        try sleeper.run()
        defer { if sleeper.isRunning { sleeper.terminate() } }

        do {
            try await PortService.kill(pid: sleeper.processIdentifier)
            XCTFail("kill must refuse a PID with no listening socket")
        } catch let error as PortServiceError {
            XCTAssertEqual(error, .notListening)
        }
        XCTAssertTrue(sleeper.isRunning, "the non-listener must not have been signalled")
    }

    func testKillAllOnFreePortThrowsNothingOnPort() async throws {
        do {
            _ = try await PortService.killAll(onPort: 39218)
            XCTFail("expected nothingOnPort")
        } catch let error as PortServiceError {
            XCTAssertEqual(error, .nothingOnPort(39218))
        }
    }
}
