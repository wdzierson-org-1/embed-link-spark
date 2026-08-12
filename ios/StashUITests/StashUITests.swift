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

        // 2. Type chip narrows server-side; the fixture account has link items.
        let linksChip = app.buttons["library.chip.links"]
        XCTAssertTrue(linksChip.waitForExistence(timeout: 5), "Links chip not found")
        linksChip.tap()
        XCTAssertTrue(anyElement("card.0").waitForExistence(timeout: 15), "Expected at least one Links card")

        // Reset to All so search/tag steps below aren't silently scoped to Links —
        // the tag-filter step selects a tag attached to a *note*, not a link, and
        // "Links ∩ ios-test" is correctly empty, which would otherwise read as a
        // false failure of the tag filter rather than a leftover chip selection.
        app.buttons["library.chip.all"].tap()
        XCTAssertTrue(anyElement("card.0").waitForExistence(timeout: 15), "Expected cards after resetting to All")

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

        // The search field still holds keyboard focus after being cleared by backspace,
        // which (standard `.searchable` behavior) replaces the trailing toolbar items
        // with a system "Cancel" button — confirmed via an accessibility-tree dump.
        // Dismiss it (text is already empty, so Cancel's clear-text side effect is a
        // no-op) before the tag button is reachable again.
        let cancelButton = app.buttons["Cancel"]
        XCTAssertTrue(cancelButton.waitForExistence(timeout: 5), "Expected a Cancel button while search is focused")
        cancelButton.tap()
        XCTAssertTrue(anyElement("card.0").waitForExistence(timeout: 15), "Expected cards after dismissing search focus")

        // 4. Tag filter narrows via the item_tags!inner join (fixture: "ios-test" tags
        // exactly one note), then Clear restores the unfiltered grid.
        app.buttons["library.tagFilterButton"].tap()
        let iosTestTagRow = app.buttons["tagfilter.tag.ios-test"]
        XCTAssertTrue(iosTestTagRow.waitForExistence(timeout: 10), "ios-test tag row not found in the filter sheet")
        iosTestTagRow.tap()
        app.buttons["tagfilter.done"].tap()
        XCTAssertTrue(anyElement("card.0").waitForExistence(timeout: 15), "Expected at least one card for the ios-test tag filter")

        app.buttons["library.tagFilterButton"].tap()
        XCTAssertTrue(app.buttons["tagfilter.clear"].waitForExistence(timeout: 5), "Clear button not found in the filter sheet")
        app.buttons["tagfilter.clear"].tap()
        app.buttons["tagfilter.done"].tap()
        XCTAssertTrue(anyElement("card.0").waitForExistence(timeout: 15), "Expected cards after clearing the tag filter")

        // 5. Sign out via the avatar menu returns to the sign-in screen.
        app.buttons["library.menu"].tap()
        let signOutById = app.buttons["library.signOut"]
        let signOutButton = signOutById.waitForExistence(timeout: 3) ? signOutById : app.buttons["Sign Out"]
        XCTAssertTrue(signOutButton.waitForExistence(timeout: 5), "Sign Out menu item not found")
        signOutButton.tap()

        XCTAssertTrue(app.textFields["signin.email"].waitForExistence(timeout: 10), "Expected the sign-in screen after signing out")
    }

    /// Opens the read-only detail sheet for one permanent UITEST-FIXTURE card of each of
    /// [link, text, image, audio] (found via a unique local-search substring, not grid
    /// position, so ordering changes can't break this), asserting the segmented tab set
    /// matches what `contentTabsConfig(for:)` predicts for that type — and, audio only, that
    /// the Transcript tab shows real, non-empty text (the fixture's Whisper transcript).
    /// After each assertion, prints a checkpoint marker to stderr (unbuffered even when
    /// redirected to a file, unlike stdout) and sleeps briefly so an external
    /// `xcrun simctl io <udid> screenshot` can capture the open sheet mid-test — same
    /// technique as testTagFilterSheetOpens below, one checkpoint per type.
    /// Note: presenting the sheet doesn't resign the presenting view's search-field
    /// keyboard (confirmed empirically — neither a submit-via-return, a tap on an unrelated
    /// button, nor a scroll gesture dismissed it), so it stays visible under the sheet in
    /// every screenshot here — harmless for the (accessibility-tree-based) assertions;
    /// link/text/audio's header and tabs still fit above it, only the image checkpoint's
    /// hero image pushes its header below the fold in the screenshot (task-12-report.md).
    func testDetailSheets() throws {
        let (email, password) = try testCredentials()
        let app = XCUIApplication()
        XCTAssertTrue(signInAndReachLibrary(app, email: email, password: password),
                      "Expected the tab bar to appear after sign-in")

        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 15), "Search field not found")

        func card0() -> XCUIElement { app.descendants(matching: .any)["card.0"] }

        func openAndCheck(search: String, expectedTabs: [String], forbiddenTabs: [String],
                           checkpoint: String, extra: () -> Void = {}) {
            searchField.tap()
            searchField.typeText(search)
            XCTAssertTrue(card0().waitForExistence(timeout: 10), "Expected a card for search '\(search)'")
            card0().tap()

            let done = app.buttons["detail.done"]
            XCTAssertTrue(done.waitForExistence(timeout: 10), "Detail sheet did not present for '\(search)'")
            for label in expectedTabs {
                XCTAssertTrue(app.buttons[label].waitForExistence(timeout: 5),
                              "Expected '\(label)' tab for '\(search)'")
            }
            for label in forbiddenTabs {
                XCTAssertFalse(app.buttons[label].exists, "Did not expect '\(label)' tab for '\(search)'")
            }
            extra()

            FileHandle.standardError.write("SCREENSHOT_CHECKPOINT: \(checkpoint)\n".data(using: .utf8)!)
            sleep(5)

            done.tap()
            XCTAssertTrue(searchField.waitForExistence(timeout: 10), "Expected the library after dismiss")
            searchField.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: search.count))
        }

        openAndCheck(search: "link one", expectedTabs: ["Summary", "Original Content", "Notes"],
                     forbiddenTabs: ["Transcript"], checkpoint: "link")

        openAndCheck(search: "note one", expectedTabs: ["Notes"],
                     forbiddenTabs: ["Summary", "Original Content", "Transcript"], checkpoint: "text")

        openAndCheck(search: "image one", expectedTabs: ["Notes"],
                     forbiddenTabs: ["Summary", "Original Content", "Transcript"], checkpoint: "image")

        openAndCheck(search: "audio one", expectedTabs: ["Notes", "Transcript"],
                     forbiddenTabs: ["Summary", "Original Content"], checkpoint: "audio") {
            app.buttons["Transcript"].tap()
            let transcript = app.descendants(matching: .any)["detail.transcriptText"]
            XCTAssertTrue(transcript.waitForExistence(timeout: 10), "Transcript text container not found")
            XCTAssertFalse(transcript.label.isEmpty, "Expected non-empty transcript text")
            XCTAssertNotEqual(transcript.label, "Transcription in progress…",
                              "Expected a real transcript, not the in-progress placeholder")
        }
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

    /// Add is the plan-2 launch tab: the composer is reachable at launch with no tab tap, so
    /// this types a marker note straight in, saves it, and confirms it lands on the View tab
    /// via the same realtime path `testLibrarySmoke` already exercises. The created row is
    /// disposable — deleted via REST in the shell after this test runs, unlike the permanent
    /// UITEST-FIXTURE rows `testDetailSheets`/`testLibrarySmoke` depend on.
    func testCaptureSmoke() throws {
        let (email, password) = try testCredentials()
        let app = XCUIApplication()
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

        func anyElement(_ identifier: String) -> XCUIElement { app.descendants(matching: .any)[identifier] }

        // Add is the launch tab (plan 2) — the editor must appear without tapping any tab.
        let editor = anyElement("capture.editor")
        XCTAssertTrue(editor.waitForExistence(timeout: 15),
                      "Expected the capture editor to appear on launch (Add is the launch tab)")

        let marker = "UITEST-CAPTURE: smoke note \(Int(Date().timeIntervalSince1970))"
        editor.tap()
        editor.typeText(marker)

        app.buttons["capture.save"].tap()

        XCTAssertTrue(anyElement("capture.toast").waitForExistence(timeout: 10),
                      "Expected a success toast after saving")

        app.tabBars.buttons["View"].tap()
        XCTAssertTrue(anyElement("library.grid").waitForExistence(timeout: 15), "Library grid did not appear")

        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 10), "Search field not found")
        searchField.tap()
        searchField.typeText("UITEST-CAPTURE: smoke note")
        XCTAssertTrue(anyElement("card.0").waitForExistence(timeout: 10),
                      "Expected the newly-captured card to appear via realtime")
    }

    /// Debounced field autosave + notes-append + detail-sheet persistence, exercised against the
    /// permanent "UITEST-FIXTURE: note one" fixture. This test mutates that fixture's title
    /// (restored below via the same in-app editing path it was changed with) and its content
    /// (mutated by the notes-append step, which can only ever ADD a paragraph — there's no
    /// in-app "undo" for that). Content is restored via a REST PATCH run in the shell
    /// immediately after this test, using the original content captured via REST *before* the
    /// test runs; see task-8-report.md for the exact commands and verification GETs.
    ///
    /// Title edits go through `replaceText` (see its doc comment) rather than trying to position
    /// the caret and append/trim a suffix — two earlier approaches (a coordinate tap near the
    /// field's trailing edge; a long-press for the system edit callout) both empirically landed
    /// the caret mid-string instead of at the end, corrupting the title (see task-8-report.md).
    /// `replaceText` makes no assumption about caret position at all.
    func testEditSmoke() throws {
        let (email, password) = try testCredentials()
        let app = XCUIApplication()
        XCTAssertTrue(signInAndReachLibrary(app, email: email, password: password),
                      "Expected the tab bar to appear after sign-in")

        func anyElement(_ identifier: String) -> XCUIElement { app.descendants(matching: .any)[identifier] }
        func card0() -> XCUIElement { app.descendants(matching: .any)["card.0"] }

        // Empirically (see task-8-report.md), neither a coordinate tap near the trailing edge
        // nor a long-press-for-callout reliably lands the caret at a known position in this
        // SwiftUI TextField — both were observed inserting mid-string instead. What IS reliable:
        // reading the field's *actual current value* (never assumed) and backspacing exactly
        // that many characters, looping (re-tapping each round, since the field's on-screen
        // width-vs-content ratio — and hence where a plain center tap's caret lands — changes as
        // the string shrinks) until the field reports empty. This makes no assumption about
        // caret position at all; it only assumes backspace deletes characters before the caret,
        // which is universally true. Bounded to 5 rounds so a genuine failure loops rather than
        // hangs; the caller's own post-condition assertion is the real safety net regardless.
        func clearField(_ field: XCUIElement, placeholder: String) {
            for _ in 0..<5 {
                let current = (field.value as? String) ?? ""
                if current.isEmpty || current == placeholder { return }
                field.tap()
                field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
            }
        }

        func replaceText(_ field: XCUIElement, placeholder: String, with newValue: String) {
            clearField(field, placeholder: placeholder)
            field.tap()
            field.typeText(newValue)
        }

        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 15), "Search field not found")
        searchField.tap()
        searchField.typeText("note one")
        XCTAssertTrue(card0().waitForExistence(timeout: 15), "Expected a card for 'note one'")
        card0().tap()

        let originalTitle = "UITEST-FIXTURE: note one"
        let epoch = Int(Date().timeIntervalSince1970)
        let editedTitle = "\(originalTitle) (edited \(epoch))"

        let titleField = anyElement("detail.title")
        XCTAssertTrue(titleField.waitForExistence(timeout: 10), "Title field not found")
        replaceText(titleField, placeholder: "Untitled", with: editedTitle)
        XCTAssertEqual(titleField.value as? String, editedTitle,
                       "Expected the title field to show the edit immediately")

        // Debounce is 400ms; give the save round trip margin, then hold for the external
        // screenshot rig (same checkpoint technique as testDetailSheets/testTagFilterSheetOpens).
        sleep(2)
        FileHandle.standardError.write("SCREENSHOT_CHECKPOINT: edit\n".data(using: .utf8)!)
        sleep(5)

        app.buttons["detail.done"].tap()
        XCTAssertTrue(searchField.waitForExistence(timeout: 10), "Expected the library after dismiss")

        // Reopen — searching the ORIGINAL substring still matches since the edit only appended.
        XCTAssertTrue(card0().waitForExistence(timeout: 15), "Expected the edited card to still be findable")
        card0().tap()

        let reopenedTitleField = anyElement("detail.title")
        XCTAssertTrue(reopenedTitleField.waitForExistence(timeout: 10), "Title field not found on reopen")
        XCTAssertEqual(reopenedTitleField.value as? String, editedTitle,
                       "Expected the edited title to have persisted across dismiss/reopen")

        // Notes append.
        let noteMarker = "appended-\(epoch)"
        let notesField = anyElement("detail.notesComposer.field")
        XCTAssertTrue(notesField.waitForExistence(timeout: 10), "Notes composer field not found")
        notesField.tap()
        notesField.typeText(noteMarker)
        app.buttons["detail.notesComposer.add"].tap()

        let notesText = anyElement("detail.notesText")
        XCTAssertTrue(notesText.waitForExistence(timeout: 10), "Notes text not found")
        let notesAppeared = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label CONTAINS %@", noteMarker), object: notesText)
        XCTAssertEqual(XCTWaiter().wait(for: [notesAppeared], timeout: 10), .completed,
                       "Expected the appended note to render in Notes")

        // Restore: back to exactly the canonical fixture title. Content is restored via REST in
        // the shell after this test (see above).
        replaceText(reopenedTitleField, placeholder: "Untitled", with: originalTitle)
        XCTAssertEqual(reopenedTitleField.value as? String, originalTitle,
                       "Expected the title to be restored to exactly the original fixture title")
        sleep(2)

        app.buttons["detail.done"].tap()
        XCTAssertTrue(searchField.waitForExistence(timeout: 10), "Expected the library after final dismiss")
    }

    /// Delete flow: creates a disposable item via the add-note REST endpoint before this test
    /// runs (never touches the permanent UITEST-FIXTURE rows — see task-8-report.md for the
    /// exact seed/verify commands), opens it from the grid, deletes it through the in-app
    /// confirmation dialog, and asserts it's gone from the grid. Absence from the server is
    /// verified separately via REST in the shell after this test runs.
    func testDeleteSmoke() throws {
        guard let marker = ProcessInfo.processInfo.environment["STASH_DELETE_MARKER"], !marker.isEmpty else {
            XCTFail("STASH_DELETE_MARKER was not set — seed a disposable item via REST before running this test")
            throw XCTSkip("missing STASH_DELETE_MARKER")
        }
        let (email, password) = try testCredentials()
        let app = XCUIApplication()
        XCTAssertTrue(signInAndReachLibrary(app, email: email, password: password),
                      "Expected the tab bar to appear after sign-in")

        func anyElement(_ identifier: String) -> XCUIElement { app.descendants(matching: .any)[identifier] }
        func card0() -> XCUIElement { app.descendants(matching: .any)["card.0"] }

        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 15), "Search field not found")
        searchField.tap()
        searchField.typeText(marker)
        XCTAssertTrue(card0().waitForExistence(timeout: 15), "Expected the disposable item's card to appear")
        card0().tap()

        let deleteButton = app.buttons["detail.delete"]
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 10), "Delete button not found in detail sheet")
        deleteButton.tap()

        let confirmButton = app.buttons["Delete"]
        XCTAssertTrue(confirmButton.waitForExistence(timeout: 5), "Delete confirmation dialog did not appear")
        confirmButton.tap()

        XCTAssertTrue(anyElement("library.empty").waitForExistence(timeout: 15),
                      "Expected no results for the deleted item's marker search after deletion")
    }

    /// Tags manager + public toggle/sticky-note lifecycle (Task 9), exercised against the
    /// permanent `UITEST-FIXTURE: note two` fixture — a different fixture than testEditSmoke's
    /// "note one" so the two tests' mutations never land on the same row. Leaves the fixture
    /// exactly as found: the "plan2-smoke" tag is added then removed (item_tags row count
    /// restored to its pre-test baseline, REST-verified in the shell after this test), and
    /// public/sticky are toggled on then off (`is_public`/`supplemental_note` restored to
    /// false/nil, also REST-verified). Note one's "ios-test" tag is never touched by this test.
    ///
    /// This is also the live proof of `increment_tag_usage`'s scalar-UUID RPC decode
    /// (`SupabaseItemPatcher.addTag`, flagged as untested against a live server in
    /// task-6-report.md) — the tag-add step below only passes end-to-end if that decode is
    /// actually correct, since a decode failure would throw before the chip ever renders.
    func testTagsAndPublicSmoke() throws {
        let (email, password) = try testCredentials()
        let app = XCUIApplication()
        XCTAssertTrue(signInAndReachLibrary(app, email: email, password: password),
                      "Expected the tab bar to appear after sign-in")

        func anyElement(_ identifier: String) -> XCUIElement { app.descendants(matching: .any)[identifier] }
        func card0() -> XCUIElement { app.descendants(matching: .any)["card.0"] }

        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 15), "Search field not found")
        searchField.tap()
        searchField.typeText("note two")
        XCTAssertTrue(card0().waitForExistence(timeout: 15), "Expected a card for 'note two'")
        card0().tap()

        XCTAssertTrue(anyElement("detail.done").waitForExistence(timeout: 10), "Detail sheet did not present")

        // --- Tags: add "plan2-smoke" (return-to-submit), assert the chip appears, remove it
        // (tap-to-remove — the whole chip is the remove control, see ItemTagsSection.swift),
        // assert it's gone. ---
        let tagInput = anyElement("detail.tags.input")
        XCTAssertTrue(tagInput.waitForExistence(timeout: 10), "Tag input field not found")
        tagInput.tap()
        tagInput.typeText("plan2-smoke\n")

        let tagChip = app.buttons["detail.tags.chip.plan2-smoke"]
        XCTAssertTrue(tagChip.waitForExistence(timeout: 15),
                      "Expected the 'plan2-smoke' tag chip to appear after adding")

        FileHandle.standardError.write("SCREENSHOT_CHECKPOINT: tags\n".data(using: .utf8)!)
        sleep(3)

        tagChip.tap()
        let chipGone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: tagChip)
        XCTAssertEqual(XCTWaiter().wait(for: [chipGone], timeout: 15), .completed,
                       "Expected the tag chip to disappear after removal")

        // --- Public toggle ON, sticky note text, toggle OFF (un-share confirm since a sticky
        // note is now present), assert the sticky field disappears once confirmed. ---
        let publicToggle = anyElement("detail.public.toggle")
        XCTAssertTrue(publicToggle.waitForExistence(timeout: 10), "Public toggle not found")
        publicToggle.tap()

        let stickyField = anyElement("detail.public.sticky")
        XCTAssertTrue(stickyField.waitForExistence(timeout: 10), "Sticky note field did not appear after enabling public")
        stickyField.tap()
        stickyField.typeText("UITEST-FIXTURE sticky check")

        // Let the sticky note's own debounced autosave land (same 400ms path as title/
        // description) before toggling off, so the un-share confirm's "a note is present" check
        // — and the un-share patch's own read of the note — see the saved value rather than
        // racing the pending debounce (see PublicToggleSection.swift's header doc comment).
        sleep(2)
        FileHandle.standardError.write("SCREENSHOT_CHECKPOINT: public\n".data(using: .utf8)!)
        sleep(3)

        publicToggle.tap()
        let confirmButton = app.buttons["Make Private"]
        XCTAssertTrue(confirmButton.waitForExistence(timeout: 5), "Un-share confirmation dialog did not appear")
        confirmButton.tap()

        let stickyGone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: stickyField)
        XCTAssertEqual(XCTWaiter().wait(for: [stickyGone], timeout: 15), .completed,
                       "Expected the sticky note field to disappear after un-sharing")

        sleep(2)   // margin for the un-share PATCH to land before this test's REST verification
        app.buttons["detail.done"].tap()
        XCTAssertTrue(searchField.waitForExistence(timeout: 10), "Expected the library after dismiss")
    }

    /// Ask tab: streaming Q&A against production (one real model call per run — expected and
    /// budgeted), citation chip, detail sheet. Deliberately does NOT assume `ask.bubble.0` is the
    /// user question / `ask.bubble.1` is the assistant reply: chat history is durable (Task 2
    /// persists every exchange to `conversations`/`messages`), so a second run of this same test
    /// against the same account restores prior turns first and appends after them — the indices
    /// this run lands on depend on how much history already exists. Instead this finds whichever
    /// `ask.bubble.*`/`ask.sources.*` elements are LAST in the tree right after sending, which are
    /// always the freshly-appended ones regardless of any earlier accumulated history.
    ///
    /// Asks about the permanent document fixture ("persimmons") per the plan's own note that its
    /// extracted `page_body` guarantees retrievable content, so a source chip is expected.
    func testAskSmoke() throws {
        let (email, password) = try testCredentials()
        let app = XCUIApplication()
        XCTAssertTrue(signInAndReachLibrary(app, email: email, password: password),
                      "Expected the tab bar to appear after sign-in")

        func anyElement(_ identifier: String) -> XCUIElement { app.descendants(matching: .any)[identifier] }

        app.tabBars.buttons["Ask"].tap()

        let input = anyElement("ask.input")
        XCTAssertTrue(input.waitForExistence(timeout: 10), "Ask input field did not appear")
        input.tap()
        input.typeText("What do my saved items say about persimmons?")

        let sendButton = app.buttons["ask.send"]
        XCTAssertTrue(sendButton.waitForExistence(timeout: 5), "Send button not found")
        XCTAssertTrue(sendButton.isEnabled, "Expected Send to be enabled for non-empty input")
        sendButton.tap()

        // Whichever `ask.bubble.<N>` is currently LAST in the tree right after sending is the
        // freshly-appended assistant reply (appended immediately after the user's own bubble,
        // well before the network stream produces its first token) — see the doc comment above.
        //
        // Needs to match the identifier EXACTLY as "<prefix><digits>", not just BEGINSWITH: an
        // assistant bubble also carries sibling identifiers like "ask.bubble.5.speak",
        // "ask.bubble.5.thumbsUp" for its action row, which themselves begin with the exact same
        // "ask.bubble." prefix — a plain BEGINSWITH query matches those too, and once the action
        // row renders (as soon as any content has streamed in) one of THEM sorts last in the tree,
        // not the bare bubble text. Confirmed live: this silently resolved to "ask.bubble.5.speak"
        // on a real second-suite run, which made the derived "ask.sources.5.speak" lookup fail
        // (never existing) — the assistant's actual reply/sources were fine; only this query was
        // wrong. A first fix attempt used an NSPredicate `MATCHES` (regex) — confirmed live that
        // XCUITest's identifier-query predicate translation doesn't support it (matched nothing at
        // all, "Assistant bubble did not appear"). A second fix attempt used BEGINSWITH (which IS
        // well-supported) filtered to an all-digit suffix in plain Swift, but held onto the
        // resulting `XCUIElement` (from `allElementsBoundByIndex`) and polled `.label` on it
        // directly — that's still an INDEX-bound reference under the hood, and the thread's
        // `LazyVStack` virtualizes bubbles that scroll out of the rendered window as the answer
        // streams in and auto-scroll keeps pace; the match count shifting from under it broke
        // re-resolution mid-poll ("Failed to get matching snapshot: No matches found for Element at
        // index 20"). Fix: resolve the identifier STRING once via this filter, then look the
        // element back up by EXACT identifier for every subsequent read — an identity-based lookup
        // re-resolves correctly regardless of how the surrounding query's result set shifts,
        // exactly like every other identifier lookup in this file already does.
        func lastBubbleIdentifier(timeout: TimeInterval) -> String? {
            let prefix = "ask.bubble."
            let deadline = Date().addingTimeInterval(timeout)
            repeat {
                let candidates = app.descendants(matching: .any)
                    .matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix))
                    .allElementsBoundByIndex
                if let match = candidates.last(where: { el in
                    let suffix = el.identifier.dropFirst(prefix.count)
                    return !suffix.isEmpty && suffix.allSatisfy(\.isNumber)
                })?.identifier {
                    return match
                }
                usleep(300_000)
            } while Date() < deadline
            return nil
        }

        guard let bubbleId = lastBubbleIdentifier(timeout: 30) else {
            XCTFail("Assistant bubble did not appear")
            return
        }
        let assistantBubble = anyElement(bubbleId)

        // Poll for the bubble's label to stabilize (stream completion), capped at 30s total.
        // Uses a real production model call — one per run, expected and budgeted.
        var previousLabel: String?
        var stableStreak = 0
        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline {
            let currentLabel = assistantBubble.label
            let meaningful = currentLabel.trimmingCharacters(in: .whitespaces)
            if !meaningful.isEmpty, currentLabel == previousLabel {
                stableStreak += 1
                if stableStreak >= 3 { break }   // stable across 3 consecutive 0.5s polls (~1.5s quiet)
            } else {
                stableStreak = 0
            }
            previousLabel = currentLabel
            usleep(500_000)
        }
        let finalLabel = assistantBubble.label.trimmingCharacters(in: .whitespaces)
        XCTAssertFalse(finalLabel.isEmpty, "Expected a non-empty assistant answer")

        // ≥1 source chip, derived from the SAME bubble's index (not assumed/hardcoded).
        let indexSuffix = bubbleId.replacingOccurrences(of: "ask.bubble.", with: "")
        let sourcesRow = anyElement("ask.sources.\(indexSuffix)")
        XCTAssertTrue(sourcesRow.waitForExistence(timeout: 10), "Expected at least one source chip for the persimmons question")

        // Screenshot rig (same checkpoint technique as testDetailSheets/testTagsAndPublicSmoke):
        // holds here so an external `xcrun simctl io <udid> screenshot` can capture the streamed
        // answer with its source chip(s) visible before this test moves on to tapping one.
        FileHandle.standardError.write("SCREENSHOT_CHECKPOINT: ask\n".data(using: .utf8)!)
        sleep(3)

        let firstChip = anyElement("ask.sources.\(indexSuffix).chip.0")
        XCTAssertTrue(firstChip.waitForExistence(timeout: 5), "Expected a tappable source chip")
        firstChip.tap()

        let done = app.buttons["detail.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 10), "Detail sheet did not present for the tapped source")
        done.tap()
        XCTAssertTrue(input.waitForExistence(timeout: 10), "Expected the Ask tab after dismissing the detail sheet")
    }

    /// Voice notes (Task 6): record → Stop → Save → success toast → View tab shows the new item.
    /// "Type audio" is proven the same way `testDetailSheets` proves type for its "audio one"
    /// fixture — the segmented tab set (`contentTabsConfig`), not any grid-level type indicator,
    /// since `ItemCardView` exposes no type string directly and this recording has no searchable
    /// text marker (voice notes never attach the composer's typed text as content — see
    /// `CaptureViewModel.submitVoiceNote`'s own doc comment, so unlike `testCaptureSmoke` there's
    /// nothing to type into the search field first). Sim mic permission (`simctl privacy … grant
    /// microphone`) is granted as a pre-step before this test runs, same spirit as testAskSmoke's
    /// grants — with it pre-granted, `AudioRecorderController` never shows a system prompt, so the
    /// sheet's record button is tappable immediately.
    ///
    /// The created row and its uploaded storage object are disposable: REST-polled for its
    /// Whisper-assigned `description` (silence → the "no speech" description path, plan 1) then
    /// REST-deleted in the shell after this test runs — same cleanup-outside-the-test convention
    /// testDeleteSmoke/testCaptureSmoke already use; never touches the permanent UITEST-FIXTURE rows.
    func testVoiceNoteSmoke() throws {
        let (email, password) = try testCredentials()
        let app = XCUIApplication()
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

        func anyElement(_ identifier: String) -> XCUIElement { app.descendants(matching: .any)[identifier] }

        // Add is the launch tab (plan 2) — the mic button must appear without tapping any tab.
        let voiceButton = anyElement("capture.voice")
        XCTAssertTrue(voiceButton.waitForExistence(timeout: 15), "Expected the voice-note mic button on the Add tab")
        voiceButton.tap()

        let recordButton = anyElement("capture.voice.record")
        XCTAssertTrue(recordButton.waitForExistence(timeout: 10),
                      "Voice recorder sheet did not present its record button")
        recordButton.tap()

        let stopButton = anyElement("capture.voice.stop")
        XCTAssertTrue(stopButton.waitForExistence(timeout: 5), "Expected the Stop button once recording starts")

        // Screenshot rig (same checkpoint technique as testDetailSheets/testAskSmoke): holds here,
        // mid-recording, so an external `xcrun simctl io <udid> screenshot` can capture the timer
        // + level meter + Stop/Cancel state before this test moves on.
        FileHandle.standardError.write("SCREENSHOT_CHECKPOINT: voice-recording\n".data(using: .utf8)!)
        sleep(2)   // ~2s of host-mic audio — silent on the simulator, which is fine (brief's own note)
        stopButton.tap()

        let saveButton = anyElement("capture.voice.save")
        XCTAssertTrue(saveButton.waitForExistence(timeout: 10), "Expected the preview state's Save button after Stop")

        FileHandle.standardError.write("SCREENSHOT_CHECKPOINT: voice-preview\n".data(using: .utf8)!)
        sleep(3)
        saveButton.tap()

        // Review fix (task-6 review, Finding 1): Cancel must be disabled the instant Save is
        // tapped, for the whole in-flight upload — a query right after the tap, with no wait, is
        // safe either way: `isEnabled` reads false both while genuinely disabled AND if the sheet
        // has already dismissed (save resolved faster than this line runs), so this can't flake
        // toward a false failure on a fast save.
        XCTAssertFalse(anyElement("capture.voice.cancel").isEnabled,
                       "Expected Cancel to be disabled for the duration of the save")

        XCTAssertTrue(anyElement("capture.toast").waitForExistence(timeout: 15),
                      "Expected a success toast after saving the voice note")

        app.tabBars.buttons["View"].tap()
        XCTAssertTrue(anyElement("library.grid").waitForExistence(timeout: 15), "Library grid did not appear")

        func card0() -> XCUIElement { app.descendants(matching: .any)["card.0"] }
        XCTAssertTrue(card0().waitForExistence(timeout: 15), "Expected the newly-captured voice note's card to appear")
        card0().tap()

        let done = app.buttons["detail.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 10), "Detail sheet did not present for the new voice note")
        XCTAssertTrue(app.buttons["Notes"].waitForExistence(timeout: 5), "Expected a Notes tab for the voice note")
        XCTAssertTrue(app.buttons["Transcript"].waitForExistence(timeout: 5),
                      "Expected a Transcript tab — the signal that this card is type audio")
        XCTAssertFalse(app.buttons["Summary"].exists, "Did not expect a Summary tab for an audio item")
        XCTAssertFalse(app.buttons["Original Content"].exists, "Did not expect an Original Content tab for an audio item")

        done.tap()
        XCTAssertTrue(anyElement("library.grid").waitForExistence(timeout: 10), "Expected the library after dismiss")
    }
}
