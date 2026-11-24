import AppKit
import Foundation
import HostShelfCore

@MainActor
extension AppStore {
    func quickLauncherHosts(for query: String) -> [HostEntry] {
        FuzzyMatcher.rankForQuickLauncher(
            hosts: sortedHosts,
            annotation: { annotation(for: $0) },
            query: query
        )
    }

    func availableTerminals() -> [(target: TerminalTarget, availability: TerminalAvailability)] {
        TerminalTarget.allCases.map { ($0, TerminalLauncher.availability(for: $0)) }
    }

    func isEditorAvailable(_ editor: EditorTarget) -> Bool {
        externalLauncher.isAvailable(editor)
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
