import HostShelfCore
import SwiftUI

struct HostTopologySection: View {
    var store: AppStore
    let host: HostEntry

    var body: some View {
        let jumps = store.jumpAnalysis(for: host)
        let forwards = store.portForwards(for: host)
        if !jumps.isEmpty || !forwards.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                if !jumps.isEmpty {
                    jumpSection(jumps)
                }
                if !forwards.isEmpty {
                    forwardsSection(forwards)
                }
            }
            Divider()
        }
    }

    private func jumpSection(_ analysis: ProxyJumpAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("跳板机链路", systemImage: "point.3.connected.trianglepath.dotted")
                .font(.headline)

            ForEach(Array(analysis.chains.enumerated()), id: \.offset) { _, chain in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        chainNode("本机", isEmphasized: false)
                        ForEach(Array(chain.enumerated()), id: \.offset) { _, hop in
                            Image(systemName: "arrow.right")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            if let alias = hop.indexedAlias {
                                Button(hop.target) {
                                    store.selectHost(alias: alias)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .font(.system(.caption, design: .monospaced))
                                .help("查看跳板机 \(alias) 的配置")
                            } else {
                                chainNode(hop.target, isEmphasized: false)
                            }
                        }
                        Image(systemName: "arrow.right")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        chainNode(host.alias, isEmphasized: true)
                    }
                }
            }

            if analysis.hasCycle {
                Label("检测到 ProxyJump 循环引用，已停止展开。", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            ForEach(Array(analysis.proxyCommands.enumerated()), id: \.offset) { _, declaration in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("ProxyCommand")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                        if declaration.isConditional {
                            Text("含条件声明")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(declaration.value)
                        .font(.system(.caption, design: .monospaced))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    private func forwardsSection(_ forwards: [PortForwardRule]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Label("端口转发", systemImage: "arrow.left.arrow.right.circle")
                    .font(.headline)
                Spacer(minLength: 8)
                Button("仅建立隧道 (ssh -N)") {
                    store.connectTunnel(host)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(store.isConnecting)
                Button("复制隧道命令") {
                    store.copyTunnelCommand(host)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            ForEach(forwards) { rule in
                HStack(alignment: .center, spacing: 10) {
                    Text(rule.kind.displayName)
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(rule.bindDisplay)
                                .font(.system(.callout, design: .monospaced))
                            if let destination = rule.destinationDisplay {
                                Image(systemName: "arrow.right")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text(destination)
                                    .font(.system(.callout, design: .monospaced))
                            }
                        }
                        if rule.isConditional {
                            Text("含条件声明 · \(store.displayPath(rule.location.filePath)):\(rule.location.line)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 8)
                    if rule.localBrowserURL != nil {
                        Button("打开本地端口") {
                            store.openForwardedPort(rule)
                        }
                        .buttonStyle(.link)
                        .controlSize(.small)
                    }
                }
                .padding(10)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    private func chainNode(_ title: String, isEmphasized: Bool) -> some View {
        Text(title)
            .font(.system(.caption, design: .monospaced))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                isEmphasized ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.12),
                in: RoundedRectangle(cornerRadius: 5)
            )
    }
}
