import AppKit
import HostShelfCore
import SwiftUI

struct QuickLauncherView: View {
    @Bindable var store: AppStore
    let focusToken: Int
    let onDismiss: () -> Void
    let onRevealHost: (String) -> Void

    @State private var query = ""
    @State private var selectedAlias: String?

    private var rankedHosts: [HostEntry] {
        store.quickLauncherHosts(for: query)
    }

    private var activeHost: HostEntry? {
        if let selectedAlias, let matched = rankedHosts.first(where: { $0.alias == selectedAlias }) {
            return matched
        }
        return rankedHosts.first
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                QuickLauncherSearchField(
                    text: $query,
                    focusToken: focusToken,
                    onMoveUp: { moveSelection(by: -1) },
                    onMoveDown: { moveSelection(by: 1) },
                    onSubmit: { connectSelected() },
                    onReveal: { revealSelected() },
                    onCopy: { copySelected() },
                    onCancel: onDismiss
                )
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("清除搜索")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            Divider()

            if rankedHosts.isEmpty {
                ContentUnavailableView(
                    store.hasScanned ? "没有匹配的主机" : "正在读取配置…",
                    systemImage: "magnifyingglass",
                    description: Text(store.hasScanned ? "换个别名、备注或主机地址关键字试试。" : "请稍候。")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(rankedHosts.prefix(60)) { host in
                                QuickLauncherRow(
                                    host: host,
                                    annotation: store.annotation(for: host.alias),
                                    query: query,
                                    isSelected: activeHost?.alias == host.alias
                                )
                                .id(host.alias)
                                .contentShape(Rectangle())
                                .onTapGesture(count: 2) {
                                    connect(host)
                                }
                                .onTapGesture {
                                    selectedAlias = host.alias
                                }
                            }
                        }
                        .padding(8)
                    }
                    .onChange(of: selectedAlias) { _, newValue in
                        if let newValue {
                            proxy.scrollTo(newValue, anchor: .center)
                        }
                    }
                }
            }

            Divider()

            HStack(spacing: 14) {
                Label("Return 用 \(store.preferredTerminal.displayName) 连接", systemImage: "return")
                Text("⌥Return 在主窗口定位")
                Text("⌘C 复制命令")
                Spacer()
                Text("Esc 关闭")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .frame(width: 600, height: 420)
        .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(.quaternary, lineWidth: 1))
        .onChange(of: query) { _, _ in
            selectedAlias = rankedHosts.first?.alias
        }
        .onAppear {
            selectedAlias = rankedHosts.first?.alias
        }
    }

    private func moveSelection(by delta: Int) {
        let visible = Array(rankedHosts.prefix(60))
        guard !visible.isEmpty else {
            selectedAlias = nil
            return
        }
        guard let current = activeHost,
              let index = visible.firstIndex(where: { $0.alias == current.alias }) else {
            selectedAlias = visible.first?.alias
            return
        }
        let next = min(visible.count - 1, max(0, index + delta))
        selectedAlias = visible[next].alias
    }

    private func connectSelected() {
        guard let host = activeHost else { return }
        connect(host)
    }

    private func connect(_ host: HostEntry) {
        onDismiss()
        store.connect(host)
    }

    private func revealSelected() {
        guard let host = activeHost else { return }
        onRevealHost(host.alias)
    }

    private func copySelected() {
        guard let host = activeHost else { return }
        store.copyCommand(host)
        onDismiss()
    }
}

private struct QuickLauncherRow: View {
    let host: HostEntry
    let annotation: HostAnnotation
    let query: String
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "terminal")
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(SearchHighlight.text(host.alias, query: query))
                        .font(.system(.body, design: .monospaced).weight(.medium))
                        .lineLimit(1)
                    if !annotation.group.isEmpty {
                        Text(annotation.group)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
                    }
                }
                Text(SearchHighlight.text(HostListPresentation.subtitle(for: host, annotation: annotation), query: query))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if annotation.lastLaunchedAt != nil {
                Image(systemName: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if annotation.isFavorite {
                Image(systemName: "star.fill")
                    .font(.caption)
                    .foregroundStyle(.yellow)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.16) : Color.clear)
        )
    }
}

private struct QuickLauncherSearchField: NSViewRepresentable {
    @Binding var text: String
    let focusToken: Int
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onSubmit: () -> Void
    let onReveal: () -> Void
    let onCopy: () -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> LauncherTextField {
        let field = LauncherTextField()
        field.placeholderString = "快速连接主机（支持模糊匹配）"
        field.stringValue = text
        field.font = .systemFont(ofSize: 16)
        field.textColor = .labelColor
        field.isBezeled = false
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.usesSingleLineMode = true
        field.delegate = context.coordinator
        field.onWindowReady = { [weak coordinator = context.coordinator] in
            coordinator?.focusIfNeeded()
        }
        field.onCopyWithoutSelection = { [weak coordinator = context.coordinator] in
            coordinator?.representable.onCopy()
        }
        return field
    }

    func updateNSView(_ field: LauncherTextField, context: Context) {
        context.coordinator.representable = self
        if field.stringValue != text { field.stringValue = text }
        context.coordinator.focusIfNeeded()
    }

    final class LauncherTextField: NSTextField {
        var onWindowReady: (() -> Void)?
        var onCopyWithoutSelection: (() -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onWindowReady?()
        }

        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if flags == [.command], event.charactersIgnoringModifiers?.lowercased() == "c" {
                let hasSelectedQueryText = (currentEditor()?.selectedRange.length ?? 0) > 0
                if !hasSelectedQueryText {
                    onCopyWithoutSelection?()
                    return true
                }
            }
            return super.performKeyEquivalent(with: event)
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var representable: QuickLauncherSearchField
        private var consumedToken = 0

        init(_ representable: QuickLauncherSearchField) {
            self.representable = representable
        }

        func focusIfNeeded() {
            guard representable.focusToken > consumedToken else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self,
                      let window = NSApp.keyWindow,
                      let field = Self.findTextField(in: window.contentView) else { return }
                if window.makeFirstResponder(field) {
                    self.consumedToken = self.representable.focusToken
                    field.currentEditor()?.selectAll(nil)
                }
            }
        }

        private static func findTextField(in root: NSView?) -> LauncherTextField? {
            guard let root else { return nil }
            if let match = root as? LauncherTextField { return match }
            for subview in root.subviews {
                if let match = findTextField(in: subview) { return match }
            }
            return nil
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField,
                  representable.text != field.stringValue else { return }
            representable.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.moveUp(_:)):
                representable.onMoveUp()
                return true
            case #selector(NSResponder.moveDown(_:)):
                representable.onMoveDown()
                return true
            case #selector(NSResponder.insertNewline(_:)),
                 #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
                if NSApp.currentEvent?.modifierFlags.contains(.option) == true {
                    representable.onReveal()
                } else {
                    representable.onSubmit()
                }
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                representable.onCancel()
                return true
            default:
                return false
            }
        }
    }
}
