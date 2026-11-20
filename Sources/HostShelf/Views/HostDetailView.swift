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
                    VStack(alignment: .leading, spacing: 20) {
                        header(isCompactLabels: isCompactLabels, isCompactButtons: isCompactButtons)
                        overview(isWide: isWideOverview) { proxy.scrollTo("declarations", anchor: .top) }
                        HostMetadataSection(store: store, alias: host.alias)
                        Divider()
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
                            excerpts: displayedExcerpts,
                            isLoadingExcerpts: isLoadingExcerpts,
                            expandedSources: $expandedSources,
                            highlightedSource: highlightedSource,
                            scrollRequest: scrollRequest
                        )
                    }
                    .padding(.horizontal, 24).padding(.vertical, 20)
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
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(host.alias)
                        .font(.system(.title2, design: .monospaced).weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("selectedHostAlias")
                    if isCompactLabels {
                        VStack(alignment: .leading, spacing: 6) { identityLabels }
                    } else {
                        HStack(spacing: 8) { identityLabels }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                Button { store.toggleFavorite(host.alias) } label: {
                    Image(systemName: annotation.isFavorite ? "star.fill" : "star")
                        .foregroundStyle(annotation.isFavorite ? Color.yellow : Color.secondary)
                }
                .accessibilityLabel(annotation.isFavorite ? "取消收藏" : "收藏主机")
                .help(annotation.isFavorite ? "取消收藏" : "收藏主机")
                .disabled(!store.metadataWritable)
            }
            if isCompactButtons {
                VStack(alignment: .leading, spacing: 8) { connectionButtons }
            } else {
                HStack(spacing: 8) { connectionButtons }
            }
            Text("使用主机别名连接，实际参数由系统 SSH 解释。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var identityLabels: some View {
        Text(annotation.group.isEmpty ? "未分组" : annotation.group)
            .font(.caption).padding(.horizontal, 7).padding(.vertical, 3)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 4))
            .fixedSize(horizontal: false, vertical: true)
        if hasConditions {
            Label("含条件声明", systemImage: "line.3.horizontal.decrease.circle")
                .font(.caption).foregroundStyle(.secondary)
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
    }

    private func overview(isWide: Bool, showDeclarations: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("声明概览").font(.headline)
                Spacer(minLength: 8)
                Text("以下为配置声明").font(.caption).foregroundStyle(.secondary)
            }
            if isWide {
                HStack(alignment: .top, spacing: 16) {
                    overviewValue("HostName", label: "地址", showDeclarations: showDeclarations).frame(minWidth: 210)
                    overviewValue("User", label: "用户", showDeclarations: showDeclarations).frame(minWidth: 100)
                    overviewValue("Port", label: "端口", showDeclarations: showDeclarations).frame(minWidth: 80)
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    overviewValue("HostName", label: "地址", showDeclarations: showDeclarations)
                    HStack(alignment: .top, spacing: 16) {
                        overviewValue("User", label: "用户", showDeclarations: showDeclarations)
                        overviewValue("Port", label: "端口", showDeclarations: showDeclarations)
                    }
                }
            }
        }
    }

    private func overviewValue(_ keyword: String, label: String, showDeclarations: @escaping () -> Void) -> some View {
        let declarations = host.declarations.filter { $0.keyword.lowercased() == keyword.lowercased() }
        return VStack(alignment: .leading, spacing: 5) {
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
