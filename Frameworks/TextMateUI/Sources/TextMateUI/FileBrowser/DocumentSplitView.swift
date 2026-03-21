import SwiftUI

// MARK: - Document Split View

/// Top-level container using NavigationSplitView.
/// Sidebar: FileBrowserView. Detail: wrapped OakDocumentView via EditorViewRepresentable.
/// On macOS Tahoe (26), the sidebar automatically gets Liquid Glass.
struct DocumentSplitView: View {
    @Bindable var model: DocumentSplitModel

    var body: some View {
        NavigationSplitView(columnVisibility: $model.sidebarVisibility) {
            FileBrowserView(model: model.fileTreeModel)
                .navigationSplitViewColumnWidth(min: 150, ideal: 250, max: 500)
        } detail: {
            if model.editorView != nil {
                EditorViewRepresentable(editorView: model.editorView)
            } else {
                Color.clear
            }
        }
        .navigationSplitViewStyle(.prominentDetail)
    }
}
