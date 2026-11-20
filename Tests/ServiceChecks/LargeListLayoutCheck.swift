import AppKit
import HostShelfCore
import SwiftUI

/// Full-window regression for large EC2-style lists, detail breakpoints, lazy excerpts, off-screen jumps, and draft flushes.
@main
struct LargeListLayoutCheck {
    static func main() {
        setbuf(stdout, nil)
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        Task { @MainActor in
            do {
                try await run()
                exit(0)
            } catch {
                fputs("FAIL: \(error)\n", stderr)
                exit(1)
            }
        }
        NSApp.run()
    }

    @MainActor
    private static func run() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("HostShelf-largelist-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let fixtures = try buildFixtures(in: root)
        setenv("HOSTSHELF_CONFIG_ROOTS", fixtures.rootConfig.path, 1)
        setenv("HOSTSHELF_METADATA_PATH", fixtures.metadataFile.path, 1)

        let suite = "HostShelf.LargeList.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }

        let calls = LaunchRecorder()
        let launcher = TerminalLauncher(execute: { alias, _ in calls.record(alias) }, availability: { _ in .available })
        let store = AppStore(preferences: preferences, launcher: launcher)
        store.refresh()
        try await wait { store.hasScanned && !store.isRefreshing }
        try require(store.sortedHosts.count == 1002, "expected 1002 indexed hosts, got \(store.sortedHosts.count)")

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1120, height: 720),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = NSHostingView(rootView: ContentView(store: store))
        window.orderBack(nil)
        defer { window.orderOut(nil); window.contentView = nil }
        try await pause(milliseconds: 300)

        try await verifyEC2ListClicks(window: window, store: store, fixtures: fixtures, calls: calls)
        try await verifyNarrowLayoutAndManyDeclarations(window: window, store: store, calls: calls)
        try await verifyDraftFlushOnFastSwitch(window: window, store: store, fixtures: fixtures, calls: calls)
        try await verifySixDigitLineAndOffscreenJump(window: window, store: store, fixtures: fixtures, calls: calls)
        try await verifyInFlightRefreshSupersedesStaleExcerptLoad(window: window, store: store, fixtures: fixtures, calls: calls)

