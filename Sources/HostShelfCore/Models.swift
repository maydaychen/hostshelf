import Foundation

public struct SourceLocation: Hashable, Codable, Sendable, Identifiable {
    public var filePath: String
    public var line: Int
    public var id: String { "\(filePath):\(line)" }
    public init(filePath: String, line: Int) { self.filePath = filePath; self.line = line }
}

public struct SSHDeclaration: Hashable, Sendable, Identifiable {
    public var keyword: String
    public var value: String
    public var location: SourceLocation
    public var isConditional: Bool
    public var id: String { "\(location.id):\(keyword):\(value)" }
    public init(keyword: String, value: String, location: SourceLocation, isConditional: Bool = false) {
        self.keyword = keyword; self.value = value; self.location = location; self.isConditional = isConditional
    }
}

public struct HostEntry: Sendable, Identifiable, Hashable {
    public var alias: String
    public var locations: [SourceLocation]
    public var declarations: [SSHDeclaration]
    public var isConditional: Bool
    public var id: String { alias }
    public init(alias: String, locations: [SourceLocation] = [], declarations: [SSHDeclaration] = [], isConditional: Bool = false) {
        self.alias = alias; self.locations = locations; self.declarations = declarations; self.isConditional = isConditional
    }
    public func declaredValues(for keyword: String) -> [String] {
        Array(Set(declarations.filter { $0.keyword.lowercased() == keyword.lowercased() }.map(\.value))).sorted()
    }
}

public struct SSHRule: Sendable, Identifiable, Hashable {
    public var kind: String
    public var expression: String
    public var location: SourceLocation
    public var id: String { "\(location.id):\(kind):\(expression)" }
    public init(kind: String, expression: String, location: SourceLocation) {
        self.kind = kind; self.expression = expression; self.location = location
    }
}

public enum IndexDiagnosticSeverity: Sendable, Hashable {
    case information, warning
}

public struct IndexDiagnostic: Sendable, Identifiable, Hashable {
    public var message: String
    public var location: SourceLocation
    public var severity: IndexDiagnosticSeverity
    public var id: String { "\(location.id):\(message)" }
    public init(message: String, location: SourceLocation, severity: IndexDiagnosticSeverity = .warning) {
        self.message = message; self.location = location; self.severity = severity
    }
}

public struct IncludeRecord: Sendable, Identifiable, Hashable {
    public var location: SourceLocation
    public var expression: String
    public var resolvedPaths: [String]
    public var isConditional: Bool
    public var id: String { "\(location.id):\(expression)" }
    public init(location: SourceLocation, expression: String, resolvedPaths: [String], isConditional: Bool = false) {
        self.location = location; self.expression = expression; self.resolvedPaths = resolvedPaths; self.isConditional = isConditional
    }
}

public struct SSHIndexSnapshot: Sendable {
    public var hosts: [HostEntry]
    public var rules: [SSHRule]
    public var diagnostics: [IndexDiagnostic]
    public var includes: [IncludeRecord]
    public var sources: [String]
    public var sourceIdentities: [String: SourceIdentity]
    public var scannedAt: Date
    public var hasWarnings: Bool { diagnostics.contains { $0.severity == .warning } }
    public init(hosts: [HostEntry] = [], rules: [SSHRule] = [], diagnostics: [IndexDiagnostic] = [], includes: [IncludeRecord] = [], sources: [String] = [], sourceIdentities: [String: SourceIdentity] = [:], scannedAt: Date = Date()) {
        self.hosts = hosts; self.rules = rules; self.diagnostics = diagnostics; self.includes = includes
        self.sources = sources; self.sourceIdentities = sourceIdentities; self.scannedAt = scannedAt
    }
}

public struct HostAnnotation: Codable, Equatable, Sendable {
    public var group: String
    public var note: String
    public var isFavorite: Bool
    public var lastLaunchedAt: Date?
    public init(group: String = "", note: String = "", isFavorite: Bool = false, lastLaunchedAt: Date? = nil) {
        self.group = group; self.note = note; self.isFavorite = isFavorite; self.lastLaunchedAt = lastLaunchedAt
    }
}

public struct MetadataDocument: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var annotations: [String: HostAnnotation]
    public var groups: [String]
    public init(schemaVersion: Int = 1, annotations: [String: HostAnnotation] = [:], groups: [String] = []) {
        self.schemaVersion = schemaVersion; self.annotations = annotations; self.groups = groups
    }
}
