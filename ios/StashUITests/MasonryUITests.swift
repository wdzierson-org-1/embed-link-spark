import XCTest

/// Read-only geometry acceptance against the review account's existing mixed-height saves.
/// No item is created, edited or deleted. Pure placement edge cases live in StashKit tests.
final class MasonryUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testColumnsPackIndependentlyInChronologicalOrder() throws {
        let screens = A11yScreens(self)
        try screens.signIn()
        let app = screens.launch(.large, tab: .view)
        let cards = (0..<6).map { app.buttons["card.\($0)"] }
        for card in cards {
            XCTAssertTrue(card.waitForExistence(timeout: 20), "This acceptance requires six existing mixed-height saves")
        }
        // A loaded cover can change a card's height. Wait for the actual card frames to settle
        // into their column packing instead of validating a transient image-loading layout.
        let packed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let frames = cards.map(\.frame)
            guard frames.allSatisfy({ $0.width > 0 && $0.height > 0 }) else { return false }
            return (2..<frames.count).allSatisfy {
                abs(frames[$0].minY - frames[$0 - 2].maxY - 16) <= 2
            }
        }, object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [packed], timeout: 12), .completed)

        let frames = cards.map(\.frame)
        XCTAssertLessThan(frames[0].minX, frames[1].minX)
        XCTAssertEqual(frames[0].minY, frames[1].minY, accuracy: 2)
        for index in frames.indices {
            XCTAssertEqual(frames[index].minX, frames[index % 2].minX, accuracy: 1,
                           "Card \(index) must keep its fixed left-to-right column")
            XCTAssertEqual(frames[index].width, frames[0].width, accuracy: 1)
        }
        let closedAGap = (2..<frames.count).contains { index in
            let previousRowStart = (index / 2 - 1) * 2
            let rowBottom = max(frames[previousRowStart].maxY, frames[previousRowStart + 1].maxY)
            return frames[index].minY < rowBottom + 14
        }
        XCTAssertTrue(closedAGap, "Mixed-height cards must close a gap that the old equal-row grid left")
        screens.attachScreenshot(named: "masonry-two-columns")

        // The layout must retain the card's whole-surface tap and existing detail presentation.
        cards[0].tap()
        XCTAssertTrue(app.buttons["detail.done"].waitForExistence(timeout: 10))
        app.buttons["detail.done"].tap()
        app.terminate()
    }

    @MainActor
    func testAccessibilityTextUsesOneChronologicalColumn() throws {
        let screens = A11yScreens(self)
        try screens.signIn()
        let app = screens.launch(.ax3, tab: .view)
        let cards = (0..<3).map { app.buttons["card.\($0)"] }
        for card in cards { XCTAssertTrue(card.waitForExistence(timeout: 20)) }
        let frames = cards.map(\.frame)
        for index in 1..<frames.count {
            XCTAssertEqual(frames[index].minX, frames[0].minX, accuracy: 1)
            XCTAssertEqual(frames[index].width, frames[0].width, accuracy: 1)
            XCTAssertEqual(frames[index].minY, frames[index - 1].maxY + 16, accuracy: 2)
        }
        XCTAssertGreaterThan(frames[0].width, app.windows.firstMatch.frame.width * 0.8)
        screens.attachScreenshot(named: "masonry-accessibility-column")
        app.terminate()
    }
}
