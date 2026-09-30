import XCTest
@testable import StashKit

/// Plan 16, Task 4 review I-1: a title the user typed that was then sent (or queued) must stay
/// cleared when the user clears the field. `DetailFieldEdits` is the one rule the detail sheet's
/// autosave, dismiss journal and `adopt` share; these tests drive it against a real `PendingEdits`
/// queue, in the order `ItemDetailView` makes its calls:
///
/// - an autosave records `textPatch` BEFORE sending it (`save(_:)`);
/// - when a save lands, `superseding(sent)` is recorded, then the sent patch is confirmed, then the
///   row is adopted (directly when it's the newest save, otherwise through the store's change);
/// - closing records `textPatch` (`handleDismiss` → `unconfirmedPatch`).
///
/// `LibraryDetailUITests` drives the same scenarios through the real sheet (slow and stalled links).
@MainActor
final class DetailFieldEditsTests: XCTestCase {
    private var directory: URL!
    private var queue: PendingEdits!
    private let t0 = Date(timeIntervalSince1970: 1_790_000_000)
    private let objectName = "f200ad94-32d7-4b39-bcfc-313b5e0a9c41.m4a"

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DetailFieldEditsTests-\(UUID().uuidString)", isDirectory: true)
        let userId = UUID()
        queue = PendingEdits(userId: userId, directory: directory, session: FakeSession(signedIn: userId))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: - A stand-in for one open sheet

    /// `local` is the sheet's fields, `snapshot` the server's last row — as in `ItemDetailView`.
    private struct Sheet {
        var local: Item
        var snapshot: Item
    }

    /// A save the sheet has started: what it recorded and sent, and when it captured it.
    private struct Save {
        let patch: ItemPatch
        let capturedAt: Date
    }

    private func audioRow(title: String?, description: String = "") -> Item {
        Item(id: UUID(), type: .audio, title: title, content: nil, url: nil, filePath: nil,
             description: description, summary: nil, pageBody: nil, supplementalNote: nil, mimeType: nil,
             isPublic: false, createdAt: t0, attributes: ItemAttributes(media: MediaAttributes(durationS: 5)))
    }

    /// Opens a sheet on `server` the way `ItemDetailView.init` does: queued values laid over the
    /// server's row, then shown as the fields show it.
    private func open(_ server: Item) -> Sheet {
        let start = queue.sheetStart(for: server, serverRow: server)
        return Sheet(local: ItemDisplay.editableRow(start.shown), snapshot: start.server)
    }

    private func edits(_ sheet: Sheet) -> DetailFieldEdits {
        DetailFieldEdits(local: sheet.local, baseline: ItemDisplay.editableRow(sheet.snapshot),
                         queued: queue.edit(for: sheet.local.id))
    }

    /// The debounced autosave: nil when there was nothing to send.
    private func autosave(_ sheet: Sheet, at time: TimeInterval) -> Save? {
        let patch = edits(sheet).textPatch
        guard !patch.isEmpty else { return nil }
        let save = Save(patch: patch, capturedAt: t0.addingTimeInterval(time))
        queue.record(itemId: sheet.local.id, patch: save.patch, capturedAt: save.capturedAt)
        return save
    }

    /// The server's row once `patch` is applied to `row`.
    private func applying(_ patch: ItemPatch, to row: Item) -> Item {
        var next = row
        if let title = patch.title { next.title = title }
        if let description = patch.description { next.description = description }
        if let note = patch.supplementalNote { next.supplementalNote = note.isEmpty ? nil : note }
        return next
    }

    /// `save` came back as `response`: supersede, confirm, adopt — `ItemDetailView.save(_:)`'s order.
    private func land(_ save: Save, as response: Item, in sheet: inout Sheet, at time: TimeInterval) {
        let superseding = edits(sheet).superseding(save.patch)
        if !superseding.isEmpty {
            queue.record(itemId: sheet.local.id, patch: superseding, capturedAt: t0.addingTimeInterval(time))
        }
        queue.confirm(itemId: sheet.local.id, patch: save.patch, capturedAt: save.capturedAt)
        adopt(response, in: &sheet)
    }

    private func adopt(_ incoming: Item, in sheet: inout Sheet) {
        sheet.local = edits(sheet).adopting(incoming)
        sheet.snapshot = incoming
    }

