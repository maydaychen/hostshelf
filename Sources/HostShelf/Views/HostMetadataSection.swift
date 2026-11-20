import HostShelfCore
import SwiftUI

struct HostMetadataSection: View {
    @Bindable var store: AppStore
    let alias: String
    @State private var isEditing = false
    @State private var draftNote = ""
    @State private var draftGroup = ""

    private var annotation: HostAnnotation { store.annotation(for: alias) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("本地备注").font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 8)
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
                TextEditor(text: Binding(get: { draftNote }, set: {
                    draftNote = $0
                    stageDraft()
                }))
                .font(.body)
                .frame(minHeight: 65, idealHeight: 85, maxHeight: 120)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(.background, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
                .disabled(!store.metadataWritable)
                .accessibilityLabel("主机备注")
                .accessibilityIdentifier("hostNote")
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
            }
            if let launched = annotation.lastLaunchedAt {
                Text("最近发起：\(launched.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
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
    }

    private func stageDraft() {
        store.stageAnnotation(alias: alias, group: draftGroup, note: draftNote)
    }
}
