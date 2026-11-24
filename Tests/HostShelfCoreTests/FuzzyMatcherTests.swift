import XCTest
@testable import HostShelfCore

final class FuzzyMatcherTests: XCTestCase {
    func testSubsequenceMatchPreservesOriginalIndicesAndMergesAdjacentRanges() {
        guard let matched = FuzzyMatcher.match(query: "prodhk", in: "prod-ap-hk-01") else {
            return XCTFail("Expected subsequence match")
        }
        let highlighted = matched.ranges.map { String("prod-ap-hk-01"[$0]) }.joined()
        XCTAssertEqual(highlighted, "prodhk")
        XCTAssertEqual(matched.ranges.count, 2)
    }

    func testEmptyAndWhitespaceQueriesReturnNil() {
        XCTAssertNil(FuzzyMatcher.match(query: "", in: "alpha"))
        XCTAssertNil(FuzzyMatcher.match(query: "   \n ", in: "alpha"))
        XCTAssertNil(FuzzyMatcher.scoreHost(HostEntry(alias: "alpha"), annotation: HostAnnotation(), query: "   "))
    }

    func testExactAndPrefixOutrankMidStringMatch() {
        let exact = FuzzyMatcher.match(query: "web", in: "web")
        let prefix = FuzzyMatcher.match(query: "web", in: "web-prod-01")
        let mid = FuzzyMatcher.match(query: "web", in: "api-web-01")
        XCTAssertNotNil(exact)
        XCTAssertNotNil(prefix)
        XCTAssertNotNil(mid)
        XCTAssertGreaterThan(exact!.score, prefix!.score)
        XCTAssertGreaterThan(prefix!.score, mid!.score)
    }

    func testScoreHostSupportsMultiTokenAcrossFieldsAndRejectsMissingToken() {
        let loc = SourceLocation(filePath: "/tmp/ssh/work.conf", line: 10)
        let host = HostEntry(
            alias: "app-node-01",
            locations: [loc],
            declarations: [SSHDeclaration(keyword: "hostname", value: "10.0.1.50", location: loc)]
        )
        let note = HostAnnotation(group: "生产环境", note: "东京核心支付")
        XCTAssertNotNil(FuzzyMatcher.scoreHost(host, annotation: note, query: "app 支付"))
        XCTAssertNotNil(FuzzyMatcher.scoreHost(host, annotation: note, query: "生产 10.0.1"))
        XCTAssertNil(FuzzyMatcher.scoreHost(host, annotation: note, query: "app 不存在"))
    }

    func testScoreHostRequiresContiguousMatchOnSourcePaths() {
        let loc = SourceLocation(filePath: "/Users/demo/Apple/Mac/.tmp/work/config", line: 1)
        let host = HostEntry(alias: "beta", locations: [loc])
        XCTAssertNil(FuzzyMatcher.scoreHost(host, annotation: HostAnnotation(), query: "gamma"))
        XCTAssertNotNil(FuzzyMatcher.scoreHost(host, annotation: HostAnnotation(), query: "work/config"))
    }

    func testQuickLauncherRankingForEmptyAndActiveQueries() {
        let now = Date(timeIntervalSince1970: 10_000)
        let alpha = HostEntry(alias: "alpha-web")
        let beta = HostEntry(alias: "beta-web")
        let gamma = HostEntry(alias: "gamma-db")
        let annotations: [String: HostAnnotation] = [
            "alpha-web": HostAnnotation(isFavorite: true),
            "beta-web": HostAnnotation(lastLaunchedAt: now.addingTimeInterval(-60)),
            "gamma-db": HostAnnotation(),
        ]

        let emptyRanked = FuzzyMatcher.rankForQuickLauncher(
            hosts: [alpha, gamma, beta],
            annotation: { annotations[$0] ?? HostAnnotation() },
            query: "",
            now: now
        )
        XCTAssertEqual(emptyRanked.map(\.alias), ["beta-web", "alpha-web", "gamma-db"])

        let queryRanked = FuzzyMatcher.rankForQuickLauncher(
            hosts: [gamma, alpha, beta],
            annotation: { annotations[$0] ?? HostAnnotation() },
            query: "web",
            now: now
        )
        XCTAssertEqual(queryRanked.map(\.alias), ["beta-web", "alpha-web"])
    }
}
