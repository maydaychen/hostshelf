import AppKit
import HostShelfCore
import SwiftUI

@main
@MainActor
enum HostShelfEntry {
    static func main() {
        if CommandLine.arguments.contains("--smoke-check") {
            precondition(!EditorTarget.allCases.isEmpty)
            exit(0)
        }
        HostShelfApp.main()
    }
}

struct HostShelfApp: App {
    @NSApplicationDelegateAdaptor(HostShelfAppDelegate.self) private var delegate
    @State private var store = AppStore()
    @State private var hotKeyManager = GlobalHotKeyManager()
    @State private var launchAtLogin = LaunchAtLoginService()
    @State private var quickLauncher = QuickLauncherController()

    var body: some Scene {
        WindowGroup("HostShelf", id: "main") {
            ContentView(store: store)
                .frame(minWidth: 880, minHeight: 560)
                .background(MainWindowMarker { _ = store.flushAllAnnotations() })
                .task {
                    delegate.store = store
                    store.onConfirmationRequired = { MainWindowAction.showRegistered() }
                    hotKeyManager.onTrigger = {
                        quickLauncher.toggle(store: store) { MainWindowAction.showRegistered() }
                    }
                    if !store.hasScanned { store.refresh() }
                }
        }
        .defaultSize(width: 1120, height: 720)
        .commands {
            HostShelfCommands(store: store) {
                quickLauncher.toggle(store: store) { MainWindowAction.showRegistered() }
            }
        }

        MenuBarExtra("HostShelf", systemImage: "terminal") {
            HostShelfMenu(store: store) {
                quickLauncher.toggle(store: store) { MainWindowAction.showRegistered() }
            }
        }

        Settings {
            SettingsView(store: store, hotKeyManager: hotKeyManager, launchAtLogin: launchAtLogin)
        }

        Window("关于 HostShelf", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)
    }
}

@MainActor
final class HostShelfAppDelegate: NSObject, NSApplicationDelegate {
    weak var store: AppStore?

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        switch ProcessInfo.processInfo.environment["HOSTSHELF_UI_APPEARANCE"] {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: break
        }
        #endif
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard store?.flushAllAnnotations() != false else {
            let alert = NSAlert()
            alert.messageText = "备注尚未保存"
            alert.informativeText = "保存失败，草稿仅保留在本次运行中。可以返回应用查看草稿；放弃草稿并退出将丢失尚未保存的修改。"
            alert.addButton(withTitle: "返回应用")
            alert.addButton(withTitle: "放弃草稿并退出")
            return alert.runModal() == .alertSecondButtonReturn ? .terminateNow : .terminateCancel
        }
        return .terminateNow
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        !MainWindowAction.activateExisting()
    }
}

@MainActor
enum MainWindowAction {
    private static let windows = NSHashTable<NSWindow>.weakObjects()
    private static var openWindowCallback: (() -> Void)?

    static func register(_ window: NSWindow) { windows.add(window) }
    static func registerOpenWindow(_ callback: @escaping () -> Void) { openWindowCallback = callback }

    static func activateExisting() -> Bool {
        let candidates = windows.allObjects.filter { $0.isVisible || $0.isMiniaturized }
        guard let window = candidates.first(where: { $0.isKeyWindow })
                ?? candidates.first(where: { $0.isVisible })
                ?? candidates.first else { return false }
        window.deminiaturize(nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        return true
    }

    static func show(using openWindow: OpenWindowAction) {
        registerOpenWindow { openWindow(id: "main") }
        if !activateExisting() {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    static func showRegistered() {
        if !activateExisting(), let openWindowCallback {
            openWindowCallback()
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

private struct MainWindowMarker: NSViewRepresentable {
    let onClose: () -> Void

    func makeNSView(context: Context) -> MarkerView {
        let view = MarkerView()
        view.onClose = onClose
        return view
    }
    func updateNSView(_ nsView: MarkerView, context: Context) { nsView.onClose = onClose }

    final class MarkerView: NSView {
        var onClose: (() -> Void)?
        private var closeObserver: NSObjectProtocol?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
            closeObserver = nil
            guard let window else { return }
            window.identifier = NSUserInterfaceItemIdentifier("HostShelf.main")
            MainWindowAction.register(window)
            closeObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification, object: window, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.onClose?() }
            }
        }

        deinit {
            if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
        }
    }
}

private struct HostShelfCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    var store: AppStore
    var openQuickLauncher: () -> Void

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("关于 HostShelf") { openWindow(id: "about") }
        }
        CommandGroup(replacing: .newItem) {
            Button("打开主窗口") { MainWindowAction.show(using: openWindow) }
                .keyboardShortcut("0", modifiers: [.command])
        }
        CommandMenu("主机") {
            Button("快速启动浮窗…") {
                MainWindowAction.registerOpenWindow { openWindow(id: "main") }
                openQuickLauncher()
            }
            AllHostsMenu(store: store)
            Divider()
            Button("搜索主机") {
                MainWindowAction.show(using: openWindow)
                store.searchFocusRequest += 1
            }.keyboardShortcut("f", modifiers: [.command])
            Button("刷新配置") { store.refresh() }
                .keyboardShortcut("r", modifiers: [.command])
                .disabled(store.isRefreshing)
            Button("连接所选主机") {
                if let host = store.selectedHost { store.connect(host) }
            }.keyboardShortcut(.return, modifiers: [.command])
                .disabled(store.selectedHost == nil || store.isConnecting)
            Button("配置诊断与规则") { store.showDiagnostics = true }
        }
    }
}
