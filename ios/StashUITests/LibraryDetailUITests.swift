import XCTest

/// Plan 16, Task 4 — two bugs in Will's 2026-09-30 device screenshots:
///
/// 1. A voice note's detail sheet was titled with its raw storage object name (`f200ad94-…`): the
///    card's type-label fallback now reaches the sheet as an EMPTY title field whose placeholder is
///    that label, and the sheet never writes a title the user didn't type.
/// 2. The View tab's "Search your stash" pill was half covered by the first card while it hid on
///    scroll: the pill is now the first element of the scroll content, above the cards, and
///    scrolls away with them instead of collapsing over them.
///
/// And from the Task 4 review (I-1): a title typed into that empty field and then cleared again
/// after its autosave went out — on a slow link, on a stalled one, and closed straight after the
/// clear — stays cleared: the field never refills, and the server gets the clear, never the typed
/// text.
///
/// Task 4c (re-review P-1, §9): the same on the slow link for a title retyped after its clear was
/// sent (the server ends with the retyped title), a description reverted to its server value while
/// the edit is in flight, and a plain note cleared and closed while its text is in flight.
///
/// Self-contained like `DetailUITests` (its own sign-in and REST helpers). Seeded rows carry a
/// `UITEST-P16-` marker and are deleted in teardown blocks, so a failed assertion can't leak them
/// (a failed delete is reported, never swallowed); `UITEST-FIXTURE` rows are never touched.
final class LibraryDetailUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Deletes a seeded row once the test ends, however it ends — and says so if the delete fails,
    /// so a leaked `UITEST-P16-` row is visible in the log and the result bundle.
    private func deleteAtTeardown(_ rest: P16Rest, _ id: String) {
        addTeardownBlock {
            do {
                try await rest.deleteItem(id: id)
            } catch {
                print("LibraryDetailUITests: LEAKED seeded row \(id) — its delete failed: \(error)")
                await MainActor.run {
                    XCTContext.runActivity(named: "Leaked seeded row \(id) — delete failed: \(error)") { _ in }
                }
            }
        }
    }

    // MARK: - Detail title

    /// An audio row titled with a UUID object name (what an iOS share / Voice Memos upload stores):
    /// the sheet shows an empty title field with "Voice note" as its placeholder; opening and
    /// closing writes nothing; a title the server writes while the sheet is open (the transcription
    /// job's AI title, via realtime) replaces the placeholder and closing still writes nothing; and a
    /// typed title — into a field that really was empty — saves.
    @MainActor
    func testAnObjectNameTitleShowsTheTypeLabelAndIsOnlyEverWrittenWhenTyped() async throws {
        let (email, password) = try credentials()
        let rest = try await P16Rest.signIn(email: email, password: password)
        let epoch = Int(Date().timeIntervalSince1970)
        let quietMarker = "UITEST-P16-\(epoch)-quiet"
        let typedMarker = "UITEST-P16-\(epoch)-typed"
        let quietName = "\(UUID().uuidString.lowercased()).m4a"
        let typedName = "\(UUID().uuidString.lowercased()).m4a"
        // Oldest first; no `file_path`, so the server's transcription sweep never picks them up and
        // nothing but this test writes their titles.
        let typedId = try await rest.insertItem(["type": "audio", "title": typedName, "content": "",
                                                 "description": "\(typedMarker) seeded audio"],
                                                attributes: ["media": ["duration_s": 5]])
        deleteAtTeardown(rest, typedId)
        try await Task.sleep(for: .milliseconds(150))
        let quietId = try await rest.insertItem(["type": "audio", "title": quietName, "content": "",
                                                 "description": "\(quietMarker) seeded audio"],
                                                attributes: ["media": ["duration_s": 5]])
        deleteAtTeardown(rest, quietId)

        let app = XCUIApplication()
        signIn(app, email: email, password: password)
        let quietCard = libraryCard(app, containing: quietMarker)
        XCTAssertTrue(quietCard.waitForExistence(timeout: 20), "Expected the seeded voice note's card")
        XCTAssertTrue(quietCard.label.contains("Voice note"), "The card reads its type label, got '\(quietCard.label)'")

        // 1. Opening: an empty field with the card's label as placeholder — never the object name.
        tapWhenHittable(quietCard)
        let titleField = app.textFields["detail.title"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 10), "Title field not found")
        XCTAssertEqual(titleField.placeholderValue, "Voice note", "Expected the type label as the placeholder")
        // An empty text field reports its placeholder as its value; a filled one reports its text.
        XCTAssertEqual(titleField.value as? String, "Voice note",
                       "Expected an empty title field, got '\((titleField.value as? String) ?? "")'")
        attachScreenshot(named: "task-4-detail-placeholder")

        // 2. Closing without typing writes nothing (the close queues and sends anything unsaved at
        //    once, so a few seconds is plenty for a wrong write to have landed).
        closeSheet(app)
        try await Task.sleep(for: .seconds(4))
        let quietTitle = try await rest.title(of: quietId)
        XCTAssertEqual(quietTitle, quietName, "Opening and closing the sheet must not write a title")

        // 3. A title the server writes while the sheet is open replaces the placeholder, and closing
        //    afterwards still writes nothing.
        tapWhenHittable(quietCard)
        XCTAssertTrue(titleField.waitForExistence(timeout: 10), "Title field not found on reopen")
        XCTAssertEqual(titleField.placeholderValue, "Voice note")
        let aiTitle = "\(quietMarker) AI title"
        try await rest.setTitle(of: quietId, to: aiTitle)
        let replaced = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", aiTitle), object: titleField)
        XCTAssertEqual(XCTWaiter().wait(for: [replaced], timeout: 30), .completed,
                       "Expected the server's new title in the open sheet, got '\((titleField.value as? String) ?? "")'")
        closeSheet(app)
        try await Task.sleep(for: .seconds(4))
        let adoptedTitle = try await rest.title(of: quietId)
        XCTAssertEqual(adoptedTitle, aiTitle, "Closing after adopting the server's title must not write one")

        // 4. Typing a real title saves it — and the field held exactly what was typed (it was empty).
        let typedCard = libraryCard(app, containing: typedMarker)
        XCTAssertTrue(typedCard.waitForExistence(timeout: 20), "Expected the second seeded voice note's card")
        tapWhenHittable(typedCard)
        XCTAssertTrue(titleField.waitForExistence(timeout: 10), "Title field not found")
        XCTAssertEqual(titleField.placeholderValue, "Voice note")
        let typed = "Groceries \(epoch)"
        tapUntilFocused(titleField)
        titleField.typeText(typed)
        XCTAssertEqual(titleField.value as? String, typed, "Expected exactly the typed title in a field that started empty")
        closeSheet(app)
        let saved = try await rest.waitForTitle(of: typedId, equalTo: typed, timeout: 20)
        XCTAssertTrue(saved, "Expected the typed title on the server")
    }

    // MARK: - A clear after the typed title was sent (plan 16 review I-1)

    /// Scenario B, on a stalled link (`--uitest-stall-item-writes`: every item write hangs 10 s,
    /// then times out): "Gro" is typed, its autosave goes out and gets stuck (so it stays queued),
    /// then the field is cleared and the sheet closed. The card must read "Voice note" (the queue
    /// holds the clear, not "Gro"), and once the link is back the server gets the clear: an empty
    /// title (M-6: still read as the type label, and still a placeholder the server's AI title can
    /// replace) — never "Gro".
    @MainActor
    func testAClearedTitleIsWhatAStalledLinkDeliversLater() async throws {
        let (email, password) = try credentials()
        let rest = try await P16Rest.signIn(email: email, password: password)
        let marker = "UITEST-P16-\(Int(Date().timeIntervalSince1970))-stalled"
        let objectName = "\(UUID().uuidString.lowercased()).m4a"
        let id = try await rest.insertItem(["type": "audio", "title": objectName, "content": "",
                                            "description": "\(marker) seeded audio"],
                                           attributes: ["media": ["duration_s": 5]])
        deleteAtTeardown(rest, id)

        let app = XCUIApplication()
        signIn(app, email: email, password: password, extraArguments: ["--uitest-stall-item-writes"])
        let card = libraryCard(app, containing: marker)
        XCTAssertTrue(card.waitForExistence(timeout: 20), "Expected the seeded voice note's card")
        tapWhenHittable(card)
        let titleField = app.textFields["detail.title"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 10), "Title field not found")
        typeThenClear("Gro", in: titleField)
        closeSheet(app)

        let cardNow = libraryCard(app, containing: marker)
        XCTAssertTrue(cardNow.waitForExistence(timeout: 10))
        XCTAssertTrue(cardNow.label.contains("Voice note") && !cardNow.label.contains("Gro"),
                      "The card should read its type label (the queued clear), got '\(cardNow.label)'")

        // The network is back: run the app again without the switch (still signed in) — its launch
        // refresh flushes the queue before it reads page 1.
        app.terminate()
        app.launchArguments = ["--uitest-tab-view"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["View"].waitForExistence(timeout: 15), "Expected the app signed in")
        let delivered = try await rest.waitForTitle(of: id, equalTo: "", timeout: 30)
        let serverTitle = try await rest.title(of: id)
        XCTAssertTrue(delivered, "Expected the clear (an empty title) on the server, got '\(serverTitle ?? "nil")'")
    }

    /// Scenarios A and C, on a slow link that still delivers (`--uitest-slow-item-writes`: every
    /// item write waits 3 s, then really goes out).
    /// - A: "Gro" is typed and its autosave sent; the field is cleared while "Gro" is in flight. The
    ///   field stays empty through the "Gro" response, and the server ends with the clear.
    /// - C: the same, but the sheet is closed at once after the clear — the close must send it.
    @MainActor
    func testAClearWhileTheTypedTitleIsStillSendingSticks() async throws {
        let (email, password) = try credentials()
        let rest = try await P16Rest.signIn(email: email, password: password)
        let epoch = Int(Date().timeIntervalSince1970)
        let sendingMarker = "UITEST-P16-\(epoch)-sending"
        let closingMarker = "UITEST-P16-\(epoch)-closing"
        let closingId = try await rest.insertItem(["type": "audio", "title": "\(UUID().uuidString.lowercased()).m4a",
                                                   "content": "", "description": "\(closingMarker) seeded audio"],
                                                  attributes: ["media": ["duration_s": 5]])
        deleteAtTeardown(rest, closingId)
        try await Task.sleep(for: .milliseconds(150))
        let sendingId = try await rest.insertItem(["type": "audio", "title": "\(UUID().uuidString.lowercased()).m4a",
                                                   "content": "", "description": "\(sendingMarker) seeded audio"],
                                                  attributes: ["media": ["duration_s": 5]])
        deleteAtTeardown(rest, sendingId)

        let app = XCUIApplication()
        signIn(app, email: email, password: password, extraArguments: ["--uitest-slow-item-writes"])
        let titleField = app.textFields["detail.title"]

        // A. The "Gro" response lands ~2.5 s after the clear, the clear's own ~3 s after that.
        let sendingCard = libraryCard(app, containing: sendingMarker)
        XCTAssertTrue(sendingCard.waitForExistence(timeout: 20), "Expected the first seeded voice note's card")
        tapWhenHittable(sendingCard)
        XCTAssertTrue(titleField.waitForExistence(timeout: 10), "Title field not found")
        typeThenClear("Gro", in: titleField)
        let watchUntil = Date().addingTimeInterval(8)
        while Date() < watchUntil {
            let shown = (titleField.value as? String) ?? ""
            XCTAssertEqual(shown, "Voice note", "The cleared field refilled with '\(shown)' while the typed title was in flight")
            usleep(250_000)
        }
        let cleared = try await rest.waitForTitle(of: sendingId, equalTo: "", timeout: 20)
        let sendingTitle = try await rest.title(of: sendingId)
        XCTAssertTrue(cleared, "Expected the clear (an empty title) on the server, got '\(sendingTitle ?? "nil")'")
        closeSheet(app)

        // C. Cleared, then closed at once while "Gro" is still in flight.
        let closingCard = libraryCard(app, containing: closingMarker)
        XCTAssertTrue(closingCard.waitForExistence(timeout: 20), "Expected the second seeded voice note's card")
        tapWhenHittable(closingCard)
        XCTAssertTrue(titleField.waitForExistence(timeout: 10), "Title field not found")
        typeThenClear("Gro", in: titleField)
        closeSheet(app)
        let closedClear = try await rest.waitForTitle(of: closingId, equalTo: "", timeout: 25)
        let closingTitle = try await rest.title(of: closingId)
        XCTAssertTrue(closedClear, "Expected the clear sent by the close, got '\(closingTitle ?? "nil")'")
        let closingCardNow = libraryCard(app, containing: closingMarker)
        XCTAssertTrue(closingCardNow.waitForExistence(timeout: 10))
        XCTAssertTrue(closingCardNow.label.contains("Voice note"), "Expected the card's type label, got '\(closingCardNow.label)'")
    }

    // MARK: - The edit queue never drops the user's last value (plan 16, Task 4c)

    /// Review P-1 (E-2), on a slow link: "Gro" is typed and sent, cleared and the clear sent, then
    /// "Gro" is typed again and the sheet closed at once — inside its debounce, so only the close's
    /// journal holds it, with both earlier saves still in flight. The first "Gro" landing must not
    /// drop it (equal, but older), so once the clear has landed the close's flush still delivers the
    /// user's last word.
    ///
    /// The close journals from `onDisappear`, after the dismiss animation — later than 400 ms after
    /// XCUITest's last keystroke, so with the shipping debounce the retyped title's own autosave
    /// always went first (and delivered it). The DEBUG timing switches open the window: a 1.5 s
    /// field debounce to close inside, and a 6 s link so the first "Gro" is still in flight then.
    @MainActor
    func testATitleRetypedAfterASentClearIsWhatTheServerEndsWith() async throws {
        let (email, password) = try credentials()
        let rest = try await P16Rest.signIn(email: email, password: password)
        let marker = "UITEST-P16-\(Int(Date().timeIntervalSince1970))-retyped"
        let id = try await rest.insertItem(["type": "audio", "title": "\(UUID().uuidString.lowercased()).m4a",
                                            "content": "", "description": "\(marker) seeded audio"],
                                           attributes: ["media": ["duration_s": 5]])
        deleteAtTeardown(rest, id)

        let app = XCUIApplication()
        signIn(app, email: email, password: password,
               extraArguments: ["--uitest-slow-item-writes", "--uitest-slow-item-write-seconds", "6",
                                "--uitest-field-debounce-seconds", "1.5"])
        let card = libraryCard(app, containing: marker)
        XCTAssertTrue(card.waitForExistence(timeout: 20), "Expected the seeded voice note's card")
        tapWhenHittable(card)
        let titleField = app.textFields["detail.title"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 10), "Title field not found")
        tapUntilFocused(titleField)
        titleField.typeText("Gro")
        sleep(2)   // past the 1.5 s autosave: "Gro" is on its 6 s way
        titleField.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 3))
        XCTAssertEqual(titleField.value as? String, "Voice note", "Expected the field empty again (placeholder showing)")
        sleep(2)   // the clear's autosave has gone out too, queued behind "Gro"
        titleField.typeText("Gro")
        closeSheet(app)   // inside the retyped title's 1.5 s debounce; the first "Gro" still in flight

        // "Gro" lands ~6 s after it was sent and the clear ~6 s after that; writes to one item never
        // overtake each other, so the close's flush goes out only then, and lands ~6 s later.
        let clearLanded = try await rest.waitFor("title", of: id, equalTo: "", timeout: 30)
        XCTAssertTrue(clearLanded, "Expected the clear (sent before the close) to land first")
        let delivered = try await rest.waitFor("title", of: id, equalTo: "Gro", timeout: 30)
        let serverTitle = try await rest.title(of: id)
        XCTAssertTrue(delivered, "Expected the retyped \"Gro\" to be what the server ends with, got '\(serverTitle ?? "nil")'")
        let cardNow = libraryCard(app, containing: marker)
        XCTAssertTrue(cardNow.waitForExistence(timeout: 10))
        XCTAssertTrue(cardNow.label.hasPrefix("Gro"), "Expected the card titled \"Gro\", got '\(cardNow.label)'")
    }

    /// Review §9, scenario A for the description, on the slow link: " x" is typed into the seeded
    /// description and its autosave sent; the user deletes it again while it is in flight — a revert
    /// to the server's own value, which the old rule saw as "nothing to save". The edit's response
    /// must not refill the field, and the server must end with the original description.
    @MainActor
    func testADescriptionRevertedWhileItsEditIsStillSendingSticks() async throws {
        let (email, password) = try credentials()
        let rest = try await P16Rest.signIn(email: email, password: password)
        let marker = "UITEST-P16-\(Int(Date().timeIntervalSince1970))-description"
        let original = "Meeting notes"
        // A text item: its sheet opens on Notes (no `page_body` read racing the edit).
        let id = try await rest.insertItem(["type": "text", "title": marker, "content": "", "description": original])
        deleteAtTeardown(rest, id)

        let app = XCUIApplication()
        signIn(app, email: email, password: password, extraArguments: ["--uitest-slow-item-writes"])
        let card = libraryCard(app, containing: marker)
        XCTAssertTrue(card.waitForExistence(timeout: 20), "Expected the seeded card")
        tapWhenHittable(card)
        let description = descriptionField(app)
        XCTAssertTrue(description.waitForExistence(timeout: 10), "Description field not found")
        tapUntilFocused(description)
        // Where the caret lands in this multi-line field isn't reliable (seen: the start of the
        // text), so the edit is " x" wherever it went — typed as one piece, and deleted again with
        // two backspaces from right after it.
        description.typeText(" x")
        let edited = (description.value as? String) ?? ""
        XCTAssertEqual(edited.replacingOccurrences(of: " x", with: ""), original,
                       "Expected \" x\" typed into the description as one piece, got '\(edited)'")
        sleep(1)   // past the 400 ms autosave: the edit is in flight
        description.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 2))
        XCTAssertEqual(description.value as? String, original, "Expected the description back to its original")

        // The edit's response lands ~2.5 s from here and the revert's ~3 s after it: watch both.
        var sawEditOnServer = false
        let watchUntil = Date().addingTimeInterval(8)
        while Date() < watchUntil {
            let shown = (description.value as? String) ?? ""
            XCTAssertEqual(shown, original, "The reverted description refilled with '\(shown)' while the edit was in flight")
            if !sawEditOnServer, (try? await rest.column("description", of: id)) == edited {
                sawEditOnServer = true
            }
            usleep(250_000)
        }
        XCTAssertTrue(sawEditOnServer, "Expected the edit to land while the field was watched (so its response was seen)")
        let reverted = try await rest.waitFor("description", of: id, equalTo: original, timeout: 20)
        let serverDescription = try await rest.column("description", of: id)
        XCTAssertTrue(reverted, "Expected the server to end with the original description, got '\(serverDescription ?? "nil")'")
        closeSheet(app)
    }

    /// A plain note (not TipTap), on the slow link: text is typed and its autosave sent, then the
    /// note is cleared and the sheet closed at once, with the text still in flight. Whatever sends
    /// the clear — the editor's blur flush, its debounce or the close's journal — must see that the
    /// cleared draft differs from the text still queued (the draft reads the edit queue, not only
    /// what has landed), so once the text lands the clear follows it: the server ends empty. The old
    /// check (`draft != savedDraft`: "" == "") sent nothing on every one of those paths.
    @MainActor
    func testAPlainNoteClearedAndClosedWhileItsTextIsStillSendingSticks() async throws {
        let (email, password) = try credentials()
        let rest = try await P16Rest.signIn(email: email, password: password)
        let marker = "UITEST-P16-\(Int(Date().timeIntervalSince1970))-plainnote"
        let id = try await rest.insertItem(["type": "text", "title": marker, "content": ""])
        deleteAtTeardown(rest, id)

        let app = XCUIApplication()
        signIn(app, email: email, password: password, extraArguments: ["--uitest-slow-item-writes"])
        let card = libraryCard(app, containing: marker)
        XCTAssertTrue(card.waitForExistence(timeout: 20), "Expected the seeded card")
        tapWhenHittable(card)
        let notes = app.textViews["detail.notes.editor"]
        XCTAssertTrue(notes.waitForExistence(timeout: 10), "Notes editor not found")
        tapUntilFocused(notes)
        notes.typeText("plain note text")
        let typed = (notes.value as? String) ?? ""
        XCTAssertTrue(typed.lowercased().contains("plain note text"), "Expected the typed note, got '\(typed)'")
        sleep(2)   // past the 600 ms notes autosave: the text is in flight
        notes.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: typed.count + 2))
        XCTAssertEqual(notes.value as? String, "", "Expected the note cleared")
        closeSheet(app)   // at once, the text still in flight

        let textLanded = try await rest.waitFor("content", of: id, equalTo: typed, timeout: 25)
        XCTAssertTrue(textLanded, "Expected the typed note (sent before the clear) to land first")
        let cleared = try await rest.waitFor("content", of: id, equalTo: "", timeout: 25)
        let serverContent = try await rest.column("content", of: id)
        XCTAssertTrue(cleared, "Expected the clear to be what the server ends with, got '\(serverContent ?? "nil")'")
    }

    // MARK: - Search pill

    /// Scrolls the View tab in small slow steps and samples the pill's and the first card's frames
    /// after each one: while the pill is visible (hittable) it never overlaps card 0, keeps its full
    /// height (nothing collapses), and moves up with the cards (constant gap), and at least two of
    /// the samples catch it part-way out. Screenshots of each visible step are kept for the report.
    ///
    /// Also: the one-scroll-view rebuild keeps the grid lazy (at rest, with 40+ rows loaded, card 30
    /// hasn't been built — scrolling down builds it), and a tap into a part-way-out pill brings it
    /// all the way back before anything is typed.
    ///
    /// `--uitest-search-no-snap` turns off the pill row's snap (plan 16 review M-2 — a release inside
    /// the row normally snaps to the nearer end, so it never RESTS part-way out; the snap itself is
    /// asserted in `testLibrarySearchBarFadesAndKeyboardDismisses`). Here it lets part-way positions
    /// be sampled between slow drags — XCUITest can't read frames mid-gesture — as they are
    /// mid-scroll, and as a list only slightly taller than the screen still leaves the row at rest.
    @MainActor
    func testSearchPillNeverOverlapsTheFirstCardWhileVisible() async throws {
        let (email, password) = try credentials()
        let rest = try await P16Rest.signIn(email: email, password: password)
        let rowsOnServer = try await rest.rowCount(upTo: 40)
        let app = XCUIApplication()
        signIn(app, email: email, password: password, extraArguments: ["--uitest-search-no-snap"])

        let pill = app.descendants(matching: .any)["library.search.pill"]
        let field = app.textFields["library.search"]
        let card0 = app.descendants(matching: .any)["card.0"]
        let card30 = app.descendants(matching: .any)["card.30"]
        XCTAssertTrue(pill.waitForExistence(timeout: 15), "Search pill not found")
        XCTAssertTrue(card0.waitForExistence(timeout: 20), "Expected at least one card")
        sleep(3)   // the cached first page, then the refreshed one, and their heroes, settle

        // Laziness (review §9): the grid sits in a plain stack inside the scroll view; if it built
        // every loaded row, card 30 would be in the tree (and every card's onAppear would page
        // through the whole library at launch).
        XCTAssertEqual(rowsOnServer, 40, "The laziness check needs 40+ rows on the test account")
        XCTAssertFalse(card30.exists, "At rest the grid must not have built card 30 — it isn't lazy")

        let restPill = pill.frame
        let restCard = card0.frame
        XCTAssertTrue(field.isHittable, "Expected the pill visible at rest")
        XCTAssertFalse(restPill.intersects(restCard), "At rest the pill \(restPill) overlaps card.0 \(restCard)")
        let restGap = restCard.minY - restPill.maxY
        attachScreenshot(named: "task-4-pill-rest")

        let window = app.windows.firstMatch.frame
        let dragStart = app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: window.midX, dy: window.midY + 120))
        let grid = app.descendants(matching: .any)["library.grid"]
        var partWayOut = 0
        // A synthesized slow drag can still land as a fling on a busy simulator — seen once, on a
        // cold-booted iOS 26.5 sim: the list coasted past the whole row in one step, so nothing
        // part-way was sampled. Every sample is checked either way; a pass that never caught the
        // pill part-way goes back to rest and samples again.
        for pass in 1...3 where partWayOut < 2 {
            if pass > 1 {
                grid.swipeDown()
                grid.swipeDown()
                XCTAssertTrue(eventually(10) { field.isHittable && abs(pill.frame.minY - restPill.minY) <= 1 },
                              "Expected the pill back at rest before sampling pass \(pass)")
            }
            partWayOut = 0
            for step in 1...14 {
                dragStart.press(forDuration: 0.05, thenDragTo: dragStart.withOffset(CGVector(dx: 0, dy: -22)),
                                withVelocity: .slow, thenHoldForDuration: 0.25)
                usleep(400_000)
                guard field.isHittable else { break }
                let pillFrame = pill.frame
                let cardFrame = card0.frame
                attachScreenshot(named: "task-4-pill-step-\(step)")
                XCTAssertFalse(pillFrame.intersects(cardFrame),
                               "Step \(step): the visible pill \(pillFrame) overlaps card.0 \(cardFrame)")
                XCTAssertEqual(pillFrame.height, restPill.height, accuracy: 1,
                               "Step \(step): the pill must keep its height while it scrolls away")
                XCTAssertEqual(cardFrame.minY - pillFrame.maxY, restGap, accuracy: 1,
                               "Step \(step): the pill must move with the cards")
                if pillFrame.minY < restPill.minY - 4 { partWayOut += 1 }
            }
        }
        XCTAssertGreaterThanOrEqual(partWayOut, 2, "Expected to sample the pill part-way out while still visible")

        // Once it's gone, the cards run on up into the slot it left (nothing stays reserved for it).
        dragStart.press(forDuration: 0.05, thenDragTo: dragStart.withOffset(CGVector(dx: 0, dy: -60)),
                        withVelocity: .slow, thenHoldForDuration: 0.25)
        usleep(400_000)
        XCTAssertFalse(field.isHittable, "Expected the pill gone once scrolled past it")
        XCTAssertLessThan(card0.frame.minY, restPill.minY, "Expected card.0 to have scrolled up through the pill's old slot")
        attachScreenshot(named: "task-4-pill-gone")

        // Part-way out (still visible), a tap into the pill brings it all the way back before
        // anything is typed — it never sits half-hidden while focused.
        var partWay = false
        for _ in 1...3 where !partWay {   // again, a drag that lands as a fling is retried from rest
            grid.swipeDown()
            grid.swipeDown()
            XCTAssertTrue(eventually(10) { field.isHittable && abs(pill.frame.minY - restPill.minY) <= 1 },
                          "Expected the pill back at rest (at \(pill.frame.minY), rest \(restPill.minY))")
            for _ in 0..<5 where pill.frame.minY > restPill.minY - 6 {
                dragStart.press(forDuration: 0.05, thenDragTo: dragStart.withOffset(CGVector(dx: 0, dy: -14)),
                                withVelocity: .slow, thenHoldForDuration: 0.25)
                usleep(400_000)
            }
            partWay = pill.frame.minY < restPill.minY - 3 && field.isHittable
        }
        XCTAssertTrue(partWay, "Expected the pill part-way scrolled out and still tappable (at \(pill.frame.minY), rest \(restPill.minY))")
        field.tap()
        XCTAssertTrue(app.keyboards.element.waitForExistence(timeout: 5), "Expected the keyboard up once the search field is focused")
        XCTAssertTrue(eventually(3) { abs(pill.frame.minY - restPill.minY) <= 1 },
                      "Expected the focused pill fully back in view (at \(pill.frame.minY), rest \(restPill.minY))")
        app.buttons["library.search.cancel"].tap()

        // A state pane fills the tab below the search row and centres its content there (review
        // N-2: sized by its container, not a measured viewport height that starts at 0). One
        // character nothing contains is below the server search's two-character minimum, so the
        // local filter answers "No matches" at once; return drops the keyboard.
        field.tap()
        field.typeText("¶\n")
        // The pane's identifier lands on each of its parts (icon, title, message): measure them together.
        let paneParts = app.descendants(matching: .any).matching(identifier: "library.empty")
        XCTAssertTrue(paneParts.firstMatch.waitForExistence(timeout: 5), "Expected the No matches pane")
        let pane = paneParts.allElementsBoundByIndex.map(\.frame).reduce(CGRect.null) { $0.union($1) }
        // Between the search row's bottom (its 10 pt bottom padding) and the tab bar — the scroll
        // view's own accessibility frame runs under both bars, so it can't be the reference.
        let paneTop = restPill.maxY + 10
        let paneBottom = app.tabBars.firstMatch.frame.minY
        XCTAssertEqual(pane.midY, (paneTop + paneBottom) / 2, accuracy: 30,
                       "Expected No matches centred below the search row (at \(pane), between \(paneTop) and \(paneBottom))")
        attachScreenshot(named: "task-4-fix-no-matches-pane")
        app.buttons["library.search.clear"].tap()
        XCTAssertTrue(card0.waitForExistence(timeout: 10), "Expected the cards back once the query is cleared")

        // The laziness check's positive control: scrolling down does build card 30.
        for _ in 0..<25 where !card30.exists { grid.swipeUp() }
        XCTAssertTrue(card30.exists, "Expected card 30 once scrolled down to it")
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

    /// `--uitest-reset-auth` forces the real sign-in screen (the Keychain session survives
    /// reinstalls on the Simulator); `--uitest-tab-view` lands on the View tab once signed in — no
    /// tab-bar tap, which iOS 26 swallows while the sign-in keyboard is still going away (the tab
    /// button reports a {-1, -1} hit point then).
    @MainActor
    private func signIn(_ app: XCUIApplication, email: String, password: String, extraArguments: [String] = []) {
        app.launchArguments = ["--uitest-reset-auth", "--uitest-tab-view"] + extraArguments
        app.launch()
        let emailField = app.textFields["signin.email"]
        XCTAssertTrue(emailField.waitForExistence(timeout: 10), "Sign-in email field did not appear")
        tapUntilFocused(emailField)
        emailField.typeText(email)
        let passwordField = app.secureTextFields["signin.password"]
        tapUntilFocused(passwordField)
        passwordField.typeText(password)
        app.buttons["signin.submit"].tap()
        XCTAssertTrue(app.tabBars.buttons["View"].waitForExistence(timeout: 15), "Expected the tab bar after sign-in")
        // The Passwords app offers "Save Password?" over the app after every sign-in on iOS 26.5
        // (never on 17.2) — decline it so it can't cover the View tab.
        if app.buttons["Not Now"].waitForExistence(timeout: 3) { declineSavePassword(app) }
    }

    /// Taps "Not Now" until the "Save Password?" sheet has really gone. It is in the tree while it
    /// is still sliding in, and a tap then is ignored — seen on the 26.5 simulator: the sheet stayed
    /// over the app for the rest of the test, so every card tap got a {-1, -1} hit point.
    @MainActor
    private func declineSavePassword(_ app: XCUIApplication) {
        let notNow = app.buttons["Not Now"]
        for _ in 0..<4 where notNow.exists {
            notNow.tap()
            _ = eventually(3) { !notNow.exists }
        }
    }

    /// Taps `element` once it can really take the tap — declining a "Save Password?" sheet that
    /// arrived late in the meantime.
    @MainActor
    private func tapWhenHittable(_ element: XCUIElement, timeout: TimeInterval = 10) {
        let app = XCUIApplication()
        _ = eventually(timeout) {
            if app.buttons["Not Now"].exists { declineSavePassword(app) }
            return element.isHittable
        }
        element.tap()
    }

    /// The grid card (`card.<n>`) whose accessibility label contains `text`.
    @MainActor
    private func libraryCard(_ app: XCUIApplication, containing text: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier MATCHES %@ AND label CONTAINS %@", #"card\.[0-9]+"#, text))
            .firstMatch
    }

    @MainActor
    private func closeSheet(_ app: XCUIApplication) {
        let close = app.buttons["detail.done"]
        close.tap()
        let closed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: close)
        XCTAssertEqual(XCTWaiter().wait(for: [closed], timeout: 5), .completed, "The sheet didn't close")
    }

    /// Polls `condition` until it holds or `timeout` passes (frames aren't KVO-observable).
    private func eventually(_ timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            usleep(200_000)
        }
        return condition()
    }

    /// Types `text` into the (empty) title field, waits past its 400 ms autosave — so the typed title
    /// has been sent — and deletes it again, leaving the field empty (its placeholder showing).
    @MainActor
    private func typeThenClear(_ text: String, in field: XCUIElement) {
        tapUntilFocused(field)
        field.typeText(text)
        XCTAssertEqual(field.value as? String, text, "Expected exactly the typed title in the empty field")
        sleep(1)
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: text.count))
        XCTAssertEqual(field.value as? String, "Voice note", "Expected the field empty again (placeholder showing)")
    }

    /// The detail sheet's description: a vertical-axis `TextField`, which XCUITest may report as a
    /// text view rather than a text field.
    @MainActor
    private func descriptionField(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@ AND (elementType == %d OR elementType == %d)",
                                  "detail.description", Int(XCUIElement.ElementType.textView.rawValue),
                                  Int(XCUIElement.ElementType.textField.rawValue)))
            .firstMatch
    }

    /// Taps `field` until it has keyboard focus (a tap can land while a sheet is still settling).
    @MainActor
    private func tapUntilFocused(_ field: XCUIElement, attempts: Int = 5) {
        for _ in 0..<attempts {
            field.tap()
            let focused = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hasKeyboardFocus == true"), object: field)
            if XCTWaiter().wait(for: [focused], timeout: 1.5) == .completed { return }
        }
    }

    /// A full-screen screenshot kept in the result bundle (exported for the task report).
    @MainActor
    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

