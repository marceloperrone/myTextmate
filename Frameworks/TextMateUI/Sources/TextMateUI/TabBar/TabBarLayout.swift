import SwiftUI

// MARK: - Tab Bar Layout

/// Custom Layout that distributes tab widths using the same algorithm
/// as OakTabBarView's makeLayoutForTabItems:inRectOfWidth:.
///
/// Algorithm:
/// 1. Compute each tab's ideal width based on title text.
/// 2. If total fits in available space, use ideal widths (capped at maxWidth).
/// 3. Otherwise, compress proportionally, clamped between minWidth and maxWidth.
/// 4. If tabs still overflow, hide excess and show overflow indicator on last visible tab.
public struct TabBarLayout: Layout {
    public let minTabWidth: CGFloat
    public let maxTabWidth: CGFloat

    public init(minTabWidth: CGFloat = 120, maxTabWidth: CGFloat = 250) {
        self.minTabWidth = minTabWidth
        self.maxTabWidth = maxTabWidth
    }

    public struct CacheData {
        var widths: [CGFloat] = []
        var visibleCount: Int = 0
    }

    public func makeCache(subviews: Subviews) -> CacheData {
        CacheData()
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout CacheData) -> CGSize {
        let availableWidth = proposal.width ?? 800
        let height = subviews.first.map { $0.sizeThatFits(.unspecified).height } ?? 28

        cache = computeLayout(subviews: subviews, availableWidth: availableWidth)

        return CGSize(width: availableWidth, height: height)
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout CacheData) {
        var x = bounds.minX

        for (index, subview) in subviews.enumerated() {
            guard index < cache.visibleCount else {
                // Hide overflow tabs by placing them off-screen
                subview.place(at: CGPoint(x: -10000, y: bounds.minY),
                              proposal: ProposedViewSize(width: 0, height: bounds.height))
                continue
            }

            let width = cache.widths[index]
            subview.place(
                at: CGPoint(x: x, y: bounds.minY),
                proposal: ProposedViewSize(width: width, height: bounds.height)
            )
            x += width
        }
    }

    // MARK: - Layout Algorithm

    private func computeLayout(subviews: Subviews, availableWidth: CGFloat) -> CacheData {
        guard !subviews.isEmpty else { return CacheData() }

        // Step 1: Compute ideal (fitting) widths
        let idealWidths = subviews.map { subview in
            min(max(subview.sizeThatFits(.unspecified).width, minTabWidth), maxTabWidth)
        }

        let totalIdeal = idealWidths.reduce(0, +)

        // Step 2: If everything fits, use ideal widths
        if totalIdeal <= availableWidth {
            return CacheData(widths: idealWidths, visibleCount: subviews.count)
        }

        // Step 3: Compress proportionally
        let ratio = availableWidth / totalIdeal
        var widths = idealWidths.map { width in
            max(width * ratio, minTabWidth)
        }

        // Step 4: Check if we need overflow
        let totalCompressed = widths.reduce(0, +)
        if totalCompressed <= availableWidth {
            return CacheData(widths: widths, visibleCount: subviews.count)
        }

        // Step 5: Determine visible count
        var accumulated: CGFloat = 0
        var visibleCount = 0
        for width in widths {
            if accumulated + width > availableWidth {
                break
            }
            accumulated += width
            visibleCount += 1
        }

        visibleCount = max(visibleCount, 1)

        // Redistribute available width among visible tabs
        let visibleWidth = availableWidth / CGFloat(visibleCount)
        for i in 0..<visibleCount {
            widths[i] = max(visibleWidth, minTabWidth)
        }

        return CacheData(widths: widths, visibleCount: visibleCount)
    }
}
