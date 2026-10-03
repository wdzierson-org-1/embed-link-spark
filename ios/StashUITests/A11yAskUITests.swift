import UIKit
import XCTest

/// Plan 16 Task 2d: the Ask tab's accessibility pass — the chat thread and its bubbles, the composer,
/// the header and the Conversations list.
///
/// - The screenshot matrix (`testAskScreensAtEveryTextSize`): every Ask screen at Large, xxxLarge, AX3
///   and Bold Text, attached as `a11y-2d-<screen>-<size>` (`a11y-2d-ios26-…` on iOS 26), with Xcode's
///   accessibility audit run on each (`A11Y audit …` lines; a finding not accepted below fails it).
/// - Controls take taps across 44 pt and say what they are; links in answers are underlined.
/// - The header doesn't jump when Cancel swaps in, at any size.
/// - Following (task 1c review, M-6): a scroll that isn't a drag — VoiceOver's, a status-bar tap —
///   leaves the end like a drag does, so streamed updates and the settle after an answer don't pull
///   the reader back.
/// - VoiceOver order (task 1b review, V5): with VoiceOver's layout every row is in the accessibility
///   tree, in order, so moving through the thread can't jump from the history to the laid-out tail.
///
/// Everything runs on `--uitest-scripted-chat` (local scripted answers and history; nothing reaches
/// the server).
final class A11yAskUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        MainActor.assumeIsolated { A11yScreens.restoreRealBoldTextIfLeftOn() }
    }

    // MARK: - Screenshot matrix

    /// Every Ask screen at the plan-16 matrix of text sizes, screenshotted and audited:
    /// - `ask-empty`: a new thread's welcome bubble and the composer;
    /// - `ask-answer`: a finished markdown answer (heading, strong and emphasised text, an inline
    ///   citation, a bulleted and a numbered list, a quote) with its uncited source as a chip;
    /// - `ask-composing`: the same with the composer focused — Cancel in the header, the keyboard up;
    /// - `conversations` and `conversations-search` (a query typed, the clear button showing);
    /// - `ask-long-thread`: a long restored thread of prose answers, at its end.
    @MainActor
    func testAskScreensAtEveryTextSize() throws {
        continueAfterFailure = true   // shoot and audit every screen, report every finding
        let screens = A11yScreens(self)
        try screens.signIn()
        var findings: [String] = []
        for variant in A11yVariant.matrix {
            var app = screens.launch(variant, tab: .ask, arguments: ["--uitest-scripted-chat"])
            XCTAssertTrue(Self.element(app, "ask.emptyState").waitForExistence(timeout: 10), "\(variant): no welcome bubble")
            sleep(1)
            shoot(screens, "ask-empty")
            findings += Self.audit(app, screen: "ask-empty", variant: variant)

            app = screens.launch(variant, tab: .ask, arguments: ["--uitest-scripted-chat", "--uitest-scripted-long-thread",
                                                                 "--uitest-seed-markdown-answer"])
            // The seed replaces the restored long thread once it has loaded.
            XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label == %@", "Feeding schedule")).firstMatch
                .waitForExistence(timeout: 10), "\(variant): the seeded answer didn't show")
            XCTAssertTrue(Self.element(app, "ask.bubble.1.thumbsUp").waitForExistence(timeout: 5),
                          "\(variant): the seeded answer has no actions")
            sleep(2)
            shoot(screens, "ask-answer")
            findings += Self.audit(app, screen: "ask-answer", variant: variant)

            let input = Self.element(app, "ask.input")
            A11yScreens.tapUntilFocused(input)
            input.typeText("What else did I save about bread?")
            let cancel = app.buttons["ask.dismissKeyboard"]
            XCTAssertTrue(cancel.waitForExistence(timeout: 5), "\(variant): no Cancel while composing")
            sleep(1)
            shoot(screens, "ask-composing")
            findings += Self.audit(app, screen: "ask-composing", variant: variant)

            cancel.tap()
            let history = app.buttons["ask.history"]
            XCTAssertTrue(history.waitForExistence(timeout: 5), "\(variant): History didn't come back")
            history.tap()
            XCTAssertTrue(Self.element(app, "convos.row.1").waitForExistence(timeout: 10), "\(variant): Conversations didn't list")
            sleep(1)
            shoot(screens, "conversations")
            findings += Self.audit(app, screen: "conversations", variant: variant)

            let search = app.textFields["convos.search"]
            A11yScreens.tapUntilFocused(search)
            search.typeText("conversation")
            XCTAssertTrue(app.buttons["convos.search.clear"].waitForExistence(timeout: 5), "\(variant): no clear button")
            sleep(2)   // the debounced search
            shoot(screens, "conversations-search")
            findings += Self.audit(app, screen: "conversations-search", variant: variant)

            app = screens.launch(variant, tab: .ask, arguments: ["--uitest-scripted-chat", "--uitest-scripted-long-thread",
                                                                 "--uitest-scripted-prose"])
            let thread = app.scrollViews["ask.thread"]
            XCTAssertTrue(Self.element(app, "ask.bubble.15.thumbsUp").waitForExistence(timeout: 10),
                          "\(variant): the long thread didn't load")
            XCTAssertTrue(Self.waitUntil(timeout: 3) {
                Self.isVisible(Self.element(app, "ask.bubble.15.thumbsUp"), in: thread)
            }, "\(variant): the long thread should open at its end")
            sleep(2)
            shoot(screens, "ask-long-thread")
            findings += Self.audit(app, screen: "ask-long-thread", variant: variant)
        }
        let unaccepted = findings.filter { !Self.isAccepted($0) }
        XCTAssertTrue(unaccepted.isEmpty, "Accessibility audit findings:\n" + unaccepted.joined(separator: "\n"))
    }

    /// The matrix's contrast gate (task 2d review, M-4): a finding on a named element passes only when the
    /// screen's own pixels measure 4.5:1 or more in its frame, or when it's a row of the thread scrolled
    /// wholly out of the thread's frame (judged by geometry in `audit`). A faint text measures low too, so
    /// a low measurement is never taken for "no text there". Launches no app.
    func testTheContrastGateNeverPassesFaintText() {
        let named = "ask-answer L | Contrast failed | id=ask.bubble.1 label=\"Your starter notes\" frame=(28.0, 300.0, 300.0, 22.0)"
        XCTAssertFalse(Self.isAccepted(named + " | measured 1.40"), "A 1.4:1 text on screen must fail the audit")
        XCTAssertFalse(Self.isAccepted(named + " | measured 4.40"), "A 4.4:1 text must fail the audit")
        XCTAssertFalse(Self.isAccepted(named + " | measured none"), "A finding that couldn't be measured must fail the audit")
        XCTAssertTrue(Self.isAccepted(named + " | measured 4.64"), "A 4.64:1 text passes")
        XCTAssertTrue(Self.isAccepted("ask-long-thread L-bold | Contrast failed | id=ask.bubble.14 label=\"Long question 8\" "
                                      + "frame=(243.0, 109.0, 120.0, 21.0) | outside the thread"),
                      "A row scrolled under the header shows nothing of its own to measure")
    }

    /// The long prose thread at the smallest text size, on the largest phone (run it on the Pro Max):
    /// the tail's height budget at its widest, landed on the last line.
    @MainActor
    func testTheLongThreadAtExtraSmall() throws {
        let screens = A11yScreens(self)
        try screens.signIn()
        let extraSmall = A11yVariant(category: "UICTContentSizeCategoryXS", token: "xS")
        let app = screens.launch(extraSmall, tab: .ask, arguments: ["--uitest-scripted-chat", "--uitest-scripted-long-thread",
                                                                    "--uitest-scripted-prose"])
        let thread = app.scrollViews["ask.thread"]
        XCTAssertTrue(Self.element(app, "ask.bubble.15.thumbsUp").waitForExistence(timeout: 10), "The long thread didn't load")
        XCTAssertTrue(Self.waitUntilVisible(Self.lastLine(app, "Long question 8"), in: thread),
                      "The long thread should open on its last line")
        XCTAssertTrue(Self.waitUntilVisible(Self.element(app, "ask.bubble.15.thumbsUp"), in: thread),
                      "The long thread should open on its last answer's actions")
        sleep(2)
        shoot(screens, "ask-long-thread")
    }

    // MARK: - Controls and links

    /// Every control on an answer, the composer and the Conversations search takes taps across at least
    /// 44 × 44 pt (an icon control's accessibility frame is its target) and says what it is (items 4, 5
    /// and 10). An answer's read-aloud and thumbs are 44 pt apart centre to centre (they were 19 × 14 and
    /// 16 × 17 pt, 26–32 pt apart); a given thumb reads as selected, and neither can be given again. A tap
    /// on the composer pill's padding — outside the field's own text line — focuses the field, and so does
    /// one on the Conversations search pill's. The search's clear button clears it.
    @MainActor
    func testAskControlsTakeTapsAcross44Points() throws {
        let screens = A11yScreens(self)
        try screens.signIn()
        let app = screens.launch(.large, tab: .ask, arguments: ["--uitest-scripted-chat", "--uitest-seed-markdown-answer"])
        let speak = app.buttons["ask.bubble.1.speak"]
        let up = app.buttons["ask.bubble.1.thumbsUp"]
        let down = app.buttons["ask.bubble.1.thumbsDown"]
        XCTAssertTrue(up.waitForExistence(timeout: 10), "The seeded answer has no thumbs")
        sleep(1)
        for (control, name) in [(speak, "Read aloud"), (up, "Helpful"), (down, "Not helpful")] {
            Self.assertTarget(control, name)
            XCTAssertEqual(control.label, name, "\(name): its VoiceOver name")
        }
        XCTAssertGreaterThanOrEqual(up.frame.midX - speak.frame.midX, 43.5, "Read aloud and Helpful are closer than 44 pt")
        XCTAssertGreaterThanOrEqual(down.frame.midX - up.frame.midX, 43.5, "Helpful and Not helpful are closer than 44 pt")
        XCTAssertFalse(up.isSelected, "No thumb is given yet")
        up.tap()
        XCTAssertTrue(Self.waitUntil(timeout: 3) { up.isSelected }, "A given thumb should read as selected")
        XCTAssertFalse(up.isEnabled || down.isEnabled, "Neither thumb can be given again")
        XCTAssertFalse(down.isSelected, "The thumb not given shouldn't read as selected")

        let send = app.buttons["ask.send"]
        Self.assertTarget(send, "Send")
        XCTAssertEqual(send.label, "Send", "Send: its VoiceOver name")
        // 6 pt above the field's own line: inside the pill's 10 pt padding.
        let input = Self.element(app, "ask.input")
        A11yScreens.tap(app, at: CGPoint(x: input.frame.minX + 30, y: input.frame.minY - 6))
        let cancel = app.buttons["ask.dismissKeyboard"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5), "A tap on the composer pill's padding should focus the field")
        cancel.tap()

        let history = app.buttons["ask.history"]
        XCTAssertTrue(history.waitForExistence(timeout: 5), "History didn't come back")
        history.tap()
        let search = app.textFields["convos.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 10), "No Conversations search")
        sleep(1)
        // 6 pt above the field's own line, inside the 44 pt pill (task 2d review, M-1): the band the pill's
        // padding ring used to leave dead, between the field's own touch area (up to 4 pt out, iOS 26.5) and
        // the ring (7 pt out and beyond, from the pill's 4 pt padding).
        A11yScreens.tap(app, at: CGPoint(x: search.frame.minX + 30, y: search.frame.minY - 6))
        let searchFocused = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hasKeyboardFocus == true"), object: search)
        XCTAssertEqual(XCTWaiter().wait(for: [searchFocused], timeout: 3), .completed,
                       "A tap on the search pill's padding should focus the field")
        A11yScreens.tapUntilFocused(search)
        search.typeText("conversation")
        let clear = app.buttons["convos.search.clear"]
        XCTAssertTrue(clear.waitForExistence(timeout: 5), "No clear button while the search has text")
        Self.assertTarget(clear, "Clear search")
        XCTAssertEqual(clear.label, "Clear search", "Clear: its VoiceOver name")
        clear.tap()
        XCTAssertTrue(Self.waitUntil(timeout: 3) { !clear.exists }, "Clear should empty the search")
    }

    /// WCAG 1.4.1, Use of Color (coordinator, from the 2b review): a link in an answer's text — an inline
    /// citation — is underlined, as in the detail sheet, since colour alone can't mark it (violet-600 is
    /// 2.93:1 against ink body text). Checked in the pixels at Large and with Bold Text: under "starter
    /// notes" in the seeded answer runs a line in the shared underline violet (`stashLinkUnderline`:
    /// violet-600 at 80 % over the answer's #f2f2f7, ≈ #8879d8, 3.26:1), far longer than any stroke edge
    /// of a violet glyph.
    @MainActor
    func testLinksInAnswersAreUnderlined() throws {
        let screens = A11yScreens(self)
        try screens.signIn()
        var failures: [String] = []
        for variant in [A11yVariant.large, .largeBold] {
            let app = screens.launch(variant, tab: .ask, arguments: ["--uitest-scripted-chat", "--uitest-seed-markdown-answer"])
            let paragraph = app.descendants(matching: .any)
                .matching(NSPredicate(format: "identifier == %@ AND label BEGINSWITH %@", "ask.bubble.1", "Your starter notes"))
                .firstMatch
            XCTAssertTrue(paragraph.waitForExistence(timeout: 10), "\(variant): the seeded answer didn't show")
            sleep(1)
            guard let pixels = AskScreenPixels(XCUIScreen.main.screenshot(), pointWidth: app.frame.width) else {
                XCTFail("\(variant): no screenshot pixels")
                continue
            }
            let run = pixels.longestRun(in: paragraph.frame, where: AskScreenPixels.isLinkUnderline)
            print("A11Y underline \(variant): paragraph \(paragraph.frame) · longest underline-colour run "
                  + "\(String(format: "%.1f", run.points)) pt at y \(String(format: "%.1f", run.y))")
            if run.points < 30 {
                failures.append("\(variant): longest underline-colour run \(String(format: "%.1f", run.points)) pt")
            }
        }
        XCTAssertTrue(failures.isEmpty, "Links in answers should be underlined:\n" + failures.joined(separator: "\n"))
    }

    // MARK: - The header

    /// Cancel swapping in for New chat and History moves nothing below the header — the thread's top
    /// stays put — at the default size, the largest standard size, and two accessibility sizes (the
    /// title wraps differently at each). Cancel is one line holding the whole word, and at the default
    /// size the circles are where they always were (16 pt from the edge, 44 pt apart).
    @MainActor
    func testTheHeaderNeverJumpsWhenCancelSwapsIn() throws {
        continueAfterFailure = true
        let screens = A11yScreens(self)
        try screens.signIn()
        for variant in [A11yVariant.large, .xxxLarge, .ax3, .ax5] {
            let app = screens.launch(variant, tab: .ask, arguments: ["--uitest-scripted-chat"])
            let thread = app.scrollViews["ask.thread"]
            let history = app.buttons["ask.history"]
            let newChat = app.buttons["ask.newChat"]
            XCTAssertTrue(history.waitForExistence(timeout: 10), "\(variant): History missing")
            let resting = thread.frame.minY
            if variant == .large {
                XCTAssertEqual(app.frame.maxX - history.frame.midX, 16 + 18, accuracy: 0.5, "History moved from the edge")
                XCTAssertEqual(history.frame.midX - newChat.frame.midX, 44, accuracy: 0.5, "The circles moved apart")
            }
            let input = Self.element(app, "ask.input")
            A11yScreens.tapUntilFocused(input)
            let cancel = app.buttons["ask.dismissKeyboard"]
            XCTAssertTrue(cancel.waitForExistence(timeout: 5), "\(variant): no Cancel while composing")
            sleep(1)
            let composing = thread.frame.minY
            let em = UIFontMetrics(forTextStyle: .body).scaledValue(for: 17, compatibleWith: variant.traits)
            print("A11Y header \(variant): thread top resting=\(resting) composing=\(composing) cancel=\(cancel.frame) em=\(em)")
            XCTAssertEqual(composing, resting, accuracy: 0.5, "\(variant): the header changed height when Cancel swapped in")
            XCTAssertLessThan(cancel.frame.height, max(44, 1.7 * em) + 0.5, "\(variant): Cancel wrapped")
            XCTAssertGreaterThan(cancel.frame.width, 2.4 * em, "\(variant): Cancel is narrower than its word")
            screens.attachScreenshot(named: "2d-\(Self.osTag)header-composing")
            cancel.tap()
            XCTAssertTrue(history.waitForExistence(timeout: 5), "\(variant): History didn't come back")
            XCTAssertEqual(thread.frame.minY, resting, accuracy: 0.5, "\(variant): the header changed height when Cancel went")
        }
    }

    // MARK: - Following: scrolls that aren't drags (task 1c review, M-6)

    /// A status-bar tap while an answer streams takes the reader to the top of the thread, and they
    /// stay there: through the rest of the answer and the settle after it. The thread used to keep
    /// following — only a drag turned that off — so the next streamed update pinned it back to the
    /// end within a tenth of a second. First, at rest, a control: the tap does reach the thread.
    ///
    /// Each tap is a cut to the top — the thread's own jump to a laid-out target — and UIKit never animates
    /// it (task 2d fix round 1, C-1): on iOS 26.5, UIKit's animated scroll through the lazy history, while an
    /// answer grew below, stopped the app's main thread for minutes now and then. The DEBUG scroll log
    /// (`--uitest-scroll-log`) counts the frames of scrolls UIKit animated that the thread didn't start, and
    /// the cuts. One tap each, never a second try: a tap the thread absorbs is the bug (task 2d review, M-4).
    @MainActor
    func testAStatusBarTapWhileAnAnswerStreamsLeavesTheEnd() throws {
        let screens = A11yScreens(self)
        try screens.signIn()
        let app = screens.launch(.large, tab: .ask, arguments: ["--uitest-scripted-chat", "--uitest-scripted-long-thread",
                                                                "--uitest-scroll-log"])
        let thread = app.scrollViews["ask.thread"]
        XCTAssertTrue(thread.waitForExistence(timeout: 10), "Ask thread did not appear")
        XCTAssertTrue(Self.element(app, "ask.bubble.15.thumbsUp").waitForExistence(timeout: 10), "The long thread should load")
        let scrollLog = Self.element(app, "ask.debug.scrollLog")
        XCTAssertTrue(scrollLog.waitForExistence(timeout: 5), "The DEBUG scroll log is missing")
        sleep(2)
        let top = Self.element(app, "ask.bubble.0")
        Self.tapStatusBar(app)
        XCTAssertTrue(Self.waitUntilVisible(top, in: thread, timeout: 5),
                      "Control: at rest, a status-bar tap should scroll the thread to its top")
        XCTAssertEqual(scrollLog.label, "animated 0 · cut 1",
                       "At rest, a status-bar tap should cut the thread to its top, never animate through it")

        let answer = try startAnAnswerFromTheEnd(app, thread, question: "Status bar question")
        XCTAssertTrue(leaveTheEnd({ Self.tapStatusBar(app) }, timeout: 5, left: { Self.isVisible(top, in: thread) }),
                      "A status-bar tap should scroll the thread to its top")
        XCTAssertEqual(scrollLog.label, "animated 0 · cut 2",
                       "While an answer streams, a status-bar tap should cut the thread to its top, never animate through it")
        XCTAssertTrue(Self.isStreaming(app, answer: answer), "The status-bar tap must land while the answer streams")
        sleep(3)   // a dozen streamed updates
        XCTAssertTrue(Self.isVisible(top, in: thread),
                      "The streaming answer pulled the reader back to the end after a status-bar tap")
        XCTAssertTrue(Self.waitUntilEnabled(app.buttons["ask.newChat"], timeout: 20), "The answer never completed")
        sleep(2)   // past the completion's settle pins
        XCTAssertTrue(Self.isVisible(top, in: thread),
                      "The settle after the answer pulled the reader back to the end after a status-bar tap")
    }

    /// VoiceOver's three-finger swipe while an answer streams scrolls the thread up a page, and the
    /// reader stays there: the answer streams on below without moving what they read. Back at the end
    /// (VoiceOver moving its focus there), they follow the answer again. XCUITest can't make an
    /// accessibility scroll, so DEBUG controls (`--uitest-a11y-hooks`) scroll the thread's scroll view
    /// as VoiceOver does — UIKit's own `accessibilityScroll(.up)`, or its animated page when that isn't
    /// loaded (no assistive technology runs on the Simulator) — never a drag.
    @MainActor
    func testAVoiceOverScrollUpWhileAnAnswerStreamsLeavesTheEnd() throws {
        let screens = A11yScreens(self)
        try screens.signIn()
        // `--uitest-scripted-slow`: a 23 s answer, room for the slow snapshots below while it streams.
        let app = screens.launch(.large, tab: .ask, arguments: ["--uitest-scripted-chat", "--uitest-scripted-long-thread",
                                                                "--uitest-scripted-slow", "--uitest-a11y-hooks"])
        let thread = app.scrollViews["ask.thread"]
        XCTAssertTrue(thread.waitForExistence(timeout: 10), "Ask thread did not appear")
        XCTAssertTrue(Self.element(app, "ask.bubble.15.thumbsUp").waitForExistence(timeout: 10), "The long thread should load")
        sleep(2)
        let answer = try startAnAnswerFromTheEnd(app, thread, question: "VoiceOver question")
        let streamingEnd = app.buttons["ask.bubble.\(answer).speak"]   // the streaming answer's actions row
        let scrollUp = app.buttons["ask.debug.voiceOverScrollUp"]
        let scrollToEnd = app.buttons["ask.debug.voiceOverScrollToEnd"]
        XCTAssertTrue(scrollUp.exists && scrollToEnd.exists, "The DEBUG accessibility-scroll controls are missing")

        XCTAssertTrue(leaveTheEnd({ scrollUp.tap() }, timeout: 3, left: { !Self.isVisible(streamingEnd, in: thread) }),
                      "An accessibility scroll up should move the thread off its end")
        usleep(500_000)   // the page scroll's animation
        XCTAssertTrue(Self.isStreaming(app, answer: answer), "The scroll must land while the answer streams")
        let reading = try XCTUnwrap(Self.centredLine(of: "ask.bubble.", in: thread),
                                    "The page scroll should land on the thread's text")
        sleep(2)   // four streamed updates
        XCTAssertFalse(Self.isVisible(streamingEnd, in: thread),
                       "The streaming answer pulled the reader back to the end after VoiceOver scrolled up")
        let now = Self.frame(ofLine: reading.label, in: reading.identifier, thread: thread)
        XCTContext.runActivity(named: "Reading \"\(reading.label)\" at y \(reading.frame.minY), then \(now.map { "\($0.minY)" } ?? "gone")") { _ in }
        XCTAssertEqual(now?.minY ?? .infinity, reading.frame.minY, accuracy: 2,
                       "The line a VoiceOver reader had scrolled to moved while the answer streamed below it")

        // VoiceOver moving its focus to the end of the thread scrolls it there — not a drag either.
        scrollToEnd.tap()
        XCTAssertTrue(Self.waitUntil(timeout: 2) { Self.isVisible(streamingEnd, in: thread) },
                      "Scrolling to the end should reach the end")
        XCTAssertTrue(Self.isStreaming(app, answer: answer), "Back at the end while the answer still streams")
        sleep(2)
        XCTAssertTrue(Self.isVisible(streamingEnd, in: thread),
                      "Back at the end without a drag, the reader should follow the answer again")
        XCTAssertTrue(Self.waitUntilEnabled(app.buttons["ask.newChat"], timeout: 20), "The answer never completed")
        sleep(2)
        XCTAssertTrue(Self.isVisible(app.buttons["ask.bubble.\(answer).thumbsUp"], in: thread),
                      "Following again, the thread should end on the finished answer's actions")
    }

    // MARK: - VoiceOver order (task 1b review, V5)

    /// VoiceOver moves through the thread in the order of the accessibility tree, scrolling each
    /// element into view. The history is a lazy stack, which has only the rows near the screen in the
    /// tree, while the laid-out tail is always there after it: from the last row the history had built,
    /// the next element was the tail, past every row in between (measured: with an answer's last
    /// element at the thread's bottom edge, the next question wasn't always built). While VoiceOver or
    /// Switch Control runs every row is laid out — `--uitest-assistive-layout` stands in for them here —
    /// so at the top of a long thread every row is in the tree, in order.
    @MainActor
    func testWithVoiceOversLayoutEveryRowIsInTheTreeInOrder() throws {
        let screens = A11yScreens(self)
        try screens.signIn()
        let app = screens.launch(.large, tab: .ask, arguments: ["--uitest-scripted-chat", "--uitest-scripted-long-thread",
                                                                "--uitest-scripted-prose", "--uitest-assistive-layout"])
        let thread = app.scrollViews["ask.thread"]
        XCTAssertTrue(thread.waitForExistence(timeout: 10), "Ask thread did not appear")
        XCTAssertTrue(Self.element(app, "ask.bubble.15.thumbsUp").waitForExistence(timeout: 10), "The long thread should load")
        XCTAssertTrue(Self.waitUntilVisible(Self.lastLine(app, "Long question 8"), in: thread),
                      "The long thread should open at its end")
        sleep(2)
        let first = Self.element(app, "ask.bubble.0")
        for _ in 0..<20 where !Self.isVisible(first, in: thread) {
            thread.swipeDown()
        }
        XCTAssertTrue(Self.waitUntilVisible(first, in: thread), "Couldn't reach the top of the long thread")
        sleep(1)
        let rows = try Self.rowsInTreeOrder(thread)
        print("A11Y order rows in the tree at the top: \(rows)")
        XCTAssertEqual(rows, Array(0...15), "At the top of the thread, every row should be in the tree, in order")
    }

    // MARK: - The streaming cursor (item 8)

    /// Evidence for the stray cursor (export-time): a burst of screenshots while an answer streams after a
    /// send from far up the long thread, keyboard up (`t1b-after-26.5-send-from-far-up-following.png`).
    @MainActor
    func testStreamingCursorBurst() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["A11Y_CURSOR_BURST"] == "1",
                          "Evidence probe: run alone with TEST_RUNNER_A11Y_CURSOR_BURST=1")
        let screens = A11yScreens(self)
        try screens.signIn()
        let app = screens.launch(.large, tab: .ask, arguments: ["--uitest-scripted-chat", "--uitest-scripted-long-thread"])
        let thread = app.scrollViews["ask.thread"]
        XCTAssertTrue(Self.element(app, "ask.bubble.15.thumbsUp").waitForExistence(timeout: 10), "The long thread should load")
        sleep(1)
        for _ in 0..<3 { thread.swipeDown() }
        Self.ask(app, "Cursor question")
        XCTAssertTrue(Self.element(app, "ask.bubble.17.speak").waitForExistence(timeout: 10), "The answer never started")
        for shot in 0..<24 {
            let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            attachment.name = "cursor-burst-\(String(format: "%02d", shot))"
            attachment.lifetime = .keepAlways
            add(attachment)
            usleep(200_000)
        }
    }

    // MARK: - Helpers

    /// Sends a question with the keyboard up (the thread jumps to its end and follows), waits for the
    /// answer to start, and puts the keyboard away with Cancel: the reader follows a streaming answer
    /// at the end of the long thread. Returns the new answer's row index.
    @MainActor
    private func startAnAnswerFromTheEnd(_ app: XCUIApplication, _ thread: XCUIElement, question: String,
                                         file: StaticString = #filePath, line: UInt = #line) throws -> Int {
        let newChat = app.buttons["ask.newChat"]
        XCTAssertTrue(newChat.waitForExistence(timeout: 5), "New chat missing", file: file, line: line)
        Self.ask(app, question)
        let answer = 17
        XCTAssertTrue(Self.element(app, "ask.bubble.\(answer).speak").waitForExistence(timeout: 10),
                      "The answer never started", file: file, line: line)
        let cancel = app.buttons["ask.dismissKeyboard"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5), "Expected Cancel while composing", file: file, line: line)
        cancel.tap()
        XCTAssertTrue(newChat.waitForExistence(timeout: 5), "The circles should be back", file: file, line: line)
        sleep(1)
        XCTAssertTrue(Self.isStreaming(app, answer: answer), "The answer should still be streaming", file: file, line: line)
        XCTAssertTrue(Self.isVisible(app.buttons["ask.bubble.\(answer).speak"], in: thread),
                      "The reader should be following the answer", file: file, line: line)
        return answer
    }

    /// Makes a scroll that isn't a drag from the end of a streaming answer — once — and waits until `left`
    /// holds. Never a second try (task 2d review, M-4): a scroll the thread absorbs, a hold landing between
    /// its start and its first frame, leaves the reader at the end as surely as a pull back does, and both
    /// are the bug.
    @MainActor
    private func leaveTheEnd(_ scroll: () -> Void, timeout: TimeInterval, left: () -> Bool) -> Bool {
        scroll()
        return Self.waitUntil(timeout: timeout, left)
    }

    /// The tag this OS's screenshots carry after `2d-`.
    private static var osTag: String {
        ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26 ? "ios26-" : ""
    }

    @MainActor
    private func shoot(_ screens: A11yScreens, _ screen: String) {
        screens.attachScreenshot(named: "2d-\(Self.osTag)\(screen)")
    }

    /// Xcode's hit-region, Dynamic Type, contrast and clipped-text audit of the screen on show, each
    /// finding logged (`A11Y audit …`) and returned as one line. A contrast finding carries the contrast
    /// measured in the screen's own pixels inside the flagged element's frame (`| measured …`; see
    /// `isAccepted`) — unless the element is a row of the thread whose frame lies wholly outside the thread's
    /// frame (`| outside the thread`): it's scrolled under the header or the composer, and what its frame
    /// shows on screen is theirs, not its text.
    ///
    /// Both are worked out once the audit is over (the handler runs inside the audit's time limit), from a
    /// screenshot and a snapshot of the app taken together: each flagged element is found again in the
    /// snapshot by its identifier and label, and judged where it is then. The frames the audit itself reports
    /// can be off what the screen shows before or after it (task 2d fix round 1: iOS 17.5's long thread, a
    /// question reported 39 pt above where it's drawn, so a screenshot from before the audit showed nothing in
    /// its frame — read as "no text" before M-4). Several matches: the best-measured one. None: the audit's
    /// own frame, in that screenshot.
    ///
    /// An audit that doesn't complete is tried once more, then returned as a finding of its own (never
    /// accepted) — so the matrix still shoots and audits every other screen.
    @MainActor
    private static func audit(_ app: XCUIApplication, screen: String, variant: A11yVariant) -> [String] {
        var failure = ""
        for attempt in 1...2 {
            var found: [(line: String, contrast: (identifier: String, label: String, frame: CGRect?)?)] = []
            do {
                try app.performAccessibilityAudit(for: [.hitRegion, .dynamicType, .contrast, .textClipped]) { issue in
                    let element = issue.element
                    let frame = element?.frame
                    let fullLabel = element?.label ?? ""
                    let label = String(fullLabel.prefix(48)).replacingOccurrences(of: "\n", with: " ")
                    let line = "\(screen) \(variant) | \(issue.compactDescription) | id=\(element?.identifier ?? "-") "
                        + "label=\"\(label)\" frame=\(frame.map { "\($0.integral)" } ?? "-")"
                    found.append((line, issue.auditType == .contrast ? (element?.identifier ?? "", fullLabel, frame) : nil))
                    return true
                }
            } catch {
                failure = "\(error.localizedDescription)"
                print("A11Y audit \(screen) \(variant) | attempt \(attempt) didn't complete: \(failure)")
                sleep(3)
                continue
            }
            let measures = found.contains { $0.contrast != nil }
            if measures { usleep(500_000) }   // the screen settles from whatever the audit did to it
            let pixels = measures ? AskScreenPixels(XCUIScreen.main.screenshot(), pointWidth: app.frame.width) : nil
            let snapshot = measures ? try? app.snapshot() : nil
            let thread = app.scrollViews["ask.thread"]
            let threadFrame = measures && thread.exists ? thread.frame : nil
            return found.map { finding in
                var line = finding.line
                if let contrast = finding.contrast {
                    let now = snapshot.map { Self.frames(in: $0, identifier: contrast.identifier, label: contrast.label) } ?? []
                    let frames = now.isEmpty ? [contrast.frame].compactMap { $0 } : now
                    if let threadFrame, contrast.identifier.hasPrefix("ask.bubble."), !frames.isEmpty,
                       frames.allSatisfy({ !$0.isEmpty && !$0.intersects(threadFrame) }) {
                        line += " | outside the thread"
                    } else {
                        let measured = frames.compactMap { pixels?.contrast(in: $0) }.max()
                        line += " | measured " + (measured.map { String(format: "%.2f", $0) } ?? "none")
                            + (now.isEmpty ? "" : " now at \(frames.map { "\($0.integral)" }.joined(separator: ", "))")
                    }
                }
                print("A11Y audit \(line)")
                return line
            }
        }
        return ["\(screen) \(variant) | Audit did not complete | \(failure)"]
    }

    /// The frames of the elements in `snapshot` with `identifier` and `label`.
    private static func frames(in snapshot: XCUIElementSnapshot, identifier: String, label: String) -> [CGRect] {
        var frames: [CGRect] = []
        var stack = [snapshot]
        while let node = stack.popLast() {
            if node.identifier == identifier, node.label == label { frames.append(node.frame) }
            stack.append(contentsOf: node.children)
        }
        return frames
    }

    /// Audit findings accepted, with the reason (the task 2d report has the evidence). Everything else —
    /// any hit-region finding, a contrast finding the pixels confirm, Dynamic Type or clipped text on any
    /// named element of the Ask tab, an audit that didn't complete — fails the matrix.
    /// - Contrast, where the screen's own pixels inside the flagged frame — its darkest against its
    ///   lightest — pass AA (4.5:1). Xcode's check flags text whose real colours pass: `muted` dates and
    ///   section labels on white (5.38:1), a question's white on violet-600 (5.18:1), text partly under the
    ///   header or the floating tab bar. Also where the element is a row of the thread scrolled wholly out
    ///   of the thread's frame, under the header's paper (`| outside the thread`, judged by geometry — a
    ///   low measurement alone is never taken for "no text": a faint text measures low too), and where the
    ///   audit names no element at all (nothing to measure; every element it names is measured).
    /// - Clipped text and "Dynamic Type partially unsupported" on a Conversations row's own texts (no
    ///   identifier): iOS 17's audit flags every text of a row whose one-line preview is cut short — the
    ///   designed clamp at the standard sizes (a row is one line of title and one of preview, as before
    ///   plan 16), lifted at the accessibility sizes, where both wrap to three lines.
    /// - Clipped text on the Conversations search field's own line (a single-line field, the audit's own
    ///   line-height arithmetic; nothing is cut in any shot), and on elements it can't name: two on the
    ///   Conversations screen at the standard sizes (not the search field's prompt — a probe without it
    ///   kept them), and now and then one elsewhere; nothing is cut in any shot.
    /// - On an Ask screen, the one Dynamic Type finding iOS 17's audit can't name ("partially
    ///   unsupported" up to xxxLarge, "unsupported" at AX3): the header's "Chat with your Stash", which
    ///   visibly scales (22 → 27 → 41 pt in the shots). An export-only probe removed the finding by
    ///   removing the title and nothing else (not the composer, its prompt, the circles' or Send's Large
    ///   Content Viewer, the header's sizing views or heading trait); the title in HEAD's own font still
    ///   drew it. The header reflows at the accessibility sizes, and the audit's size probe seems to lose
    ///   the title there.
    private static func isAccepted(_ finding: String) -> Bool {
        let unnamed = finding.contains("| id=- ")
        let conversationsRowText = finding.hasPrefix("conversations") && finding.contains("| id= ")
        if finding.contains("| Contrast failed |") {
            // No element, so nothing to measure (1 run in 3, Conversations at AX3 on iOS 17.5): accepted
            // because every element the audit can name is measured here, and every informational text
            // on these screens measures 4.6:1 or more in the shots (the task 2d report's table).
            if unnamed || finding.hasSuffix("| outside the thread") { return true }
            guard let marker = finding.range(of: "| measured "),
                  let measured = Double(finding[marker.upperBound...].prefix { $0.isNumber || $0 == "." })
            else { return false }
            return measured >= 4.5
        }
        if finding.contains("| Text clipped |") {
            return unnamed || conversationsRowText || finding.contains("| id=convos.search ")
        }
        if finding.contains("| Dynamic Type font sizes are partially unsupported |")
            || finding.contains("| Dynamic Type font sizes are unsupported |") {
            return (unnamed && finding.hasPrefix("ask-")) || conversationsRowText
        }
        return false
    }

    /// A control's target: at least 44 × 44 pt (43.5: iOS 26.5 reports 44 as 43.99999999999994).
    @MainActor
    private static func assertTarget(_ control: XCUIElement, _ name: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(control.exists, "\(name) is missing", file: file, line: line)
        let frame = control.frame
        print("A11Y target \(name): \(frame)")
        XCTAssertGreaterThanOrEqual(frame.width, 43.5, "\(name) takes taps across less than 44 pt (\(frame))", file: file, line: line)
        XCTAssertGreaterThanOrEqual(frame.height, 43.5, "\(name) takes taps across less than 44 pt (\(frame))", file: file, line: line)
    }

    /// The thread's rows (`ask.bubble.<n>`), in the accessibility tree's order — VoiceOver's — each once.
    @MainActor
    private static func rowsInTreeOrder(_ thread: XCUIElement) throws -> [Int] {
        let snapshot = try thread.snapshot()
        var rows: [Int] = []
        func visit(_ node: XCUIElementSnapshot) {
            let id = node.identifier
            if id.hasPrefix("ask.bubble."), let row = Int(id.dropFirst("ask.bubble.".count)), rows.last != row {
                rows.append(row)
            }
            node.children.forEach(visit)
        }
        snapshot.children.forEach(visit)
        return rows
    }

    @MainActor
    static func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// Types `question` and sends it the way a user does: the composer keeps focus.
    @MainActor
    static func ask(_ app: XCUIApplication, _ question: String) {
        let input = element(app, "ask.input")
        A11yScreens.tapUntilFocused(input)
        input.typeText(question)
        let send = app.buttons["ask.send"]
        XCTAssertTrue(send.waitForExistence(timeout: 5), "Send button not found")
        send.tap()
    }

    /// Answer `n` has started (its read-aloud button exists) and hasn't finished (no thumbs yet).
    @MainActor
    static func isStreaming(_ app: XCUIApplication, answer n: Int) -> Bool {
        element(app, "ask.bubble.\(n).speak").exists && !element(app, "ask.bubble.\(n).thumbsUp").exists
    }

    /// The scripted answer's closing paragraph (`ScriptedChatStreamer`).
    @MainActor
    static func lastLine(_ app: XCUIApplication, _ question: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label == %@", "End of the scripted answer to: \(question)")).firstMatch
    }

    /// Entirely inside `container`'s frame (1 pt tolerance). Laid-out rows exist off screen, so
    /// `exists` alone proves nothing.
    @MainActor
    static func isVisible(_ element: XCUIElement, in container: XCUIElement) -> Bool {
        guard element.exists else { return false }
        let frame = element.frame
        let viewport = container.frame
        return !frame.isEmpty && frame.minY >= viewport.minY - 1 && frame.maxY <= viewport.maxY + 1
    }

    @MainActor
    static func waitUntilVisible(_ element: XCUIElement, in container: XCUIElement, timeout: TimeInterval = 3) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if isVisible(element, in: container) { return true }
            Thread.sleep(forTimeInterval: 0.25)
        } while Date() < deadline
        return isVisible(element, in: container)
    }

    @MainActor
    static func waitUntil(timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if condition() { return true }
            Thread.sleep(forTimeInterval: 0.2)
        } while Date() < deadline
        return condition()
    }

    @MainActor
    static func waitUntilEnabled(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: element)
        return XCTWaiter().wait(for: [enabled], timeout: timeout) == .completed
    }

    /// A tap on the status bar (iOS: the scroll view under it scrolls to its top). The status bar is the
    /// system's, so this taps the screen's top-left corner, over the clock.
    @MainActor
    static func tapStatusBar(_ app: XCUIApplication) {
        A11yScreens.tap(app, at: CGPoint(x: 40, y: 18))
    }
}

