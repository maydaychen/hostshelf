import HostShelfCore
import SwiftUI

struct HostDetailView: View {
    @Bindable var store: AppStore
    let host: HostEntry
    @State private var excerpts: [SourceExcerpt] = []
    @State private var loadedScan: Date?
    @State private var isLoadingExcerpts = false
    @State private var activeExcerptLoad: ActiveExcerptLoad?
    @State private var expandedSources: Set<String> = []
    @State private var highlightedSource: SourceLocation?
    @State private var scrollRequest: SourceScrollRequest?

    private var annotation: HostAnnotation { store.annotation(for: host.alias) }
    private var hasConditions: Bool { host.isConditional || host.declarations.contains(where: \.isConditional) }
    private var sourcePaths: [String] {
        Set(host.locations.map(\.filePath) + host.declarations.map { $0.location.filePath }).sorted()
    }
    private var preferredLinesByPath: [String: Int] {
        var lines: [String: Int] = [:]
        for location in host.locations where lines[location.filePath] == nil {
            lines[location.filePath] = location.line
        }
        for declaration in host.declarations where lines[declaration.location.filePath] == nil {
            lines[declaration.location.filePath] = declaration.location.line
        }
        return lines
    }
    private var displayedExcerpts: [SourceExcerpt] {
        loadedScan == store.snapshot.scannedAt ? excerpts : []
    }

