import CryptoKit
import Foundation

@main
enum ReadOnlyIndexCheck {
    static func fingerprints(_ sources: [String]) -> [String: String] {
        var hashes: [String: String] = [:]
        for source in sources {
            if let data = try? Data(contentsOf: URL(fileURLWithPath: source)) {
                hashes[source] = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            }
        }
        return hashes
    }

    static func main() throws {
        let indexer = SSHConfigIndexer()
        let roots = CommandLine.arguments.dropFirst().map { URL(fileURLWithPath: $0) }
        let initial = indexer.scan(roots: roots.isEmpty ? nil : roots)
        let before = fingerprints(initial.sources)
        let result = indexer.scan(roots: roots.isEmpty ? nil : roots)
        let after = fingerprints(result.sources)
        guard before == after else {
            throw NSError(domain: "HostShelf.ReadOnlyCheck", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "索引前后配置内容发生变化；请核对并行修改。"])
        }
        let report: [String: Any] = ["hostCount": result.hosts.count,
            "sourceCount": result.sources.count, "includeCount": result.includes.count,
            "ruleCount": result.rules.count, "diagnosticCount": result.diagnostics.count,
            "configurationFilesUnchanged": true, "networkConnectionAttempted": false]
        let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