extension A11yAskUITests {
    /// The line of a row nearest the middle of the thread's frame — a text element whose identifier is
    /// `prefix` followed by the row's number (not an action), with its centre inside the frame — from one
    /// snapshot: its identifier, label and frame.
    @MainActor
    static func centredLine(of prefix: String, in thread: XCUIElement)
        -> (identifier: String, label: String, frame: CGRect)? {
        guard let snapshot = try? thread.snapshot() else { return nil }
        let viewport = snapshot.frame
        var best: (identifier: String, label: String, frame: CGRect)?
        func visit(_ node: XCUIElementSnapshot) {
            let frame = node.frame
            if node.identifier.hasPrefix(prefix), node.identifier.dropFirst(prefix.count).allSatisfy(\.isNumber),
               frame.height >= 8, viewport.contains(CGPoint(x: frame.midX, y: frame.midY)),
               !node.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               best.map({ abs(frame.midY - viewport.midY) < abs($0.frame.midY - viewport.midY) }) ?? true {
                best = (node.identifier, node.label, frame)
            }
            node.children.forEach(visit)
        }
        snapshot.children.forEach(visit)
        return best
    }

    /// The frame of row `identifier`'s line labelled `label`, wherever it is, from one snapshot.
    @MainActor
    static func frame(ofLine label: String, in identifier: String, thread: XCUIElement) -> CGRect? {
        guard let snapshot = try? thread.snapshot() else { return nil }
        var stack = snapshot.children
        while let node = stack.popLast() {
            if node.identifier == identifier, node.label == label { return node.frame }
            stack.append(contentsOf: node.children)
        }
        return nil
    }
}

