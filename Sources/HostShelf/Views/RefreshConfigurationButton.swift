import SwiftUI

struct RefreshConfigurationButton: View {
    let isRefreshing: Bool
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsProgress = false

    var body: some View {
        Button(action: action) {
            Label("刷新配置", systemImage: "arrow.clockwise")
                .labelStyle(.iconOnly)
                .opacity(showsProgress && !reduceMotion ? 0 : 1)
                .frame(width: 16, height: 16)
                .overlay {
                    if showsProgress && !reduceMotion {
                        ProgressView().controlSize(.small)
                            .frame(width: 16, height: 16)
                            .accessibilityHidden(true)
                    }
                }
        }
        .disabled(isRefreshing)
        .accessibilityLabel(isRefreshing ? "正在读取配置" : "刷新配置")
        .accessibilityIdentifier("refreshConfiguration")
        .help(isRefreshing ? "正在读取配置" : "刷新配置（⌘R）")
        .task(id: isRefreshing) {
            showsProgress = false
            guard isRefreshing else { return }
            do { try await Task.sleep(for: .milliseconds(250)) }
            catch { return }
            showsProgress = true
        }
    }
}
