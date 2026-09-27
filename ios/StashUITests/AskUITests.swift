import XCTest

/// Plan 15 Task 6A (Ask tune-up): checks that need no live answer. The standing `will+uitest`
/// account is subscription-lapsed, so Ask sends are blocked client-side by the gate — which is
/// exactly what keeps the banner test below from ever requesting a model answer (it skips itself
/// if the account is not gated).
///
/// A standalone file (`StashUITests.swift` belongs to another task this round), so it carries its
/// own small sign-in helper — the same recipe as `StashUITests.signInAndReachLibrary`.
final class AskUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// M11: Ask is retrieval-only on every platform — the composer shows the web mole's
    /// placeholder and no longer advertises "paste a link / 'remember:' to save".
    func testAskComposerIsRetrievalOnly() throws {
        let app = XCUIApplication()
        try signIn(app)
        app.tabBars.buttons["Ask"].tap()

        let input = element(app, "ask.input")
        XCTAssertTrue(input.waitForExistence(timeout: 10), "Ask input field did not appear")
        // A vertical-axis SwiftUI TextField can surface its placeholder as `placeholderValue` or,
        // while empty, as its `value` — accept either, but it must be the new copy.
        let shown = [input.placeholderValue, input.value as? String, input.label].compactMap { $0 }
        XCTAssertTrue(shown.contains("Ask your stash…"), "Expected the 'Ask your stash…' placeholder, got \(shown)")
        XCTAssertFalse(shown.contains { $0.contains("remember:") || $0.contains("paste a link") },
                       "The retired capture hint must be gone, got \(shown)")
    }

    /// L2: an Ask error banner dismisses on tap, and a later send re-evaluates (the gate banner
    /// comes back). Uses the client-side subscription gate as the banner source, probed on the
    /// Add tab first so no live answer is ever requested.
    func testAskBannerDismissesOnTap() throws {
        let app = XCUIApplication()
        try signIn(app)
        // Add is the landing tab; its gate line means `canUseAI` is false too (same boolean).
        guard element(app, "capture.subscriptionGate").waitForExistence(timeout: 15) else {
            throw XCTSkip("Test account isn't subscription-gated — skipping so no live Ask answer is requested")
        }
        app.tabBars.buttons["Ask"].tap()

        let input = element(app, "ask.input")
        XCTAssertTrue(input.waitForExistence(timeout: 10), "Ask input field did not appear")
        input.tap()
        input.typeText("UI test: banner dismissal")
        let send = app.buttons["ask.send"]
        XCTAssertTrue(send.waitForExistence(timeout: 5), "Send button not found")
        send.tap()

        let banner = element(app, "ask.gateError")
        XCTAssertTrue(banner.waitForExistence(timeout: 5), "Expected the subscription gate banner")
        banner.tap()
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: banner)
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 5), .completed, "Tapping the banner should dismiss it")

        // A gate block keeps the typed text, so Send is still live: sending again re-evaluates.
        send.tap()
        XCTAssertTrue(banner.waitForExistence(timeout: 5), "Expected the banner back on the next blocked send")
    }

    // MARK: - Helpers

    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    /// `--uitest-reset-auth` forces the real sign-in screen (the Keychain session survives
    /// reinstalls on the Simulator) and marks the one-time onboarding panel as seen.
    private func signIn(_ app: XCUIApplication) throws {
        let environment = ProcessInfo.processInfo.environment
        guard let email = environment["STASH_TEST_EMAIL"], let password = environment["STASH_TEST_PASSWORD"],
              !email.isEmpty, !password.isEmpty
        else {
            XCTFail("STASH_TEST_EMAIL / STASH_TEST_PASSWORD were not set in the test runner environment")
            throw XCTSkip("missing test credentials")
        }
        app.launchArguments = ["--uitest-reset-auth"]
        app.launch()
        let emailField = app.textFields["signin.email"]
        XCTAssertTrue(emailField.waitForExistence(timeout: 10), "Sign-in email field did not appear")
        emailField.tap()
        emailField.typeText(email)
        let passwordField = app.secureTextFields["signin.password"]
        passwordField.tap()
        passwordField.typeText(password)
        app.buttons["signin.submit"].tap()
        XCTAssertTrue(app.tabBars.buttons["Ask"].waitForExistence(timeout: 15), "Expected the tab bar after sign-in")
    }
}