/// A screenshot's pixels, read in screen points: the contrast inside a frame, and the longest horizontal
/// run of a colour (a link's underline).
private struct AskScreenPixels {
    private let width: Int
    private let height: Int
    private let scale: CGFloat
    private let bytes: [UInt8]

    init?(_ screenshot: XCUIScreenshot, pointWidth: CGFloat) {
        guard let image = screenshot.image.cgImage, pointWidth > 0,
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        width = image.width
        height = image.height
        scale = CGFloat(image.width) / pointWidth
        var buffer = [UInt8](repeating: 0, count: image.width * image.height * 4)
        guard let context = CGContext(data: &buffer, width: image.width, height: image.height, bitsPerComponent: 8,
                                      bytesPerRow: image.width * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        bytes = buffer
    }

    /// WCAG contrast of the darkest pixel inside `frame` against its lightest — a text against its
    /// background, where the frame holds one text on one fill. Nil when the frame is off the screen.
    func contrast(in frame: CGRect) -> Double? {
        guard let (x0, x1, y0, y1) = pixelBounds(frame) else { return nil }
        let linear = Self.linear
        var darkest = 2.0, lightest = -1.0
        for y in y0..<y1 {
            for x in x0..<x1 {
                let i = (y * width + x) * 4
                let lum = 0.2126 * linear[Int(bytes[i])] + 0.7152 * linear[Int(bytes[i + 1])] + 0.0722 * linear[Int(bytes[i + 2])]
                darkest = min(darkest, lum)
                lightest = max(lightest, lum)
            }
        }
        return (lightest + 0.05) / (darkest + 0.05)
    }

    /// sRGB channel value → linear light (WCAG relative luminance), for each of the 256 values.
    private static let linear: [Double] = (0...255).map { c in
        let v = Double(c) / 255
        return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
    }

    /// The longest unbroken horizontal run of pixels that `matches` inside `frame`: its length and its
    /// row, in points.
    func longestRun(in frame: CGRect, where matches: (UInt8, UInt8, UInt8) -> Bool) -> (points: CGFloat, y: CGFloat) {
        guard let (x0, x1, y0, y1) = pixelBounds(frame) else { return (0, 0) }
        var best = 0, bestRow = 0
        for y in y0..<y1 {
            var run = 0
            for x in x0..<x1 {
                let i = (y * width + x) * 4
                if matches(bytes[i], bytes[i + 1], bytes[i + 2]) {
                    run += 1
                    if run > best { (best, bestRow) = (run, y) }
                } else {
                    run = 0
                }
            }
        }
        return (CGFloat(best) / scale, CGFloat(bestRow) / scale)
    }

    /// The link underline's colour — the shared `Text.LineStyle.stashLinkUnderline`, violet-600 (#6d5bd0)
    /// at 80 % over an answer's #f2f2f7, ≈ #8879d8 (or over white, ≈ #8a7cd9) — give or take
    /// antialiasing. Never the bubble, white, a grey, `ink`, `muted`, a violet-600 glyph's core
    /// (#6d5bd0) or the old 50 % underline (≈ #b0a7e4); a violet glyph's antialiased edges match too, but
    /// only in runs as short as a stroke.
    static func isLinkUnderline(_ r: UInt8, _ g: UInt8, _ b: UInt8) -> Bool {
        let (r, g, b) = (Int(r), Int(g), Int(b))
        return (124...150).contains(r) && (110...136).contains(g) && (206...228).contains(b) && b - r >= 60
    }

    private func pixelBounds(_ frame: CGRect) -> (Int, Int, Int, Int)? {
        let x0 = max(0, Int(frame.minX * scale)), x1 = min(width, Int(frame.maxX * scale))
        let y0 = max(0, Int(frame.minY * scale)), y1 = min(height, Int(frame.maxY * scale))
        return x0 < x1 && y0 < y1 ? (x0, x1, y0, y1) : nil
    }
}
