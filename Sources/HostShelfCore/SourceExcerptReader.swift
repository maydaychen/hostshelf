import Foundation

public struct SourceExcerpt: Identifiable, Sendable {
    public var id: String { location.id }
    public let location: SourceLocation
    public let lines: [ExcerptLine]
    public let error: String?

    public init(location: SourceLocation, lines: [ExcerptLine], error: String?) {
        self.location = location
        self.lines = lines
        self.error = error
    }
}

public struct ExcerptLine: Identifiable, Sendable {
    public var id: Int { number }
    public let number: Int
    public let text: String
    public let isDeclaration: Bool

    public init(number: Int, text: String, isDeclaration: Bool) {
        self.number = number
        self.text = text
        self.isDeclaration = isDeclaration
    }
}

public enum SourceExcerptReader {
    public static func read(
        for host: HostEntry,
        sourceIdentities: [String: SourceIdentity],
        shouldCancel: () -> Bool = { false }
    ) -> [SourceExcerpt] {
        let locations = Set(host.locations + host.declarations.map(\.location))
        let files = Dictionary(grouping: locations, by: \.filePath)

        var results: [SourceExcerpt] = []
        for filePath in files.keys.sorted() {
            if shouldCancel() { break }
            let anchors = files[filePath]!.sorted { $0.line < $1.line }
            let location = anchors[0]
            guard let identity = sourceIdentities[filePath] else {
                results.append(SourceExcerpt(location: location, lines: [], error: "此路径不在已读取配置来源中。请手动刷新配置。"))
                continue
            }

            do {
                let (data, _) = try ConfigurationFile.read(filePath, expectedIdentity: identity)
                guard var text = String(data: data, encoding: .utf8) else {
                    results.append(SourceExcerpt(location: location, lines: [], error: "来源片段读取失败：文件不是有效的 UTF-8 文本。请手动刷新配置。"))
                    continue
                }
                if text.first == "\u{FEFF}" { text.removeFirst() }
                let lines = text.components(separatedBy: "\n").map {
                    $0.hasSuffix("\r") ? String($0.dropLast()) : $0
                }
                let validAnchors = anchors.filter { $0.line >= 1 && $0.line <= lines.count }
                let invalidAnchors = anchors.filter { $0.line < 1 || $0.line > lines.count }
                let declarationLines = Set(validAnchors.map(\.line))
                var includedLines = Set<Int>()
                for anchor in validAnchors {
                    let lower = max(1, anchor.line - 2)
                    let upper = min(lines.count, anchor.line + 2)
                    includedLines.formUnion(lower...upper)
                }
                let excerpt = includedLines.sorted().map { number in
                    ExcerptLine(number: number, text: lines[number - 1], isDeclaration: declarationLines.contains(number))
                }
                let error: String?
                if invalidAnchors.isEmpty {
                    error = nil
                } else {
                    let numbers = invalidAnchors.map { String($0.line) }.joined(separator: "、")
                    error = "来源已变化：第 \(numbers) 行超出当前文件范围（共 \(lines.count) 行），请刷新配置。"
                }
                results.append(SourceExcerpt(location: location, lines: excerpt, error: error))
            } catch {
                results.append(SourceExcerpt(location: location, lines: [], error: "来源片段读取失败：\(error.localizedDescription)\n请手动刷新配置。"))
            }
        }
        return results
    }
}
