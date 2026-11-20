import AppKit
import HostShelfCore
import SwiftUI

/// Isolated presentation and responder checks. Does not access SSH configuration or terminals.
@main
struct InteractionUICheck {
    @MainActor
    static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        try checkHighlight()
        try checkAddressSummary()
        try checkKeywordWidth()
        try checkSearchEscape()
    }

    private static func checkHighlight() throws {
        let highlighted = SearchHighlight.text("CAFÉ café 主机 🖥️", query: " cafe ")
        guard String(highlighted.characters) == "CAFÉ café 主机 🖥️",
              highlighted.runs.filter({ $0.inlinePresentationIntent == .stronglyEmphasized }).count == 2 else {
            throw Failure.check("case/diacritic matching or original text preservation")
        }
        for query in ["", "   ", "absent", "\u{0301}"] {
            let text = SearchHighlight.text("主机 🖥️", query: query)
            guard String(text.characters) == "主机 🖥️" else { throw Failure.check("unmatched Unicode text changed") }
        }
        let chinese = SearchHighlight.text("主机甲与主机乙", query: "主机")
        guard chinese.runs.filter({ $0.inlinePresentationIntent == .stronglyEmphasized }).count == 2 else {
            throw Failure.check("repeated Chinese matches")
        }
        print("PASS: search highlighting preserves Unicode text and handles repeated, folded, empty and absent matches")
    }

    private static func checkAddressSummary() throws {
        let location = SourceLocation(filePath: "/fixture/config", line: 1)
        var host = HostEntry(alias: "fixture")
        guard HostListPresentation.subtitle(for: host, annotation: HostAnnotation()) == "查看配置声明" else {
            throw Failure.check("no address")
        }
        host.declarations = [SSHDeclaration(keyword: "hostname", value: "one.example.invalid", location: location)]
        host.declarations.append(host.declarations[0])
        guard HostListPresentation.subtitle(for: host, annotation: HostAnnotation()) == "one.example.invalid" else {
            throw Failure.check("one distinct address")
        }
        host.declarations.append(SSHDeclaration(keyword: "hostname", value: "two.example.invalid", location: location))
        guard HostListPresentation.subtitle(for: host, annotation: HostAnnotation()) == "多处地址声明",
              HostListPresentation.subtitle(for: host, annotation: HostAnnotation(note: "说明")) == "说明" else {
            throw Failure.check("multiple address ambiguity or note priority")
        }
        print("PASS: row summary distinguishes zero, one and multiple distinct addresses and preserves note priority")
    }

    private static func checkKeywordWidth() throws {
        guard HostListPresentation.keywordColumnWidth([]) == 96,
              HostListPresentation.keywordColumnWidth(["port"]) == 96,
              HostListPresentation.keywordColumnWidth(["serveraliveinterval"]) > 96,
              HostListPresentation.keywordColumnWidth([String(repeating: "x", count: 300)]) == 160 else {
            throw Failure.check("keyword width bounds")
        }
        print("PASS: declaration keyword width grows for long directives and stays within 96–160 points")
    }

    @MainActor
    private static func checkSearchEscape() throws {
        var query = "fixture"
        let representable = HostSearchField(text: Binding(get: { query }, set: { query = $0 }), focusRequest: 0)
        let coordinator = representable.makeCoordinator()
        let field = HostSearchField.SearchTextField(frame: NSRect(x: 20, y: 20, width: 200, height: 24))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 100),
                              styleMask: [.titled], backing: .buffered, defer: false)
        defer { window.contentView = nil; coordinator.detach() }
        window.contentView?.addSubview(field)
        field.delegate = coordinator
        field.stringValue = query
        coordinator.attach(field)
        guard window.makeFirstResponder(field), let editor = field.currentEditor() as? NSTextView else {
            throw Failure.check("search field editor setup")
        }
        let cancel = #selector(NSResponder.cancelOperation(_:))
        guard !coordinator.control(NSTextField(), textView: editor, doCommandBy: cancel),
              !coordinator.control(field, textView: editor, doCommandBy: #selector(NSResponder.insertNewline(_:))),
              query == "fixture" else { throw Failure.check("unrelated editor or command intercepted") }
        guard coordinator.control(field, textView: editor, doCommandBy: cancel),
              query.isEmpty, field.stringValue.isEmpty, window.firstResponder !== editor else {
            throw Failure.check("Escape must clear search and release its editor")
        }
        guard !coordinator.control(field, textView: editor, doCommandBy: cancel) else {
            throw Failure.check("inactive search editor intercepted cancellation")
        }
        print("PASS: Escape clears and leaves only the active search field; unrelated editors and commands remain untouched")
    }

    enum Failure: Error { case check(String) }
}
