import SwiftUI

// MARK: - Tab Bar Model

/// Observable model for the tab bar, replacing OakTabBarViewController's data arrays.
/// Uses @objc(TabBarModel) so ObjC can instantiate via NSClassFromString("TabBarModel").
@MainActor
@objc(TabBarModel)
@Observable
public final class TabBarModel: NSObject {
    public var tabs: [TabItem] = []
    @objc public var selectedIndex: Int = 0

    /// Controls whether the titlebar accessory is hidden (single-tab auto-collapse).
    @objc public var isHidden: Bool = false {
        didSet { _titlebarViewController?.isHidden = isHidden }
    }

    // MARK: - ObjC Interop (delegate/target pattern matching StatusBarViewModel)

    @ObservationIgnored
    @objc public weak var delegate: AnyObject?

    @ObservationIgnored
    @objc public weak var target: AnyObject?

    // MARK: - Callbacks (set from Swift; ObjC uses delegate/target selectors)

    @ObservationIgnored public var onSelectTab: ((Int) -> Void)?
    @ObservationIgnored public var onDoubleClickTab: ((Int) -> Void)?
    @ObservationIgnored public var onDoubleClickBackground: (() -> Void)?
    @ObservationIgnored public var onCloseTab: ((Int) -> Void)?
    @ObservationIgnored public var onCloseOtherTabs: ((Int) -> Void)?
    @ObservationIgnored public var onContextMenu: ((Int) -> NSMenu?)?
    @ObservationIgnored public var onDragTab: ((Int, Int) -> Void)?
    @ObservationIgnored public var onDropFromOtherTabBar: ((UUID, Int, NSDragOperation) -> Bool)?

    // MARK: - Titlebar Accessory

    @ObservationIgnored private var _titlebarViewController: NSTitlebarAccessoryViewController?

    @ObservationIgnored
    @objc public lazy var titlebarViewController: NSTitlebarAccessoryViewController = {
        let hostingView = NSHostingView(rootView: TabBarView(model: self))
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = .clear
        let vc = NSTitlebarAccessoryViewController()
        vc.view = hostingView
        vc.layoutAttribute = .bottom
        vc.fullScreenMinHeight = 28
        vc.isHidden = isHidden
        _titlebarViewController = vc
        return vc
    }()

    public override init() {
        super.init()
    }

    // MARK: - ObjC Bridge Methods

    /// Reload tabs from arrays passed by ObjC.
    /// ObjC calls: [tabBarModel reloadWithCount:titles:paths:identifiers:editedFlags:]
    @objc public func reload(
        withCount count: Int,
        titles: [String],
        paths: [String],
        identifiers: [NSUUID],
        editedFlags: [NSNumber]
    ) {
        var newTabs: [TabItem] = []
        for i in 0..<count {
            let uuid = identifiers[i] as UUID
            newTabs.append(TabItem(
                uuid: uuid,
                title: titles[i],
                path: paths[i],
                isModified: editedFlags[i].boolValue
            ))
        }
        tabs = newTabs
    }

    /// Select a tab by index — called from SwiftUI side.
    public func selectTab(at index: Int) {
        guard index >= 0, index < tabs.count else { return }
        selectedIndex = index
        if let onSelectTab {
            onSelectTab(index)
        } else {
            // Dispatch to ObjC delegate via selector
            _ = delegate?.perform(
                NSSelectorFromString("tabBarModel:didSelectIndex:"),
                with: self, with: NSNumber(value: index)
            )
        }
    }

    /// Close a tab at the given index.
    public func closeTab(at index: Int) {
        guard index >= 0, index < tabs.count else { return }
        if let onCloseTab {
            onCloseTab(index)
        } else {
            _ = delegate?.perform(
                NSSelectorFromString("tabBarModel:didCloseIndex:"),
                with: self, with: NSNumber(value: index)
            )
        }
    }

    /// Double-click on a tab (tear off).
    public func doubleClickTab(at index: Int) {
        if let onDoubleClickTab {
            onDoubleClickTab(index)
        } else {
            _ = delegate?.perform(
                NSSelectorFromString("tabBarModel:didDoubleClickIndex:"),
                with: self, with: NSNumber(value: index)
            )
        }
    }

    /// Double-click on empty area (new tab).
    public func doubleClickBackground() {
        if let onDoubleClickBackground {
            onDoubleClickBackground()
        } else {
            _ = delegate?.perform(
                NSSelectorFromString("tabBarModelDidDoubleClickBackground:"),
                with: self
            )
        }
    }

    /// Request context menu for tab at index (-1 for background).
    public func contextMenu(forIndex index: Int) -> NSMenu? {
        if let onContextMenu {
            return onContextMenu(index)
        }
        // Dispatch to delegate
        let result = delegate?.perform(
            NSSelectorFromString("tabBarModel:menuForIndex:"),
            with: self, with: NSNumber(value: index)
        )
        return result?.takeUnretainedValue() as? NSMenu
    }

    /// Number of visible tabs (for overflow/auto-close detection).
    @objc public var countOfVisibleTabs: Int {
        tabs.count
    }
}

// MARK: - Tab Item

public struct TabItem: Identifiable, Equatable {
    public let id: UUID
    public var uuid: UUID
    public var title: String
    public var path: String
    public var isModified: Bool

    /// The computed display title (filename, or "untitled" for unsaved).
    public var displayTitle: String {
        title.isEmpty ? "untitled" : title
    }

    /// Tooltip showing the full path.
    public var tooltip: String {
        path.isEmpty ? title : path
    }

    public init(uuid: UUID = UUID(), title: String, path: String = "", isModified: Bool = false) {
        self.id = uuid
        self.uuid = uuid
        self.title = title
        self.path = path
        self.isModified = isModified
    }
}

// MARK: - Tab Pasteboard Support

extension TabItem {
    static let pasteboardType = NSPasteboard.PasteboardType("com.wonky.works.myTextMate.tabItem")
}
