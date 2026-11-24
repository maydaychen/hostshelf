import XCTest
@testable import HostShelfCore

final class SSHCommandTests: XCTestCase {
    func testFixedExecutableAndOptionTerminator() throws {
        XCTAssertEqual(try SSHCommand.connectionCommand(for: "production"), "/usr/bin/ssh -- 'production'")
        XCTAssertEqual(try SSHCommand.connectionCommand(for: "-oProxyCommand=oops"), "/usr/bin/ssh -- '-oProxyCommand=oops'")
    }

    func testShellMetacharactersRemainInsideLiteral() throws {
        XCTAssertEqual(try SSHCommand.connectionCommand(for: "host;$(touch x)`id`$HOME &"),
                       "/usr/bin/ssh -- 'host;$(touch x)`id`$HOME &'")
        XCTAssertEqual(try SSHCommand.connectionCommand(for: "host'name"), "/usr/bin/ssh -- 'host'\\''name'")
    }

    func testUnicodeAliasIsPreserved() throws {
        XCTAssertEqual(try SSHCommand.connectionCommand(for: "家里-测试"), "/usr/bin/ssh -- '家里-测试'")
    }

    func testQuotedAliasRoundTripsThroughShellWithoutExpansion() throws {
        let alias = "host'name; printf unexpected $(printf expanded) `printf expanded` $HOME"
        let command = try SSHCommand.connectionCommand(for: alias)
        let literal = String(command.dropFirst("/usr/bin/ssh -- ".count))
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        // Only printf runs: this exercises shell quoting without launching SSH.
        process.arguments = ["-c", "/usr/bin/printf '%s' " + literal]
        process.standardOutput = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        XCTAssertEqual(String(data: data, encoding: .utf8), alias)
    }

    func testEmptyAliasIsRejected() {
        for alias in ["", " ", "   "] {
            XCTAssertThrowsError(try SSHCommand.connectionCommand(for: alias)) {
                XCTAssertEqual($0 as? SSHCommandError, .emptyAlias)
            }
        }
    }

    func testControlsAreRejected() {
        for scalar in [UInt32(0), 9, 10, 13, 27, 127, 0x85] {
            let alias = "host" + String(UnicodeScalar(scalar)!) + "name"
            XCTAssertThrowsError(try SSHCommand.connectionCommand(for: alias)) {
                XCTAssertEqual($0 as? SSHCommandError, .controlCharacter)
            }
        }
    }

    func testConnectionAndCopyRejectAmbiguousDestinations() {
        for alias in ["user@host", "ssh://example.invalid", "SSH://example.invalid"] {
            XCTAssertThrowsError(try SSHCommand.validate(alias: alias)) {
                XCTAssertEqual($0 as? SSHCommandError, .ambiguousAlias)
            }
            XCTAssertThrowsError(try SSHCommand.connectionCommand(for: alias)) {
                XCTAssertEqual($0 as? SSHCommandError, .ambiguousAlias)
            }
        }
    }

    func testTunnelCommandUsesDashNAndValidates() throws {
        XCTAssertEqual(try SSHCommand.tunnelCommand(for: "production"), "/usr/bin/ssh -N -- 'production'")
        XCTAssertEqual(try SSHCommand.tunnelCommand(for: "host'box"), "/usr/bin/ssh -N -- 'host'\\''box'")
        XCTAssertThrowsError(try SSHCommand.tunnelCommand(for: "user@host")) {
            XCTAssertEqual($0 as? SSHCommandError, .ambiguousAlias)
        }
    }
}
