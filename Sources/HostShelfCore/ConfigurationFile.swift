import Darwin
import Foundation

public struct SourceIdentity: Equatable, Sendable {
    private let device: dev_t
    private let inode: ino_t
    private let size: off_t
    private let modificationSeconds: Int
    private let modificationNanoseconds: Int
    private let changeSeconds: Int
    private let changeNanoseconds: Int

    fileprivate init(_ attributes: stat) {
        device = attributes.st_dev
        inode = attributes.st_ino
        size = attributes.st_size
        modificationSeconds = attributes.st_mtimespec.tv_sec
        modificationNanoseconds = attributes.st_mtimespec.tv_nsec
        changeSeconds = attributes.st_ctimespec.tv_sec
        changeNanoseconds = attributes.st_ctimespec.tv_nsec
    }
}

enum ConfigurationFile {
    static let maximumSize = 8 * 1_024 * 1_024

    enum ReadError: LocalizedError {
        case notRegular, tooLarge, changed

        var errorDescription: String? {
            switch self {
            case .notRegular: return "配置路径不是普通文件"
            case .tooLarge: return "配置文件超过 8 MB"
            case .changed: return "配置来源已变化"
            }
        }
    }

    static func read(_ path: String, expectedIdentity: SourceIdentity? = nil) throws -> (data: Data, identity: SourceIdentity) {
        var descriptor: Int32
        repeat {
            // Check the actual target of a symlink without waiting for a FIFO writer.
            descriptor = Darwin.open(path, O_RDONLY | O_NONBLOCK | O_CLOEXEC)
        } while descriptor == -1 && errno == EINTR
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { _ = Darwin.close(descriptor) }

        let identity = try checkedIdentity(of: descriptor)
        if let expectedIdentity, expectedIdentity != identity { throw ReadError.changed }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1_024)
        while data.count <= maximumSize {
            let requested = min(buffer.count, maximumSize + 1 - data.count)
            let count = buffer.withUnsafeMutableBytes { Darwin.read(descriptor, $0.baseAddress, requested) }
            if count == 0 { break }
            if count == -1 {
                if errno == EINTR { continue }
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            data.append(contentsOf: buffer.prefix(count))
        }
        guard data.count <= maximumSize else { throw ReadError.tooLarge }
        guard try checkedIdentity(of: descriptor) == identity else { throw ReadError.changed }
        return (data, identity)
    }

    private static func checkedIdentity(of descriptor: Int32) throws -> SourceIdentity {
        var attributes = stat()
        var result: Int32
        repeat { result = fstat(descriptor, &attributes) } while result == -1 && errno == EINTR
        guard result == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        guard attributes.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else { throw ReadError.notRegular }
        guard attributes.st_size <= maximumSize else { throw ReadError.tooLarge }
        return SourceIdentity(attributes)
    }
}
