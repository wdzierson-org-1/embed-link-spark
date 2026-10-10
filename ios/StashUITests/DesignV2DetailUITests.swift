import XCTest

/// Read-only acceptance against the review account's existing NASA link, seeded by
/// StoreScreenshotsUITests. Run on an isolated QA simulator with review credentials in
/// STASH_TEST_EMAIL / STASH_TEST_PASSWORD. No item is created, edited, shared or deleted.
/// The older fixture-account anatomy test remains independent and unchanged.
final class DesignV2DetailUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testReviewLinkOrderAndKeyboardDismissal() throws {
        let screens = A11yScreens(self)
        try screens.signIn()
        let app = screens.launch(.large, tab: .view)
        defer { app.terminate() }

        func element(_ identifier: String) -> XCUIElement {
            app.descendants(matching: .any).matching(identifier: identifier).firstMatch
        }

        let search = app.textFields["library.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 15))
        A11yScreens.tapUntilFocused(search)
        search.typeText("NASA")
        let card = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label CONTAINS[c] %@", "card.", "NASA"
        )).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 20),
                      "Expected the review account's existing NASA link; do not seed or modify another account")
        card.tap()
        XCTAssertTrue(app.buttons["detail.done"].waitForExistence(timeout: 10))

        let url = element("detail.urlBar")
        let title = element("detail.title")
        let description = element("detail.description")
        let summaryTab = app.buttons["Summary"]
        let originalTab = app.buttons["Original Content"]
        let summary = element("detail.summaryText")
        let notesHeading = element("detail.notes.heading")
        let notes = element("detail.notes.editor")
        let details = app.buttons["detail.details"]
        let sharing = element("detail.sharing")
        let autosave = element("detail.autosave")

        for required in [url, title, description, summaryTab, originalTab,
                         summary, notesHeading, notes, details, sharing, autosave] {
            XCTAssertTrue(required.waitForExistence(timeout: 10),
                          "Missing detail anatomy element: \(required.identifier)")
        }
        XCTAssertTrue(element("detail.urlText").label.contains("nasa.gov"))
        XCTAssertEqual(title.value as? String, "NASA")
        XCTAssertTrue(element("detail.eyebrow").label.lowercased().contains("nasa.gov"))
        XCTAssertEqual(autosave.label, "changes save automatically")
        XCTAssertFalse(element("detail.details.row.saved").exists,
                       "Details should retain its initially collapsed state")

        // These are the actual laid-out frames in one scroll position, including content
        // below the viewport. Checking order catches a source/notes swap, unlike presence
        // assertions or separate screenshots of each section.
        assertAbove(url, title, "URL must precede title")
        assertAbove(title, description, "Title must precede description")
        let hero = element("detail.heroImage")
        if hero.exists {
            assertAbove(description, hero, "Description must precede media")
            assertAbove(hero, summaryTab, "Media must precede source tabs")
        } else {
            assertAbove(description, summaryTab, "Description must precede source tabs")
        }
        assertAbove(summaryTab, summary, "The selected source must follow its tabs")
        assertAbove(summary, notesHeading, "Source must precede notes")
        assertAbove(notesHeading, notes, "The notes heading must precede its editor")
        assertAbove(notes, details, "Notes must precede Details")
        assertAbove(details, sharing, "Details must precede Sharing")
        screens.attachScreenshot(named: "detail")

        // Focus only: the existing item is never changed. Check both a top field and the
        // notes field below the source; the pinned footer must dismiss either keyboard.
        A11yScreens.scrollIntoView(app, title)
        let initialTitle = title.value as? String
        assertKeyboardDismisses(app, field: title)
        XCTAssertEqual(title.value as? String, initialTitle)

        A11yScreens.scrollIntoView(app, notes)
        let initialNotes = notes.value as? String
        assertKeyboardDismisses(app, field: notes)
        XCTAssertEqual(notes.value as? String, initialNotes)

        // Changing source tabs and expanding the facts drawer are local presentation state.
        // Verify that original content still sits ahead of Notes after the tab changes.
        A11yScreens.scrollIntoView(app, originalTab)
        originalTab.tap()
        let original = element("detail.originalText")
        XCTAssertTrue(original.waitForExistence(timeout: 15))
        assertAbove(originalTab, original, "Original content must follow the source tabs")
        assertAbove(original, notesHeading, "Original content must also precede notes")
        summaryTab.tap()
        XCTAssertTrue(summary.waitForExistence(timeout: 5))

        A11yScreens.scrollIntoView(app, details)
        details.tap()
        let saved = element("detail.details.row.saved")
        XCTAssertTrue(saved.waitForExistence(timeout: 5))
        assertAbove(notes, details, "Expanded Details must remain after notes")
        assertAbove(details, saved, "Saved facts must follow the Details header")
        assertAbove(saved, sharing, "Sharing must remain after the expanded facts")
        A11yScreens.scrollIntoView(app, sharing)
        screens.attachScreenshot(named: "detail-notes-facts-sharing")

        app.buttons["detail.done"].tap()
        XCTAssertTrue(search.waitForExistence(timeout: 10))
    }

    @MainActor
    private func assertAbove(_ first: XCUIElement, _ second: XCUIElement, _ message: String,
                             file: StaticString = #filePath, line: UInt = #line) {
        let firstFrame = first.frame
        let secondFrame = second.frame
        XCTAssertGreaterThan(firstFrame.height, 0, "First element needs a real frame", file: file, line: line)
        XCTAssertGreaterThan(secondFrame.height, 0, "Second element needs a real frame", file: file, line: line)
        XCTAssertLessThanOrEqual(firstFrame.maxY, secondFrame.minY + 2,
                                 message, file: file, line: line)
    }

    @MainActor
    private func assertKeyboardDismisses(_ app: XCUIApplication, field: XCUIElement,
                                         file: StaticString = #filePath, line: UInt = #line) {
        A11yScreens.tapUntilFocused(field)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5),
                      "Focusing the field should show the keyboard", file: file, line: line)
        let dismiss = app.buttons["detail.dismissKeyboard"]
        XCTAssertTrue(dismiss.waitForExistence(timeout: 5), file: file, line: line)
        XCTAssertTrue(dismiss.isHittable, "Pinned dismissal must stay reachable", file: file, line: line)
        dismiss.tap()
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            !app.keyboards.firstMatch.exists && !dismiss.exists
        }, object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 10), .completed,
                       "The keyboard and its dismissal control must disappear", file: file, line: line)
    }
}
