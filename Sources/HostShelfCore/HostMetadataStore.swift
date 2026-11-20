import Darwin
import Foundation

public enum MetadataStoreError: LocalizedError, Equatable {
    case unsupportedVersion(Int)
    case unreadable
    case damaged
    case locked
    case conflict
    case writeFailed

    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version):
            return "附加信息使用不支持的数据版本（\(version)）。原文件已保留，写入已停用。"
        case .unreadable:
            return "无法读取附加信息。原文件已保留，写入已停用，请检查文件权限。"
        case .damaged:
            return "附加信息文件已损坏。原文件已保留，写入已停用，请先备份并检查文件。"
        case .locked:
            return "附加信息写入已停用。请保留原文件，排查后重读附加信息。"
        case .conflict:
            return "磁盘上的附加信息已变化。请重读附加信息后再继续保存，当前草稿会保留。"
        case .writeFailed:
            return "无法保存附加信息，请检查应用数据目录的权限和可用空间。"
        }
    }
}

/// Stores only app-owned annotations. A failed read disables writes for this instance.
public final class HostMetadataStore {
    private enum DiskState: Equatable {
        case missing
        case document(Data)
    }

    private let fileURL: URL
    private let lock = NSLock()
    private var writesLocked = false
    private var baseline: DiskState?

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func load() throws -> MetadataDocument {
        lock.lock()
        defer { lock.unlock() }
        guard !writesLocked else { throw MetadataStoreError.locked }
        let (document, state) = try readExistingDocument()
        baseline = state
        return document
    }

    public func reload() throws -> MetadataDocument {
        lock.lock()
        defer { lock.unlock() }
        let (document, state) = try readExistingDocument()
        baseline = state
        writesLocked = false
        return document
    }

    public func save(_ document: MetadataDocument) throws {
        lock.lock()
        defer { lock.unlock() }
        guard !writesLocked else { throw MetadataStoreError.locked }
        guard document.schemaVersion == 1 else {
            throw MetadataStoreError.unsupportedVersion(document.schemaVersion)
        }
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(document)
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            var template = directory.appendingPathComponent(".metadata.XXXXXX").path.utf8CString
            try template.withUnsafeMutableBufferPointer { buffer in
                let temporaryPath = buffer.baseAddress!
                let descriptor = mkstemp(temporaryPath)
                guard descriptor >= 0 else { throw MetadataStoreError.writeFailed }
                var replaced = false
                defer {
                    _ = Darwin.close(descriptor)
                    if !replaced { _ = unlink(temporaryPath) }
                }
                guard fchmod(descriptor, 0o600) == 0 else { throw MetadataStoreError.writeFailed }
                let file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
                try file.write(contentsOf: data)
                let (_, current) = try readExistingDocument()
                guard current == (baseline ?? .missing) else { throw MetadataStoreError.conflict }
                guard rename(temporaryPath, fileURL.path) == 0 else { throw MetadataStoreError.writeFailed }
                replaced = true
            }
            baseline = .document(data)
        } catch let error as MetadataStoreError {
            throw error
        } catch {
            throw MetadataStoreError.writeFailed
        }
    }

    private func readExistingDocument() throws -> (MetadataDocument, DiskState) {
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return (MetadataDocument(), .missing)
        } catch {
            writesLocked = true
            throw MetadataStoreError.unreadable
        }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let document = try decoder.decode(MetadataDocument.self, from: data)
            guard document.schemaVersion == 1 else {
                writesLocked = true
                throw MetadataStoreError.unsupportedVersion(document.schemaVersion)
            }
            return (document, .document(data))
        } catch let error as MetadataStoreError {
            throw error
        } catch {
            writesLocked = true
            throw MetadataStoreError.damaged
        }
    }
}
