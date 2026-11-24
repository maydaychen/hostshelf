import AppKit
import HostShelfCore

@MainActor
public final class ExternalActionLauncher {
    typealias ApplicationURLProvider = @MainActor (EditorTarget) -> URL?
    typealias URLOpener = @MainActor (URL, URL?) -> Bool

    private let applicationURLProvider: ApplicationURLProvider
    private let openURL: URLOpener

    public init() {
        applicationURLProvider = { target in
            target.bundleIdentifier.flatMap {
                NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0)
            }
        }
        openURL = { url, appURL in
            if let appURL {
                let defaultApp = NSWorkspace.shared.urlForApplication(toOpen: url)
                if defaultApp?.standardizedFileURL == appURL.standardizedFileURL {
                    return NSWorkspace.shared.open(url)
                }
                let config = NSWorkspace.OpenConfiguration()
                NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: config, completionHandler: nil)
                return true
            }
            return NSWorkspace.shared.open(url)
        }
    }

    init(
        applicationURLProvider: @escaping ApplicationURLProvider,
        openURL: @escaping URLOpener
    ) {
        self.applicationURLProvider = applicationURLProvider
        self.openURL = openURL
    }

    public func isAvailable(_ editor: EditorTarget) -> Bool {
        if editor == .systemDefault { return true }
        return applicationURLProvider(editor) != nil
    }

    public func openFile(path: String, line: Int, in editor: EditorTarget) throws {
        guard let url = ExternalActionBuilder.editorFileURL(for: editor, filePath: path, line: line) else {
            throw ExternalActionError.invalidFilePath
        }
        let targetAppURL = try resolvedAppURL(for: editor)
        guard openURL(url, targetAppURL) else {
            throw ExternalActionError.openFailed(editor.displayName)
        }
    }

    public func openRemoteSSH(alias: String, in editor: EditorTarget) throws {
        let url = try ExternalActionBuilder.remoteSSHURL(for: editor, alias: alias)
        let targetAppURL = try resolvedAppURL(for: editor)
        guard openURL(url, targetAppURL) else {
            throw ExternalActionError.openFailed("\(editor.displayName) Remote-SSH")
        }
    }

    public func openWebURL(_ url: URL) throws {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            throw ExternalActionError.openFailed(url.absoluteString)
        }
        guard openURL(url, nil) else {
            throw ExternalActionError.openFailed(url.absoluteString)
        }
    }

    private func resolvedAppURL(for editor: EditorTarget) throws -> URL? {
        if editor == .systemDefault { return nil }
        guard let appURL = applicationURLProvider(editor) else {
            throw ExternalActionError.editorUnavailable(editor)
        }
        return appURL
    }
}
