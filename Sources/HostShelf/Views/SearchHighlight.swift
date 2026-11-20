import AppKit
import HostShelfCore
import SwiftUI

enum SearchHighlight {
    static func text(_ value: String, query: String) -> AttributedString {
        var result = AttributedString(value)
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return result }
        var searchRange = value.startIndex..<value.endIndex
        while let match = value.range(of: query, options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                                      range: searchRange, locale: .current) {
            guard !match.isEmpty else { break }
            if let start = AttributedString.Index(match.lowerBound, within: result),
               let end = AttributedString.Index(match.upperBound, within: result) {
                result[start..<end].backgroundColor = Color.accentColor.opacity(0.18)
                result[start..<end].inlinePresentationIntent = .stronglyEmphasized
            }
            searchRange = match.upperBound..<value.endIndex
        }
        return result
    }
}

enum HostListPresentation {
    static func subtitle(for host: HostEntry, annotation: HostAnnotation) -> String {
        guard annotation.note.isEmpty else { return annotation.note }
        let addresses = host.declaredValues(for: "hostname")
        switch addresses.count {
        case 0: return "查看配置声明"
        case 1: return addresses[0]
        default: return "多处地址声明"
        }
    }

    static func keywordColumnWidth(_ keywords: [String]) -> CGFloat {
        let font = NSFont.monospacedSystemFont(ofSize: NSFont.preferredFont(forTextStyle: .callout).pointSize, weight: .regular)
        let width = keywords.map { ($0 as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
        return min(160, max(96, ceil(width) + 4))
    }
}
