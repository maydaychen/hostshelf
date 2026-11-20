import HostShelfCore
import SwiftUI

struct ContentView: View {
    @Bindable var store: AppStore

    var body: some View {
        VStack(spacing: 0) {
            if let error = store.metadataError {
                VStack(alignment: .leading, spacing: 8) {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.orange)
                    HStack {
                        Button("重读附加信息") { store.reloadMetadata() }
                        Button("在 Finder 中显示") { store.showMetadataInFinder() }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(.quaternary)
                Divider()
            }
            NavigationSplitView {
                SidebarView(store: store)
                    .navigationSplitViewColumnWidth(min: 165, ideal: 200, max: 260)
            } content: {
                HostListView(store: store)
                    .navigationSplitViewColumnWidth(min: 220, ideal: 280, max: 420)
            } detail: {
                HostDetailColumn(store: store)
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    HostSearchField(text: $store.searchText, focusRequest: store.searchFocusRequest)
                        .frame(minWidth: 150, idealWidth: 220, maxWidth: 280)
                    if !store.searchText.isEmpty {
                        Button { store.searchText = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain)
                            .accessibilityLabel("清除搜索")
                            .help("清除搜索")
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .frame(minHeight: 32)
            }
            ToolbarItem(id: "refreshConfiguration") {
                RefreshConfigurationButton(isRefreshing: store.isRefreshing) { store.refresh() }
            }
            ToolbarItem {
                Button { store.showDiagnostics = true } label: {
                    Label("配置诊断", systemImage: store.snapshot.hasWarnings ? "exclamationmark.triangle" : "list.bullet.rectangle")
                }.help("查看诊断、规则和 Include 来源")
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
        case .source(let path):
            return URL(fileURLWithPath: path).lastPathComponent
        }
    }

    var body: some View {
        let hosts = store.visibleHosts
        let status = store.isConnecting ? "正在交给终端…" : store.statusMessage ?? "\(store.snapshot.sources.count) 个配置来源"
        VStack(spacing: 0) {
            HStack {
                Text(filterTitle).font(.headline)
                Spacer()
                Text("\(hosts.count)").foregroundStyle(.secondary).monospacedDigit()
            }.padding(12)
            Divider()
            if hosts.isEmpty {
                if !store.hasScanned {
                    VStack(spacing: 12) { ProgressView(); Text("正在读取 SSH 配置…").foregroundStyle(.secondary) }
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
                            isConditional: host.isConditional,
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
                    }
                } primaryAction: { aliases in
                    guard aliases.count == 1, let alias = aliases.first, visibleAliases.contains(alias),
                          let host = store.host(for: alias) else { return }
                    store.connect(host)
                }
            }
            Divider()
            HStack(spacing: 6) {
                Image(systemName: store.isConnecting ? "arrow.up.forward.app" : store.statusMessage == nil ? "doc.text.magnifyingglass" : "checkmark.circle")
                    .frame(width: 16)
                Text(status)
                    .lineLimit(1)
                    .help(status)
                    .accessibilityIdentifier("hostListStatus")
                Spacer(minLength: 4)
                if store.hasScanned {
                    Text("上次读取 \(store.snapshot.scannedAt.formatted(date: .omitted, time: .shortened))")
                        .fixedSize()
                }
            }.font(.caption).foregroundStyle(.secondary).frame(height: 20).padding(10)
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
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(description)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .padding(.top, 6)
            }
        }
        .padding(.vertical, 28)
        .frame(maxWidth: .infinity)
    }
}

private struct HostRow: View, Equatable {
    let alias: String
    let subtitle: String
    let isFavorite: Bool
    let isConditional: Bool
    let query: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "terminal").foregroundStyle(.secondary).padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                aliasText.font(.system(.body, design: .monospaced)).lineLimit(1)
                subtitleText.font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            if isFavorite { Image(systemName: "star.fill").foregroundStyle(.yellow).accessibilityLabel("已收藏") }
            if isConditional { Image(systemName: "line.3.horizontal.decrease.circle").foregroundStyle(.secondary).help("包含条件配置") }
        }.padding(.vertical, 5).help(alias)
    }

    private var aliasText: Text {
        query.isEmpty ? Text(alias) : Text(SearchHighlight.text(alias, query: query))
    }

    private var subtitleText: Text {
        query.isEmpty ? Text(subtitle) : Text(SearchHighlight.text(subtitle, query: query))
    }
}
