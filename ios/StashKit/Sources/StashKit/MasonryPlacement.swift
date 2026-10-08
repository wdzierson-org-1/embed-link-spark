import Foundation

/// Frames stay in input order, so view identity and accessibility order remain chronological.
public struct MasonryPlan: Equatable {
    public let frames: [CGRect]
    public let size: CGSize
    public let columnWidth: CGFloat
}

/// The web's fixed left-to-right placement (`src/utils/masonryPlacement.ts`), in native points.
/// Card index chooses its column; measured height changes only the next y in that column.
public enum MasonryPlacement {
    public static func plan(heights: [CGFloat], width: CGFloat, columns: Int,
                            columnGap: CGFloat = 12, rowGap: CGFloat = 16) -> MasonryPlan {
        let count = max(columns, 1)
        let width = width.isFinite ? max(0, width) : 0
        let gap = columnGap.isFinite ? max(0, columnGap) : 0
        let gutter = count > 1 ? min(gap, width / CGFloat(count - 1)) : 0
        let rowGap = rowGap.isFinite ? max(0, rowGap) : 0
        let columnWidth = max(0, (width - CGFloat(count - 1) * gutter) / CGFloat(count))
        let heights = heights.map { $0.isFinite ? max(1, ceil($0)) : 1 }
        var frames: [CGRect] = []
        frames.reserveCapacity(heights.count)
        var nextY = Array(repeating: CGFloat.zero, count: count)
        var contentHeight: CGFloat = 0
        for (index, height) in heights.enumerated() {
            let column = index % count
            let frame = CGRect(x: CGFloat(column) * (columnWidth + gutter), y: nextY[column],
                               width: columnWidth, height: height)
            frames.append(frame)
            nextY[column] = frame.maxY + rowGap
            contentHeight = max(contentHeight, frame.maxY)
        }
        return MasonryPlan(frames: frames, size: CGSize(width: width, height: contentHeight),
                           columnWidth: columnWidth)
    }
}
