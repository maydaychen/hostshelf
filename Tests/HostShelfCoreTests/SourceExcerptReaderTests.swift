import Darwin
import Foundation
import XCTest
@testable import HostShelfCore

final class SourceExcerptReaderTests: XCTestCase {
    private var fixture: URL!

    override func setUpWithError() throws {
        fixture = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".tmp/source-excerpt-tests/\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let fixture { try FileManager.default.removeItem(at: fixture) }
    }

    private func write(_ name: String, _ content: String) throws -> URL {
        let url = fixture.appendingPathComponent(name)
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func location(_ url: URL, _ line: Int) -> SourceLocation {
        SourceLocation(filePath: url.path, line: line)
    }

    private func identities(for files: URL...) throws -> [String: SourceIdentity] {
        try Dictionary(uniqueKeysWithValues: files.map { ($0.path, try ConfigurationFile.read($0.path).identity) })
    }

    func testIncludeDeclarationsAreReadableWithTheirOwnFileIdentity() throws {
        let included = try write("included.conf", "HostName included.example\nPort 2202")
        let root = try write("config", "Host shared\nInclude \(included.path)\nUser local")
        let snapshot = SSHConfigIndexer(homeDirectory: fixture).scan(roots: [root])
        let host = try XCTUnwrap(snapshot.hosts.first)

        let excerpts = SourceExcerptReader.read(for: host, sourceIdentities: snapshot.sourceIdentities)

        XCTAssertEqual(excerpts.map(\.location.filePath), [root.path, included.path].sorted())
        XCTAssertTrue(excerpts.allSatisfy { $0.error == nil })
        let child = try XCTUnwrap(excerpts.first { $0.location.filePath == included.path })
        XCTAssertEqual(child.lines.map(\.text), ["HostName included.example", "Port 2202"])
        XCTAssertTrue(child.lines.allSatisfy(\.isDeclaration))
    }

    func testFarApartDeclarationsShareOneExcerptWithDistinctRanges() throws {
        let file = try write("config", (1...30).map { "line \($0)" }.joined(separator: "\n"))
        let host = HostEntry(alias: "shared", locations: [location(file, 1)], declarations: [
            SSHDeclaration(keyword: "User", value: "alice", location: location(file, 20))
        ])

        let excerpts = SourceExcerptReader.read(for: host, sourceIdentities: try identities(for: file))

        XCTAssertEqual(excerpts.count, 1)
        let excerpt = try XCTUnwrap(excerpts.first)
        XCTAssertEqual(excerpt.location, location(file, 1))
        XCTAssertEqual(excerpt.lines.map(\.number), [1, 2, 3, 18, 19, 20, 21, 22])
        XCTAssertEqual(excerpt.lines.filter(\.isDeclaration).map(\.number), [1, 20])
        XCTAssertEqual(excerpt.lines.last?.text, "line 22")
    }

    func testOverlappingAndDuplicateAnchorsAreDeduplicatedAndSorted() throws {
        let file = try write("config", (1...10).map { String($0) }.joined(separator: "\n"))
        let host = HostEntry(alias: "shared", locations: [location(file, 3), location(file, 2), location(file, 3)], declarations: [
            SSHDeclaration(keyword: "User", value: "alice", location: location(file, 4)),
            SSHDeclaration(keyword: "Port", value: "22", location: location(file, 3))
        ])

        let excerpt = try XCTUnwrap(SourceExcerptReader.read(for: host, sourceIdentities: try identities(for: file)).first)

        XCTAssertEqual(excerpt.location.line, 2)
        XCTAssertEqual(excerpt.lines.map(\.number), Array(1...6))
        XCTAssertEqual(excerpt.lines.filter(\.isDeclaration).map(\.number), [2, 3, 4])
    }

    func testSameLineNumberInDifferentFilesStaysSeparate() throws {
        let first = try write("a.conf", "first\nHost shared\nUser alice")
        let second = try write("b.conf", "second\nHost shared\nUser bob")
        let host = HostEntry(alias: "shared", locations: [location(second, 2), location(first, 2)])

        let excerpts = SourceExcerptReader.read(for: host, sourceIdentities: try identities(for: first, second))

        XCTAssertEqual(excerpts.count, 2)
        XCTAssertNotEqual(excerpts[0].id, excerpts[1].id)
        XCTAssertEqual(excerpts.map { $0.lines.first?.text }, ["first", "second"])
        XCTAssertTrue(excerpts.allSatisfy { $0.lines.first(where: \.isDeclaration)?.number == 2 })
    }

    func testUnlistedSourceIsRejectedBeforeReadingAndIdentityFileIsNotFollowed() throws {
        let file = try write("unlisted.conf", "sensitive content")
        let missingKey = fixture.appendingPathComponent("must-not-read-private-key")
        let host = HostEntry(alias: "shared", locations: [location(file, 1)], declarations: [
            SSHDeclaration(keyword: "IdentityFile", value: missingKey.path, location: location(file, 1))
        ])

        let excerpts = SourceExcerptReader.read(for: host, sourceIdentities: [:])

        XCTAssertEqual(excerpts.count, 1)
        XCTAssertEqual(excerpts[0].location.filePath, file.path)
        XCTAssertTrue(excerpts[0].lines.isEmpty)
        XCTAssertTrue(excerpts[0].error?.contains("此路径不在已读取配置来源中") == true)
    }

    func testDisappearedFileDoesNotDiscardOtherReadableSources() throws {
        let readable = try write("a.conf", "Host shared")
        let missing = try write("b.conf", "Host shared")
        let host = HostEntry(alias: "shared", locations: [location(readable, 1), location(missing, 1)])
        let sourceIdentities = try identities(for: readable, missing)
        try FileManager.default.removeItem(at: missing)

        let excerpts = SourceExcerptReader.read(for: host, sourceIdentities: sourceIdentities)

        XCTAssertEqual(excerpts.count, 2)
        XCTAssertEqual(excerpts[0].lines.first?.text, "Host shared")
        XCTAssertNil(excerpts[0].error)
        XCTAssertTrue(excerpts[1].lines.isEmpty)
        XCTAssertTrue(excerpts[1].error?.contains("读取失败") == true)
    }

    func testOutOfRangeAnchorsReportStaleSourceAndKeepValidLines() throws {
        let file = try write("config", "one\ntwo\nthree\nfour\nfive")
        let host = HostEntry(alias: "shared", locations: [location(file, 0), location(file, Int.max)], declarations: [
            SSHDeclaration(keyword: "User", value: "alice", location: location(file, 3))
        ])

        let excerpt = try XCTUnwrap(SourceExcerptReader.read(for: host, sourceIdentities: try identities(for: file)).first)

        XCTAssertEqual(excerpt.lines.map(\.number), Array(1...5))
        XCTAssertEqual(excerpt.lines.filter(\.isDeclaration).map(\.number), [3])
        XCTAssertTrue(excerpt.error?.contains("第 0、\(Int.max) 行") == true)
        XCTAssertTrue(excerpt.error?.contains("请刷新配置") == true)
    }

    func testAllOutOfRangeAnchorsReturnExplicitError() throws {
        let file = try write("config", "Host shared")
        let host = HostEntry(alias: "shared", locations: [location(file, 10)])

        let excerpt = try XCTUnwrap(SourceExcerptReader.read(for: host, sourceIdentities: try identities(for: file)).first)

        XCTAssertTrue(excerpt.lines.isEmpty)
        XCTAssertTrue(excerpt.error?.contains("共 1 行") == true)
    }

    func testInvalidEncodingReturnsReadError() throws {
        let file = fixture.appendingPathComponent("config")
        try Data([0xFF, 0xFE, 0xFD]).write(to: file)
        let host = HostEntry(alias: "shared", locations: [location(file, 1)])

        let excerpt = try XCTUnwrap(SourceExcerptReader.read(for: host, sourceIdentities: try identities(for: file)).first)

        XCTAssertTrue(excerpt.lines.isEmpty)
        XCTAssertTrue(excerpt.error?.contains("读取失败") == true)
    }

    func testCRLFLineNumbersAgreeWithIndexer() throws {
        let root = try write("config", "Host shared\r\nHostName shared.example\r\nUser alice")
        let snapshot = SSHConfigIndexer(homeDirectory: fixture).scan(roots: [root])
        let host = try XCTUnwrap(snapshot.hosts.first)

        let excerpt = try XCTUnwrap(SourceExcerptReader.read(for: host, sourceIdentities: snapshot.sourceIdentities).first)

        XCTAssertEqual(excerpt.lines.map(\.number), [1, 2, 3])
        XCTAssertEqual(excerpt.lines.map(\.text), ["Host shared", "HostName shared.example", "User alice"])
        XCTAssertTrue(excerpt.lines.allSatisfy(\.isDeclaration))
    }

    func testShouldCancelStopsBeforeReadingRemainingFiles() throws {
        let first = try write("a.conf", "Host shared\nUser alice")
        let second = try write("b.conf", "Host shared\nPort 2222")
        let host = HostEntry(alias: "shared", locations: [location(first, 1), location(second, 1)])
        var checks = 0

        let excerpts = SourceExcerptReader.read(for: host, sourceIdentities: try identities(for: first, second)) {
            checks += 1
            return checks > 1
        }

        XCTAssertEqual(excerpts.map(\.location.filePath), [first.path])
    }

    func testRetargetedSymlinkRequiresRefreshBeforeShowingAnotherFile() throws {
        let original = try write("original", "Host shared\n User old")
        let replacement = try write("replacement", "Host shared\n User new")
        let link = fixture.appendingPathComponent("config")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: original)
        let indexer = SSHConfigIndexer(homeDirectory: fixture)
        let snapshot = indexer.scan(roots: [link])
        let oldHost = try XCTUnwrap(snapshot.hosts.first)
        XCTAssertEqual(SourceExcerptReader.read(for: oldHost, sourceIdentities: snapshot.sourceIdentities).first?.lines.last?.text, " User old")

        try FileManager.default.removeItem(at: link)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: replacement)
        let stale = try XCTUnwrap(SourceExcerptReader.read(for: oldHost, sourceIdentities: snapshot.sourceIdentities).first)
        XCTAssertTrue(stale.lines.isEmpty)
        XCTAssertTrue(stale.error?.contains("请手动刷新配置") == true)