    var body: some View {
        let loadKey = ExcerptLoadKey(alias: host.alias, scannedAt: store.snapshot.scannedAt, needsLoad: !expandedSources.isEmpty)
        GeometryReader { geometry in
            let contentWidth = max(0, geometry.size.width - 64)
            let isCompactLabels = max(0, contentWidth - 48) < 280 || annotation.group.count > 24
            let isCompactButtons = contentWidth < 260
            let isWideOverview = contentWidth >= 422

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: HostShelfSpacing.s20) {
                        header(isCompactLabels: isCompactLabels, isCompactButtons: isCompactButtons)
                        overview(isWide: isWideOverview) { proxy.scrollTo("declarations", anchor: .top) }
                        Divider()
                        HostMetadataSection(store: store, alias: host.alias)
                        Divider()
                        HostTopologySection(store: store, host: host)
                        HostDeclarationsSection(store: store, host: host) { location in
                            scrollRequest?.invalidate()
                            expandedSources.insert(location.filePath)
                            highlightedSource = location
                            scrollRequest = SourceScrollRequest(location: location)
                        }.id("declarations")
                        Divider()
                        HostSourceExcerptsSection(
                            store: store,
                            sourcePaths: sourcePaths,
                            preferredLines: preferredLinesByPath,
                            excerpts: displayedExcerpts,
                            isLoadingExcerpts: isLoadingExcerpts,
                            expandedSources: $expandedSources,
                            highlightedSource: highlightedSource,
                            scrollRequest: scrollRequest
                        )
                    }
                    .padding(.horizontal, HostShelfSpacing.s24).padding(.vertical, HostShelfSpacing.s20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .onChange(of: store.snapshot.scannedAt) { _, _ in
            expandedSources.formIntersection(sourcePaths)
            highlightedSource = nil
            scrollRequest?.invalidate()
            scrollRequest = nil
            if activeExcerptLoad?.scannedAt != store.snapshot.scannedAt {
                activeExcerptLoad = nil
                isLoadingExcerpts = false
            }
            if expandedSources.isEmpty {
                excerpts = []
                loadedScan = nil
            }
        }
        .onDisappear {
            scrollRequest?.invalidate()
            scrollRequest = nil
            activeExcerptLoad = nil
        }
        .task(id: loadKey) {
            let targetScan = loadKey.scannedAt
            guard !Task.isCancelled, loadKey.needsLoad, !expandedSources.isEmpty,
                  store.snapshot.scannedAt == targetScan, loadedScan != targetScan else { return }
            let load = ActiveExcerptLoad(id: UUID(), scannedAt: targetScan)
            activeExcerptLoad = load
            isLoadingExcerpts = true
            let result = await store.loadExcerpts(for: host)
            #if DEBUG
            defer { store.excerptLoadDidFinish?(result) }
            #endif
            guard !Task.isCancelled, activeExcerptLoad == load, store.snapshot.scannedAt == targetScan else {
                if activeExcerptLoad == load {
                    isLoadingExcerpts = false
                    activeExcerptLoad = nil
                }
                return
            }
            excerpts = result
            loadedScan = targetScan
            isLoadingExcerpts = false
            activeExcerptLoad = nil
        }
        .textSelection(.enabled)
    }

    private func header(isCompactLabels: Bool, isCompactButtons: Bool) -> some View {
        VStack(alignment: .leading, spacing: HostShelfSpacing.s12) {
            HStack(alignment: .top, spacing: HostShelfSpacing.s12) {
                VStack(alignment: .leading, spacing: HostShelfSpacing.s6) {
                    Text(host.alias)
                        .font(.system(.title2, design: .monospaced).weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("selectedHostAlias")
                    if isCompactLabels {
                        VStack(alignment: .leading, spacing: HostShelfSpacing.s6) { identityLabels }
                    } else {
                        HStack(spacing: HostShelfSpacing.s8) { identityLabels }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                Button { store.toggleFavorite(host.alias) } label: {
                    Image(systemName: annotation.isFavorite ? "star.fill" : "star")
                        .font(.title3)
                        .foregroundStyle(annotation.isFavorite ? Color.yellow : Color.secondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(annotation.isFavorite ? "取消收藏" : "收藏主机")
                .help(annotation.isFavorite ? "取消收藏" : "收藏主机")
                .disabled(!store.metadataWritable)
            }
            Group {
                if isCompactButtons {
                    VStack(alignment: .leading, spacing: HostShelfSpacing.s8) { connectionButtons }
                } else {
                    HStack(spacing: HostShelfSpacing.s8) { connectionButtons }
                }
            }
            .controlSize(.regular)
            Text("使用主机别名连接，实际参数由系统 SSH 解释。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var identityLabels: some View {
        HostChip(annotation.group.isEmpty ? "未分组" : annotation.group)
            .fixedSize(horizontal: false, vertical: true)
        if hasConditions {
            Label("含条件声明", systemImage: "line.3.horizontal.decrease.circle")
                .font(.caption).foregroundStyle(.secondary)
        }
        if store.requiresConnectionConfirmation(for: host.alias) {
            Label("需连接确认", systemImage: "shield.lefthalf.filled")
                .font(.caption).foregroundStyle(.orange)
        }
        Text("\(sourcePaths.count) 个声明来源").font(.caption).foregroundStyle(.secondary)
    }

    @ViewBuilder private var connectionButtons: some View {
        Button { store.connect(host) } label: {
            Label(store.isConnecting ? "正在交给终端…" : "在 \(store.preferredTerminal.displayName) 中连接", systemImage: "terminal")
        }
        .buttonStyle(.borderedProminent)
        .disabled(store.isConnecting)
        .help("交给 \(store.preferredTerminal.displayName) 连接（⌘Return）")
        .accessibilityIdentifier("connectHost")
        Button { store.copyCommand(host) } label: { Image(systemName: "doc.on.doc") }
            .accessibilityLabel("复制命令")
            .help("复制连接命令")
        Menu {
            HostMoreActionsMenuContent(store: store, host: host)
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuIndicator(.hidden)
        .accessibilityLabel("更多操作")
        .help("更多连接、复制与编辑器操作")
        .accessibilityIdentifier("moreHostActions")
    }

    private func overview(isWide: Bool, showDeclarations: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: HostShelfSpacing.s12) {
            HStack {
                Text("声明概览").hostSectionTitle()
                Spacer(minLength: HostShelfSpacing.s8)
                Text("以下为配置声明").font(.caption).foregroundStyle(.secondary)
            }
            if isWide {
                HStack(alignment: .top, spacing: HostShelfSpacing.s16) {
                    overviewValue("HostName", label: "地址", showDeclarations: showDeclarations).frame(minWidth: 210)
                    overviewValue("User", label: "用户", showDeclarations: showDeclarations).frame(minWidth: 100)
                    overviewValue("Port", label: "端口", showDeclarations: showDeclarations).frame(minWidth: 80)
                }
            } else {
                VStack(alignment: .leading, spacing: HostShelfSpacing.s12) {
                    overviewValue("HostName", label: "地址", showDeclarations: showDeclarations)
                    HStack(alignment: .top, spacing: HostShelfSpacing.s16) {
                        overviewValue("User", label: "用户", showDeclarations: showDeclarations)
                        overviewValue("Port", label: "端口", showDeclarations: showDeclarations)
                    }
                }
            }
        }
    }

    private func overviewValue(_ keyword: String, label: String, showDeclarations: @escaping () -> Void) -> some View {
        let declarations = host.declarations.filter { $0.keyword.lowercased() == keyword.lowercased() }
        return VStack(alignment: .leading, spacing: HostShelfSpacing.s4) {
            Text(keyword).font(.caption).foregroundStyle(.secondary).help(label)
            if declarations.count > 1 {
                Button("\(declarations.count) 处声明", action: showDeclarations)
                    .buttonStyle(.link)
                    .accessibilityLabel("\(keyword) 有 \(declarations.count) 处声明，查看全部声明")
            } else if let declaration = declarations.first {
                Text(declaration.value).font(.system(.callout, design: .monospaced))
                    .fixedSize(horizontal: false, vertical: true)
                if declaration.isConditional {
                    Text("含条件声明").font(.caption2).foregroundStyle(.secondary)
                }
            } else {
                Text("未声明").font(.callout).foregroundStyle(.secondary)
                Text("由 SSH 判断").font(.caption2).foregroundStyle(.secondary)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ActiveExcerptLoad: Equatable {
    let id: UUID
    let scannedAt: Date
}

private struct ExcerptLoadKey: Equatable {
    let alias: String
    let scannedAt: Date
    let needsLoad: Bool
}

struct HostMoreActionsMenuContent: View {
    var store: AppStore
    let host: HostEntry

    var body: some View {
        Menu("使用其他终端连接") {
            ForEach(store.availableTerminals(), id: \.target) { item in
                let label = item.availability.unavailableReason.map {
                    "\(item.target.displayName)（\($0)）"
                } ?? item.target.displayName
                Button(label) { store.connect(host, target: item.target) }
                    .disabled(store.isConnecting || !item.availability.isAvailable)
            }
        }
        Menu("在 Remote-SSH 中打开") {
            ForEach(EditorTarget.remoteSSHTargets) { editor in
                let available = store.isEditorAvailable(editor)
                Button(available ? editor.displayName : "\(editor.displayName)（未安装）") {
                    store.openRemoteSSH(host, editor: editor)
                }
                .disabled(!available)
            }
        }
        Divider()
        Button("复制主机地址（HostName）") { store.copyHostName(host) }
            .disabled(ExternalActionBuilder.singleDeclaredAddress(for: host) == nil)
        Button("复制 User@HostName") { store.copyUserAtHost(host) }
            .disabled(ExternalActionBuilder.userAtHostAddress(for: host) == nil)
        Button("复制 SCP 命令模板") { store.copySCPCommand(host) }
        Divider()
        Button("仅建立 SSH 隧道（-N）") { store.connectTunnel(host) }
            .disabled(store.isConnecting)
        Button("复制隧道命令") { store.copyTunnelCommand(host) }
        Divider()
        Button("在 \(store.preferredEditor.displayName) 中打开配置") {
            store.openHostConfigInEditor(host)
        }
        .disabled(host.locations.isEmpty || !store.isEditorAvailable(store.preferredEditor))
        Menu("用指定编辑器打开配置") {
            ForEach(EditorTarget.allCases) { editor in
                let available = store.isEditorAvailable(editor)
                Button(available ? editor.displayName : "\(editor.displayName)（未安装）") {
                    store.openHostConfigInEditor(host, editor: editor)
                }
                .disabled(host.locations.isEmpty || !available)
            }
        }
    }
}
