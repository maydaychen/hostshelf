import SwiftUI

struct SidebarView: View {
    @Bindable var store: AppStore
    @State private var showNewGroup = false
    @State private var groupName = ""

    var body: some View {
        List(selection: $store.sidebarSelection) {
            Section("主机目录") {
                Label("全部主机", systemImage: "server.rack").tag(SidebarFilter.all)
                Label("收藏", systemImage: "star").tag(SidebarFilter.favorites)
                Label("最近发起", systemImage: "clock").tag(SidebarFilter.recent)
            }
            Section {
                ForEach(store.groups, id: \.self) { group in
                    Label(group, systemImage: "folder").tag(SidebarFilter.group(group))
                        .contextMenu {
                            Button("删除空分组", role: .destructive) { _ = store.deleteEmptyGroup(group) }
                                .disabled(!store.metadataWritable || !store.canDeleteGroup(group))
                        }
                }
                Button { groupName = ""; showNewGroup = true } label: {
                    Label("新建分组", systemImage: "folder.badge.plus")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!store.metadataWritable)
                .accessibilityIdentifier("newGroupButton")
            } header: { Text("分组") }
            if !store.hostSources.isEmpty {
                Section("配置来源") {
                    ForEach(store.hostSources, id: \.self) { path in
                        Label(URL(fileURLWithPath: path).lastPathComponent, systemImage: "doc.text")
                            .tag(SidebarFilter.source(path))
                            .help(store.displayPath(path))
                            .contextMenu { Button("在 Finder 中显示") { store.showInFinder(path) } }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("HostShelf")
        .sheet(isPresented: $showNewGroup) {
            VStack(alignment: .leading, spacing: 16) {
                Text("新建分组").font(.title2.weight(.semibold))
                TextField("分组名称，例如“工作”", text: $groupName)
                    .onSubmit { createGroup() }
                Text("分组只保存在 HostShelf 中，不会修改 SSH 配置。")
                    .font(.callout).foregroundStyle(.secondary)
                HStack {
                    Spacer()
                    Button("取消", role: .cancel) { showNewGroup = false }
                    Button("创建") { createGroup() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(groupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if let error = store.metadataError { Text(error).font(.caption).foregroundStyle(.orange) }
            }.padding(24).frame(width: 370)
        }
    }

    private func createGroup() {
        if store.addGroup(groupName) { showNewGroup = false }
    }
}
