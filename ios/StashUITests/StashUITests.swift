import XCTest

/// Drives the real sign-in screen against production Supabase (test account creds are
/// injected via TEST_RUNNER_ environment variables, never hardcoded). Covers both the
/// wrong-password error path and the successful sign-in path in one launch so the two
/// scenarios can't drift out of order across reruns.
final class StashUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testWrongPasswordShowsErrorThenCorrectPasswordSignsIn() throws {
        guard
            let email = ProcessInfo.processInfo.environment["STASH_TEST_EMAIL"],
            let password = ProcessInfo.processInfo.environment["STASH_TEST_PASSWORD"],
            !email.isEmpty, !password.isEmpty
        else {
            XCTFail("STASH_TEST_EMAIL / STASH_TEST_PASSWORD were not set in the test runner environment")
            return
        }

        let app = XCUIApplication()
        // Without this, a second consecutive run against the same simulator finds a
        // Keychain session already persisted from the first run's successful sign-in
        // (uninstall/reinstall doesn't clear it — see task-8-report.md Adaptation #5),
        // so the app launches straight into MainTabView, "signin.email" never appears,
        // and the test fails on a timeout that looks like a regression but is stale state.
        app.launchArguments = ["--uitest-reset-auth"]
        app.launch()

        let emailField = app.textFields["signin.email"]
        let passwordField = app.secureTextFields["signin.password"]
        let submitButton = app.buttons["signin.submit"]

        XCTAssertTrue(emailField.waitForExistence(timeout: 10), "Sign-in email field did not appear")

        emailField.tap()
        emailField.typeText(email)

        let wrongPassword = "wrong-\(password)"
        passwordField.tap()
        passwordField.typeText(wrongPassword)

        submitButton.tap()

        let errorText = app.staticTexts["signin.error"]
        XCTAssertTrue(
            errorText.waitForExistence(timeout: 10),
            "Expected an error message after signing in with the wrong password"
        )

        // Replace the wrong password with the correct one (secure fields don't support
        // reliable select-all-via-gesture in XCUITest, so backspace it out by length instead).
        passwordField.tap()
        passwordField.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: wrongPassword.count))
        passwordField.typeText(password)

        submitButton.tap()

        let viewTab = app.tabBars.buttons["View"]
        XCTAssertTrue(
            viewTab.waitForExistence(timeout: 15),
            "Expected the tab bar (View tab) to appear after signing in with correct credentials"
        )
    }

    /// Env-sourced test creds, shared by the two tests below (the wrong-password test above
    /// keeps its own inline guard — untouched, already proven).
    private func testCredentials() throws -> (email: String, password: String) {
        guard
            let email = ProcessInfo.processInfo.environment["STASH_TEST_EMAIL"],
            let password = ProcessInfo.processInfo.environment["STASH_TEST_PASSWORD"],
            !email.isEmpty, !password.isEmpty
        else {
            XCTFail("STASH_TEST_EMAIL / STASH_TEST_PASSWORD were not set in the test runner environment")
            throw XCTSkip("missing test credentials")
        }
        return (email, password)
    }

    /// Happy-path sign-in, reused by tests that don't need the wrong-password detour.
    @discardableResult
    private func signInAndReachLibrary(_ app: XCUIApplication, email: String, password: String) -> Bool {
        app.launchArguments = ["--uitest-reset-auth"]
        app.launch()
        let emailField = app.textFields["signin.email"]
        guard emailField.waitForExistence(timeout: 10) else { return false }
        emailField.tap()
        emailField.typeText(email)
        let passwordField = app.secureTextFields["signin.password"]
        passwordField.tap()
        passwordField.typeText(password)
        app.buttons["signin.submit"].tap()
        let viewTab = app.tabBars.buttons["View"]
        let reached = viewTab.waitForExistence(timeout: 15)
        if reached { viewTab.tap() }
        return reached
    }

    /// Signs into the real View tab and exercises the grid, type chip, search, and sign-out
    /// against production data. Element types for custom-identifier views (grid/cards) are
    /// looked up type-agnostically since SwiftUI doesn't guarantee a stable XCUIElementType
    /// for arbitrary containers the way it does for Button/TextField.
    func testLibrarySmoke() throws {
        let (email, password) = try testCredentials()
        let app = XCUIApplication()

        func anyElement(_ identifier: String) -> XCUIElement {
            app.descendants(matching: .any)[identifier]
        }

        XCTAssertTrue(signInAndReachLibrary(app, email: email, password: password),
                      "Expected the tab bar to appear after sign-in")

        // 1. Grid shows at least one real item card.
        XCTAssertTrue(anyElement("library.grid").waitForExistence(timeout: 15), "Library grid did not appear")
        XCTAssertTrue(anyElement("card.0").waitForExistence(timeout: 15), "Expected at least one item card in the grid")

        // 2. Type chip narrows server-side; the test account has link items.
        let linksChip = app.buttons["library.chip.links"]
        XCTAssertTrue(linksChip.waitForExistence(timeout: 5), "Links chip not found")
        linksChip.tap()
        XCTAssertTrue(anyElement("card.0").waitForExistence(timeout: 15), "Expected at least one Links card")

        // 3. Local search narrows to nothing for an unmatchable query, then clears back.
        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 5), "Search field not found")
        searchField.tap()
        let needle = "zzzunmatchablezzz"
        searchField.typeText(needle)
        XCTAssertTrue(anyElement("library.empty").waitForExistence(timeout: 10), "Expected an empty state for an unmatchable search")
        XCTAssertFalse(anyElement("card.0").exists, "No cards should be visible for an unmatchable search")

        searchField.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: needle.count))
        XCTAssertTrue(anyElement("card.0").waitForExistence(timeout: 15), "Expected cards to return after clearing the search")

        // 4. Sign out via the avatar menu returns to the sign-in screen.
        app.buttons["library.menu"].tap()
        let signOutById = app.buttons["library.signOut"]
        let signOutButton = signOutById.waitForExistence(timeout: 3) ? signOutById : app.buttons["Sign Out"]
        XCTAssertTrue(signOutButton.waitForExistence(timeout: 5), "Sign Out menu item not found")
        signOutButton.tap()

        XCTAssertTrue(app.textFields["signin.email"].waitForExistence(timeout: 10), "Expected the sign-in screen after signing out")
    }

    /// Opens the tag-filter sheet — independent of item-count data, so it stays meaningful
    /// even when the account has no items. Also the screenshot rig for task-10-report.md's
    /// required tag-filter-sheet capture: sleeps briefly post-presentation so an external
    /// `xcrun simctl io <udid> screenshot` can capture it mid-test.
    func testTagFilterSheetOpens() throws {
        let (email, password) = try testCredentials()
        let app = XCUIApplication()
        XCTAssertTrue(signInAndReachLibrary(app, email: email, password: password),
                      "Expected the tab bar to appear after sign-in")

        let tagButton = app.buttons["library.tagFilterButton"]
        XCTAssertTrue(tagButton.waitForExistence(timeout: 15), "Tag filter button did not appear")
        tagButton.tap()

        XCTAssertTrue(app.buttons["tagfilter.done"].waitForExistence(timeout: 10), "Tag filter sheet did not present")
        sleep(3)
    }
}
