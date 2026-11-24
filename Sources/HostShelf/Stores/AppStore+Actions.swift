import AppKit
import Foundation
import HostShelfCore

@MainActor
extension AppStore {
    var allTags: [String] {
        var merged: Set<String> = []
        for (alias, saved) in metadata.annotations {
            if let draft = unsavedAnnotations[alias] {
                merged.formUnion(draft.tags)
            } else {
                merged.formUnion(saved.tags)
            }
        }
        for (alias, draft) in unsavedAnnotations where metadata.annotations[alias] == nil {
            merged.formUnion(draft.tags)
        }
        return merged.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    func quickLauncherHosts(for query: String) -> [HostEntry] {
        FuzzyMatcher.rankForQuickLauncher(
            hosts: sortedHosts,
            annotation: { annotation(for: $0) },
            query: query
        )
    }

    func availableTerminals() -> [(target: TerminalTarget, availability: TerminalAvailability)] {
        TerminalTarget.allCases.map { ($0, launcher.availability(for: $0)) }
    }

    func isEditorAvailable(_ editor: EditorTarget) -> Bool {
        externalLauncher.isAvailable(editor)
    }

    func isGroupProtected(_ group: String) -> Bool {
        !group.isEmpty && metadata.protectedGroups.contains(group)
    }

    func confirmationReason(for alias: String) -> String? {
        let note = annotation(for: alias)
        let hostProtected = note.requiresConfirmation
        let groupProtected = !note.group.isEmpty && isGroupProtected(note.group)
        if hostProtected && groupProtected {
            return "此主机与分组「\(note.group)」均已启用高危连接确认。"
        }
        if hostProtected {
            return "此主机已标记为连接前需二次确认。"
        }
        if groupProtected {
            return "此主机所属分组「\(note.group)」已启用高危连接确认。"
        }
        return nil
    }

    func requiresConnectionConfirmation(for alias: String) -> Bool {
        confirmationReason(for: alias) != nil
    }

    func setRequiresConfirmation(_ enabled: Bool, for alias: String) {
        var candidate = metadata
        var note = annotation(for: alias)
        note.requiresConfirmation = enabled
        candidate.annotations[alias] = note
        if persist(candidate) {
            if var draft = unsavedAnnotations[alias] {
                draft.requiresConfirmation = enabled
                unsavedAnnotations[alias] = draft
            }
            reconcileSelection()
        }
    }

    func toggleGroupProtection(_ group: String) {
        guard !group.isEmpty else { return }
        var candidate = metadata
        if candidate.protectedGroups.contains(group) {
            candidate.protectedGroups.removeAll { $0 == group }
        } else {
            candidate.protectedGroups.append(group)
        }
        _ = persist(candidate)
    }

    func confirmPendingConnection() {
        guard let pending = pendingConfirmation else { return }
        pendingConfirmation = nil
        connect(pending.host, target: pending.target, mode: pending.mode, bypassConfirmation: true)
    }

    func cancelPendingConnection() {
        pendingConfirmation = nil
    }

    func connectTunnel(_ host: HostEntry, target overrideTarget: TerminalTarget? = nil) {
        connect(host, target: overrideTarget, mode: .tunnelOnly)
    }

    func copyTunnelCommand(_ host: HostEntry) {
        do {
            let command = try SSHCommand.tunnelCommand(for: host.alias)
            copyToPasteboard(command, successMessage: "已复制隧道命令。", errorCopyAlias: host.alias)
        } catch {
            errorNotice = OperationNotice(message: error.localizedDescription)
        }
    }

    func openForwardedPort(_ rule: PortForwardRule) {
        guard let url = rule.localBrowserURL else { return }
        do {
            try externalLauncher.openWebURL(url)
            showTransientStatus("已在浏览器打开 \(url.absoluteString)。")
        } catch {
            errorNotice = OperationNotice(message: error.localizedDescription)
        }
    }

    func jumpAnalysis(for host: HostEntry) -> ProxyJumpAnalysis {
        SSHTopologyAnalyzer.analyzeJumps(for: host, allHosts: hostsByAlias)
    }

    func portForwards(for host: HostEntry) -> [PortForwardRule] {
        SSHTopologyAnalyzer.portForwards(for: host)
    }

    func copyHostName(_ host: HostEntry) {
        guard let address = ExternalActionBuilder.singleDeclaredAddress(for: host) else {
            errorNotice = OperationNotice(message: "此主机未声明唯一 HostName，请在详情中查看全部声明。")
            return
        }
        copyToPasteboard(address, successMessage: "已复制主机地址。")
    }

    func copyUserAtHost(_ host: HostEntry) {
        guard let target = ExternalActionBuilder.userAtHostAddress(for: host) else {
            errorNotice = OperationNotice(message: "需要同时声明唯一的 User 与 HostName 才能生成 User@HostName。")
            return
        }
        copyToPasteboard(target, successMessage: "已复制 User@HostName。")
    }

    func copySCPCommand(_ host: HostEntry) {
        do {
            let command = try ExternalActionBuilder.scpTemplateCommand(for: host.alias)
            copyToPasteboard(command, successMessage: "已复制 SCP 命令模板。")
        } catch {
            errorNotice = OperationNotice(message: error.localizedDescription)
        }
    }

    func openSourceInEditor(path: String, line: Int, editor: EditorTarget? = nil) {
        let target = editor ?? preferredEditor
        do {
            try externalLauncher.openFile(path: path, line: line, in: target)
            showTransientStatus("已在 \(target.displayName) 中打开。")
        } catch {
            errorNotice = OperationNotice(message: error.localizedDescription)
        }
    }

    func openHostConfigInEditor(_ host: HostEntry, editor: EditorTarget? = nil) {
        guard let location = host.locations.first else {
            errorNotice = OperationNotice(message: "未找到该主机的配置文件位置。")
            return
        }
        openSourceInEditor(path: location.filePath, line: location.line, editor: editor)
    }

    func openRemoteSSH(_ host: HostEntry, editor: EditorTarget) {
        guard hostsByAlias[host.alias] != nil else { return }
        do {
            try externalLauncher.openRemoteSSH(alias: host.alias, in: editor)
            showTransientStatus("已交给 \(editor.displayName) 打开 Remote-SSH。")
        } catch {
            errorNotice = OperationNotice(message: error.localizedDescription)
        }
    }

    func selectHost(alias: String) {
        guard hostsByAlias[alias] != nil else { return }
        if !visibleHosts.contains(where: { $0.alias == alias }) {
            searchText = ""
            sidebarSelection = .all
        }
        selectedHostAlias = alias
    }

    func copyToPasteboard(_ content: String, successMessage: String, errorCopyAlias: String? = nil) {
        NSPasteboard.general.clearContents()
        guard NSPasteboard.general.setString(content, forType: .string) else {
            errorNotice = OperationNotice(message: "无法访问剪贴板，请稍后重试。", copyAlias: errorCopyAlias)
            return
        }
        showTransientStatus(successMessage)
    }
}
