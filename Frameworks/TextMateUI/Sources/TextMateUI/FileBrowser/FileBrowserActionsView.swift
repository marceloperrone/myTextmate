import SwiftUI

// MARK: - File Browser Actions View

/// Replaces OFBActionsView — bottom toolbar with action buttons.
public struct FileBrowserActionsView: View {
    let onCreateFile: () -> Void
    let onCreateFolder: () -> Void
    let onReload: () -> Void
    let onSearch: () -> Void
    let onShowFavorites: () -> Void
    let onShowSCMStatus: () -> Void

    public init(
        onCreateFile: @escaping () -> Void = {},
        onCreateFolder: @escaping () -> Void = {},
        onReload: @escaping () -> Void = {},
        onSearch: @escaping () -> Void = {},
        onShowFavorites: @escaping () -> Void = {},
        onShowSCMStatus: @escaping () -> Void = {}
    ) {
        self.onCreateFile = onCreateFile
        self.onCreateFolder = onCreateFolder
        self.onReload = onReload
        self.onSearch = onSearch
        self.onShowFavorites = onShowFavorites
        self.onShowSCMStatus = onShowSCMStatus
    }

    public var body: some View {
        HStack(spacing: 0) {
            // New file/folder menu
            Menu {
                Button("New File") {
                    onCreateFile()
                }
                Button("New Folder") {
                    onCreateFolder()
                }
            } label: {
                Image(systemName: "plus")
                    .frame(width: 28, height: 22)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 28)
            .help("New File/Folder")

            actionDivider

            // Reload
            Button(action: onReload) {
                Image(systemName: "arrow.clockwise")
                    .frame(width: 28, height: 22)
            }
            .buttonStyle(.borderless)
            .help("Reload")

            actionDivider

            // Search
            Button(action: onSearch) {
                Image(systemName: "magnifyingglass")
                    .frame(width: 28, height: 22)
            }
            .buttonStyle(.borderless)
            .help("Search in Folder")

            Spacer()

            actionDivider

            // Favorites
            Button(action: onShowFavorites) {
                Image(systemName: "star")
                    .frame(width: 28, height: 22)
            }
            .buttonStyle(.borderless)
            .help("Favorites")

            actionDivider

            // SCM status
            Button(action: onShowSCMStatus) {
                Image(systemName: "arrow.triangle.branch")
                    .frame(width: 28, height: 22)
            }
            .buttonStyle(.borderless)
            .help("SCM Status")

            actionDivider

            // More actions
            Menu {
                Button("Open in Finder") {
                    // Opens current directory in Finder
                }
                Button("Copy Path") {
                    // Copies path to clipboard
                }
                Divider()
                Button("Show Hidden Files") {
                    // Toggles hidden file visibility
                }
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 28, height: 22)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 28)
            .help("Actions")
        }
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
        .frame(height: 24)
        .background(.bar)
    }

    private var actionDivider: some View {
        Rectangle()
            .fill(.separator)
            .frame(width: 1, height: 16)
    }
}
