import AppKit
import Carbon
import HostShelfCore

enum TerminalAvailability: Equatable {
    case available
    case notInstalled
    case unsupportedVersion

    var isAvailable: Bool { self == .available }

    var unavailableReason: String? {
        switch self {
        case .available: return nil
        case .notInstalled: return "未安装"
        case .unsupportedVersion: return "需要 1.3.0 或更新版本"
        }
    }
}

enum TerminalLaunchError: LocalizedError {
    case unavailable(TerminalTarget, TerminalAvailability)
    case scriptUnavailable(TerminalTarget)
    case automationDenied(TerminalTarget)
    case failed(TerminalTarget)

    var errorDescription: String? {
        switch self {
        case .unavailable(let target, let availability):
            return "无法使用 \(target.displayName)：\(availability.unavailableReason ?? "不可用")。请在设置中选择可用终端。"
        case .scriptUnavailable(let target):
            return "无法准备 \(target.displayName) 的启动脚本，请检查应用版本及自动化支持。"
        case .automationDenied(let target):
            return "未获准控制 \(target.displayName)。请在“系统设置 → 隐私与安全性 → 自动化”中允许 HostShelf 控制 \(target.displayName)，或复制连接命令。"
        case .failed(let target):
            return "无法将连接交给 \(target.displayName)。请检查终端是否可用、是否开启 AppleScript 支持，或复制连接命令。"
        }
    }
}

@MainActor
public final class TerminalLauncher {
    typealias ScriptExecutor = @Sendable (String, TerminalTarget) throws -> Void
    private nonisolated static let executionQueue = DispatchQueue(label: "HostShelf.TerminalLauncher", qos: .userInitiated)
    private let execute: ScriptExecutor
    private let checkAvailability: @MainActor (TerminalTarget) -> TerminalAvailability

    public init() {
        execute = { alias, target in try Self.executeScript(alias: alias, target: target) }
        checkAvailability = Self.availability(for:)
    }

    init(execute: @escaping ScriptExecutor,
         availability: @escaping @MainActor (TerminalTarget) -> TerminalAvailability) {
        self.execute = execute
        checkAvailability = availability
    }

    static func availability(for target: TerminalTarget) -> TerminalAvailability {
        availability(for: target, applicationURL: NSWorkspace.shared.urlForApplication(withBundleIdentifier: target.bundleIdentifier))
    }

    static func availability(for target: TerminalTarget, applicationURL: URL?) -> TerminalAvailability {
        guard let applicationURL, let bundle = Bundle(url: applicationURL),
              bundle.bundleIdentifier == target.bundleIdentifier else { return .notInstalled }
        if target == .ghostty,
           !supportsGhosttyVersion(bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) {
            return .unsupportedVersion
        }
        return .available
    }

    static func supportsGhosttyVersion(_ version: String?) -> Bool {
        guard let version else { return false }
        let parts = version.split(separator: ".", omittingEmptySubsequences: false)
        guard (2...3).contains(parts.count), parts.allSatisfy({
            $0.utf8.allSatisfy { (48...57).contains($0) } && Int($0) != nil
        }) else { return false }
        let numbers = parts.map { Int($0)! }
        return numbers[0] > 1 || (numbers[0] == 1 && numbers[1] >= 3)
    }

    // Only fixed application code enters the source. The host is an AppleEvent parameter.
    nonisolated static func scriptSource(for target: TerminalTarget) -> String {
        let body: String
        switch target {
        case .terminal:
            body = """
            tell application id "com.apple.Terminal"
                do script connectionCommand
                activate
            end tell
            """
        case .iterm2:
            body = """
            tell application id "com.googlecode.iterm2"
                create window with default profile command connectionCommand
                activate
            end tell
            """
        case .ghostty:
            body = """
            tell application id "com.mitchellh.ghostty"
                set cfg to new surface configuration
                set command of cfg to "shell:" & connectionCommand
                set wait after command of cfg to true
                new window with configuration cfg
                activate
            end tell
            """
        }
        return """
        on connectHost(hostAlias)
            set connectionCommand to "/usr/bin/ssh -- " & quoted form of hostAlias
            \(body)
        end connectHost
        """
    }

    nonisolated static func connectionEvent(alias: String) -> NSAppleEventDescriptor {
        let arguments = NSAppleEventDescriptor.list()
        arguments.insert(NSAppleEventDescriptor(string: alias), at: 1)
        let event = NSAppleEventDescriptor(
            eventClass: AEEventClass(kASAppleScriptSuite), eventID: AEEventID(kASSubroutineEvent),
            targetDescriptor: nil, returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID)
        )
        event.setParam(NSAppleEventDescriptor(string: "connecthost"), forKeyword: AEKeyword(keyASSubroutineName))
        event.setParam(arguments, forKeyword: AEKeyword(keyDirectObject))
        return event
    }

    public func launch(alias: String, target: TerminalTarget = .terminal) async throws {
        try SSHCommand.validate(alias: alias)
        let availability = checkAvailability(target)
        guard availability.isAvailable else { throw TerminalLaunchError.unavailable(target, availability) }
        let execute = execute
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            Self.executionQueue.async {
                do {
                    try autoreleasepool { try execute(alias, target) }
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // Script and descriptor objects remain confined to the serial execution queue.
    private nonisolated static func executeScript(alias: String, target: TerminalTarget) throws {
        guard let script = NSAppleScript(source: Self.scriptSource(for: target)) else {
            throw TerminalLaunchError.scriptUnavailable(target)
        }
        var error: NSDictionary?
        guard script.compileAndReturnError(&error) else {
            throw TerminalLaunchError.scriptUnavailable(target)
        }
        script.executeAppleEvent(Self.connectionEvent(alias: alias), error: &error)
        if let error {
            if (error[NSAppleScript.errorNumber] as? NSNumber)?.intValue == -1743 {
                throw TerminalLaunchError.automationDenied(target)
            }
            throw TerminalLaunchError.failed(target)
        }
    }
}
