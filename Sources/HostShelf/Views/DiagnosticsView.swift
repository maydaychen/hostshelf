import HostShelfCore
import SwiftUI

struct DiagnosticsView: View {
    var store: AppStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: HostShelfSpacing.s4) {
                    Text("配置诊断与规则").font(.title2.weight(.semibold))
                    Text("配置只读；此处显示静态索引结果，不执行 Match 条件。")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button("完成") { dismiss() }.keyboardShortcut(.cancelAction)
            }.padding(HostShelfSpacing.s20)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: HostShelfSpacing.s24) {
                    diagnosticSection(.warning, title: "警告", systemImage: "exclamationmark.triangle")
                    if store.snapshot.diagnostics.contains(where: { $0.severity == .information }) {
                        diagnosticSection(.information, title: "提示", systemImage: "info.circle")
                    }
                    VStack(alignment: .leading, spacing: HostShelfSpacing.s10) {
                        Label("已扫描配置来源（\(store.snapshot.sources.count)）", systemImage: "doc.text").font(.headline)
                        if store.snapshot.sources.isEmpty {
                            Text("尚未扫描到配置文件。").font(.callout).foregroundStyle(.secondary)
                        }
                        ForEach(store.snapshot.sources, id: \.self) { path in
                            let hostCount = store.hostCount(forSource: path)
                            let status = hostCount > 0
                                ? "\(hostCount) 台主机"
                                : (store.snapshot.sourceIdentities[path] == nil ? "未能读取" : "未声明主机")
                            HStack(spacing: HostShelfSpacing.s8) {
                                Text(store.displayPath(path)).font(.system(.callout, design: .monospaced))
                                Text(status).font(.caption).foregroundStyle(.secondary).fixedSize()
                                Button { store.showInFinder(path) } label: { Image(systemName: "folder") }
                                    .buttonStyle(.borderless)
                                    .help("在 Finder 中显示")
                                    .accessibilityLabel("在 Finder 中显示 \(URL(fileURLWithPath: path).lastPathComponent)")
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: HostShelfSpacing.s10) {
                        Label("Include 关系（\(store.snapshot.includes.count)）", systemImage: "point.3.connected.trianglepath.dotted").font(.headline)
                        if store.snapshot.includes.isEmpty { Text("没有 Include 声明。 ").foregroundStyle(.secondary) }
                        ForEach(Array(store.snapshot.includes.enumerated()), id: \.offset) { _, include in
                            VStack(alignment: .leading, spacing: HostShelfSpacing.s4) {
                                Text("Include \(include.expression)").font(.system(.callout, design: .monospaced))
                                location(include.location.filePath, line: include.location.line)
                                if include.isConditional { Text("条件包含，实际适用范围由 SSH 判断。").font(.caption).foregroundStyle(.secondary) }
                                ForEach(Array(include.resolvedPaths.enumerated()), id: \.offset) { _, path in
                                    Text("↳ \(store.displayPath(path))").font(.caption.monospaced())
                                }
                                if include.resolvedPaths.isEmpty { Text("没有静态展开的文件。").font(.caption).foregroundStyle(.secondary) }
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: HostShelfSpacing.s10) {
                        Label("匹配规则（\(store.snapshot.rules.count)）", systemImage: "line.3.horizontal.decrease.circle").font(.headline)
                        if store.snapshot.rules.isEmpty { Text("没有额外匹配规则。 ").foregroundStyle(.secondary) }
                        ForEach(Array(store.snapshot.rules.enumerated()), id: \.offset) { _, rule in
                            VStack(alignment: .leading, spacing: HostShelfSpacing.s4) {
                                Text("\(rule.kind) \(rule.expression)").font(.system(.callout, design: .monospaced))
                                location(rule.location.filePath, line: rule.location.line)
                            }
                        }
                    }
                }.padding(HostShelfSpacing.s20).frame(maxWidth: .infinity, alignment: .leading)
            }.textSelection(.enabled)
        }.frame(minWidth: 660, idealWidth: 760, minHeight: 420, idealHeight: 560)
    }

    private func diagnosticSection(_ severity: IndexDiagnosticSeverity, title: String, systemImage: String) -> some View {
        let diagnostics = store.snapshot.diagnostics.filter { $0.severity == severity }
        return VStack(alignment: .leading, spacing: HostShelfSpacing.s10) {
            Label("\(title)（\(diagnostics.count)）", systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(severity == .warning && !diagnostics.isEmpty ? Color.orange : Color.secondary)
            if diagnostics.isEmpty {
                Text("本次静态索引没有发现读取或解析警告。")
                    .font(.callout).foregroundStyle(.secondary)
            }
            ForEach(Array(diagnostics.enumerated()), id: \.offset) { _, diagnostic in
                VStack(alignment: .leading, spacing: HostShelfSpacing.s4) {
                    Text(diagnostic.message).font(.callout)
                    location(diagnostic.location.filePath, line: diagnostic.location.line)
                }
            }
        }
    }

    private func location(_ path: String, line: Int) -> some View {
        HStack {
            Text("\(store.displayPath(path)):\(line)").font(.caption.monospaced()).foregroundStyle(.secondary)
            Button { store.showInFinder(path) } label: { Image(systemName: "folder") }
                .buttonStyle(.borderless).help("在 Finder 中显示")
        }
    }
}
