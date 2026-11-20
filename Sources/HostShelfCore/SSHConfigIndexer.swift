import Foundation
import Darwin

/// Reads declarations only. It never executes ssh, Match predicates or identity files.
public struct SSHConfigIndexer: Sendable {
    private let homeDirectory: URL
    private let environment: [String: String]
    private let systemDirectory: URL

    public init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.init(homeDirectory: homeDirectory, environment: environment, systemDirectory: URL(fileURLWithPath: "/etc/ssh"))
    }

    init(homeDirectory: URL, environment: [String: String], systemDirectory: URL) {
        self.homeDirectory = homeDirectory
        self.environment = environment
        self.systemDirectory = systemDirectory.standardizedFileURL
    }

    public func scan(roots: [URL]? = nil) -> SSHIndexSnapshot {
        var scanner = Scanner(homeDirectory: homeDirectory, environment: environment)
        for root in roots ?? [homeDirectory.appendingPathComponent(".ssh/config"), systemDirectory.appendingPathComponent("ssh_config")] {
            var section = Scanner.Section()
            let path = root.standardizedFileURL.path
            let isSystem = path.hasPrefix(systemDirectory.path + "/")
                || (systemDirectory.path == "/etc/ssh" && path.hasPrefix("/private/etc/ssh/"))
            let base = isSystem ? systemDirectory : homeDirectory.appendingPathComponent(".ssh")
            scanner.read(root, origin: ConfigurationOrigin(base: base, isSystem: isSystem), section: &section,
                         inheritedCondition: false, chain: [])
        }
        return scanner.snapshot()
    }
}

private struct ConfigurationOrigin {
    let base: URL
    let isSystem: Bool
}

private struct Scanner {
    struct Section {
        var aliases: [String] = []
        var isConditional = false
        var isScoped = false
    }

    let homeDirectory: URL
    let environment: [String: String]
    var hosts: [String: HostEntry] = [:]
    var rules: [SSHRule] = []
    var diagnostics: [IndexDiagnostic] = []
    var includes: [IncludeRecord] = []
    var sources: Set<String> = []
    var sourceIdentities: [String: SourceIdentity] = [:]
    private var fileVisits = 0

    init(homeDirectory: URL, environment: [String: String]) {
        self.homeDirectory = homeDirectory
        self.environment = environment
    }

    func snapshot() -> SSHIndexSnapshot {
        SSHIndexSnapshot(hosts: hosts.values.sorted { $0.alias < $1.alias }, rules: rules, diagnostics: diagnostics,
                         includes: includes, sources: sources.sorted(), sourceIdentities: sourceIdentities)
    }

    mutating func read(_ input: URL, origin: ConfigurationOrigin, section: inout Section, inheritedCondition: Bool, chain: [String]) {
        let url = input.standardizedFileURL
        let path = url.path
        let realPath = url.resolvingSymlinksInPath().path
        sources.insert(path)
        let location = SourceLocation(filePath: path, line: 1)
        guard !chain.contains(realPath) else {
            diagnose("检测到 Include 循环，已停止展开此分支。", at: location)
            return
        }
        guard chain.count < 64, fileVisits < 10_000 else {
            diagnose("配置展开超过安全上限，已停止此分支。", at: location)
            return
        }
        fileVisits += 1
        do {
            let (data, identity) = try ConfigurationFile.read(path, expectedIdentity: sourceIdentities[path])
            guard var text = String(data: data, encoding: .utf8) else {
                diagnose("配置文件不是有效的 UTF-8 文本，未解析。", at: location)
                return
            }
            sourceIdentities[path] = identity
            if text.first == "\u{FEFF}" { text.removeFirst() }
            for (index, rawLine) in text.components(separatedBy: "\n").enumerated() {
                let line = rawLine.hasSuffix("\r") ? String(rawLine.dropLast()) : rawLine
                let lineLocation = SourceLocation(filePath: path, line: index + 1)
                do {
                    guard let parsed = try SSHConfigLexer.parse(line) else { continue }
                    consume(parsed, at: lineLocation, origin: origin, section: &section,
                            inheritedCondition: inheritedCondition, chain: chain + [realPath])
                } catch {
                    diagnose("引号或转义未闭合，此行未解析。", at: lineLocation)
                }
            }
        } catch {
            diagnose("无法读取配置文件：\(error.localizedDescription)", at: location)
        }
    }

