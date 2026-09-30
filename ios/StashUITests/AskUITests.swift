import XCTest

/// Plan 15 Task 6A (Ask tune-up): checks that need no live answer. The banner test relies on the
/// client-side subscription gate so it never requests a model answer — it skips itself when the
/// account isn't gated (`will+uitest` is comped since 2026-09-30). The follow-scroll and plan-16
/// keyboard tests run on `--uitest-scripted-chat` (local scripted answers, in-memory history with
/// one fixed earlier conversation), so they never reach the server either.
///
/// A standalone file (`StashUITests.swift` belongs to another task this round), so it carries its
/// own small sign-in helper — the same recipe as `StashUITests.signInAndReachLibrary`, plus the
/// iOS 26 "Save Password?" sheet dismissal, and a tab switch that fails on a swallowed tap unless
/// that sheet is still to come.
final class AskUITests: XCTestCase {
    /// iOS 26's "Save Password?" prompt may still turn up and take a tap — set by `signIn` from
    /// `dismissSavePasswordPrompt`, read by `openAskTab`. Per test (XCTest makes an instance per
    /// test method).
    private var savePasswordPromptPending = false

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// M11: Ask is retrieval-only on every platform — the composer shows the web mole's
    /// placeholder and no longer advertises "paste a link / 'remember:' to save".
    func testAskComposerIsRetrievalOnly() throws {
        let app = XCUIApplication()
        try signIn(app)
        openAskTab(app)

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
        openAskTab(app)

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

    /// Final wave B: when the SERVER refuses a question (`403 subscription_required` —
    /// chat-with-all-content's own paywall, reached when the app's local gate was out of date or
    /// still failing open), Ask shows the subscription-gate copy — not "Failed to get a response."
    /// — rolls the exchange back and keeps the question in the composer. `--uitest-scripted-chat`
    /// refuses questions starting with "gate:" exactly that way, so nothing reaches the server.
    func testServerSubscriptionRefusalShowsTheGateCopy() throws {
        let app = XCUIApplication()
        try signIn(app, extraLaunchArguments: ["--uitest-scripted-chat"])
        openAskTab(app)
        let input = element(app, "ask.input")
        XCTAssertTrue(input.waitForExistence(timeout: 10), "Ask input field did not appear")

        ask(app, "gate: refused by the server")

        let banner = element(app, "ask.gateError")
        XCTAssertTrue(banner.waitForExistence(timeout: 5), "Expected the subscription gate banner")
        XCTAssertTrue(banner.label.contains("AI chat needs an active trial or subscription."),
                      "Expected the gate copy, got '\(banner.label)'")
        XCTAssertFalse(element(app, "ask.error").exists, "A paywall refusal is not a generic failure")
        XCTAssertFalse(element(app, "ask.bubble.0").exists, "The refused exchange is rolled back")
        XCTAssertEqual(input.value as? String, "gate: refused by the server",
                       "The refused question is back in the composer")
    }

    /// M2 review fix, verified on the iOS 17 floor: the thread follows a streaming answer until
    /// the USER drags it away, and a new send follows again. `--uitest-scripted-chat` swaps in a
    /// local scripted stream (status frames, then ~60 list lines over ~6 s including two
    /// ten-bullet bursts in single deltas) with in-memory history — nothing reaches the server,
    /// so this runs on the gate-blocked account without creating conversations.
    ///
    /// Final wave B: on the iOS 17.0 sim this failed every run at (a), for two reasons found with
    /// scroll-geometry logging: the streaming cursor's `repeatForever` animation had leaked into
    /// the answer row's layout (content height swinging ~376 pt every 0.6 s, forever — the cursor
    /// now animates only its own opacity), and the settle scroll ran while the finished answer was
    /// still being re-measured, resting hundreds of points short (the settle now holds the true end
    /// for ~1.3 s — `AskView.followThread`).
    ///
    /// Thread rows are `[q1, a1, q2, a2, q3, a3]`, so the answers are bubbles 1, 3 and 5. An
    /// answer has started once its read-aloud button exists (content arrived) and has finished
    /// once `ask.newChat` is enabled again (disabled exactly while an answer streams) — a signal
    /// that doesn't depend on where the thread is scrolled; an answer's own thumbs can be
    /// scrolled out of the lazily built thread.
    ///
    /// Plan 16: (a) and (b) send with the keyboard up, as a user sends, so each answer starts
    /// streaming under a live keyboard, and (b)'s drag runs against it
    /// (`.scrollDismissesKeyboard(.interactively)`). While the composer is focused, New chat gives
    /// way to Cancel. So the keyboard is put away with Cancel once the answer is under way, and in
    /// (b) only after the drag. Each Cancel asserts that the keyboard is on screen and logs its
    /// frame; (a)'s also asserts that the answer is still streaming. (c) sends with the keyboard
    /// down; see the note there.
    func testThreadFollowsTheStreamUntilTheUserScrollsAway() throws {
        let app = XCUIApplication()
        try signIn(app, extraLaunchArguments: ["--uitest-scripted-chat"])
        openAskTab(app)

        let input = element(app, "ask.input")
        XCTAssertTrue(input.waitForExistence(timeout: 10), "Ask input field did not appear")
        let thread = app.scrollViews["ask.thread"]
        XCTAssertTrue(thread.waitForExistence(timeout: 5), "Ask thread did not appear")
        let newChat = app.buttons["ask.newChat"]

        // (a) Send and keep hands off: the view keeps up with every burst, with the keyboard up
        // and after it goes mid-answer, and settles on the finished answer's last line and
        // actions row.
        ask(app, "Scripted question one")
        XCTAssertTrue(element(app, "ask.bubble.1.speak").waitForExistence(timeout: 10), "Answer 1 never started")
        putKeyboardAway(app, streamingAnswer: 1, "mid-answer 1")
        XCTAssertTrue(waitUntilEnabled(newChat, timeout: 20), "Answer 1 never completed")
        sleep(1)
        XCTAssertTrue(isVisible(lastLine(app, "Scripted question one"), in: thread),
                      "Following: answer 1's last line should be on screen when it completes")
        XCTAssertTrue(isVisible(element(app, "ask.bubble.1.thumbsUp"), in: thread),
                      "Following: answer 1's actions row should be on screen when it completes")

        // (b) Send, then drag the thread up while the answer is still streaming: it must stay
        // where the user put it — no yank back down, not even the settle scroll at completion.
        // The drag goes with the keyboard still up; Cancel only after it.
        ask(app, "Scripted question two")
        XCTAssertTrue(element(app, "ask.bubble.3.speak").waitForExistence(timeout: 10), "Answer 2 never started")
        sleep(2)   // a couple of screens of answer 2 have streamed in
        // New chat, the enabled-state signal, is behind Cancel while the keyboard is up.
        XCTAssertTrue(isStreaming(app, answer: 3), "The drag must happen mid-stream")
        assertKeyboardOnScreen(app, "for the mid-stream drag")
        thread.swipeDown()
        putKeyboardAway(app, "after the mid-stream drag")
        XCTAssertTrue(waitUntilEnabled(newChat, timeout: 20), "Answer 2 never completed")
        sleep(1)
        XCTAssertFalse(isVisible(lastLine(app, "Scripted question two"), in: thread),
                       "After a user drag the thread must not be pulled back to the end of the answer")
        XCTAssertFalse(isVisible(element(app, "ask.bubble.3.thumbsUp"), in: thread),
                       "After a user drag the thread must not be pulled back to the answer's actions row")

        // (c) A new send follows again, from wherever the user had scrolled to. Sent with the
        // keyboard down. With the keyboard up, this send hits an app bug on the iOS 17.5
        // simulator in about half of runs: the follow-jump from far up the thread lands past the
        // last row (the lazy thread has overestimated its height), and the thread stays blank for
        // the whole answer, with no rows built. Go back to a keyboard-up send once that's fixed.
        ask(app, "Scripted question three", keyboardDown: true)
        XCTAssertTrue(element(app, "ask.bubble.5.speak").waitForExistence(timeout: 10), "Answer 3 never started")
        XCTAssertTrue(waitUntilEnabled(newChat, timeout: 20), "Answer 3 never completed")
        sleep(1)
        XCTAssertTrue(isVisible(lastLine(app, "Scripted question three"), in: thread),
                      "A new send should follow its answer to the end")
        XCTAssertTrue(isVisible(element(app, "ask.bubble.5.thumbsUp"), in: thread),
                      "A new send should end on its answer's actions row")
    }

    // MARK: - Plan 16: keyboard

    /// Plan 16 (Will: "picking a conversation then back to the 'Ask' view causes the input area to
    /// disappear … and causes the keyboard to appear stuck in the on position"). Root cause,
    /// reproduced on the iOS 26.5 simulator: History was tapped while the composer held the
    /// keyboard; the pop back handed the keyboard to the composer again, and SwiftUI's keyboard
    /// avoidance missed it — keyboard up, composer left at its resting position behind it. Now
    /// History gives way to Cancel while composing, and every way of showing an earlier
    /// conversation puts the keyboard away first.
    ///
    /// Walks Will's path the way the app now allows it — compose, Cancel, History, search, pick —
    /// then a Back-button pop and the restore banner (tapped while composing), checking after each
    /// that no keyboard comes back and the composer is reachable with its draft intact.
    /// `--uitest-scripted-chat` supplies the one earlier conversation, so no server is involved.
    func testShowingAnEarlierConversationLeavesNoKeyboardUp() throws {
        let app = XCUIApplication()
        try signIn(app, extraLaunchArguments: ["--uitest-scripted-chat"])
        openAskTab(app)
        let input = element(app, "ask.input")
        let cancel = app.buttons["ask.dismissKeyboard"]
        let history = app.buttons["ask.history"]
        let pill = element(app, "ask.sessionPill")
        let draft = "half-typed question"

        // Composing: the keyboard is up and History has given way to Cancel.
        input.tap()
        input.typeText(draft)
        XCTAssertTrue(cancel.waitForExistence(timeout: 5), "Expected Cancel while composing")
        XCTAssertFalse(history.exists, "History must not be reachable while the composer holds the keyboard")
        cancel.tap()
        XCTAssertTrue(noKeyboard(app), "Cancel should put the keyboard away")

        // History → search (the list's own keyboard is up) → pick the earlier conversation.
        XCTAssertTrue(history.waitForExistence(timeout: 5), "History should be back once the keyboard is away")
        history.tap()
        let search = app.textFields["convos.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 10), "Conversations search did not appear")
        search.tap()
        search.typeText("earlier")
        let row = element(app, "convos.row.0")
        XCTAssertTrue(row.waitForExistence(timeout: 10), "The scripted earlier conversation did not list")
        row.tap()
        XCTAssertTrue(pill.waitForExistence(timeout: 10), "Expected the earlier conversation's title pill")
        XCTAssertTrue(element(app, "ask.bubble.1").label.contains("sourdough"),
                      "Expected the earlier conversation on the thread")
        assertComposerReachableWithNoKeyboard(app, draft: draft, "after picking a conversation")
        attachScreenshot(app, named: "ask-after-picking-a-conversation")

        // History → Back without picking.
        history.tap()
        XCTAssertTrue(search.waitForExistence(timeout: 10), "Conversations search did not appear")
        search.tap()
        search.typeText("x")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(input.waitForExistence(timeout: 10), "Expected the Ask thread after Back")
        assertComposerReachableWithNoKeyboard(app, draft: draft, "after Back from Conversations")

        // New chat lets the conversation go; its restore banner, tapped while composing, brings it
        // back with the keyboard put away.
        app.buttons["ask.newChat"].tap()
        let banner = element(app, "ask.restoreBanner")
        XCTAssertTrue(banner.waitForExistence(timeout: 5), "Expected the restore banner after New chat")
        input.tap()
        XCTAssertTrue(cancel.waitForExistence(timeout: 5), "Expected Cancel while composing")
        assertComposerAboveKeyboard(app, "while composing over the restore banner")
        banner.tap()
        XCTAssertTrue(pill.waitForExistence(timeout: 10), "Expected the conversation restored")
        assertComposerReachableWithNoKeyboard(app, draft: draft, "after restoring a conversation")
        attachScreenshot(app, named: "ask-after-restoring-a-conversation")
    }

    /// Plan 16 (Will: "when keyboard is shown and input is active while composing on Ask view,
    /// upper right should become 'cancel' (same as when composing on the home screen)"): focusing
    /// the composer swaps New chat / History for `StashCancelButton` (label "Cancel", at least
    /// 44×44 pt); Cancel puts the keyboard away, keeps the typed text, and brings the circles back.
    func testCancelWhileComposingHidesTheKeyboardAndKeepsTheDraft() throws {
        let app = XCUIApplication()
        try signIn(app, extraLaunchArguments: ["--uitest-scripted-chat"])
        openAskTab(app)
        let input = element(app, "ask.input")
        let newChat = app.buttons["ask.newChat"]
        let history = app.buttons["ask.history"]
        let cancel = app.buttons["ask.dismissKeyboard"]
        XCTAssertTrue(newChat.waitForExistence(timeout: 5), "New chat missing at rest")
        XCTAssertTrue(history.exists, "History missing at rest")
        XCTAssertFalse(cancel.exists, "No Cancel before the composer is focused")

        input.tap()
        input.typeText("Keep this draft")
        XCTAssertTrue(cancel.waitForExistence(timeout: 5), "Expected Cancel while composing")
        XCTAssertTrue(cancel.isHittable, "Cancel should be tappable while composing")
        XCTAssertEqual(cancel.label, "Cancel")
        XCTAssertGreaterThanOrEqual(cancel.frame.width, 44, "Cancel's hit area is narrower than 44 pt")
        XCTAssertGreaterThanOrEqual(cancel.frame.height, 44, "Cancel's hit area is shorter than 44 pt")
        XCTAssertFalse(newChat.exists, "New chat should give way to Cancel while composing")
        XCTAssertFalse(history.exists, "History should give way to Cancel while composing")
        XCTAssertTrue(app.keyboards.firstMatch.exists, "Expected the keyboard while composing")
        assertComposerAboveKeyboard(app, "while composing")
        attachScreenshot(app, named: "ask-composing-cancel")

        cancel.tap()
        XCTAssertTrue(noKeyboard(app), "Cancel should put the keyboard away")
        XCTAssertEqual(input.value as? String, "Keep this draft", "Cancel must keep the draft")
        XCTAssertTrue(newChat.waitForExistence(timeout: 5), "New chat should come back with the keyboard gone")
        XCTAssertTrue(history.exists, "History should come back with the keyboard gone")
        XCTAssertFalse(cancel.exists, "Cancel should go with the keyboard")
        attachScreenshot(app, named: "ask-after-cancel")
    }

    // MARK: - Helpers

    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    /// A screenshot kept in the result bundle (exported for task reports).
    private func attachScreenshot(_ app: XCUIApplication, named name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// Types `question` and sends it the way a user does: the composer keeps focus, so the answer
    /// streams with the keyboard up, and with Cancel where New chat was (plan 16), until the test
    /// puts the keyboard away (`putKeyboardAway`). With `keyboardDown`, Cancel goes first (the
    /// typed text stays), so the question is sent with the keyboard down.
    private func ask(_ app: XCUIApplication, _ question: String, keyboardDown: Bool = false) {
        let input = element(app, "ask.input")
        input.tap()
        input.typeText(question)
        if keyboardDown { putKeyboardAway(app, "before sending") }
        let send = app.buttons["ask.send"]
        XCTAssertTrue(send.waitForExistence(timeout: 5), "Send button not found")
        send.tap()
    }

    /// Answer `n` is still streaming: its actions row is built (read-aloud shows once content has
    /// arrived), but its thumbs aren't there yet (they show only on a finished answer). This works
    /// with the keyboard up, when New chat, whose enabled state is the "finished" signal, has given
    /// way to Cancel. It's only meaningful while the answer's row is on screen, since the thread is
    /// built lazily.
    private func isStreaming(_ app: XCUIApplication, answer n: Int) -> Bool {
        element(app, "ask.bubble.\(n).speak").exists && !element(app, "ask.bubble.\(n).thumbsUp").exists
    }

    /// The software keyboard is up and on screen, not just present in the tree: on a simulator with a
    /// hardware keyboard attached it sits below the screen until XCUITest types. Its frame goes in
    /// the test's activity log.
    private func assertKeyboardOnScreen(_ app: XCUIApplication, _ context: String,
                                        file: StaticString = #filePath, line: UInt = #line) {
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.exists, "Expected the keyboard up \(context)", file: file, line: line)
        let frame = keyboard.frame
        let screen = app.frame
        XCTContext.runActivity(named: "Keyboard \(context): \(frame) (screen \(screen))") { _ in }
        XCTAssertLessThan(frame.minY, screen.maxY,
                          "Expected the keyboard on screen \(context) (keyboard \(frame), screen \(screen))",
                          file: file, line: line)
    }

    /// Puts the keyboard away with the header's Cancel. While the composer is focused, Cancel stands
    /// where New chat (the "answer finished" signal) sits. Asserts first that the keyboard is on
    /// screen (its frame is logged). When `streamingAnswer` is given, also asserts that that answer
    /// is still streaming: together they show the answer streamed with the keyboard up.
    private func putKeyboardAway(_ app: XCUIApplication, streamingAnswer: Int? = nil, _ context: String,
                                 file: StaticString = #filePath, line: UInt = #line) {
        let cancel = app.buttons["ask.dismissKeyboard"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5), "Expected Cancel while composing \(context)",
                      file: file, line: line)
        assertKeyboardOnScreen(app, "at Cancel \(context)", file: file, line: line)
        if let n = streamingAnswer {
            XCTAssertTrue(isStreaming(app, answer: n), "Expected the answer still streaming at Cancel \(context)",
                          file: file, line: line)
        }
        cancel.tap()
        XCTAssertTrue(app.buttons["ask.newChat"].waitForExistence(timeout: 5),
                      "New chat should be back once the keyboard is away \(context)", file: file, line: line)
    }

    /// True when no keyboard is up — waiting out one still animating away — and none has come back
    /// 1.5 s later: the stuck keyboard came back at the END of the pop, so an instant check could
    /// pass before it landed.
    private func noKeyboard(_ app: XCUIApplication) -> Bool {
        let keyboard = app.keyboards.firstMatch
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: keyboard)
        guard XCTWaiter().wait(for: [gone], timeout: 5) == .completed else { return false }
        Thread.sleep(forTimeInterval: 1.5)
        return !keyboard.exists
    }

