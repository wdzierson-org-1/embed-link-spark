import XCTest

/// Plan 15 Task 6A (Ask tune-up): checks that need no live answer. The standing `will+uitest`
/// account is subscription-lapsed, so Ask sends are blocked client-side by the gate — which is
/// exactly what keeps the banner test below from ever requesting a model answer (it skips itself
/// if the account is not gated). The follow-scroll test streams a local scripted answer instead
/// (`--uitest-scripted-chat`), so it never reaches the server either.
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

    /// M2 review fix, verified on the iOS 17 floor: the thread follows a streaming answer until
    /// the USER drags it away, and a new send follows again. `--uitest-scripted-chat` swaps in a
    /// local scripted stream (status frames, then ~60 list lines over ~6 s including two
    /// ten-bullet bursts in single deltas) with in-memory history — nothing reaches the server,
    /// so this runs on the gate-blocked account without creating conversations.
    ///
    /// Thread rows are `[q1, a1, q2, a2, q3, a3]`, so the answers are bubbles 1, 3 and 5. An
    /// answer has started once its read-aloud button exists (content arrived) and has finished
    /// once `ask.newChat` is enabled again (disabled exactly while an answer streams) — a signal
    /// that doesn't depend on where the thread is scrolled; an answer's own thumbs can be
    /// scrolled out of the lazily built thread.
    func testThreadFollowsTheStreamUntilTheUserScrollsAway() throws {
        let app = XCUIApplication()
        try signIn(app, extraLaunchArguments: ["--uitest-scripted-chat"])
        app.tabBars.buttons["Ask"].tap()

        let input = element(app, "ask.input")
        XCTAssertTrue(input.waitForExistence(timeout: 10), "Ask input field did not appear")
        let thread = app.scrollViews["ask.thread"]
        XCTAssertTrue(thread.waitForExistence(timeout: 5), "Ask thread did not appear")
        let newChat = app.buttons["ask.newChat"]

        // (a) Send and keep hands off: the view keeps up with every burst and settles on the
        // finished answer's last line and actions row.
        ask(app, "Scripted question one")
        XCTAssertTrue(element(app, "ask.bubble.1.speak").waitForExistence(timeout: 10), "Answer 1 never started")
        XCTAssertTrue(waitUntilEnabled(newChat, timeout: 20), "Answer 1 never completed")
        sleep(1)
        XCTAssertTrue(isVisible(lastLine(app, "Scripted question one"), in: thread),
                      "Following: answer 1's last line should be on screen when it completes")
        XCTAssertTrue(isVisible(element(app, "ask.bubble.1.thumbsUp"), in: thread),
                      "Following: answer 1's actions row should be on screen when it completes")

        // (b) Send, then drag the thread up while the answer is still streaming: it must stay
        // where the user put it — no yank back down, not even the settle scroll at completion.
        ask(app, "Scripted question two")
        XCTAssertTrue(element(app, "ask.bubble.3.speak").waitForExistence(timeout: 10), "Answer 2 never started")
        sleep(2)   // a couple of screens of answer 2 have streamed in
        XCTAssertFalse(newChat.isEnabled, "The drag must happen mid-stream")
        thread.swipeDown()
        XCTAssertTrue(waitUntilEnabled(newChat, timeout: 20), "Answer 2 never completed")
        sleep(1)
        XCTAssertFalse(isVisible(lastLine(app, "Scripted question two"), in: thread),
                       "After a user drag the thread must not be pulled back to the end of the answer")
        XCTAssertFalse(isVisible(element(app, "ask.bubble.3.thumbsUp"), in: thread),
                       "After a user drag the thread must not be pulled back to the answer's actions row")

        // (c) A new send follows again, from wherever the user had scrolled to.
        ask(app, "Scripted question three")
        XCTAssertTrue(element(app, "ask.bubble.5.speak").waitForExistence(timeout: 10), "Answer 3 never started")
        XCTAssertTrue(waitUntilEnabled(newChat, timeout: 20), "Answer 3 never completed")
        sleep(1)
        XCTAssertTrue(isVisible(lastLine(app, "Scripted question three"), in: thread),
                      "A new send should follow its answer to the end")
        XCTAssertTrue(isVisible(element(app, "ask.bubble.5.thumbsUp"), in: thread),
                      "A new send should end on its answer's actions row")
    }

    // MARK: - Helpers

    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    private func ask(_ app: XCUIApplication, _ question: String) {
        let input = element(app, "ask.input")
        input.tap()
        input.typeText(question)
        let send = app.buttons["ask.send"]
        XCTAssertTrue(send.waitForExistence(timeout: 5), "Send button not found")
        send.tap()
    }

    private func waitUntilEnabled(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: element)
        return XCTWaiter().wait(for: [enabled], timeout: timeout) == .completed
    }

    /// The scripted answer's closing paragraph (`ScriptedChatStreamer`).
    private func lastLine(_ app: XCUIApplication, _ question: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label == %@", "End of the scripted answer to: \(question)")).firstMatch
    }

    /// Entirely inside the thread's viewport (1 pt tolerance) — XCUITest still reports frames for
    /// laid-out rows that are scrolled off screen, so `exists` alone proves nothing here.
    private func isVisible(_ element: XCUIElement, in container: XCUIElement) -> Bool {
        guard element.exists else { return false }
        let frame = element.frame
        let viewport = container.frame
        return !frame.isEmpty && frame.minY >= viewport.minY - 1 && frame.maxY <= viewport.maxY + 1
    }

    /// `--uitest-reset-auth` forces the real sign-in screen (the Keychain session survives
    /// reinstalls on the Simulator) and marks the one-time onboarding panel as seen.
    private func signIn(_ app: XCUIApplication, extraLaunchArguments: [String] = []) throws {
        let environment = ProcessInfo.processInfo.environment
        guard let email = environment["STASH_TEST_EMAIL"], let password = environment["STASH_TEST_PASSWORD"],
              !email.isEmpty, !password.isEmpty
        else {
            XCTFail("STASH_TEST_EMAIL / STASH_TEST_PASSWORD were not set in the test runner environment")
            throw XCTSkip("missing test credentials")
        }
        app.launchArguments = ["--uitest-reset-auth"] + extraLaunchArguments
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
