import AppKit
import Foundation
import HostShelfCore
import Observation

enum SidebarFilter: Hashable {
    case all, favorites, recent, group(String), source(String)
}

struct OperationNotice {
    let message: String
    var copyAlias: String? = nil
    var offersAutomationSettings = false
}

@MainActor
@Observable
final class AppStore {
    static let terminalPreferenceKey = "preferredTerminal"
    var preferredTerminal: TerminalTarget {
        didSet { preferences.set(preferredTerminal.rawValue, forKey: Self.terminalPreferenceKey) }
    }
    private(set) var snapshot = SSHIndexSnapshot()
    private(set) var sortedHosts: [HostEntry] = []
    private(set) var hostSources: [String] = []
    private var hostCountsBySource: [String: Int] = [:]
    private(set) var metadata = MetadataDocument()
    private(set) var isRefreshing = false
    private(set) var hasScanned = false
    private(set) var metadataError: String?
    private(set) var metadataWritable = true
    var sidebarSelection: SidebarFilter? = .all
    var selectedHostAlias: String?
    var searchText = ""
    var errorNotice: OperationNotice?
    private(set) var statusMessage: String?
    private(set) var connectingAlias: String?
    var isConnecting: Bool { connectingAlias != nil }
    var showDiagnostics = false
    var searchFocusRequest = 0
    var unsavedAnnotations: [String: HostAnnotation] = [:]
    private(set) var pendingAnnotationAliases: Set<String> = []
    #if DEBUG
    typealias ExcerptReader = @Sendable (HostEntry, [String: SourceIdentity], () -> Bool) -> [SourceExcerpt]
    @ObservationIgnored private(set) var excerptReadCount = 0
    @ObservationIgnored var excerptReaderOverride: ExcerptReader?
    @ObservationIgnored var excerptLoadDidFinish: (([SourceExcerpt]) -> Void)?
    #endif

    private var hostsByAlias: [String: HostEntry] = [:]
    @ObservationIgnored private let metadataStore: HostMetadataStore
    @ObservationIgnored private let metadataURL: URL
    @ObservationIgnored private let preferences: UserDefaults
    @ObservationIgnored private let launcher: TerminalLauncher
    @ObservationIgnored private let roots: [URL]?
    @ObservationIgnored private var annotationSaveTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var statusTask: Task<Void, Never>?
    @ObservationIgnored private var visibleWindowCount = 0

    init(preferences: UserDefaults = .standard, launcher: TerminalLauncher? = nil) {
        self.preferences = preferences
        self.launcher = launcher ?? TerminalLauncher()
        preferredTerminal = TerminalTarget(rawValue: preferences.string(forKey: Self.terminalPreferenceKey) ?? "") ?? .terminal
        let environment = ProcessInfo.processInfo.environment
        var metadataURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HostShelf", isDirectory: true)
            .appendingPathComponent("metadata.json")
        var configurationRoots: [URL]?
        #if DEBUG
        if let path = environment["HOSTSHELF_METADATA_PATH"], !path.isEmpty {
            metadataURL = URL(fileURLWithPath: path)
        }
        if let paths = environment["HOSTSHELF_CONFIG_ROOTS"] {
            configurationRoots = paths.split(separator: ":").map { URL(fileURLWithPath: String($0)) }
        }
        #endif
        self.metadataURL = metadataURL
        metadataStore = HostMetadataStore(fileURL: metadataURL)
        roots = configurationRoots
        do {
            metadata = try metadataStore.load()
        } catch {
            metadataWritable = false
            metadataError = "附加信息读取失败。原文件已保留，本次运行暂停写入：\(error.localizedDescription)"
        }
    }

