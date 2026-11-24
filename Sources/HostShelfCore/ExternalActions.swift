import Foundation

public enum EditorTarget: String, CaseIterable, Identifiable, Sendable {
    case vscode
    case cursor
    case zed
    case systemDefault

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .vscode: return "VS Code"
        case .cursor: return "Cursor"
        case .zed: return "Zed"
        case .systemDefault: return "系统默认编辑器"
        }
    }

    public var bundleIdentifier: String? {
        switch self {
        case .vscode: return "com.microsoft.VSCode"
        case .cursor: return "com.todesktop.230313mzl4w4u92"
        case .zed: return "dev.zed.Zed"
        case .systemDefault: return nil
        }
    }

    public var scheme: String? {
        switch self {
        case .vscode: return "vscode"
        case .cursor: return "cursor"
        case .zed: return "zed"
        case .systemDefault: return nil
        }
    }

    public var supportsRemoteSSH: Bool {
        switch self {
        case .vscode, .cursor, .zed: return true
        case .systemDefault: return false
        }
    }

    public static var remoteSSHTargets: [EditorTarget] {
        [.vscode, .cursor, .zed]
    }
}

public enum ExternalActionError: LocalizedError, Equatable {
    case invalidFilePath
    case remoteSSHUnsupported
    case editorUnavailable(EditorTarget)
    case openFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidFilePath:
            return "配置文件路径无效，无法在外部编辑器中打开。"
        case .remoteSSHUnsupported:
            return "当前所选编辑器不支持 Remote-SSH。"
        case .editorUnavailable(let editor):
            return "未安装 \(editor.displayName)，或无法在系统中找到该应用。"
        case .openFailed(let target):
            return "无法打开 \(target)，请检查对应应用是否可用。"
        }
    }
}

public enum ExternalActionBuilder {
    private static let editorPathAllowed = CharacterSet.urlPathAllowed
        .subtracting(CharacterSet(charactersIn: ":;#?%"))
    private static let remoteAliasAllowed = CharacterSet.alphanumerics
        .union(CharacterSet(charactersIn: "-._"))

    public static func editorFileURL(for editor: EditorTarget, filePath: String, line: Int) -> URL? {
        guard !filePath.isEmpty,
              filePath.hasPrefix("/"),
              filePath.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else {
            return nil
        }
        let clampedLine = max(1, line)
        let standardizedPath = URL(fileURLWithPath: filePath).standardizedFileURL.path
        guard standardizedPath.hasPrefix("/") else { return nil }

        guard let scheme = editor.scheme else {
            return URL(fileURLWithPath: standardizedPath)
        }
        guard let encodedPath = standardizedPath.addingPercentEncoding(withAllowedCharacters: editorPathAllowed) else {
            return nil
        }
        return URL(string: "\(scheme)://file\(encodedPath):\(clampedLine)")
    }

    public static func remoteSSHURL(for editor: EditorTarget, alias: String) throws -> URL {
        try SSHCommand.validate(alias: alias)
        guard let scheme = editor.scheme, editor.supportsRemoteSSH else {
            throw ExternalActionError.remoteSSHUnsupported
        }
        guard let encodedAlias = alias.addingPercentEncoding(withAllowedCharacters: remoteAliasAllowed),
              !encodedAlias.isEmpty else {
            throw SSHCommandError.controlCharacter
        }
        switch editor {
        case .vscode, .cursor:
            guard let url = URL(string: "\(scheme)://vscode-remote/ssh-remote+\(encodedAlias)/") else {
                throw ExternalActionError.openFailed(editor.displayName)
            }
            return url
        case .zed:
            guard let url = URL(string: "\(scheme)://ssh/\(encodedAlias)/~") else {
                throw ExternalActionError.openFailed(editor.displayName)
            }
            return url
        case .systemDefault:
            throw ExternalActionError.remoteSSHUnsupported
        }
    }

    public static func scpTemplateCommand(for alias: String) throws -> String {
        try SSHCommand.validate(alias: alias)
        let escapedAlias = alias.replacingOccurrences(of: "'", with: "'\\''")
        return "/usr/bin/scp -- <local-path> '\(escapedAlias):~/'"
    }

    public static func singleDeclaredAddress(for host: HostEntry) -> String? {
        let addresses = host.declaredValues(for: "hostname")
        return addresses.count == 1 ? addresses[0] : nil
    }

    public static func userAtHostAddress(for host: HostEntry) -> String? {
        let users = host.declaredValues(for: "user")
        let addresses = host.declaredValues(for: "hostname")
        guard users.count == 1, addresses.count == 1 else { return nil }
        return "\(users[0])@\(addresses[0])"
    }
}
