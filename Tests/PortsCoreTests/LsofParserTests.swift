import XCTest
@testable import PortsCore

final class LsofParserTests: XCTestCase {

    func testParsesSimpleIPv4Listener() {
        let output = """
        p123
        cnode
        Lap
        f23
        tIPv4
        PTCP
        n127.0.0.1:3000
        """
        let entries = LsofParser.parse(output)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].port, 3000)
        XCTAssertEqual(entries[0].pid, 123)
        XCTAssertEqual(entries[0].processName, "node")
        XCTAssertEqual(entries[0].address, "127.0.0.1")
        XCTAssertEqual(entries[0].user, "ap")
        XCTAssertFalse(entries[0].isExposed)
    }

    func testCommandNamesWithSpacesSurvive() {
        let output = """
        p42
        cGoogle Chrome Helper
        Lap
        f10
        tIPv4
        PTCP
        n127.0.0.1:9222
        """
        let entries = LsofParser.parse(output)
        XCTAssertEqual(entries[0].processName, "Google Chrome Helper")
    }

    func testWildcardResolvesPerIPVersion() {
        let output = """
        p7
        cpython
        Lap
        f3
        tIPv4
        PTCP
        n*:8000
        p8
        cdeno
        Lap
        f3
        tIPv6
        PTCP
        n*:8001
        """
        let entries = LsofParser.parse(output)
        XCTAssertEqual(entries.map(\.address), ["0.0.0.0", "::"])
        XCTAssertTrue(entries.allSatisfy(\.isExposed))
    }

    func testBracketedIPv6AddressIsUnwrapped() {
        let output = """
        p9
        cbeam
        Lap
        f30
        tIPv6
        PTCP
        n[::1]:5000
        """
        let entries = LsofParser.parse(output)
        XCTAssertEqual(entries[0].address, "::1")
        XCTAssertEqual(entries[0].port, 5000)
        XCTAssertFalse(entries[0].isExposed)
    }

    func testDualStackSocketsDedupeToOneEntryPreferringExposure() {
        // Same pid + port on loopback IPv4 and wildcard IPv6: one row,
        // and the exposed bind must win so the UI never under-reports.
        let output = """
        p50
        cvite
        Lap
        f20
        tIPv4
        PTCP
        n127.0.0.1:5173
        f21
        tIPv6
        PTCP
        n*:5173
        """
        let entries = LsofParser.parse(output)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].address, "::")
        XCTAssertTrue(entries[0].isExposed)
    }

    func testMultipleProcessesOnSamePortAreAllKept() {
        // SO_REUSEPORT workers: same port, different pids — two rows.
        let output = """
        p100
        cnginx
        Lroot
        f6
        tIPv4
        PTCP
        n*:80
        p101
        cnginx
        Lroot
        f6
        tIPv4
        PTCP
        n*:80
        """
        let entries = LsofParser.parse(output)
        XCTAssertEqual(entries.map(\.pid), [100, 101])
    }

    func testFileBlockStateResetsBetweenFds() {
        // Second fd has no explicit t line; stale IPv4 from fd 20 must not leak.
        let output = """
        p60
        cmystery
        Lap
        f20
        tIPv4
        PTCP
        n*:1234
        f21
        PTCP
        n*:1235
        """
        let entries = LsofParser.parse(output)
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].ipVersion, "IPv4")
        XCTAssertEqual(entries[1].ipVersion, "")
        XCTAssertEqual(entries[1].address, "*")
    }

    func testGarbageAndPartialLinesAreSkipped() {
        let output = """
        garbage without tag prefix meaning
        p0
        cbroken
        n127.0.0.1:99
        pnotanumber
        n127.0.0.1:98
        p70
        cok
        Lap
        f5
        tIPv4
        PTCP
        nnoport
        n127.0.0.1:70000
        n127.0.0.1:7070
        """
        let entries = LsofParser.parse(output)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].port, 7070)
        XCTAssertEqual(entries[0].processName, "ok")
    }

    func testEmptyOutputYieldsEmptyList() {
        XCTAssertEqual(LsofParser.parse(""), [])
    }

    func testSortedByPortThenPid() {
        let output = """
        p300
        cb
        Lap
        f1
        tIPv4
        PTCP
        n127.0.0.1:9000
        p200
        ca
        Lap
        f1
        tIPv4
        PTCP
        n127.0.0.1:80
        """
        let entries = LsofParser.parse(output)
        XCTAssertEqual(entries.map(\.port), [80, 9000])
    }

    func testParseAddressRejectsInvalidPorts() {
        XCTAssertNil(LsofParser.parseAddress("127.0.0.1:0", ipVersion: "IPv4"))
        XCTAssertNil(LsofParser.parseAddress("127.0.0.1:65536", ipVersion: "IPv4"))
        XCTAssertNil(LsofParser.parseAddress("127.0.0.1:abc", ipVersion: "IPv4"))
        XCTAssertNil(LsofParser.parseAddress("no-colon", ipVersion: "IPv4"))
        XCTAssertNotNil(LsofParser.parseAddress("127.0.0.1:65535", ipVersion: "IPv4"))
    }
}
