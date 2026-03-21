import SwiftUI

// MARK: - Document Split Model

/// Bridge between ObjC DocumentWindowController and the NavigationSplitView container.
/// Owns the FileTreeModel and manages sidebar visibility.
/// ObjC instantiates via NSClassFromString("DocumentSplitModel").
@MainActor
@objc(DocumentSplitModel)
@Observable
public final class DocumentSplitModel: NSObject {

    // MARK: - ObjC Interop

    @ObservationIgnored
    @objc public weak var delegate: AnyObject?

    // MARK: - File Tree Model (owned)

    @ObservationIgnored
    public var fileTreeModel: FileTreeModel

    /// KVC accessor so ObjC can reach the file tree model.
    @objc public var fileBrowser: FileTreeModel { fileTreeModel }

    // MARK: - Sidebar Visibility

    /// Drives NavigationSplitView column visibility.
    public var sidebarVisibility: NavigationSplitViewVisibility = .detailOnly

    /// KVC-settable from ObjC (bool ↔ visibility enum).
    @objc public var sidebarVisible: Bool {
        get { sidebarVisibility != .detailOnly }
        set { sidebarVisibility = newValue ? .all : .detailOnly }
    }

    // MARK: - Editor View (AppKit)

    /// The OakDocumentView, set from ObjC via KVC.
    @ObservationIgnored
    @objc public var editorView: NSView?

    // MARK: - Hosting View

    @ObservationIgnored
    @objc public lazy var hostingView: NSView = {
        let view = NSHostingView(rootView: DocumentSplitView(model: self))
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    // MARK: - Init

    public override init() {
        self.fileTreeModel = FileTreeModel()
        super.init()
    }
}
