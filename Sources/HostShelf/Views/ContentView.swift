import HostShelfCore
import SwiftUI

struct ContentView: View {
    @Bindable var store: AppStore
    @State private var isSearchFocused = false

    var body: some View {
        NavigationSplitView {
            SidebarView(store: store)
                .navigationSplitViewColumnWidth(min: 165, ideal: 200, max: 260)
        } content: {
            HostListView(store: store)
                .safeAreaInset(edge: .top, spacing: 0) {
                    if let error = store.metadataError {
                        MetadataErrorBanner(store: store, message: error)
                    }
                }
                .navigationSplitViewColumnWidth(min: 220, ideal: 280, max: 420)
        } detail: {
            HostDetailColumn(store: store)
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: HostShelfSpacing.s6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    HostSearchField(
                        text: $store.searchText,
                        focusRequest: store.searchFocusRequest,
                        onFocusChange: { isSearchFocused = $0 }
                    )
                    .frame(minWidth: 150, idealWidth: 220, maxWidth: 280)
                    if !store.searchText.isEmpty {
                        Button { store.searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("清除搜索")
                        .help("清除搜索")
                    }
                }
                .padding(.horizontal, HostShelfSpacing.s8)
                .padding(.vertical, HostShelfSpacing.s4)
                .frame(minHeight: 28)
                .hostSearchFieldChrome(isFocused: isSearchFocused)
                .padding(3) // Room for the outer focus ring so the toolbar does not clip it.
            }
            ToolbarItem(id: "refreshConfiguration") {
                RefreshConfigurationButton(isRefreshing: store.isRefreshing) { store.refresh() }
            }
            ToolbarItem {
                Button { store.showDiagnostics = true } label: {
                    Label("配置诊断", systemImage: store.snapshot.hasWarnings ? "exclamationmark.triangle" : "list.bullet.rectangle")
                }.help("查看诊断、配置来源、规则和 Include 关系")
            }
        }
        .onChange(of: store.searchText) { _, _ in store.reconcileSelection() }
        .onChange(of: store.sidebarSelection) { _, _ in store.reconcileSelection() }
        .onAppear { store.mainWindowAppeared() }
        .onDisappear { store.mainWindowDisappeared() }
        .sheet(isPresented: $store.showDiagnostics) { DiagnosticsView(store: store) }
        .alert("操作未完成", isPresented: Binding(get: { store.errorNotice != nil }, set: { if !$0 { store.errorNotice = nil } }), presenting: store.errorNotice) { notice in
            if notice.offersAutomationSettings {
                Button("打开自动化设置") { Task { store.openAutomationSettings() } }
            }
            if let alias = notice.copyAlias {
                Button("复制连接命令") { Task { store.copyCommand(for: alias) } }
            }
            Button("关闭", role: .cancel) { store.errorNotice = nil }
        } message: { notice in Text(notice.message) }
        .alert(
            "确认连接高危主机",
            isPresented: Binding(get: { store.pendingConfirmation != nil }, set: { if !$0 { store.cancelPendingConnection() } }),
            presenting: store.pendingConfirmation
        ) { _ in
            Button("确认连接", role: .destructive) { store.confirmPendingConnection() }
            Button("取消", role: .cancel) { store.cancelPendingConnection() }
        } message: { pending in
            let action = pending.mode == .tunnelOnly ? "仅建立隧道（ssh -N）" : "连接"
            Text("即将通过 \(pending.target.displayName) 对“\(pending.host.alias)”执行\(action)。\n\(pending.reason)")
        }
    }
}

private struct HostDetailColumn: View {
    var store: AppStore

    var body: some View {
        if let host = store.selectedHost {
            HostDetailView(store: store, host: host)
                .id(host.alias)
        } else {
            ContentUnavailableView("选择一台主机", systemImage: "terminal", description: Text("查看配置声明、整理备注，并交给默认终端连接。"))
        }
    }
}

private struct HostListView: View {
    @Bindable var store: AppStore

    private var filterTitle: String {
        switch store.sidebarSelection ?? .all {
        case .all:
            return "全部主机"
        case .favorites:
            return "收藏"
        case .recent:
            return "最近发起"
        case .group(let group):
            return group
        case .tag(let tag):
            return "#\(tag)"
        case .source(let path):
            return URL(fileURLWithPath: path).lastPathComponent
        }
    }

