import SwiftUI

// MARK: - Where Menu Item

public struct WhereMenuItem: Identifiable {
    public let id = UUID()
    public var title: String
    public var tag: Int
    public var iconName: String?
    public var isSeparator: Bool
    public var indent: Int

    public init(title: String = "", tag: Int = -1, iconName: String? = nil, isSeparator: Bool = false, indent: Int = 0) {
        self.title = title
        self.tag = tag
        self.iconName = iconName
        self.isSeparator = isSeparator
        self.indent = indent
    }
}

// MARK: - Find Panel Model

/// Observable model for the floating Find panel (project/folder/open-files search).
/// Uses @objc(FindPanelModel) so ObjC can instantiate via NSClassFromString("FindPanelModel").
@MainActor
@objc(FindPanelModel)
@Observable
public final class FindPanelModel: NSObject {

    // MARK: - Search State (set by Find.mm via KVC)

    @objc public var findString: String = "" {
        didSet {
            guard findString != oldValue else { return }
            _ = target?.perform(NSSelectorFromString("findPanelDidChangeFindString:"), with: self)
        }
    }
    @objc public var replaceString: String = "" {
        didSet {
            guard replaceString != oldValue else { return }
            _ = target?.perform(NSSelectorFromString("findPanelDidChangeReplaceString:"), with: self)
        }
    }

    // MARK: - Options (bidirectional — model changes notify Find.mm)

    @objc public var regularExpression: Bool = false {
        didSet {
            guard regularExpression != oldValue else { return }
            _ = target?.perform(NSSelectorFromString("findPanelDidChangeOptions:"), with: self)
        }
    }
    @objc public var ignoreCase: Bool = true {
        didSet {
            guard ignoreCase != oldValue else { return }
            _ = target?.perform(NSSelectorFromString("findPanelDidChangeOptions:"), with: self)
        }
    }
    @objc public var wrapAround: Bool = true {
        didSet {
            guard wrapAround != oldValue else { return }
            _ = target?.perform(NSSelectorFromString("findPanelDidChangeOptions:"), with: self)
        }
    }
    @objc public var ignoreWhitespace: Bool = false {
        didSet {
            guard ignoreWhitespace != oldValue else { return }
            _ = target?.perform(NSSelectorFromString("findPanelDidChangeOptions:"), with: self)
        }
    }
    @objc public var fullWords: Bool = false {
        didSet {
            guard fullWords != oldValue else { return }
            _ = target?.perform(NSSelectorFromString("findPanelDidChangeOptions:"), with: self)
        }
    }

    // MARK: - Folder Search Options

    @objc public var searchHiddenFolders: Bool = false {
        didSet {
            guard searchHiddenFolders != oldValue else { return }
            _ = target?.perform(NSSelectorFromString("findPanelDidChangeFolderOptions:"), with: self)
        }
    }
    @objc public var searchFolderLinks: Bool = false {
        didSet {
            guard searchFolderLinks != oldValue else { return }
            _ = target?.perform(NSSelectorFromString("findPanelDidChangeFolderOptions:"), with: self)
        }
    }
    @objc public var searchFileLinks: Bool = true {
        didSet {
            guard searchFileLinks != oldValue else { return }
            _ = target?.perform(NSSelectorFromString("findPanelDidChangeFolderOptions:"), with: self)
        }
    }
    @objc public var searchBinaryFiles: Bool = false {
        didSet {
            guard searchBinaryFiles != oldValue else { return }
            _ = target?.perform(NSSelectorFromString("findPanelDidChangeFolderOptions:"), with: self)
        }
    }

    // MARK: - Computed State

    @objc public var canEditGlob: Bool = false
    @objc public var canReplaceInDocument: Bool = true

    public var canIgnoreWhitespace: Bool { !regularExpression }

    @objc public var canReplaceAll: Bool = true
    @objc public var replaceAllButtonTitle: String = "Replace All"

    // MARK: - Status (pushed by Find.mm)

    @objc public var statusText: String = ""
    @objc public var alternateStatusText: String = ""
    @objc public var isSearching: Bool = false

    @objc public var countOfMatches: Int = 0
    @objc public var countOfExcludedMatches: Int = 0
    @objc public var countOfReadOnlyMatches: Int = 0
    @objc public var countOfExcludedReadOnlyMatches: Int = 0

    @objc public var showResults: Bool = false
    @objc public var hideCheckBoxes: Bool = false

    // MARK: - Glob

    @objc public var globString: String = "*"
    @objc public var globHistory: [String] = ["*", "*.txt", "*.{c,h}"]

    // MARK: - Where Popup (NSPopUpButton wrapped via NSViewRepresentable)

    @ObservationIgnored
    @objc public var wherePopUpButton: NSPopUpButton?

    // MARK: - AppKit View References (set by Find.mm)

    @ObservationIgnored
    @objc public var resultsView: NSView?

    @ObservationIgnored
    @objc public var statusBarView: NSView?

    // MARK: - Actions Menu (NSPopUpButton from Find.mm)

    @ObservationIgnored
    @objc public var actionsPopUpButton: NSPopUpButton?

    // MARK: - Delegate/Target

    @ObservationIgnored
    @objc public weak var target: AnyObject?

    // MARK: - Hosting View

    @ObservationIgnored
    @objc public lazy var hostingView: NSView = {
        let view = NSHostingView(rootView: FindPanelView(model: self))
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    // MARK: - Init

    public override init() {
        super.init()
    }

    // MARK: - Actions (dispatch to ObjC target)

    public func findAll() {
        _ = target?.perform(NSSelectorFromString("findPanelFindAll:"), with: self)
    }

    public func findNext() {
        _ = target?.perform(NSSelectorFromString("findPanelFindNext:"), with: self)
    }

    public func findPrevious() {
        _ = target?.perform(NSSelectorFromString("findPanelFindPrevious:"), with: self)
    }

    public func replaceAll() {
        _ = target?.perform(NSSelectorFromString("findPanelReplaceAll:"), with: self)
    }

    public func replaceOne() {
        _ = target?.perform(NSSelectorFromString("findPanelReplace:"), with: self)
    }

    public func replaceAndFind() {
        _ = target?.perform(NSSelectorFromString("findPanelReplaceAndFind:"), with: self)
    }

    public func countOccurrences() {
        _ = target?.perform(NSSelectorFromString("findPanelCountOccurrences:"), with: self)
    }

    public func stopSearch() {
        _ = target?.perform(NSSelectorFromString("findPanelStopSearch:"), with: self)
    }

    public func showFindHistory() {
        _ = target?.perform(NSSelectorFromString("findPanelShowFindHistory:"), with: self)
    }

    public func showReplaceHistory() {
        _ = target?.perform(NSSelectorFromString("findPanelShowReplaceHistory:"), with: self)
    }
}
