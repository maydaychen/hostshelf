import Foundation
import XCTest
@testable import HostShelfCore

final class SSHConfigIndexerTests: XCTestCase {
    private var fixture: URL!
    private var home: URL { fixture.appendingPathComponent("home") }
    private var root: URL { home.appendingPathComponent(".ssh/config") }

    override func setUpWithError() throws {
        fixture = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".tmp/indexer-tests/\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".ssh"), withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let fixture { try FileManager.default.removeItem(at: fixture) }
    }

    @discardableResult
    private func write(_ path: String, _ contents: String) throws -> URL {
        let url = home.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func scan(environment: [String: String] = [:]) -> SSHIndexSnapshot {
        SSHConfigIndexer(homeDirectory: home, environment: environment).scan(roots: [root])
    }

    func testMultipleAliasesDuplicateSourcesAndDeclarationValues() throws {
        try write(".ssh/config", """
        Host first second
          HostName server.example
          User=alice
          ProxyCommand ssh gateway -W %h:%p
        Host first
          Port 2222
        """)
        let snapshot = scan()
        XCTAssertTrue(snapshot.diagnostics.isEmpty)
        XCTAssertEqual(snapshot.hosts.map(\.alias), ["first", "second"])
        let first = try XCTUnwrap(snapshot.hosts.first)
        XCTAssertEqual(first.locations.map(\.line), [1, 5])
        XCTAssertEqual(first.declaredValues(for: "hostname"), ["server.example"])
        XCTAssertEqual(first.declaredValues(for: "PORT"), ["2222"])
        XCTAssertEqual(first.declaredValues(for: "proxycommand"), ["ssh gateway -W %h:%p"])
        XCTAssertEqual(snapshot.hosts[1].declaredValues(for: "port"), [])
    }

    func testNestedIncludeExpandsAtItsPositionAndRelativeToUserSSHDirectory() throws {
        try write(".ssh/config", "Include nested/entry.conf\nHost final\n User end\n")
        try write(".ssh/nested/entry.conf", "Host outer\n Include child.conf\n Port 2201\n")
        let child = try write(".ssh/child.conf", "Host child\n User nested\n")
        let snapshot = scan()
        let host = try XCTUnwrap(snapshot.hosts.first { $0.alias == "child" })
        XCTAssertEqual(host.locations.first?.filePath, child.path)
        XCTAssertEqual(host.declaredValues(for: "port"), [])
        XCTAssertEqual(snapshot.hosts.first { $0.alias == "outer" }?.declaredValues(for: "port"), ["2201"])
        XCTAssertEqual(snapshot.includes.map(\.expression), ["nested/entry.conf", "child.conf"])
        XCTAssertTrue(snapshot.diagnostics.isEmpty)
    }

    func testGlobExpansionSortsLexicallyAndReportsUnmatchedPattern() throws {
        try write(".ssh/config", "Include parts/*.conf future/*.conf\n")
        let zebra = try write(".ssh/parts/z.conf", "Host zebra\n")
        let alpha = try write(".ssh/parts/a.conf", "Host alpha\n")
        let snapshot = scan()
        XCTAssertEqual(snapshot.hosts.map(\.alias), ["alpha", "zebra"])
        XCTAssertEqual(snapshot.includes[0].resolvedPaths.map { URL(fileURLWithPath: $0).lastPathComponent }, ["a.conf", "z.conf"])
        XCTAssertTrue(snapshot.includes[1].resolvedPaths.isEmpty)
        XCTAssertEqual(snapshot.sources, [root.path, alpha.path, zebra.path].sorted())
        XCTAssertEqual(snapshot.hosts.map { $0.locations.first?.filePath }, [alpha.path, zebra.path])
        XCTAssertEqual(snapshot.diagnostics.count, 1)
        XCTAssertTrue(snapshot.diagnostics[0].message.contains("未匹配"))
        XCTAssertEqual(snapshot.diagnostics[0].severity, .information)
        XCTAssertFalse(snapshot.hasWarnings)
    }

    func testUnmatchedGlobReportsDiagnosticAndKeepsReadableHosts() throws {
        try write(".ssh/config", "Include empty/*.conf\nHost available\n")
        let directory = home.appendingPathComponent(".ssh/empty")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let snapshot = scan()
        XCTAssertEqual(snapshot.hosts.map(\.alias), ["available"])
        XCTAssertEqual(snapshot.includes.first?.resolvedPaths, [])
        XCTAssertTrue(snapshot.diagnostics.first?.message.contains("未匹配") == true)
        XCTAssertEqual(snapshot.diagnostics.first?.severity, .information)
        XCTAssertFalse(snapshot.hasWarnings)
        XCTAssertEqual(snapshot.diagnostics.first?.location.line, 1)
        XCTAssertEqual(snapshot.sources, [root.path])
        XCTAssertEqual(snapshot.includes.first?.location.filePath, root.path)
        XCTAssertEqual(snapshot.hosts.first?.locations, [SourceLocation(filePath: root.path, line: 2)])
    }

    func testSameFileIncludedAtDifferentPositionsKeepsBothRelationships() throws {
        try write(".ssh/config", "Include child.conf\nHost outer\nInclude child.conf\n")
        try write(".ssh/child.conf", "Host inner\n User child\n")
        let snapshot = scan()
        XCTAssertEqual(snapshot.includes.count, 2)
        XCTAssertEqual(snapshot.includes.map(\.isConditional), [false, true])
        XCTAssertEqual(snapshot.includes.map(\.location.line), [1, 3])
        XCTAssertEqual(snapshot.hosts.first { $0.alias == "inner" }?.isConditional, false)
        XCTAssertFalse(snapshot.diagnostics.contains { $0.message.contains("循环") })
    }

    func testConditionalIncludesAndRulesNeverExecutePredicates() throws {
        let trap = fixture.appendingPathComponent("must-not-exist")
        try write(".ssh/config", """
        Host *.example !blocked
          User common
        Match exec "touch \(trap.path)"
          Include conditional.conf
        Host ordinary
          HostName normal
        """)
        try write(".ssh/conditional.conf", "Host candidate\n HostName conditional\n")
        let snapshot = scan()
        XCTAssertEqual(snapshot.hosts.map(\.alias), ["candidate", "ordinary"])
        XCTAssertEqual(snapshot.rules.map(\.kind), ["Host", "Match"])
        XCTAssertTrue(try XCTUnwrap(snapshot.hosts.first { $0.alias == "candidate" }).isConditional)
        XCTAssertFalse(try XCTUnwrap(snapshot.hosts.first { $0.alias == "ordinary" }).isConditional)
        XCTAssertTrue(snapshot.includes[0].isConditional)
        XCTAssertFalse(FileManager.default.fileExists(atPath: trap.path))
    }

    func testIncludeCycleDetectedByRealPathAndOtherBranchesSurvive() throws {
        try write(".ssh/config", "Host first\nInclude cycle.conf\nHost survivor\n")
        try FileManager.default.createSymbolicLink(at: home.appendingPathComponent(".ssh/cycle.conf"), withDestinationURL: root)
        let snapshot = scan()
        XCTAssertEqual(snapshot.hosts.map(\.alias), ["first", "survivor"])
        XCTAssertEqual(snapshot.diagnostics.count, 1)
        XCTAssertTrue(snapshot.diagnostics[0].message.contains("循环"))
    }

    func testSymlinkSourceKeepsLogicalPathForHostsAndDeclarations() throws {
        let target = try write("shared/config", "Host shared\n User linked-user\n")
        try FileManager.default.createSymbolicLink(at: root, withDestinationURL: target)
        let snapshot = scan()
        XCTAssertEqual(snapshot.hosts.map(\.alias), ["shared"])
        XCTAssertEqual(snapshot.sources, [root.path])
        XCTAssertEqual(snapshot.hosts.first?.locations, [SourceLocation(filePath: root.path, line: 1)])
        XCTAssertEqual(snapshot.hosts.first?.declarations.first?.location, SourceLocation(filePath: root.path, line: 2))
        XCTAssertEqual(snapshot.hosts.first?.declaredValues(for: "user"), ["linked-user"])
        XCTAssertTrue(snapshot.diagnostics.isEmpty)
    }

    func testDirectorySymlinkKeepsIncludedLogicalSourcePath() throws {
        let target = try write("shared/config", "Host shared\n")
        let link = home.appendingPathComponent(".ssh/linked-directory")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target.deletingLastPathComponent())
        try write(".ssh/config", "Include linked-directory/config\n")
        let snapshot = scan()
        let includedPath = link.appendingPathComponent("config").path
        XCTAssertEqual(snapshot.hosts.map(\.alias), ["shared"])
        XCTAssertEqual(snapshot.sources, [root.path, includedPath].sorted())
        XCTAssertEqual(snapshot.includes.first?.resolvedPaths, [includedPath])
        XCTAssertEqual(snapshot.hosts.first?.locations, [SourceLocation(filePath: includedPath, line: 1)])
        XCTAssertTrue(snapshot.diagnostics.isEmpty)
    }