    /// Closing: what `handleDismiss` journals.
    private func dismiss(_ sheet: Sheet, at time: TimeInterval) {
        let patch = edits(sheet).textPatch
        guard !patch.isEmpty else { return }
        queue.record(itemId: sheet.local.id, patch: patch, capturedAt: t0.addingTimeInterval(time))
    }

    /// What a flush of the queue would send for the item (`PendingEdit.fieldPatch`).
    private func queuedTitle(_ sheet: Sheet) -> String? {
        queue.edit(for: sheet.local.id)?.fieldPatch.title
    }

    // MARK: - Opening, typing, saving

    func testOpeningAndClosingAnUntouchedObjectNameTitleWritesNothing() {
        let server = audioRow(title: objectName)
        var sheet = open(server)
        XCTAssertEqual(sheet.local.title, "", "An object name opens as an empty field")
        XCTAssertNil(autosave(sheet, at: 1), "Nothing typed: nothing to save")

        adopt(server, in: &sheet)   // e.g. the page_body fetch bringing the same row back
        XCTAssertEqual(sheet.local.title, "")
        dismiss(sheet, at: 2)
        XCTAssertNil(queue.edit(for: server.id), "Closing an untouched sheet queues nothing")
    }

    func testATitleTypedAndClearedBeforeItsAutosaveWritesNothing() {
        let sheet = open(audioRow(title: objectName))
        var typed = sheet
        typed.local.title = "Gro"
        typed.local.title = ""   // cleared again inside the 400 ms debounce
        XCTAssertNil(autosave(typed, at: 1))
        dismiss(typed, at: 2)
        XCTAssertNil(queue.edit(for: sheet.local.id), "Nothing was ever sent, so nothing needs undoing")
    }

    func testATypedTitleIsSavedAndStaysOnceItsSaveLands() throws {
        let server = audioRow(title: objectName)
        var sheet = open(server)
        sheet.local.title = "Groceries"
        let save = try XCTUnwrap(autosave(sheet, at: 1))
        XCTAssertEqual(save.patch, ItemPatch(title: "Groceries"), "Only the title is sent")

        land(save, as: applying(save.patch, to: server), in: &sheet, at: 2)
        XCTAssertEqual(sheet.local.title, "Groceries")
        XCTAssertNil(queue.edit(for: server.id), "The server confirmed it")
        XCTAssertTrue(edits(sheet).textPatch.isEmpty, "Nothing left to save")
    }

    // MARK: - I-1: a clear after the typed title was sent or queued

    /// Scenario A: "Gro" is in flight when the user clears the field; the clear's autosave runs
    /// before "Gro" comes back. The clear is sent after "Gro" (latest wins in the queue), the "Gro"
    /// response never refills the field, and the server ends empty.
    func testAClearWhileTheTypedTitleIsInFlightSupersedesIt() throws {
        let server = audioRow(title: objectName)
        var sheet = open(server)
        sheet.local.title = "Gro"
        let sendGro = try XCTUnwrap(autosave(sheet, at: 1))

        sheet.local.title = ""
        let clear = autosave(sheet, at: 2)
        XCTAssertEqual(clear?.patch.title, "", "The clear must be sent: \"Gro\" is still on its way to the server")
        XCTAssertEqual(queuedTitle(sheet), "", "The clear replaces \"Gro\" in the queue (latest wins)")

        let groRow = applying(sendGro.patch, to: server)
        land(sendGro, as: groRow, in: &sheet, at: 3)
        XCTAssertEqual(sheet.local.title, "", "The \"Gro\" response must not refill the cleared field")
        XCTAssertEqual(queuedTitle(sheet), "", "The clear is still queued after \"Gro\" is confirmed")

        let clearSave = try XCTUnwrap(clear)
        land(clearSave, as: applying(clearSave.patch, to: groRow), in: &sheet, at: 4)
        XCTAssertEqual(sheet.local.title, "")
        XCTAssertEqual(sheet.snapshot.title, "", "The server ends with the cleared title")
        XCTAssertNil(queue.edit(for: server.id))
        XCTAssertTrue(edits(sheet).textPatch.isEmpty)
    }

