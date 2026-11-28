import HostShelfCore
import SwiftUI

struct HostMetadataSection: View {
    @Bindable var store: AppStore
    let alias: String
    @State private var isEditing = false
    @State private var draftNote = ""
    @State private var draftGroup = ""
    @State private var draftTagsText = ""

    private var annotation: HostAnnotation { store.annotation(for: alias) }

    var body: some View {
        VStack(alignment: .leading, spacing: HostShelfSpacing.s10) {
            HStack(alignment: .firstTextBaseline, spacing: HostShelfSpacing.s12) {
                Text("本地备注").hostSectionTitle()
                Spacer(minLength: HostShelfSpacing.s8)
                Button(isEditing ? "完成" : "编辑分组与备注") {
                    if isEditing {
                        if store.flushAnnotation(alias: alias) { isEditing = false }
                    } else {
                        restoreDraft()
                        isEditing = true
                    }
                }
                .buttonStyle(.link)
                .disabled(!store.metadataWritable)
                .accessibilityIdentifier("editHostMetadata")
            }
            if isEditing {
                Picker("分组", selection: Binding(get: { draftGroup }, set: {
                    draftGroup = $0
                    stageDraft()
                })) {
                    Text("未分组").tag("")
                    ForEach(store.groups, id: \.self) { Text($0).tag($0) }
                }.disabled(!store.metadataWritable)
                TextField("标签，例如 prod, hk（空格或逗号分隔）", text: Binding(get: { draftTagsText }, set: {
                    draftTagsText = $0
                    stageDraft()
                }))
                .textFieldStyle(.roundedBorder)
                .disabled(!store.metadataWritable)
                .accessibilityLabel("主机标签")
                .accessibilityIdentifier("hostTags")
                TextEditor(text: Binding(get: { draftNote }, set: {
                    draftNote = $0
                    stageDraft()
                }))
                .font(.body)
                .frame(minHeight: 65, idealHeight: 85, maxHeight: 120)
                .scrollContentBackground(.hidden)
                .padding(HostShelfSpacing.s6)
                .hostSurface(HostShelfSurface.text, cornerRadius: HostShelfRadius.small)
                .disabled(!store.metadataWritable)
                .accessibilityLabel("主机备注")
                .accessibilityIdentifier("hostNote")
                Toggle("连接前需要二次确认", isOn: Binding(
                    get: { annotation.requiresConfirmation },
                    set: { store.setRequiresConfirmation($0, for: alias) }
                ))
                .disabled(!store.metadataWritable)
                .accessibilityIdentifier("requiresConfirmationToggle")
                Text("停止输入后自动保存到本机；点击“完成”立即保存，不会写回 SSH 配置。")
                    .font(.caption).foregroundStyle(.secondary)
                if store.pendingAnnotationAliases.contains(alias) {
                    Label("正在等待保存…", systemImage: "clock")
                        .font(.caption).foregroundStyle(.secondary)
                } else if store.unsavedAnnotations[alias] != nil {
                    Label("修改尚未保存；本次运行期间保留草稿。", systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                }
            } else {
                Text(annotation.note.isEmpty ? "暂无备注。可添加此主机的用途和注意事项。" : annotation.note)
                    .font(.callout)
                    .foregroundStyle(annotation.note.isEmpty ? Color.secondary : Color.primary)
                    .fixedSize(horizontal: false, vertical: true)
                if !annotation.tags.isEmpty {
                    TagFlowLayout(spacing: HostShelfSpacing.s4) {
                        ForEach(annotation.tags, id: \.self) { tag in
                            HostTag(tag)
                        }
                    }
                }
                if let reason = store.confirmationReason(for: alias) {
                    Label(reason, systemImage: "shield.lefthalf.filled")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            if let launched = annotation.lastLaunchedAt {
                Text("最近发起：\(launched.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .onAppear {
            if store.unsavedAnnotations[alias] != nil {
                restoreDraft()
                isEditing = true
            }
        }
        .onDisappear { _ = store.flushAnnotation(alias: alias) }
    }

    private func restoreDraft() {
        let draft = store.unsavedAnnotations[alias] ?? annotation
        draftGroup = draft.group
        draftNote = draft.note
        draftTagsText = draft.tags.joined(separator: ", ")
    }

    private func stageDraft() {
        store.stageAnnotation(
            alias: alias,
            group: draftGroup,
            note: draftNote,
            tags: HostAnnotation.parseTagsInput(draftTagsText)
        )
    }
}

private struct TagFlowLayout: Layout {
    var spacing: CGFloat = HostShelfSpacing.s4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var totalHeight: CGFloat = 0
        var rowHeight: CGFloat = 0
        var measuredWidth: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth > 0 && rowWidth + spacing + size.width > maxWidth {
                measuredWidth = max(measuredWidth, rowWidth)
                totalHeight += rowHeight + spacing
                rowWidth = size.width
                rowHeight = size.height
            } else {
                rowWidth = rowWidth > 0 ? rowWidth + spacing + size.width : size.width
                rowHeight = max(rowHeight, size.height)
            }
        }
        measuredWidth = max(measuredWidth, rowWidth)
        totalHeight += rowHeight
        return CGSize(width: measuredWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