        let refreshed = indexer.scan(roots: [link])
        let newHost = try XCTUnwrap(refreshed.hosts.first)
        XCTAssertEqual(SourceExcerptReader.read(for: newHost, sourceIdentities: refreshed.sourceIdentities).first?.lines.last?.text, " User new")
    }

    func testSameSizeEditDoesNotShowStaleLineLocations() throws {
        let file = try write("config", "Host shared\n User old")
        let sourceIdentities = try identities(for: file)
        let handle = try FileHandle(forWritingTo: file)
        try handle.write(contentsOf: Data("Host shared\n User new".utf8))
        try handle.close()
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_700_000_000)], ofItemAtPath: file.path)

        let host = HostEntry(alias: "shared", locations: [location(file, 2)])
        let excerpt = try XCTUnwrap(SourceExcerptReader.read(for: host, sourceIdentities: sourceIdentities).first)
        XCTAssertTrue(excerpt.lines.isEmpty)
        XCTAssertTrue(excerpt.error?.contains("来源已变化") == true)
    }

    func testPreviewRejectsFilesThatGrowPastLimitOrBecomeNonRegular() throws {
        let file = try write("config", "Host shared\n")
        let sourceIdentities = try identities(for: file)
        let host = HostEntry(alias: "shared", locations: [location(file, 1)])
        let handle = try FileHandle(forWritingTo: file)
        try handle.truncate(atOffset: UInt64(ConfigurationFile.maximumSize + 1))
        try handle.close()

        let oversized = try XCTUnwrap(SourceExcerptReader.read(for: host, sourceIdentities: sourceIdentities).first)
        XCTAssertTrue(oversized.lines.isEmpty)
        XCTAssertTrue(oversized.error?.contains("超过 8 MB") == true)

        try FileManager.default.removeItem(at: file)
        XCTAssertEqual(mkfifo(file.path, 0o600), 0)
        let nonRegular = try XCTUnwrap(SourceExcerptReader.read(for: host, sourceIdentities: sourceIdentities).first)
        XCTAssertTrue(nonRegular.lines.isEmpty)
        XCTAssertTrue(nonRegular.error?.contains("不是普通文件") == true)
    }

    func testDescriptorReaderAcceptsTheExactByteLimitWithoutTruncating() throws {
        let file = fixture.appendingPathComponent("config")
        var bytes = Data(repeating: 0x31, count: ConfigurationFile.maximumSize)
        bytes[bytes.count - 1] = 0x32
        try bytes.write(to: file)

        XCTAssertEqual(try ConfigurationFile.read(file.path).data, bytes)
    }
}
