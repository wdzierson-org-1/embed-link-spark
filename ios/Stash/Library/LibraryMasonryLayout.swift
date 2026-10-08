import SwiftUI
import StashKit

/// Fixed left-to-right masonry, matching the web library. One chronological list of subviews
/// keeps card identity intact; each measured height advances only its assigned column.
/// Measurement happens synchronously before placement, so no first-frame estimates overlap.
struct LibraryMasonryLayout: Layout {
    var columns: Int
    var columnGap: CGFloat = 12
    var rowGap: CGFloat = 16

    struct Cache {
        var plan: MasonryPlan?
    }

    func makeCache(subviews: Subviews) -> Cache { Cache() }

    func updateCache(_ cache: inout Cache, subviews: Subviews) {
        // A title, note, loaded hero, or Dynamic Type change may alter a card's height even when
        // its ID is unchanged. Never reuse measurements across a subview update.
        cache.plan = nil
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        let plan = measure(width: resolvedWidth(proposal, subviews: subviews), subviews: subviews)
        cache.plan = plan
        return plan.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        let plan: MasonryPlan
        if let measured = cache.plan, measured.size.width == bounds.width,
           measured.frames.count == subviews.count {
            plan = measured
        } else {
            plan = measure(width: bounds.width, subviews: subviews)
            cache.plan = plan
        }
        for (index, frame) in plan.frames.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                                 anchor: .topLeading,
                                 proposal: ProposedViewSize(width: frame.width, height: nil))
        }
    }

    private func measure(width: CGFloat, subviews: Subviews) -> MasonryPlan {
        let columnWidth = MasonryPlacement.plan(heights: [], width: width, columns: columns,
                                                columnGap: columnGap, rowGap: rowGap).columnWidth
        let proposal = ProposedViewSize(width: columnWidth, height: nil)
        let heights = subviews.map { $0.sizeThatFits(proposal).height }
        return MasonryPlacement.plan(heights: heights, width: width, columns: columns,
                                     columnGap: columnGap, rowGap: rowGap)
    }

    private func resolvedWidth(_ proposal: ProposedViewSize, subviews: Subviews) -> CGFloat {
        if let width = proposal.width, width.isFinite { return max(0, width) }
        // SwiftUI can ask for an ideal size before providing the scroll view's finite width.
        // This branch is only an ideal-size answer; placement always remeasures the real width.
        let ideal = subviews.map { $0.sizeThatFits(.unspecified).width }
            .filter { $0.isFinite }.max() ?? 0
        return max(0, ideal) * CGFloat(max(columns, 1)) + max(0, columnGap) * CGFloat(max(columns - 1, 0))
    }
}