    private mutating func consume(_ line: SSHConfigLexer.Line, at location: SourceLocation, origin: ConfigurationOrigin,
                                  section: inout Section, inheritedCondition: Bool, chain: [String]) {
        switch line.keyword {
        case "host":
            guard !line.arguments.isEmpty else {
                diagnose("Host 缺少主机模式。", at: location)
                section = Section()
                return
            }
            let explicit = line.arguments.filter { !$0.isEmpty && !$0.hasPrefix("!") && !$0.contains("*") && !$0.contains("?") }
            let hasRules = explicit.count != line.arguments.count
            if hasRules { rules.append(SSHRule(kind: "Host", expression: line.value, location: location)) }
            let conditional = inheritedCondition || line.arguments.contains { $0.hasPrefix("!") }
            section = Section(aliases: Array(Set(explicit)).sorted(), isConditional: conditional, isScoped: true)
            for alias in section.aliases {
                if var entry = hosts[alias] {
                    if !entry.locations.contains(location) { entry.locations.append(location) }
                    entry.isConditional = entry.isConditional && conditional
                    hosts[alias] = entry
                } else {
                    hosts[alias] = HostEntry(alias: alias, locations: [location], isConditional: conditional)
                }
            }
        case "match":
            rules.append(SSHRule(kind: "Match", expression: line.value, location: location))
            section = Section(isConditional: true, isScoped: true)
            if line.arguments.isEmpty { diagnose("Match 缺少条件。", at: location) }
        case "include":
            guard !line.arguments.isEmpty else {
                diagnose("Include 缺少配置路径。", at: location)
                return
            }
            let conditional = inheritedCondition || section.isScoped
            for expression in line.arguments {
                guard let pattern = expand(expression, origin: origin, at: location) else {
                    includes.append(IncludeRecord(location: location, expression: expression, resolvedPaths: [], isConditional: conditional))
                    continue
                }
                let paths = matchingPaths(pattern, at: location)
                includes.append(IncludeRecord(location: location, expression: expression,
                                              resolvedPaths: paths, isConditional: conditional))
                for path in paths {
                    // OpenSSH restores the caller's Host/Match context after every included file.
                    var includedSection = section
                    read(URL(fileURLWithPath: path), origin: origin, section: &includedSection,
                         inheritedCondition: conditional, chain: chain)
                }
            }
        default:
            guard !line.arguments.isEmpty else {
                diagnose("\(line.keyword) 缺少参数。", at: location)
                return
            }
            for alias in section.aliases {
                let declaration = SSHDeclaration(keyword: line.keyword, value: line.value, location: location,
                                                 isConditional: section.isConditional || inheritedCondition)
                if hosts[alias]?.declarations.contains(declaration) == false {
                    hosts[alias]?.declarations.append(declaration)
                }
            }
        }
    }

    private mutating func expand(_ expression: String, origin: ConfigurationOrigin, at location: SourceLocation) -> String? {
        guard !expression.isEmpty, !expression.contains("\0") else {
            diagnose("Include 路径为空或包含无效字符。", at: location)
            return nil
        }
        var result = ""
        let characters = Array(expression)
        var index = 0
        while index < characters.count {
            if characters[index] == "%" {
                guard index + 1 < characters.count else {
                    diagnose("Include 含有无法静态展开的 token。", at: location)
                    return nil
                }
                switch characters[index + 1] {
                case "%": result.append("%")
                case "d": result += homeDirectory.path
                default:
                    diagnose("Include 含有依赖连接上下文的 token，未展开：\(expression)", at: location)
                    return nil
                }
                index += 2
            } else if characters[index] == "$", index + 1 < characters.count, characters[index + 1] == "{" {
                guard let end = characters[(index + 2)...].firstIndex(of: "}") else {
                    diagnose("Include 环境变量未闭合。", at: location)
                    return nil
                }
                let name = String(characters[(index + 2)..<end])
                guard let value = environment[name] else {
                    diagnose("Include 所需环境变量未定义：\(name)", at: location)
                    return nil
                }
                result += value
                index = end + 1
            } else {
                result.append(characters[index])
                index += 1
            }
        }
        if origin.isSystem && result.hasPrefix("~") {
            diagnose("系统配置中的 Include 不支持以 ~ 开头的路径。", at: location)
            return nil
        }
        if result == "~" { result = homeDirectory.path }
        else if result.hasPrefix("~/") { result = homeDirectory.path + result.dropFirst() }
        else if result.hasPrefix("~") {
            let slash = result.firstIndex(of: "/") ?? result.endIndex
            let user = String(result[result.index(after: result.startIndex)..<slash])
            guard let userHome = NSHomeDirectoryForUser(user) else {
                diagnose("Include 中的用户目录无法展开。", at: location)
                return nil
            }
            result = userHome + result[slash...]
        }
        if !result.hasPrefix("/") { result = origin.base.appendingPathComponent(result).path }
        return URL(fileURLWithPath: result).standardizedFileURL.path
    }

    private mutating func matchingPaths(_ pattern: String, at location: SourceLocation) -> [String] {
        let result = globPaths(pattern, flags: GLOB_NOSORT | GLOB_ERR)
        switch result.status {
        case 0:
            return result.paths
        case GLOB_NOMATCH:
            diagnose("Include 未匹配任何配置文件，已跳过。", at: location, severity: .information)
        case GLOB_ABORTED:
            diagnose("Include 无法遍历部分路径，已继续查找可读取的匹配项。", at: location)
            return globPaths(pattern, flags: GLOB_NOSORT).paths
        default:
            diagnose("Include 路径展开失败，未读取。", at: location)
        }
        return []
    }

    private func globPaths(_ pattern: String, flags: Int32) -> (status: Int32, paths: [String]) {
        var matches = glob_t()
        let status = pattern.withCString { Darwin.glob($0, flags, nil, &matches) }
        defer { globfree(&matches) }
        guard status == 0 else { return (status, []) }
        let paths = (0..<Int(matches.gl_pathc)).compactMap { index in
            matches.gl_pathv[index].map { String(cString: $0) }
        }.sorted()
        return (status, paths)
    }

    private mutating func diagnose(_ message: String, at location: SourceLocation, severity: IndexDiagnosticSeverity = .warning) {
        diagnostics.append(IndexDiagnostic(message: message, location: location, severity: severity))
    }
}