    var body: some View {
        let hosts = store.visibleHosts
        let defaultStatus = "已扫描 \(store.snapshot.sources.count) 个来源"
        let defaultHelp = "已扫描 \(store.snapshot.sources.count) 个配置文件（其中 \(store.hostSources.count) 个包含主机）；完整列表见配置诊断。"
        let status = store.isConnecting ? "正在交给终端…" : store.statusMessage ?? defaultStatus
        let statusHelp = store.isConnecting || store.statusMessage != nil ? status : defaultHelp
        VStack(spacing: 0) {
            HStack {
                Text(filterTitle).font(.headline)
                Spacer()
                Text("\(hosts.count)").foregroundStyle(.secondary).monospacedDigit()
            }.padding(HostShelfSpacing.s12)
            Divider()
            if hosts.isEmpty {
                if !store.hasScanned {
                    VStack(spacing: HostShelfSpacing.s12) { ProgressView(); Text("正在读取 SSH 配置…").foregroundStyle(.secondary) }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if !store.searchText.isEmpty {
                    VStack(spacing: 0) {
                        HostEmptyStateCard(
                            icon: "magnifyingglass",
                            title: "无搜索结果",
                            description: "未找到与“\(store.searchText)”匹配的主机、备注或来源。"
                        )
                        Spacer()
                    }
                } else {
                    VStack(spacing: 0) {
                        emptyStateView
                        Spacer()
                    }
                }
            } else {
                let trimmedQuery = store.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                let visibleAliases = Set(hosts.map(\.alias))
                List(selection: $store.selectedHostAlias) {
                    ForEach(hosts) { host in
                        let annotation = store.annotation(for: host.alias)
                        HostRow(
                            alias: host.alias,
                            subtitle: HostListPresentation.subtitle(for: host, annotation: annotation),
                            isFavorite: annotation.isFavorite,
                            isProtected: store.requiresConnectionConfirmation(for: host.alias),
                            query: trimmedQuery
                        )
                        .equatable()
                        .tag(host.alias)
                        .contentShape(Rectangle())
                    }
                }
                .listStyle(.inset)
                .contextMenu(forSelectionType: String.self) { aliases in
                    if aliases.count == 1, let alias = aliases.first, visibleAliases.contains(alias),
                       let host = store.host(for: alias) {
                        Button("连接") { store.connect(host) }.disabled(store.isConnecting)
                        Button("复制连接命令") { store.copyCommand(host) }
                        Button(store.annotation(for: alias).isFavorite ? "取消收藏" : "收藏") { store.toggleFavorite(alias) }
                            .disabled(!store.metadataWritable)
                        Divider()
                        HostMoreActionsMenuContent(store: store, host: host)
                    }
                } primaryAction: { aliases in
                    guard aliases.count == 1, let alias = aliases.first, visibleAliases.contains(alias),
                          let host = store.host(for: alias) else { return }
                    store.connect(host)
                }
            }
            Divider()
            HStack(spacing: HostShelfSpacing.s6) {
                Image(systemName: store.isConnecting ? "arrow.up.forward.app" : store.statusMessage == nil ? "doc.text.magnifyingglass" : "checkmark.circle")
                    .frame(width: 16)
                Text(status)
                    .lineLimit(1)
                    .help(statusHelp)
                    .accessibilityIdentifier("hostListStatus")
                Spacer(minLength: HostShelfSpacing.s4)
                if store.hasScanned {
                    Text("上次读取 \(store.snapshot.scannedAt.formatted(date: .omitted, time: .shortened))")
                        .fixedSize()
                }
            }.font(.caption).foregroundStyle(.secondary).frame(height: 20).padding(HostShelfSpacing.s10)
        }
    }

    @ViewBuilder
    private var emptyStateView: some View {
        switch store.sidebarSelection ?? .all {
        case .favorites:
            HostEmptyStateCard(
                icon: "star",
                title: "尚无收藏的主机",
                description: "在主机列表中使用快捷菜单或详情页星标，可将主机加入收藏。",
                actionTitle: "查看全部主机",
                action: { store.sidebarSelection = .all }
            )
        case .recent:
            HostEmptyStateCard(
                icon: "clock",
                title: "暂无连接记录",
                description: "成功交给终端的主机会按最近发起时间显示在这里。",
                actionTitle: "查看全部主机",
                action: { store.sidebarSelection = .all }
            )
        case .group(let group):
            HostEmptyStateCard(
                icon: "folder",
                title: "分组暂无主机",
                description: "在主机详情中，可将主机归入“\(group)”分组。",
                actionTitle: "查看全部主机",
                action: { store.sidebarSelection = .all }
            )
        case .tag(let tag):
            HostEmptyStateCard(
                icon: "tag",
                title: "此标签暂无主机",
                description: "可在主机详情的“编辑分组与备注”中添加“#\(tag)”标签。",
                actionTitle: "查看全部主机",
                action: { store.sidebarSelection = .all }
            )
        case .source(let path):
            let filename = URL(fileURLWithPath: path).lastPathComponent
            HostEmptyStateCard(
                icon: "doc.text",
                title: "此来源未声明主机",
                description: "“\(filename)”可能仅包含公共配置规则或 Match 条件。",
                actionTitle: store.snapshot.diagnostics.isEmpty ? "查看全部主机" : "查看配置诊断",
                action: {
                    if store.snapshot.diagnostics.isEmpty {
                        store.sidebarSelection = .all
                    } else {
                        store.showDiagnostics = true
                    }
                }
            )
        case .all:
            HostEmptyStateCard(
                icon: "server.rack",
                title: "没有可显示的主机",
                description: store.snapshot.hasWarnings
                    ? "部分配置无法读取或解析。请查看诊断与规则，确认配置来源。"
                    : "配置中的明确 Host 别名会显示在这里。",
                actionTitle: store.snapshot.hasWarnings ? "查看配置诊断" : nil,
                action: store.snapshot.hasWarnings ? { store.showDiagnostics = true } : nil
            )
        }
    }
}

private struct HostEmptyStateCard: View {
    let icon: String
    let title: String
    let description: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: HostShelfSpacing.s10) {
            Image(systemName: icon)
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(description)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, HostShelfSpacing.s20)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .padding(.top, HostShelfSpacing.s6)
            }
        }
        .padding(.vertical, 28)
        .frame(maxWidth: .infinity)
    }
}

