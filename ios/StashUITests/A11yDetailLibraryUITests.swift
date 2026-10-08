import UIKit
import XCTest

/// Plan 16, Task 2b — the HIG + accessibility pass on the detail sheet and the View tab (Library).
///
/// Will: "The font sizes on the detail screen appear to be especially small, and should match the
/// user's preferences for accessibility/increased font sizing". Here:
/// - the screenshot matrix — the View tab at rest, scrolled, searching, with no matches and with
///   the refresh-error banner, and the detail sheet of a link, of a voice note whose title is only
///   its file name (the "Voice note" placeholder), of an item with a markdown summary, of one with
///   a rich note (and its open Details drawer: the facts and a set location), and the lower half
///   of a shared one (Details open, Sharing with its feed link and sticky note) — at Large,
///   xxxLarge, AX3 and Bold Text, with Xcode's accessibility audit run on every screen (`A11Y
///   audit …` lines, contrast findings with the real pixels; the report judges each);
/// - the contracts the pass set, measured: detail reading text at 17 pt and growing with the text
///   size; the title wrapping instead of cutting off; every detail control taking taps across at
///   least 44×44 pt; the footer and the Details facts stacking at the accessibility sizes; the
///   scrolled-away search field staying reachable (and, in a by-hand probe, real VoiceOver
///   bringing its row back).
///
/// The 2b fix wave adds, measured the same way: reading text's line spacing tapering at the
/// accessibility sizes, the detail URL keeping to three lines there, links in reading text
/// underlined (in the pixels), and the "Generating summary…" progress label keeping its contrast.
///
/// Seeded rows carry a `UITEST-P16-2b-` marker and are deleted in teardown blocks (a failed delete
/// is reported, never swallowed); every seeding first deletes this file's rows that a killed run
/// leaked (`Rest2b.deleteStaleSeededRows`). The permanent `UITEST-FIXTURE: link one` is only
/// opened, never edited. Shots are attached as `a11y-2b-<screen>-<size>` (`a11y-2b-ios26-…` on
/// iOS 26); export them with `/tmp/p16/export-shots.sh`-style tooling.
final class A11yDetailLibraryUITests: XCTestCase {
    /// One pass of Xcode's audit (`XCUIApplication.performAccessibilityAudit`). A parameter of `audit`
    /// only so that `testAnAuditThatNeverCompletesEndsTheTestAsSkipped` can stand in a runner that
    /// gives up, as the real one does when it "failed to complete in time".
    private typealias AuditRun = (_ types: XCUIAccessibilityAuditType,
                                  _ issueHandler: @escaping (XCUIAccessibilityAuditIssue) throws -> Bool) throws -> Void

    /// The screens whose audit never completed in this test (`audit`, which records them; a test
    /// that audits ends with `skipIfAnAuditNeverFinished()`). XCTest makes a new instance per test.
    private var unfinishedAudits: [String] = []

    override func setUpWithError() throws {
        continueAfterFailure = false
        // The real Bold Text setting is simulator-global; a killed earlier run can leave it on.
        MainActor.assumeIsolated { A11yScreens.restoreRealBoldTextIfLeftOn() }
    }

    // MARK: - Screenshot matrix: the View tab