    /// Scenario A, other timing: the user clears the field and "Gro" comes back before the clear's
    /// autosave has run. The landing save queues the clear before it confirms "Gro", so the field
    /// stays empty and the clear still goes out.
    func testAClearTypedJustBeforeTheSentTitleLandsIsQueuedBeforeTheConfirm() throws {
        let server = audioRow(title: objectName)
        var sheet = open(server)
        sheet.local.title = "Gro"
        let sendGro = try XCTUnwrap(autosave(sheet, at: 1))

        sheet.local.title = ""   // its autosave is still in the debounce
        XCTAssertEqual(edits(sheet).superseding(sendGro.patch), ItemPatch(title: ""),
                       "\"Gro\" landed after the user cleared it: the clear is the newest word")
        land(sendGro, as: applying(sendGro.patch, to: server), in: &sheet, at: 2)
        XCTAssertEqual(sheet.local.title, "", "The \"Gro\" response must not refill the cleared field")
        XCTAssertEqual(queuedTitle(sheet), "", "The clear is queued (a close now would send it)")
        XCTAssertEqual(autosave(sheet, at: 3)?.patch.title, "", "The debounced autosave then sends the clear")
    }

    /// Scenario B: "Gro" failed to send (offline) and stays queued; the user clears the field and
    /// closes. The queue must deliver the clear, not "Gro", and the list shows the type label.
    func testAClearAfterAFailedSendIsWhatTheQueueDelivers() throws {
        let server = audioRow(title: objectName)
        var sheet = open(server)
        sheet.local.title = "Gro"
        _ = try XCTUnwrap(autosave(sheet, at: 1))   // the PATCH fails: never confirmed

        sheet.local.title = ""
        XCTAssertEqual(autosave(sheet, at: 2)?.patch.title, "", "The clear must be sent over the queued \"Gro\"")
        dismiss(sheet, at: 3)
        XCTAssertEqual(queuedTitle(sheet), "", "A flush sends the clear")
        let listRow = queue.overlay(server)
        XCTAssertEqual(ItemDisplay.displayTitle(for: listRow), "Voice note", "The card reads its type label")

        let reopened = open(server)
        XCTAssertEqual(reopened.local.title, "", "Reopening shows the cleared field, not \"Gro\"")
    }

    /// Scenario C: the user clears the field and closes at once while "Gro" is still in flight —
    /// the dismiss journal (not an autosave) must supersede "Gro".
    func testAClearThenAnInstantCloseWhileTheTypedTitleIsInFlight() throws {
        let server = audioRow(title: objectName)
        var sheet = open(server)
        sheet.local.title = "Gro"
        let sendGro = try XCTUnwrap(autosave(sheet, at: 1))

        sheet.local.title = ""
        dismiss(sheet, at: 2)   // closed inside the clear's debounce
        XCTAssertEqual(queuedTitle(sheet), "", "The close must queue the clear over the in-flight \"Gro\"")

        // "Gro" lands after the close; the sheet is gone, so only the confirm runs.
        queue.confirm(itemId: server.id, patch: sendGro.patch, capturedAt: sendGro.capturedAt)
        XCTAssertEqual(queuedTitle(sheet), "", "Confirming \"Gro\" leaves the newer clear queued")
    }

    // MARK: - A server title arriving while the sheet is open (the transcription job's AI title)

    func testAnAITitleArrivingWhileTheFieldIsUntouchedReplacesThePlaceholder() {
        let server = audioRow(title: objectName)
        var sheet = open(server)
        let aiRow = applying(ItemPatch(title: "Grocery run ideas"), to: server)
        adopt(aiRow, in: &sheet)
        XCTAssertEqual(sheet.local.title, "Grocery run ideas")
        XCTAssertTrue(edits(sheet).textPatch.isEmpty, "Adopting the server's title is not an edit")
    }

    func testAnAITitleArrivingMidTypingKeepsWhatTheUserTyped() {
        let server = audioRow(title: objectName)
        var sheet = open(server)
        sheet.local.title = "Gro"   // still in the debounce
        adopt(applying(ItemPatch(title: "Grocery run ideas"), to: server), in: &sheet)
        XCTAssertEqual(sheet.local.title, "Gro", "The user's typing wins")
        XCTAssertEqual(edits(sheet).textPatch.title, "Gro", "…and is saved over the AI title")
    }

