import XCTest
@testable import HostShelfCore

final class SSHTopologyTests: XCTestCase {
    func testProxyJumpParsesUserPortIPv6AndTransitiveChains() {
        let loc = SourceLocation(filePath: "/fixture/config", line: 1)
        let edge = HostEntry(alias: "edge", locations: [loc])
        let bastion = HostEntry(
            alias: "bastion",
            locations: [loc],
            declarations: [SSHDeclaration(keyword: "ProxyJump", value: "ops@edge:2222", location: loc)]
        )
        let app = HostEntry(
            alias: "app",
            locations: [loc],
            declarations: [
                SSHDeclaration(keyword: "ProxyJump", value: "admin@[bastion]:2200, unindexed-gw", location: loc),
                SSHDeclaration(keyword: "ProxyCommand", value: "ssh -W %h:%p relay", location: loc, isConditional: true),
            ]
        )
        let hosts = ["edge": edge, "bastion": bastion, "app": app]

        let analysis = SSHTopologyAnalyzer.analyzeJumps(for: app, allHosts: hosts)
        XCTAssertFalse(analysis.isEmpty)
        XCTAssertFalse(analysis.hasCycle)
        XCTAssertEqual(analysis.chains.count, 1)
        XCTAssertEqual(analysis.chains[0], [
            JumpHop(target: "ops@edge:2222", indexedAlias: "edge", isConditional: false),
            JumpHop(target: "admin@[bastion]:2200", indexedAlias: "bastion", isConditional: false),
            JumpHop(target: "unindexed-gw", indexedAlias: nil, isConditional: false),
        ])
        XCTAssertEqual(analysis.proxyCommands.count, 1)
        XCTAssertTrue(analysis.proxyCommands[0].isConditional)
    }

    func testDiamondProxyJumpIsNotMarkedAsCycleWhileRealCycleIsDetected() {
        let loc = SourceLocation(filePath: "/fixture/config", line: 1)
        let sharedEdge = HostEntry(alias: "shared", locations: [loc])
        let hop1 = HostEntry(
            alias: "hop1",
            locations: [loc],
            declarations: [SSHDeclaration(keyword: "ProxyJump", value: "shared", location: loc)]
        )
        let hop2 = HostEntry(
            alias: "hop2",
            locations: [loc],
            declarations: [SSHDeclaration(keyword: "ProxyJump", value: "shared", location: loc)]
        )
        let diamondTarget = HostEntry(
            alias: "target",
            locations: [loc],
            declarations: [SSHDeclaration(keyword: "ProxyJump", value: "hop1,hop2", location: loc)]
        )
        let diamondHosts = ["shared": sharedEdge, "hop1": hop1, "hop2": hop2, "target": diamondTarget]
        let diamond = SSHTopologyAnalyzer.analyzeJumps(for: diamondTarget, allHosts: diamondHosts)
        XCTAssertFalse(diamond.hasCycle)
        XCTAssertEqual(diamond.chains.first?.map(\.target), ["shared", "hop1", "shared", "hop2"])

        let loopA = HostEntry(
            alias: "loop-a",
            locations: [loc],
            declarations: [SSHDeclaration(keyword: "ProxyJump", value: "loop-b", location: loc)]
        )
        let loopB = HostEntry(
            alias: "loop-b",
            locations: [loc],
            declarations: [SSHDeclaration(keyword: "ProxyJump", value: "loop-a", location: loc)]
        )
        let cycle = SSHTopologyAnalyzer.analyzeJumps(for: loopA, allHosts: ["loop-a": loopA, "loop-b": loopB])
        XCTAssertTrue(cycle.hasCycle)
    }

    func testProxyJumpNoneAndPortForwards() {
        let loc = SourceLocation(filePath: "/fixture/config", line: 12)
        let host = HostEntry(
            alias: "tunnel-box",
            locations: [loc],
            declarations: [
                SSHDeclaration(keyword: "ProxyJump", value: "none", location: loc),
                SSHDeclaration(keyword: "LocalForward", value: "8080 127.0.0.1:80", location: loc),
                SSHDeclaration(keyword: "LocalForward", value: "[::1]:8443 web.internal:443", location: loc),
                SSHDeclaration(keyword: "LocalForward", value: "/tmp/local.sock /run/remote.sock", location: loc),
                SSHDeclaration(keyword: "RemoteForward", value: "9000 localhost:3000", location: loc, isConditional: true),
                SSHDeclaration(keyword: "DynamicForward", value: "127.0.0.1:1080", location: loc),
            ]
        )

        let jumps = SSHTopologyAnalyzer.analyzeJumps(for: host, allHosts: ["tunnel-box": host])
        XCTAssertTrue(jumps.isEmpty)

        let forwards = SSHTopologyAnalyzer.portForwards(for: host)
        XCTAssertEqual(forwards.count, 5)
        XCTAssertEqual(forwards[0].kind, .local)
        XCTAssertEqual(forwards[0].localPort, 8080)
        XCTAssertEqual(forwards[0].localBrowserURL, URL(string: "http://127.0.0.1:8080"))

        XCTAssertEqual(forwards[1].localPort, 8443)
        XCTAssertEqual(forwards[1].localBrowserURL, URL(string: "http://127.0.0.1:8443"))

        XCTAssertNil(forwards[2].localPort)
        XCTAssertNil(forwards[2].localBrowserURL)

        XCTAssertEqual(forwards[3].kind, .remote)
        XCTAssertNil(forwards[3].localPort)
        XCTAssertNil(forwards[3].localBrowserURL)
        XCTAssertTrue(forwards[3].isConditional)

        XCTAssertEqual(forwards[4].kind, .dynamic)
        XCTAssertEqual(forwards[4].localPort, 1080)
        XCTAssertNil(forwards[4].localBrowserURL)
        XCTAssertEqual(forwards[4].destinationDisplay, "SOCKS 代理")
    }
}