    var visibleHosts: [HostEntry] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filter = sidebarSelection ?? .all
        if filter == .all && query.isEmpty { return sortedHosts }
        let hosts = sortedHosts.filter { host in
            let annotation = annotation(for: host.alias)
            let matchesFilter: Bool
            switch filter {
            case .all: matchesFilter = true
            case .favorites: matchesFilter = annotation.isFavorite
            case .recent: matchesFilter = annotation.lastLaunchedAt != nil
            case .group(let group): matchesFilter = annotation.group == group
            case .source(let path): matchesFilter = host.locations.contains { $0.filePath == path }
                || host.declarations.contains { $0.location.filePath == path }
            }
            guard matchesFilter else { return false }
            guard !query.isEmpty else { return true }
            let values = [host.alias, annotation.note, annotation.group]
                + host.declaredValues(for: "hostname") + host.locations.map(\.filePath)
                + host.declarations.map { $0.location.filePath }
            return values.contains { $0.localizedStandardContains(query) }
        }
        return filter == .recent ? sortedRecentHosts(hosts) : hosts
    }

    var selectedHost: HostEntry? { selectedHostAlias.flatMap { hostsByAlias[$0] } }
    func host(for alias: String) -> HostEntry? { hostsByAlias[alias] }
    func hostCount(forSource path: String) -> Int { hostCountsBySource[path] ?? 0 }
    var groups: [String] {
        Array(Set(metadata.groups + metadata.annotations.values.map(\.group)
            + unsavedAnnotations.values.map(\.group)).subtracting([""]))
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
    var favorites: [HostEntry] {
        sortedHosts.filter { annotation(for: $0.alias).isFavorite }
    }
    var recentHosts: [HostEntry] {
        sortedRecentHosts(sortedHosts)
    }

    private func sortedRecentHosts(_ hosts: [HostEntry]) -> [HostEntry] {
        hosts.compactMap { host -> (host: HostEntry, date: Date)? in
            guard let date = annotation(for: host.alias).lastLaunchedAt else { return nil }
            return (host, date)
        }.sorted {
            if $0.date != $1.date { return $0.date > $1.date }
            return $0.host.alias.localizedStandardCompare($1.host.alias) == .orderedAscending
        }.map(\.host)
    }

    func annotation(for alias: String) -> HostAnnotation { metadata.annotations[alias] ?? HostAnnotation() }

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        let configurationRoots = roots
        Task { [weak self] in
            let (result, sorted, countsBySource, hostSources) = await Task.detached(priority: .userInitiated) {
                let snapshot = SSHConfigIndexer().scan(roots: configurationRoots)
                let sorted = snapshot.hosts.sorted {
                    $0.alias.localizedStandardCompare($1.alias) == .orderedAscending
                }
                var countsBySource: [String: Int] = [:]
                for host in sorted {
                    var hostPaths = Set<String>()
                    for location in host.locations { hostPaths.insert(location.filePath) }
                    for declaration in host.declarations { hostPaths.insert(declaration.location.filePath) }
                    for path in hostPaths { countsBySource[path, default: 0] += 1 }
                }
                let hostSources = snapshot.sources.filter { (countsBySource[$0] ?? 0) > 0 }
                return (snapshot, sorted, countsBySource, hostSources)
            }.value
            guard let self else { return }
            snapshot = result
            sortedHosts = sorted
            hostsByAlias = Dictionary(uniqueKeysWithValues: sorted.map { ($0.alias, $0) })
            hostCountsBySource = countsBySource
            self.hostSources = hostSources
            hasScanned = true
            isRefreshing = false
            reconcileSelection()
        }
    }

    func reconcileSelection() {
        if case .source(let path) = sidebarSelection, !hostSources.contains(path) {
            sidebarSelection = .all
        }
        let hosts = visibleHosts
        if !hosts.contains(where: { $0.alias == selectedHostAlias }) {
            selectedHostAlias = hosts.first?.alias
        }
    }

    func canDeleteGroup(_ name: String) -> Bool {
        metadataWritable && groups.contains(name)
            && !metadata.annotations.values.contains { $0.group == name }
            && !unsavedAnnotations.values.contains { $0.group == name }
    }

    @discardableResult
    func deleteEmptyGroup(_ name: String) -> Bool {
        guard canDeleteGroup(name) else { return false }
        var candidate = metadata
        candidate.groups.removeAll { $0 == name }
        guard persist(candidate) else { return false }
        if sidebarSelection == .group(name) { sidebarSelection = .all }
        reconcileSelection()
        return true
    }

    func stageAnnotation(alias: String, group: String, note: String) {
        annotationSaveTasks.removeValue(forKey: alias)?.cancel()
        pendingAnnotationAliases.remove(alias)
        var draft = annotation(for: alias)
        guard draft.group != group || draft.note != note else {
            unsavedAnnotations.removeValue(forKey: alias)
            return
        }
        draft.group = group
        draft.note = note
        unsavedAnnotations[alias] = draft
        pendingAnnotationAliases.insert(alias)
        annotationSaveTasks[alias] = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(400)) } catch { return }
            guard !Task.isCancelled else { return }
            self?.flushAnnotation(alias: alias)
        }
    }

    @discardableResult
    func flushAnnotation(alias: String) -> Bool {
        annotationSaveTasks.removeValue(forKey: alias)?.cancel()
        pendingAnnotationAliases.remove(alias)
        guard let draft = unsavedAnnotations[alias] else { return true }
        let saved = annotation(for: alias)
        guard (draft.group == saved.group && draft.note == saved.note)
                || saveAnnotation(alias: alias, group: draft.group, note: draft.note) else { return false }
        unsavedAnnotations.removeValue(forKey: alias)
        return true
    }

    @discardableResult
    func flushAllAnnotations() -> Bool {
        var saved = true
        for alias in Array(unsavedAnnotations.keys) {
            if !flushAnnotation(alias: alias) { saved = false }
        }
        return saved
    }

    @discardableResult
    func addGroup(_ proposedName: String) -> Bool {
        let name = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return false }
        guard !groups.contains(name) else { sidebarSelection = .group(name); return true }
        var candidate = metadata
        candidate.groups.append(name)
        guard persist(candidate) else { return false }
        sidebarSelection = .group(name)
        reconcileSelection()
        return true
    }

    @discardableResult
    func saveAnnotation(alias: String, group: String, note: String) -> Bool {
        var candidate = metadata
        var annotation = annotation(for: alias)
        annotation.group = group
        annotation.note = note
        candidate.annotations[alias] = annotation
        guard persist(candidate) else { return false }
        reconcileSelection()
        return true
    }

    func toggleFavorite(_ alias: String) {
        var candidate = metadata
        var annotation = annotation(for: alias)
        annotation.isFavorite.toggle()
        candidate.annotations[alias] = annotation
        if persist(candidate) { reconcileSelection() }
    }

    func connect(_ host: HostEntry) {
        guard !isConnecting, hostsByAlias[host.alias] != nil else { return }
        do {
            try SSHCommand.validate(alias: host.alias)
        } catch {
            errorNotice = OperationNotice(message: error.localizedDescription)
            return
        }
        let target = preferredTerminal
        connectingAlias = host.alias
        errorNotice = nil
        statusTask?.cancel()
        statusMessage = "正在交给 \(target.displayName)…"
        Task { [self] in
            defer { connectingAlias = nil }
            do {
                try await launcher.launch(alias: host.alias, target: target)
                var candidate = metadata
                var annotation = annotation(for: host.alias)
                annotation.lastLaunchedAt = Date()
                candidate.annotations[host.alias] = annotation
                if metadataWritable { _ = persist(candidate) }
                showTransientStatus("已交给 \(target.displayName)，登录结果请在终端中查看。")
            } catch let error as TerminalLaunchError {
                statusMessage = nil
                let denied: Bool
                if case .automationDenied = error { denied = true } else { denied = false }
                errorNotice = OperationNotice(message: error.localizedDescription, copyAlias: host.alias, offersAutomationSettings: denied)
            } catch {
                statusMessage = nil
                errorNotice = OperationNotice(message: "无法将连接交给 \(target.displayName)。", copyAlias: host.alias)
            }
        }
    }

    func copyCommand(_ host: HostEntry) {
        copyCommand(for: host.alias)
    }

    func copyCommand(for alias: String) {
        do {
            let command = try SSHCommand.connectionCommand(for: alias)
            NSPasteboard.general.clearContents()
            guard NSPasteboard.general.setString(command, forType: .string) else {
                errorNotice = OperationNotice(message: "无法访问剪贴板，请稍后重试。", copyAlias: alias)
                return
            }
            showTransientStatus("已复制连接命令。")
        } catch { errorNotice = OperationNotice(message: error.localizedDescription) }
    }

    func openAutomationSettings() {
        let privacySettings = "x-apple.systempreferences:com.apple.preference.security"
        for location in [privacySettings + "?Privacy_Automation", privacySettings] {
            if let url = URL(string: location), NSWorkspace.shared.open(url) { return }
        }
        errorNotice = OperationNotice(message: "无法打开自动化设置。请前往系统设置，在「隐私与安全性」中选择「自动化」。")
    }

    func mainWindowAppeared() {
        visibleWindowCount += 1
        clearTransientStatus()
    }

    func mainWindowDisappeared() {
        visibleWindowCount = max(0, visibleWindowCount - 1)
        _ = flushAllAnnotations()
        if visibleWindowCount == 0 { clearTransientStatus() }
    }

    func clearTransientStatus() {
        statusTask?.cancel()
        if !isConnecting { statusMessage = nil }
    }

    private func showTransientStatus(_ message: String) {
        statusTask?.cancel()
        statusMessage = visibleWindowCount > 0 ? message : nil
        guard statusMessage != nil else { return }
        statusTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(3)) } catch { return }
            guard !Task.isCancelled else { return }
            self?.statusMessage = nil
        }
    }

    func showInFinder(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    func showMetadataInFinder() {
        let directory = metadataURL.deletingLastPathComponent()
        if FileManager.default.fileExists(atPath: metadataURL.path) {
            showInFinder(metadataURL.path)
        } else if FileManager.default.fileExists(atPath: directory.path) {
            showInFinder(directory.path)
        } else {
            showInFinder(directory.deletingLastPathComponent().path)
        }
    }

    func reloadMetadata() {
        do {
            let document = try metadataStore.reload()
            for task in annotationSaveTasks.values { task.cancel() }
            annotationSaveTasks.removeAll()
            pendingAnnotationAliases.removeAll()
            metadata = document
            metadataWritable = true
            metadataError = nil
            reconcileSelection()
        } catch {
            metadataWritable = false
            metadataError = "附加信息重读失败。\(error.localizedDescription)"
        }
    }

    func displayPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path == home ? "~" : path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }

    private func persist(_ candidate: MetadataDocument) -> Bool {
        guard metadataWritable else { return false }
        do {
            try metadataStore.save(candidate)
            metadata = candidate
            metadataError = nil
            return true
        } catch let error as MetadataStoreError {
            switch error {
            case .damaged, .unreadable, .locked, .unsupportedVersion, .conflict:
                metadataWritable = false
            case .writeFailed:
                break
            }
            metadataError = "附加信息保存失败，本次修改尚未保存：\(error.localizedDescription)"
            return false
        } catch {
            metadataError = "附加信息保存失败，本次修改尚未保存：\(error.localizedDescription)"
            return false
        }
    }

    func loadExcerpts(for host: HostEntry) async -> [SourceExcerpt] {
        #if DEBUG
        excerptReadCount += 1
        let readerOverride = excerptReaderOverride
        #endif
        let sourceIdentities = snapshot.sourceIdentities
        let worker = Task.detached(priority: .utility) {
            #if DEBUG
            if let readerOverride {
                return readerOverride(host, sourceIdentities, { Task.isCancelled })
            }
            #endif
            return SourceExcerptReader.read(for: host, sourceIdentities: sourceIdentities, shouldCancel: { Task.isCancelled })
        }
        return await withTaskCancellationHandler {
            await worker.value
        } onCancel: {
            worker.cancel()
        }
    }
}
