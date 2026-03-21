import SwiftUI

@MainActor
@objc(StatusBarViewModel)
@Observable
public final class StatusBarViewModel: NSObject {
	/// Reference to the single-source-of-truth document model.
	/// Set from ObjC via KVC: `[statusBarModel setValue:_documentModel forKey:@"documentModel"]`
	@ObservationIgnored
	@objc public var documentModel: DocumentModel?

	@ObservationIgnored
	@objc public weak var delegate: AnyObject?

	@ObservationIgnored
	@objc public weak var target: AnyObject?

	@ObservationIgnored
	@objc public weak var bundleItemsPopUp: NSPopUpButton?

	@ObservationIgnored
	@objc public lazy var hostingView: NSView = {
		let view = NSHostingView(rootView: StatusBarView(model: self))
		view.translatesAutoresizingMaskIntoConstraints = false
		view.setContentHuggingPriority(.required, for: .vertical)
		return view
	}()

	// MARK: - Computed Display Properties

	public var formattedSelection: String {
		(documentModel?.selectionString ?? "")
			.replacingOccurrences(of: "&", with: ", ")
			.replacingOccurrences(of: "x", with: "\u{00D7}")
	}

	public var tabSizeDisplay: String {
		let label = (documentModel?.softTabs ?? false) ? "Soft Tabs" : "Tab Size"
		return "\(label):\u{2003}\(documentModel?.tabSize ?? 4)"
	}

	/// Fresh grammar list queried from the C++ bundles engine via BundlesBridge.
	public var currentGrammarEntries: [GrammarEntry] {
		BundlesBridge.availableGrammars().filter { !$0.hiddenFromUser }
	}

	// MARK: - Actions (dispatch to ObjC target via selectors)

	public func selectGrammar(uuid: String) {
		let item = NSMenuItem()
		item.representedObject = uuid
		_ = target?.perform(NSSelectorFromString("takeGrammarUUIDFrom:"), with: item)
	}

	public func selectTabSize(_ size: Int) {
		let item = NSMenuItem()
		item.tag = size
		_ = target?.perform(NSSelectorFromString("takeTabSizeFrom:"), with: item)
	}

	public func setIndentWithSpaces() {
		_ = target?.perform(NSSelectorFromString("setIndentWithSpaces:"), with: nil)
	}

	public func setIndentWithTabs() {
		_ = target?.perform(NSSelectorFromString("setIndentWithTabs:"), with: nil)
	}

	public func showTabSizePanel() {
		_ = target?.perform(NSSelectorFromString("showTabSizeSelectorPanel:"), with: nil)
	}

	public override init() {
		super.init()
	}
}