    func testMissingAndInvalidUTF8IncludesAreDiagnosedWithoutDroppingReadableHosts() throws {
        try write(".ssh/config", "Include absent.conf bad.conf\nHost valid\n")
        let invalid = home.appendingPathComponent(".ssh/bad.conf")
        try Data([0xFF, 0xFE, 0xFD]).write(to: invalid)
        let snapshot = scan()
        XCTAssertEqual(snapshot.hosts.map(\.alias), ["valid"])
        XCTAssertEqual(snapshot.diagnostics.count, 2)
        let information = try XCTUnwrap(snapshot.diagnostics.first { $0.severity == .information })
        XCTAssertEqual(information.location, SourceLocation(filePath: root.path, line: 1))
        XCTAssertTrue(information.message.contains("未匹配"))
        let warning = try XCTUnwrap(snapshot.diagnostics.first { $0.severity == .warning })
        XCTAssertEqual(warning.location.filePath, invalid.path)
        XCTAssertTrue(warning.message.contains("UTF-8"))
        XCTAssertTrue(snapshot.hasWarnings)
        XCTAssertEqual(snapshot.includes[0].resolvedPaths, [])
        XCTAssertFalse(snapshot.sources.contains(home.appendingPathComponent(".ssh/absent.conf").path))
    }

