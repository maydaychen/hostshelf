import AppKit
import HostShelfCore
import SwiftUI

/// Uses app-owned fixtures only. Never calls Terminal or SSH.
@main
struct ManualRefreshCheck {
    @MainActor
    static func main() async throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".tmp/manual-refresh-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let config = root.appendingPathComponent("config")
        try "Host initial\n  HostName initial.example.invalid\n".write(to: config, atomically: true, encoding: .utf8)
        setenv("HOSTSHELF_CONFIG_ROOTS", config.path, 1)
        setenv("HOSTSHELF_METADATA_PATH", root.appendingPathComponent("metadata.json").path, 1)

        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let store = AppStore()
        store.refresh()
        try await waitForRefresh(store)
        guard store.snapshot.hosts.map(\.alias) == ["initial"] else { throw Failure.check("initial load") }
        let initialScan = store.snapshot.scannedAt

        let include = root.appendingPathComponent("extra.conf")
        try "Host included\n".write(to: include, atomically: true, encoding: .utf8)
        try "Include \(include.path)\nHost updated\n".write(to: config, atomically: true, encoding: .utf8)
        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: NSApp)
        try await Task.sleep(for: .seconds(1))
        guard store.snapshot.scannedAt == initialScan,
              store.snapshot.hosts.map(\.alias) == ["initial"], !store.isRefreshing else {
            throw Failure.check("configuration changes and activation must not refresh")
        }
        print("PASS: configuration changes and activation leave the loaded snapshot unchanged")

        store.refresh()
        for _ in 0..<20 { store.refresh() }
        try await waitForRefresh(store)
        guard store.snapshot.hosts.map(\.alias) == ["included", "updated"] else {
            throw Failure.check("manual refresh includes changed configuration")
        }
        let manualScan = store.snapshot.scannedAt
        try await Task.sleep(for: .seconds(1))
        guard store.snapshot.scannedAt == manualScan, !store.isRefreshing else {
            throw Failure.check("repeated in-flight refresh must not queue another scan")
        }
        print("PASS: manual refresh updates hosts; in-flight requests do not queue automatic scans")

        store.sidebarSelection = .source(include.path)
        store.reconcileSelection()
        guard store.selectedHostAlias == "included" else { throw Failure.check("included host must be selected") }
        try "Host updated\n".write(to: config, atomically: true, encoding: .utf8)
        store.refresh()
        try await waitForRefresh(store)
        guard !store.snapshot.sources.contains(include.path), store.sidebarSelection == .all,
              store.selectedHostAlias == "updated", store.visibleHosts.map(\.alias) == ["updated"] else {
            throw Failure.check("removed source must fall back to all hosts and reconcile selection")
        }
        print("PASS: refresh falls back to all hosts when the selected source disappears")

        let sizes = try await checkButtonGeometry()
        print("PASS: refresh button fitting size remains \(sizes) in light/dark idle/loading states")
    }

    @MainActor
    private static func waitForRefresh(_ store: AppStore) async throws {
        for _ in 0..<100 {
            if store.hasScanned && !store.isRefreshing { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        throw Failure.check("refresh timeout")
    }

    @MainActor
    private static func checkButtonGeometry() async throws -> NSSize {
        var reference: NSSize?
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            for busy in [false, true] {
                let host = NSHostingView(rootView: RefreshConfigurationButton(isRefreshing: busy) {})
                host.appearance = NSAppearance(named: appearance)
                let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 80), styleMask: [], backing: .buffered, defer: false)
                window.contentView = host
                host.layoutSubtreeIfNeeded()
                try await Task.sleep(for: .milliseconds(350))
                host.layoutSubtreeIfNeeded()
                let size = host.fittingSize
                guard size.width > 0, size.height > 0 else { throw Failure.check("button has no size") }
                if let reference {
                    guard abs(size.width - reference.width) < 0.1,
                          abs(size.height - reference.height) < 0.1 else {
                        throw Failure.check("button geometry changed: \(reference) -> \(size)")
                    }
                } else { reference = size }
                window.contentView = nil
            }
        }
        return reference!
    }

    enum Failure: Error { case check(String) }
}
