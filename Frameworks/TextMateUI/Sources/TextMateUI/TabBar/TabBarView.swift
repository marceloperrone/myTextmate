import SwiftUI

// MARK: - Tab Bar View

/// SwiftUI replacement for OakTabBarView.mm.
/// Renders tabs in the window titlebar via NSTitlebarAccessoryViewController.
/// Uses native macOS materials and shapes for a system-native appearance.
public struct TabBarView: View {
    @Bindable var model: TabBarModel
    @State private var draggedTab: TabItem?
    @State private var hoveredTabID: UUID?

    public init(model: TabBarModel) {
        self.model = model
    }

    public var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(model.tabs.enumerated()), id: \.element.id) { index, tab in
                TabItemView(
                    tab: tab,
                    isSelected: index == model.selectedIndex,
                    isHovered: hoveredTabID == tab.id,
                    onSelect: { model.selectTab(at: index) },
                    onClose: { model.closeTab(at: index) },
                    onDoubleClick: { model.doubleClickTab(at: index) }
                )
                .onHover { isHovered in
                    hoveredTabID = isHovered ? tab.id : nil
                }
                .contextMenu(forIndex: index, model: model)
                .draggable(tab.uuid.uuidString) {
                    TabDragPreview(title: tab.displayTitle)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .gesture(
            TapGesture(count: 2).onEnded {
                model.doubleClickBackground()
            }
        )
        .contextMenu(forIndex: -1, model: model)
        .dropDestination(for: String.self) { items, location in
            handleDrop(items: items, at: location)
        }
    }

    // MARK: - Drop Handling

    private func handleDrop(items: [String], at location: CGPoint) -> Bool {
        guard let uuidString = items.first, let uuid = UUID(uuidString: uuidString) else { return false }
        let targetIndex = model.tabs.count
        return model.onDropFromOtherTabBar?(uuid, targetIndex, .move) ?? false
    }
}

// MARK: - Context Menu Modifier

private struct TabContextMenu: ViewModifier {
    let index: Int
    let model: TabBarModel

    func body(content: Content) -> some View {
        content.overlay {
            TabContextMenuHelper(index: index, model: model)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
        }
    }
}

private struct TabContextMenuHelper: NSViewRepresentable {
    let index: Int
    let model: TabBarModel

    func makeNSView(context: Context) -> TabContextMenuNSView {
        let view = TabContextMenuNSView()
        view.index = index
        view.model = model
        return view
    }

    func updateNSView(_ nsView: TabContextMenuNSView, context: Context) {
        nsView.index = index
        nsView.model = model
    }
}

private class TabContextMenuNSView: NSView {
    var index: Int = -1
    weak var model: TabBarModel?

    override func menu(for event: NSEvent) -> NSMenu? {
        model?.contextMenu(forIndex: index)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let event = NSApp.currentEvent, event.type == .rightMouseDown else {
            return nil
        }
        return frame.contains(point) ? self : nil
    }

    override var acceptsFirstResponder: Bool { false }
}

private extension View {
    func contextMenu(forIndex index: Int, model: TabBarModel) -> some View {
        modifier(TabContextMenu(index: index, model: model))
    }
}

// MARK: - Individual Tab View

private struct TabItemView: View {
    let tab: TabItem
    let isSelected: Bool
    let isHovered: Bool
    var onSelect: () -> Void
    var onClose: () -> Void
    var onDoubleClick: () -> Void

    private let cornerRadius: CGFloat = 6

    var body: some View {
        HStack(spacing: 6) {
            // Close / modified indicator
            closeOrModifiedIndicator

            // Tab icon
            if !tab.path.isEmpty {
                Image(nsImage: NSWorkspace.shared.icon(forFile: tab.path))
                    .resizable()
                    .frame(width: 16, height: 16)
            }

            // Title
            Text(tab.displayTitle)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(isSelected ? .primary : .secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background { tabBackground }
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius))
        .onTapGesture(count: 2, perform: onDoubleClick)
        .onTapGesture(count: 1, perform: onSelect)
        .help(tab.tooltip)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
        .animation(.easeInOut(duration: 0.1), value: isHovered)
    }

    // MARK: - Close / Modified

    @ViewBuilder
    private var closeOrModifiedIndicator: some View {
        if tab.isModified && !isHovered {
            Circle()
                .fill(Color(nsColor: .controlAccentColor))
                .frame(width: 7, height: 7)
                .frame(width: 18, height: 18)
        } else if isHovered {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
        } else {
            Color.clear
                .frame(width: 0, height: 18)
        }
    }

    // MARK: - Background

    @ViewBuilder
    private var tabBackground: some View {
        if isSelected {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.12), radius: 1, y: 0.5)
        } else if isHovered {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(.ultraThinMaterial)
        } else {
            Color.clear
        }
    }
}

// MARK: - Drag Preview

private struct TabDragPreview: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 12))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
    }
}