        print("PASS: full-window large EC2 list, narrow detail breakpoints, lazy excerpt load, off-screen 6-digit line jump, in-flight refresh and fast draft flush completed cleanly")
    }

    private struct Fixtures {
        let rootConfig: URL
        let ec2Config: URL
        let longLinesConfig: URL
        let metadataFile: URL
        let longGroupName: String
        let targetLongLine: Int
    }

    private static func buildFixtures(in root: URL) throws -> Fixtures {
        let ec2Config = root.appendingPathComponent("ec2.conf")
        let longLinesConfig = root.appendingPathComponent("long-lines.conf")
        let rootConfig = root.appendingPathComponent("config")
        let metadataFile = root.appendingPathComponent("metadata.json")
        let longHostName = "ec2-203-0-113-42.ap-southeast-1.compute.amazonaws.internal.long-hostname.example.invalid"

        var ec2Lines: [String] = []
        ec2Lines.reserveCapacity(6100)
        for index in 1...1000 {
            let alias = String(format: "ec2-%04d", index)
            ec2Lines.append("Host \(alias)")
            if index == 1 {
                ec2Lines.append("  HostName \(longHostName)")
                ec2Lines.append("  User ec2-user")
                ec2Lines.append("  Port 22")
                ec2Lines.append("  ProxyCommand ssh -W %h:%p bastion-ap-southeast-1.example.invalid")
                for envIndex in 1...56 {
                    ec2Lines.append("  SetEnv HOSTSHELF_TEST_VAR_\(envIndex)=value_\(envIndex)")
                }
            } else {
                ec2Lines.append("  HostName ec2-198-51-100-\((index % 250) + 1).ap-southeast-1.compute.amazonaws.internal.example.invalid")
                ec2Lines.append("  User ec2-user")
                ec2Lines.append("  Port 22")
                ec2Lines.append("  ProxyCommand ssh -W %h:%p bastion.example.invalid")
            }
        }
        try ec2Lines.joined(separator: "\n").write(to: ec2Config, atomically: true, encoding: .utf8)

        var longLines = Array(repeating: "# filler line", count: 100_005)
        longLines[9] = "Host long-file-host"
        for offset in 0..<25 {
            longLines[10 + offset] = "  SetEnv EARLY_OPT_\(offset + 1)=val_\(offset + 1)"
        }
        let targetLine = 100_002
        longLines[targetLine - 2] = "  User ops"
        longLines[targetLine - 1] = "  Port 2222"
        longLines[targetLine] = "  HostName line100k.example.invalid"
        try longLines.joined(separator: "\n").write(to: longLinesConfig, atomically: true, encoding: .utf8)

        let rootText = """
        Host alpha-local
          HostName alpha.example.invalid
          User dev

        Include \(ec2Config.path)
        Include \(longLinesConfig.path)
        """
        try rootText.write(to: rootConfig, atomically: true, encoding: .utf8)

        let longGroupName = "Production-AP-Southeast-1-Very-Long-Group-Name-Breakpoint"
        var document = MetadataDocument(groups: [longGroupName])
        document.annotations["ec2-0001"] = HostAnnotation(group: longGroupName, note: "primary ec2 check", isFavorite: true)
        try HostMetadataStore(fileURL: metadataFile).save(document)

        return Fixtures(
            rootConfig: rootConfig,
            ec2Config: ec2Config,
            longLinesConfig: longLinesConfig,
            metadataFile: metadataFile,
            longGroupName: longGroupName,
            targetLongLine: targetLine
        )
    }

    @MainActor
    private static func verifyEC2ListClicks(
        window: NSWindow,
        store: AppStore,
        fixtures: Fixtures,
        calls: LaunchRecorder
    ) async throws {
        store.sidebarSelection = .source(fixtures.ec2Config.path)
        try await pause(milliseconds: 250)
        try require(store.visibleHosts.count == 1000, "ec2 filter must show 1000 hosts")
        try require(store.excerptReadCount == 0, "collapsed detail must trigger zero excerpt reads initially")

        let hostTable = try findHostListTable(in: window, expectedRows: 1000)
        let tableRightX = hostTable.convert(NSPoint(x: hostTable.bounds.maxX, y: 0), to: nil).x
        for row in [5, 10, 2, 1] {
            let expectedAlias = store.visibleHosts[row].alias
            try await click(window, table: hostTable, row: row)
            try await wait { store.selectedHostAlias == expectedAlias }
            try await wait { findDetailTextView(in: window, rightOf: tableRightX, value: expectedAlias) != nil }
        }
        try require(calls.aliases.isEmpty, "single clicks must never trigger terminal handoffs")
        try require(store.excerptReadCount == 0, "switching across hosts with collapsed excerpts must trigger zero file reads")
        print("PASS: 1000 EC2 hosts click selection updated details cleanly with zero excerpt reads and zero launches")
    }

    @MainActor
    private static func verifyNarrowLayoutAndManyDeclarations(
        window: NSWindow,
        store: AppStore,
        calls: LaunchRecorder
    ) async throws {
        try require(store.selectedHostAlias == "ec2-0002", "expected short host ec2-0002 before narrow resize")
        let hostTable = try findHostListTable(in: window, expectedRows: 1000)
        let wideTableRightX = hostTable.convert(NSPoint(x: hostTable.bounds.maxX, y: 0), to: nil).x
        let wideHostNameLabel = try requireValue(findDetailTextView(in: window, rightOf: wideTableRightX, value: "HostName"), "wide HostName label")
        let wideUserLabel = try requireValue(findDetailTextView(in: window, rightOf: wideTableRightX, value: "User"), "wide User label")
        try require(
            abs(wideHostNameLabel.convert(wideHostNameLabel.bounds, to: nil).midY - wideUserLabel.convert(wideUserLabel.bounds, to: nil).midY) < 16,
            "1120x720 wide overview should place HostName and User on the same row"
        )

        window.setContentSize(NSSize(width: 880, height: 560))
        try await pause(milliseconds: 200)
        try await click(window, table: hostTable, row: 0)
        try await wait { store.selectedHostAlias == "ec2-0001" }
        let narrowTableRightX = hostTable.convert(NSPoint(x: hostTable.bounds.maxX, y: 0), to: nil).x
        try await wait { findDetailTextView(in: window, rightOf: narrowTableRightX, value: "ec2-0001") != nil }

        let narrowHostNameLabel = try requireValue(findDetailTextView(in: window, rightOf: narrowTableRightX, value: "HostName"), "narrow HostName label")
        let narrowUserLabel = try requireValue(findDetailTextView(in: window, rightOf: narrowTableRightX, value: "User"), "narrow User label")
        let hostNameFrame = narrowHostNameLabel.convert(narrowHostNameLabel.bounds, to: nil)
        let userFrame = narrowUserLabel.convert(narrowUserLabel.bounds, to: nil)
        try require(hostNameFrame.minY > userFrame.maxY - 2, "880x560 narrow overview must stack HostName above User (hostName=\(hostNameFrame), user=\(userFrame))")

        try require(store.selectedHost?.declarations.count == 60, "ec2-0001 must have 60 declarations")
        try require(store.excerptReadCount == 0, "narrow layout switch with collapsed excerpts must not read files")
        try require(calls.aliases.isEmpty, "narrow layout check must not launch terminal")
        window.setContentSize(NSSize(width: 1120, height: 720))
        try await pause(milliseconds: 200)
        print("PASS: 880x560 narrow switch from short host to long host stacked overview cleanly with 60 declarations")
    }

    @MainActor
    private static func verifyDraftFlushOnFastSwitch(
        window: NSWindow,
        store: AppStore,
        fixtures: Fixtures,
        calls: LaunchRecorder
    ) async throws {
        let hostTable = try findHostListTable(in: window, expectedRows: 1000)
        try await click(window, table: hostTable, row: 1)
        try await wait { store.selectedHostAlias == "ec2-0002" }

        let draftText = "unsaved-before-400ms-\(UUID().uuidString)"
        let clock = ContinuousClock()
        let start = clock.now
        store.stageAnnotation(alias: "ec2-0002", group: fixtures.longGroupName, note: draftText)
        try require(store.pendingAnnotationAliases.contains("ec2-0002"), "draft should be pending before 400ms")

        try await click(window, table: hostTable, row: 2)
        try await wait { store.selectedHostAlias == "ec2-0003" && store.unsavedAnnotations["ec2-0002"] == nil }
        let elapsed = clock.now - start

        try require(elapsed < .milliseconds(350), "host switch flush took \(elapsed), must finish before 400ms debounce")
        try require(store.annotation(for: "ec2-0002").note == draftText, "flushed note must be visible in store")
        let persisted = try HostMetadataStore(fileURL: fixtures.metadataFile).load()
        try require(persisted.annotations["ec2-0002"]?.note == draftText, "flushed note must be persisted to disk on switch")
        try require(calls.aliases.isEmpty, "draft switch check must not launch terminal")
        print("PASS: switching hosts flushed and persisted draft in \(elapsed) (< 350ms before 400ms debounce)")
    }

    @MainActor
    private static func verifySixDigitLineAndOffscreenJump(
        window: NSWindow,
        store: AppStore,
        fixtures: Fixtures,
        calls: LaunchRecorder
    ) async throws {
        store.sidebarSelection = .source(fixtures.longLinesConfig.path)
        try await pause(milliseconds: 250)
        try require(store.visibleHosts.map(\.alias) == ["long-file-host"], "long-lines filter must show long-file-host")
        try require(store.excerptReadCount == 0, "long-file-host collapsed excerpt read count must start at 0")

        let hostTable = try findHostListTable(in: window, expectedRows: 1)
        let tableRightX = hostTable.convert(NSPoint(x: hostTable.bounds.maxX, y: 0), to: nil).x
        try await wait { findDetailTextView(in: window, rightOf: tableRightX, value: "long-file-host") != nil }

        let detailScrollView = try findDetailVerticalScrollView(in: window, rightOf: tableRightX)
        let targetLineString = String(fixtures.targetLongLine)
        try require(findCodeLineView(in: window, rightOf: tableRightX, lineNumber: targetLineString) == nil, "collapsed code excerpt must not be rendered initially")

        // First-click line button while collapsed: simultaneously loads excerpt once and jumps into viewport.
        let lineButton = try findDeclarationLineButton(in: window, rightOf: tableRightX, rowValue: "2222")
        lineButton.performClick(nil)
        try await wait {
            guard store.excerptReadCount == 1,
                  let lineView = findCodeLineView(in: window, rightOf: tableRightX, lineNumber: targetLineString) else {
                return false
            }
            let rect = lineRectInDocument(lineView: lineView, scrollView: detailScrollView)
            return detailScrollView.contentView.documentVisibleRect.intersects(rect)
        }

        // Scroll back to top and assert target line is genuinely off-screen, then re-jump without re-reading disk.
        detailScrollView.documentView?.scroll(NSPoint(x: 0, y: 0))
        try await pause(milliseconds: 150)
        let lineViewBeforeJump = try requireValue(
            findCodeLineView(in: window, rightOf: tableRightX, lineNumber: targetLineString),
            "target line view must exist inside expanded code excerpt"
        )
        let rectBefore = lineRectInDocument(lineView: lineViewBeforeJump, scrollView: detailScrollView)
        try require(
            !detailScrollView.contentView.documentVisibleRect.intersects(rectBefore),
            "target line \(fixtures.targetLongLine) must sit outside vertical viewport when scrolled to top"
        )

        lineButton.performClick(nil)
        try await wait {
            guard let lineView = findCodeLineView(in: window, rightOf: tableRightX, lineNumber: targetLineString) else {
                return false
            }
            let rect = lineRectInDocument(lineView: lineView, scrollView: detailScrollView)
            return detailScrollView.contentView.documentVisibleRect.intersects(rect)
        }
        try require(store.excerptReadCount == 1, "re-jumping within same snapshot must reuse loaded excerpts without re-reading disk")

        // Trigger refresh while expanded and ensure new snapshot reloads excerpts cleanly.
        store.refresh()
        try await wait { !store.isRefreshing && store.excerptReadCount == 2 }
        try await wait { findCodeLineView(in: window, rightOf: tableRightX, lineNumber: targetLineString) != nil }
        try require(calls.aliases.isEmpty, "line jump and refresh checks must not launch terminal")
        print("PASS: first-click collapsed jump (readCount=1), off-screen re-jump (readCount=1) and refresh reload (readCount=2) succeeded")
    }

    @MainActor
    private static func verifyInFlightRefreshSupersedesStaleExcerptLoad(
        window: NSWindow,
        store: AppStore,
        fixtures: Fixtures,
        calls: LaunchRecorder
    ) async throws {
        store.sidebarSelection = .source(fixtures.rootConfig.path)
        try await pause(milliseconds: 250)
        try require(store.visibleHosts.map(\.alias) == ["alpha-local"], "root config filter must show alpha-local")
        let hostTable = try findHostListTable(in: window, expectedRows: 1)
        let tableRightX = hostTable.convert(NSPoint(x: hostTable.bounds.maxX, y: 0), to: nil).x
        try await wait { findDetailTextView(in: window, rightOf: tableRightX, value: "alpha-local") != nil }

        let baselineReads = store.excerptReadCount
        let oldLine = "  User dev"
        let gate = InFlightExcerptGate(expectedOldLine: oldLine)
        var finishedStaleLoad = false
        store.excerptReaderOverride = { host, sourceIdentities, shouldCancel in
            gate.read(host: host, sourceIdentities: sourceIdentities, shouldCancel: shouldCancel)
        }
        store.excerptLoadDidFinish = { result in
            if result.contains(where: { $0.lines.contains(where: { $0.text == oldLine }) }) { finishedStaleLoad = true }
        }
        defer {
            gate.releaseFirstCall()
            store.excerptReaderOverride = nil
            store.excerptLoadDidFinish = nil
        }

        let lineButton = try findDeclarationLineButton(in: window, rightOf: tableRightX, rowValue: "dev")
        lineButton.performClick(nil)
        try await wait { gate.hasCapturedOldResult && store.excerptReadCount == baselineReads + 1 }

        let updatedRoot = try String(contentsOf: fixtures.rootConfig, encoding: .utf8)
            .replacingOccurrences(of: oldLine, with: "  User dev-refreshed")
        try updatedRoot.write(to: fixtures.rootConfig, atomically: true, encoding: .utf8)
        store.refresh()
        try await wait { !store.isRefreshing && store.excerptReadCount == baselineReads + 2 }
        try await wait { findCodeLineView(in: window, rightOf: tableRightX, lineNumber: "  User dev-refreshed") != nil }

        gate.releaseFirstCall()
        try await wait { finishedStaleLoad }
        try require(gate.firstCallWasReleased, "the old read must have waited for explicit release")

        try require(findCodeLineView(in: window, rightOf: tableRightX, lineNumber: "  User dev-refreshed") != nil, "newer snapshot excerpt must stay visible")
        try require(findCodeLineView(in: window, rightOf: tableRightX, lineNumber: oldLine) == nil, "stale cancelled excerpt must not overwrite newer snapshot")
        try require(findDetailTextView(in: window, rightOf: tableRightX, value: "正在读取来源片段…") == nil, "loading indicator must not remain stuck")
        try require(findDetailTextView(in: window, rightOf: tableRightX, value: "展开以读取来源片段。") == nil, "collapsed placeholder must not replace loaded excerpt")
        try require(calls.aliases.isEmpty, "in-flight refresh check must not launch terminal")
        print("PASS: refresh while excerpt load was in flight kept newer excerpt without clobbering loading state")
    }

    @MainActor
    private static func findHostListTable(in window: NSWindow, expectedRows: Int) throws -> NSTableView {
        let tables = allViews(ofType: NSTableView.self, in: window.contentView!)
            .sorted { $0.convert($0.bounds.origin, to: nil).x < $1.convert($1.bounds.origin, to: nil).x }
        if let match = tables.dropFirst().first(where: { $0.numberOfRows == expectedRows }) { return match }
        if let fallback = tables.first(where: { $0.numberOfRows == expectedRows }) { return fallback }
        throw Failure.check("could not locate host list NSTableView with \(expectedRows) rows; found \(tables.map(\.numberOfRows))")
    }

    @MainActor
    private static func findDetailTextView(in window: NSWindow, rightOf minX: CGFloat, value: String) -> NSView? {
        allViews(ofType: NSView.self, in: window.contentView!).first { view in
            guard let text = (view as NSAccessibilityProtocol).accessibilityValue() as? String,
                  text == value else { return false }
            return view.convert(view.bounds.origin, to: nil).x >= minX
        }
    }

    @MainActor
    private static func findDetailVerticalScrollView(in window: NSWindow, rightOf minX: CGFloat) throws -> NSScrollView {
        if let match = allViews(ofType: NSScrollView.self, in: window.contentView!).first(where: {
            $0.hasVerticalScroller && $0.convert($0.bounds.origin, to: nil).x >= minX
        }) {
            return match
        }
        throw Failure.check("missing detail vertical NSScrollView")
    }

    @MainActor
    private static func findCodeLineView(in window: NSWindow, rightOf minX: CGFloat, lineNumber: String) -> NSView? {
        allViews(ofType: NSView.self, in: window.contentView!).first { view in
            guard let text = (view as NSAccessibilityProtocol).accessibilityValue() as? String,
                  text == lineNumber,
                  view.convert(view.bounds.origin, to: nil).x >= minX else { return false }
            return enclosingScrollViews(of: view).count >= 2
        }
    }

    @MainActor
    private static func findDeclarationLineButton(in window: NSWindow, rightOf minX: CGFloat, rowValue: String) throws -> NSButton {
        let valueViews = allViews(ofType: NSView.self, in: window.contentView!).filter { view in
            guard let text = (view as NSAccessibilityProtocol).accessibilityValue() as? String,
                  text == rowValue,
                  view.convert(view.bounds.origin, to: nil).x >= minX else { return false }
            return enclosingScrollViews(of: view).count == 1
        }
        let buttons = allViews(ofType: NSButton.self, in: window.contentView!)
        for valueView in valueViews {
            let valueFrame = valueView.convert(valueView.bounds, to: nil)
            if let button = buttons.first(where: { button in
                let frame = button.convert(button.bounds, to: nil)
                return frame.minX >= valueFrame.maxX - 4 && abs(frame.midY - valueFrame.midY) < 16
            }) {
                return button
            }
        }
        throw Failure.check("could not find declaration line button aligned with '\(rowValue)'")
    }

    @MainActor
    private static func enclosingScrollViews(of view: NSView) -> [NSScrollView] {
        var result: [NSScrollView] = []
        var ancestor = view.superview
        while let current = ancestor {
            if let scrollView = current as? NSScrollView { result.append(scrollView) }
            ancestor = current.superview
        }
        return result
    }

    @MainActor
    private static func lineRectInDocument(lineView: NSView, scrollView: NSScrollView) -> NSRect {
        let document = scrollView.documentView!
        let rect = document.convert(lineView.bounds, from: lineView)
        return NSRect(x: scrollView.contentView.documentVisibleRect.minX, y: rect.minY, width: 1, height: max(1, rect.height))
    }

    @MainActor
    private static func allViews<T: NSView>(ofType _: T.Type, in root: NSView) -> [T] {
        var result: [T] = []
        if let match = root as? T { result.append(match) }
        for child in root.subviews { result.append(contentsOf: allViews(ofType: T.self, in: child)) }
        return result
    }

    @MainActor
    private static func click(_ window: NSWindow, table: NSTableView, row: Int) async throws {
        table.scrollRowToVisible(row)
        let rect = table.rect(ofRow: row)
        let point = table.convert(NSPoint(x: min(40, rect.midX), y: rect.midY), to: nil)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = NSEvent.mouseEvent(
                with: type, location: point, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, eventNumber: 1, clickCount: 1, pressure: 1
            )!
            NSApp.postEvent(event, atStart: false)
        }
        try await pause(milliseconds: 60)
    }

    @MainActor
    private static func wait(_ predicate: () -> Bool) async throws {
        let end = Date(timeIntervalSinceNow: 6)
        while !predicate() {
            guard Date() < end else { throw Failure.check("timed out waiting for UI/store state") }
            try await pause(milliseconds: 20)
        }
    }

    @MainActor
    private static func pause(milliseconds: Int) async throws {
        try await Task.sleep(for: .milliseconds(milliseconds))
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw Failure.check(message) }
    }

    private static func requireValue<T>(_ value: T?, _ message: String) throws -> T {
        guard let value else { throw Failure.check(message) }
        return value
    }

    enum Failure: Error { case check(String) }
}

private final class LaunchRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String] = []
    var aliases: [String] { lock.lock(); defer { lock.unlock() }; return values }
    func record(_ alias: String) { lock.lock(); defer { lock.unlock() }; values.append(alias) }
}
