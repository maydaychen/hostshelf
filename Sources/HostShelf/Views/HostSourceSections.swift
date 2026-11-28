import AppKit
import HostShelfCore
import SwiftUI

struct HostDeclarationsSection: View {
    var store: AppStore
    let host: HostEntry
    let revealSource: (SourceLocation) -> Void

    private var groupedDeclarations: [(path: String, declarations: [SSHDeclaration])] {
        let grouped = Dictionary(grouping: host.declarations, by: { $0.location.filePath })
        var seen: Set<String> = []
        return host.declarations.compactMap { declaration in
            let path = declaration.location.filePath
            guard seen.insert(path).inserted, let items = grouped[path] else { return nil }
            return (path: path, declarations: items)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: HostShelfSpacing.s16) {
            Text("全部声明").hostSectionTitle()
            Text("按来源文件分组。声明可能受公共规则、顺序或条件影响；点击行号查看原文。")
                .font(.caption).foregroundStyle(.secondary)
            if host.declarations.isEmpty {
                Text("此别名没有可展示的独立参数；可能使用公共规则或默认设置。")
                    .font(.callout).foregroundStyle(.secondary)
            }
            ForEach(groupedDeclarations, id: \.path) { group in
                let path = group.path
                let declarations = group.declarations
                let keywordWidth = HostListPresentation.keywordColumnWidth(declarations.map(\.keyword))
                VStack(alignment: .leading, spacing: HostShelfSpacing.s8) {
                    Label(store.displayPath(path), systemImage: "doc.text")
                        .font(.caption.monospaced()).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Grid(alignment: .leading, horizontalSpacing: HostShelfSpacing.s12, verticalSpacing: HostShelfSpacing.s8) {
                        GridRow {
                            Text("指令").frame(width: keywordWidth, alignment: .leading)
                            Text("声明值").frame(maxWidth: .infinity, alignment: .leading)
                            Text("行号").gridColumnAlignment(.trailing)
                        }.font(.caption).foregroundStyle(.secondary)
                        Divider().gridCellColumns(3)
                        ForEach(Array(declarations.enumerated()), id: \.offset) { _, declaration in
                            GridRow(alignment: .top) {
                                Text(declaration.keyword)
                                    .frame(width: keywordWidth, alignment: .leading)
                                    .fixedSize(horizontal: false, vertical: true)
                                VStack(alignment: .leading, spacing: HostShelfSpacing.s4) {
                                    Text(declaration.value).fixedSize(horizontal: false, vertical: true)
                                    if declaration.isConditional {
                                        Text("含条件声明").font(.caption2).foregroundStyle(.secondary)
                                    }
                                }.frame(maxWidth: .infinity, alignment: .leading)
                                Button(String(declaration.location.line)) { revealSource(declaration.location) }
                                    .buttonStyle(.link)
                                    .fixedSize()
                                    .accessibilityLabel("查看 \(store.displayPath(path)) 第 \(declaration.location.line) 行")
                                    .help("展开来源片段并定位第 \(declaration.location.line) 行")
                                    .contextMenu {
                                        Button("在 \(store.preferredEditor.displayName) 中打开第 \(declaration.location.line) 行") {
                                            store.openSourceInEditor(path: path, line: declaration.location.line)
                                        }
                                        .disabled(!store.isEditorAvailable(store.preferredEditor))
                                    }
                            }.font(.system(.callout, design: .monospaced))
                        }
                    }
                }
            }
        }
    }
}

struct HostSourceExcerptsSection: View {
    var store: AppStore
    let sourcePaths: [String]
    var preferredLines: [String: Int] = [:]
    let excerpts: [SourceExcerpt]
    let isLoadingExcerpts: Bool
    @Binding var expandedSources: Set<String>
    let highlightedSource: SourceLocation?
    let scrollRequest: SourceScrollRequest?

    private var excerptsByPath: [String: SourceExcerpt] {
        Dictionary(uniqueKeysWithValues: excerpts.map { ($0.location.filePath, $0) })
    }

