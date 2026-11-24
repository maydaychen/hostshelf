import SwiftUI

struct HostShelfMenu: View {
    var store: AppStore
    var openQuickLauncher: () -> Void = {}
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let favorites = store.favorites
        let recentHosts = store.recentHosts
        Button("快速启动浮窗…") {
            MainWindowAction.registerOpenWindow { openWindow(id: "main") }
            openQuickLauncher()
        }
        Button("打开主窗口") { MainWindowAction.show(using: openWindow) }
        if store.isConnecting { Text("正在交给终端…") }
        if store.errorNotice != nil {
            Button("查看连接或复制错误…") { MainWindowAction.show(using: openWindow) }
        }
        Divider()
        AllHostsMenu(store: store)
        Divider()
        Section("收藏") {
            if favorites.isEmpty { Text("尚未收藏主机") }
            ForEach(Array(favorites.prefix(10))) { host in
                Button(menuHostTitle(host.alias)) { store.connect(host) }
                    .disabled(store.isConnecting)
                    .help(host.alias)
                    .accessibilityLabel("连接 \(host.alias)")
            }
        }
        Section("最近发起") {
            if recentHosts.isEmpty { Text("暂无连接记录") }
            ForEach(Array(recentHosts.prefix(5))) { host in
                Button(menuHostTitle(host.alias)) { store.connect(host) }
                    .disabled(store.isConnecting)
                    .help(host.alias)
                    .accessibilityLabel("连接 \(host.alias)")
            }
        }
        Divider()
        Button(store.isRefreshing ? "正在刷新…" : "刷新配置") { store.refresh() }
            .disabled(store.isRefreshing)
        Button("配置诊断与规则") {
            MainWindowAction.show(using: openWindow)
            store.showDiagnostics = true
        }
        SettingsLink { Text("设置与关于…") }
        Divider()
        Button("退出 HostShelf") { NSApplication.shared.terminate(nil) }
    }
}

struct AllHostsMenu: View {
    var store: AppStore

    var body: some View {
        Menu("全部主机（\(store.snapshot.hosts.count)）") {
            if !store.hasScanned {
                Text("正在读取配置…")
            } else if store.snapshot.hosts.isEmpty {
                Text("尚未发现主机")
            }
            ForEach(store.sortedHosts) { host in
                Button(menuHostTitle(host.alias)) {
                    store.connect(host)
                }
                .disabled(store.isConnecting)
                .help(host.alias)
                .accessibilityLabel("连接 \(host.alias)")
            }
        }
        .accessibilityIdentifier("allHostsMenu")
    }
}

private func menuHostTitle(_ alias: String) -> String {
    alias.count > 30 ? String(alias.prefix(15)) + "…" + String(alias.suffix(14)) : alias
}
