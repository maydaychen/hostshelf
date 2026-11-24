import AppKit
import HostShelfCore
import SwiftUI

struct HotKeyRecorderView: View {
    var hotKeyManager: GlobalHotKeyManager
    @State private var isRecording = false
    @State private var eventMonitor: Any?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button {
                    if isRecording {
                        stopRecording()
                    } else {
                        startRecording()
                    }
                } label: {
                    Text(buttonTitle)
                        .monospaced()
                        .frame(minWidth: 110)
                }
                .accessibilityIdentifier("hotKeyRecorderButton")

                Button("设为 ⌃⌥H") {
                    stopRecording()
                    hotKeyManager.applyRecommendedShortcut()
                }
                .buttonStyle(.bordered)
                .disabled(hotKeyManager.shortcut == .recommendedDefault)

                if hotKeyManager.shortcut != nil {
                    Button("清除") {
                        stopRecording()
                        hotKeyManager.clearShortcut()
                    }
                    .buttonStyle(.bordered)
                }
            }

            if let error = hotKeyManager.registrationError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .onDisappear { stopRecording() }
    }

    private var buttonTitle: String {
        if isRecording { return "按下组合键…" }
        return hotKeyManager.shortcut?.displayString ?? "点击录制"
    }

    private func startRecording() {
        stopRecording()
        isRecording = true
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handleKeyEvent(event)
        }
    }

    private func stopRecording() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
        isRecording = false
    }

    private func handleKeyEvent(_ event: NSEvent) -> NSEvent? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let carbonModifiers = HotKeyShortcut.carbonModifiers(
            control: flags.contains(.control),
            option: flags.contains(.option),
            shift: flags.contains(.shift),
            command: flags.contains(.command)
        )
        let keyCode = UInt32(event.keyCode)

        if keyCode == 53 && carbonModifiers == 0 {
            stopRecording()
            return nil
        }
        if keyCode == 51 && carbonModifiers == 0 {
            stopRecording()
            hotKeyManager.clearShortcut()
            return nil
        }

        let candidate = HotKeyShortcut(keyCode: keyCode, carbonModifiers: carbonModifiers)
        hotKeyManager.setShortcut(candidate)
        stopRecording()
        return nil
    }
}
