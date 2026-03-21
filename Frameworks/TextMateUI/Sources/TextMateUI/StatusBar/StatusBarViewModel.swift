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

	public override init() {
		super.init()
	}
}
