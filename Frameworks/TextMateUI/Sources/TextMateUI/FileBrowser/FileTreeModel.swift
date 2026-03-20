import SwiftUI

// MARK: - File Tree Model

/// Observable model wrapping the existing FileItem ObjC objects.
/// Uses @objc(FileTreeModel) so ObjC can instantiate via NSClassFromString("FileTreeModel").
@objc(FileTreeModel)
@Observable
public final class FileTreeModel: NSObject {
    public var rootItems: [FileItemWrapper] = []
    public var expandedURLs: Set<URL> = []
    public var selectedURLs: Set<URL> = []
    public var isLoading = false

    // MARK: - ObjC Interop

    @ObservationIgnored
    @objc public weak var delegate: AnyObject?

    @ObservationIgnored
    @objc public weak var target: AnyObject?

    @ObservationIgnored
    public var navigation: NavigationModel

    // MARK: - Hosting View

    @ObservationIgnored
    @objc public lazy var hostingView: NSView = {
        let view = NSHostingView(rootView: FileBrowserView(model: self))
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    // MARK: - Init

    public override init() {
        self.navigation = NavigationModel()
        super.init()
    }

    // MARK: - ObjC Properties

    @objc public var path: String? {
        navigation.currentURL.path
    }

    @objc public var selectedFileURLs: [URL] {
        Array(selectedURLs)
    }

    @objc public var directoryURLForNewItems: URL? {
        if selectedURLs.count == 1, let url = selectedURLs.first {
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            return isDir ? url : url.deletingLastPathComponent()
        }
        return navigation.currentURL
    }

    @objc public var environmentVariables: [String: String] {
        var vars: [String: String] = [:]
        let selected = Array(selectedURLs)
        if let first = selected.first {
            vars["TM_SELECTED_FILE"] = first.path
        }
        if !selected.isEmpty {
            vars["TM_SELECTED_FILES"] = selected.map { "'\($0.path)'" }.joined(separator: " ")
        }
        return vars
    }

    // MARK: - Session State

    @objc public var sessionState: Any? {
        var state: [String: Any] = [:]
        state["currentURL"] = navigation.currentURL.absoluteString
        state["historyURLs"] = navigation.history.map { $0.url.absoluteString }
        state["historyIndex"] = navigation.historyIndex
        state["expandedURLs"] = expandedURLs.map { $0.absoluteString }
        state["selectedURLs"] = selectedURLs.map { $0.absoluteString }
        return state
    }

    @objc public func setupViewWithState(_ state: Any?) {
        guard let dict = state as? [String: Any] else { return }

        if let urlString = dict["currentURL"] as? String,
           let url = URL(string: urlString) {
            navigation.navigateTo(url)
        }

        if let historyStrings = dict["historyURLs"] as? [String],
           let index = dict["historyIndex"] as? Int {
            let entries = historyStrings.compactMap { URL(string: $0) }.map { NavigationEntry(url: $0) }
            if !entries.isEmpty {
                navigation.history = entries
                navigation.historyIndex = min(index, entries.count - 1)
                navigation.currentURL = entries[navigation.historyIndex].url
            }
        }

        if let expandedStrings = dict["expandedURLs"] as? [String] {
            expandedURLs = Set(expandedStrings.compactMap { URL(string: $0) })
        }

        if let selectedStrings = dict["selectedURLs"] as? [String] {
            selectedURLs = Set(selectedStrings.compactMap { URL(string: $0) })
        }
    }

    // MARK: - Navigation Actions

    @objc public func goToURL(_ url: URL) {
        navigation.navigateTo(url)
    }

    @objc public func goBack(_ sender: Any?) {
        navigation.goBack()
    }

    @objc public func goForward(_ sender: Any?) {
        navigation.goForward()
    }

    @objc public func goToParentFolder(_ sender: Any?) {
        navigation.goToParent()
    }

    @objc public func goToComputer(_ sender: Any?) {
        navigation.goToComputer()
    }

    @objc public func goToHome(_ sender: Any?) {
        navigation.goHome()
    }

    @objc public func goToDesktop(_ sender: Any?) {
        navigation.goToDesktop()
    }

    @objc public func selectURL(_ url: URL, withParentURL parentURL: URL?) {
        if let parentURL = parentURL, navigation.currentURL != parentURL {
            navigation.navigateTo(parentURL)
        }
        selectedURLs = [url]
    }

    @objc public func createFolder(_ sender: Any?) -> URL? {
        let url = (directoryURLForNewItems ?? navigation.currentURL).appendingPathComponent("untitled folder")
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
            refresh()
            return url
        } catch {
            return nil
        }
    }

    @objc public func createFile(_ sender: Any?) -> URL? {
        let url = (directoryURLForNewItems ?? navigation.currentURL).appendingPathComponent("untitled")
        if FileManager.default.createFile(atPath: url.path, contents: nil) {
            refresh()
            return url
        }
        return nil
    }

