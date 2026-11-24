import Foundation

public struct JumpHop: Equatable, Hashable, Sendable {
    public let target: String
    public let indexedAlias: String?
    public let isConditional: Bool

    public init(target: String, indexedAlias: String? = nil, isConditional: Bool = false) {
        self.target = target
        self.indexedAlias = indexedAlias
        self.isConditional = isConditional
    }
}

public struct ProxyJumpAnalysis: Equatable, Sendable {
    public let chains: [[JumpHop]]
    public let proxyCommands: [SSHDeclaration]
    public let hasCycle: Bool

    public var isEmpty: Bool {
        chains.isEmpty && proxyCommands.isEmpty
    }

    public init(chains: [[JumpHop]] = [], proxyCommands: [SSHDeclaration] = [], hasCycle: Bool = false) {
        self.chains = chains
        self.proxyCommands = proxyCommands
        self.hasCycle = hasCycle
    }
}

public enum ForwardKind: String, Equatable, Hashable, Sendable {
    case local
    case remote
    case dynamic

    public var displayName: String {
        switch self {
        case .local: return "本地转发"
        case .remote: return "远程转发"
        case .dynamic: return "动态代理"
        }
    }

    public var directiveName: String {
        switch self {
        case .local: return "LocalForward"
        case .remote: return "RemoteForward"
        case .dynamic: return "DynamicForward"
        }
    }
}

public struct PortForwardRule: Equatable, Hashable, Identifiable, Sendable {
    public var id: String { "\(location.id):\(kind.rawValue):\(rawValue)" }
    public let kind: ForwardKind
    public let bindDisplay: String
    public let destinationDisplay: String?
    public let localPort: Int?
    public let localBrowserURL: URL?
    public let location: SourceLocation
    public let isConditional: Bool
    public let rawValue: String

    public init(
        kind: ForwardKind,
        bindDisplay: String,
        destinationDisplay: String?,
        localPort: Int?,
        localBrowserURL: URL?,
        location: SourceLocation,
        isConditional: Bool,
        rawValue: String
    ) {
        self.kind = kind
        self.bindDisplay = bindDisplay
        self.destinationDisplay = destinationDisplay
        self.localPort = localPort
        self.localBrowserURL = localBrowserURL
        self.location = location
        self.isConditional = isConditional
        self.rawValue = rawValue
    }
}

public enum SSHTopologyAnalyzer {
    private static let maximumJumpDepth = 8

    public static func analyzeJumps(
        for host: HostEntry,
        allHosts: [String: HostEntry]
    ) -> ProxyJumpAnalysis {
        let proxyCommands = host.declarations.filter {
            $0.keyword.lowercased() == "proxycommand"
        }
        let proxyJumps = host.declarations.filter {
            $0.keyword.lowercased() == "proxyjump"
        }

        var chains: [[JumpHop]] = []
        var hasCycle = false
        for declaration in proxyJumps {
            let tokens = declaration.value
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            guard !tokens.isEmpty else { continue }
            if tokens.count == 1 && tokens[0].caseInsensitiveCompare("none") == .orderedSame {
                continue
            }
            var chain: [JumpHop] = []
            let ancestors: Set<String> = [host.alias]
            for token in tokens where token.caseInsensitiveCompare("none") != .orderedSame {
                appendExpandedHop(
                    token,
                    isConditional: declaration.isConditional,
                    allHosts: allHosts,
                    depth: 0,
                    ancestors: ancestors,
                    chain: &chain,
                    hasCycle: &hasCycle
                )
            }
            if !chain.isEmpty {
                chains.append(chain)
            }
        }
        return ProxyJumpAnalysis(chains: chains, proxyCommands: proxyCommands, hasCycle: hasCycle)
    }

    public static func portForwards(for host: HostEntry) -> [PortForwardRule] {
        host.declarations.compactMap { declaration in
            switch declaration.keyword.lowercased() {
            case "localforward":
                return parseForward(kind: .local, declaration: declaration)
            case "remoteforward":
                return parseForward(kind: .remote, declaration: declaration)
            case "dynamicforward":
                return parseForward(kind: .dynamic, declaration: declaration)
            default:
                return nil
            }
        }
    }

