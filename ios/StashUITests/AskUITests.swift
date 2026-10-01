import XCTest

/// Plan 15 Task 6A (Ask tune-up): checks that need no live answer. The banner test relies on the
/// client-side subscription gate so it never requests a model answer — it skips itself when the
/// account isn't gated (`will+uitest` is comped since 2026-09-30). The follow-scroll and plan-16
/// keyboard tests run on `--uitest-scripted-chat` (local scripted answers, in-memory history with
/// one fixed earlier conversation), so they never reach the server either; task 1b's long-thread
/// test adds `--uitest-scripted-long-thread` (a long restored conversation, and a second one in
/// History).
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
    /// Plan 16: every send goes with the keyboard up, as a user sends, so each answer starts
    /// streaming under a live keyboard, and (b)'s drag runs against it
    /// (`.scrollDismissesKeyboard(.interactively)`). While the composer is focused, New chat gives
    /// way to Cancel. So the keyboard is put away with Cancel once the answer is under way, and in
    /// (b) only after the drag. Each Cancel asserts that the keyboard is on screen and logs its
    /// frame; (a)'s and (c)'s also assert that the answer is still streaming. (c) is task 1b's
    /// regression: see the note there.
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

        // (c) A new send follows again, from wherever the user had scrolled to, sent the way a user
        // sends: with the keyboard up. That's a jump across screens. It used to land past the last
        // row on iOS 17 and 18 (task 1b): the lazy thread sizes rows it hasn't loaded at the average
        // of the ones it has, so the jump overshot, and the thread stayed blank for the whole answer.
        // So the thread must show a bubble right after the send and mid-answer. "Still streaming" is
        // checked straight after the answer starts, while the keyboard is up: by the time the bubble
        // checks and Cancel are done, answer 3 can be over (task 1c, review finding M1: that margin
        // was 0.6–1.6 s on iOS 26.5).
        ask(app, "Scripted question three")
        assertThreadShowsABubble(app, thread, "right after the send from up the thread")
        XCTAssertTrue(element(app, "ask.bubble.5.speak").waitForExistence(timeout: 10), "Answer 3 never started")
        XCTAssertTrue(isStreaming(app, answer: 5), "Answer 3 should still be streaming, keyboard up")
        assertKeyboardOnScreen(app, "while answer 3 streams")
        assertThreadShowsABubble(app, thread, "mid-answer 3, keyboard up")
        putKeyboardAway(app, "mid-answer 3")
        assertThreadShowsABubble(app, thread, "mid-answer 3, keyboard down")
        XCTAssertTrue(waitUntilEnabled(newChat, timeout: 20), "Answer 3 never completed")
        sleep(1)
        XCTAssertTrue(isVisible(lastLine(app, "Scripted question three"), in: thread),
                      "A new send should follow its answer to the end")
        XCTAssertTrue(isVisible(element(app, "ask.bubble.5.thumbsUp"), in: thread),
                      "A new send should end on its answer's actions row")
    }

    /// Task 1b: no far jump leaves a long thread blank. `--uitest-scripted-long-thread` restores a
    /// long scripted conversation at launch (8 exchanges, each answer a 60-line list several
    /// screens tall) and lists a second one in History, so every far jump the thread makes runs
    /// against rows the lazy stack hasn't loaded, and sizes at the average of the ones it has:
    /// - the restored thread's first landing at its end;
    /// - a send, keyboard up, from several screens up (the jump that used to land past the last row
    ///   and leave the thread blank for the whole answer, on iOS 17 and 18);
    /// - a conversation picked in History (opened while the thread is hidden);
    /// - New chat, then the restore banner (the thread replaced while on screen).
    /// After each, the thread must show a bubble, and the landing must be the thread's last row.
    func testFarJumpsInALongThreadLandOnItsLastRow() throws {
        let app = XCUIApplication()
        try signIn(app, extraLaunchArguments: ["--uitest-scripted-chat", "--uitest-scripted-long-thread"])
        openAskTab(app)
        let thread = app.scrollViews["ask.thread"]
        XCTAssertTrue(thread.waitForExistence(timeout: 10), "Ask thread did not appear")
        let newChat = app.buttons["ask.newChat"]
        // Rows are [q1, a1, … q8, a8]: the last restored answer is bubble 15.
        let lastAnswer = 15

        // The restored thread opens at its end. Its last answer's thumbs exist as soon as it's loaded
        // (the answer is in the laid-out tail, on screen or not): that wait is for the load, and the
        // last-line check is the landing.
        XCTAssertTrue(element(app, "ask.bubble.\(lastAnswer).thumbsUp").waitForExistence(timeout: 10),
                      "The restored long thread should load")
        assertThreadShowsABubble(app, thread, "after opening the long thread")
        XCTAssertTrue(waitUntilVisible(lastLine(app, "Long question 8"), in: thread),
                      "The restored long thread should open on its last answer's last line")

        // Several screens up, then a keyboard-up send: the thread follows the new answer from the
        // first frame to the last, and is never blank on the way.
        for _ in 0..<3 { thread.swipeDown() }
        XCTAssertFalse(isVisible(element(app, "ask.bubble.\(lastAnswer).thumbsUp"), in: thread),
                       "The drags should have left the end of the thread")
        ask(app, "Scripted question from far up")
        assertThreadShowsABubble(app, thread, "right after the send from far up")
        let answer = lastAnswer + 2
        XCTAssertTrue(element(app, "ask.bubble.\(answer).speak").waitForExistence(timeout: 10), "The new answer never started")
        assertThreadShowsABubble(app, thread, "mid-answer, keyboard up")
        putKeyboardAway(app, streamingAnswer: answer, "mid-answer after the send from far up")
        assertThreadShowsABubble(app, thread, "mid-answer, keyboard down")
        XCTAssertTrue(waitUntilEnabled(newChat, timeout: 20), "The new answer never completed")
        sleep(1)
        XCTAssertTrue(isVisible(lastLine(app, "Scripted question from far up"), in: thread),
                      "The send from far up should follow its answer to the end")
        XCTAssertTrue(isVisible(element(app, "ask.bubble.\(answer).thumbsUp"), in: thread),
                      "The send from far up should end on its answer's actions row")

        // A long conversation picked in History opens at its end.
        app.buttons["ask.history"].tap()
        let search = app.textFields["convos.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 10), "Conversations search did not appear")
        search.tap()
        search.typeText("long")
        let row = element(app, "convos.row.0")
        XCTAssertTrue(row.waitForExistence(timeout: 10), "The scripted long conversation did not list")
        row.tap()
        XCTAssertTrue(element(app, "ask.sessionPill").waitForExistence(timeout: 10), "Expected the picked conversation's title pill")
        XCTAssertTrue(element(app, "ask.bubble.\(lastAnswer).thumbsUp").waitForExistence(timeout: 10),
                      "The picked long conversation should load")
        assertThreadShowsABubble(app, thread, "after picking the long conversation")
        XCTAssertTrue(waitUntilVisible(lastLine(app, "Long question B8"), in: thread),
                      "The picked long conversation should open on its last answer's last line")

        // New chat lets it go; the restore banner brings it back, again at its end.
        newChat.tap()
        let banner = element(app, "ask.restoreBanner")
        XCTAssertTrue(banner.waitForExistence(timeout: 5), "Expected the restore banner after New chat")
        assertThreadShowsABubble(app, thread, "after New chat", matching: "ask.restoreBanner")
        banner.tap()
        XCTAssertTrue(element(app, "ask.bubble.\(lastAnswer).thumbsUp").waitForExistence(timeout: 10),
                      "The restored long conversation should load")
        assertThreadShowsABubble(app, thread, "after restoring the long conversation")
        XCTAssertTrue(waitUntilVisible(lastLine(app, "Long question B8"), in: thread),
                      "The restored long conversation should open on its last answer's last line")
    }

    /// Task 1c (review finding I1): a send from a little way up the last answer, inside the laid-out
    /// tail, lands on the new answer and is never blank. Task 1b shed the tail on any send made while
    /// not following, which from here moves rows above the reader into the lazy history, to be
    /// re-estimated there. (No frame of that showed on screen in task 1c's measurements on iOS 17.5,
    /// 18.5 or 26.5, with a UIKit marker inside the last answer; the thousands-of-points jumps an
    /// earlier probe reported were geometry SwiftUI reports from layout passes it then drops.) Now
    /// only a reader above the whole tail sheds it, a hop within a screen eases again, and this send
    /// keeps every row where it is. The follow test's (c) and the long-thread test don't cover this
    /// geometry: theirs start inside a fresh thread's rows and above the tail.
    ///
    /// The drag's own check — that it left the end but stayed inside the last answer — is the
    /// reader's place under their finger. Re-rendering the thread when following turned off made the
    /// lazy history above re-estimate as the drag began (+4,893 pt on iOS 18.5), and with nothing
    /// holding the tail, the last answer jumped away into an older one (4 of 5 runs on 18.5, 3 of 5
    /// on 26.5, failed here). Following no longer re-renders anything (`AskView.isFollowing`), and the
    /// tail hold (`AskThreadScrollObserver`) keeps the line still through such a re-estimate anyway.
    func testASendFromJustUpTheLastAnswerLandsOnItsAnswer() throws {
        let app = XCUIApplication()
        try signIn(app, extraLaunchArguments: ["--uitest-scripted-chat", "--uitest-scripted-long-thread"])
        openAskTab(app)
        let thread = app.scrollViews["ask.thread"]
        XCTAssertTrue(thread.waitForExistence(timeout: 10), "Ask thread did not appear")
        let newChat = app.buttons["ask.newChat"]
        // Rows are [q1, a1, … q8, a8]: the last restored answer is bubble 15, and the tail holds it.
        let lastAnswer = 15
        XCTAssertTrue(element(app, "ask.bubble.\(lastAnswer).thumbsUp").waitForExistence(timeout: 10),
                      "The restored long thread should load")
        XCTAssertTrue(waitUntilVisible(lastLine(app, "Long question 8"), in: thread),
                      "The restored long thread should open on its last answer's last line")

        // A short drag up: off the end, but still inside the last answer.
        sleep(1)
        dragThreadDown(thread, by: 0.35)
        XCTAssertFalse(isVisible(element(app, "ask.bubble.\(lastAnswer).thumbsUp"), in: thread),
                       "The drag should have left the end of the thread")
        XCTAssertTrue(showsPart(of: "ask.bubble.\(lastAnswer)", in: thread),
                      "The drag should have stayed inside the last answer")

        ask(app, "Scripted question from just up")
        assertThreadShowsABubble(app, thread, "right after the send from just up")
        let answer = lastAnswer + 2
        XCTAssertTrue(element(app, "ask.bubble.\(answer).speak").waitForExistence(timeout: 10), "The new answer never started")
        XCTAssertTrue(isStreaming(app, answer: answer), "The new answer should still be streaming, keyboard up")
        assertThreadShowsABubble(app, thread, "mid-answer, keyboard up")
        putKeyboardAway(app, "mid-answer after the send from just up")
        assertThreadShowsABubble(app, thread, "mid-answer, keyboard down")
        XCTAssertTrue(waitUntilEnabled(newChat, timeout: 20), "The new answer never completed")
        sleep(1)
        XCTAssertTrue(isVisible(lastLine(app, "Scripted question from just up"), in: thread),
                      "The send from just up should follow its answer to the end")
        XCTAssertTrue(isVisible(element(app, "ask.bubble.\(answer).thumbsUp"), in: thread),
                      "The send from just up should end on its answer's actions row")
    }

    /// Task 1c: a reader who has scrolled a little way up the last answer — inside the laid-out tail,
    /// no longer following — keeps their place when they tap the composer. The keyboard shrinks the
    /// thread from below, so what they read stays where it is on screen. Measured on iOS 18.5, that
    /// same moment made the lazy history above the tail re-estimate its unbuilt rows by +816, +2,298
    /// and +1,562 pt in three passes; the tail moves with every one, and only the observer's tail
    /// hold (`AskThreadScrollObserver`) keeps the reader's line still through them.
    func testReadingUpTheLastAnswerKeepsItsPlaceWhenTheKeyboardComesUp() throws {
        let app = XCUIApplication()
        try signIn(app, extraLaunchArguments: ["--uitest-scripted-chat", "--uitest-scripted-long-thread"])
        openAskTab(app)
        let thread = app.scrollViews["ask.thread"]
        XCTAssertTrue(thread.waitForExistence(timeout: 10), "Ask thread did not appear")
        let lastAnswer = 15
        XCTAssertTrue(element(app, "ask.bubble.\(lastAnswer).thumbsUp").waitForExistence(timeout: 10),
                      "The restored long thread should load")
        XCTAssertTrue(waitUntilVisible(lastLine(app, "Long question 8"), in: thread),
                      "The restored long thread should open on its last answer's last line")

        sleep(1)
        dragThreadDown(thread, by: 0.35)
        sleep(1)
        let line = try XCTUnwrap(centredLine(of: "ask.bubble.\(lastAnswer)", in: thread),
                                 "The drag should have stayed inside the last answer")
        XCTContext.runActivity(named: "Reading \"\(line.label)\" at y \(line.frame.minY)") { _ in }

        let input = element(app, "ask.input")
        input.tap()
        XCTAssertTrue(app.buttons["ask.dismissKeyboard"].waitForExistence(timeout: 5), "Expected Cancel while composing")
        sleep(2)   // the keyboard's animation, and the layout passes it sets off
        let after = frame(ofLine: line.label, in: "ask.bubble.\(lastAnswer)", thread: thread)
        XCTContext.runActivity(named: "Keyboard up: \"\(line.label)\" at \(after.map { "y \($0.minY)" } ?? "no frame")") { _ in }
        XCTAssertNotNil(after, "The line being read should still be in the last answer's rows")
        if let after {
            XCTAssertEqual(after.minY, line.frame.minY, accuracy: 2,
                           "The line being read should stay where it was on screen when the keyboard comes up")
        }
    }

    /// Task 1c: a long restored thread at rest at its end keeps its end when the composer is tapped
    /// and put away, twice. Its lazy history re-estimates as the keyboard comes up, over several
    /// layout passes, and on iOS 26.5 SwiftUI then set the offset itself, undoing the end hold: the
    /// thread was left about 2,640 pt short of its end, on an older answer, with nothing to bring it
    /// back until the next send — every time, until the hold was put back
    /// (`AskThreadScrollObserver.Coordinator.offsetChanged`).
    func testALongThreadKeepsItsEndWhenTheKeyboardComesUp() throws {
        let app = XCUIApplication()
        try signIn(app, extraLaunchArguments: ["--uitest-scripted-chat", "--uitest-scripted-long-thread"])
        openAskTab(app)
        let thread = app.scrollViews["ask.thread"]
        XCTAssertTrue(thread.waitForExistence(timeout: 10), "Ask thread did not appear")
        let lastAnswer = 15
        let question = "Long question 8"
        XCTAssertTrue(element(app, "ask.bubble.\(lastAnswer).thumbsUp").waitForExistence(timeout: 10),
                      "The restored long thread should load")
        assertShowsTheEnd(of: lastAnswer, question: question, app, thread, "once restored")
        sleep(2)   // past the landing's settle pins: the end from here on is the hold's
        let input = element(app, "ask.input")
        for round in 1...2 {
            input.tap()
            XCTAssertTrue(app.buttons["ask.dismissKeyboard"].waitForExistence(timeout: 5), "Expected Cancel while composing")
            sleep(1)
            assertShowsTheEnd(of: lastAnswer, question: question, app, thread, "with the keyboard up (round \(round))")
            putKeyboardAway(app, "after composing (round \(round))")
            sleep(1)
            assertShowsTheEnd(of: lastAnswer, question: question, app, thread, "with the keyboard down again (round \(round))")
        }
    }

    /// Task 1c (review finding M3): at rest at the end of an answer, the thread keeps its end in
    /// place when the keyboard rises (it used to cover the answer's last lines and actions row) and
    /// goes, and when the phone turns to landscape and back (it used to be left hundreds of points
    /// short of the end).
    func testTheThreadKeepsItsEndWhenTheKeyboardRisesOrThePhoneTurns() throws {
        let app = XCUIApplication()
        try signIn(app, extraLaunchArguments: ["--uitest-scripted-chat"])
        openAskTab(app)
        let thread = app.scrollViews["ask.thread"]
        XCTAssertTrue(thread.waitForExistence(timeout: 10), "Ask thread did not appear")
        addTeardownBlock { XCUIDevice.shared.orientation = .portrait }
        let question = "Scripted question one"
        ask(app, question)
        XCTAssertTrue(element(app, "ask.bubble.1.speak").waitForExistence(timeout: 10), "The answer never started")
        putKeyboardAway(app, "mid-answer")
        XCTAssertTrue(waitUntilEnabled(app.buttons["ask.newChat"], timeout: 20), "The answer never completed")
        // Past the completion's settle scrolls (about 1.5 s), which would otherwise pin the end again
        // after the keyboard rises: this is the thread at rest.
        sleep(3)
        assertShowsTheEnd(of: 1, question: question, app, thread, "at rest")

        let input = element(app, "ask.input")
        input.tap()
        input.typeText("A draft")
        assertKeyboardOnScreen(app, "while composing at rest")
        assertShowsTheEnd(of: 1, question: question, app, thread, "with the keyboard up")
        putKeyboardAway(app, "after composing at rest")
        assertShowsTheEnd(of: 1, question: question, app, thread, "with the keyboard down again")

        XCUIDevice.shared.orientation = .landscapeLeft
        assertShowsTheEnd(of: 1, question: question, app, thread, "in landscape")
        XCUIDevice.shared.orientation = .portrait
        assertShowsTheEnd(of: 1, question: question, app, thread, "back in portrait")
    }

    /// Task 1c (review nit N5): a thumb given to an answer is still given after the next answer. When
    /// the reader follows that next answer to its end, the thread moves the rated one out of its
    /// laid-out tail into the lazy history, which rebuilds the row; the rating used to be the
    /// bubble's own state, so it came back unset (and could be sent twice). `--uitest-scripted-chat`
    /// keeps the feedback on the device.
    func testAGivenThumbStaysGivenAfterTheNextAnswer() throws {
        let app = XCUIApplication()
        try signIn(app, extraLaunchArguments: ["--uitest-scripted-chat"])
        openAskTab(app)
        let thread = app.scrollViews["ask.thread"]
        XCTAssertTrue(thread.waitForExistence(timeout: 10), "Ask thread did not appear")
        let newChat = app.buttons["ask.newChat"]
        ask(app, "Scripted question one")
        XCTAssertTrue(element(app, "ask.bubble.1.speak").waitForExistence(timeout: 10), "Answer 1 never started")
        putKeyboardAway(app, "mid-answer 1")
        XCTAssertTrue(waitUntilEnabled(newChat, timeout: 20), "Answer 1 never completed")
        let thumbsUp = app.buttons["ask.bubble.1.thumbsUp"]
        XCTAssertTrue(waitUntilVisible(thumbsUp, in: thread), "Answer 1's thumbs should be on screen")
        thumbsUp.tap()
        XCTAssertFalse(thumbsUp.isEnabled, "A given thumb disables the pair")

        ask(app, "Scripted question two")
        XCTAssertTrue(element(app, "ask.bubble.3.speak").waitForExistence(timeout: 10), "Answer 2 never started")
        putKeyboardAway(app, "mid-answer 2")
        XCTAssertTrue(waitUntilEnabled(newChat, timeout: 20), "Answer 2 never completed")
        sleep(1)
        for _ in 0..<8 where !isVisible(thumbsUp, in: thread) {
            thread.swipeDown(velocity: .slow)
        }
        XCTAssertTrue(isVisible(thumbsUp, in: thread), "Couldn't scroll back up to answer 1's thumbs")
        XCTAssertFalse(thumbsUp.isEnabled, "The thumb given to answer 1 should still be given after answer 2")
    }

    /// Task 1c (review finding I3): the laid-out tail is sized by height, and the end is held while
    /// the lazy history above it re-measures, so a long thread of prose (`--uitest-scripted-prose`:
    /// wrapping paragraphs, whose height depends on the text size) lands on its last line at xSmall —
    /// on an iPhone 15 Pro Max task 1b's restored prose thread opened short of it, at the start of
    /// its last answer — and at AX3 and AX5, where task 1b's 2,000-character tail laid out many
    /// screens: its first row, the fifth answer (bubble 9), is in the tree there only if the tail
    /// holds it. At xSmall a conversation picked in History and one brought back by the restore
    /// banner land on their last line too. Screenshots `a11y-ask-long-prose-<size>` go in the result
    /// bundle.
    @MainActor
    func testALongProseThreadLandsOnItsLastRowAtEveryTextSize() throws {
        let screens = A11yScreens(self)
        try screens.signIn()
        let extraSmall = A11yVariant(category: "UICTContentSizeCategoryXS", token: "xS")
        for variant in [extraSmall, .ax3, .ax5] {
            let app = screens.launch(variant, tab: .ask, arguments: ["--uitest-scripted-chat", "--uitest-scripted-long-thread",
                                                                    "--uitest-scripted-prose"])
            let thread = app.scrollViews["ask.thread"]
            XCTAssertTrue(thread.waitForExistence(timeout: 10), "\(variant): Ask thread did not appear")
            XCTAssertTrue(element(app, "ask.bubble.15.thumbsUp").waitForExistence(timeout: 10),
                          "\(variant): the restored prose thread should load")
            XCTAssertTrue(waitUntilVisible(lastLine(app, "Long question 8"), in: thread),
                          "\(variant): the restored prose thread should open on its last answer's last line")
            XCTAssertTrue(isVisible(element(app, "ask.bubble.15.thumbsUp"), in: thread),
                          "\(variant): the restored prose thread should open on its last answer's actions row")
            assertThreadShowsABubble(app, thread, "\(variant): after opening the long prose thread")
            screens.attachScreenshot(named: "ask-long-prose")
            if variant != extraSmall {
                // By the old character budget the tail started at the fifth answer (bubble 9), about
                // four answers up: laid out, it would be in the tree.
                XCTAssertFalse(element(app, "ask.bubble.9").exists,
                               "\(variant): the laid-out tail should be about a screen and a half, not every row up to the fifth answer")
                continue
            }
            app.buttons["ask.history"].tap()
            let search = app.textFields["convos.search"]
            XCTAssertTrue(search.waitForExistence(timeout: 10), "Conversations search did not appear")
            search.tap()
            search.typeText("long")
            let row = element(app, "convos.row.0")
            XCTAssertTrue(row.waitForExistence(timeout: 10), "The scripted long conversation did not list")
            row.tap()
            XCTAssertTrue(element(app, "ask.sessionPill").waitForExistence(timeout: 10), "Expected the picked conversation's title pill")
            XCTAssertTrue(waitUntilVisible(lastLine(app, "Long question B8"), in: thread),
                          "\(variant): the picked prose conversation should open on its last answer's last line")
            assertThreadShowsABubble(app, thread, "\(variant): after picking the long prose conversation")
            app.buttons["ask.newChat"].tap()
            let banner = element(app, "ask.restoreBanner")
            XCTAssertTrue(banner.waitForExistence(timeout: 5), "Expected the restore banner after New chat")
            banner.tap()
            XCTAssertTrue(waitUntilVisible(lastLine(app, "Long question B8"), in: thread),
                          "\(variant): the restored prose conversation should open on its last answer's last line")
            assertThreadShowsABubble(app, thread, "\(variant): after restoring the long prose conversation")
        }
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
    /// puts the keyboard away (`putKeyboardAway`).
    private func ask(_ app: XCUIApplication, _ question: String) {
        let input = element(app, "ask.input")
        input.tap()
        input.typeText(question)
        let send = app.buttons["ask.send"]
        XCTAssertTrue(send.waitForExistence(timeout: 5), "Send button not found")
        send.tap()
    }

    /// The thread isn't blank: some element whose identifier starts with `prefix` (by default any
    /// `ask.bubble.*` text: a question or an answer block) is centred inside the thread's frame in a
    /// snapshot of the thread. Polls for up to `timeout`, since a far jump settles over a few frames,
    /// then fails with a screenshot.
    ///
    /// One snapshot of the thread per poll: a loaded 60-line answer alone carries dozens of
    /// `ask.bubble.*` elements, too many to query one at a time. Skipped: elements that show nothing
    /// (a blank label, such as an empty answer's placeholder space), glyph-sized ones, the transient
    /// status line, and an answer's action buttons. Laid-out rows are in the tree wherever the thread
    /// is scrolled (the tail, task 1b), so only a frame inside the thread's counts; the old blank
    /// landing left none there.
    ///
    /// Task 1c: the check no longer asks each candidate `isHittable` too. While an answer streamed
    /// with the keyboard up on iOS 26.5, that query itself raised "Activation point invalid" (a test
    /// failure, not a `false`) for rows the snapshot had just shown centred inside the thread — 2 of 6
    /// runs of the follow test — as the following thread moved them between the snapshot and the
    /// query.
    private func assertThreadShowsABubble(_ app: XCUIApplication, _ thread: XCUIElement, _ context: String,
                                          matching prefix: String = "ask.bubble.", timeout: TimeInterval = 6,
                                          file: StaticString = #filePath, line: UInt = #line) {
        let deadline = Date().addingTimeInterval(timeout)
        var seen = "no snapshot of the thread"
        repeat {
            if let snapshot = try? thread.snapshot() {
                let viewport = snapshot.frame
                let candidates = Self.elements(under: snapshot, prefix: prefix, inside: viewport)
                    .filter { candidate in !Self.actionSuffixes.contains { candidate.identifier.hasSuffix($0) } }
                if !candidates.isEmpty { return }
                seen = "no \(prefix)* element with content inside the thread's frame \(viewport)"
            }
            Thread.sleep(forTimeInterval: 0.25)
        } while Date() < deadline
        attachScreenshot(app, named: "thread-blank \(context)")
        XCTFail("The thread shows nothing \(context): \(seen)", file: file, line: line)
    }

    /// An answer's action buttons (`ChatBubble.actionsRow`).
    private static let actionSuffixes = [".speak", ".thumbsUp", ".thumbsDown", ".retry"]

    /// Depth-first search below `root` (never `root` itself) for elements whose identifier starts
    /// with `prefix` (never an answer's `.status` line), whose centre is inside `viewport`, with a
    /// label that isn't blank and a frame at least 8 pt each way.
    private static func elements(under root: XCUIElementSnapshot, prefix: String,
                                 inside viewport: CGRect) -> [XCUIElementSnapshot] {
        var found: [XCUIElementSnapshot] = []
        var stack = root.children
        while let node = stack.popLast() {
            let frame = node.frame
            if node.identifier.hasPrefix(prefix), !node.identifier.hasSuffix(".status"),
               frame.width >= 8, frame.height >= 8,
               !node.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               viewport.contains(CGPoint(x: frame.midX, y: frame.midY)) {
                found.append(node)
            }
            stack.append(contentsOf: node.children)
        }
        return found
    }

    /// Answer `n` is still streaming: its actions row is built (read-aloud shows once content has
    /// arrived), but its thumbs aren't there yet (they show only on a finished answer). This works
    /// with the keyboard up, when New chat, whose enabled state is the "finished" signal, has given
    /// way to Cancel. The streaming answer is always in the laid-out tail (task 1b), so its row is
    /// in the tree wherever the thread is scrolled.
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

    /// Answer `n`'s last line and actions row are both on screen: the thread shows its end. Polled
    /// for up to 3 s (a keyboard or a rotation animates).
    private func assertShowsTheEnd(of n: Int, question: String, _ app: XCUIApplication, _ thread: XCUIElement,
                                   _ context: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(waitUntilVisible(lastLine(app, question), in: thread),
                      "The answer's last line should be on screen \(context)", file: file, line: line)
        XCTAssertTrue(waitUntilVisible(element(app, "ask.bubble.\(n).thumbsUp"), in: thread),
                      "The answer's actions row should be on screen \(context)", file: file, line: line)
    }

    /// A drag down the thread by `fraction` of its height (content moves down, the reader goes up the
    /// thread), held at the end so it leaves no momentum.
    private func dragThreadDown(_ thread: XCUIElement, by fraction: CGFloat) {
        let from = thread.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
        let to = thread.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3 + fraction))
        from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.3)
    }

    /// The line of row `identifier` nearest the middle of the thread's frame (a text element of the
    /// row whose centre is inside it), from one snapshot: its label and frame.
    private func centredLine(of identifier: String, in thread: XCUIElement) -> (label: String, frame: CGRect)? {
        guard let snapshot = try? thread.snapshot() else { return nil }
        let middle = snapshot.frame.midY
        return Self.elements(under: snapshot, prefix: identifier, inside: snapshot.frame)
            .filter { $0.identifier == identifier }
            .min { abs($0.frame.midY - middle) < abs($1.frame.midY - middle) }
            .map { ($0.label, $0.frame) }
    }

    /// The frame of row `identifier`'s line labelled `label`, wherever it is, from one snapshot.
    private func frame(ofLine label: String, in identifier: String, thread: XCUIElement) -> CGRect? {
        guard let snapshot = try? thread.snapshot() else { return nil }
        var stack = snapshot.children
        while let node = stack.popLast() {
            if node.identifier == identifier, node.label == label { return node.frame }
            stack.append(contentsOf: node.children)
        }
        return nil
    }

    /// Some element of a row (identifier `prefix`, or `prefix.…`) is centred inside the thread's frame.
    private func showsPart(of prefix: String, in thread: XCUIElement) -> Bool {
        guard let snapshot = try? thread.snapshot() else { return false }
        return Self.elements(under: snapshot, prefix: prefix, inside: snapshot.frame).contains {
            $0.identifier == prefix || $0.identifier.hasPrefix(prefix + ".")
        }
    }

    /// `isVisible`, polled for up to `timeout`: a jump to the end of a thread just opened lands a
    /// few frames after its rows exist.
    private func waitUntilVisible(_ element: XCUIElement, in container: XCUIElement, timeout: TimeInterval = 3) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if isVisible(element, in: container) { return true }
            Thread.sleep(forTimeInterval: 0.25)
        } while Date() < deadline
        return isVisible(element, in: container)
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
