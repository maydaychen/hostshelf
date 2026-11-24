import AppKit
import SwiftUI

@MainActor
final class QuickLauncherController: NSObject, NSWindowDelegate {
    private var panel: QuickLauncherPanel?
    private var focusToken = 0
    private var isDismissing = false

    var isVisible: Bool { panel?.isVisible == true }

    func toggle(store: AppStore, revealMainWindow: @escaping @MainActor () -> Void) {
        if isVisible {
            dismiss()
        } else {
            show(store: store, revealMainWindow: revealMainWindow)
        }
    }

    func show(store: AppStore, revealMainWindow: @escaping @MainActor () -> Void) {
        let panel = ensurePanel()
        focusToken += 1
        let rootView = QuickLauncherView(
            store: store,
            focusToken: focusToken,
            onDismiss: { [weak self] in self?.dismiss() },
            onRevealHost: { [weak self] alias in
                self?.dismiss()
                store.selectHost(alias: alias)
                revealMainWindow()
            }
        )
        panel.contentViewController = NSHostingController(rootView: rootView)
        position(panel)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func dismiss() {
        guard !isDismissing, let panel, panel.isVisible else { return }
        isDismissing = true
        defer { isDismissing = false }
        panel.orderOut(nil)
        panel.contentViewController = nil
    }

    func windowDidResignKey(_ notification: Notification) {
        dismiss()
    }

    private func ensurePanel() -> QuickLauncherPanel {
        if let panel { return panel }
        let created = QuickLauncherPanel(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 420),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        created.isFloatingPanel = true
        created.level = .floating
        created.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        created.titleVisibility = .hidden
        created.titlebarAppearsTransparent = true
        created.isMovableByWindowBackground = true
        created.hidesOnDeactivate = false
        created.isReleasedWhenClosed = false
        created.backgroundColor = .clear
        created.hasShadow = true
        created.delegate = self
        panel = created
        return created
    }

    private func position(_ panel: QuickLauncherPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let visible = screen?.visibleFrame else {
            panel.center()
            return
        }
        let size = NSSize(width: 600, height: 420)
        let originX = visible.midX - size.width / 2
        let upperOriginY = visible.maxY - visible.height * 0.2 - size.height
        let clampedY = min(visible.maxY - size.height - 16, max(visible.minY + 16, upperOriginY))
        panel.setFrame(NSRect(origin: NSPoint(x: originX, y: clampedY), size: size), display: true)
    }
}

private final class QuickLauncherPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
