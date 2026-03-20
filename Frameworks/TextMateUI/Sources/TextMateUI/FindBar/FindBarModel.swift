import SwiftUI

// MARK: - Find Bar Model

/// Observable model for the inline find/replace bar.
/// Uses @objc(FindBarModel) so ObjC can instantiate via NSClassFromString("FindBarModel").
@MainActor
@objc(FindBarModel)
@Observable
public final class FindBarModel: NSObject {
    @objc public var findString: String = "" {
        didSet {
            guard findString != oldValue else { return }
            _ = target?.perform(NSSelectorFromString("findBarDidChangeSearchString:"), with: self)
        }
    }
    @objc public var replaceString: String = ""
    @objc public var matchCount: Int = 0
    @objc public var currentMatchIndex: Int = 0
    @objc public var showReplace: Bool = false

    // Find options
    @objc public var regularExpression: Bool = false {
        didSet { _ = target?.perform(NSSelectorFromString("findBarDidChangeOptions:"), with: self) }
    }
    @objc public var ignoreCase: Bool = true {
        didSet { _ = target?.perform(NSSelectorFromString("findBarDidChangeOptions:"), with: self) }
    }
    @objc public var wrapAround: Bool = true {
        didSet { _ = target?.perform(NSSelectorFromString("findBarDidChangeOptions:"), with: self) }
    }

    // Status message from find operations
    @objc public var statusMessage: String = ""

    @ObservationIgnored
    @objc public weak var target: AnyObject?

    @ObservationIgnored
    @objc public lazy var hostingView: NSView = {
        let view = NSHostingView(rootView: FindBarView(model: self))
        view.translatesAutoresizingMaskIntoConstraints = false
        view.setContentHuggingPriority(.required, for: .vertical)
        return view
    }()

    public override init() {
        super.init()
    }

    // MARK: - Match Display

    public var matchDisplay: String {
        if findString.isEmpty { return "" }
        if matchCount == 0 { return "No results" }
        if currentMatchIndex > 0 {
            return "\(currentMatchIndex)/\(matchCount)"
        }
        return "\(matchCount) found"
    }

    // MARK: - Actions (dispatch to ObjC target)

    public func findNext() {
        _ = target?.perform(NSSelectorFromString("findBarFindNext:"), with: self)
    }

    public func findPrevious() {
        _ = target?.perform(NSSelectorFromString("findBarFindPrevious:"), with: self)
    }

    public func replaceOne() {
        _ = target?.perform(NSSelectorFromString("findBarReplace:"), with: self)
    }

    public func replaceAll() {
        _ = target?.perform(NSSelectorFromString("findBarReplaceAll:"), with: self)
    }

    public func dismiss() {
        _ = target?.perform(NSSelectorFromString("findBarDismiss:"), with: self)
    }
}
