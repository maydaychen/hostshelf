import AppKit
import Carbon
import HostShelfCore

/// Tests parameters, preferences and app metadata; never executes an AppleEvent or SSH.
@main
struct TerminalLauncherCheck {
    @MainActor
    static func main() async throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".tmp/terminal-launcher-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)

        let aliases = ["ordinary", "with space", "quote'and\"double", "$(touch forbidden); `id` & host", "中文主机", "-leading-option"]
        for target in TerminalTarget.allCases {
            let source = TerminalLauncher.scriptSource(for: target)
            try require(source.contains("quoted form of hostAlias") && source.contains("/usr/bin/ssh -- "), "fixed safe command")
            try require(source.contains(target.bundleIdentifier), "target bundle")
            for alias in aliases {
                let event = TerminalLauncher.connectionEvent(alias: alias)
                let arguments = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))
                try require(arguments?.numberOfItems == 1, "single argument")
                try require(arguments?.atIndex(1)?.stringValue == alias, "alias preserved as data")
                try require(!source.contains(alias), "alias must not enter script source")
            }
            for alias in ["", " \t", "host\ncommand", "host\u{7F}", "user@host", "SSH://host"] {
                do {
                    try await TerminalLauncher().launch(alias: alias, target: target)
                    throw Failure.check("invalid alias reached launch")
                } catch is SSHCommandError {}
            }
        }
        try require(TerminalLauncher.scriptSource(for: .iterm2).contains("create window with default profile command connectionCommand"), "iTerm new window")
        let ghostty = TerminalLauncher.scriptSource(for: .ghostty)
        try require(ghostty.contains("new window with configuration cfg") && ghostty.contains("\"shell:\" & connectionCommand"), "Ghostty new window with shell quoting")
        print("PASS: all targets use fixed new-window handlers and preserve special aliases as one AppleEvent parameter")

        for target in TerminalTarget.allCases {
            try require(TerminalLauncher.availability(for: target, applicationURL: nil) == .notInstalled, "missing app")
            let mismatch = try appFixture(root: root, bundleID: "example.invalid.other", version: "99.0.0")
            try require(TerminalLauncher.availability(for: target, applicationURL: mismatch) == .notInstalled, "mismatched bundle")
        }
        for version in [nil, "unknown", "1.2.99", "1.3.-1", "1.3.0-dev"] as [String?] {
            let app = try appFixture(root: root, bundleID: TerminalTarget.ghostty.bundleIdentifier, version: version)
            try require(TerminalLauncher.availability(for: .ghostty, applicationURL: app) == .unsupportedVersion, "unsupported Ghostty version")
        }
        for version in ["1.3", "1.3.0", "1.3.1", "1.4.0", "2.0.0"] {
            let app = try appFixture(root: root, bundleID: TerminalTarget.ghostty.bundleIdentifier, version: version)
            try require(TerminalLauncher.availability(for: .ghostty, applicationURL: app) == .available, "supported Ghostty version")
        }
        for target in TerminalTarget.allCases {
            let message = TerminalLaunchError.automationDenied(target).localizedDescription
            try require(message.contains(target.displayName) && message.contains("自动化"), "target-specific permission recovery")
            try require(TerminalLaunchError.unavailable(target, .notInstalled).localizedDescription.contains(target.displayName), "target-specific missing app error")
        }
        print("PASS: missing apps, mismatched bundles, Ghostty version boundaries and permission recovery messages")

        let metadata = root.appendingPathComponent("metadata.json")
        let initialMetadata = Data("{\"schemaVersion\":1,\"annotations\":{},\"groups\":[]}".utf8)
        try initialMetadata.write(to: metadata)
        setenv("HOSTSHELF_METADATA_PATH", metadata.path, 1)
        setenv("HOSTSHELF_CONFIG_ROOTS", root.appendingPathComponent("unused-config").path, 1)
        let suiteName = "HostShelf.TerminalCheck.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: suiteName)!
        defer { preferences.removePersistentDomain(forName: suiteName) }
        let initial = AppStore(preferences: preferences)
        try require(initial.preferredTerminal == .terminal, "default Terminal")
        initial.preferredTerminal = .ghostty
        try require(preferences.string(forKey: AppStore.terminalPreferenceKey) == "ghostty", "persist selection")
        let restored = AppStore(preferences: preferences)
        try require(restored.preferredTerminal == .ghostty, "restore selection")
        preferences.set("unknown-future-terminal", forKey: AppStore.terminalPreferenceKey)
        let unknown = AppStore(preferences: preferences)
        try require(unknown.preferredTerminal == .terminal, "unknown selection fallback")
        try require(try Data(contentsOf: metadata) == initialMetadata, "preferences must not rewrite host metadata")
        print("PASS: default selection, persistence, restart restoration and unknown-value fallback leave host metadata unchanged")
        try await checkBackgroundExecution(aliases: aliases)
        try await checkExecutionFailures()
        print("NOTE: no scripts were compiled or executed; Terminal/Ghostty/iTerm2 handoff and TCC require separate runtime acceptance")
    }

    @MainActor
    private static func checkBackgroundExecution(aliases: [String]) async throws {
        let probe = ExecutionProbe()
        let releaseFirst = DispatchSemaphore(value: 0)
        defer { releaseFirst.signal() }
        let execute: TerminalLauncher.ScriptExecutor = { alias, _ in
            probe.begin(alias)
            defer { probe.finish() }
            if alias == "first" {
                guard releaseFirst.wait(timeout: .now() + 5) == .success else {
                    throw Failure.check("test execution gate timed out")
                }
            }
        }
        let availability: @MainActor (TerminalTarget) -> TerminalAvailability = { _ in
            probe.checkAvailability()
            return .available
        }
        let launcher = TerminalLauncher(execute: execute, availability: availability)
        let secondLauncher = TerminalLauncher(execute: execute, availability: availability)
        let first = Task { try await launcher.launch(alias: "first") }
        try await waitUntil { probe.snapshot().aliases == ["first"] }
        let second = Task { try await secondLauncher.launch(alias: "second") }
        try await waitUntil { probe.snapshot().availabilityChecks == 2 }
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
        try require(probe.snapshot().aliases == ["first"], "second execution waits on serial queue while main queue responds")
        releaseFirst.signal()
        try await first.value
        try await second.value
        for alias in aliases { try await launcher.launch(alias: alias, target: .ghostty) }
        let result = probe.snapshot()
        try require(result.aliases == ["first", "second"] + aliases, "serial execution preserves order and exact aliases")
        try require(result.maximumConcurrent == 1 && !result.executedOnMain, "execution is serial and off main thread")
        try require(result.availabilityOnMain, "availability remains on main thread")
        print("PASS: blocked handoff leaves the main queue responsive; concurrent requests execute serially off main and preserve aliases")
    }

    @MainActor
    private static func checkExecutionFailures() async throws {
        let unavailable = TerminalLauncher(execute: { _, _ in
            throw Failure.check("unavailable target must not execute")
        }, availability: { _ in .notInstalled })
        do {
            try await unavailable.launch(alias: "host", target: .iterm2)
            throw Failure.check("missing target succeeded")
        } catch TerminalLaunchError.unavailable(.iterm2, .notInstalled) {}

        let denied = TerminalLauncher(execute: { _, target in
            throw TerminalLaunchError.automationDenied(target)
        }, availability: { _ in .available })
        do {
            try await denied.launch(alias: "host", target: .ghostty)
            throw Failure.check("denied automation succeeded")
        } catch TerminalLaunchError.automationDenied(.ghostty) {}

        let invalid = TerminalLauncher(execute: { _, _ in
            throw Failure.check("invalid alias must not execute")
        }, availability: { _ in .notInstalled })
        do {
            try await invalid.launch(alias: "host\ncommand")
            throw Failure.check("invalid alias succeeded")
        } catch is SSHCommandError {}
        print("PASS: unavailable targets and invalid aliases never execute; background errors return unchanged")
    }

    @MainActor
    private static func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw Failure.check("asynchronous execution did not start")
    }

    private static func appFixture(root: URL, bundleID: String, version: String?) throws -> URL {
        let app = root.appendingPathComponent("\(UUID().uuidString).app")
        let contents = app.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        var info = ["CFBundleIdentifier": bundleID, "CFBundlePackageType": "APPL", "CFBundleExecutable": "fixture"]
        if let version { info["CFBundleShortVersionString"] = version }
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))
        return app
    }

    private static func require(_ condition: @autoclosure () throws -> Bool, _ name: String) throws {
        guard try condition() else { throw Failure.check(name) }
    }

    enum Failure: Error { case check(String) }
}

private final class ExecutionProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var aliases: [String] = []
    private var active = 0
    private var maximumConcurrent = 0
    private var executedOnMain = false
    private var availabilityChecks = 0
    private var availabilityOnMain = true

    func begin(_ alias: String) {
        lock.lock()
        defer { lock.unlock() }
        aliases.append(alias)
        active += 1
        maximumConcurrent = max(maximumConcurrent, active)
        executedOnMain = executedOnMain || Thread.isMainThread
    }

    func finish() {
        lock.lock()
        defer { lock.unlock() }
        active -= 1
    }

    func checkAvailability() {
        lock.lock()
        defer { lock.unlock() }
        availabilityChecks += 1
        availabilityOnMain = availabilityOnMain && Thread.isMainThread
    }

    func snapshot() -> (aliases: [String], maximumConcurrent: Int, executedOnMain: Bool,
                        availabilityChecks: Int, availabilityOnMain: Bool) {
        lock.lock()
        defer { lock.unlock() }
        return (aliases, maximumConcurrent, executedOnMain, availabilityChecks, availabilityOnMain)
    }
}
