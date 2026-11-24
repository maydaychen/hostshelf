import XCTest
@testable import HostShelfCore

final class ExternalActionsTests: XCTestCase {
    func testEditorFileURLFormatsAndValidatesPaths() {
        let url = ExternalActionBuilder.editorFileURL(
            for: .vscode,
            filePath: "/Users/demo/my ssh/prod #1?.conf",
            line: 24
        )
        XCTAssertEqual(url?.scheme, "vscode")
        XCTAssertEqual(url?.host, "file")
        XCTAssertEqual(url?.absoluteString, "vscode://file/Users/demo/my%20ssh/prod%20%231%3F.conf:24")

        let clamped = ExternalActionBuilder.editorFileURL(for: .cursor, filePath: "/etc/ssh/ssh_config", line: 0)
        XCTAssertEqual(clamped?.absoluteString, "cursor://file/etc/ssh/ssh_config:1")

        let sysURL = ExternalActionBuilder.editorFileURL(for: .systemDefault, filePath: "/etc/ssh/ssh_config", line: 5)
        XCTAssertEqual(sysURL, URL(fileURLWithPath: "/etc/ssh/ssh_config"))

        XCTAssertNil(ExternalActionBuilder.editorFileURL(for: .vscode, filePath: "relative/config", line: 1))
        XCTAssertNil(ExternalActionBuilder.editorFileURL(for: .zed, filePath: "/tmp/bad\npath", line: 1))
    }

    func testRemoteSSHURLBuildsPerEditorAndRejectsInvalidAliases() throws {
        XCTAssertEqual(
            try ExternalActionBuilder.remoteSSHURL(for: .vscode, alias: "prod-api_01").absoluteString,
            "vscode://vscode-remote/ssh-remote+prod-api_01/"
        )
        XCTAssertEqual(
            try ExternalActionBuilder.remoteSSHURL(for: .cursor, alias: "prod host").absoluteString,
            "cursor://vscode-remote/ssh-remote+prod%20host/"
        )
        XCTAssertEqual(
            try ExternalActionBuilder.remoteSSHURL(for: .zed, alias: "prod-api_01").absoluteString,
            "zed://ssh/prod-api_01/~"
        )

        XCTAssertThrowsError(try ExternalActionBuilder.remoteSSHURL(for: .systemDefault, alias: "prod")) {
            XCTAssertEqual($0 as? ExternalActionError, .remoteSSHUnsupported)
        }
        XCTAssertThrowsError(try ExternalActionBuilder.remoteSSHURL(for: .vscode, alias: "user@prod")) {
            XCTAssertEqual($0 as? SSHCommandError, .ambiguousAlias)
        }
        XCTAssertThrowsError(try ExternalActionBuilder.remoteSSHURL(for: .cursor, alias: "ssh://prod")) {
            XCTAssertEqual($0 as? SSHCommandError, .ambiguousAlias)
        }
    }

    func testSCPTemplateAndAddressHelpers() throws {
        XCTAssertEqual(
            try ExternalActionBuilder.scpTemplateCommand(for: "prod'box"),
            "/usr/bin/scp -- <local-path> 'prod'\\''box:~/'"
        )
        XCTAssertThrowsError(try ExternalActionBuilder.scpTemplateCommand(for: "user@box"))

        let loc = SourceLocation(filePath: "/fixture/config", line: 1)
        let unique = HostEntry(
            alias: "web",
            declarations: [
                SSHDeclaration(keyword: "HostName", value: "web.example.invalid", location: loc),
                SSHDeclaration(keyword: "User", value: "deploy", location: loc),
            ]
        )
        XCTAssertEqual(ExternalActionBuilder.singleDeclaredAddress(for: unique), "web.example.invalid")
        XCTAssertEqual(ExternalActionBuilder.userAtHostAddress(for: unique), "deploy@web.example.invalid")

        var ambiguous = unique
        ambiguous.declarations.append(SSHDeclaration(keyword: "HostName", value: "alt.example.invalid", location: loc))
        XCTAssertNil(ExternalActionBuilder.singleDeclaredAddress(for: ambiguous))
        XCTAssertNil(ExternalActionBuilder.userAtHostAddress(for: ambiguous))
    }
}
