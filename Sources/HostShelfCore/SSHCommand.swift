import Foundation

public enum SSHCommandError: LocalizedError, Equatable {
    case emptyAlias
    case controlCharacter
    case ambiguousAlias

    public var errorDescription: String? {
        switch self {
        case .emptyAlias: return "主机别名不能为空。"
        case .controlCharacter: return "主机别名含控制字符，无法交给终端。"
        case .ambiguousAlias: return "此主机声明含 @ 或 SSH URI，系统 SSH 会将它解释为连接目标，无法按原样使用别名。"
        }
    }
}

public enum SSHCommand {
    public static func validate(alias: String) throws {
        guard !alias.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SSHCommandError.emptyAlias
        }
        guard alias.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else {
            throw SSHCommandError.controlCharacter
        }
        guard !alias.contains("@"), !alias.lowercased().contains("ssh://") else {
            throw SSHCommandError.ambiguousAlias
        }
    }

    public static func connectionCommand(for alias: String) throws -> String {
        try validate(alias: alias)
        let quoted = "'" + alias.replacingOccurrences(of: "'", with: "'\\''") + "'"
        return "/usr/bin/ssh -- " + quoted
    }
}
