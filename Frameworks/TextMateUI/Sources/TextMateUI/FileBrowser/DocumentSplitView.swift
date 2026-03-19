import SwiftUI

// MARK: - Document Split View

/// Top-level container using NavigationSplitView.
/// Sidebar: FileBrowserView. Detail: wrapped AppKit ProjectLayoutView.
/// On macOS Tahoe (26), the sidebar automatically gets Liquid Glass.
struct DocumentSplitView: View {
    @Bindable var model: DocumentSplitModel

    var body: some View {
        NavigationSplitView(columnVisibility: $model.sidebarVisibility) {
            FileBrowserView(model: model.fileTreeModel)
                .navigationSplitViewColumnWidth(min: 150, ideal: 250, max: 500)
        } detail: {
            if let detailView = model.detailView {
                AppKitViewRepresentable(nsView: detailView)
            } else {
                Color.clear
            }
        }
        .navigationSplitViewStyle(.prominentDetail)
    }
}

// MARK: - AppKit View Wrapper

/// Wraps an existing AppKit NSView for embedding in SwiftUI.
struct AppKitViewRepresentable: NSViewRepresentable {
    let nsView: NSView

    func makeNSView(context: Context) -> NSView {
        nsView
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // Nothing to update — the AppKit view manages itself.
    }
}