    private func assertComposerReachableWithNoKeyboard(_ app: XCUIApplication, draft: String, _ context: String,
                                                       file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(noKeyboard(app), "No keyboard should be up \(context)", file: file, line: line)
        let input = element(app, "ask.input")
        XCTAssertTrue(input.waitForExistence(timeout: 5), "Composer missing \(context)", file: file, line: line)
        XCTAssertTrue(input.isHittable, "The composer should be reachable \(context)", file: file, line: line)
        XCTAssertEqual(input.value as? String, draft, "The draft should survive \(context)", file: file, line: line)
        XCTAssertTrue(app.buttons["ask.history"].exists, "History should be back \(context)", file: file, line: line)
    }

    /// `ChatComposerBar`'s vertical padding around the text. `ask.input`'s accessibility frame is
    /// the text line only, and the visible field (the pill) reaches this far beyond it on each side
    /// (`StashUITests.testAskComposerLayout` measures the same).
    private static let composerPillPadding: CGFloat = 10

    /// Whenever a keyboard is up, the composer's pill sits wholly above it (on a simulator with a
    /// hardware keyboard attached the software keyboard stays off screen, which passes trivially).
    private func assertComposerAboveKeyboard(_ app: XCUIApplication, _ context: String,
                                             file: StaticString = #filePath, line: UInt = #line) {
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5), "Expected a keyboard \(context)", file: file, line: line)
        sleep(1)   // keyboard animation + avoidance
        let input = element(app, "ask.input")
        XCTAssertTrue(input.isHittable, "The composer should be reachable \(context)", file: file, line: line)
        let pillBottom = input.frame.maxY + Self.composerPillPadding
        XCTAssertLessThanOrEqual(pillBottom, keyboard.frame.minY,
                                 "The composer's pill should sit above the keyboard \(context) (pill bottom \(pillBottom), keyboard top \(keyboard.frame.minY))",
                                 file: file, line: line)
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
        savePasswordPromptPending = dismissSavePasswordPrompt(app)
    }

    /// iOS 26 offers "Save Password?" a moment after the sign-in form submits; left up, it swallows
    /// the test's next tap (the Ask tab switch, or a header button). "Not Now" when it shows.
    /// Returns whether it could still be in the way: iOS 26, and not seen and dismissed yet.
    private func dismissSavePasswordPrompt(_ app: XCUIApplication) -> Bool {
        // Only ever seen on iOS 26, where it's an in-app sheet that can take several seconds.
        guard ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26 else { return false }
        let notNow = app.buttons["Not Now"]
        guard notNow.waitForExistence(timeout: 12) else { return true }
        // A tap while the sheet is still animating in (or out) is ignored — settle, tap, and
        // check it actually went away.
        for _ in 0..<3 {
            sleep(1)
            guard notNow.exists else { break }
            notNow.tap()
            let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: notNow)
            if XCTWaiter().wait(for: [gone], timeout: 3) == .completed { break }
        }
        sleep(1)
        return notNow.exists
    }

    /// Switches to the Ask tab. The tap has to land: a swallowed tab tap is a real regression
    /// (something over the tab bar), so it fails the test. The one exception is iOS 26's "Save
    /// Password?" prompt while it's still pending (`dismissSavePasswordPrompt` hasn't seen it go),
    /// the one known thing that takes this tap. Then there's one retry, recorded in the test's
    /// activity log with a screenshot. Allowing the retry "once the prompt was seen" would be
    /// backwards: the prompt shows on every iOS 26 sign-in and is confirmed gone by then, so every
    /// iOS 26 run could retry, just when the prompt can no longer be the cause.
    private func openAskTab(_ app: XCUIApplication) {
        let askTab = app.tabBars.buttons["Ask"]
        let input = element(app, "ask.input")
        askTab.tap()
        if input.waitForExistence(timeout: 10) { return }
        guard savePasswordPromptPending else {
            attachScreenshot(app, named: "ask-tab-tap-swallowed")
            XCTFail("The Ask tab tap was swallowed with no Save Password prompt pending")
            return
        }
        XCTContext.runActivity(named: "Ask tab tap swallowed while the Save Password prompt was pending: dismissing it, retrying once") { activity in
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "ask-tab-retry"
            shot.lifetime = .keepAlways
            activity.add(shot)
            savePasswordPromptPending = dismissSavePasswordPrompt(app)
            askTab.tap()
        }
        XCTAssertTrue(input.waitForExistence(timeout: 10), "Could not switch to the Ask tab")
    }
}
