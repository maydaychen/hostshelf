import Foundation
import Observation
import ServiceManagement

@MainActor
@Observable
final class LaunchAtLoginService {
    private(set) var status: SMAppService.Status
    private(set) var errorMessage: String?

    @ObservationIgnored private let statusProvider: @MainActor () -> SMAppService.Status
    @ObservationIgnored private let registerAction: @MainActor () throws -> Void
    @ObservationIgnored private let unregisterAction: @MainActor () throws -> Void

    init(
        statusProvider: @escaping @MainActor () -> SMAppService.Status = { SMAppService.mainApp.status },
        registerAction: @escaping @MainActor () throws -> Void = { try SMAppService.mainApp.register() },
        unregisterAction: @escaping @MainActor () throws -> Void = { try SMAppService.mainApp.unregister() }
    ) {
        self.statusProvider = statusProvider
        self.registerAction = registerAction
        self.unregisterAction = unregisterAction
        self.status = statusProvider()
    }

    var isEnabled: Bool {
        status == .enabled || status == .requiresApproval
    }

    var statusMessage: String? {
        switch status {
        case .requiresApproval:
            return "请在“系统设置 → 通用 → 登录项”中允许 HostShelf 开机启动。"
        case .notFound:
            return "当前构建状态无法注册登录项；请在正式安装包中启用。"
        case .enabled, .notRegistered:
            return nil
        @unknown default:
            return nil
        }
    }

    func refresh() {
        status = statusProvider()
    }

    func setEnabled(_ enabled: Bool) {
        errorMessage = nil
        do {
            if enabled {
                try registerAction()
            } else {
                try unregisterAction()
            }
        } catch {
            errorMessage = enabled
                ? "无法开启登录时自动启动：\(error.localizedDescription)"
                : "无法关闭登录时自动启动：\(error.localizedDescription)"
        }
        refresh()
    }
}
