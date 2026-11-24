import Foundation
import XCTest
@testable import HostShelfCore

final class HostMetadataStoreTests: XCTestCase {
    private var directory: URL!
    private var fileURL: URL { directory.appendingPathComponent("nested/metadata.json") }

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("hostshelf-metadata-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    func testMissingFileLoadsEmptyWithoutCreatingData() throws {
        XCTAssertEqual(try HostMetadataStore(fileURL: fileURL).load(), MetadataDocument())
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testRoundTripKeepsUnknownHostsAndChineseNotes() throws {
        let document = MetadataDocument(annotations: [
            "old-host": HostAnnotation(group: "工作", note: "生产环境，请先检查。", isFavorite: true,
                                       lastLaunchedAt: Date(timeIntervalSince1970: 1_700_000_000))
        ], groups: ["工作", "家里"])
        let store = HostMetadataStore(fileURL: fileURL)
        try store.save(document)
        XCTAssertEqual(try HostMetadataStore(fileURL: fileURL).load(), document)
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }

    func testUpdateAtomicallyReplacesValidDocument() throws {
        let store = HostMetadataStore(fileURL: fileURL)
        try store.save(MetadataDocument(groups: ["before"]))
        try store.save(MetadataDocument(groups: ["after"]))
        XCTAssertEqual(try store.load().groups, ["after"])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: fileURL.deletingLastPathComponent().path), ["metadata.json"])
    }

    func testCorruptionIsPreservedAndLocksWrites() throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let original = Data("{ invalid metadata".utf8)
        try original.write(to: fileURL)
        let store = HostMetadataStore(fileURL: fileURL)
        XCTAssertThrowsError(try store.load()) { XCTAssertEqual($0 as? MetadataStoreError, .damaged) }
        XCTAssertThrowsError(try store.save(MetadataDocument())) { XCTAssertEqual($0 as? MetadataStoreError, .locked) }
        XCTAssertEqual(try Data(contentsOf: fileURL), original)
    }

    func testUnsupportedSchemaIsPreserved() throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let original = Data(#"{"schemaVersion":99,"annotations":{},"groups":[]}"#.utf8)
        try original.write(to: fileURL)
        let store = HostMetadataStore(fileURL: fileURL)
        XCTAssertThrowsError(try store.load()) { XCTAssertEqual($0 as? MetadataStoreError, .unsupportedVersion(99)) }
        XCTAssertThrowsError(try store.save(MetadataDocument()))
        XCTAssertEqual(try Data(contentsOf: fileURL), original)
    }

    func testUnreadablePathLocksWritesInsteadOfTreatingItAsMissing() throws {
        try FileManager.default.createDirectory(at: fileURL, withIntermediateDirectories: true)
        let store = HostMetadataStore(fileURL: fileURL)
        XCTAssertThrowsError(try store.load()) { XCTAssertEqual($0 as? MetadataStoreError, .unreadable) }
        XCTAssertThrowsError(try store.save(MetadataDocument())) { XCTAssertEqual($0 as? MetadataStoreError, .locked) }
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
    }

    func testSaveRechecksFileChangedSinceLoad() throws {
        let store = HostMetadataStore(fileURL: fileURL)
        try store.save(MetadataDocument())
        _ = try store.load()
        let corrupted = Data("corrupted externally".utf8)
        try corrupted.write(to: fileURL)
        XCTAssertThrowsError(try store.save(MetadataDocument(groups: ["must not overwrite"])))
        XCTAssertEqual(try Data(contentsOf: fileURL), corrupted)
    }

    func testSaveWithoutLoadProtectsExistingCorruption() throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let corrupted = Data("broken".utf8)
        try corrupted.write(to: fileURL)
        XCTAssertThrowsError(try HostMetadataStore(fileURL: fileURL).save(MetadataDocument()))
        XCTAssertEqual(try Data(contentsOf: fileURL), corrupted)
    }

    func testUnsupportedOutgoingSchemaDoesNotChangeExistingData() throws {
        let store = HostMetadataStore(fileURL: fileURL)
        try store.save(MetadataDocument(groups: ["original"]))
        XCTAssertThrowsError(try store.save(MetadataDocument(schemaVersion: 2)))
        XCTAssertEqual(try store.load().groups, ["original"])
    }

    func testExternalCreationAfterMissingLoadRequiresExplicitReload() throws {
        let store = HostMetadataStore(fileURL: fileURL)
        XCTAssertEqual(try store.load(), MetadataDocument())
        let external = MetadataDocument(groups: ["external"])
        try HostMetadataStore(fileURL: fileURL).save(external)

        XCTAssertThrowsError(try store.save(MetadataDocument(groups: ["local"]))) {
            XCTAssertEqual($0 as? MetadataStoreError, .conflict)
        }
        XCTAssertEqual(try HostMetadataStore(fileURL: fileURL).load(), external)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: fileURL.deletingLastPathComponent().path), ["metadata.json"])
        XCTAssertEqual(try store.reload(), external)
        let updated = MetadataDocument(groups: ["external", "local"])
        try store.save(updated)
        XCTAssertEqual(try store.load(), updated)
    }

    func testValidExternalUpdateCannotBeOverwrittenByStaleStore() throws {
        let store = HostMetadataStore(fileURL: fileURL)
        try store.save(MetadataDocument(groups: ["original"]))
        let external = HostMetadataStore(fileURL: fileURL)
        _ = try external.load()
        try external.save(MetadataDocument(groups: ["external"]))

        XCTAssertThrowsError(try store.save(MetadataDocument(groups: ["stale"]))) {
            XCTAssertEqual($0 as? MetadataStoreError, .conflict)
        }
        XCTAssertEqual(try external.load().groups, ["external"])
    }

    func testReloadOnlyUnlocksAfterReadingRepairedDocument() throws {
        let store = HostMetadataStore(fileURL: fileURL)
        try store.save(MetadataDocument(groups: ["old"]))
        let backup = try Data(contentsOf: fileURL)
        try Data("broken".utf8).write(to: fileURL, options: .atomic)
        XCTAssertThrowsError(try store.load())
        XCTAssertThrowsError(try store.reload())
        XCTAssertThrowsError(try store.save(MetadataDocument())) {
            XCTAssertEqual($0 as? MetadataStoreError, .locked)
        }
        try backup.write(to: fileURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: fileURL.path)
        XCTAssertEqual(try store.reload().groups, ["old"])
        try store.save(MetadataDocument(groups: ["restored"]))
        let permissions = try FileManager.default.attributesOfItem(atPath: fileURL.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)
    }

    func testLegacyV1MetadataDecodesWithDefaultTagsAndProtection() throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let legacy = Data(#"{"annotations":{"alpha":{"group":"工作","isFavorite":true,"note":"备注"}},"groups":["工作"],"schemaVersion":1}"#.utf8)
        try legacy.write(to: fileURL)
        let loaded = try HostMetadataStore(fileURL: fileURL).load()
        XCTAssertEqual(loaded.protectedGroups, [])
        XCTAssertEqual(loaded.annotations["alpha"]?.tags, [])
        XCTAssertEqual(loaded.annotations["alpha"]?.requiresConfirmation, false)
        XCTAssertEqual(loaded.annotations["alpha"]?.isFavorite, true)
    }

    func testTagsConfirmationAndProtectedGroupsRoundTrip() throws {
        XCTAssertEqual(HostAnnotation.parseTagsInput(" #prod, hk  #db，prod "), ["prod", "hk", "db"])
        let doc = MetadataDocument(
            annotations: [
                "prod-db": HostAnnotation(
                    group: "生产",
                    note: "核心库",
                    tags: ["#prod", "prod", " db "],
                    requiresConfirmation: true
                ),
            ],
            groups: ["生产"],
            protectedGroups: ["生产"]
        )
        let store = HostMetadataStore(fileURL: fileURL)
        try store.save(doc)
        let reloaded = try HostMetadataStore(fileURL: fileURL).load()
        XCTAssertEqual(reloaded, doc)
        XCTAssertEqual(reloaded.annotations["prod-db"]?.tags, ["prod", "db"])
    }
}