    @objc public func reload(_ sender: Any?) {
        refresh()
    }

    @objc public func deselectAll(_ sender: Any?) {
        selectedURLs.removeAll()
    }

    @objc public func orderFrontGoToFolder(_ sender: Any?) {
        // TODO: Show "Go to Folder" panel
    }

    @objc public func goToFavorites(_ sender: Any?) {
        // No-op for now
    }

    // MARK: - Menu Validation

    @objc public func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        let action = menuItem.action
        if action == NSSelectorFromString("goBack:") {
            return navigation.canGoBack
        } else if action == NSSelectorFromString("goForward:") {
            return navigation.canGoForward
        } else if action == NSSelectorFromString("newFolder:") {
            return directoryURLForNewItems != nil
        }
        return true
    }

    // MARK: - Delegate Dispatch

    func dispatchOpenURLs(_ urls: [URL]) {
        _ = delegate?.perform(
            NSSelectorFromString("fileBrowserModel:openURLs:"),
            with: self, with: urls as NSArray
        )
    }

    func dispatchCloseURL(_ url: URL) {
        _ = delegate?.perform(
            NSSelectorFromString("fileBrowserModel:closeURL:"),
            with: self, with: url as NSURL
        )
    }

    // MARK: - File System Operations

    public func loadDirectory(at url: URL) {
        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let items = Self.loadItems(at: url)
            DispatchQueue.main.async {
                self?.rootItems = items
                self?.isLoading = false
            }
        }
    }

    public func refresh() {
        loadDirectory(at: navigation.currentURL)
    }

    public func toggleExpansion(of item: FileItemWrapper) {
        if expandedURLs.contains(item.url) {
            expandedURLs.remove(item.url)
        } else {
            expandedURLs.insert(item.url)
            if item.children == nil {
                item.loadChildren()
            }
        }
    }

    // MARK: - File Loading

    private static func loadItems(at url: URL) -> [FileItemWrapper] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .localizedNameKey, .effectiveIconKey, .tagNamesKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let foldersOnTop = UserDefaults.standard.bool(forKey: "foldersOnTop")

        return contents
            .map { FileItemWrapper(url: $0) }
            .sorted { a, b in
                if foldersOnTop && a.isDirectory != b.isDirectory {
                    return a.isDirectory
                }
                return a.displayName.localizedCaseInsensitiveCompare(b.displayName) == .orderedAscending
            }
    }
}

// MARK: - File Item Wrapper

/// Swift wrapper around a file system item.
/// In production, this wraps the existing ObjC FileItem class.
public final class FileItemWrapper: Identifiable, ObservableObject {
    public let id: URL
    public let url: URL
    public let displayName: String
    public let isDirectory: Bool
    public let isSymbolicLink: Bool
    public var children: [FileItemWrapper]?
    public var finderTags: [FinderTag] = []

    public init(url: URL) {
        self.id = url
        self.url = url

        let resourceValues = try? url.resourceValues(forKeys: [
            .isDirectoryKey, .localizedNameKey, .isSymbolicLinkKey, .tagNamesKey
        ])

        self.displayName = resourceValues?.localizedName ?? url.lastPathComponent
        self.isDirectory = resourceValues?.isDirectory ?? false
        self.isSymbolicLink = resourceValues?.isSymbolicLink ?? false

        if let tagNames = resourceValues?.tagNames {
            self.finderTags = tagNames.map { FinderTag(name: $0) }
        }
    }

    /// Lazily loads children for directories.
    public func loadChildren() {
        guard isDirectory, children == nil else { return }
        let fm = FileManager.default
        let foldersOnTop = UserDefaults.standard.bool(forKey: "foldersOnTop")

        guard let contents = try? fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .localizedNameKey, .effectiveIconKey, .tagNamesKey],
            options: [.skipsHiddenFiles]
        ) else {
            children = []
            return
        }

        children = contents
            .map { FileItemWrapper(url: $0) }
            .sorted { a, b in
                if foldersOnTop && a.isDirectory != b.isDirectory {
                    return a.isDirectory
                }
                return a.displayName.localizedCaseInsensitiveCompare(b.displayName) == .orderedAscending
            }
    }

    /// Icon for this file item.
    public var icon: NSImage {
        if isDirectory {
            return NSWorkspace.shared.icon(for: .folder)
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}

// MARK: - Supporting Types

public struct FinderTag: Identifiable {
    public let id = UUID()
    public let name: String

    public var color: Color {
        switch name.lowercased() {
        case "red":    return .red
        case "orange": return .orange
        case "yellow": return .yellow
        case "green":  return .green
        case "blue":   return .blue
        case "purple": return .purple
        case "gray":   return .gray
        default:       return .secondary
        }
    }
}
