import AppKit
import HostShelfCore
import SwiftUI

/// Exercises the production list with temporary data and an injected terminal, never real SSH.
@main
struct HostListSelectionCheck {
    @MainActor
    static func main() async throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("HostShelf-selection-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let config = root.appendingPathComponent("config")
        try "Host alpha beta gamma\n HostName fixture.example.invalid\n".write(to: config, atomically: true, encoding: .utf8)
        setenv("HOSTSHELF_CONFIG_ROOTS", config.path, 1)
        setenv("HOSTSHELF_METADATA_PATH", root.appendingPathComponent("metadata.json").path, 1)
        let suite = "HostShelf.Selection.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        let calls = SelectionCalls()
        let launcher = TerminalLauncher(execute: { alias, _ in calls.record(alias) }, availability: { _ in .available })
        let store = AppStore(preferences: preferences, launcher: launcher)
        store.refresh()
        try await wait { store.hasScanned }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 360),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = NSHostingView(rootView: HostListView(store: store))
        window.orderBack(nil)
        defer { window.orderOut(nil); window.contentView = nil }
        pump()
        guard let table = findTable(window.contentView!), table.numberOfRows == 3 else {
            throw Failure.check("production list must expose the three fixture rows")
        }
        click(window, table: table, row: 1, x: 40)
        pump()
        try require(store.selectedHostAlias == "beta" && store.selectedHost?.alias == "beta", "single click on host name selects beta")
        click(window, table: table, row: 2, x: table.bounds.width - 35)
        pump()
        try require(store.selectedHostAlias == "gamma", "single click on row whitespace selects gamma")
        try require(calls.aliases.isEmpty, "selection must not connect")
        let key = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.function, .numericPad],
                                  timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                  context: nil, characters: "\u{f700}", charactersIgnoringModifiers: "\u{f700}",
                                  isARepeat: false, keyCode: 126)!
        table.keyDown(with: key)
        pump()
        try require(store.selectedHostAlias == "beta", "native keyboard up selects beta")
        print("PASS: production host list selects names and row whitespace, switches details and preserves native keyboard selection without connecting")
        try require(table.doubleAction != nil, "native list primary action must be installed")
        print("PASS: native list primary action is installed; actual double-click handoff remains a GUI acceptance check")

    }

    @MainActor private static func wait(_ predicate: () -> Bool) async throws {
        let end = Date(timeIntervalSinceNow: 5)
        while !predicate() {
            guard Date() < end else { throw Failure.check("timed out") }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
    @MainActor private static func pump() {
        let end = Date(timeIntervalSinceNow: 0.6)
        while Date() < end {
            if let event = NSApp.nextEvent(matching: .any, until: Date(timeIntervalSinceNow: 0.01), inMode: .default, dequeue: true) {
                NSApp.sendEvent(event)
            }
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
        }
    }
    @MainActor private static func click(_ window: NSWindow, table: NSTableView, row: Int, x: CGFloat) {
        let rect = table.rect(ofRow: row)
        let point = table.convert(NSPoint(x: x, y: rect.midY), to: nil)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
            NSApp.postEvent(event, atStart: false)
        }
    }
    @MainActor private static func findTable(_ view: NSView) -> NSTableView? {
        if let table = view as? NSTableView { return table }
        for child in view.subviews { if let table = findTable(child) { return table } }
        return nil
    }
    private static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw Failure.check(message) }
    }
    enum Failure: Error { case check(String) }
}
private final class SelectionCalls: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String] = []
    var aliases: [String] { lock.lock(); defer { lock.unlock() }; return values }
    func record(_ alias: String) { lock.lock(); defer { lock.unlock() }; values.append(alias) }
}