    /// The View tab at rest, scrolled (the search row gone, cards under the status-bar scrim),
    /// searching (keyboard up, Cancel on its paper capsule), a card with a plate hero (the favicon
    /// plate), with no matches (the state pane), and with the refresh-error banner, at every size.
    /// Asserts that each screen comes up (and Retry's target at Large); the audit findings are
    /// logged.
    @MainActor
    func testViewTabScreens() async throws {
        let seeded = try await seedRows()
        let screens = A11yScreens(self)
        try screens.signIn()
        for variant in A11yVariant.matrix {
            let app = screens.launch(variant, tab: .view)
            let search = app.textFields["library.search"]
            XCTAssertTrue(search.waitForExistence(timeout: 15), "\(variant): search field missing")
            XCTAssertTrue(element(app, "card.0").waitForExistence(timeout: 20), "\(variant): no cards")
            // The disk-cached page shows first, then the refreshed one with the seeded rows.
            XCTAssertTrue(card(app, containing: seeded.marker).waitForExistence(timeout: 30),
                          "\(variant): the seeded rows never listed")
            sleep(2)   // the backdrop's blurred tier fades in; heroes settle
            try capture(app, screens, "view", variant)

            // Scrolled: the row snaps out, the scrim fills the status bar, cards run under it.
            let window = app.windows.firstMatch.frame
            let start = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: window.midX, dy: window.midY + 150))
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -320)),
                        withVelocity: .slow, thenHoldForDuration: 0.3)
            sleep(1)
            XCTAssertFalse(search.isHittable, "\(variant): expected the search row scrolled away")
            // The audit scrolls every element it inspects into view — the search field too, which
            // brings its row back to rest (as VoiceOver reaching it would) — so its findings for
            // this screen are for a list moving back to the top.
            try capture(app, screens, "view-scrolled", variant)
            print("A11Y after-audit \(variant) search row hittable=\(search.isHittable)")
            let grid = element(app, "library.grid")
            for _ in 0..<3 where !search.isHittable { grid.swipeDown() }
            XCTAssertTrue(eventually(10) { search.isHittable }, "\(variant): expected the search row back")

            // Searching: focused, typed, the server's answer in. At Large the focusing tap goes on
            // the magnifier — the whole 44 pt pill takes it, not only the field's ~22 pt line.
            if variant == .large {
                let pill = element(app, "library.search.pill").frame
                print("A11Y target Search pill \(pill) · field \(search.frame)")
                XCTAssertGreaterThanOrEqual(pill.height, 43.5, "The search pill should be at least 44 pt tall")
                A11yScreens.tap(app, at: CGPoint(x: pill.minX + 26, y: pill.maxY - 4))
                let focused = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hasKeyboardFocus == true"), object: search)
                XCTAssertEqual(XCTWaiter().wait(for: [focused], timeout: 3), .completed,
                               "A tap on the pill's magnifier, near its bottom edge, should focus the search field")
            }
            A11yScreens.tapUntilFocused(search)
            search.typeText(seeded.marker)
            XCTAssertTrue(waitForSearchToSettle(app), "\(variant): the search never settled")
            XCTAssertTrue(app.buttons["library.search.cancel"].waitForExistence(timeout: 5), "\(variant): no Cancel")
            sleep(1)
            try capture(app, screens, "view-search", variant)

            // A plate hero among the results: the seeded link has no image, so its card leads with
            // the favicon plate, whose words grow with the text (and the plate with them).
            search.typeText("\n")
            let plateCard = card(app, containing: seeded.summaryWords)
            XCTAssertTrue(findCard(app, plateCard), "\(variant): no card for the seeded link")
            scrollTopIntoView(app, plateCard)
            sleep(1)
            try capture(app, screens, "view-plate", variant)
            for _ in 0..<4 where !search.isHittable { element(app, "library.grid").swipeDown() }

            // No matches: one character nothing contains — below the server search's two-character
            // minimum (which otherwise answers with its nearest neighbours), so the local filter
            // says "No matches" — and Return drops the keyboard so the pane shows whole.
            let clear = app.buttons["library.search.clear"]
            XCTAssertTrue(clear.waitForExistence(timeout: 5), "\(variant): no clear button")
            clear.tap()
            A11yScreens.tapUntilFocused(search)
            search.typeText("¶\n")
            let pane = element(app, "library.empty")
            XCTAssertTrue(pane.waitForExistence(timeout: 20), "\(variant): expected the No matches pane")
            sleep(1)
            try capture(app, screens, "view-nomatch", variant)
            XCTAssertTrue(pane.label.contains("Nothing matches that."), "\(variant): the pane should read as one element, got '\(pane.label)'")

            // The refresh-error banner over the cards (DEBUG `--uitest-library-error-banner` — a
            // real one needs a failed refresh): ink on the orange, the message whole, and "Retry"
            // a 44 pt target that keeps its word (under the message at the accessibility sizes).
            let bannerApp = screens.launch(variant, tab: .view, arguments: ["--uitest-library-error-banner"])
            let banner = bannerApp.descendants(matching: .any).matching(identifier: "library.errorBanner").firstMatch
            XCTAssertTrue(banner.waitForExistence(timeout: 20), "\(variant): no error banner")
            XCTAssertTrue(element(bannerApp, "card.0").waitForExistence(timeout: 20), "\(variant): no cards under the banner")
            sleep(2)
            if variant == .large { assertTarget(bannerApp.buttons["Retry"], "Retry") }
            try capture(bannerApp, screens, "view-error", variant)
        }
        try skipIfAnAuditNeverFinished()
    }

    // MARK: - Screenshot matrix: the detail sheet

    /// The detail sheet of the permanent link fixture, of a seeded voice note titled with its file
    /// name (the "Voice note" placeholder), of a seeded link with a markdown summary, of a seeded
    /// text item with a rich (TipTap) note — and that item's open Details drawer — and of a seeded
    /// public item's Sharing section, at every size — each with its audit logged.
    @MainActor
    func testDetailScreens() async throws {
        let seeded = try await seedRows()
        let screens = A11yScreens(self)
        try screens.signIn()
        for variant in A11yVariant.matrix {
            let app = screens.launch(variant, tab: .view)
            XCTAssertTrue(app.textFields["library.search"].waitForExistence(timeout: 15), "\(variant): search missing")

            openDetail(app, query: "link one", cardText: "UITEST-FIXTURE: link one", variant: variant)
            XCTAssertTrue(element(app, "detail.urlBar").waitForExistence(timeout: 10), "\(variant): no URL bar")
            sleep(2)
            try capture(app, screens, "detail-link", variant)
            closeDetail(app)

            openDetail(app, query: seeded.marker, cardText: seeded.audioWords, variant: variant)
            let title = titleField(app)
            XCTAssertTrue(title.waitForExistence(timeout: 10), "\(variant): no title field")
            XCTAssertTrue(title.placeholderValue == "Voice note" || (title.value as? String) == "Voice note",
                          "\(variant): expected the Voice note placeholder, got '\(title.placeholderValue ?? "nil")'")
            // The transcript (`page_body`) is read after the sheet opens and moves everything below
            // it: audit once it's in.
            let transcript = firstElement(app, "detail.transcriptText")
            XCTAssertTrue(transcript.waitForExistence(timeout: 10), "\(variant): no transcript")
            XCTAssertTrue(A11yScreens.waitForLabel(transcript, "harbour", timeout: 15), "\(variant): the transcript never loaded")
            sleep(1)
            try capture(app, screens, "detail-audio", variant)
            closeDetail(app)

            openDetail(app, query: seeded.marker, cardText: seeded.summaryWords, variant: variant)
            let summary = firstElement(app, "detail.summaryText")
            XCTAssertTrue(summary.waitForExistence(timeout: 10), "\(variant): no summary")
            A11yScreens.scrollIntoView(app, summary)
            sleep(1)
            try capture(app, screens, "detail-summary", variant)
            closeDetail(app)

            openDetail(app, query: seeded.marker, cardText: seeded.noteWords, variant: variant)
            let notes = firstElement(app, "detail.notesText")
            XCTAssertTrue(notes.waitForExistence(timeout: 10), "\(variant): no rendered note")
            A11yScreens.scrollIntoView(app, notes)
            sleep(1)
            try capture(app, screens, "detail-notes", variant)
            // The same item's Details drawer, open: its facts and a set location (the place and
            // its remove ×) — label over value at the accessibility sizes.
            let facts = element(app, "detail.details")
            A11yScreens.scrollIntoView(app, facts)
            facts.tap()
            let place = element(app, "detail.location.label")
            XCTAssertTrue(place.waitForExistence(timeout: 10), "\(variant): no location in the open drawer")
            A11yScreens.scrollIntoView(app, place)
            sleep(1)
            if variant == .large {
                // The place (edits it) and its × (removes it): each a 44 pt target, apart.
                let remove = element(app, "detail.location.remove")
                assertTarget(place, "Location label")
                assertTarget(remove, "Remove location")
                XCTAssertGreaterThanOrEqual(remove.frame.minX, place.frame.maxX - 0.5,
                                            "The × target must not overlap the label's (\(place.frame) vs \(remove.frame))")
            }
            try capture(app, screens, "detail-facts", variant)
            closeDetail(app)

            // The lower half: the Details drawer open (facts; the location row) and Sharing on a
            // public item (the feed link, the sticky note).
            openDetail(app, query: seeded.marker, cardText: seeded.sharedWords, variant: variant)
            let details = element(app, "detail.details")
            A11yScreens.scrollIntoView(app, details)
            details.tap()
            let sticky = element(app, "detail.public.sticky")
            XCTAssertTrue(sticky.waitForExistence(timeout: 10), "\(variant): no sticky note field")
            A11yScreens.scrollIntoView(app, sticky)
            sleep(1)
            if variant == .large {
                // By its name: the chip's own `detail.sharing.feedLink` identifier reaches its
                // children too.
                assertTarget(app.buttons["Copy public feed link"], "Copy feed link")
                print("A11Y target Sticky note \(sticky.frame) · Sharing switch \(element(app, "detail.public.toggle").frame)")
            }
            try capture(app, screens, "detail-sharing", variant)
            if variant == .large {
                // The sticky note's text is one 21 pt line, but its whole note box (≥ 44 pt) takes
                // the focusing tap: one 8 pt above the text lands on the box's padding. (The audit
                // above scrolls the sheet: bring the note back into view first.)
                A11yScreens.scrollIntoView(app, sticky)
                sleep(1)
                let frame = sticky.frame
                A11yScreens.tap(app, at: CGPoint(x: frame.midX, y: frame.minY - 8))
                let focused = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hasKeyboardFocus == true"), object: sticky)
                XCTAssertEqual(XCTWaiter().wait(for: [focused], timeout: 3), .completed,
                               "A tap on the sticky note box's padding should focus the note (field \(frame))")
            }
            closeDetail(app)
        }
        try skipIfAnAuditNeverFinished()
    }

    // MARK: - Contracts

    /// An audit that never completes must not pass silently (polish batch, item 4). Xcode's audit
    /// can give up ("Audit failed to complete in time"); `audit` then scrolls 30 pt and tries once
    /// more, and if that times out too, nothing was audited — the matrix tests above must end as
    /// SKIPPED, naming the screen, not pass with a log line. A skip rather than a failure because
    /// a double timeout with the app still answering is the tool's known hang (iOS 26.5, the detail
    /// facts screen at xxxL, 3 of 3 first attempts; the app idle and answering at once), not
    /// something the app did — and the helper fails right there if the app stops answering. This
    /// puts a runner that gives up in the real helper's place, on the type specimen (signed out, no
    /// network): twice → the test must be skipped; once, then completing → it must not be.
    @MainActor
    func testAnAuditThatNeverCompletesEndsTheTestAsSkipped() throws {
        let app = A11yScreens(self).launchSpecimen(.large)
        let timedOut = NSError(domain: "com.apple.xcode.xctest.accessibilityAudit", code: -56,
                               userInfo: [NSLocalizedDescriptionKey: "Audit failed to complete in time"])

        var runs = 0
        try audit(app, screen: "probe-never-completes", variant: .large) { _, _ in
            runs += 1
            throw timedOut
        }
        XCTAssertEqual(runs, 2, "The audit should be tried, then once more after the scroll — not more, not less")
        XCTAssertEqual(unfinishedAudits.count, 1, "A double timeout should be recorded")
        do {
            try skipIfAnAuditNeverFinished()
            XCTFail("An audit that timed out twice must end its test as skipped, not let it pass")
        } catch is XCTSkip {
            print("A11Y audit probe | the double timeout ended the test as skipped, as it should")
        }

        // Once, then completing after the scroll: audited after all — no skip.
        unfinishedAudits.removeAll()
        runs = 0
        try audit(app, screen: "probe-completes-on-retry", variant: .large) { _, _ in
            runs += 1
            if runs == 1 { throw timedOut }
        }
        XCTAssertEqual(runs, 2)
        XCTAssertTrue(unfinishedAudits.isEmpty, "An audit that completed on the retry was recorded as unfinished")
        XCTAssertNoThrow(try skipIfAnAuditNeverFinished(), "An audit that completed on the retry is no reason to skip")
    }

    /// Will's "especially small" detail text, measured: the description is the `reading` role —
    /// 17 pt at Large (it was 14; the summary, transcript and notes share the role) — and grows
    /// with the text size: at AX3 a line of it is over 1.8× as tall as at Large; and one line of
    /// it, ~25 pt tall, still takes taps across 44 pt. The title wraps (it used to be one line that
    /// scrolled sideways), so a long title is never cut off at AX3 — and it's still one line of
    /// text: Return ends editing and adds no line break.
    @MainActor
    func testDetailReadingTextIs17AndGrowsWithTheTextSize() async throws {
        let seeded = try await seedRows()
        let screens = A11yScreens(self)
        try screens.signIn()
        var lineHeights: [String: [String: CGFloat]] = [:]
        for variant in [A11yVariant.large, .ax3] {
            let app = screens.launch(variant, tab: .view)
            openDetail(app, query: seeded.marker, cardText: seeded.summaryWords, variant: variant)
            let description = descriptionField(app)
            XCTAssertTrue(description.waitForExistence(timeout: 10), "\(variant): no description")
            // One line of the description (a short one) — the field's height is its line height.
            lineHeights[variant.token, default: [:]]["description"] = description.frame.height
            if variant == .large {
                // That one line is ~25 pt tall with its insets, but the field takes taps across
                // 44 pt: a tap 8 pt above its text — in the gap under the title — focuses it.
                let frame = description.frame
                A11yScreens.tap(app, at: CGPoint(x: frame.midX, y: frame.minY - 8))
                let focused = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hasKeyboardFocus == true"),
                                                        object: description)
                XCTAssertEqual(XCTWaiter().wait(for: [focused], timeout: 3), .completed,
                               "A tap 8 pt above a one-line description should focus it (field \(frame))")
                let hideKeyboard = app.buttons["detail.dismissKeyboard"]
                if hideKeyboard.waitForExistence(timeout: 3) { hideKeyboard.tap() }
                let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: hideKeyboard)
                XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 5), .completed, "The keyboard didn't go away")
            }

            let title = titleField(app)
            XCTAssertTrue(title.waitForExistence(timeout: 10), "\(variant): no title field")
            let titleText = (title.value as? String) ?? ""
            XCTAssertTrue(titleText.contains("Field guide"), "\(variant): unexpected title '\(titleText)'")
            let window = app.windows.firstMatch.frame
            XCTAssertLessThanOrEqual(title.frame.maxX, window.maxX, "\(variant): the title runs off the sheet")
            if variant == .ax3 {
                // At AX3 this 50-odd-character title can't fit one line: it must wrap, not scroll away.
                XCTAssertGreaterThan(title.frame.height, 80,
                                     "\(variant): expected the long title to wrap onto several lines, got \(title.frame)")
            } else {
                // It wraps, but it's one line of text: Return ends editing and adds no line break.
                A11yScreens.tapUntilFocused(title)
                let hideKeyboard = app.buttons["detail.dismissKeyboard"]
                XCTAssertTrue(hideKeyboard.waitForExistence(timeout: 5), "\(variant): the title didn't take focus")
                title.typeText("\n")
                let ended = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: hideKeyboard)
                XCTAssertEqual(XCTWaiter().wait(for: [ended], timeout: 5), .completed, "\(variant): Return should end editing")
                XCTAssertEqual(title.value as? String, titleText, "\(variant): Return must not change the title")
            }
            closeDetail(app)
        }
        let large = lineHeights["L"]?["description"] ?? 0
        let ax3 = lineHeights["AX3"]?["description"] ?? 0
        print("A11Y measure description line: L \(large) AX3 \(ax3)")
        // Neue Montreal Book 17 sets a ~20–24 pt line with the field's 2 pt insets; 14 pt set ~17–19.
        XCTAssertGreaterThanOrEqual(large, 20, "The description should be 17 pt reading text at Large (line \(large))")
        XCTAssertGreaterThan(ax3, large * 1.8, "The description should grow with the text size (L \(large), AX3 \(ax3))")
    }

    /// Every control on the detail sheet takes taps across at least 44×44 pt (its accessibility
    /// frame is its target): the close ×, "Open link", "Delete item", the Details header, "Add a
    /// location", the hide-keyboard circle — and a tap 5 pt past the close circle's edge still
    /// closes the sheet. Xcode's hit-region audit finds nothing on the sheet at Large.
    @MainActor
    func testDetailControlsTakeTapsAcross44Points() async throws {
        let screens = A11yScreens(self)
        try screens.signIn()
        let app = screens.launch(.large, tab: .view)
        openDetail(app, query: "link one", cardText: "UITEST-FIXTURE: link one", variant: .large)

        let close = app.buttons["detail.done"]
        assertTarget(close, "Close")
        XCTAssertEqual(close.label, "Close")
        assertTarget(element(app, "detail.openLink"), "Open link")
        let delete = app.buttons["detail.delete"]
        assertTarget(delete, "Delete item")

        var hitRegionIssues: [String] = []
        try app.performAccessibilityAudit(for: [.hitRegion]) { issue in
            let id = issue.element?.identifier ?? "-"
            let label = issue.element?.label ?? ""
            print("A11Y audit controls L | \(issue.compactDescription) | id=\(id) label=\"\(label)\" frame=\(issue.element?.frame ?? .zero)")
            hitRegionIssues.append("\(id) \"\(label)\"")
            return true
        }

        // At the top of the sheet: the title field, and the footer's hide-keyboard circle it shows.
        let title = titleField(app)
        A11yScreens.tapUntilFocused(title)
        assertTarget(app.buttons["detail.dismissKeyboard"], "Hide keyboard")
        app.buttons["detail.dismissKeyboard"].tap()
        let keyboardGone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"),
                                                     object: app.buttons["detail.dismissKeyboard"])
        XCTAssertEqual(XCTWaiter().wait(for: [keyboardGone], timeout: 5), .completed, "Hide keyboard didn't")

        let details = element(app, "detail.details")
        A11yScreens.scrollIntoView(app, details)
        assertTarget(details, "Details header")
        details.tap()
        let addLocation = element(app, "detail.location.add")
        A11yScreens.scrollIntoView(app, addLocation)
        assertTarget(addLocation, "Add a location")

        // The close × (a 28 pt circle, 14 pt in from the corner) takes a tap 5 pt past its edge —
        // inside the 44 pt target — and the sheet goes.
        let circleEdgeX = close.frame.midX - 14
        A11yScreens.tap(app, at: CGPoint(x: circleEdgeX - 5, y: close.frame.midY))
        let closed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: close)
        XCTAssertEqual(XCTWaiter().wait(for: [closed], timeout: 5), .completed,
                       "A tap 5 pt past the close circle's edge should close the sheet")
        XCTAssertTrue(hitRegionIssues.isEmpty, "Xcode's hit-region audit flagged: \(hitRegionIssues)")
    }

    /// The footer and the Details facts reflow at the accessibility sizes instead of cramming: at
    /// Large "Changes saved automatically" sits beside "Delete item"; at AX sizes that resting
    /// line is left out (Task 4d, 2b review M-3 — "Saving…" and errors still show, under Delete:
    /// `LibraryDetailUITests`), and a fact's value sits under its label.
    @MainActor
    func testTheDetailFooterAndFactsStackAtAccessibilitySizes() async throws {
        let screens = A11yScreens(self)
        try screens.signIn()
        for variant in [A11yVariant.large, .ax3] {
            let app = screens.launch(variant, tab: .view)
            openDetail(app, query: "link one", cardText: "UITEST-FIXTURE: link one", variant: variant)
            let delete = app.buttons["detail.delete"]
            let autosave = element(app, "detail.autosave")
            XCTAssertTrue(delete.waitForExistence(timeout: 10), "\(variant): footer missing")
            if variant == .ax3 {
                XCTAssertFalse(autosave.exists, "\(variant): no resting autosave line at the accessibility sizes")
            } else {
                XCTAssertTrue(autosave.waitForExistence(timeout: 10), "\(variant): footer missing")
                print("A11Y footer \(variant) delete \(delete.frame) autosave \(autosave.frame)")
                XCTAssertEqual(autosave.frame.midY, delete.frame.midY, accuracy: 4,
                               "\(variant): the autosave line should sit beside Delete item")
            }
            let details = element(app, "detail.details")
            A11yScreens.scrollIntoView(app, details)
            details.tap()
            let saved = element(app, "detail.details.row.saved")
            XCTAssertTrue(saved.waitForExistence(timeout: 10), "\(variant): no Saved fact")
            A11yScreens.scrollIntoView(app, saved)
            print("A11Y fact \(variant) saved \(saved.frame) label '\(saved.label)'")
            if variant == .ax3 {
                // Label over value: the row is (at least) two AX3 meta lines tall.
                XCTAssertGreaterThan(saved.frame.height, 60, "\(variant): expected the Saved value under its label")
            }
            closeDetail(app)
        }
    }

    // MARK: - Contracts (2b fix wave)

    /// Reading text's line spacing — `stashLeading(0.55, role: .reading)`, the detail sheet's — on
    /// the sheet itself, at Large, xxxLarge and AX3: a seeded link's one-line summary and its
    /// three-line "Original Content", both plain reading text. Their heights give the gap between
    /// lines, (h3 − 3·h1) / 2. It is 0.55 em of the scaled reading size at the standard sizes (9.35
    /// pt at Large, 12.1 at xxxLarge) and 0.35 em at the accessibility sizes (12.95 pt at AX3, where
    /// 0.55 em was 20.35): the foundation's taper (2b review). Measured at AX3, a line's pitch goes
    /// from 1.75 em to 1.55.
    @MainActor
    func testDetailReadingLeadingTapersAtAccessibilitySizes() async throws {
        let seeded = try await seedLinkRow("Leading probe", fields: [
            "url": "https://example.com/p16-2b/leading-probe",
            "description": "Three short lines.",
            // Plain text, not markdown, and short enough to stay one line apiece at AX3.
            "summary": "One line.",
            "page_body": "First line\nSecond line\nThird line",
        ])
        let screens = A11yScreens(self)
        try screens.signIn()
        var failures: [String] = []
        for variant in [A11yVariant.large, .xxxLarge, .ax3] {
            let app = screens.launch(variant, tab: .view)
            openDetail(app, query: seeded.marker, cardText: "Leading probe", variant: variant)
            let summary = firstElement(app, "detail.summaryText")
            XCTAssertTrue(summary.waitForExistence(timeout: 10), "\(variant): no summary")
            XCTAssertTrue(A11yScreens.waitForLabel(summary, "One line.", condition: "==", timeout: 10),
                          "\(variant): unexpected summary '\(summary.label)'")
            A11yScreens.scrollIntoView(app, summary)
            let oneLine = summary.frame.height

            let originalTab = app.buttons["Original Content"]
            XCTAssertTrue(originalTab.waitForExistence(timeout: 10), "\(variant): no Original Content tab")
            A11yScreens.scrollIntoView(app, originalTab)
            originalTab.tap()
            let original = firstElement(app, "detail.originalText")
            XCTAssertTrue(original.waitForExistence(timeout: 10), "\(variant): no Original Content text")
            XCTAssertTrue(A11yScreens.waitForLabel(original, "Third line", timeout: 15),
                          "\(variant): the captured text never loaded ('\(original.label)')")
            A11yScreens.scrollIntoView(app, original)
            sleep(1)
            let threeLines = original.frame.height
            screens.attachScreenshot(named: (Self.isIOS26 ? "2b-ios26-" : "2b-") + "detail-leading")

            let metrics = UIFontMetrics(forTextStyle: .body)
            let size = metrics.scaledValue(for: 17, compatibleWith: variant.traits)
            let em: CGFloat = Self.isAccessibilitySize(variant) ? 0.35 : 0.55
            let expected = metrics.scaledValue(for: em * 17, compatibleWith: variant.traits)
            let gap = (threeLines - 3 * oneLine) / 2
            let pitch = (threeLines - oneLine) / 2
            print("A11Y leading detail \(variant): line \(oneLine) · three lines \(threeLines) · pitch \(pitch) "
                  + "(\(String(format: "%.2f", pitch / size)) em of \(size)) · gap \(gap) · expected \(expected) (\(em) em)")
            if abs(gap - expected) > 0.75 {
                failures.append("\(variant): gap \(gap) pt, expected \(expected) (\(em) em)")
            }
            closeDetail(app)
        }
        XCTAssertTrue(failures.isEmpty, "Reading text's line spacing is off its rule:\n" + failures.joined(separator: "\n"))
    }

    /// The detail URL (2b review M-3; coordinator decision): one line, shortened in the middle, at
    /// the standard sizes — and at the accessibility sizes it wraps but keeps to three lines, still
    /// shortened in the middle, instead of the whole address (10 lines of 33 pt mono at AX3 for
    /// this one). VoiceOver reads it whole, and the whole URL is a long press away at every size:
    /// the context menu (Copy link, Open link) previews it wrapped. XCUITest doesn't see inside that
    /// preview, so the `detail-url-menu` shots are its check (it was sized for one line and cut the
    /// rest off). The long domain is also the Details header's summary (2b review N-1): beside the
    /// label, shortened, at the standard sizes — under it only at the accessibility sizes.
    @MainActor
    func testTheDetailURLKeepsToThreeLinesAtAccessibilitySizes() async throws {
        let url = "https://dynamic-type-field-guide.everyday-reading.example.com/p16-2b/at-every-text-size-from-large-up"
        let seeded = try await seedLinkRow("Address probe", fields: [
            "url": url, "description": "A long address.", "summary": "One line.",
        ])
        let screens = A11yScreens(self)
        try screens.signIn()
        var failures: [String] = []
        for variant in [A11yVariant.large, .ax3] {
            let app = screens.launch(variant, tab: .view)
            openDetail(app, query: seeded.marker, cardText: "Address probe", variant: variant)
            let bar = element(app, "detail.urlBar")
            let text = element(app, "detail.urlText")
            XCTAssertTrue(text.waitForExistence(timeout: 10), "\(variant): no URL")
            A11yScreens.scrollIntoView(app, bar)
            sleep(1)
            if text.label != url { failures.append("\(variant): VoiceOver reads '\(text.label)', not the whole URL") }
            // The v2 URL is `.code(.footnote)`: JetBrains Mono at 13 pt, scaled and
            // rounded by UIFontMetrics. The bundled TTF's hhea metrics are 1020/-300
            // with zero gap and 1000 units/em, so a line is 1.32 em. A UI test runs
            // in its own process and cannot resolve the app's registered custom font.
            let pointSize = UIFontMetrics(forTextStyle: .footnote)
                .scaledValue(for: 13, compatibleWith: variant.traits).rounded()
            let line = pointSize * 1.32
            let lines = text.frame.height / line
            print("A11Y url \(variant): text \(text.frame) · mono line \(line) · \(String(format: "%.2f", lines)) lines")
            screens.attachScreenshot(named: (Self.isIOS26 ? "2b-ios26-" : "2b-") + "detail-url")
            if Self.isAccessibilitySize(variant) {
                if !(2.5...3.4).contains(lines) { failures.append("\(variant): \(lines) lines, expected three (\(text.frame))") }
            } else if lines > 1.4 {
                failures.append("\(variant): \(lines) lines, expected one (\(text.frame))")
            }

            // The whole URL, a long press away.
            bar.press(forDuration: 1.2)
            let copy = app.buttons["Copy link"]
            XCTAssertTrue(copy.waitForExistence(timeout: 5), "\(variant): the long press should open the link menu")
            sleep(1)
            screens.attachScreenshot(named: (Self.isIOS26 ? "2b-ios26-" : "2b-") + "detail-url-menu")
            A11yScreens.tap(app, at: CGPoint(x: app.windows.firstMatch.frame.midX, y: 70))
            let closed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: copy)
            XCTAssertEqual(XCTWaiter().wait(for: [closed], timeout: 5), .completed, "\(variant): the link menu didn't close")

            // N-1: the Details header with this long domain as its summary. One row at Large is
            // ~65 pt with the section's rhythm; the summary moved under the label made it ~88.
            let details = element(app, "detail.details")
            A11yScreens.scrollIntoView(app, details)
            sleep(1)
            print("A11Y details header \(variant): \(details.frame) label '\(details.label)'")
            screens.attachScreenshot(named: (Self.isIOS26 ? "2b-ios26-" : "2b-") + "detail-details-header")
            if Self.isAccessibilitySize(variant) {
                if details.frame.height < 100 {
                    failures.append("\(variant): the Details summary should sit under its label (\(details.frame))")
                }
            } else if details.frame.height > 76 {
                failures.append("\(variant): the Details summary should stay beside its label (\(details.frame))")
            }
            closeDetail(app)
        }
        XCTAssertTrue(failures.isEmpty, "The detail URL is off its contract:\n" + failures.joined(separator: "\n"))
    }

    /// Links in reading text remain underlined in v2: both links and body text are ink,
    /// so colour cannot identify a link. Checked in body text and in a quote at Large and
    /// Bold Text: the solid `StashColor.linkUnderline` (#000) runs at least 30 pt, longer
    /// than a glyph's horizontal stroke. The probe's link words have no descenders.
    /// The former violet/transparent underline and a missing underline both fail.
    @MainActor
    func testLinksInReadingTextAreUnderlined() async throws {
        let seeded = try await seedLinkRow("Link probe", fields: [
            "url": "https://example.com/p16-2b/link-probe",
            "description": "Links in a summary.",
            "summary": """
            Read the [handbook](https://example.com/p16-2b/handbook) first, then the [standards](https://example.com/p16-2b/standards) list.

            > Wrap the text instead of [truncation](https://example.com/p16-2b/truncation) marks.
            """,
        ])
        let screens = A11yScreens(self)
        try screens.signIn()
        var failures: [String] = []
        for variant in [A11yVariant.large, .largeBold] {
            let app = screens.launch(variant, tab: .view)
            openDetail(app, query: seeded.marker, cardText: "Link probe", variant: variant)
            let first = firstElement(app, "detail.summaryText")
            XCTAssertTrue(first.waitForExistence(timeout: 10), "\(variant): no summary")
            A11yScreens.scrollIntoView(app, first)
            sleep(1)
            screens.attachScreenshot(named: (Self.isIOS26 ? "2b-ios26-" : "2b-") + "detail-links")
            let window = app.windows.firstMatch.frame
            guard let pixels = ScreenPixels(XCUIScreen.main.screenshot(), pointWidth: window.width) else {
                XCTFail("\(variant): no screenshot pixels")
                continue
            }
            for words in ["Read the handbook", "Wrap the text"] {
                let block = app.descendants(matching: .any)
                    .matching(NSPredicate(format: "identifier == %@ AND label BEGINSWITH %@", "detail.summaryText", words))
                    .firstMatch
                XCTAssertTrue(block.exists, "\(variant): no '\(words)' block")
                let run = pixels.longestRun(in: block.frame, where: ScreenPixels.isLinkUnderline)
                print("A11Y underline \(variant) '\(words)…': block \(block.frame) · longest underline-colour run "
                      + "\(String(format: "%.1f", run.points)) pt at y \(String(format: "%.1f", run.y)), colour \(run.hex)")
                if run.points < 30 {
                    failures.append("\(variant) '\(words)…': longest underline-colour run \(run.points) pt")
                }
            }
            closeDetail(app)
        }
        XCTAssertTrue(failures.isEmpty, "Links in reading text should be underlined:\n" + failures.joined(separator: "\n"))
    }

    /// 2b review M-2 (recipe R-2), and the 2bf review's m1:
    /// - "Generating summary…" is the progress people read while a summary is made. So it keeps
    ///   `muted`'s contrast (#5c6159, 6.4:1 on white) and isn't dimmed by its disabled button.
    ///   It's sampled in the label's middle band, past the spinner; the 44 pt target's overhang
    ///   reaches the "No summary yet" line above.
    /// - VoiceOver still hears a button, dimmed (not enabled).
    /// - It turns busy from a tap, as a person does it, and stays ONE control in place: the same
    ///   identifier on one element, with the same origin and height (m1: one `Button` for both
    ///   states).
    /// - That last check passes for the old two-button form too. Whether VoiceOver's cursor stays
    ///   on the control is the device check (task-2bf-report.md, "Fix round 1").
    /// - The busy state comes from the DEBUG `--uitest-detail-busy-on-tap`: the tap turns the
    ///   action busy with no job behind it. A real `summarize-content` call answers, or fails,
    ///   within about a frame (one frame of a recording).
    @MainActor
    func testTheBusySummaryLabelKeepsItsContrast() async throws {
        let seeded = try await seedLinkRow("Busy probe", fields: [
            "url": "https://example.com/p16-2b/busy-probe",
            "description": "Captured text, no summary yet.",
            "page_body": "Persimmon season runs from October to December. Fuyu persimmons are squat and crisp "
                + "and are eaten like apples; Hachiya persimmons stay astringent until they are soft.",
        ])
        let screens = A11yScreens(self)
        try screens.signIn()
        let app = screens.launch(.large, tab: .view, arguments: ["--uitest-detail-busy-on-tap"])
        openDetail(app, query: seeded.marker, cardText: "Busy probe", variant: .large)
        let busy = element(app, "detail.generateSummary")
        XCTAssertTrue(busy.waitForExistence(timeout: 15), "no Generate summary")
        A11yScreens.scrollIntoView(app, busy)
        sleep(1)
        XCTAssertEqual(busy.label, "Generate summary", "Expected the idle action before the tap")
        XCTAssertTrue(busy.isEnabled, "The idle action should be enabled")
        let idleFrame = busy.frame
        busy.tap()
        XCTAssertTrue(A11yScreens.waitForLabel(busy, "Generating summary", timeout: 10),
                      "Expected the busy label after the tap, got '\(busy.label)'")
        sleep(1)
        let sameIdentifier = app.descendants(matching: .any).matching(identifier: "detail.generateSummary").count
        print("A11Y busy swap: idle \(idleFrame) → busy \(busy.frame) · elements with its identifier: \(sameIdentifier)")
        XCTAssertEqual(sameIdentifier, 1, "Idle and busy should be one control")
        XCTAssertEqual(busy.frame.minX, idleFrame.minX, accuracy: 0.5, "The action shouldn't move when it turns busy")
        XCTAssertEqual(busy.frame.minY, idleFrame.minY, accuracy: 0.5, "The action shouldn't move when it turns busy")
        XCTAssertEqual(busy.frame.height, idleFrame.height, accuracy: 0.5, "The action should keep its 44 pt target")
        let shot = XCUIScreen.main.screenshot()
        let frame = busy.frame
        let window = app.windows.firstMatch.frame
        let pixels = try XCTUnwrap(ScreenPixels(shot, pointWidth: window.width), "no screenshot pixels")
        let band = CGRect(x: frame.minX + 24, y: frame.midY - 8, width: max(frame.width - 24, 1), height: 16)
        let darkest = pixels.darkest(in: band)
        print("A11Y busy label: frame \(frame) · sampled \(band) · darkest \(darkest.hex) = "
              + "\(String(format: "%.2f", darkest.contrastOnWhite)):1 on white · enabled=\(busy.isEnabled) "
              + "type=\(busy.elementType.rawValue) label='\(busy.label)'")
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = (Self.isIOS26 ? "a11y-2b-ios26-" : "a11y-2b-") + "detail-busy-L"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertEqual(busy.elementType, .button, "VoiceOver should still hear a button")
        XCTAssertFalse(busy.isEnabled, "VoiceOver should still hear it dimmed (not enabled)")
        XCTAssertGreaterThanOrEqual(darkest.contrastOnWhite, 4.5,
                                    "The busy label is dimmed: darkest \(darkest.hex), \(darkest.contrastOnWhite):1")
        closeDetail(app)
    }

    /// Task 4 review M-3: the search row fades to a 1 % floor as it scrolls away — invisible, but
    /// still in the accessibility tree, so VoiceOver can reach the field from anywhere in the list.
    /// Reaching an element that's scrolled out of view, VoiceOver scrolls it into view with the
    /// accessibility scroll-to-visible action — the one Xcode's audit uses on every element it
    /// inspects on iOS 17.0, so there the audit stands in for VoiceOver: with the row scrolled all
    /// the way out, the field is still in the tree, and after the audit the row is back at rest,
    /// hittable (so at full opacity) — the row's snap doesn't push it back out.
    ///
    /// The audits of iOS 17.2 and 26.5 don't scroll an element into view (measured: the pill
    /// stayed ~310 pt out), so there the test checks the floor and then skips the scroll-back
    /// half, which `testVoiceOverProbeSwipingBackFromCardZeroBringsTheSearchRowBack` covers with
    /// real VoiceOver — as it does a row resting PART-way out, which VoiceOver doesn't scroll and
    /// `LibrarySearchRow` brings back when the field gains VoiceOver's focus.
    @MainActor
    func testTheSearchRowComesBackWhenAccessibilityScrollsToItsField() throws {
        let screens = A11yScreens(self)
        try screens.signIn()
        let app = screens.launch(.large, tab: .view)
        let search = app.textFields["library.search"]
        let pill = element(app, "library.search.pill")
        XCTAssertTrue(search.waitForExistence(timeout: 15), "search field missing")
        XCTAssertTrue(element(app, "card.0").waitForExistence(timeout: 20), "no cards")
        sleep(2)
        let rest = pill.frame
        let window = app.windows.firstMatch.frame
        let start = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: window.midX, dy: window.midY + 150))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -320)),
                    withVelocity: .slow, thenHoldForDuration: 0.3)
        sleep(1)
        XCTAssertFalse(search.isHittable, "Expected the search row scrolled away (at its 1 % fade floor)")
        XCTAssertTrue(search.exists, "The field must stay in the accessibility tree while scrolled away")
        XCTAssertLessThan(pill.frame.maxY, rest.minY, "Expected the pill above its resting slot")

        let away = pill.frame.minY
        try app.performAccessibilityAudit(for: [.dynamicType]) { _ in true }
        sleep(1)
        if abs(pill.frame.minY - away) < 1 {
            // Measured: iOS 17.0's audit scrolls each element it inspects into view; 17.2's and
            // 26.5's don't. Without that scroll there's nothing here to stand in for VoiceOver's.
            throw XCTSkip("This OS's audit didn't scroll to the field (the 1 % floor above passed); the "
                          + "scroll-back is covered by the real-VoiceOver probe")
        }
        XCTAssertTrue(eventually(5) { search.isHittable && abs(pill.frame.minY - rest.minY) <= 1 },
                      "Scrolling the field into view should bring its row back to rest (pill at \(pill.frame.minY), rest \(rest.minY))")
    }

    /// MANUAL PROBE — skipped unless the runner gets `A11Y_VOICEOVER_PROBE=1` (pass
    /// `TEST_RUNNER_A11Y_VOICEOVER_PROBE=1` to xcodebuild) AND VoiceOver is running: the M-3 check
    /// with REAL VoiceOver running. The Simulator's Settings has no VoiceOver switch, but its
    /// VoiceOver service runs when started by hand from the host (simulator-global — stop it after):
    ///
    ///     xcrun simctl spawn <udid> defaults write com.apple.Accessibility VoiceOverTouchEnabled -bool true
    ///     xcrun simctl spawn <udid> launchctl start com.apple.VoiceOverTouch
    ///     … run this test …
    ///     xcrun simctl spawn <udid> defaults write com.apple.Accessibility VoiceOverTouchEnabled -bool false
    ///     xcrun simctl spawn <udid> launchctl stop com.apple.VoiceOverTouch
    ///
    /// Sign in BEFORE starting VoiceOver (any test here signs in). XCUITest's synthesized touches
    /// and keys never reach VoiceOver (measured on 17.2: a tap activates, a drag scrolls,
    /// Control-Option-arrows don't move its cursor), so VoiceOver can't be swiped from here: the
    /// drags below scroll the list as a finger does, and VoiceOver's focus is put on the search
    /// field by the app (DEBUG `--uitest-voiceover-focus-search-after`, which sets the field's
    /// `@AccessibilityFocusState` — what VoiceOver's own navigation sets when a swipe lands there).
    /// Checked, with VoiceOver running:
    /// - the row's snap stands aside: a drag released with the row part-way out leaves it there;
    /// - once VoiceOver's focus is on the field — the row all the way out, at its 1 % floor — the
    ///   row comes back to rest, whole, VoiceOver's cursor on the field (screenshots).
    ///
    /// Measured: both hold on the iOS 17.2 Simulator. On the iOS 26.5 Simulator the first holds,
    /// but the app's focus request is refused there — the binding reads false right after it's set,
    /// even with the row at rest and the field in full view (a 5 % fade floor changed nothing) — so
    /// the second can't be reached on that runtime: the test skips it, saying so. It needs a device.
    @MainActor
    func testVoiceOverProbeFocusOnTheScrolledAwayFieldBringsTheSearchRowBack() throws {
        guard ProcessInfo.processInfo.environment["A11Y_VOICEOVER_PROBE"] == "1" else {
            throw XCTSkip("VoiceOver probe: run with TEST_RUNNER_A11Y_VOICEOVER_PROBE=1, VoiceOver started on the simulator")
        }
        XCTAssertTrue(UIAccessibility.isVoiceOverRunning, "VoiceOver isn't running on this simulator")
        let screens = A11yScreens(self)
        let app = screens.launch(.large, tab: .view, arguments: ["--uitest-voiceover-focus-search-after", "20"])
        let launched = Date()
        let search = app.textFields["library.search"]
        let pill = element(app, "library.search.pill")
        XCTAssertTrue(search.waitForExistence(timeout: 15), "search field missing")
        XCTAssertTrue(element(app, "card.0").waitForExistence(timeout: 20), "no cards")
        sleep(2)
        let rest = pill.frame
        let os = Self.isIOS26 ? "ios26-" : ""
        func shot(_ name: String) {
            print("A11Y VO \(name): pill minY \(pill.frame.minY) (rest \(rest.minY)) hittable=\(search.isHittable)")
            screens.attachScreenshot(named: "2b-\(os)vo-\(name)")
        }
        func drag(_ distance: CGFloat) {
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -distance)),
                        withVelocity: .slow, thenHoldForDuration: 0.4)
            sleep(1)
        }
        shot("0-rest")
        // Part-way: with VoiceOver running the snap stands aside, so the row stays where it's left.
        drag(28)
        shot("1-partway")
        let partWay = pill.frame.minY
        XCTAssertTrue(partWay < rest.minY - 3 && partWay > rest.minY - 60,
                      "Expected the row left part-way out with VoiceOver running (pill at \(partWay), rest \(rest.minY))")
        // All the way out: the field at its 1 % floor, still in the tree for VoiceOver.
        drag(300)
        shot("2-away")
        XCTAssertLessThan(pill.frame.maxY, rest.minY - 20, "Expected the row all the way out")
        XCTAssertTrue(search.exists, "The field must stay in the accessibility tree while scrolled away")
        // VoiceOver's focus arrives on the field (20 s after the row appeared): the row comes back.
        let wait = max(0, 24 - Date().timeIntervalSince(launched))
        let back = eventually(wait + 6) { search.isHittable && abs(pill.frame.minY - rest.minY) <= 1 }
        if !back, Self.isIOS26 {
            shot("3-ios26-focus-request-refused")
            throw XCTSkip("The iOS 26 Simulator refuses the app's VoiceOver focus request (measured), so the "
                          + "scroll-back can't be reached here — the snap check above passed; check on a device")
        }
        XCTAssertTrue(back, "With VoiceOver's focus on the field its row should be back at rest (pill at \(pill.frame.minY), rest \(rest.minY))")
        sleep(1)
        shot("3-voiceover-on-field")
    }

    // MARK: - Seeded rows

    private struct SeededRows {
        let marker: String
        /// Words only the seeded voice note's card shows (its description).
        let audioWords: String
        let summaryWords: String
        let noteWords: String
        /// Words only the seeded PUBLIC item's card shows (its title).
        let sharedWords: String
    }

    /// Four throwaway rows the screens need, newest last: a voice note titled with its file name
    /// (a transcript in `page_body`), a link with a markdown summary and a long title, a text item
    /// with a rich note and a location, and a PUBLIC text item with a sticky note (the Sharing
    /// section's feed link and note field; it's on the test account's own public feed for the
    /// minutes the test runs). Deleted in teardown blocks.
    @MainActor
    private func seedRows() async throws -> SeededRows {
        let (email, password) = try credentials()
        let rest = try await Rest2b.signIn(email: email, password: password)
        await rest.deleteStaleSeededRows()
        let marker = "UITEST-P16-2b-\(Int(Date().timeIntervalSince1970))"
        let audioWords = "harbour walk"
        let summaryWords = "Field guide"
        let noteWords = "Trip notes"

        let audioId = try await rest.insertItem([
            "type": "audio", "title": "\(UUID().uuidString.lowercased()).m4a", "content": "",
            "description": "\(marker) Voice memo about the \(audioWords) and the ferry times.",
            "mime_type": "audio/mp4", "file_size": 81_300,
            "page_body": "Okay, so the plan for Saturday: meet at the harbour at nine, walk the long pier, "
                + "and catch the 11:40 ferry back. Bring the blue notebook for the sketches.",
        ], attributes: ["media": ["duration_s": 42]])
        deleteAtTeardown(rest, audioId)
        try await Task.sleep(for: .milliseconds(150))

        // Links in body text and in a quote — underlined (2b fix wave), the first in view in the shot.
        let summary = """
        ## Why it matters

        Text that follows the user's **preferred size** stays readable at *every* setting, from \
        Large to the [accessibility sizes](https://developer.apple.com/design/human-interface-guidelines/typography).

        - Reading text is 17 pt at Large
        - Machine metadata is 11 pt, in `muted`
        - Controls take taps across 44 × 44 pt

        1. Set roles, never point sizes
        2. Let rows reflow when they can't fit

        > Wrap critical text instead of [truncating](https://example.com/p16-2b/truncation) it.

        See the [guidelines](https://developer.apple.com/design/human-interface-guidelines/typography) for more.
        """
        let linkId = try await rest.insertItem([
            "type": "link", "title": "\(summaryWords) to Dynamic Type for everyday reading (\(marker))",
            "url": "https://example.com/p16-2b/dynamic-type-field-guide-for-everyday-reading",
            // One line at Large and at AX3 — the reading-size test measures a line of it.
            "description": "A short primer.",
            "summary": summary, "content": "",
        ], attributes: ["link": ["flavor": "article"]])
        deleteAtTeardown(rest, linkId)
        try await Task.sleep(for: .milliseconds(150))

        let tipTap: [String: Any] = [
            "type": "doc",
            "content": [
                ["type": "heading", "attrs": ["level": 2], "content": [["type": "text", "text": noteWords]]],
                ["type": "paragraph", "content": [
                    ["type": "text", "text": "Book the "],
                    ["type": "text", "marks": [["type": "bold"]], "text": "early train"],
                    ["type": "text", "text": " and pack the "],
                    ["type": "text", "marks": [["type": "italic"]], "text": "blue notebook"],
                    ["type": "text", "text": " for the sketches."],
                ]],
                ["type": "bulletList", "content": [
                    ["type": "listItem", "content": [["type": "paragraph", "content": [["type": "text", "text": "Museum on Tuesday"]]]]],
                    ["type": "listItem", "content": [["type": "paragraph", "content": [["type": "text", "text": "Harbour walk at nine"]]]]],
                ]],
            ],
        ]
        let tipTapJSON = String(data: try JSONSerialization.data(withJSONObject: tipTap), encoding: .utf8) ?? ""
        let textId = try await rest.insertItem([
            "type": "text", "title": "\(noteWords) (\(marker))", "content": tipTapJSON,
            "description": "Weekend plans and the list to pack.",
        ], attributes: ["location": ["label": "Saratoga Springs, New York", "source": "manual"]])
        deleteAtTeardown(rest, textId)
        try await Task.sleep(for: .milliseconds(150))

        let sharedWords = "Shared packing list"
        let sharedId = try await rest.insertItem([
            "type": "text", "title": "\(sharedWords) (\(marker))", "content": "Tent, stove, two mugs.",
            "supplemental_note": "Borrow the big tent from Sam",
        ], attributes: [:], isPublic: true)
        deleteAtTeardown(rest, sharedId)
        return SeededRows(marker: marker, audioWords: audioWords, summaryWords: summaryWords, noteWords: noteWords,
                          sharedWords: sharedWords)
    }

    /// One throwaway LINK row for a contract test, titled "`label` (`marker`)" — `fields` add the
    /// rest (url, summary, page_body…) — and deleted in teardown. Runs the leak janitor first.
    @MainActor
    private func seedLinkRow(_ label: String, fields: [String: Any]) async throws -> (marker: String, title: String) {
        let (email, password) = try credentials()
        let rest = try await Rest2b.signIn(email: email, password: password)
        await rest.deleteStaleSeededRows()
        let marker = "UITEST-P16-2b-\(Int(Date().timeIntervalSince1970))"
        let title = "\(label) (\(marker))"
        var row = fields
        row["type"] = "link"
        row["title"] = title
        if row["content"] == nil { row["content"] = "" }
        let id = try await rest.insertItem(row, attributes: ["link": ["flavor": "article"]])
        deleteAtTeardown(rest, id)
        return (marker, title)
    }

    /// Deletes a seeded row once the test ends, however it ends — and says so if the delete fails.
    private func deleteAtTeardown(_ rest: Rest2b, _ id: String) {
        addTeardownBlock {
            do {
                try await rest.deleteItem(id: id)
            } catch {
                print("A11yDetailLibraryUITests: LEAKED seeded row \(id) — its delete failed: \(error)")
                await MainActor.run {
                    XCTContext.runActivity(named: "Leaked seeded row \(id) — delete failed: \(error)") { _ in }
                }
            }
        }
    }

    // MARK: - Helpers

    private func credentials() throws -> (String, String) {
        let environment = ProcessInfo.processInfo.environment
        guard let email = environment["STASH_TEST_EMAIL"], let password = environment["STASH_TEST_PASSWORD"],
              !email.isEmpty, !password.isEmpty
        else {
            XCTFail("STASH_TEST_EMAIL / STASH_TEST_PASSWORD were not set in the test runner environment")
            throw XCTSkip("missing test credentials")
        }
        return (email, password)
    }

    private static var isIOS26: Bool { ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26 }

    /// Xcode's "Audit failed to complete in time" (`performAccessibilityAudit` gave up).
    private static func isAuditTimeout(_ error: NSError) -> Bool {
        error.domain == "com.apple.xcode.xctest.accessibilityAudit" && error.code == -56
    }

    /// AX1–AX5 (SwiftUI's `dynamicTypeSize.isAccessibilitySize`).
    private static func isAccessibilitySize(_ variant: A11yVariant) -> Bool {
        variant.category.contains("Accessibility")
    }

    /// Shoots the screen on show, then audits it: `a11y-2b-<screen>-<size>`, or
    /// `a11y-2b-ios26-<screen>-<size>` on iOS 26. The shot comes first because the audit moves
    /// things: it scrolls each element it inspects into view (the sheet back to its top, the View
    /// tab's search row back to rest), and text views it touches can grow (the notes editor to its
    /// 110 pt cap). The audit's own contrast findings get pixels from a screenshot taken right
    /// after it (`audit`).
    @MainActor
    private func capture(_ app: XCUIApplication, _ screens: A11yScreens, _ screen: String,
                         _ variant: A11yVariant) throws {
        shoot(screens, screen)
        try audit(app, screen: screen, variant: variant)
    }

    @MainActor
    private func shoot(_ screens: A11yScreens, _ screen: String) {
        screens.attachScreenshot(named: (Self.isIOS26 ? "2b-ios26-" : "2b-") + screen)
    }

    @MainActor
    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    /// A control's accessibility frame is its tap target (the 44 pt overhang is part of it):
    /// at least 44 × 44 pt (43.5 — iOS 26 can report 43.99999999999994).
    @MainActor
    private func assertTarget(_ control: XCUIElement, _ name: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(control.waitForExistence(timeout: 10), "\(name) missing", file: file, line: line)
        print("A11Y target \(name) \(control.frame)")
        XCTAssertGreaterThanOrEqual(control.frame.width, 43.5, "\(name) target too narrow: \(control.frame)", file: file, line: line)
        XCTAssertGreaterThanOrEqual(control.frame.height, 43.5, "\(name) target too short: \(control.frame)", file: file, line: line)
    }

    /// The first element carrying `identifier` — for a container whose identifier lands on each of
    /// its texts (a markdown summary's blocks).
    @MainActor
    private func firstElement(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// The grid card (`card.<n>`) whose accessibility label contains `text`.
    @MainActor
    private func card(_ app: XCUIApplication, containing text: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier MATCHES %@ AND label CONTAINS %@", #"card\.[0-9]+"#, text))
            .firstMatch
    }

    /// The title: a vertical-axis field (plan 16), which XCUITest may report as a text view.
    @MainActor
    private func titleField(_ app: XCUIApplication) -> XCUIElement { field(app, "detail.title") }

    @MainActor
    private func descriptionField(_ app: XCUIApplication) -> XCUIElement { field(app, "detail.description") }

    @MainActor
    private func field(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@ AND (elementType == %d OR elementType == %d)",
                                  identifier, Int(XCUIElement.ElementType.textView.rawValue),
                                  Int(XCUIElement.ElementType.textField.rawValue)))
            .firstMatch
    }

    /// Searches the View tab for `query` and opens the card whose label contains `cardText`. A card
    /// tap drops the keyboard before the sheet opens.
    @MainActor
    private func openDetail(_ app: XCUIApplication, query: String, cardText: String, variant: A11yVariant,
                            file: StaticString = #filePath, line: UInt = #line) {
        let search = app.textFields["library.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 15), "\(variant): search missing", file: file, line: line)
        if !search.isHittable {
            for _ in 0..<3 where !search.isHittable { element(app, "library.grid").swipeDown() }
        }
        A11yScreens.tapUntilFocused(search)
        let current = (search.value as? String) ?? ""
        if !current.isEmpty, current != "Search your stash", current != "Search" {
            search.typeKey("a", modifierFlags: .command)
            search.typeText(XCUIKeyboardKey.delete.rawValue)
        }
        // Return keeps the query and drops the keyboard.
        search.typeText(query + "\n")
        _ = waitForSearchToSettle(app)
        let target = card(app, containing: cardText)
        if !findCard(app, target) {
            print("A11Y fixture: '\(cardText)' not listed at \(variant) — retyping the query once")
            for _ in 0..<4 where !search.isHittable { element(app, "library.grid").swipeDown() }
            A11yScreens.tapUntilFocused(search)
            search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: query.count) + query + "\n")
            _ = waitForSearchToSettle(app)
        }
        XCTAssertTrue(findCard(app, target), "\(variant): no card with '\(cardText)'", file: file, line: line)
        // Brought into view (at the larger sizes a card can start below the fold), then tapped.
        scrollTopIntoView(app, target)
        let frame = target.frame
        A11yScreens.tap(app, at: CGPoint(x: frame.midX, y: min(frame.minY + 40, frame.midY)))
        XCTAssertTrue(app.buttons["detail.done"].waitForExistence(timeout: 10), "\(variant): no detail sheet",
                      file: file, line: line)
    }

    /// Waits for `target` to list; the grid is lazy — it only builds the cards near the screen — so
    /// at the larger text sizes, where three cards fill several screens, it also looks further down
    /// the results (slow drags) before giving up.
    @MainActor
    private func findCard(_ app: XCUIApplication, _ target: XCUIElement) -> Bool {
        if target.waitForExistence(timeout: 15) { return true }
        for _ in 0..<8 {
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -300)),
                        withVelocity: .slow, thenHoldForDuration: 0.2)
            if target.waitForExistence(timeout: 2) { return true }
        }
        return false
    }

    /// Slow drags (no fling) until `element`'s TOP edge sits between 120 pt from the top of the
    /// screen and 240 pt from its bottom — for a card that may be taller than the screen.
    @MainActor
    private func scrollTopIntoView(_ app: XCUIApplication, _ element: XCUIElement) {
        let screen = app.windows.firstMatch.frame
        for _ in 0..<12 {
            let top = element.frame.minY
            let distance: CGFloat
            if top > screen.maxY - 240 {
                distance = min(top - (screen.minY + 200), screen.height * 0.5)
            } else if top < screen.minY + 120 {
                distance = -min((screen.minY + 200) - top, screen.height * 0.5)
            } else {
                return
            }
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: distance > 0 ? 0.7 : 0.3))
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -distance)),
                        withVelocity: .slow, thenHoldForDuration: 0.3)
        }
    }

    /// Closes the sheet and clears the search (the clear button drops the keyboard too).
    @MainActor
    private func closeDetail(_ app: XCUIApplication) {
        let close = app.buttons["detail.done"]
        close.tap()
        let closed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: close)
        XCTAssertEqual(XCTWaiter().wait(for: [closed], timeout: 5), .completed, "The sheet didn't close")
        let search = app.textFields["library.search"]
        for _ in 0..<3 where !search.isHittable { element(app, "library.grid").swipeDown() }
        A11yScreens.tapUntilFocused(search)
        let clear = app.buttons["library.search.clear"]
        if clear.waitForExistence(timeout: 3) { clear.tap() }
    }

    @MainActor
    private func waitForSearchToSettle(_ app: XCUIApplication, timeout: TimeInterval = 20) -> Bool {
        let pill = element(app, "library.search.pill")
        let settled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value != %@", "searching"), object: pill)
        return XCTWaiter().wait(for: [settled], timeout: timeout) == .completed
    }

    private func eventually(_ timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            usleep(200_000)
        }
        return condition()
    }

    /// Logs Xcode's hit-region, Dynamic Type, contrast and clipped-text findings for the screen on
    /// show (`A11Y audit …`), with where the element sits: `under-chrome` when any of it is under
    /// the tab bar, the keyboard, the detail sheet's footer or the top 50 pt (the status bar) —
    /// where the audit samples bars, not the text — and `no-element` when the audit names none. A
    /// contrast finding also gets the element's real pixels, sampled from a screenshot taken right
    /// after the audit: the darkest and lightest colours in its frame and their WCAG ratio (for a
    /// text element, its text against its background). Never fails the test on a finding: the
    /// report judges each finding. An audit that never COMPLETES is another matter — it says
    /// nothing about the screen — and is never a pass: see the second timeout below.
    @MainActor
    private func audit(_ app: XCUIApplication, screen: String, variant: A11yVariant,
                       run: AuditRun? = nil) throws {
        let perform: AuditRun = run ?? { types, handler in try app.performAccessibilityAudit(for: types, handler) }
        let window = app.windows.firstMatch.frame
        var bottom = window.maxY
        if app.tabBars.firstMatch.exists { bottom = min(bottom, app.tabBars.firstMatch.frame.minY) }
        if app.keyboards.firstMatch.exists { bottom = min(bottom, app.keyboards.firstMatch.frame.minY) }
        let delete = app.buttons["detail.delete"]
        if delete.exists { bottom = min(bottom, delete.frame.minY - 4) }
        let top = window.minY + 50
        let name = (Self.isIOS26 ? "ios26-" : "") + screen
        var findings: [(line: String, contrastFrame: CGRect?)] = []
        let record: (XCUIAccessibilityAuditIssue) throws -> Bool = { issue in
            let element = issue.element
            let frame = element?.frame ?? .zero
            let place = element == nil ? "no-element"
                : (frame.minY < top || frame.maxY > bottom) ? "under-chrome" : "on-screen"
            let label = String((element?.label ?? "").prefix(56)).replacingOccurrences(of: "\n", with: " ")
            let detail = element == nil ? " detail=\"\(issue.detailedDescription.prefix(160))\"" : ""
            let line = "A11Y audit \(name) \(variant) | \(issue.compactDescription) | \(place) | "
                + "id=\(element?.identifier ?? "-") label=\"\(label)\" frame=\(frame.integral)\(detail)"
            findings.append((line, issue.auditType == .contrast && element != nil ? frame : nil))
            return true
        }
        let types: XCUIAccessibilityAuditType = [.hitRegion, .dynamicType, .contrast, .textClipped]
        do {
            try perform(types, record)
        } catch let error as NSError where Self.isAuditTimeout(error) {
            // The audit itself can give up ("Audit failed to complete in time", about 15 s, nothing
            // reported). iOS 26.5 did, in 3 of 3 runs, on the detail facts screen at xxxL, which 17.2
            // audits in 2 s. It's a failure of the tool, not a finding: say so loudly, nudge the scroll
            // 30 pt and audit once more. A hung app would still fail the test, here (below) or at the
            // drag or the next step.
            print("A11Y audit \(name) \(variant) | AUDIT TIMED OUT (\(error.localizedDescription)); "
                  + "scrolling 30 pt and auditing again")
            findings.removeAll()
            let start = app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.04, dy: 0.5))
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -30)))
            sleep(1)
            do {
                try perform(types, record)
                print("A11Y audit \(name) \(variant) | the second audit completed")
            } catch let error as NSError where Self.isAuditTimeout(error) {
                // Twice: nothing was audited, and "no findings" would be a lie. This helper never fails
                // a test on a finding, but the test must not PASS as though this screen had been
                // looked at. So the screen is recorded, the matrix carries on (its other checks and
                // shots still count), and the test ends as SKIPPED, naming it
                // (`skipIfAnAuditNeverFinished`) — a skip and not a failure because a double timeout
                // with the app still answering is the tool's known hang (above), not something the
                // app did. If the app has stopped answering, it is not that: fail, here and now.
                let answers = app.state == .runningForeground && app.windows.firstMatch.waitForExistence(timeout: 10)
                XCTAssertTrue(answers, "\(name) \(variant): Xcode's audit timed out twice and the app has stopped "
                              + "answering — a hang in the app, not the audit tool's")
                print("A11Y audit \(name) \(variant) | AUDIT NEVER COMPLETED (timed out twice, the app "
                      + "\(answers ? "still answers" : "does NOT answer")): no findings for this screen (its shot is "
                      + "attached); the test will end as skipped")
                unfinishedAudits.append("\(name) \(variant)")
                return
            }
        }
        let pixels = findings.contains { $0.contrastFrame != nil }
            ? ScreenPixels(XCUIScreen.main.screenshot(), pointWidth: window.width) : nil
        for finding in findings {
            if let frame = finding.contrastFrame, let pixels {
                print(finding.line + " | pixels " + pixels.contrast(in: frame))
            } else {
                print(finding.line)
            }
        }
    }

    /// Ends the test as SKIPPED — never passed — if an `audit` in it never completed (it timed out,
    /// then timed out again after a scroll, with the app still answering). Call it as the last line
    /// of every test that audits, so a missing audit can't pass for a clean one. The reason starts
    /// "UNVERIFIED, RE-RUN THIS TEST", so it can't be read as one of the suite's by-design skips (the
    /// env-gated VoiceOver probe, the OS-specific scroll skip), which say what to set or why instead.
    private func skipIfAnAuditNeverFinished() throws {
        guard !unfinishedAudits.isEmpty else { return }
        throw XCTSkip("UNVERIFIED, RE-RUN THIS TEST — Xcode's accessibility audit never completed on "
                      + "\(unfinishedAudits.joined(separator: ", ")): it timed out, and again after a 30 pt scroll, while "
                      + "the app kept answering — the audit tool's own hang (seen on iOS 26.5 at xxxL). Everything else in "
                      + "this test passed; those screens have no audit findings from this run (their shots are attached). "
                      + "This is not one of the suite's by-design skips.")
    }
}

