import XCTest
@testable import StashKit

final class MasonryPlacementTests: XCTestCase {
    func testNewestToOldestAlternatesLeftToRightWithoutChoosingShortestColumn() {
        let plan = MasonryPlacement.plan(heights: [300, 40, 80, 60, 30], width: 332, columns: 2)

        // Card 3 belongs under the tall first card, even though the right column is shorter.
        XCTAssertEqual(plan.frames, [
            CGRect(x: 0, y: 0, width: 160, height: 300),
            CGRect(x: 172, y: 0, width: 160, height: 40),
            CGRect(x: 0, y: 316, width: 160, height: 80),
            CGRect(x: 172, y: 56, width: 160, height: 60),
            CGRect(x: 0, y: 412, width: 160, height: 30)
        ])
        XCTAssertEqual(plan.size, CGSize(width: 332, height: 442))
    }

    func testChangingAHeightMovesOnlyLaterCardsInThatColumn() {
        let before = MasonryPlacement.plan(heights: [80, 100, 50, 60], width: 332, columns: 2)
        let after = MasonryPlacement.plan(heights: [180, 100, 50, 60], width: 332, columns: 2)

        XCTAssertEqual(after.frames[1], before.frames[1])
        XCTAssertEqual(after.frames[3], before.frames[3])
        XCTAssertEqual(after.frames[2].minY, before.frames[2].minY + 100)
        XCTAssertEqual(after.frames.map(\.minX), before.frames.map(\.minX))
    }

    func testAppendingAPagePreservesAllExistingCardFrames() {
        let before = MasonryPlacement.plan(heights: [100, 50, 70], width: 332, columns: 2)
        let after = MasonryPlacement.plan(heights: [100, 50, 70, 200, 40], width: 332, columns: 2)

        XCTAssertEqual(Array(after.frames.prefix(3)), before.frames)
        XCTAssertEqual(after.frames[3].origin, CGPoint(x: 172, y: 66))
        XCTAssertEqual(after.frames[4].origin, CGPoint(x: 0, y: 202))
        XCTAssertEqual(after.size.height, 266)
    }

    func testAccessibilitySingleColumnKeepsChronologyAndHasNoTrailingGap() {
        let plan = MasonryPlacement.plan(heights: [100, 50, 75], width: 343, columns: 1)

        XCTAssertEqual(plan.frames.map(\.origin), [CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 116), CGPoint(x: 0, y: 182)])
        XCTAssertEqual(plan.frames.map(\.width), [343, 343, 343])
        XCTAssertEqual(plan.size.height, 257)
    }

    func testWidthChangesResizeColumnsWithoutChangingAssignment() {
        let narrow = MasonryPlacement.plan(heights: [100, 50, 80], width: 332, columns: 2)
        let wide = MasonryPlacement.plan(heights: [100, 50, 80], width: 412, columns: 2)

        XCTAssertEqual(wide.columnWidth, 200)
        XCTAssertEqual(wide.frames.map(\.minX), [0, 212, 0])
        XCTAssertEqual(wide.frames.map(\.minY), narrow.frames.map(\.minY))
    }

    func testEmptyAndSingleSaveReserveOnlyTheirOwnHeight() {
        let empty = MasonryPlacement.plan(heights: [], width: 332, columns: 2)
        XCTAssertEqual(empty.frames, [])
        XCTAssertEqual(empty.size, CGSize(width: 332, height: 0))

        let single = MasonryPlacement.plan(heights: [41], width: 332, columns: 2)
        XCTAssertEqual(single.frames, [CGRect(x: 0, y: 0, width: 160, height: 41)])
        XCTAssertEqual(single.size.height, 41)
    }

    func testFractionalHeightsRoundUpSoTheNextCardNeverOverlaps() {
        let plan = MasonryPlacement.plan(heights: [100.2, 20.1, 40.9, 30.8], width: 331, columns: 2)

        XCTAssertEqual(plan.frames.map(\.height), [101, 21, 41, 31])
        XCTAssertEqual(plan.frames[2].minY, 117)
        XCTAssertEqual(plan.frames[3].minY, 37)
        XCTAssertEqual(plan.frames[2].minY - plan.frames[0].maxY, 16)
    }

    func testInvalidMeasurementsAndNarrowProposalsProduceFiniteNonnegativeFrames() {
        let invalid = MasonryPlacement.plan(heights: [0, -10, .nan, .infinity], width: 10,
                                            columns: 2, columnGap: 12, rowGap: -4)
        XCTAssertEqual(invalid.frames.map(\.height), [1, 1, 1, 1])
        XCTAssertTrue(invalid.frames.allSatisfy { $0.minX >= 0 && $0.maxX <= 10 && $0.minY >= 0 })
        XCTAssertEqual(invalid.size.height, 2)

        let zeroColumns = MasonryPlacement.plan(heights: [20, 30], width: .infinity, columns: 0)
        XCTAssertEqual(zeroColumns.columnWidth, 0)
        XCTAssertEqual(zeroColumns.frames.map(\.minX), [0, 0])
        XCTAssertEqual(zeroColumns.size, CGSize(width: 0, height: 66))
    }
}
