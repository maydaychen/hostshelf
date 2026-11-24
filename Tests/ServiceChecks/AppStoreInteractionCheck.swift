import AppKit
import HostShelfCore

/// Uses temporary configuration, metadata and an injected terminal executor only.
@main
struct AppStoreInteractionCheck {
    @MainActor
    static func main() async throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".tmp/app-interactions-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let config = root.appendingPathComponent("config")
        let systemConfig = root.appendingPathComponent("ssh_config")
        let metadata = root.appendingPathComponent("metadata.json")
        try "Host alpha beta gamma delta user@host SSH://host\n HostName fixture.example.invalid\n".write(to: config, atomically: true, encoding: .utf8)
        try "Host *\n  SendEnv LANG LC_*\n".write(to: systemConfig, atomically: true, encoding: .utf8)
        setenv("HOSTSHELF_CONFIG_ROOTS", "\(config.path):\(systemConfig.path)", 1)
        setenv("HOSTSHELF_METADATA_PATH", metadata.path, 1)
        var document = MetadataDocument(groups: ["empty", "used", "archived", "draft"])
        document.annotations["alpha"] = HostAnnotation(group: "used", note: "original", lastLaunchedAt: Date(timeIntervalSince1970: 100))
        document.annotations["beta"] = HostAnnotation(lastLaunchedAt: Date(timeIntervalSince1970: 200))
        document.annotations["gamma"] = HostAnnotation(lastLaunchedAt: Date(timeIntervalSince1970: 200))
        document.annotations["no-longer-indexed"] = HostAnnotation(group: "archived", note: "retained")
        try HostMetadataStore(fileURL: metadata).save(document)
        let calls = Calls()
        let suite = "HostShelf.StoreCheck.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        let launcher = TerminalLauncher(execute: { alias, _ in
            calls.record(alias)
            Thread.sleep(forTimeInterval: 0.25)
            if alias == "gamma" { throw TerminalLaunchError.automationDenied(.terminal) }
            if alias == "delta" { throw TerminalLaunchError.failed(.terminal) }
        }, availability: { _ in .available })
        let store = AppStore(preferences: preferences, launcher: launcher)
        store.refresh()
        try await wait { store.hasScanned && !store.isRefreshing }
        try require(
            store.snapshot.sources == [config.path, systemConfig.path].sorted()
                && store.hostSources == [config.path]
                && store.hostCount(forSource: config.path) == 6
                && store.hostCount(forSource: systemConfig.path) == 0
                && store.snapshot.sourceIdentities[systemConfig.path] != nil,
            "sidebar hostSources excludes zero-host sources while snapshot retains all scanned sources"
        )

        try require(store.recentHosts.map(\.alias) == ["beta", "gamma", "alpha"], "recent date order and deterministic ties")
        store.sidebarSelection = .recent
        store.searchText = "gamma"
        try require(store.visibleHosts.map(\.alias) == ["gamma"], "search within recent filter")
        store.searchText = ""
        try require(store.canDeleteGroup("empty") && store.deleteEmptyGroup("empty"), "delete empty explicit group")
        try require(!store.groups.contains("empty"), "deleted empty group must stay absent")
        try require(!store.deleteEmptyGroup("used") && !store.deleteEmptyGroup("archived"), "indexed and hidden annotations protect groups")

        let initialData = try Data(contentsOf: metadata)
        for index in 0..<100 { store.stageAnnotation(alias: "beta", group: "draft", note: "draft \(index)") }
        try require(try Data(contentsOf: metadata) == initialData, "typing burst must not write synchronously")
        try require(store.pendingAnnotationAliases.contains("beta") && !store.canDeleteGroup("draft"), "pending draft and group protection")
        try await wait { store.pendingAnnotationAliases.isEmpty }
        try require(store.annotation(for: "beta").note == "draft 99" && store.unsavedAnnotations.isEmpty, "debounced latest draft saved")
        let savedFile = try fileIdentity(metadata)
        try await Task.sleep(for: .milliseconds(500))
        try require(try fileIdentity(metadata) == savedFile, "no redundant timer writes")
        store.stageAnnotation(alias: "beta", group: "draft", note: "flush now")
        store.toggleFavorite("beta")
        try require(store.flushAnnotation(alias: "beta") && store.annotation(for: "beta").isFavorite, "flush preserves concurrent favorite change")
        let flushedFile = try fileIdentity(metadata)
        try await Task.sleep(for: .milliseconds(500))
        try require(try fileIdentity(metadata) == flushedFile, "flushing cancels pending timer")
        store.stageAnnotation(alias: "alpha", group: "used", note: "close flush")
        store.mainWindowAppeared()
        store.mainWindowDisappeared()
        try require(store.annotation(for: "alpha").note == "close flush", "window disappearance flushes pending note")
        store.stageAnnotation(alias: "alpha", group: "used", note: "quit flush")
        try require(store.flushAllAnnotations() && store.annotation(for: "alpha").note == "quit flush", "termination flushes pending notes")
        print("PASS: recent filtering, deterministic ordering and empty-group protection include hidden and pending records")
        print("PASS: input bursts stay in memory, debounce saves the latest draft, flush cancels timers and preserves favorites")

        guard let alpha = store.snapshot.hosts.first(where: { $0.alias == "alpha" }),
              let beta = store.snapshot.hosts.first(where: { $0.alias == "beta" }),
              let gamma = store.snapshot.hosts.first(where: { $0.alias == "gamma" }) else { throw Failure.check("fixture hosts") }
        store.mainWindowAppeared()
        store.connect(alpha)
        store.connect(beta)
        try require(store.isConnecting && store.statusMessage != nil, "immediate busy feedback")
        try await Task.sleep(for: .milliseconds(40))
        try require(store.isConnecting, "main actor remains responsive during blocked executor")
        try await wait { !store.isConnecting }
        try require(calls.aliases == ["alpha"] && store.errorNotice == nil, "duplicate submission ignored and success has no alert")
        try require(store.recentHosts.first?.alias == "alpha" && store.statusMessage?.contains("已交给") == true, "handoff updates recent and lightweight feedback")
        store.mainWindowDisappeared()
        store.mainWindowAppeared()
        try require(store.statusMessage == nil && store.errorNotice == nil, "success does not reappear on window reopen")
        store.mainWindowDisappeared()
        store.connect(beta)
        try await wait { !store.isConnecting }
        try require(store.statusMessage == nil && store.errorNotice == nil, "no-window success leaves no stale feedback")
        let beforeFailure = store.annotation(for: "gamma").lastLaunchedAt
        store.connect(gamma)
        try await wait { !store.isConnecting }
        try require(store.errorNotice?.message.contains("自动化") == true && store.errorNotice?.offersAutomationSettings == true
                    && store.errorNotice?.copyAlias == "gamma" && store.annotation(for: "gamma").lastLaunchedAt == beforeFailure,
                    "denied automation offers settings and a safe copy action without recording success")
        store.mainWindowAppeared()
        try require(store.errorNotice != nil, "opening window must not swallow a real failure")
        let beforeUnindexed = calls.aliases.count
        store.connect(HostEntry(alias: "not-indexed"))
        try require(!store.isConnecting && calls.aliases.count == beforeUnindexed, "unindexed hosts rejected")
        print("PASS: slow handoff leaves the main actor responsive, ignores duplicates and separates success from recoverable errors")

        guard let delta = store.host(for: "delta") else { throw Failure.check("ordinary failure fixture") }
        store.connect(delta)
        try await wait { !store.isConnecting }
        try require(store.errorNotice?.copyAlias == "delta" && store.errorNotice?.offersAutomationSettings == false,
                    "ordinary failure offers only the safe copy action")
        let callsBeforeValidation = calls.aliases
        for alias in ["user@host", "SSH://host"] {
            guard let host = store.host(for: alias) else { throw Failure.check("ambiguous declaration must remain indexed") }
            store.connect(host)
            try require(!store.isConnecting && store.errorNotice?.message.contains("SSH URI") == true
                        && store.errorNotice?.copyAlias == nil, "ambiguous alias must not be handed to the launcher")
            store.errorNotice = nil
            store.copyCommand(host)
            try require(store.errorNotice?.message.contains("SSH URI") == true && store.errorNotice?.copyAlias == nil,
                        "ambiguous alias must fail copy validation before touching the pasteboard")
        }
        try require(calls.aliases == callsBeforeValidation, "alias validation cannot invoke the executor")
        print("PASS: recovery actions distinguish automation denial, ordinary failure and ambiguous aliases")

        let external = HostMetadataStore(fileURL: metadata)
        var externalDocument = try external.load()
        externalDocument.annotations["gamma"]?.note = "external edit"
        try external.save(externalDocument)
        store.stageAnnotation(alias: "alpha", group: "used", note: "local draft")
        try require(!store.flushAnnotation(alias: "alpha") && !store.metadataWritable
                    && store.metadataError?.contains("已变化") == true, "valid external changes must block a stale save")
        try require(try external.load() == externalDocument, "conflict cannot change the disk document")
        store.reloadMetadata()
        try require(store.metadataWritable && store.metadataError == nil && store.annotation(for: "gamma").note == "external edit"
                    && store.unsavedAnnotations["alpha"]?.note == "local draft", "reload keeps both the external edit and local draft")
        try require(store.flushAnnotation(alias: "alpha"), "draft can be saved after explicit reload")
        let recovered = try external.load()
        try require(recovered.annotations["alpha"]?.note == "local draft" && recovered.annotations["gamma"]?.note == "external edit",
                    "saving the draft after recovery must preserve the external edit")
        print("PASS: external metadata conflict preserves the disk document and allows draft recovery after explicit reload")

        let damaged = Data("{not valid JSON".utf8)
        try damaged.write(to: metadata, options: .atomic)
        store.stageAnnotation(alias: "alpha", group: "used", note: "must survive failure")
        try require(!store.flushAllAnnotations(), "failed flush must be reported")
        try require(store.unsavedAnnotations["alpha"]?.note == "must survive failure"
                    && !store.pendingAnnotationAliases.contains("alpha") && store.metadataError != nil,
                    "save failure retains draft and persistent error")
        store.mainWindowDisappeared()
        try require(try Data(contentsOf: metadata) == damaged, "damaged file must not be overwritten")
        try require(!store.flushAllAnnotations(), "termination must not report unsaved drafts as saved")
        print("PASS: window/termination flushes persist pending drafts; damaged metadata blocks writes and retains unsaved content")
        print("NOTE: no terminal script, Apple Event, real SSH configuration, clipboard or server was used")
    }

    @MainActor
    private static func wait(_ condition: () -> Bool) async throws {
        for _ in 0..<150 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        throw Failure.check("async state timeout")
    }

    private static func fileIdentity(_ url: URL) throws -> UInt64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0
    }

    private static func require(_ condition: @autoclosure () throws -> Bool, _ name: String) throws {
        guard try condition() else { throw Failure.check(name) }
    }

    private final class Calls: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [String] = []
        var aliases: [String] { lock.lock(); defer { lock.unlock() }; return values }
        func record(_ alias: String) { lock.lock(); defer { lock.unlock() }; values.append(alias) }
    }

    enum Failure: Error { case check(String) }
}
