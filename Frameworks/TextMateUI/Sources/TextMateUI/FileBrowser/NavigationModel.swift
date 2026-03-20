import SwiftUI

// MARK: - Navigation Model

/// Manages back/forward navigation history for the file browser.
/// Replaces the navigation tracking in FileBrowserViewController.mm.
@MainActor
@Observable
public final class NavigationModel {
    public var currentURL: URL
    public internal(set) var history: [NavigationEntry] = []
    public internal(set) var historyIndex: Int = -1

    public init(url: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.currentURL = url
        pushEntry(url)
    }

    // MARK: - Navigation

    public var canGoBack: Bool {
        historyIndex > 0
    }

    public var canGoForward: Bool {
        historyIndex < history.count - 1
    }

    public func goBack() {
        guard canGoBack else { return }
        historyIndex -= 1
        currentURL = history[historyIndex].url
    }

    public func goForward() {
        guard canGoForward else { return }
        historyIndex += 1
        currentURL = history[historyIndex].url
    }

    public func goToParent() {
        let parent = currentURL.deletingLastPathComponent()
        navigateTo(parent)
    }

    public func navigateTo(_ url: URL) {
        currentURL = url
        pushEntry(url)
    }

    // MARK: - Special Locations

    public func goHome() {
        navigateTo(FileManager.default.homeDirectoryForCurrentUser)
    }

    public func goToDesktop() {
        if let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first {
            navigateTo(desktop)
        }
    }

    public func goToRoot() {
        navigateTo(URL(fileURLWithPath: "/"))
    }

    public func goToComputer() {
        navigateTo(URL(fileURLWithPath: "/Volumes"))
    }

    // MARK: - Breadcrumb Path

    /// Returns breadcrumb components from root to current URL.
    public var breadcrumbs: [BreadcrumbItem] {
        var items: [BreadcrumbItem] = []
        var url = currentURL

        while url.path != "/" {
            items.insert(BreadcrumbItem(url: url, name: url.lastPathComponent), at: 0)
            url = url.deletingLastPathComponent()
        }
        items.insert(BreadcrumbItem(url: URL(fileURLWithPath: "/"), name: "/"), at: 0)

        return items
    }

    // MARK: - Favorites

    public var favorites: [URL] {
        // In production, reads from file browser favorites
        [
            FileManager.default.homeDirectoryForCurrentUser,
            FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first,
            FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
            FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first,
        ].compactMap { $0 }
    }

    // MARK: - Private

    private func pushEntry(_ url: URL) {
        // Truncate forward history
        if historyIndex < history.count - 1 {
            history = Array(history.prefix(historyIndex + 1))
        }
        history.append(NavigationEntry(url: url))
        historyIndex = history.count - 1
    }
}

// MARK: - Navigation Entry

public struct NavigationEntry {
    public let url: URL
    public let timestamp = Date()
}

// MARK: - Breadcrumb Item

public struct BreadcrumbItem: Identifiable {
    public let id = UUID()
    public let url: URL
    public let name: String
}