    func testMissingLiteralIncludeIsInformationalAndKeepsReadableHosts() throws {
        try write(".ssh/config", "Include missing-directory/absent.conf\nHost available\n")
        let snapshot = scan()
        XCTAssertEqual(snapshot.hosts.map(\.alias), ["available"])
        XCTAssertEqual(snapshot.diagnostics.count, 1)
        XCTAssertEqual(snapshot.diagnostics.first?.severity, .information)
        XCTAssertEqual(snapshot.diagnostics.first?.location, SourceLocation(filePath: root.path, line: 1))
        XCTAssertFalse(snapshot.hasWarnings)
        XCTAssertEqual(snapshot.includes.first?.resolvedPaths, [])
        XCTAssertEqual(snapshot.sources, [root.path])
    }

    func testMissingRootRemainsAReadWarning() throws {
        let snapshot = scan()
        XCTAssertTrue(snapshot.hosts.isEmpty)
        XCTAssertEqual(snapshot.diagnostics.count, 1)
        XCTAssertEqual(snapshot.diagnostics.first?.severity, .warning)
        XCTAssertTrue(snapshot.diagnostics.first?.message.contains("无法读取") == true)
        XCTAssertTrue(snapshot.hasWarnings)
    }

    func testUnreadableIncludeDirectoryRemainsAWarning() throws {
        try write(".ssh/config", "Include denied/*.conf\nHost available\n")
        let deniedFile = try write(".ssh/denied/hidden.conf", "Host hidden\n")
        let deniedDirectory = deniedFile.deletingLastPathComponent()
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: deniedDirectory.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: deniedDirectory.path) }
        let snapshot = scan()
        XCTAssertEqual(snapshot.hosts.map(\.alias), ["available"])
        XCTAssertEqual(snapshot.diagnostics.count, 1)
        XCTAssertEqual(snapshot.diagnostics.first?.severity, .warning)
        XCTAssertTrue(snapshot.hasWarnings)
    }

    func testGlobKeepsReadableMatchesWhenAnotherBranchIsUnreadable() throws {
        try write(".ssh/config", "Include parts/*/*.conf\nHost available\n")
        let first = try write(".ssh/parts/a/first.conf", "Host first\n")
        let denied = try write(".ssh/parts/b/hidden.conf", "Host hidden\n").deletingLastPathComponent()
        let last = try write(".ssh/parts/c/last.conf", "Host last\n")
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: denied.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: denied.path) }

        let snapshot = scan()

        XCTAssertEqual(snapshot.hosts.map(\.alias), ["available", "first", "last"])
        XCTAssertEqual(snapshot.includes.first?.resolvedPaths, [first.path, last.path])
        XCTAssertEqual(snapshot.diagnostics.map(\.severity), [.warning])
    }

    func testSystemIncludesRejectTildeAndKeepSystemBaseForNestedPaths() throws {
        try write(".ssh/user-only.conf", "Host must-not-be-indexed\n")
        let system = try write("system/ssh_config", "Include nested/entry.conf\n")
        let nested = try write("system/nested/entry.conf", "Include ~/.ssh/user-only.conf child.conf\n")
        let child = try write("system/child.conf", "Host system-host\n")
        let indexer = SSHConfigIndexer(homeDirectory: home, environment: [:], systemDirectory: system.deletingLastPathComponent())

        let snapshot = indexer.scan(roots: [system])

        XCTAssertEqual(snapshot.hosts.map(\.alias), ["system-host"])
        XCTAssertEqual(snapshot.includes.map(\.resolvedPaths), [[nested.path], [], [child.path]])
        XCTAssertEqual(snapshot.diagnostics.map(\.severity), [.warning])
        XCTAssertTrue(snapshot.diagnostics.first?.message.contains("系统配置") == true)
    }

    func testUnreadableIncludeIsDiagnosed() throws {
        try write(".ssh/config", "Include denied.conf\nHost available\n")
        let denied = try write(".ssh/denied.conf", "Host unavailable\n")
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: denied.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: denied.path) }
        let snapshot = scan()
        XCTAssertEqual(snapshot.hosts.map(\.alias), ["available"])
        XCTAssertEqual(snapshot.diagnostics.first?.location.filePath, denied.path)
        XCTAssertEqual(snapshot.diagnostics.first?.severity, .warning)
        XCTAssertTrue(snapshot.hasWarnings)
    }

    func testTildeStaticTokensEnvironmentAndUnresolvedDynamicTokens() throws {
        try write(".ssh/config", "Include ~/.ssh/tilde %d/.ssh/home ${CONFIG_PART} %h.conf ${MISSING}\n")
        try write(".ssh/tilde", "Host tilde\n")
        try write(".ssh/home", "Host home\n")
        let env = try write(".ssh/env", "Host environment\n")
        let snapshot = scan(environment: ["CONFIG_PART": env.path])
        XCTAssertEqual(snapshot.hosts.map(\.alias), ["environment", "home", "tilde"])
        XCTAssertEqual(snapshot.includes.count, 5)
        XCTAssertEqual(snapshot.diagnostics.count, 2)
        XCTAssertTrue(snapshot.diagnostics.contains { $0.message.contains("上下文") })
        XCTAssertTrue(snapshot.diagnostics.contains { $0.message.contains("MISSING") })
    }

    func testQuotesEscapesCommentsAndEqualsMatchOpenSSHLexing() throws {
        try write(".ssh/config", """
        # comment
        Include = "parts with spaces/one.conf" 'parts with spaces/two.conf'
        Host = "quoted" 'single' literal#suffix
          ProxyCommand sh -c 'printf "a b"' # trailing comment
        """)
        try write(".ssh/parts with spaces/one.conf", "Host included-one\n")
        try write(".ssh/parts with spaces/two.conf", "Host included-two\n")
        let snapshot = scan()
        XCTAssertEqual(snapshot.hosts.map(\.alias), ["included-one", "included-two", "literal#suffix", "quoted", "single"])
        XCTAssertTrue(snapshot.diagnostics.isEmpty)
        let quoted = try XCTUnwrap(snapshot.hosts.first { $0.alias == "quoted" })
        XCTAssertEqual(quoted.declaredValues(for: "proxycommand"), ["sh -c 'printf \"a b\"'"])
        let escaped = try XCTUnwrap(SSHConfigLexer.parse(##"Include part\ with\ spaces.conf path\#file.conf"##))
        XCTAssertEqual(escaped.arguments, ["part with spaces.conf", ##"path\#file.conf"##])
        XCTAssertEqual(try SSHConfigLexer.parse("Host trailing\\")?.arguments, ["trailing\\"])
    }

    func testCRLFAndBOMPreserveSourceLineNumbers() throws {
        try write(".ssh/config", "\u{FEFF}# comment\r\nHost windows\r\n User alice\r\n")
        let entry = try XCTUnwrap(scan().hosts.first)
        XCTAssertEqual(entry.locations.first?.line, 2)
        XCTAssertEqual(entry.declarations.first?.location.line, 3)
    }

    func testMalformedLineReportsLocationAndKeepsLaterHosts() throws {
        try write(".ssh/config", "Include \"unfinished\nHost recovered\nHost\nMatch\nInclude\n")
        let snapshot = scan()
        XCTAssertEqual(snapshot.hosts.map(\.alias), ["recovered"])
        XCTAssertEqual(snapshot.diagnostics.map(\.location.line), [1, 3, 4, 5])
    }

    func testIdentityFileIsNotFollowedAndInputRemainsUnchanged() throws {
        let identity = try write("private/key", "NOT A CONFIGURATION\nHost secret\n")
        try write(".ssh/config", "Host public\n IdentityFile \(identity.path)\n")
        let before = try Data(contentsOf: root)
        let snapshot = scan()
        XCTAssertEqual(snapshot.hosts.map(\.alias), ["public"])
        XCTAssertFalse(snapshot.sources.contains(identity.path))
        XCTAssertEqual(try Data(contentsOf: root), before)
    }

    func testFreshScanReflectsAtomicReplacementAndNewGlobFile() throws {
        try write(".ssh/config", "Include parts/*.conf\nHost before\n")
        try write(".ssh/parts/one.conf", "Host one\n")
        XCTAssertEqual(scan().hosts.map(\.alias), ["before", "one"])
        try write(".ssh/config", "Include parts/*.conf\nHost after\n")
        try write(".ssh/parts/two.conf", "Host two\n")
        XCTAssertEqual(scan().hosts.map(\.alias), ["after", "one", "two"])
    }

    func testOnlyExplicitAliasesBecomeHostsAndNegatedBlocksAreConditional() throws {
        try write(".ssh/config", "Host exact *.example !blocked ?server\n User common\n")
        let snapshot = scan()
        XCTAssertEqual(snapshot.hosts.map(\.alias), ["exact"])
        XCTAssertEqual(snapshot.rules.count, 1)
        XCTAssertTrue(try XCTUnwrap(snapshot.hosts.first).isConditional)
    }

    func testGlobChildrenRestoreOuterHostAndEachOther() throws {
        try write(".ssh/config", "Host outer\n Include parts/*.conf\n Port 2222\n")
        try write(".ssh/parts/a.conf", "Host inner\n User child\n")
        try write(".ssh/parts/b.conf", "HostName inherited.example\n")
        let snapshot = scan()
        let outer = try XCTUnwrap(snapshot.hosts.first { $0.alias == "outer" })
        let inner = try XCTUnwrap(snapshot.hosts.first { $0.alias == "inner" })
        XCTAssertEqual(outer.declaredValues(for: "port"), ["2222"])
        XCTAssertEqual(outer.declaredValues(for: "hostname"), ["inherited.example"])
        XCTAssertEqual(inner.declaredValues(for: "port"), [])
        XCTAssertEqual(inner.declaredValues(for: "hostname"), [])
    }

    func testNonRegularIncludeDoesNotBlockScanning() throws {
        try write(".ssh/config", "Include /dev/null\nHost remaining\n")
        let snapshot = scan()
        XCTAssertEqual(snapshot.hosts.map(\.alias), ["remaining"])
        XCTAssertTrue(snapshot.diagnostics.contains { $0.message.contains("普通文件") })
    }

    func testGlobUnescapesLiteralIncludeAndEscapedWildcard() throws {
        try write(".ssh/config", ##"Include path\#file.conf literal\*.conf"## + "\n")
        try write(".ssh/path#file.conf", "Host hash-file\n")
        try write(".ssh/literal*.conf", "Host star-file\n")
        let snapshot = scan()
        XCTAssertEqual(snapshot.hosts.map(\.alias), ["hash-file", "star-file"])
        XCTAssertTrue(snapshot.diagnostics.isEmpty)
    }

    func testOversizedSymlinkTargetIsRejectedWithoutReading() throws {
        let large = try write("shared/large", String(repeating: " ", count: 8 * 1_024 * 1_024 + 1))
        try FileManager.default.createSymbolicLink(at: root, withDestinationURL: large)
        let snapshot = scan()
        XCTAssertTrue(snapshot.hosts.isEmpty)
        XCTAssertTrue(snapshot.diagnostics.first?.message.contains("8 MB") == true)
    }
}