/// A screenshot's pixels, for checking a contrast finding against what was really drawn: the
/// darkest and lightest colours inside an element's frame (by WCAG relative luminance) and the
/// contrast ratio between them — for a text element, its text against its background.
private struct ScreenPixels {
    private let width: Int
    private let height: Int
    private let scale: CGFloat
    private let bytes: [UInt8]

    init?(_ screenshot: XCUIScreenshot, pointWidth: CGFloat) {
        guard let cg = screenshot.image.cgImage, pointWidth > 0,
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        width = cg.width
        height = cg.height
        scale = CGFloat(cg.width) / pointWidth
        var buffer = [UInt8](repeating: 0, count: cg.width * cg.height * 4)
        guard let context = CGContext(data: &buffer, width: cg.width, height: cg.height, bitsPerComponent: 8,
                                      bytesPerRow: cg.width * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        bytes = buffer
    }

    func contrast(in frame: CGRect) -> String {
        func linear(_ c: UInt8) -> Double {
            let v = Double(c) / 255
            return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        var darkest: (lum: Double, hex: String) = (2, "")
        var lightest: (lum: Double, hex: String) = (-1, "")
        let x0 = max(0, Int(frame.minX * scale)), x1 = min(width, Int(frame.maxX * scale))
        let y0 = max(0, Int(frame.minY * scale)), y1 = min(height, Int(frame.maxY * scale))
        guard x0 < x1, y0 < y1 else { return "(off screen)" }
        for y in y0..<y1 {
            for x in x0..<x1 {
                let i = (y * width + x) * 4
                let (r, g, b) = (bytes[i], bytes[i + 1], bytes[i + 2])
                let lum = 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
                if lum < darkest.lum { darkest = (lum, String(format: "#%02x%02x%02x", r, g, b)) }
                if lum > lightest.lum { lightest = (lum, String(format: "#%02x%02x%02x", r, g, b)) }
            }
        }
        let ratio = (lightest.lum + 0.05) / (darkest.lum + 0.05)
        return "darkest \(darkest.hex) on lightest \(lightest.hex) = " + String(format: "%.2f:1", ratio)
    }

    /// The darkest colour inside `frame` (by WCAG relative luminance) and its contrast on white —
    /// for a text whose glyph cores are its colour (2b fix wave, recipe R-2).
    func darkest(in frame: CGRect) -> (hex: String, contrastOnWhite: Double) {
        func linear(_ c: UInt8) -> Double {
            let v = Double(c) / 255
            return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        guard let (x0, x1, y0, y1) = pixelBounds(frame) else { return ("(off screen)", 0) }
        var darkest: (lum: Double, hex: String) = (2, "")
        for y in y0..<y1 {
            for x in x0..<x1 {
                let i = (y * width + x) * 4
                let (r, g, b) = (bytes[i], bytes[i + 1], bytes[i + 2])
                let lum = 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
                if lum < darkest.lum { darkest = (lum, String(format: "#%02x%02x%02x", r, g, b)) }
            }
        }
        return (darkest.hex, 1.05 / (darkest.lum + 0.05))
    }

    /// The longest unbroken horizontal run of pixels that `matches` inside `frame`: its length and
    /// its row, in screen points, and the colour at its middle (2b fix wave: a link's underline).
    func longestRun(in frame: CGRect, where matches: (UInt8, UInt8, UInt8) -> Bool)
        -> (points: CGFloat, y: CGFloat, hex: String) {
        guard let (x0, x1, y0, y1) = pixelBounds(frame) else { return (0, 0, "-") }
        var best = 0, bestRow = 0, bestEnd = 0
        for y in y0..<y1 {
            var run = 0
            for x in x0..<x1 {
                let i = (y * width + x) * 4
                if matches(bytes[i], bytes[i + 1], bytes[i + 2]) {
                    run += 1
                    if run > best { (best, bestRow, bestEnd) = (run, y, x) }
                } else {
                    run = 0
                }
            }
        }
        guard best > 0 else { return (0, 0, "-") }
        let i = (bestRow * width + bestEnd - best / 2) * 4
        return (CGFloat(best) / scale, CGFloat(bestRow) / scale,
                String(format: "#%02x%02x%02x", bytes[i], bytes[i + 1], bytes[i + 2]))
    }

    /// Mirrors `StashColor.linkUnderline` (`StashDesign.swift`): solid ink in v2.
    /// A UI test cannot import the app, so keep these reference tokens in sync.
    static let linkUnderlineAlpha = 1.0
    private static let ink: (r: Double, g: Double, b: Double) = (0, 0, 0)

    /// The line's fully covered ink pixels, allowing six levels per channel for rendering.
    /// Translucent ink and the old violet recipe miss this range. Black glyph cores can
    /// match too, so the caller still requires an unbroken 30 pt run inside the text block;
    /// no glyph stroke is that long. The quote's vertical rule cannot satisfy that length.
    static func isLinkUnderline(_ r: UInt8, _ g: UInt8, _ b: UInt8) -> Bool {
        let a = linkUnderlineAlpha, tolerance = 6.0
        func expected(_ c: Double) -> Double { 255 - a * (255 - c) }
        return abs(Double(r) - expected(ink.r)) <= tolerance
            && abs(Double(g) - expected(ink.g)) <= tolerance
            && abs(Double(b) - expected(ink.b)) <= tolerance
    }

    private func pixelBounds(_ frame: CGRect) -> (Int, Int, Int, Int)? {
        let x0 = max(0, Int(frame.minX * scale)), x1 = min(width, Int(frame.maxX * scale))
        let y0 = max(0, Int(frame.minY * scale)), y1 = min(height, Int(frame.maxY * scale))
        return x0 < x1 && y0 < y1 ? (x0, x1, y0, y1) : nil
    }
}

/// A password-grant REST session for the test account — seeds and deletes this file's throwaway
/// rows independently of the app. The public project URL + anon key are the ones `StashConfig.swift`
/// ships (not secrets); a UI-test bundle can't import StashKit.
private struct Rest2b: Sendable {
    static let baseURL = URL(string: "https://uqqsgmwkvslaomzxptnp.supabase.co")!
    static let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVxcXNnbXdrdnNsYW9tenhwdG5wIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTA2MjU0ODcsImV4cCI6MjA2NjIwMTQ4N30.vGWb1EdshtLFLpUHQ54Vy2CDmuPVCTbvc8UYW6_cvmE"

    struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    let token: String
    let userId: String

    static func signIn(email: String, password: String) async throws -> Rest2b {
        var request = URLRequest(url: baseURL.appending(path: "/auth/v1/token")
            .appending(queryItems: [URLQueryItem(name: "grant_type", value: "password")]))
        request.httpMethod = "POST"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["email": email, "password": password])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard succeeded(response),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = object["access_token"] as? String,
              let user = object["user"] as? [String: Any], let userId = user["id"] as? String
        else { throw Failure(description: "test-account sign-in failed") }
        return Rest2b(token: token, userId: userId)
    }

    private static func succeeded(_ response: URLResponse) -> Bool {
        (response as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } ?? false
    }

    private func request(_ path: String, query: [URLQueryItem] = [], method: String = "GET") -> URLRequest {
        var request = URLRequest(url: Self.baseURL.appending(path: path).appending(queryItems: query))
        request.httpMethod = method
        request.setValue(Self.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    func insertItem(_ fields: [String: Any], attributes: [String: Any] = [:], isPublic: Bool = false) async throws -> String {
        var body = fields
        body["user_id"] = userId
        body["is_public"] = isPublic
        body["attributes"] = attributes
        var request = request("/rest/v1/items", method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=representation", forHTTPHeaderField: "Prefer")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard Self.succeeded(response),
              let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let id = rows.first?["id"] as? String
        else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw Failure(description: "throwaway insert failed (status \(status)): \(String(data: data, encoding: .utf8) ?? "")")
        }
        return id
    }

    /// 2b review N-8: a run killed before its teardown blocks run (a timeout, a stopped runner)
    /// leaks its seeded rows. So every seeding first deletes THIS file's leftovers: rows with
    /// `UITEST-P16-2b-` in the title or description (the voice note carries it in its description)
    /// created more than `age` ago — 30 minutes, three times the longest test here (the detail
    /// matrix, ~10), so a run going on the other simulator keeps its rows. Each row is re-checked
    /// before its delete, and a `UITEST-FIXTURE` row is never touched. It logs how many stale rows
    /// it found, 0 included (2bf review m5: an empty lookup was silent), and each delete; a failure
    /// only logs.
    func deleteStaleSeededRows(olderThan age: TimeInterval = 30 * 60) async {
        let cutoff = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-age))
        let query = [
            URLQueryItem(name: "select", value: "id,title,description,created_at"),
            URLQueryItem(name: "or", value: "(title.like.*UITEST-P16-2b-*,description.like.*UITEST-P16-2b-*)"),
            URLQueryItem(name: "created_at", value: "lt.\(cutoff)"),
        ]
        do {
            let (data, response) = try await URLSession.shared.data(for: request("/rest/v1/items", query: query))
            guard Self.succeeded(response),
                  let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                print("A11yDetailLibraryUITests janitor: the lookup failed (status \((response as? HTTPURLResponse)?.statusCode ?? -1))")
                return
            }
            print("A11yDetailLibraryUITests janitor: \(rows.count) stale UITEST-P16-2b- row(s) created before \(cutoff)")
            for row in rows {
                guard let id = row["id"] as? String else { continue }
                let title = row["title"] as? String ?? "", description = row["description"] as? String ?? ""
                let text = title + " " + description
                guard text.contains("UITEST-P16-2b-"), !text.contains("UITEST-FIXTURE") else { continue }
                do {
                    try await deleteItem(id: id)
                    print("A11yDetailLibraryUITests janitor: deleted leaked row \(id) '\(title.prefix(60))' "
                          + "from \(row["created_at"] as? String ?? "?")")
                } catch {
                    print("A11yDetailLibraryUITests janitor: couldn't delete leaked row \(id): \(error)")
                }
            }
        } catch {
            print("A11yDetailLibraryUITests janitor: \(error)")
        }
    }

    func deleteItem(id: String) async throws {
        var tries = 1
        while true {
            do {
                let (_, response) = try await URLSession.shared.data(
                    for: request("/rest/v1/items", query: [URLQueryItem(name: "id", value: "eq.\(id)")], method: "DELETE"))
                guard Self.succeeded(response) else { throw Failure(description: "throwaway delete failed for \(id)") }
                return
            } catch let error as URLError where tries < 3 {
                print("REST retry after URLError \(error.code.rawValue)")
                tries += 1
                try await Task.sleep(for: .seconds(1))
            }
        }
    }
}
