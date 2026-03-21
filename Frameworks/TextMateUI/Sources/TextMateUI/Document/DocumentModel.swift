import SwiftUI

/// Reactive model that mirrors OakDocument/OakTextView state.
///
/// State flows one-way from ObjC → Swift via KVC push (same pattern as
/// ``StatusBarViewModel``, ``TabBarModel``, etc.).  OakDocumentView.mm
/// instantiates this via `NSClassFromString("DocumentModel")` and pushes
/// editor state alongside the existing StatusBarViewModel pushes.
/// DocumentWindowController.mm pushes document-level identity/state.
@MainActor
@objc(DocumentModel)
@Observable
public final class DocumentModel: NSObject {

	// MARK: - Document Identity

	/// File path (empty string for untitled documents).
	@objc public var path: String = ""

	/// Display name shown in tabs/title bar.
	@objc public var displayName: String = ""

	/// OakDocument UUID string.
	@objc public var identifier: String = ""

	// MARK: - Document State

	/// Whether the document has unsaved changes.
	@objc public var isDocumentEdited: Bool = false

	/// Whether the file exists on disk.
	@objc public var isOnDisk: Bool = false

	// MARK: - Editor State

	/// Current selection (e.g. "1:5", "2:3-4:8").
	@objc public var selectionString: String = ""

	/// Symbol at the caret position.
	@objc public var symbolName: String = ""

	/// UTI or grammar scope (e.g. "source.swift").
	@objc public var fileType: String = ""

	/// Human-readable grammar name (e.g. "Swift").
	@objc public var grammarName: String = ""

	/// Tab width in spaces.
	@objc public var tabSize: Int = 4

	/// Whether indent uses spaces (true) or tabs (false).
	@objc public var softTabs: Bool = false

	// MARK: - Theme

	/// UUID of the current syntax theme.
	@objc public var themeUUID: String = ""

	// MARK: - Hosting (future use)

	@ObservationIgnored
	@objc public lazy var hostingView: NSView = {
		// Placeholder — will host SwiftUI document chrome in Phase 4b.
		let view = NSView(frame: .zero)
		view.translatesAutoresizingMaskIntoConstraints = false
		return view
	}()

	public override init() {
		super.init()
	}
}
