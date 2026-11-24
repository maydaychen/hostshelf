import Foundation

public struct FuzzyMatch: Equatable, Sendable {
    public let score: Int
    public let ranges: [Range<String.Index>]

    public init(score: Int, ranges: [Range<String.Index>]) {
        self.score = score
        self.ranges = ranges
    }
}

public enum FuzzyMatcher {
    private static let matchOptions: String.CompareOptions = [
        .caseInsensitive,
        .diacriticInsensitive,
        .widthInsensitive,
    ]

    public static func match(query: String, in text: String) -> FuzzyMatch? {
        let tokens = query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
        guard !tokens.isEmpty, !text.isEmpty else { return nil }

        var totalScore = 0
        var allRanges: [Range<String.Index>] = []
        for token in tokens {
            guard let matched = matchToken(token, in: text) else { return nil }
            totalScore += matched.score
            allRanges.append(contentsOf: matched.ranges)
        }
        if tokens.count > 1 {
            totalScore += 15
        }
        if text.compare(query.trimmingCharacters(in: .whitespacesAndNewlines), options: matchOptions, locale: .current) == .orderedSame {
            totalScore += 40
        }
        return FuzzyMatch(score: totalScore, ranges: mergeRanges(allRanges))
    }

    public static func scoreHost(_ host: HostEntry, annotation: HostAnnotation, query: String) -> Int? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let tokens = trimmed.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !tokens.isEmpty else { return nil }

        let hostNames = host.declaredValues(for: "hostname")
        let sourcePaths = Array(
            Set(host.locations.map(\.filePath) + host.declarations.map { $0.location.filePath })
        ).sorted()

        var totalScore = 0
        for token in tokens {
            var bestTokenScore: Int?
            func consider(_ candidate: Int?) {
                guard let candidate else { return }
                if let existing = bestTokenScore {
                    bestTokenScore = max(existing, candidate)
                } else {
                    bestTokenScore = candidate
                }
            }

            if let match = matchToken(token, in: host.alias) {
                consider(1_000 + match.score)
            }
            if !annotation.note.isEmpty, let match = matchToken(token, in: annotation.note) {
                consider(500 + match.score)
            }
            for hostName in hostNames {
                if let match = matchToken(token, in: hostName) {
                    consider(450 + match.score)
                }
            }
            if !annotation.group.isEmpty, let match = matchToken(token, in: annotation.group) {
                consider(350 + match.score)
            }
            let tagToken = token.hasPrefix("#") && token.count > 1 ? String(token.dropFirst()) : token
            for tag in annotation.tags {
                if let match = matchToken(tagToken, in: tag) {
                    consider(350 + match.score)
                }
            }
            for path in sourcePaths {
                if let match = bestContiguousMatch(token: token, in: path) {
                    consider(150 + match.score)
                }
            }

            guard let tokenScore = bestTokenScore else { return nil }
            totalScore += tokenScore
        }