/// Metadata read/save failure, pinned to the top safe area of the host list column.
private struct MetadataErrorBanner: View {
    var store: AppStore
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: HostShelfSpacing.s8) {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(HostShelfSurface.warning)
                    .fixedSize(horizontal: false, vertical: true)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: HostShelfSpacing.s8) { actions }
                    VStack(alignment: .leading, spacing: HostShelfSpacing.s6) { actions }
                }
                .controlSize(.small)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(HostShelfSpacing.s12)
            .background(HostShelfSurface.warning.opacity(0.1))
            Divider()
        }
        .background(.bar)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("metadataErrorBanner")
    }

    @ViewBuilder private var actions: some View {
        Button("重读附加信息") { store.reloadMetadata() }
        Button("在 Finder 中显示") { store.showMetadataInFinder() }
    }
}

private struct HostRow: View, Equatable {
    let alias: String
    let subtitle: String
    let isFavorite: Bool
    let isProtected: Bool
    let query: String

    var body: some View {
        HStack(alignment: .center, spacing: HostShelfSpacing.s8) {
            VStack(alignment: .leading, spacing: 2) {
                aliasText.font(.system(.body, design: .monospaced)).lineLimit(1)
                subtitleText.font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: HostShelfSpacing.s4)
            // At most two trailing marks; both are fixed-size so the alias truncates first.
            HStack(spacing: HostShelfSpacing.s4) {
                if isProtected {
                    Image(systemName: "shield.lefthalf.filled")
                        .foregroundStyle(HostShelfSurface.warning)
                        .help("连接前需二次确认")
                        .accessibilityLabel("连接前需二次确认")
                }
                if isFavorite {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.yellow)
                        .help("已收藏")
                        .accessibilityLabel("已收藏")
                }
            }
            .fixedSize()
            .layoutPriority(1)
        }.padding(.vertical, HostShelfSpacing.s4).help(alias)
    }

    private var aliasText: Text {
        query.isEmpty ? Text(alias) : Text(SearchHighlight.text(alias, query: query))
    }

    private var subtitleText: Text {
        query.isEmpty ? Text(subtitle) : Text(SearchHighlight.text(subtitle, query: query))
    }
}
