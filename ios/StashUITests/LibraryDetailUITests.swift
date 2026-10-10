import XCTest

/// Detail regression coverage: explicit title drafts and durable Save; inline description and
/// note autosave races; failed sharing never replayed as a surprise publish; keyboard, footer,
/// accessibility and library search layout behavior. Title concurrency cases use description
/// because a title's explicit Save intentionally disables its editor until the request ends.
///
/// Self-contained throwaway `UITEST-P16-` rows are deleted in teardown. Permanent fixtures are
/// never edited; a failed cleanup is reported rather than swallowed.
final class LibraryDetailUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        // Plan 16: the real Bold Text setting is simulator-global; an interrupted a11y run can
        // leave it on.
        MainActor.assumeIsolated { A11yScreens.restoreRealBoldTextIfLeftOn() }
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

    /// Object-name titles render the type label. Opening/cancelling does not persist the fallback,
    /// realtime can replace it, and a real title reaches the server only after explicit Save.
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

        // Opening and cancelling the explicit editor must not publish the object-name fallback.
        tapWhenHittable(quietCard)
        let titleLabel = app.buttons["detail.title"]
        XCTAssertTrue(titleLabel.waitForExistence(timeout: 10), "Title button not found")
        XCTAssertEqual(titleLabel.label, "Voice note")
        let titleField = openTitleEditor(app)
        XCTAssertTrue(showsPlaceholder("Voice note", titleField))
        XCTAssertTrue(isEmpty(titleField, placeholder: "Voice note"))
        attachScreenshot(named: "task-4-detail-placeholder")
        app.buttons["detail.title.cancel"].tap()
        closeSheet(app)
        try await Task.sleep(for: .seconds(4))
        let quietTitle = try await rest.title(of: quietId)
        XCTAssertEqual(quietTitle, quietName, "Opening and cancelling must not write a title")

        // A realtime title updates the collapsed label without becoming a local edit.
        tapWhenHittable(quietCard)
        XCTAssertTrue(titleLabel.waitForExistence(timeout: 10))
        XCTAssertEqual(titleLabel.label, "Voice note")
        let aiTitle = "\(quietMarker) AI title"
        try await rest.setTitle(of: quietId, to: aiTitle)
        let replaced = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", aiTitle), object: titleLabel)
        XCTAssertEqual(XCTWaiter().wait(for: [replaced], timeout: 30), .completed,
                       "Expected the server's new title in the collapsed label")
        closeSheet(app)
        try await Task.sleep(for: .seconds(4))
        let adoptedTitle = try await rest.title(of: quietId)
        XCTAssertEqual(adoptedTitle, aiTitle, "Closing after adopting the server's title must not write one")

        // A draft stays local until Save, even after the former autosave interval.
        let typedCard = libraryCard(app, containing: typedMarker)
        XCTAssertTrue(typedCard.waitForExistence(timeout: 20), "Expected the second seeded voice note's card")
        tapWhenHittable(typedCard)
        let typedField = openTitleEditor(app)
        XCTAssertTrue(showsPlaceholder("Voice note", typedField))
        let typed = "Groceries \(epoch)"
        typedField.typeText(typed)
        XCTAssertEqual(typedField.value as? String, typed)
        try await Task.sleep(for: .seconds(1))
        let beforeSave = try await rest.title(of: typedId)
        XCTAssertEqual(beforeSave, typedName, "An uncommitted draft must not reach the server")
        commitTitle(app)
        closeSheet(app)
        let saved = try await rest.waitForTitle(of: typedId, equalTo: typed, timeout: 20)
        XCTAssertTrue(saved, "Expected the explicitly saved title on the server")
    }

    // MARK: - Autosaved descriptions preserve the latest edit

    /// Description keeps autosave semantics. A typed value sent on a stalled link, then cleared
    /// and closed, must replay the clear after relaunch rather than restore the older value.
    @MainActor
    func testAClearedDescriptionIsWhatAStalledLinkDeliversLater() async throws {
        let (email, password) = try credentials()
        let rest = try await P16Rest.signIn(email: email, password: password)
        let marker = "UITEST-P16-\(Int(Date().timeIntervalSince1970))-stalled"
        let id = try await rest.insertItem(["type": "text", "title": marker, "content": "", "description": "Before edit"])
        deleteAtTeardown(rest, id)

        let app = XCUIApplication()
        signIn(app, email: email, password: password, extraArguments: ["--uitest-stall-item-writes"])
        let card = libraryCard(app, containing: marker)
        XCTAssertTrue(card.waitForExistence(timeout: 20), "Expected the seeded card")
        tapWhenHittable(card)
        let description = descriptionField(app)
        XCTAssertTrue(description.waitForExistence(timeout: 10), "Description field not found")
        typeThenClearDescription("Gro", in: description)
        closeSheet(app)

        let cardNow = libraryCard(app, containing: marker)
        XCTAssertTrue(cardNow.waitForExistence(timeout: 10))
        XCTAssertFalse(cardNow.label.contains("Gro"), "The queued clear must remove the old description from the card")
        tapWhenHittable(cardNow)
        XCTAssertTrue(description.waitForExistence(timeout: 10))
        XCTAssertTrue(isEmpty(description, placeholder: "Add a description…"), "Reopening must show the queued clear")
        closeSheet(app)

        app.terminate()
        app.launchArguments = ["--uitest-tab-view"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["View"].waitForExistence(timeout: 15), "Expected the app signed in")
        let delivered = try await rest.waitFor("description", of: id, equalTo: "", timeout: 30)
        let serverDescription = try await rest.column("description", of: id)
        XCTAssertTrue(delivered, "Expected the clear on the server, got '\(serverDescription ?? "nil")'")
    }

    /// The old response must not refill a cleared autosave field, with the sheet either open or
    /// closed immediately after clearing. Title Save disables its editor, so this race belongs to
    /// the still-inline description field.
    @MainActor
    func testAClearWhileTheTypedDescriptionIsStillSendingSticks() async throws {
        let (email, password) = try credentials()
        let rest = try await P16Rest.signIn(email: email, password: password)
        let epoch = Int(Date().timeIntervalSince1970)
        let sendingMarker = "UITEST-P16-\(epoch)-sending"
        let closingMarker = "UITEST-P16-\(epoch)-closing"
        let closingId = try await rest.insertItem(["type": "text", "title": closingMarker, "content": "", "description": ""])
        deleteAtTeardown(rest, closingId)
        try await Task.sleep(for: .milliseconds(150))
        let sendingId = try await rest.insertItem(["type": "text", "title": sendingMarker, "content": "", "description": ""])
        deleteAtTeardown(rest, sendingId)

        let app = XCUIApplication()
        signIn(app, email: email, password: password, extraArguments: ["--uitest-slow-item-writes"])
        let description = descriptionField(app)
        let sendingCard = libraryCard(app, containing: sendingMarker)
        XCTAssertTrue(sendingCard.waitForExistence(timeout: 20), "Expected the first seeded card")
        tapWhenHittable(sendingCard)
        XCTAssertTrue(description.waitForExistence(timeout: 10), "Description field not found")
        typeThenClearDescription("Gro", in: description)
        var sawTypedValue = false
        let watchUntil = Date().addingTimeInterval(8)
        while Date() < watchUntil {
            XCTAssertTrue(isEmpty(description, placeholder: "Add a description…"),
                          "The cleared description refilled while its older write was in flight")
            if !sawTypedValue, (try? await rest.column("description", of: sendingId)) == "Gro" { sawTypedValue = true }
            usleep(250_000)
        }
        XCTAssertTrue(sawTypedValue, "The older typed value must actually land while the cleared field is watched")
        let cleared = try await rest.waitFor("description", of: sendingId, equalTo: "", timeout: 20)
        XCTAssertTrue(cleared, "Expected the server to end with the clear")
        closeSheet(app)

        let closingCard = libraryCard(app, containing: closingMarker)
        XCTAssertTrue(closingCard.waitForExistence(timeout: 20), "Expected the second seeded card")
        tapWhenHittable(closingCard)
        XCTAssertTrue(description.waitForExistence(timeout: 10), "Description field not found")
        typeThenClearDescription("Gro", in: description)
        closeSheet(app)
        let typedLanded = try await rest.waitFor("description", of: closingId, equalTo: "Gro", timeout: 15)
        XCTAssertTrue(typedLanded, "The older write must land before the close's clear")
        let closedClear = try await rest.waitFor("description", of: closingId, equalTo: "", timeout: 25)
        XCTAssertTrue(closedClear, "Expected the clear sent by the close")
        let closingCardNow = libraryCard(app, containing: closingMarker)
        XCTAssertTrue(closingCardNow.waitForExistence(timeout: 10))
        XCTAssertFalse(closingCardNow.label.contains("Gro"), "The card must not restore the older description")
    }

    /// A long debounce and slow writes expose the equal-but-newer edit race: typed, cleared,
    /// retyped, then closed before debounce. The close must journal the final value even though
    /// it equals the first in-flight write; that older response must not delete the newer intent.
    @MainActor
    func testADescriptionRetypedAfterASentClearIsWhatTheServerEndsWith() async throws {
        let (email, password) = try credentials()
        let rest = try await P16Rest.signIn(email: email, password: password)
        let marker = "UITEST-P16-\(Int(Date().timeIntervalSince1970))-retyped"
        let id = try await rest.insertItem(["type": "text", "title": marker, "content": "", "description": ""])
        deleteAtTeardown(rest, id)

        let app = XCUIApplication()
        signIn(app, email: email, password: password,
               extraArguments: ["--uitest-slow-item-writes", "--uitest-slow-item-write-seconds", "8",
                                "--uitest-field-debounce-seconds", "3"])
        let card = libraryCard(app, containing: marker)
        XCTAssertTrue(card.waitForExistence(timeout: 20), "Expected the seeded card")
        tapWhenHittable(card)
        let description = descriptionField(app)
        XCTAssertTrue(description.waitForExistence(timeout: 10), "Description field not found")
        tapUntilFocused(description)
        description.typeText("Gro")
        usleep(3_500_000)
        description.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 3))
        XCTAssertTrue(isEmpty(description, placeholder: "Add a description…"))
        usleep(3_500_000)
        description.typeText("Gro")
        closeSheet(app)

        let firstLanded = try await rest.waitFor("description", of: id, equalTo: "Gro", timeout: 20)
        XCTAssertTrue(firstLanded, "Expected the first typed value to land before the clear")
        let clearLanded = try await rest.waitFor("description", of: id, equalTo: "", timeout: 30)
        XCTAssertTrue(clearLanded, "Expected the clear sent before the close to land next")
        let delivered = try await rest.waitFor("description", of: id, equalTo: "Gro", timeout: 30)
        XCTAssertTrue(delivered, "Expected the retyped value to be what the server ends with")
        let cardNow = libraryCard(app, containing: marker)
        XCTAssertTrue(cardNow.waitForExistence(timeout: 10))
        tapWhenHittable(cardNow)
        XCTAssertTrue(description.waitForExistence(timeout: 10))
        XCTAssertEqual(description.value as? String, "Gro", "The reopened sheet must retain the newest value")
        closeSheet(app)
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

    // MARK: - Sharing never goes out behind the user's back (plan 16, Task 4d)

    /// Review P-4, on a stalled link (`--uitest-stall-item-writes`: every item write hangs 10 s, then
    /// times out). Sharing is turned on for a private item, and while that PATCH hangs the app
    /// leaves the foreground (Home) and comes back — the journal that runs then used to queue the
    /// share. The PATCH fails: the switch flips back off and the section says it couldn't update.
    /// Once the link is back (a relaunch without the switch, whose launch refresh flushes the
    /// queue) the item must still be private: a share the user saw fail is never published. A
    /// title edit queued in the same flight lands first, so the read proves that flush ran (4d
    /// review B-4).
    @MainActor
    func testAShareThatFailedInFrontOfTheUserIsNeverPublishedLater() async throws {
        let (email, password) = try credentials()
        let rest = try await P16Rest.signIn(email: email, password: password)
        let marker = "UITEST-P16-\(Int(Date().timeIntervalSince1970))-share"
        let id = try await rest.insertItem(["type": "text", "title": marker, "content": ""])
        deleteAtTeardown(rest, id)

        let app = XCUIApplication()
        signIn(app, email: email, password: password, extraArguments: ["--uitest-stall-item-writes"])
        let card = libraryCard(app, containing: marker)
        XCTAssertTrue(card.waitForExistence(timeout: 20), "Expected the seeded card")
        tapWhenHittable(card)
        let toggle = sharingSwitch(app)
        XCTAssertTrue(toggle.waitForExistence(timeout: 10), "Sharing switch not found")
        A11yScreens.scrollIntoView(app, toggle)
        XCTAssertEqual(toggle.value as? String, "0", "Expected the seeded item private")
        toggle.tap()
        XCTAssertEqual(toggle.value as? String, "1", "The switch turns on at once (optimistic)")
        let titled = editTitleInTheSameFlight(app)

        // Away and back while the share hangs.
        XCUIDevice.shared.press(.home)
        sleep(2)
        app.activate()
        let error = app.descendants(matching: .any)["detail.public.error"]
        XCTAssertTrue(error.waitForExistence(timeout: 25), "Expected the share to fail visibly once its PATCH times out")
        XCTAssertEqual(toggle.value as? String, "0", "The switch is back off")

        try await relaunchAndWaitForTheFlush(app, id: id, title: titled, rest: rest)
        let isPublic = try await rest.isPublic(id)
        XCTAssertFalse(isPublic, "A share the user saw fail must never be published later")
    }

    /// 4d review A-1, on the stalled link: Sharing is turned on and the sheet closed while that PATCH
    /// hangs — the close queues the share (plan 15). Reopened at once, the sheet shows the queued
    /// share (on) while the server is still private; the user turns it off, and closes while that
    /// PATCH hangs too. They last saw it off, so once the link is back the item must still be
    /// private. Off equals the server's value, so the close used to journal nothing, and the
    /// relaunch's flush published the queued share.
    @MainActor
    func testAQueuedShareTurnedBackOffInAReopenedSheetIsNeverPublished() async throws {
        let (email, password) = try credentials()
        let rest = try await P16Rest.signIn(email: email, password: password)
        let marker = "UITEST-P16-\(Int(Date().timeIntervalSince1970))-reshare"
        let id = try await rest.insertItem(["type": "text", "title": marker, "content": ""])
        deleteAtTeardown(rest, id)

        let app = XCUIApplication()
        signIn(app, email: email, password: password, extraArguments: ["--uitest-stall-item-writes"])
        let card = libraryCard(app, containing: marker)
        XCTAssertTrue(card.waitForExistence(timeout: 20), "Expected the seeded card")
        tapWhenHittable(card)
        let toggle = sharingSwitch(app)
        XCTAssertTrue(toggle.waitForExistence(timeout: 10), "Sharing switch not found")
        A11yScreens.scrollIntoView(app, toggle)
        XCTAssertEqual(toggle.value as? String, "0", "Expected the seeded item private")
        toggle.tap()
        XCTAssertEqual(toggle.value as? String, "1", "The switch turns on at once (optimistic)")
        closeSheet(app)   // the share still hangs: the close queues it

        tapWhenHittable(libraryCard(app, containing: marker))
        XCTAssertTrue(toggle.waitForExistence(timeout: 10), "Sharing switch not found on reopen")
        A11yScreens.scrollIntoView(app, toggle)
        XCTAssertEqual(toggle.value as? String, "1", "The reopened sheet shows the queued share")
        toggle.tap()
        XCTAssertEqual(toggle.value as? String, "0", "Turned back off")
        let titled = editTitleInTheSameFlight(app)
        closeSheet(app)   // the off PATCH hangs too

        try await relaunchAndWaitForTheFlush(app, id: id, title: titled, rest: rest)
        let isPublic = try await rest.isPublic(id)
        XCTAssertFalse(isPublic, "The user last saw it off: it must never be published")
    }

    /// The reverse, on the stalled link: a PUBLIC item with a sticky note is made private ("Make
    /// Private" — the note will be removed), and while that PATCH hangs the app leaves the
    /// foreground and comes back, so the journal queues the un-share. The PATCH fails: the switch
    /// flips back on and the note comes back. Once the link is back, the server must agree with
    /// what the sheet showed — still public, still with its note — not take the queued un-share
    /// (which made it private while the sheet said public). As above, a title edit queued in the
    /// same flight proves the relaunch's flush ran before `is_public` is read.
    @MainActor
    func testAnUnshareThatFailedInFrontOfTheUserLeavesTheItemPublicWithItsNote() async throws {
        let (email, password) = try credentials()
        let rest = try await P16Rest.signIn(email: email, password: password)
        let marker = "UITEST-P16-\(Int(Date().timeIntervalSince1970))-unshare"
        let note = "\(marker) note"
        let id = try await rest.insertItem(["type": "text", "title": marker, "content": "", "supplemental_note": note],
                                           isPublic: true)
        deleteAtTeardown(rest, id)

        let app = XCUIApplication()
        signIn(app, email: email, password: password, extraArguments: ["--uitest-stall-item-writes"])
        let card = libraryCard(app, containing: marker)
        XCTAssertTrue(card.waitForExistence(timeout: 20), "Expected the seeded card")
        tapWhenHittable(card)
        let toggle = sharingSwitch(app)
        XCTAssertTrue(toggle.waitForExistence(timeout: 10), "Sharing switch not found")
        A11yScreens.scrollIntoView(app, toggle)
        XCTAssertEqual(toggle.value as? String, "1", "Expected the seeded item public")
        let sticky = app.descendants(matching: .any)["detail.public.sticky"]
        XCTAssertTrue(sticky.waitForExistence(timeout: 5), "Expected the sticky note field")
        XCTAssertEqual(sticky.value as? String, note)
        toggle.tap()
        let makePrivate = app.buttons["Make Private"]
        XCTAssertTrue(makePrivate.waitForExistence(timeout: 5), "Expected the un-share confirmation")
        makePrivate.tap()
        XCTAssertTrue(waitUntilGone(sticky, timeout: 5), "The note field goes with the un-share (optimistic)")
        XCTAssertEqual(toggle.value as? String, "0")
        let titled = editTitleInTheSameFlight(app)

        // Away and back while the un-share hangs.
        XCUIDevice.shared.press(.home)
        sleep(2)
        app.activate()
        let error = app.descendants(matching: .any)["detail.public.error"]
        XCTAssertTrue(error.waitForExistence(timeout: 25), "Expected the un-share to fail visibly once its PATCH times out")
        XCTAssertEqual(toggle.value as? String, "1", "The switch is back on")
        XCTAssertTrue(sticky.waitForExistence(timeout: 5), "The note field is back")
        XCTAssertEqual(sticky.value as? String, note, "…with the note")

        try await relaunchAndWaitForTheFlush(app, id: id, title: titled, rest: rest)
        let isPublic = try await rest.isPublic(id)
        XCTAssertTrue(isPublic, "The server must end as the sheet showed it: public")
        let serverNote = try await rest.column("supplemental_note", of: id)
        XCTAssertEqual(serverNote, note, "…with its sticky note")
    }

    /// The sticky note's field hides its keyboard the way the sheet's other text fields do: while
    /// it has focus, the footer's "Hide keyboard" control is there, and it takes the focus away.
    /// (The field used to keep a focus of its own, which that control never saw.)
    @MainActor
    func testTheStickyNoteFieldCanHideItsKeyboard() async throws {
        let (email, password) = try credentials()
        let rest = try await P16Rest.signIn(email: email, password: password)
        let marker = "UITEST-P16-\(Int(Date().timeIntervalSince1970))-sticky"
        let id = try await rest.insertItem(["type": "text", "title": marker, "content": ""], isPublic: true)
        deleteAtTeardown(rest, id)

        let app = XCUIApplication()
        signIn(app, email: email, password: password)
        let card = libraryCard(app, containing: marker)
        XCTAssertTrue(card.waitForExistence(timeout: 20), "Expected the seeded card")
        tapWhenHittable(card)
        let sticky = app.descendants(matching: .any)["detail.public.sticky"]
        XCTAssertTrue(sticky.waitForExistence(timeout: 10), "Expected the sticky note field on a public item")
        A11yScreens.scrollIntoView(app, sticky)
        A11yScreens.tapUntilFocused(sticky)
        let focused = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hasKeyboardFocus == true"), object: sticky)
        XCTAssertEqual(XCTWaiter().wait(for: [focused], timeout: 3), .completed, "Expected the sticky note focused")

        let hide = app.buttons["detail.dismissKeyboard"]
        XCTAssertTrue(hide.waitForExistence(timeout: 5), "Expected the sheet's Hide keyboard control while the sticky note has focus")
        hide.tap()
        let unfocused = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hasKeyboardFocus == false"), object: sticky)
        XCTAssertEqual(XCTWaiter().wait(for: [unfocused], timeout: 5), .completed, "Expected the sticky note to give up the keyboard")
        XCTAssertTrue(waitUntilGone(hide, timeout: 5), "The control goes once nothing has focus")
        // 2b review N-3: VoiceOver hears the field's name once — the visible "Sticky note" label
        // above it isn't a second element saying the same.
        XCTAssertFalse(app.staticTexts["Sticky note"].exists, "The visible label repeats the field's name to VoiceOver")
        closeSheet(app)
    }

    // MARK: - The wrapping title and the footer (plan 16, 2b review I-1, M-3)

    /// Return in the explicit title editor dismisses the keyboard without replacing a selected
    /// word, inserting a line break, or committing the draft.
    @MainActor
    func testDoneOverASelectedWordKeepsTheTitleAndEndsEditing() async throws {
        let (email, password) = try credentials()
        let rest = try await P16Rest.signIn(email: email, password: password)
        let marker = "UITEST-P16-\(Int(Date().timeIntervalSince1970))-done"
        let original = "\(marker) Grocery list"
        let id = try await rest.insertItem(["type": "text", "title": original, "content": ""])
        deleteAtTeardown(rest, id)

        let app = XCUIApplication()
        signIn(app, email: email, password: password)
        let card = libraryCard(app, containing: marker)
        XCTAssertTrue(card.waitForExistence(timeout: 20), "Expected the seeded card")
        tapWhenHittable(card)
        let title = openTitleEditor(app)
        title.doubleTap()   // selects the word under the tap
        title.typeText("\n")   // the keyboard's "done"
        XCTAssertEqual(title.value as? String, original, "Done over a selected word must leave the title as it was")
        XCTAssertTrue(waitUntilGone(app.buttons["detail.dismissKeyboard"], timeout: 5), "…and end editing")
        sleep(2)   // Return dismisses the keyboard without committing a title draft.
        let serverTitle = try await rest.title(of: id)
        XCTAssertEqual(serverTitle, original, "Nothing is saved over the title")
        closeSheet(app)
    }

    /// At the accessibility sizes, on the slow link, typing in the sticky note — the sheet's bottom
    /// field, right above the pinned footer:
    /// - 2b review M-3: the footer drops its resting "Changes saved automatically" (under "Delete
    ///   item" it took two more lines, a fifth of the screen at AX3);
    /// - 4d review B-3: while a save is on its way it says "Saving…" — a spinner in the Delete row
    ///   (Task 4e) — and the footer keeps still. "Saving…" as a line under Delete grew the footer
    ///   ~400 ms into every pause in typing and shrank it again, covering and moving the note.
    @MainActor
    func testTheFooterKeepsStillWhileItSavesAtAccessibilitySizes() async throws {
        _ = try await footerWhileSaving(sizeCategory: "UICTContentSizeCategoryAccessibilityXL", size: "AX3",
                                        shot: "task-4e-ax3-sticky-saving")
    }

    /// 4e review M-3, at the largest text size, AX5, on the slow link: the Delete row has no room for
    /// a spinner. Measured on iOS 17.0 at AX5 — "Delete item" 274 pt wide, the hide-keyboard control
    /// 44, a spinner 56 drawn (44 laid out) — the row with one needed ~376 pt and overflowed even
    /// this 393 pt-wide phone: "Delete item" moved 10 pt left while it saved. Without one it needs
    /// 326 pt (no spacing beside a `Spacer`), and the narrowest phone the app supports — 375 pt —
    /// has 335 inside the sheet's insets: 3 pt to spare, too little for any spinner. So at AX4 and
    /// AX5 the footer shows no "Saving…" (an error still shows under Delete), never overflows, and
    /// keeps still through the save.
    @MainActor
    func testTheFooterRowFitsTheNarrowestPhoneAtTheLargestTextSize() async throws {
        let (email, password) = try credentials()
        let rest = try await P16Rest.signIn(email: email, password: password)
        let marker = "UITEST-P16-\(Int(Date().timeIntervalSince1970))-footer5"
        let id = try await rest.insertItem(["type": "text", "title": marker, "content": ""], isPublic: true)
        deleteAtTeardown(rest, id)

        let app = XCUIApplication()
        signIn(app, email: email, password: password)
        app.terminate()
        app.launchArguments = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
                               "--uitest-tab-view", "--uitest-slow-item-writes"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["View"].waitForExistence(timeout: 15), "Expected the app signed in at AX5")
        let card = libraryCard(app, containing: marker)
        XCTAssertTrue(card.waitForExistence(timeout: 20), "Expected the seeded card")
        tapWhenHittable(card)
        let delete = app.buttons["detail.delete"]
        XCTAssertTrue(delete.waitForExistence(timeout: 10), "Expected Delete item in the footer")
        let sticky = app.descendants(matching: .any)["detail.public.sticky"]
        XCTAssertTrue(sticky.waitForExistence(timeout: 10), "Expected the sticky note field on a public item")
        A11yScreens.scrollIntoView(app, sticky)
        A11yScreens.tapUntilFocused(sticky)
        let hide = app.buttons["detail.dismissKeyboard"]
        XCTAssertTrue(hide.waitForExistence(timeout: 5), "Expected the sticky note focused")

        sticky.typeText("For you")
        sleep(1)   // past the 400 ms autosave: its PATCH is on its 3 s way
        let whileSaving = (delete: delete.frame, hide: hide.frame)
        attachScreenshot(named: "task-4e-ax5-sticky-saving")
        XCTAssertFalse(app.descendants(matching: .any)["detail.autosave"].exists,
                       "At AX5 the Delete row has no room for \"Saving…\"")
        let saved = try await rest.waitFor("supplemental_note", of: id, equalTo: "For you", timeout: 10)
        XCTAssertTrue(saved, "Expected the sticky note saved")
        sleep(1)
        print("A11Y footer AX5 delete while saving \(whileSaving.delete) · after \(delete.frame) · hide while saving "
              + "\(whileSaving.hide) · after \(hide.frame) · screen \(app.frame)")
        XCTAssertEqual(delete.frame.minX, whileSaving.delete.minX, accuracy: 1, "Delete must not move while it saves")
        XCTAssertEqual(delete.frame.minY, whileSaving.delete.minY, accuracy: 1, "The footer must keep its height")
        XCTAssertGreaterThanOrEqual(whileSaving.delete.minX, 19, "Nothing overflows the sheet's leading inset")
        // The hide-keyboard control's frame is its 44 pt target, 2 pt past its 40 pt circle on each
        // side (an overhang, by design): at rest it ends 18 pt from the edge.
        XCTAssertLessThanOrEqual(whileSaving.hide.maxX, app.frame.maxX - 17, "…nor its trailing one")
        // What a 375 pt-wide phone gets: Delete, the 8 pt spacer, the hide-keyboard control.
        let needed = delete.frame.width + 8 + hide.frame.width
        print("A11Y footer AX5 row needs \(needed) pt of the 335 a 375 pt phone has")
        XCTAssertLessThanOrEqual(needed, 335, "At AX5 the Delete row must fit a 375 pt-wide phone")
        closeSheet(app)
    }

    /// The accessibility-size footer while it saves: a public item seeded, the app launched at
    /// `sizeCategory` on the slow link, the sticky note typed into. No resting caption; "Saving…"
    /// in the Delete row; the footer keeps its height through the save. Returns the frames of
    /// Delete, the spinner and the hide-keyboard control, measured while it saved.
    @MainActor
    private func footerWhileSaving(sizeCategory: String, size: String,
                                   shot: String) async throws -> (delete: CGRect, saving: CGRect, hide: CGRect) {
        let (email, password) = try credentials()
        let rest = try await P16Rest.signIn(email: email, password: password)
        let marker = "UITEST-P16-\(Int(Date().timeIntervalSince1970))-footer"
        let id = try await rest.insertItem(["type": "text", "title": marker, "content": ""], isPublic: true)
        deleteAtTeardown(rest, id)

        let app = XCUIApplication()
        signIn(app, email: email, password: password)
        app.terminate()
        app.launchArguments = ["-UIPreferredContentSizeCategoryName", sizeCategory,
                               "--uitest-tab-view", "--uitest-slow-item-writes"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["View"].waitForExistence(timeout: 15), "Expected the app signed in at \(size)")
        let card = libraryCard(app, containing: marker)
        XCTAssertTrue(card.waitForExistence(timeout: 20), "Expected the seeded card")
        tapWhenHittable(card)
        let delete = app.buttons["detail.delete"]
        XCTAssertTrue(delete.waitForExistence(timeout: 10), "Expected Delete item in the footer")
        let saving = app.descendants(matching: .any)["detail.autosave"]
        XCTAssertFalse(saving.exists, "At \(size) the footer has no resting caption")

        let sticky = app.descendants(matching: .any)["detail.public.sticky"]
        XCTAssertTrue(sticky.waitForExistence(timeout: 10), "Expected the sticky note field on a public item")
        A11yScreens.scrollIntoView(app, sticky)
        A11yScreens.tapUntilFocused(sticky)
        let hide = app.buttons["detail.dismissKeyboard"]
        XCTAssertTrue(hide.waitForExistence(timeout: 5), "Expected the sticky note focused")
        // The footer is measured with the keyboard up both times — while "Saving…" shows, and once
        // it has gone. (On the iOS 17.0 simulator the keyboard comes up only with the first typed
        // character, so a frame taken before typing has no keyboard under it.)
        sticky.typeText("For you")
        XCTAssertTrue(saving.waitForExistence(timeout: 5), "Expected \"Saving…\" while the save is on its way")
        XCTAssertEqual(saving.label, "Saving…")
        let whileSaving = delete.frame
        let indicator = saving.frame
        let hideFrame = hide.frame
        attachScreenshot(named: shot)
        XCTAssertTrue(waitUntilGone(saving, timeout: 15), "Expected \"Saving…\" gone once the save landed")
        print("A11Y footer \(size) delete while saving \(whileSaving) · after \(delete.frame) · saving \(indicator) · hide \(hideFrame)")
        XCTAssertEqual(delete.frame.minY, whileSaving.minY, accuracy: 1,
                       "The footer must keep its height through the save — not grow for \"Saving…\" and shrink again")
        XCTAssertEqual(indicator.midY, whileSaving.midY, accuracy: whileSaving.height / 2,
                       "\"Saving…\" sits in the Delete row")
        let saved = try await rest.waitFor("supplemental_note", of: id, equalTo: "For you", timeout: 10)
        XCTAssertTrue(saved, "Expected the sticky note saved")
        closeSheet(app)
        return (whileSaving, indicator, hideFrame)
    }

    /// 4d review B-4: at AX3 a save that fails says so — "Couldn't save — try again." — on its own
    /// line under "Delete item" (an error stays until something changes, so it may take the room),
    /// on the stalled link. Once the link is back, the queued edit is delivered.
    @MainActor
    func testAFailedSaveSaysSoUnderDeleteAtAccessibilitySizes() async throws {
        let (email, password) = try credentials()
        let rest = try await P16Rest.signIn(email: email, password: password)
        let marker = "UITEST-P16-\(Int(Date().timeIntervalSince1970))-axerror"
        let id = try await rest.insertItem(["type": "text", "title": marker, "content": ""])
        deleteAtTeardown(rest, id)

        let app = XCUIApplication()
        signIn(app, email: email, password: password)
        app.terminate()
        app.launchArguments = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL",
                               "--uitest-tab-view", "--uitest-stall-item-writes"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["View"].waitForExistence(timeout: 15), "Expected the app signed in at AX3")
        let card = libraryCard(app, containing: marker)
        XCTAssertTrue(card.waitForExistence(timeout: 20), "Expected the seeded card")
        tapWhenHittable(card)
        let delete = app.buttons["detail.delete"]
        XCTAssertTrue(delete.waitForExistence(timeout: 10), "Expected Delete item in the footer")

        let title = openTitleEditor(app)
        title.typeText(" x")   // wherever the caret is: what matters is that a save goes out
        let typed = (title.value as? String) ?? ""
        XCTAssertNotEqual(typed, marker, "Expected the title edited")
        commitTitle(app)
        let error = app.descendants(matching: .any)["detail.autosave.error"]
        XCTAssertTrue(error.waitForExistence(timeout: 20), "Expected the failed save to say so once its PATCH times out")
        XCTAssertEqual(error.label, "Couldn't save — try again.")
        attachScreenshot(named: "task-4e-ax3-save-error")
        print("A11Y footer AX3 delete \(delete.frame) error \(error.frame)")
        XCTAssertGreaterThanOrEqual(error.frame.minY, delete.frame.maxY - 4, "The error sits under Delete item")
        XCTAssertLessThanOrEqual(error.frame.maxY, app.frame.maxY, "…on screen")
        closeSheet(app)

        try await relaunchAndWaitForTheFlush(app, id: id, title: typed, rest: rest)
    }

    /// A realtime server title does not replace an uncommitted local draft or dismiss its
    /// keyboard. Cancel reveals that server title unchanged; the draft never reaches the server.
    @MainActor
    func testAServerTitleArrivingWhileTheTitleHasFocusIsLeftAsTheServerHasIt() async throws {
        let (email, password) = try credentials()
        let rest = try await P16Rest.signIn(email: email, password: password)
        let marker = "UITEST-P16-\(Int(Date().timeIntervalSince1970))-servertitle"
        let id = try await rest.insertItem(["type": "text", "title": marker, "content": "", "description": "Before realtime"])
        deleteAtTeardown(rest, id)

        let app = XCUIApplication()
        signIn(app, email: email, password: password)
        let card = libraryCard(app, containing: marker)
        XCTAssertTrue(card.waitForExistence(timeout: 20), "Expected the seeded card")
        tapWhenHittable(card)
        let title = openTitleEditor(app)
        title.typeText(" local draft")
        let draft = title.value as? String ?? ""
        XCTAssertNotEqual(draft, marker)
        let hide = app.buttons["detail.dismissKeyboard"]
        XCTAssertTrue(hide.waitForExistence(timeout: 5), "Expected the title focused")

        let serverTitle = "\(marker) from the server\n"
        let serverDescription = "Realtime row arrived"
        // A second field in the same row proves realtime was adopted while the title draft
        // stayed open; waiting only for the REST write would not establish that ordering.
        try await rest.setTitle(of: id, to: serverTitle, description: serverDescription)
        let arrived = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", serverDescription),
                                                object: descriptionField(app))
        XCTAssertEqual(XCTWaiter().wait(for: [arrived], timeout: 30), .completed)
        XCTAssertEqual(title.value as? String, draft, "A server title must leave the local draft untouched")
        XCTAssertTrue(hide.exists, "A server title ending in a line break must not dismiss the keyboard")
        hide.tap()
        let cancel = app.buttons["detail.title.cancel"]
        A11yScreens.scrollIntoView(app, cancel)
        cancel.tap()
        let collapsed = app.buttons["detail.title"]
        XCTAssertTrue(collapsed.waitForExistence(timeout: 5))
        XCTAssertEqual(collapsed.label, serverTitle, "Cancel must reveal the full server title")
        closeSheet(app)
        try await Task.sleep(for: .seconds(4))
        let after = try await rest.title(of: id)
        XCTAssertEqual(after, serverTitle, "Cancelling and closing must not publish the local draft")
    }

    // MARK: - The save error clears once what it reports has landed (batch B fix round 1)

    /// Review I-1, trigger A, end to end: a rich note's save fails ("Couldn't save — try again."), a
    /// share fails too, and the flush the failed share starts gets through and delivers the note. The
    /// error stayed up, though the note was on the server and the box was empty under it: the sheet
    /// adopted the flush's row before the queue had updated its entry, and nothing checked again.
    /// `--uitest-fail-item-writes <id> 2`: the note's PATCH and the share's fail, as offline; the
    /// third, the flush's, goes out. A note added afterwards lands once, after "abc".
    @MainActor
    func testTheSaveErrorClearsOnceTheFlushOfAFailedShareDeliversTheFailedNote() async throws {
        let (email, password) = try credentials()
        let rest = try await P16Rest.signIn(email: email, password: password)
        let marker = "UITEST-P16-\(Int(Date().timeIntervalSince1970))-caption"
        let first = #"{"type":"doc","content":[{"type":"paragraph","content":[{"type":"text","text":"first"}]}]}"#
        let id = try await rest.insertItem(["type": "text", "title": marker, "content": first])
        deleteAtTeardown(rest, id)

        let app = XCUIApplication()
        signIn(app, email: email, password: password, extraArguments: ["--uitest-fail-item-writes", id, "2"])
        let card = libraryCard(app, containing: marker)
        XCTAssertTrue(card.waitForExistence(timeout: 20), "Expected the seeded card")
        tapWhenHittable(card)
        let box = app.textViews["detail.notes.editor"]
        XCTAssertTrue(box.waitForExistence(timeout: 10), "Notes box not found")
        tapUntilFocused(box)
        box.typeText("abc")
        app.buttons["detail.dismissKeyboard"].tap()                      // the box lets go: its save (PATCH 1) fails
        let error = app.staticTexts["detail.autosave.error"]
        XCTAssertTrue(error.waitForExistence(timeout: 10), "precondition: the note's save failed in front of the user")

        let toggle = sharingSwitch(app)
        A11yScreens.scrollIntoView(app, toggle)
        toggle.tap()                                                     // the share (PATCH 2) fails; its flush goes out
        XCTAssertTrue(app.descendants(matching: .any)["detail.public.error"].waitForExistence(timeout: 10),
                      "precondition: the share failed in front of the user")
        XCTAssertTrue(waitUntilGone(error, timeout: 6),
                      "Expected \"Couldn't save — try again.\" gone once the flush delivered the note")
        XCTAssertTrue(app.staticTexts["detail.autosave"].exists, "Expected the resting caption back")
        attachScreenshot(named: "batch-b-fr1-caption-cleared")
        let delivered = try await serverParagraphs(of: id, rest: rest, waitingFor: ["first", "abc"])
        XCTAssertEqual(delivered, ["first", "abc"], "Expected the flush to have delivered the note")
        XCTAssertEqual((box.value as? String) ?? "", "", "The delivered note has left the box")

        A11yScreens.scrollIntoView(app, box)
        tapUntilFocused(box)
        box.typeText("def")
        app.buttons["detail.dismissKeyboard"].tap()
        let notes = try await serverParagraphs(of: id, rest: rest, waitingFor: ["first", "abc", "def"])
        XCTAssertEqual(notes, ["first", "abc", "def"], "Each note once, in order")
        let isPublic = try await rest.isPublic(id)
        XCTAssertFalse(isPublic, "The failed share never reached the server")
    }

    /// Re-review N-2, end to end (batch B fix round 2): a sticky note's save fails ("Couldn't save —
    /// try again."), then the user makes the item private, confirming that the note is removed, and
    /// that un-share lands. The server holds what they last asked for, with nothing left to retry,
    /// yet the error stayed up: the toggle's PATCH went out past the queue's delivered ledger, so its
    /// removal of the note didn't count as the newer value of the note it is.
    /// `--uitest-fail-item-writes <id> 1`: only the note's PATCH fails, as offline; the un-share's
    /// goes out. Hiding the keyboard saves the sticky note again (its text is written back as the
    /// field lets go, measured on 17.0: a re-save that worked cleared the error before the un-share,
    /// and this test passed on the unfixed app). So the keyboard goes inside a 3 s field debounce
    /// (`--uitest-field-debounce-seconds`): the typing and that write-back are one save, the one
    /// that fails, and the un-share is the next write of the item.
    @MainActor
    func testTheSaveErrorClearsOnceAnUnshareRemovesTheStickyNoteWhoseSaveFailed() async throws {
        let (email, password) = try credentials()
        let rest = try await P16Rest.signIn(email: email, password: password)
        let marker = "UITEST-P16-\(Int(Date().timeIntervalSince1970))-unsharecaption"
        let note = "\(marker) note"
        let id = try await rest.insertItem(["type": "text", "title": marker, "content": "", "supplemental_note": note],
                                           isPublic: true)
        deleteAtTeardown(rest, id)

        let app = XCUIApplication()
        signIn(app, email: email, password: password,
               extraArguments: ["--uitest-fail-item-writes", id, "1", "--uitest-field-debounce-seconds", "3"])
        let card = libraryCard(app, containing: marker)
        XCTAssertTrue(card.waitForExistence(timeout: 20), "Expected the seeded card")
        tapWhenHittable(card)
        let sticky = app.descendants(matching: .any)["detail.public.sticky"]
        XCTAssertTrue(sticky.waitForExistence(timeout: 10), "Expected the sticky note field on a public item")
        A11yScreens.scrollIntoView(app, sticky)
        A11yScreens.tapUntilFocused(sticky)
        sticky.typeText(" more")
        let typed = (sticky.value as? String) ?? ""
        XCTAssertNotEqual(typed, note, "precondition: the note was edited")
        app.buttons["detail.dismissKeyboard"].tap()                      // inside the debounce
        let error = app.staticTexts["detail.autosave.error"]
        XCTAssertTrue(error.waitForExistence(timeout: 10), "precondition: the note's save (PATCH 1) failed in front of the user")
        sleep(2)                                                         // nothing else saves the note meanwhile
        XCTAssertTrue(error.exists, "precondition: the error is still up before the un-share")
        let seedStands = try await rest.column("supplemental_note", of: id)
        XCTAssertEqual(seedStands, note, "precondition: the typed note never reached the server")

        let toggle = sharingSwitch(app)
        A11yScreens.scrollIntoView(app, toggle)
        XCTAssertEqual(toggle.value as? String, "1", "precondition: the seeded item is public")
        toggle.tap()
        let makePrivate = app.buttons["Make Private"]
        XCTAssertTrue(makePrivate.waitForExistence(timeout: 5), "Expected the un-share confirmation")
        makePrivate.tap()                                                // the un-share (PATCH 2) goes out
        let landed = try await rest.waitForPublic(id, equalTo: false, timeout: 15)
        XCTAssertTrue(landed, "precondition: the un-share landed")
        XCTAssertTrue(waitUntilGone(error, timeout: 6),
                      "Expected \"Couldn't save — try again.\" gone once the un-share removed the note")
        XCTAssertTrue(app.staticTexts["detail.autosave"].exists, "Expected the resting caption back")
        XCTAssertFalse(app.descendants(matching: .any)["detail.public.error"].exists, "The un-share itself worked")
        XCTAssertEqual(toggle.value as? String, "0", "The switch shows private")
        attachScreenshot(named: "batch-b-fr2-unshare-caption-cleared")
        let serverNote = try await rest.column("supplemental_note", of: id)
        XCTAssertNil(serverNote, "The note the user agreed to remove is gone")
    }

    /// The seeded row's rich note as paragraphs, polled until they are `expected` (up to 15 s): the
    /// last read either way.
    private func serverParagraphs(of id: String, rest: P16Rest, waitingFor expected: [String]) async throws -> [String] {
        var read: [String] = []
        for _ in 0..<30 {
            read = Self.paragraphs(try await rest.column("content", of: id))
            if read == expected { break }
            try await Task.sleep(for: .milliseconds(500))
        }
        return read
    }

    /// A TipTap document's paragraphs, in order.
    private static func paragraphs(_ content: String?) -> [String] {
        guard let data = content?.data(using: .utf8),
              let document = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let blocks = document["content"] as? [[String: Any]]
        else { return [] }
        return blocks.map { (($0["content"] as? [[String: Any]]) ?? []).compactMap { $0["text"] as? String }.joined() }
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
        // N-2: sized by its container, not a measured viewport height that starts at 0): the part
        // of it the keyboard leaves while it is up, all of it once it has gone. One character
        // nothing contains is below the server search's two-character minimum, so the local filter
        // answers "No matches" at once; return drops the keyboard.
        //
        // Batch B: on iOS 17.0 the pane kept the keyboard-up centring after the keyboard had gone
        // (here, after the part-way tap above) — 319 pt against 445. Earlier 17.0 passes were
        // vacuous: a stuck simulator flag hid the software keyboard. Measured with the keyboard up
        // and after it, so a pane that ignores the keyboard fails as well as one that keeps it.
        field.tap()
        field.typeText("¶")
        // Plan 16: the pane is one VoiceOver element (title, then message); measuring every match
        // together still holds if its identifier ever lands on its parts again.
        let paneParts = app.descendants(matching: .any).matching(identifier: "library.empty")
        func paneFrame() -> CGRect { paneParts.allElementsBoundByIndex.map(\.frame).reduce(CGRect.null) { $0.union($1) } }
        XCTAssertTrue(paneParts.firstMatch.waitForExistence(timeout: 5), "Expected the No matches pane")
        XCTAssertTrue(app.keyboards.element.exists, "Expected the keyboard up while the query is typed")
        sleep(1)
        let paneWithKeyboard = paneFrame()
        attachScreenshot(named: "batch-b-no-matches-keyboard-up")
        field.typeText("\n")
        XCTAssertTrue(eventually(5) { !app.keyboards.element.exists }, "Expected return to drop the keyboard")
        // Between the search row's bottom (its 10 pt bottom padding) and the tab bar — the scroll
        // view's own accessibility frame runs under both bars, so it can't be the reference.
        let paneTop = restPill.maxY + 10
        let paneBottom = app.tabBars.firstMatch.frame.minY
        let centre = (paneTop + paneBottom) / 2
        let centred = eventually(3) { abs(paneFrame().midY - centre) <= 30 }
        let pane = paneFrame()
        XCTAssertTrue(centred, "Expected No matches centred below the search row once the keyboard has gone (at \(pane), between \(paneTop) and \(paneBottom))")
        XCTAssertGreaterThan(pane.midY, paneWithKeyboard.midY + 60,
                             "Expected No matches to follow the keyboard down: at \(paneWithKeyboard.midY) with it up, \(pane.midY) after")
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
        // (never on 17.2) — declined with the canonical helper (plan 16: exactly "Not Now", in the
        // app or SpringBoard, until it has really gone), so it can't cover the View tab.
        A11yScreens.dismissSavePasswordPrompt(app)
    }

    /// Taps `element` once it can really take the tap — declining a "Save Password?" sheet that
    /// arrived late in the meantime (a tap while it's up gets a {-1, -1} hit point).
    @MainActor
    private func tapWhenHittable(_ element: XCUIElement, timeout: TimeInterval = 10) {
        let app = XCUIApplication()
        _ = eventually(timeout) {
            if app.buttons["Not Now"].exists { A11yScreens.dismissSavePasswordPrompt(app, timeout: 3) }
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

    /// The detail sheet's Sharing switch.
    @MainActor
    private func sharingSwitch(_ app: XCUIApplication) -> XCUIElement {
        app.switches["detail.public.toggle"]
    }

    /// Waits until `element` no longer exists; true if it went within `timeout`.
    @MainActor
    private func waitUntilGone(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        return XCTWaiter().wait(for: [gone], timeout: timeout) == .completed
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

    /// Explicitly commits a title alongside the stalled sharing write. Its later delivery proves
    /// the relaunch's flush ran before the tests inspect the sharing state.
    @MainActor
    private func editTitleInTheSameFlight(_ app: XCUIApplication) -> String {
        let title = openTitleEditor(app)
        title.typeText(" t")
        let typed = (title.value as? String) ?? ""
        XCTAssertTrue(typed.contains(" t"), "Expected the title draft to contain the edit")
        commitTitle(app)
        return typed
    }

    /// The link is back: runs the app again without the network switches (still signed in) — its
    /// launch refresh flushes the queue before it reads page 1 — and waits until the queued `title`
    /// has landed, so whatever else was queued for the item has gone out with it.
    @MainActor
    private func relaunchAndWaitForTheFlush(_ app: XCUIApplication, id: String, title: String, rest: P16Rest) async throws {
        app.terminate()
        app.launchArguments = ["--uitest-tab-view"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["View"].waitForExistence(timeout: 15), "Expected the app signed in")
        let flushed = try await rest.waitForTitle(of: id, equalTo: title, timeout: 30)
        let serverTitle = try await rest.title(of: id)
        XCTAssertTrue(flushed, "Expected the relaunch's flush to deliver the queued title, got '\(serverTitle ?? "nil")'")
    }

    /// Replaces the description, waits past autosave, then clears while that write is in flight.
    /// The description deliberately retains the inline autosave contract.
    @MainActor
    private func typeThenClearDescription(_ text: String, in field: XCUIElement) {
        tapUntilFocused(field)
        if !isEmpty(field, placeholder: "Add a description…") {
            field.typeKey("a", modifierFlags: .command)
        }
        field.typeText(text)
        XCTAssertEqual(field.value as? String, text, "Expected the typed description")
        sleep(1)
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: text.count))
        XCTAssertTrue(isEmpty(field, placeholder: "Add a description…"), "Expected the description cleared")
    }

    @MainActor
    private func openTitleEditor(_ app: XCUIApplication) -> XCUIElement {
        let collapsed = app.buttons["detail.title"]
        XCTAssertTrue(collapsed.waitForExistence(timeout: 10), "Title button not found")
        A11yScreens.scrollIntoView(app, collapsed)
        collapsed.tap()
        let editor = detailTitleField(app)
        XCTAssertTrue(editor.waitForExistence(timeout: 5), "Title editor not found")
        tapUntilFocused(editor)
        return editor
    }

    /// Save begins the durable commit; callers choose whether to wait for the network or close.
    @MainActor
    private func commitTitle(_ app: XCUIApplication) {
        let hide = app.buttons["detail.dismissKeyboard"]
        if hide.exists { hide.tap() }
        let save = app.buttons["detail.title.save"]
        A11yScreens.scrollIntoView(app, save)
        XCTAssertTrue(save.isEnabled, "Title Save must be enabled for the local draft")
        save.tap()
    }

    @MainActor
    private func detailTitleField(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@ AND (elementType == %d OR elementType == %d)",
                                  "detail.title.editor", Int(XCUIElement.ElementType.textView.rawValue),
                                  Int(XCUIElement.ElementType.textField.rawValue)))
            .firstMatch
    }

    /// Whether `field` shows `placeholder` — as its `placeholderValue`, or (an empty field, the way
    /// XCUITest reports some text fields and vertical-axis ones) as its `value`.
    @MainActor
    private func showsPlaceholder(_ placeholder: String, _ field: XCUIElement) -> Bool {
        field.placeholderValue == placeholder || (field.value as? String) == placeholder
    }

    /// Whether `field` is empty: no text, or its placeholder reported as its value.
    @MainActor
    private func isEmpty(_ field: XCUIElement, placeholder: String) -> Bool {
        let value = (field.value as? String) ?? ""
        return value.isEmpty || value == placeholder || value == field.placeholderValue
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

    /// A seeded row's `is_public`.
    func isPublic(_ id: String) async throws -> Bool {
        let (data, response) = try await Self.send(request("/rest/v1/items", query: [
            URLQueryItem(name: "id", value: "eq.\(id)"),
            URLQueryItem(name: "select", value: "is_public"),
        ]))
        guard Self.succeeded(response),
              let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let value = rows.first?["is_public"] as? Bool
        else { throw Failure(description: "is_public read failed for \(id)") }
        return value
    }

    /// Polls a seeded row's `is_public` (about once a second) until it equals `expected`; false if
    /// it never did within `timeout`.
    func waitForPublic(_ id: String, equalTo expected: Bool, timeout: TimeInterval) async throws -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let value = try? await isPublic(id), value == expected { return true }
            try await Task.sleep(for: .seconds(1))
        } while Date() < deadline
        return false
    }

    /// A title write from outside the app — what the server's transcription job does when it
    /// replaces an object-name title with an AI one.
    func setTitle(of id: String, to title: String, description: String? = nil) async throws {
        var request = request("/rest/v1/items", query: [URLQueryItem(name: "id", value: "eq.\(id)")], method: "PATCH")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var values = ["title": title]
        if let description { values["description"] = description }
        request.httpBody = try JSONSerialization.data(withJSONObject: values)
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