    var body: some View {
        let excerptsByPath = excerptsByPath
        VStack(alignment: .leading, spacing: HostShelfSpacing.s12) {
            Text("来源片段").hostSectionTitle()
            ForEach(sourcePaths, id: \.self) { path in
                let excerpt = excerptsByPath[path]
                VStack(alignment: .leading, spacing: HostShelfSpacing.s8) {
                    HStack(alignment: .top, spacing: HostShelfSpacing.s8) {
                        DisclosureGroup(isExpanded: Binding(
                            get: { expandedSources.contains(path) },
                            set: { expanded in
                                if expanded { expandedSources.insert(path) }
                                else { expandedSources.remove(path) }
                            }
                        )) {
                            if let excerpt {
                                if !excerpt.lines.isEmpty { code(excerpt) }
                            } else {
                                Text(isLoadingExcerpts ? "正在读取来源片段…" : "展开以读取来源片段。")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        } label: {
                            Text(store.displayPath(path))
                                .font(.caption.monospaced())
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Button { store.openSourceInEditor(path: path, line: preferredLines[path] ?? 1) } label: {
                            Image(systemName: "square.and.pencil")
                        }
                        .accessibilityLabel("在编辑器中打开 \(store.displayPath(path))")
                        .help("在 \(store.preferredEditor.displayName) 中打开并跳转到定义行")
                        .disabled(!store.isEditorAvailable(store.preferredEditor))
                        Button { store.showInFinder(path) } label: {
                            Image(systemName: "folder")
                        }
                        .accessibilityLabel("在 Finder 中显示 \(store.displayPath(path))")
                        .help("在 Finder 中显示源文件")
                    }
                    if let error = excerpt?.error {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }
            }
        }
    }

    private func code(_ excerpt: SourceExcerpt) -> some View {
        ScrollView(.horizontal) {
            Grid(alignment: .leading, horizontalSpacing: HostShelfSpacing.s10, verticalSpacing: 3) {
                ForEach(Array(excerpt.lines.enumerated()), id: \.element.number) { index, line in
                    if index > 0 && line.number > excerpt.lines[index - 1].number + 1 {
                        Text("⋯ 中间行已省略 ⋯").font(.caption2).foregroundStyle(.secondary)
                            .gridCellColumns(2)
                    }
                    let location = SourceLocation(filePath: excerpt.location.filePath, line: line.number)
                    GridRow(alignment: .firstTextBaseline) {
                        Text(String(line.number)).foregroundStyle(.secondary)
                            .fixedSize().frame(minWidth: 32, alignment: .trailing)
                            .gridColumnAlignment(.trailing)
                        Text(line.text.isEmpty ? " " : line.text)
                            .fixedSize()
                            .padding(.horizontal, HostShelfSpacing.s4)
                            .background(highlightedSource == location ? Color.accentColor.opacity(0.18) : Color.clear)
                            .background {
                                SourceLineScrollAnchor(request: scrollRequest?.location == location ? scrollRequest : nil)
                                    .allowsHitTesting(false)
                                    .accessibilityHidden(true)
                            }
                            .accessibilityIdentifier("sourceLine-\(location.id)")
                            .id(location)
                    }.font(.system(.caption, design: .monospaced))
                }
            }.padding(HostShelfSpacing.s10)
        }
        .hostSurface(HostShelfSurface.text, cornerRadius: HostShelfRadius.small)
    }
}

@MainActor
final class SourceScrollRequest {
    let location: SourceLocation
    private let maxAttempts = 5
    private var attempts = 0
    private var isQueued = false
    private weak var queuedAnchor: NSView?
    private var isCompleted = false
    private(set) var isInvalidated = false

    init(location: SourceLocation) {
        self.location = location
    }

    func invalidate() {
        isInvalidated = true
        isQueued = false
        queuedAnchor = nil
    }

    func prepare(anchor: NSView) -> Bool {
        guard !isInvalidated, !isCompleted, attempts < maxAttempts else { return false }
        if isQueued, queuedAnchor === anchor { return false }
        isQueued = true
        queuedAnchor = anchor
        return true
    }

    func canBeginAttempt(anchor: NSView) -> Bool {
        !isInvalidated && !isCompleted && attempts < maxAttempts && queuedAnchor === anchor
    }

    func isCurrentOwner(anchor: NSView) -> Bool {
        !isInvalidated && !isCompleted && queuedAnchor === anchor
    }

    func recordAttempt() {
        attempts += 1
    }

    func markCompleted() {
        isCompleted = true
    }

    func finishDispatch(anchor: NSView) {
        guard queuedAnchor === anchor else { return }
        isQueued = false
        queuedAnchor = nil
    }
}

private struct SourceLineScrollAnchor: NSViewRepresentable {
    let request: SourceScrollRequest?

    func makeNSView(context: Context) -> AnchorView { AnchorView() }

    func updateNSView(_ nsView: AnchorView, context: Context) {
        nsView.requestScroll(request)
    }

    final class AnchorView: NSView {
        private var activeRequest: SourceScrollRequest?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil {
                activeRequest?.finishDispatch(anchor: self)
            } else {
                scheduleScroll()
            }
        }

        override func layout() {
            super.layout()
            scheduleScroll()
        }

        func requestScroll(_ request: SourceScrollRequest?) {
            if activeRequest !== request {
                activeRequest?.finishDispatch(anchor: self)
                activeRequest = request
            }
            scheduleScroll()
        }

        private func scheduleScroll() {
            guard let request = activeRequest, window != nil,
                  request.prepare(anchor: self) else { return }
            DispatchQueue.main.async { [weak self, weak request] in
                defer {
                    MainActor.assumeIsolated {
                        if let self, let request {
                            request.finishDispatch(anchor: self)
                        }
                    }
                }
                guard let self, let request, self.activeRequest === request, self.window != nil,
                      request.canBeginAttempt(anchor: self) else { return }
                request.recordAttempt()
                self.window?.contentView?.layoutSubtreeIfNeeded()
                guard self.activeRequest === request, self.window != nil,
                      request.isCurrentOwner(anchor: self), self.bounds.height > 0 else { return }
                var ancestor = self.superview
                while let view = ancestor {
                    if let scrollView = view as? NSScrollView, scrollView.hasVerticalScroller,
                       let document = scrollView.documentView {
                        // A line lives inside a horizontal scroll view. Scroll its vertical ancestor explicitly.
                        let line = document.convert(self.bounds, from: self)
                        let visible = scrollView.contentView.documentVisibleRect
                        let target = NSRect(x: visible.minX, y: line.minY - 8, width: 1, height: line.height + 16)
                        _ = document.scrollToVisible(target)
                        let lineArea = NSRect(x: visible.minX, y: line.minY, width: 1, height: line.height)
                        if scrollView.contentView.documentVisibleRect.intersects(lineArea) {
                            request.markCompleted()
                        }
                        return
                    }
                    ancestor = view.superview
                }
            }
        }
    }
}
