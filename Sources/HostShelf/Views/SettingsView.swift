import HostShelfCore
import SwiftUI

struct SettingsView: View {
    @Bindable var store: AppStore

    var body: some View {
        Form {
            Section {
                LabeledContent("应用", value: "HostShelf")
                LabeledContent("版本", value: AppIdentity.version)
                LabeledContent("应用架构", value: AppIdentity.architecture)
            }
            Section("连接") {
                Picker("默认终端", selection: $store.preferredTerminal) {
                    ForEach(TerminalTarget.allCases) { target in
                        let availability = TerminalLauncher.availability(for: target)
                        Text(availability.unavailableReason.map { "\(target.displayName)（\($0)）" } ?? target.displayName)
                            .tag(target)
                            .selectionDisabled(!availability.isAvailable)
                    }
                }
                .accessibilityIdentifier("preferredTerminalPicker")
                Text("所有连接入口使用此终端，修改后立即保存到本机。")
                    .font(.caption).foregroundStyle(.secondary)
                if let reason = TerminalLauncher.availability(for: store.preferredTerminal).unavailableReason {
                    Label("\(store.preferredTerminal.displayName)：\(reason)。请安装应用或选择其他终端。", systemImage: "exclamationmark.triangle")
                        .font(.callout).foregroundStyle(.orange)
                }
                if store.preferredTerminal == .ghostty {
                    Text("需要 Ghostty 1.3.0 或更新版本，并启用 AppleScript 支持。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("配置与数据") {
                Text("默认读取 ~/.ssh/config、/etc/ssh/ssh_config 及其 Include 文件。")
                Text("收藏、分组、备注和最近发起时间只保存在本机 Application Support 目录。SSH 配置和私钥不会被修改。")
            }
            Section("连接权限") {
                Text("首次连接时允许 HostShelf 控制所选终端。若此前拒绝，可在“系统设置 → 隐私与安全性 → 自动化”中恢复。")
                Text("关闭主窗口后，仍可通过菜单栏打开。完全退出请使用“退出 HostShelf”。")
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 520, idealWidth: 520, maxWidth: 640, minHeight: 420, idealHeight: 520)
        .textSelection(.enabled)
    }
}

struct AboutView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "terminal.fill").font(.system(size: 56)).foregroundStyle(.tint)
            Text("HostShelf").font(.largeTitle.weight(.semibold))
            Text("SSH 主机目录与终端启动器").foregroundStyle(.secondary)
            Text("版本 \(AppIdentity.version)")
            Text(AppIdentity.architecture).font(.callout.monospaced())
            Text("配置只读，连接由系统 SSH 完成。")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(32).frame(width: 380).textSelection(.enabled)
    }
}

private enum AppIdentity {
    static var version: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version)（\(build)）"
    }
    static var architecture: String {
        #if arch(arm64)
        "Apple Silicon（arm64）"
        #elseif arch(x86_64)
        "Intel（x86_64）"
        #else
        "未知架构"
        #endif
    }
}