        if let wholeAliasMatch = match(query: trimmed, in: host.alias) {
            totalScore += 200 + min(100, wholeAliasMatch.score)
        }
        return totalScore
    }

    public static func rankForQuickLauncher(
        hosts: [HostEntry],
        annotation: (String) -> HostAnnotation,
        query: String,
        now: Date = Date()
    ) -> [HostEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return hosts.sorted { lhs, rhs in
                let leftNote = annotation(lhs.alias)
                let rightNote = annotation(rhs.alias)
                switch (leftNote.lastLaunchedAt, rightNote.lastLaunchedAt) {
                case (let lDate?, let rDate?):
                    if lDate != rDate { return lDate > rDate }
                case (.some, .none):
                    return true
                case (.none, .some):
                    return false
                case (.none, .none):
                    break
                }
                if leftNote.isFavorite != rightNote.isFavorite {
                    return leftNote.isFavorite
                }
                return lhs.alias.localizedStandardCompare(rhs.alias) == .orderedAscending
            }
        }

        return hosts.compactMap { host -> (host: HostEntry, score: Int)? in
            let note = annotation(host.alias)
            guard let baseScore = scoreHost(host, annotation: note, query: trimmed) else { return nil }
            let favoriteBonus = note.isFavorite ? 80 : 0
            let recency = recencyBonus(note.lastLaunchedAt, now: now)
            return (host, baseScore + favoriteBonus + recency)
        }.sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.host.alias.localizedStandardCompare(rhs.host.alias) == .orderedAscending
        }.map(\.host)
    }

    private static func recencyBonus(_ launchedAt: Date?, now: Date) -> Int {
        guard let launchedAt else { return 0 }
        let age = max(0, now.timeIntervalSince(launchedAt))
        if age <= 3_600 { return 120 }
        if age <= 86_400 { return 90 }
        if age <= 604_800 { return 60 }
        if age <= 2_592_000 { return 30 }
        return 15
    }

    private static func matchToken(_ token: String, in text: String) -> (score: Int, ranges: [Range<String.Index>])? {
        guard !token.isEmpty, !text.isEmpty else { return nil }

        if let bestContiguous = bestContiguousMatch(token: token, in: text) {
            return bestContiguous
        }
        return subsequenceMatch(token: token, in: text)
    }

    private static func bestContiguousMatch(token: String, in text: String) -> (score: Int, ranges: [Range<String.Index>])? {
        var best: (score: Int, range: Range<String.Index>)?
        var searchRange = text.startIndex..<text.endIndex
        while let match = text.range(of: token, options: matchOptions, range: searchRange, locale: .current) {
            guard !match.isEmpty else { break }
            let score: Int
            if match.lowerBound == text.startIndex && match.upperBound == text.endIndex {
                score = 220
            } else if match.lowerBound == text.startIndex {
                score = 170
            } else if isWordBoundary(at: match.lowerBound, in: text) {
                score = 140
            } else {
                score = 100
            }
            let lengthPenalty = min(30, max(0, text.count - token.count))
            let total = score - lengthPenalty
            if best == nil || total > best!.score {
                best = (total, match)
            }
            searchRange = match.upperBound..<text.endIndex
        }
        return best.map { ($0.score, [$0.range]) }
    }

    private struct TextUnit {
        let folded: Character
        let range: Range<String.Index>
        let isBoundary: Bool
    }

    private static func subsequenceMatch(token: String, in text: String) -> (score: Int, ranges: [Range<String.Index>])? {
        let tokenUnits = foldedCharacters(of: token)
        let textUnits = foldedTextUnits(of: text)
        let m = tokenUnits.count
        let n = textUnits.count
        guard m > 0, n >= m else { return nil }

        if m <= 64 && n <= 256 {
            return optimalSubsequenceMatch(tokenUnits: tokenUnits, textUnits: textUnits)
        }
        return greedySubsequenceMatch(tokenUnits: tokenUnits, textUnits: textUnits)
    }

    private static func optimalSubsequenceMatch(tokenUnits: [Character], textUnits: [TextUnit]) -> (score: Int, ranges: [Range<String.Index>])? {
        let m = tokenUnits.count
        let n = textUnits.count
        let negInf = Int.min / 4
        var prev = [Int](repeating: negInf, count: n)
        var parents = [Int16](repeating: -1, count: m * n)

        for j in 0..<n where textUnits[j].folded == tokenUnits[0] {
            let boundaryBonus = textUnits[j].isBoundary ? 16 : 0
            let startBonus = j == 0 ? 12 : 0
            let leadPenalty = min(20, j)
            prev[j] = 10 + boundaryBonus + startBonus - leadPenalty
        }

        if m > 1 {
            for i in 1..<m {
                var curr = [Int](repeating: negInf, count: n)
                var bestNonAdj = negInf
                var bestNonAdjIdx = -1

                for j in 0..<n {
                    if j >= 2 {
                        let k = j - 2
                        if prev[k] > negInf / 2 {
                            let candidate = prev[k] + 2 * k
                            if candidate > bestNonAdj {
                                bestNonAdj = candidate
                                bestNonAdjIdx = k
                            }
                        }
                    }
                    guard textUnits[j].folded == tokenUnits[i] else { continue }
                    let base = 10 + (textUnits[j].isBoundary ? 16 : 0)

                    var bestScore = negInf
                    var bestParent = -1

                    if j >= 1 && prev[j - 1] > negInf / 2 {
                        let adjScore = prev[j - 1] + 22 + base
                        bestScore = adjScore
                        bestParent = j - 1
                    }
                    if bestNonAdjIdx >= 0 {
                        let gapScore = bestNonAdj - 2 * (j - 1) + base
                        if gapScore > bestScore {
                            bestScore = gapScore
                            bestParent = bestNonAdjIdx
                        }
                    }
                    if bestParent >= 0 {
                        curr[j] = bestScore
                        parents[i * n + j] = Int16(bestParent)
                    }
                }
                prev = curr
            }
        }

        var bestEnd = -1
        var bestScore = negInf
        for j in 0..<n where prev[j] > bestScore {
            bestScore = prev[j]
            bestEnd = j
        }
        guard bestEnd >= 0, bestScore > negInf / 2 else { return nil }

        var matchedIndices = [Int](repeating: 0, count: m)
        var cursor = bestEnd
        for i in stride(from: m - 1, through: 0, by: -1) {
            matchedIndices[i] = cursor
            cursor = Int(parents[i * n + cursor])
        }

        let lengthPenalty = min(30, max(0, textUnits.count - m))
        let ranges = mergeRanges(matchedIndices.map { textUnits[$0].range })
        return (max(1, bestScore - lengthPenalty), ranges)
    }

    private static func greedySubsequenceMatch(tokenUnits: [Character], textUnits: [TextUnit]) -> (score: Int, ranges: [Range<String.Index>])? {
        var matched: [Range<String.Index>] = []
        matched.reserveCapacity(tokenUnits.count)
        var tokenIndex = 0
        var score = 0
        var lastMatch = -2

        for (index, unit) in textUnits.enumerated() where unit.folded == tokenUnits[tokenIndex] {
            score += 10
            if unit.isBoundary { score += 16 }
            if index == lastMatch + 1 { score += 18 }
            lastMatch = index
            matched.append(unit.range)
            tokenIndex += 1
            if tokenIndex == tokenUnits.count { break }
        }
        guard tokenIndex == tokenUnits.count else { return nil }
        return (max(1, score), mergeRanges(matched))
    }

    private static func foldedCharacters(of value: String) -> [Character] {
        var result: [Character] = []
        for character in value {
            let folded = String(character).folding(options: matchOptions, locale: .current)
            if folded.isEmpty {
                result.append(character)
            } else {
                result.append(contentsOf: folded)
            }
        }
        return result
    }

    private static func foldedTextUnits(of text: String) -> [TextUnit] {
        var units: [TextUnit] = []
        var index = text.startIndex
        while index < text.endIndex {
            let next = text.index(after: index)
            let range = index..<next
            let boundary = isWordBoundary(at: index, in: text)
            let folded = String(text[index]).folding(options: matchOptions, locale: .current)
            if folded.isEmpty {
                units.append(TextUnit(folded: text[index], range: range, isBoundary: boundary))
            } else {
                for (offset, char) in folded.enumerated() {
                    units.append(TextUnit(folded: char, range: range, isBoundary: offset == 0 && boundary))
                }
            }
            index = next
        }
        return units
    }

    private static func isWordBoundary(at index: String.Index, in text: String) -> Bool {
        if index == text.startIndex { return true }
        let prev = text[text.index(before: index)]
        let curr = text[index]
        if prev.isWhitespace || "-_./:@".contains(prev) { return true }
        return prev.isLowercase && curr.isUppercase
    }

    private static func mergeRanges(_ raw: [Range<String.Index>]) -> [Range<String.Index>] {
        let sorted = raw.sorted {
            if $0.lowerBound != $1.lowerBound { return $0.lowerBound < $1.lowerBound }
            return $0.upperBound < $1.upperBound
        }
        var merged: [Range<String.Index>] = []
        for range in sorted {
            if let last = merged.last, range.lowerBound <= last.upperBound {
                merged[merged.count - 1] = last.lowerBound..<max(last.upperBound, range.upperBound)
            } else {
                merged.append(range)
            }
        }
        return merged
    }
}