    private static func appendExpandedHop(
        _ token: String,
        isConditional: Bool,
        allHosts: [String: HostEntry],
        depth: Int,
        ancestors: Set<String>,
        chain: inout [JumpHop],
        hasCycle: inout Bool
    ) {
        let hostName = extractHostName(fromJumpToken: token)
        let matched = allHosts[hostName]?.alias
        if let matched {
            if ancestors.contains(matched) {
                hasCycle = true
                chain.append(JumpHop(target: token, indexedAlias: matched, isConditional: isConditional))
                return
            }
            if depth < maximumJumpDepth, let hopEntry = allHosts[matched] {
                let nextAncestors = ancestors.union([matched])
                let upstream = firstActiveJumpTokens(in: hopEntry)
                for upstreamToken in upstream {
                    appendExpandedHop(
                        upstreamToken.token,
                        isConditional: isConditional || upstreamToken.isConditional,
                        allHosts: allHosts,
                        depth: depth + 1,
                        ancestors: nextAncestors,
                        chain: &chain,
                        hasCycle: &hasCycle
                    )
                }
            }
        }
        chain.append(JumpHop(target: token, indexedAlias: matched, isConditional: isConditional))
    }

    private static func firstActiveJumpTokens(in host: HostEntry) -> [(token: String, isConditional: Bool)] {
        for declaration in host.declarations where declaration.keyword.lowercased() == "proxyjump" {
            let tokens = declaration.value
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && $0.caseInsensitiveCompare("none") != .orderedSame }
            if !tokens.isEmpty {
                return tokens.map { ($0, declaration.isConditional) }
            }
        }
        return []
    }

    private static func extractHostName(fromJumpToken token: String) -> String {
        var remainder = token
        if let atIndex = remainder.lastIndex(of: "@") {
            let afterAt = remainder[remainder.index(after: atIndex)...]
            if !afterAt.isEmpty { remainder = String(afterAt) }
        }
        if remainder.hasPrefix("[") {
            if let closeBracket = remainder.firstIndex(of: "]") {
                return String(remainder[remainder.index(after: remainder.startIndex)..<closeBracket])
            }
            return remainder
        }
        let colonCount = remainder.filter { $0 == ":" }.count
        if colonCount == 1, let colonIndex = remainder.firstIndex(of: ":") {
            return String(remainder[..<colonIndex])
        }
        return remainder
    }

    private static func parseForward(kind: ForwardKind, declaration: SSHDeclaration) -> PortForwardRule {
        let tokens = splitDirectiveTokens(declaration.value)
        let bindDisplay = tokens.first ?? declaration.value
        let destinationDisplay: String?
        switch kind {
        case .local, .remote:
            destinationDisplay = tokens.count >= 2 ? tokens[1] : nil
        case .dynamic:
            destinationDisplay = "SOCKS 代理"
        }

        let localPort = kind == .remote ? nil : parseNumericPort(from: bindDisplay)
        let browserURL: URL?
        if kind == .local, let localPort, (1...65_535).contains(localPort) {
            browserURL = URL(string: "http://127.0.0.1:\(localPort)")
        } else {
            browserURL = nil
        }

        return PortForwardRule(
            kind: kind,
            bindDisplay: bindDisplay,
            destinationDisplay: destinationDisplay,
            localPort: localPort,
            localBrowserURL: browserURL,
            location: declaration.location,
            isConditional: declaration.isConditional,
            rawValue: declaration.value
        )
    }

    private static func parseNumericPort(from bindSpec: String) -> Int? {
        guard !bindSpec.contains("/") else { return nil }
        let candidate: Substring
        if bindSpec.hasPrefix("[") {
            guard let close = bindSpec.firstIndex(of: "]") else { return nil }
            let after = bindSpec[bindSpec.index(after: close)...]
            guard after.hasPrefix(":") else { return nil }
            candidate = after.dropFirst()
        } else if let colon = bindSpec.lastIndex(of: ":") {
            let prefix = bindSpec[..<colon]
            if prefix.contains(":") { return nil }
            candidate = bindSpec[bindSpec.index(after: colon)...]
        } else {
            candidate = bindSpec[...]
        }
        guard let port = Int(candidate), (1...65_535).contains(port) else { return nil }
        return port
    }

    private static func splitDirectiveTokens(_ value: String) -> [String] {
        var result: [String] = []
        var current = ""
        var quote: Character?
        var escaping = false
        for char in value {
            if escaping {
                current.append(char)
                escaping = false
            } else if char == "\\" && quote != "'" {
                escaping = true
            } else if let active = quote {
                if char == active { quote = nil } else { current.append(char) }
            } else if char == "\"" || char == "'" {
                quote = char
            } else if char.isWhitespace {
                if !current.isEmpty {
                    result.append(current)
                    current = ""
                }
            } else {
                current.append(char)
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }
}