/// A password-grant REST session for the test account — seeds, reads, writes and deletes this
/// file's throwaway rows independently of the app. The public project URL + anon key are the ones
/// `StashConfig.swift` ships (not secrets); a UI-test bundle can't import StashKit.
private struct P16Rest: Sendable {
    static let baseURL = URL(string: "https://uqqsgmwkvslaomzxptnp.supabase.co")!
    static let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVxcXNnbXdrdnNsYW9tenhwdG5wIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTA2MjU0ODcsImV4cCI6MjA2NjIwMTQ4N30.vGWb1EdshtLFLpUHQ54Vy2CDmuPVCTbvc8UYW6_cvmE"

    struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    let token: String
    let userId: String

    static func signIn(email: String, password: String) async throws -> P16Rest {
        var request = URLRequest(url: baseURL.appending(path: "/auth/v1/token")
            .appending(queryItems: [URLQueryItem(name: "grant_type", value: "password")]))
        request.httpMethod = "POST"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["email": email, "password": password])
        let (data, response) = try await send(request)
        guard succeeded(response),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = object["access_token"] as? String,
              let user = object["user"] as? [String: Any], let userId = user["id"] as? String
        else { throw Failure(description: "test-account sign-in failed") }
        return P16Rest(token: token, userId: userId)
    }

    /// `URLSession` with up to three tries on a transport error — only for the idempotent requests
    /// (auth, reads, the title write, deletes); the insert goes out once.
    private static func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        var tries = 1
        while true {
            do {
                return try await URLSession.shared.data(for: request)
            } catch let error as URLError where tries < 3 {
                print("REST retry after URLError \(error.code.rawValue)")
                tries += 1
                try await Task.sleep(for: .seconds(1))
            }
        }
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

    func insertItem(_ fields: [String: Any], attributes: [String: Any] = [:]) async throws -> String {
        var body = fields
        body["user_id"] = userId
        body["is_public"] = false
        body["attributes"] = attributes
        var request = request("/rest/v1/items", method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=representation", forHTTPHeaderField: "Prefer")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard Self.succeeded(response),
              let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let id = rows.first?["id"] as? String
        else { throw Failure(description: "throwaway insert failed") }
        return id
    }

    func deleteItem(id: String) async throws {
        let (_, response) = try await Self.send(
            request("/rest/v1/items", query: [URLQueryItem(name: "id", value: "eq.\(id)")], method: "DELETE"))
        guard Self.succeeded(response) else { throw Failure(description: "throwaway delete failed for \(id)") }
    }

    func title(of id: String) async throws -> String? {
        try await column("title", of: id)
    }

    /// One text column of a seeded row (`title`, `description`, `content`, …); nil when it is null.
    func column(_ name: String, of id: String) async throws -> String? {
        let (data, response) = try await Self.send(request("/rest/v1/items", query: [
            URLQueryItem(name: "id", value: "eq.\(id)"),
            URLQueryItem(name: "select", value: name),
        ]))
        guard Self.succeeded(response),
              let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]], let row = rows.first
        else { throw Failure(description: "\(name) read failed for \(id)") }
        return row[name] as? String
    }

    /// A title write from outside the app — what the server's transcription job does when it
    /// replaces an object-name title with an AI one.
    func setTitle(of id: String, to title: String) async throws {
        var request = request("/rest/v1/items", query: [URLQueryItem(name: "id", value: "eq.\(id)")], method: "PATCH")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["title": title])
        let (_, response) = try await Self.send(request)
        guard Self.succeeded(response) else { throw Failure(description: "title write failed for \(id)") }
    }

    /// How many rows the test account holds, counting no further than `limit`.
    func rowCount(upTo limit: Int) async throws -> Int {
        let (data, response) = try await Self.send(request("/rest/v1/items", query: [
            URLQueryItem(name: "select", value: "id"),
            URLQueryItem(name: "limit", value: String(limit)),
        ]))
        guard Self.succeeded(response), let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { throw Failure(description: "row count failed") }
        return rows.count
    }

    func waitForTitle(of id: String, equalTo expected: String, timeout: TimeInterval) async throws -> Bool {
        try await waitFor("title", of: id, equalTo: expected, timeout: timeout)
    }

    /// Polls a seeded row's text column (about once a second) until it equals `expected`.
    func waitFor(_ name: String, of id: String, equalTo expected: String, timeout: TimeInterval) async throws -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let value = try? await column(name, of: id), value == expected { return true }
            try await Task.sleep(for: .seconds(1))
        } while Date() < deadline
        return false
    }
}
