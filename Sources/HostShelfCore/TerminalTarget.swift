import Foundation

public enum SSHLaunchMode: String, Sendable, Equatable {
    case interactive
    case tunnelOnly
}

public enum TerminalTarget: String, CaseIterable, Identifiable, Sendable {
    case terminal
    case iterm2
    case ghostty

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .terminal: return "Terminal"
        case .iterm2: return "iTerm2"
        case .ghostty: return "Ghostty"
        }
    }

    public var bundleIdentifier: String {
        switch self {
        case .terminal: return "com.apple.Terminal"
        case .iterm2: return "com.googlecode.iterm2"
        case .ghostty: return "com.mitchellh.ghostty"
        }
    }
}