    /// Once the clear has landed the field and the server agree again, so a later AI title fills
    /// the field — exactly as it would have had the user never typed.
    func testAnAITitleArrivingAfterASavedClearFillsTheField() throws {
        let server = audioRow(title: objectName)
        var sheet = open(server)
        sheet.local.title = "Gro"
        let sendGro = try XCTUnwrap(autosave(sheet, at: 1))
        let groRow = applying(sendGro.patch, to: server)
        land(sendGro, as: groRow, in: &sheet, at: 2)
        sheet.local.title = ""
        let clear = try XCTUnwrap(autosave(sheet, at: 3))
        let clearedRow = applying(clear.patch, to: groRow)
        land(clear, as: clearedRow, in: &sheet, at: 4)
        XCTAssertNil(queue.edit(for: server.id))

        adopt(applying(ItemPatch(title: "Grocery run ideas"), to: clearedRow), in: &sheet)
        XCTAssertEqual(sheet.local.title, "Grocery run ideas")
        XCTAssertTrue(edits(sheet).textPatch.isEmpty)
    }

    /// While the clear is still on its way, an AI title landing meanwhile doesn't replace it: the
    /// clear is the user's newest word and still goes out.
    func testAnAITitleArrivingWhileAClearIsInFlightKeepsTheField() throws {
        let server = audioRow(title: objectName)
        var sheet = open(server)
        sheet.local.title = "Gro"
        _ = try XCTUnwrap(autosave(sheet, at: 1))
        sheet.local.title = ""
        _ = try XCTUnwrap(autosave(sheet, at: 2))

        adopt(applying(ItemPatch(title: "Grocery run ideas"), to: server), in: &sheet)
        XCTAssertEqual(sheet.local.title, "", "The pending clear is kept")
        XCTAssertEqual(edits(sheet).textPatch.title, "", "…and still sent")
    }

    func testANewObjectNameArrivingStillReadsAsEmpty() {
        let server = audioRow(title: objectName)
        var sheet = open(server)
        adopt(applying(ItemPatch(title: "1758945584318.m4a"), to: server), in: &sheet)
        XCTAssertEqual(sheet.local.title, "")
        XCTAssertTrue(edits(sheet).textPatch.isEmpty)
    }

    // MARK: - Every other field keeps its plain comparison with the server's row

    func testNonTitleFieldsKeepTheirCurrentBehaviour() throws {
        let server = audioRow(title: objectName, description: "Server description")
        var sheet = open(server)

        sheet.local.description = "Typed description"
        XCTAssertEqual(edits(sheet).textPatch, ItemPatch(description: "Typed description"),
                       "A description edit sends only the description — never the placeholder title")
        adopt(applying(ItemPatch(description: "Enrichment's description"), to: server), in: &sheet)
        XCTAssertEqual(sheet.local.description, "Typed description", "An unsaved description is kept")

        var untouched = open(server)
        adopt(applying(ItemPatch(description: "Enrichment's description"), to: server), in: &untouched)
        XCTAssertEqual(untouched.local.description, "Enrichment's description", "An untouched one follows the server")

        // The sticky note: nil and "" are the same empty note.
        var note = open(server)
        note.local.supplementalNote = ""
        XCTAssertTrue(edits(note).textPatch.isEmpty)
        note.local.supplementalNote = "For you"
        XCTAssertEqual(edits(note).textPatch, ItemPatch(supplementalNote: "For you"))

        // Plan 16 scope: only the title reads the queue. A description the queue still holds while
        // the field is back at the server's value is not re-sent (unchanged pre-plan-16 behaviour).
        var reverted = open(server)
        queue.record(itemId: server.id, patch: ItemPatch(description: "Queued description"), capturedAt: t0)
        reverted.local.description = "Server description"
        XCTAssertNil(edits(reverted).textPatch.description)
    }

    /// The rest of `adopt`'s merge, unchanged: a location the user just set and an optimistic
    /// Sharing flip are kept over a row that predates them; the server's other columns are taken.
    func testAdoptKeepsALocalLocationAndSharingFlipOverAnOlderRow() {
        let server = audioRow(title: objectName)
        var sheet = open(server)
        let location = CapturedLocation(label: "Brooklyn", source: "manual")
        sheet.local.attributes.location = location
        sheet.local.isPublic = true
        var incoming = server
        incoming.summary = "A new summary"
        adopt(incoming, in: &sheet)
        XCTAssertEqual(sheet.local.attributes.location, location)
        XCTAssertTrue(sheet.local.isPublic)
        XCTAssertEqual(sheet.local.summary, "A new summary")
    }
}
