import SwiftUI

// MARK: - File Browser View

/// SwiftUI replacement for FileBrowserViewController.mm + FileBrowserView.mm.
/// Uses List with recursive DisclosureGroup for the file tree.
public struct FileBrowserView: View {
    var model: FileTreeModel

    @State private var editingURL: URL?
    @State private var editingName: String = ""

    public init(model: FileTreeModel) {
        self.model = model
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header with navigation
            FileBrowserHeaderView(navigation: model.navigation)

            Divider()

            // File tree
            if model.isLoading {
                Spacer()
                ProgressView()
                    .controlSize(.small)
                Spacer()
            } else {
                fileTreeList
            }

            Divider()

            // Actions bar
            FileBrowserActionsView(
                onCreateFile: { _ = model.createFile(nil) },
                onCreateFolder: { _ = model.createFolder(nil) },
                onReload: { model.reload(nil) },
                onSearch: { /* TODO: Trigger folder search */ },
                onShowFavorites: { /* TODO: Show favorites panel */ },
                onShowSCMStatus: { /* TODO: Show SCM status view */ }
            )
        }
        .frame(minWidth: 200)
        .onAppear {
            model.loadDirectory(at: model.navigation.currentURL)
        }
        .onChange(of: model.navigation.currentURL) { _, newURL in
            model.loadDirectory(at: newURL)
        }
    }

    // MARK: - File Tree List

    private var fileTreeList: some View {
        List(selection: Binding(
            get: { model.selectedURLs },
            set: { model.selectedURLs = $0 }
        )) {
            ForEach(model.rootItems) { item in
                fileTreeRow(item: item)
            }
        }
        .listStyle(.sidebar)
        .environment(\.defaultMinListRowHeight, 22)
        .onChange(of: model.selectedURLs) { oldValue, newValue in
            for url in newValue.subtracting(oldValue) {
                let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                if !isDir {
                    model.dispatchOpenURLs([url])
                }
            }
        }
    }

    // MARK: - Recursive Tree Row

    private func fileTreeRow(item: FileItemWrapper) -> AnyView {
        if item.isDirectory {
            return AnyView(
                DisclosureGroup(
                    isExpanded: Binding(
                        get: { model.expandedURLs.contains(item.url) },
                        set: { expanded in
                            if expanded {
                                model.expandedURLs.insert(item.url)
                                if item.children == nil {
                                    item.loadChildren()
                                }
                            } else {
                                model.expandedURLs.remove(item.url)
                            }
                        }
                    )
                ) {
                    if let children = item.children {
                        ForEach(children) { child in
                            fileTreeRow(item: child)
                        }
                    }
                } label: {
                    FileItemRow(item: item, isSelected: model.selectedURLs.contains(item.url))
                        .tag(item.url)
                }
                .contextMenu { contextMenuItems(for: item) }
            )
        } else {
            return AnyView(
                FileItemRow(item: item, isSelected: model.selectedURLs.contains(item.url))
                    .tag(item.url)
                    .contextMenu { contextMenuItems(for: item) }
            )
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func contextMenuItems(for item: FileItemWrapper) -> some View {
        Button("Open") { openItem(item) }
        Button("Open in New Tab") { model.dispatchOpenURLs([item.url]) }
        Divider()
        Button("Reveal in Finder") {
            NSWorkspace.shared.activateFileViewerSelecting([item.url])
        }
        Divider()
        Button("Rename\u{2026}") {
            startRename(item)
        }
        Button("Duplicate") {
            duplicateItem(item)
        }
        Button("Move to Trash") {
            trashItem(item)
        }
        Divider()
        Button("Copy Path") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(item.url.path, forType: .string)
        }
        Button("Copy Relative Path") {
            let relativePath = item.url.path.replacingOccurrences(
                of: model.navigation.currentURL.path + "/",
                with: ""
            )
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(relativePath, forType: .string)
        }
    }

    // MARK: - Actions

    private func openItem(_ item: FileItemWrapper) {
        if item.isDirectory {
            model.navigation.navigateTo(item.url)
        } else {
            model.dispatchOpenURLs([item.url])
        }
    }

    private func startRename(_ item: FileItemWrapper) {
        editingURL = item.url
        editingName = item.displayName
    }

    private func duplicateItem(_ item: FileItemWrapper) {
        let name = item.url.deletingPathExtension().lastPathComponent
        let ext = item.url.pathExtension
        let newName = ext.isEmpty ? "\(name) copy" : "\(name) copy.\(ext)"
        let newURL = item.url.deletingLastPathComponent().appendingPathComponent(newName)
        try? FileManager.default.copyItem(at: item.url, to: newURL)
        model.refresh()
    }

    private func trashItem(_ item: FileItemWrapper) {
        try? FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
        model.selectedURLs.remove(item.url)
        model.refresh()
    }
}
