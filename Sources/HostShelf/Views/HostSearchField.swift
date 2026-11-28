import AppKit
import SwiftUI

struct HostSearchField: NSViewRepresentable {
    @Binding var text: String
    let focusRequest: Int
    /// Reports whether the field editor owns focus, so the surrounding container can draw an aligned focus ring.
    var onFocusChange: ((Bool) -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> SearchTextField {
        let field = SearchTextField()
        field.placeholderString = "搜索主机、备注或来源"
        field.stringValue = text
        field.font = .systemFont(ofSize: NSFont.systemFontSize)
        field.textColor = .labelColor
        field.isBezeled = false
        field.isBordered = false
        field.drawsBackground = false
        // The SwiftUI container draws the focus ring around its full rounded chrome.
        field.focusRingType = .none
        field.usesSingleLineMode = true
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.setAccessibilityLabel("搜索主机、备注或来源")
        field.setAccessibilityIdentifier("hostSearch")
        field.delegate = context.coordinator
        field.focusChanged = { [weak coordinator = context.coordinator] focused in
            coordinator?.representable.onFocusChange?(focused)
        }
        context.coordinator.attach(field)
        return field
    }

    func updateNSView(_ field: SearchTextField, context: Context) {
        context.coordinator.representable = self
        if field.stringValue != text { field.stringValue = text }
        context.coordinator.focusIfRequested()
    }

    static func dismantleNSView(_ field: SearchTextField, coordinator: Coordinator) {
        field.delegate = nil
        field.windowChanged = nil
        field.focusChanged = nil
        let reportFocus = coordinator.representable.onFocusChange
        DispatchQueue.main.async { reportFocus?(false) }
        coordinator.detach()
    }

    final class SearchTextField: NSTextField {
        var windowChanged: (() -> Void)?
        var focusChanged: ((Bool) -> Void)?
        private var reportedFocus = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            windowChanged?()
            scheduleFocusReport()
        }

        override func becomeFirstResponder() -> Bool {
            let accepted = super.becomeFirstResponder()
            scheduleFocusReport()
            return accepted
        }

        override func textDidEndEditing(_ notification: Notification) {
            super.textDidEndEditing(notification)
            scheduleFocusReport()
        }

        /// Re-evaluates after the responder chain settles (e.g. Return re-selects the field).
        private func scheduleFocusReport() {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let focused = self.currentEditor().map { self.window?.firstResponder === $0 } ?? false
                guard focused != self.reportedFocus else { return }
                self.reportedFocus = focused
                self.focusChanged?(focused)
            }
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var representable: HostSearchField
        private weak var field: SearchTextField?
        private var consumedRequest = 0
        private var windowObserver: NSObjectProtocol?

        init(_ representable: HostSearchField) { self.representable = representable }

        deinit {
            if let windowObserver { NotificationCenter.default.removeObserver(windowObserver) }
        }

        func attach(_ field: SearchTextField) {
            self.field = field
            field.windowChanged = { [weak self] in self?.observeWindow() }
            observeWindow()
        }

        func detach() {
            if let windowObserver { NotificationCenter.default.removeObserver(windowObserver) }
            windowObserver = nil
            field = nil
        }

        private func observeWindow() {
            if let windowObserver { NotificationCenter.default.removeObserver(windowObserver) }
            windowObserver = nil
            if let window = field?.window {
                windowObserver = NotificationCenter.default.addObserver(
                    forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main
                ) { [weak self] _ in self?.focusIfRequested() }
            }
            focusIfRequested()
        }

        func focusIfRequested() {
            let request = representable.focusRequest
            guard request > consumedRequest,
                  let field, let window = field.window,
                  window.isKeyWindow, window.attachedSheet == nil else { return }
            let alreadyFocused = field.currentEditor().map { window.firstResponder === $0 } ?? false
            let accepted = alreadyFocused || window.makeFirstResponder(field)
            let editor = field.currentEditor()
            let isFocused = editor.map { window.firstResponder === $0 } ?? false
            // Consume the request only after the actual field editor owns focus.
            if accepted && isFocused {
                consumedRequest = request
                editor?.selectAll(nil)
            }
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField,
                  representable.text != field.stringValue else { return }
            representable.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard commandSelector == #selector(NSResponder.cancelOperation(_:)),
                  let field, control === field,
                  let window = field.window, window.attachedSheet == nil,
                  window.firstResponder === textView else { return false }
            field.stringValue = ""
            representable.text = ""
            window.makeFirstResponder(nil)
            return true
        }
    }
}
