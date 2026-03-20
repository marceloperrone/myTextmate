import SwiftUI

// MARK: - File Item Row

/// Custom row view for file browser items, replacing FileItemTableCellView.
public struct FileItemRow: View {
    let item: FileItemWrapper
    let isSelected: Bool

    @State private var isHovered = false

    public init(item: FileItemWrapper, isSelected: Bool = false) {
        self.item = item
        self.isSelected = isSelected
    }

    public var body: some View {
        HStack(spacing: 6) {
            // File/folder icon
            Image(nsImage: item.icon)
                .resizable()
                .frame(width: 16, height: 16)

            // Display name
            Text(item.displayName)
                .font(.system(size: 13))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(isSelected ? .white : .primary)

            Spacer()

            // Finder tags
            if !item.finderTags.isEmpty {
                HStack(spacing: 2) {
                    ForEach(item.finderTags.prefix(3)) { tag in
                        Circle()
                            .fill(tag.color)
                            .frame(width: 8, height: 8)
                    }
                }
            }

            // Symbolic link indicator
            if item.isSymbolicLink {
                Image(systemName: "arrow.turn.right.up")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 1)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }
}
