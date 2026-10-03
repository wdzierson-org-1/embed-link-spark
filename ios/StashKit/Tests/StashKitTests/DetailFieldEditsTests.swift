import XCTest
@testable import StashKit

/// Plan 16, Task 4 review I-1 and Task 4c (re-review §9, m-3): a title, description or sticky note
/// the user changed after a value of it was sent (or queued) must keep the user's value — a clear
/// or a revert included. `DetailFieldEdits` is the one rule the detail sheet's autosave, dismiss
/// journal and `adopt` share; these tests drive it against a real `PendingEdits` queue, in the
/// order `ItemDetailView` makes its calls:
///
/// - an autosave records `textPatch` BEFORE sending it (`save(_:)`);
/// - when a save lands, the sheet calls `DetailFieldEdits.landing` (supersede, confirm, adopt) —
///   the same function these tests call, so its order is pinned here;
/// - closing records `textPatch` (`handleDismiss` → `unconfirmedPatch`).
///
/// `LibraryDetailUITests` drives the same scenarios through the real sheet (slow and stalled links).
@MainActor
final class DetailFieldEditsTests: XCTestCase {
    private var directory: URL!
    private var userId: UUID!
    private var queue: PendingEdits!
    private let t0 = Date(timeIntervalSince1970: 1_790_000_000)
    private let objectName = "f200ad94-32d7-4b39-bcfc-313b5e0a9c41.m4a"

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DetailFieldEditsTests-\(UUID().uuidString)", isDirectory: true)
        userId = UUID()
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

    /// A text item with a real title, so only the field under test is in play.
    private func textRow(title: String = "Standup", description: String = "", note: String? = nil,
                         isPublic: Bool = false) -> Item {
        Item(id: UUID(), type: .text, title: title, content: "", url: nil, filePath: nil,
             description: description, summary: nil, pageBody: nil, supplementalNote: note, mimeType: nil,
             isPublic: isPublic, createdAt: t0, attributes: ItemAttributes())
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
        if let isPublic = patch.isPublic { next.isPublic = isPublic }
        return next
    }

    /// `save` came back as `response` in the open sheet: `DetailFieldEdits.landing`, exactly as
    /// `ItemDetailView.save(_:)` calls it (supersede, confirm, the list row, adopt), then the sheet
    /// adopts. (The list row's own order is pinned by `testAnUnshareLandingLeavesNoDroppedNoteOnTheListRow`.)
    private func land(_ save: Save, as response: Item, in sheet: inout Sheet, at time: TimeInterval) {
        sheet.local = DetailFieldEdits.landing(save.patch, capturedAt: save.capturedAt, as: response,
                                               local: sheet.local, baseline: ItemDisplay.editableRow(sheet.snapshot),
                                               queue: queue, sheetIsOpen: true, at: t0.addingTimeInterval(time),
                                               apply: { _ in })
        sheet.snapshot = response
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

    private func queuedDescription(_ sheet: Sheet) -> String? {
        queue.edit(for: sheet.local.id)?.fieldPatch.description
    }

    /// "" is a queued clear (`ItemPatch.restBody` sends it as null).
    private func queuedNote(_ sheet: Sheet) -> String? {
        queue.edit(for: sheet.local.id)?.fieldPatch.supplementalNote
    }

    /// Delivers the queue to `server` the way the close's (or the app's) flush does.
    private func deliverQueue(to server: FakeRowServer) async {
        await queue.flush(editor: ItemEditor(patcher: server,
                                             refresher: EmbeddingRefresher(syncer: RecordingSyncer(), idle: .milliseconds(10)),
                                             writeQueue: ItemWriteQueue()))
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

    // MARK: - The description and the sticky note (Task 4c, re-review §9)

    func testTheDescriptionAndStickyNoteSendOnlyWhatTheUserChanged() throws {
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

        // Task 4c: the description reads the queue too. The field back at the server's value while
        // the queue still holds another description is a revert that must supersede it — sent.
        var reverted = open(server)
        queue.record(itemId: server.id, patch: ItemPatch(description: "Queued description"), capturedAt: t0)
        reverted.local.description = "Server description"
        XCTAssertEqual(edits(reverted).textPatch, ItemPatch(description: "Server description"))
    }

    /// Re-review §9 scenario A, non-empty baseline: " x" is appended and sent, then deleted again —
    /// a revert to the server's own value — and the revert's autosave runs before " x" lands. The
    /// revert is sent (latest wins), the " x" response never refills the field, and the server ends
    /// with the original.
    func testADescriptionRevertedWhileItsEditIsInFlightSupersedesIt() throws {
        let server = textRow(description: "Meeting notes")
        var sheet = open(server)
        sheet.local.description = "Meeting notes x"
        let sendX = try XCTUnwrap(autosave(sheet, at: 1))
        XCTAssertEqual(sendX.patch, ItemPatch(description: "Meeting notes x"))

        sheet.local.description = "Meeting notes"
        let revert = autosave(sheet, at: 2)
        XCTAssertEqual(revert?.patch, ItemPatch(description: "Meeting notes"),
                       "The revert must be sent: \" x\" is still on its way to the server")
        XCTAssertEqual(queuedDescription(sheet), "Meeting notes", "The revert replaces \" x\" in the queue (latest wins)")

        let xRow = applying(sendX.patch, to: server)
        land(sendX, as: xRow, in: &sheet, at: 3)
        XCTAssertEqual(sheet.local.description, "Meeting notes", "The \" x\" response must not refill the reverted field")
        XCTAssertEqual(queuedDescription(sheet), "Meeting notes", "The revert is still queued after \" x\" is confirmed")

        let revertSave = try XCTUnwrap(revert)
        land(revertSave, as: applying(revertSave.patch, to: xRow), in: &sheet, at: 4)
        XCTAssertEqual(sheet.local.description, "Meeting notes")
        XCTAssertEqual(sheet.snapshot.description, "Meeting notes", "The server ends with the original")
        XCTAssertNil(queue.edit(for: server.id))
        XCTAssertTrue(edits(sheet).textPatch.isEmpty)
    }

    /// A′: the revert is typed and " x" lands before the revert's autosave has run. The landing
    /// queues the revert before it confirms " x", so the field stays reverted and it still goes out.
    func testADescriptionRevertedJustBeforeItsSentEditLandsIsQueuedBeforeTheConfirm() throws {
        let server = textRow(description: "Meeting notes")
        var sheet = open(server)
        sheet.local.description = "Meeting notes x"
        let sendX = try XCTUnwrap(autosave(sheet, at: 1))

        sheet.local.description = "Meeting notes"   // its autosave is still in the debounce
        XCTAssertEqual(edits(sheet).superseding(sendX.patch), ItemPatch(description: "Meeting notes"),
                       "\" x\" landed after the user reverted it: the revert is the newest word")
        let xRow = applying(sendX.patch, to: server)
        land(sendX, as: xRow, in: &sheet, at: 2)
        XCTAssertEqual(sheet.local.description, "Meeting notes", "The \" x\" response must not refill the reverted field")
        XCTAssertEqual(queuedDescription(sheet), "Meeting notes", "The revert is queued (a close now would send it)")

        let revert = try XCTUnwrap(autosave(sheet, at: 3))
        XCTAssertEqual(revert.patch, ItemPatch(description: "Meeting notes"), "The debounced autosave then sends it")
        land(revert, as: applying(revert.patch, to: xRow), in: &sheet, at: 4)
        XCTAssertEqual(sheet.snapshot.description, "Meeting notes", "The server ends with the original")
        XCTAssertNil(queue.edit(for: server.id))
    }

    /// B: " x" failed to send (offline) and stays queued; the user reverts and closes. The queue
    /// delivers the revert, never " x"; the list and a reopened sheet show the original.
    func testADescriptionRevertedAfterAFailedSendIsWhatTheQueueDelivers() async throws {
        let server = textRow(description: "Meeting notes")
        var sheet = open(server)
        sheet.local.description = "Meeting notes x"
        _ = try XCTUnwrap(autosave(sheet, at: 1))   // the PATCH fails: never confirmed

        sheet.local.description = "Meeting notes"
        XCTAssertEqual(autosave(sheet, at: 2)?.patch, ItemPatch(description: "Meeting notes"),
                       "The revert must be sent over the queued \" x\"")   // fails too: queued
        dismiss(sheet, at: 3)
        XCTAssertEqual(queuedDescription(sheet), "Meeting notes", "A flush sends the revert")
        XCTAssertEqual(queue.overlay(server).description, "Meeting notes", "The list shows the original")
        XCTAssertEqual(open(server).local.description, "Meeting notes", "Reopening shows the revert, not \" x\"")

        let online = FakeRowServer(rows: [server])
        await deliverQueue(to: online)
        XCTAssertEqual(online.patches.map(\.1), [ItemPatch(description: "Meeting notes")], "Never \" x\"")
        XCTAssertEqual(online.row(server.id)?.description, "Meeting notes")
        XCTAssertNil(queue.edit(for: server.id))
    }

    /// C: the user reverts and closes at once while " x" is in flight — the close's journal (not an
    /// autosave) supersedes " x", and the flush after it puts the original back on the server.
    func testADescriptionRevertedThenAnInstantCloseWhileItsEditIsInFlight() async throws {
        let server = textRow(description: "Meeting notes")
        var sheet = open(server)
        sheet.local.description = "Meeting notes x"
        let sendX = try XCTUnwrap(autosave(sheet, at: 1))

        sheet.local.description = "Meeting notes"
        dismiss(sheet, at: 2)   // closed inside the revert's debounce
        XCTAssertEqual(queuedDescription(sheet), "Meeting notes", "The close must queue the revert over the in-flight \" x\"")

        // " x" lands after the close (the sheet is gone: only its confirm runs).
        let online = FakeRowServer(rows: [applying(sendX.patch, to: server)])
        queue.confirm(itemId: server.id, patch: sendX.patch, capturedAt: sendX.capturedAt)
        XCTAssertEqual(queuedDescription(sheet), "Meeting notes", "Confirming \" x\" leaves the newer revert queued")
        await deliverQueue(to: online)
        XCTAssertEqual(online.row(server.id)?.description, "Meeting notes", "The server ends with the original")
        XCTAssertNil(queue.edit(for: server.id))
    }

    /// Empty baseline, A: a description typed and sent, then cleared while it's in flight.
    func testADescriptionClearedWhileItsTextIsInFlightSupersedesIt() throws {
        let server = textRow(description: "")
        var sheet = open(server)
        sheet.local.description = "Idea"
        let sendIdea = try XCTUnwrap(autosave(sheet, at: 1))

        sheet.local.description = ""
        let clear = try XCTUnwrap(autosave(sheet, at: 2))
        XCTAssertEqual(clear.patch, ItemPatch(description: ""), "The clear must be sent: \"Idea\" is still on its way")

        let ideaRow = applying(sendIdea.patch, to: server)
        land(sendIdea, as: ideaRow, in: &sheet, at: 3)
        XCTAssertEqual(sheet.local.description, "", "The \"Idea\" response must not refill the cleared field")
        land(clear, as: applying(clear.patch, to: ideaRow), in: &sheet, at: 4)
        XCTAssertEqual(sheet.snapshot.description, "", "The server ends empty")
        XCTAssertNil(queue.edit(for: server.id))
    }

    /// Empty baseline, C: cleared, then closed at once while the text is in flight.
    func testADescriptionClearedThenAnInstantCloseWhileItsTextIsInFlight() async throws {
        let server = textRow(description: "")
        var sheet = open(server)
        sheet.local.description = "Idea"
        let sendIdea = try XCTUnwrap(autosave(sheet, at: 1))

        sheet.local.description = ""
        dismiss(sheet, at: 2)
        XCTAssertEqual(queuedDescription(sheet), "", "The close must queue the clear over the in-flight \"Idea\"")
        let online = FakeRowServer(rows: [applying(sendIdea.patch, to: server)])
        queue.confirm(itemId: server.id, patch: sendIdea.patch, capturedAt: sendIdea.capturedAt)
        await deliverQueue(to: online)
        XCTAssertEqual(online.row(server.id)?.description, "", "The server ends empty")
    }

    /// Enrichment (or a transcription) writing the description while the sheet is open: an untouched
    /// field takes it; while a revert of the user's is still queued, the field keeps the revert (and
    /// still sends it); once the revert has landed, the next one is taken again.
    func testAServerDescriptionIsTakenUnlessARevertIsStillQueued() throws {
        let server = textRow(description: "Meeting notes")
        var untouched = open(server)
        adopt(applying(ItemPatch(description: "Enrichment's description"), to: server), in: &untouched)
        XCTAssertEqual(untouched.local.description, "Enrichment's description", "An untouched field takes it")

        var sheet = open(server)
        sheet.local.description = "Meeting notes x"
        let sendX = try XCTUnwrap(autosave(sheet, at: 1))
        sheet.local.description = "Meeting notes"
        let revert = try XCTUnwrap(autosave(sheet, at: 2))
        adopt(applying(ItemPatch(description: "Enrichment's description"), to: server), in: &sheet)
        XCTAssertEqual(sheet.local.description, "Meeting notes", "The queued revert is kept")
        XCTAssertEqual(edits(sheet).textPatch.description, "Meeting notes", "…and still sent")

        let xRow = applying(sendX.patch, to: sheet.snapshot)
        land(sendX, as: xRow, in: &sheet, at: 3)
        land(revert, as: applying(revert.patch, to: xRow), in: &sheet, at: 4)
        XCTAssertNil(queue.edit(for: server.id))
        adopt(applying(ItemPatch(description: "A later enrichment"), to: sheet.snapshot), in: &sheet)
        XCTAssertEqual(sheet.local.description, "A later enrichment", "Once the revert landed, the server's is taken again")
    }

    /// The sticky note, A: a public item whose server note is nil; a note is typed and sent, then
    /// cleared while it is in flight. The clear is sent ("" — null on the wire), the note's response
    /// never refills the field, and the server ends with no note.
    func testAStickyNoteClearedWhileItsTextIsInFlightSupersedesIt() throws {
        let server = textRow(isPublic: true)
        var sheet = open(server)
        sheet.local.supplementalNote = "For you"
        let sendNote = try XCTUnwrap(autosave(sheet, at: 1))
        XCTAssertEqual(sendNote.patch, ItemPatch(supplementalNote: "For you"))

        sheet.local.supplementalNote = ""   // what the field's binding writes once the text is deleted
        XCTAssertEqual(edits(sheet).textPatch.supplementalNote, "", "The clear must be sent: the note is still on its way")
        let clear = try XCTUnwrap(autosave(sheet, at: 2))
        XCTAssertNil(queue.overlay(server).supplementalNote, "The list shows no note")

        let noteRow = applying(sendNote.patch, to: server)
        land(sendNote, as: noteRow, in: &sheet, at: 3)
        XCTAssertEqual(sheet.local.supplementalNote ?? "", "", "The note's response must not refill the cleared field")
        land(clear, as: applying(clear.patch, to: noteRow), in: &sheet, at: 4)
        XCTAssertNil(sheet.snapshot.supplementalNote, "The server ends with no note")
        XCTAssertNil(queue.edit(for: server.id))
        XCTAssertEqual(open(sheet.snapshot).local.supplementalNote ?? "", "", "Reopened: no note")
    }

    /// The sticky note, B: the note failed to send (offline); the user clears it and closes. The
    /// queue delivers the clear, never the note; the list and a reopened sheet show no note.
    func testAStickyNoteClearedAfterAFailedSendIsWhatTheQueueDelivers() async throws {
        let server = textRow(isPublic: true)
        var sheet = open(server)
        sheet.local.supplementalNote = "For you"
        _ = try XCTUnwrap(autosave(sheet, at: 1))   // fails: queued

        sheet.local.supplementalNote = ""
        XCTAssertEqual(edits(sheet).textPatch.supplementalNote, "", "The clear must be sent over the queued note")
        _ = try XCTUnwrap(autosave(sheet, at: 2))   // fails too: queued
        dismiss(sheet, at: 3)
        XCTAssertEqual(queuedNote(sheet), "", "A flush sends the clear")
        XCTAssertNil(queue.overlay(server).supplementalNote, "The list shows no note")
        XCTAssertEqual(open(server).local.supplementalNote ?? "", "", "Reopening shows no note, not \"For you\"")

        let online = FakeRowServer(rows: [server])
        await deliverQueue(to: online)
        XCTAssertEqual(online.patches.map(\.1), [ItemPatch(supplementalNote: "")], "Only the clear goes out — never the note")
        XCTAssertNil(online.row(server.id)?.supplementalNote)
    }

    /// The sticky note, C: cleared, then closed at once while the note is in flight.
    func testAStickyNoteClearedThenAnInstantCloseWhileItsTextIsInFlight() async throws {
        let server = textRow(isPublic: true)
        var sheet = open(server)
        sheet.local.supplementalNote = "For you"
        let sendNote = try XCTUnwrap(autosave(sheet, at: 1))

        sheet.local.supplementalNote = ""
        dismiss(sheet, at: 2)
        XCTAssertEqual(queuedNote(sheet), "", "The close must queue the clear over the in-flight note")
        XCTAssertNil(queue.overlay(server).supplementalNote, "The list shows no note")

        let online = FakeRowServer(rows: [applying(sendNote.patch, to: server)])
        queue.confirm(itemId: server.id, patch: sendNote.patch, capturedAt: sendNote.capturedAt)
        XCTAssertEqual(queuedNote(sheet), "", "Confirming the note leaves the newer clear queued")
        await deliverQueue(to: online)
        XCTAssertNil(online.row(server.id)?.supplementalNote, "The server ends with no note")
        XCTAssertEqual(open(server).local.supplementalNote ?? "", "", "Reopened: no note")
    }

    /// Making a public item private clears its sticky note in the same PATCH (`togglePublic`). A
    /// note still queued when that succeeds is gone for good: the confirm drops it (it was captured
    /// before the un-share) and nothing sends it again.
    func testASuccessfulUnshareDropsAQueuedNoteForGood() throws {
        let server = textRow(isPublic: true)
        var sheet = open(server)
        sheet.local.supplementalNote = "For you"
        _ = try XCTUnwrap(autosave(sheet, at: 1))   // fails: queued, undelivered

        let unshare = ItemPatch(supplementalNote: "", isPublic: false)
        sheet.local.isPublic = false
        sheet.local.supplementalNote = nil   // optimistic, as `setPublic` does
        queue.confirm(itemId: server.id, patch: unshare, capturedAt: t0.addingTimeInterval(2))
        adopt(applying(unshare, to: server), in: &sheet)
        XCTAssertNil(queuedNote(sheet), "The un-share confirmed the note's removal")
        XCTAssertNil(edits(sheet).textPatch.supplementalNote, "Nothing sends the note again")
        XCTAssertNil(sheet.local.supplementalNote)
        XCTAssertNil(queue.overlay(sheet.snapshot).supplementalNote)
    }

    /// Review m-1: the list row is laid AFTER the landing's confirm. A successful un-share removes
    /// the sticky note in the same PATCH, so its confirm drops a note still queued from before it.
    /// Laid before that, the row kept showing the dropped note: the store re-lays a row only from
    /// what is still queued, so the note stayed on the row (and a sheet reopened on it) until the
    /// next refresh.
    func testAnUnshareLandingLeavesNoDroppedNoteOnTheListRow() async throws {
        let server = textRow(isPublic: true)
        let store = ItemStore(userId: UUID(), fetcher: FakeItemsServer(rows: [server], pageSize: 50), pageSize: 50)
        store.installPendingEdits(queue) { _ in }
        await store.refresh()
        var sheet = open(server)
        sheet.local.supplementalNote = "For you"
        _ = try XCTUnwrap(autosave(sheet, at: 1))   // fails: queued, undelivered
        XCTAssertEqual(store.item(withId: server.id)?.supplementalNote, "For you", "The list shows the queued note")

        let unshare = ItemPatch(supplementalNote: "", isPublic: false)
        sheet.local.isPublic = false
        sheet.local.supplementalNote = nil   // optimistic, as `setPublic` does
        let saved = applying(unshare, to: server)
        sheet.local = DetailFieldEdits.landing(unshare, capturedAt: t0.addingTimeInterval(2), as: saved,
                                               local: sheet.local, baseline: ItemDisplay.editableRow(sheet.snapshot),
                                               queue: queue, sheetIsOpen: true, at: t0.addingTimeInterval(3),
                                               apply: store.applyDetail)
        XCTAssertNil(queuedNote(sheet), "The un-share confirmed the note's removal")
        XCTAssertNil(store.item(withId: server.id)?.supplementalNote, "The list row shows no note")
        XCTAssertEqual(store.item(withId: server.id)?.isPublic, false)
        XCTAssertNil(sheet.local.supplementalNote)
    }

    /// An un-share that FAILS must change nothing. Its optimistic clear of the field would otherwise
    /// read as the user clearing a queued, undelivered note — now that the field reads the queue,
    /// that is a clear the next autosave or the close would send. The note goes back in the field
    /// (`DetailFieldEdits.undoingFailedUnshare`), and the sheet sends exactly what it would have.
    func testAFailedUnshareRestoresAQueuedNote() throws {
        let server = textRow(isPublic: true)
        var sheet = open(server)
        sheet.local.supplementalNote = "For you"
        _ = try XCTUnwrap(autosave(sheet, at: 1))   // fails: queued, undelivered
        let sendsBefore = edits(sheet).textPatch
        let queuedBefore = queue.edit(for: server.id)

        let noteBefore = sheet.local.supplementalNote
        sheet.local.isPublic = false
        sheet.local.supplementalNote = nil   // optimistic
        XCTAssertEqual(edits(sheet).textPatch.supplementalNote, "",
                       "Left like this, the empty field is a clear of the queued note")

        sheet.local.isPublic = true   // the un-share failed: `setPublic` flips the switch back
        sheet.local = DetailFieldEdits.undoingFailedUnshare(noteBefore: noteBefore, local: sheet.local,
                                                            baseline: ItemDisplay.editableRow(sheet.snapshot),
                                                            queue: queue, sheetIsOpen: true, at: t0.addingTimeInterval(3))
        XCTAssertEqual(sheet.local.supplementalNote, "For you", "The queued note is back in the field")
        XCTAssertEqual(edits(sheet).textPatch, sendsBefore, "The sheet sends what it would have before — never a clear")
        XCTAssertEqual(queue.edit(for: server.id), queuedBefore, "The queue is exactly as it was")
    }

    /// A save of the note that lands while the un-share is in flight queues the field's value — the
    /// optimistic clear (the landing's supersede step). If the un-share then fails, the note goes
    /// back in the queue as well as the field, so that clear is never sent.
    func testAFailedUnshareRequeuesANoteWhoseSaveLandedDuringIt() throws {
        let server = textRow(isPublic: true)
        var sheet = open(server)
        sheet.local.supplementalNote = "For you"
        let sendNote = try XCTUnwrap(autosave(sheet, at: 1))   // in flight

        let noteBefore = sheet.local.supplementalNote
        sheet.local.isPublic = false
        sheet.local.supplementalNote = nil   // the un-share goes out behind the note's save
        land(sendNote, as: applying(sendNote.patch, to: server), in: &sheet, at: 2)
        XCTAssertEqual(queuedNote(sheet), "", "The note's landing queued the optimistic clear")

        sheet.local.isPublic = true   // the un-share failed
        sheet.local = DetailFieldEdits.undoingFailedUnshare(noteBefore: noteBefore, local: sheet.local,
                                                            baseline: ItemDisplay.editableRow(sheet.snapshot),
                                                            queue: queue, sheetIsOpen: true, at: t0.addingTimeInterval(3))
        XCTAssertEqual(sheet.local.supplementalNote, "For you", "The note (now on the server) is back in the field")
        XCTAssertEqual(queuedNote(sheet), "For you", "…and in the queue: nothing ever sends that clear")
        XCTAssertEqual(queue.overlay(sheet.snapshot).supplementalNote, "For you", "The list shows the note")
    }

    /// Review F1: the un-share's PATCH outlives the sheet (`SharingSection` runs it in its own
    /// task). Closed while it was in flight, the sheet journaled the toggle the user last saw —
    /// private, the note removed, as they confirmed ("The sticky note will be removed"). When the
    /// un-share then fails, the closed sheet must not put the note back over that clear: the
    /// journal owns what the user last saw, and the close's flush delivers it (plan 15). Re-queuing
    /// the note there made the item private WITH the note — published again on a later re-share.
    func testAFailedUnshareInAClosedSheetLeavesTheJournaledUnshareQueued() async throws {
        let server = textRow(note: "On the server", isPublic: true)
        var sheet = open(server)
        let noteBefore = sheet.local.supplementalNote
        sheet.local.isPublic = false
        sheet.local.supplementalNote = nil                                  // optimistic
        var journal = edits(sheet).textPatch
        journal.isPublic = false                                            // the close journals the Sharing flip
        queue.record(itemId: server.id, patch: journal, capturedAt: t0.addingTimeInterval(1))
        let queuedBefore = queue.edit(for: server.id)
        sheet.local.isPublic = true                                         // the un-share failed
        _ = DetailFieldEdits.undoingFailedUnshare(noteBefore: noteBefore, local: sheet.local,
                                                  baseline: ItemDisplay.editableRow(sheet.snapshot),
                                                  queue: queue, sheetIsOpen: false, at: t0.addingTimeInterval(2))
        XCTAssertEqual(queue.edit(for: server.id), queuedBefore, "the journaled un-share stands")
        let online = FakeRowServer(rows: [server])
        await deliverQueue(to: online)
        XCTAssertEqual(online.row(server.id)?.isPublic, false)
        XCTAssertNil(online.row(server.id)?.supplementalNote, "the note the user agreed to remove is gone")
    }

    /// The same for a note the server already holds (the pre-plan-16 case), and nothing put back
    /// when the note before the un-share is neither the server's nor a queued one.
    func testAFailedUnshareRestoresOnlyANoteTheServerOrTheQueueStillHolds() {
        let server = textRow(note: "On the server", isPublic: true)
        var sheet = open(server)
        sheet.local.isPublic = false
        sheet.local.supplementalNote = nil
        XCTAssertEqual(edits(sheet).noteAfterFailedUnshare(noteBefore: "On the server"), "On the server")
        XCTAssertNil(edits(sheet).noteAfterFailedUnshare(noteBefore: "Neither"),
                     "A note that is neither the server's nor queued isn't put back")
        XCTAssertNil(edits(sheet).noteAfterFailedUnshare(noteBefore: nil), "No note: nothing to put back")

        sheet.local.supplementalNote = "Typed since"
        XCTAssertNil(edits(sheet).noteAfterFailedUnshare(noteBefore: "On the server"),
                     "A field that isn't empty any more is left as it is")
    }

    // MARK: - A failed Sharing toggle (review P-4)

    /// What the sheet's journal records (`ItemDetailView.unconfirmedPatch`: the text fields and the
    /// Sharing value) when the app leaves the foreground (`closing: false`) or the sheet closes.
    private func journal(_ sheet: Sheet, closing: Bool, at time: TimeInterval) {
        var patch = edits(sheet).textPatch
        patch.isPublic = edits(sheet).journaledSharing(closing: closing)
        guard !patch.isEmpty else { return }
        queue.record(itemId: sheet.local.id, patch: patch, capturedAt: t0.addingTimeInterval(time))
    }

    /// `setPublic`'s failure, as the sheet handles it: the fields to show — and whether the toggle
    /// took effect after all (the server already holds it), so the section shows no error.
    /// `knownDeliveries`: the queue's `deliveryCount` when the sheet last read the server's row.
    private func failToggle(to target: Bool, noteBefore: String?, knownDeliveries: Int? = nil,
                            in sheet: inout Sheet, sheetIsOpen: Bool = true, at time: TimeInterval) -> Bool {
        sheet.local = DetailFieldEdits.undoingFailedToggle(to: target, noteBefore: noteBefore, knownDeliveries: knownDeliveries,
                                                           local: sheet.local,
                                                           baseline: ItemDisplay.editableRow(sheet.snapshot),
                                                           queue: queue, sheetIsOpen: sheetIsOpen,
                                                           at: t0.addingTimeInterval(time))
        return sheet.local.isPublic == target
    }

    /// P-4's way in: the app leaves the foreground (app switcher, Control Center, a notification)
    /// while a share is in flight. The journal that runs then must not queue the share — if its
    /// PATCH fails, the switch flips back in front of the user, and a queued copy would publish the
    /// item later anyway. Closing the sheet still queues it (the user never sees a failure then:
    /// plan 15 retries what they last saw), and an un-share is always queued: it fails safe.
    func testTheBackgroundJournalNeverQueuesAShareStillInFlight() {
        var sharing = open(textRow())
        sharing.local.isPublic = true   // optimistic: the share is in flight
        XCTAssertNil(edits(sharing).journaledSharing(closing: false), "Leaving the foreground: not queued")
        XCTAssertEqual(edits(sharing).journaledSharing(closing: true), true, "Closing: queued (plan 15)")

        var unsharing = open(textRow(note: "For you", isPublic: true))
        unsharing.local.isPublic = false
        unsharing.local.supplementalNote = nil
        XCTAssertEqual(edits(unsharing).journaledSharing(closing: false), false, "An un-share is queued either way")
        XCTAssertEqual(edits(unsharing).journaledSharing(closing: true), false)

        XCTAssertNil(edits(open(textRow())).journaledSharing(closing: true), "Untouched: nothing")
    }

    /// P-4: a share fails while the user watches — the switch flips back and the section says
    /// "Couldn't update". A Sharing value queued during the flight (by the old journal, say) must
    /// never go out: delivered by the next flush, it published the item.
    func testAFailedShareIsNeverPublishedLater() async {
        let server = textRow()
        var sheet = open(server)
        sheet.local.isPublic = true   // optimistic
        queue.record(itemId: server.id, patch: ItemPatch(isPublic: true), capturedAt: t0.addingTimeInterval(1))

        let tookEffect = failToggle(to: true, noteBefore: nil, in: &sheet, at: 2)
        XCTAssertFalse(tookEffect, "The share failed: the section says so")
        XCTAssertFalse(sheet.local.isPublic, "The switch is back off")
        XCTAssertNotEqual(queue.edit(for: server.id)?.isPublic?.value, true,
                          "The queued share is taken back (private is queued instead — Task 4e)")
        let online = FakeRowServer(rows: [server])
        await deliverQueue(to: online)
        XCTAssertEqual(online.row(server.id)?.isPublic, false, "Never published")
        journal(sheet, closing: true, at: 3)
        XCTAssertNil(queue.edit(for: server.id), "Closing afterwards queues nothing either")
    }

    /// The reverse: an un-share fails while the user watches — the switch flips back on and the
    /// sticky note comes back. The un-share the background journal queued during the flight
    /// (private, the note removed) must not go out either: the item stays public with its note,
    /// exactly as the sheet shows it.
    func testAFailedUnshareKeepsTheItemPublicWithItsNoteAsTheSheetShows() async {
        let server = textRow(note: "For you", isPublic: true)
        var sheet = open(server)
        let noteBefore = sheet.local.supplementalNote
        sheet.local.isPublic = false
        sheet.local.supplementalNote = nil   // optimistic
        journal(sheet, closing: false, at: 1)   // the app left the foreground mid-flight
        XCTAssertEqual(queue.edit(for: server.id)?.fieldPatch, ItemPatch(supplementalNote: "", isPublic: false))

        let tookEffect = failToggle(to: false, noteBefore: noteBefore, in: &sheet, at: 2)
        XCTAssertFalse(tookEffect)
        XCTAssertTrue(sheet.local.isPublic, "The switch is back on")
        XCTAssertEqual(sheet.local.supplementalNote, "For you", "The note is back")
        XCTAssertNil(queue.edit(for: server.id)?.isPublic, "The queued un-share is taken back")
        let online = FakeRowServer(rows: [server])
        await deliverQueue(to: online)
        XCTAssertEqual(online.row(server.id)?.isPublic, true, "The server ends as the sheet shows: public")
        XCTAssertEqual(online.row(server.id)?.supplementalNote, "For you", "…with its note")
    }

    /// A flush ahead of the toggle's own PATCH (a refresh, waiting behind an earlier write) already
    /// delivered the un-share the background journal queued, and the sheet took that row. The
    /// toggle's own PATCH then fails — but the server holds what the user asked for: the switch
    /// stays off, there's no error, and nothing queued now or journaled on close makes the item
    /// public again (flipping the switch back on did: the close then queued a share).
    func testAnUnshareTheServerAlreadyHoldsStaysPrivateWhenItsOwnPatchFails() async throws {
        let server = textRow(note: "For you", isPublic: true)
        var sheet = open(server)
        let noteBefore = sheet.local.supplementalNote
        sheet.local.isPublic = false
        sheet.local.supplementalNote = nil
        journal(sheet, closing: false, at: 1)
        let online = FakeRowServer(rows: [server])
        await deliverQueue(to: online)                             // the flush ahead of it
        adopt(try XCTUnwrap(online.row(server.id)), in: &sheet)    // the store's row reaches the sheet
        XCTAssertEqual(sheet.snapshot.isPublic, false)

        let tookEffect = failToggle(to: false, noteBefore: noteBefore, in: &sheet, at: 2)
        XCTAssertTrue(tookEffect, "The server already holds it: no error")
        XCTAssertFalse(sheet.local.isPublic, "The switch stays off")
        XCTAssertNil(sheet.local.supplementalNote, "The removed note stays removed")
        journal(sheet, closing: true, at: 3)
        await deliverQueue(to: online)
        XCTAssertEqual(online.row(server.id)?.isPublic, false, "Never made public again")
        XCTAssertNil(online.row(server.id)?.supplementalNote)
    }

    /// Closed while the share was in flight, the user last saw it on — never the failure. The
    /// close queued the share (plan 15), and a failure arriving after the sheet has gone leaves
    /// that alone: it is retried.
    func testAFailedShareInAClosedSheetLeavesTheClosesJournalToRetryIt() async {
        let server = textRow()
        var sheet = open(server)
        sheet.local.isPublic = true
        journal(sheet, closing: true, at: 1)
        let queuedBefore = queue.edit(for: server.id)

        _ = failToggle(to: true, noteBefore: nil, in: &sheet, sheetIsOpen: false, at: 2)
        XCTAssertEqual(queue.edit(for: server.id), queuedBefore, "The close's journal stands")
        let online = FakeRowServer(rows: [server])
        await deliverQueue(to: online)
        XCTAssertEqual(online.row(server.id)?.isPublic, true, "What the user last saw is delivered")
    }

    /// Opened on a share still queued from earlier (the switch on, the server private), the user
    /// turns it off, and that PATCH fails. The server holds private — what they asked for — so the
    /// switch stays off and private is queued over the queued share (Task 4e): nothing publishes it
    /// later. A sticky note typed meanwhile (queued too) never lands either, as the un-share
    /// promised.
    func testTurningAQueuedShareOffSticksWithoutTheNetwork() async {
        let server = textRow()
        queue.record(itemId: server.id, patch: ItemPatch(isPublic: true), capturedAt: t0)   // an undelivered share
        var sheet = open(server)
        XCTAssertTrue(sheet.local.isPublic, "The sheet opens on the queued share")
        sheet.local.supplementalNote = "For you"
        _ = autosave(sheet, at: 1)   // offline: queued too
        let noteBefore = sheet.local.supplementalNote
        sheet.local.isPublic = false
        sheet.local.supplementalNote = nil   // the un-share removes it

        let tookEffect = failToggle(to: false, noteBefore: noteBefore, in: &sheet, at: 2)
        XCTAssertTrue(tookEffect, "The server already holds private")
        XCTAssertFalse(sheet.local.isPublic)
        let online = FakeRowServer(rows: [server])
        await deliverQueue(to: online)
        XCTAssertEqual(online.row(server.id)?.isPublic, false, "Never published")
        XCTAssertNil(online.row(server.id)?.supplementalNote, "The note the un-share removed never lands")
    }

    // MARK: - Turning a queued share back off (4d review A-1)

    /// 4d review A-1, on a stalled link. Sheet 1: Sharing on, closed while that PATCH hangs — the
    /// close queues the share (plan 15). Sheet 2, opened at once, shows the queued share (on) while
    /// the server is still private; the user turns it off and closes while that PATCH hangs too.
    /// Both PATCHes fail after their sheets closed. The user last saw it off, so it must never be
    /// published — but off equals the server's value, so the close journaled nothing, and the next
    /// flush delivered the queued share.
    func testAShareTurnedOffInAReopenedSheetAndClosedOnAStalledLinkIsNeverPublished() async {
        let server = textRow()
        var first = open(server)
        first.local.isPublic = true
        journal(first, closing: true, at: 1)
        _ = failToggle(to: true, noteBefore: nil, in: &first, sheetIsOpen: false, at: 2)
        XCTAssertEqual(queue.edit(for: server.id)?.isPublic?.value, true, "The first close queued the share")

        var second = open(server)
        XCTAssertTrue(second.local.isPublic, "The reopened sheet shows the queued share")
        second.local.isPublic = false
        journal(second, closing: true, at: 3)
        XCTAssertEqual(queue.edit(for: server.id)?.isPublic?.value, false, "The close queues what the switch shows: off")
        _ = failToggle(to: false, noteBefore: nil, in: &second, sheetIsOpen: false, at: 4)

        let online = FakeRowServer(rows: [server])
        await deliverQueue(to: online)
        XCTAssertEqual(online.row(server.id)?.isPublic, false, "The user last saw it off: never published")
    }

    /// A-1, the kill route: a sheet opens on a queued share (on), the user turns it off, and the app
    /// leaves the foreground — its journal (`closing: false`) — and is killed while that PATCH is in
    /// flight, so its failure never runs. The relaunch's flush delivers whatever is queued.
    func testAQueuedShareTurnedOffThenKilledInTheBackgroundIsNeverPublished() async {
        let server = textRow()
        queue.record(itemId: server.id, patch: ItemPatch(isPublic: true), capturedAt: t0)   // an undelivered share
        var sheet = open(server)
        XCTAssertTrue(sheet.local.isPublic, "The sheet opens on the queued share")
        sheet.local.isPublic = false
        journal(sheet, closing: false, at: 1)

        // Killed: no failure, no close. The relaunch's flush:
        let relaunched = PendingEdits(userId: userId, directory: directory, session: FakeSession(signedIn: userId))
        let online = FakeRowServer(rows: [server])
        await relaunched.flush(editor: ItemEditor(patcher: online,
                                                  refresher: EmbeddingRefresher(syncer: RecordingSyncer(), idle: .milliseconds(10)),
                                                  writeQueue: ItemWriteQueue()))
        XCTAssertEqual(online.row(server.id)?.isPublic, false, "The user's last action was off")
    }

    // MARK: - A toggle that fails and settles off queues private again (4d review A-3, B-2)

    /// 4d review A-3, an Ask citation sheet — its own store holds no rows, so a flush's row never
    /// reaches it. A share is queued, undelivered; the citation sheet opens on it (on), and the user
    /// turns it off. A flush already ahead of that PATCH delivers the queued share: the server is
    /// public. Then the off PATCH fails. The sheet's last server row says private, so the switch
    /// stays off with no error — and with nothing queued saying private, the item stayed public.
    func testACitationSheetsFailedUnshareOverADeliveredShareEndsPrivate() async {
        let server = textRow()
        queue.record(itemId: server.id, patch: ItemPatch(isPublic: true), capturedAt: t0)
        var citation = open(server)
        XCTAssertTrue(citation.local.isPublic, "The citation sheet shows the queued share")
        citation.local.isPublic = false

        let online = FakeRowServer(rows: [server])
        await deliverQueue(to: online)
        XCTAssertEqual(online.row(server.id)?.isPublic, true, "A flush ahead of the un-share delivered the share")

        let tookEffect = failToggle(to: false, noteBefore: nil, in: &citation, at: 1)
        XCTAssertTrue(tookEffect, "The sheet's last server row is private: no error")
        XCTAssertFalse(citation.local.isPublic, "The switch stays off")
        XCTAssertEqual(queue.edit(for: server.id)?.isPublic?.value, false, "Private is queued again")
        journal(citation, closing: true, at: 2)
        await deliverQueue(to: online)
        XCTAssertEqual(online.row(server.id)?.isPublic, false, "The server ends as the sheet shows it: private")
    }

    /// 4d review B-2: a share the server APPLIED, whose response was lost (it timed out). As far as
    /// the sheet knows the share failed — the switch goes back off and the section says so — but the
    /// item is public. Taking back a queued share can't help: none is queued.
    func testAShareTheServerAppliedButWhoseResponseWasLostEndsPrivate() async {
        let server = textRow()
        var sheet = open(server)
        sheet.local.isPublic = true
        let online = FakeRowServer(rows: [server])
        online.update(server.id) { $0.isPublic = true }   // the share reached the server; its response didn't

        let tookEffect = failToggle(to: true, noteBefore: nil, in: &sheet, at: 1)
        XCTAssertFalse(tookEffect, "The share failed as far as the sheet knows: the section says so")
        XCTAssertFalse(sheet.local.isPublic, "The switch is back off")
        journal(sheet, closing: true, at: 2)
        await deliverQueue(to: online)
        XCTAssertEqual(online.row(server.id)?.isPublic, false, "The server ends as the sheet shows it: private")
    }

    /// A guard for A-3's fix: a LIBRARY sheet in the same sequence — its store hands it the flushed
    /// row before the un-share fails — shows the failure with the switch on, as the server is, and
    /// nothing queued changes that.
    func testALibrarySheetsFailedUnshareOverADeliveredShareShowsTheServersPublicRow() async throws {
        let server = textRow()
        queue.record(itemId: server.id, patch: ItemPatch(isPublic: true), capturedAt: t0)
        var sheet = open(server)
        sheet.local.isPublic = false
        let online = FakeRowServer(rows: [server])
        await deliverQueue(to: online)
        adopt(try XCTUnwrap(online.row(server.id)), in: &sheet)   // the store's `onChange`

        let tookEffect = failToggle(to: false, noteBefore: nil, in: &sheet, at: 1)
        XCTAssertFalse(tookEffect, "The un-share failed: the section says so")
        XCTAssertTrue(sheet.local.isPublic, "The switch shows what the server holds: on")
        journal(sheet, closing: true, at: 2)
        await deliverQueue(to: online)
        XCTAssertEqual(online.row(server.id)?.isPublic, true)
    }

    /// 4e review M-4, A-3's mirror: an un-share is queued, undelivered, and the item is opened from an
    /// Ask citation on its public row — the switch shows off. The user turns it on; a flush ahead of
    /// that PATCH delivers the queued un-share (the server is private), and the share fails. The
    /// sheet's last server row said public, so the switch stayed on with no error, and closing
    /// journaled nothing: the share was lost without a word. A failed share settles on what the
    /// server actually holds — here the un-share that flush delivered — and says it failed.
    func testACitationSheetsFailedShareOverADeliveredUnshareSaysSoAndShowsPrivate() async {
        let server = textRow(isPublic: true)
        queue.record(itemId: server.id, patch: ItemPatch(isPublic: false), capturedAt: t0)   // an undelivered un-share
        var citation = open(server)
        let readAt = queue.deliveryCount                                 // the sheet's last server row is read here
        XCTAssertFalse(citation.local.isPublic, "precondition: the citation sheet shows the queued un-share")
        citation.local.isPublic = true                                   // the share, optimistic
        let online = FakeRowServer(rows: [server])
        await deliverQueue(to: online)                                   // a flush ahead of the share
        XCTAssertEqual(online.row(server.id)?.isPublic, false, "precondition: the flush delivered the un-share")

        let tookEffect = failToggle(to: true, noteBefore: nil, knownDeliveries: readAt, in: &citation, at: 1)
        XCTAssertFalse(tookEffect, "The share failed: the section says so")
        XCTAssertFalse(citation.local.isPublic, "The switch shows what the server holds: private")
        journal(citation, closing: true, at: 2)
        await deliverQueue(to: online)
        XCTAssertEqual(online.row(server.id)?.isPublic, false, "A failed share is never published")
    }

    /// 4e re-review M-4b: the same, but the queued un-share was delivered BEFORE the user turned the
    /// switch on — the app's flush while the citation sheet was open, a row its store never sees —
    /// so nothing was queued as the toggle started, and the round-1 rule (which looked for a value
    /// queued then) didn't apply: the switch stayed on with no error over a private item. The rule
    /// is ordering-free: a failed share settles on what the server holds as far as the app knows —
    /// the sheet's last server row, or a Sharing value the queue delivered after that row was read.
    func testACitationSheetsFailedShareAfterTheUnshareWasDeliveredSaysSoAndShowsPrivate() async {
        let server = textRow(isPublic: true)
        queue.record(itemId: server.id, patch: ItemPatch(isPublic: false), capturedAt: t0)   // an undelivered un-share
        var citation = open(server)
        let readAt = queue.deliveryCount
        XCTAssertFalse(citation.local.isPublic, "precondition: the citation sheet shows the queued un-share")
        let online = FakeRowServer(rows: [server])
        await deliverQueue(to: online)                                   // the app's flush, the sheet still open
        XCTAssertEqual(online.row(server.id)?.isPublic, false, "precondition: the server is private")
        citation.local.isPublic = true                                   // only now the share, optimistic

        let tookEffect = failToggle(to: true, noteBefore: nil, knownDeliveries: readAt, in: &citation, at: 1)
        XCTAssertFalse(tookEffect, "The share failed: the section says so")
        XCTAssertFalse(citation.local.isPublic, "The switch shows what the server holds: private")
        journal(citation, closing: true, at: 2)
        await deliverQueue(to: online)
        XCTAssertEqual(online.row(server.id)?.isPublic, false, "A failed share is never published")
    }

    /// The un-share mirror in an Ask citation sheet: the app leaves the foreground with an un-share
    /// in flight (its journal queues it) and the app's flush delivers it — the server is private —
    /// in a row the citation store never hands the sheet. The un-share's own PATCH then fails. The
    /// server holds what the user asked for: the switch stays off, with no error, and the removed
    /// note stays removed. It went back on, note and all, with an error, over a private item.
    func testACitationSheetsUnshareTheAppDeliveredStaysOffWhenItsOwnPatchFails() async {
        let server = textRow(note: "For you", isPublic: true)
        var citation = open(server)
        let readAt = queue.deliveryCount
        let noteBefore = citation.local.supplementalNote
        citation.local.isPublic = false
        citation.local.supplementalNote = nil                            // optimistic
        journal(citation, closing: false, at: 1)                         // the app left the foreground mid-flight
        let online = FakeRowServer(rows: [server])
        await deliverQueue(to: online)                                   // the app's flush delivers the un-share

        let tookEffect = failToggle(to: false, noteBefore: noteBefore, knownDeliveries: readAt, in: &citation, at: 2)
        XCTAssertTrue(tookEffect, "The server holds what the user asked for: no error")
        XCTAssertFalse(citation.local.isPublic, "The switch stays off")
        XCTAssertNil(citation.local.supplementalNote, "The removed note stays removed")
        journal(citation, closing: true, at: 3)
        await deliverQueue(to: online)
        XCTAssertEqual(online.row(server.id)?.isPublic, false)
        XCTAssertNil(online.row(server.id)?.supplementalNote)
    }

    /// A guard for the rule above: the queued un-share was never delivered — the server is still
    /// public — when the user turned the switch back on and that share failed. The server holds what
    /// they asked for: the switch stays on with no error, and the queued un-share is taken back.
    func testAFailedShareOverAnUnshareThatWasNeverDeliveredStaysOn() async {
        let server = textRow(isPublic: true)
        queue.record(itemId: server.id, patch: ItemPatch(isPublic: false), capturedAt: t0)
        var citation = open(server)
        let readAt = queue.deliveryCount
        citation.local.isPublic = true

        let tookEffect = failToggle(to: true, noteBefore: nil, knownDeliveries: readAt, in: &citation, at: 1)
        XCTAssertTrue(tookEffect, "The server is public, as the user asked: no error")
        XCTAssertTrue(citation.local.isPublic)
        XCTAssertNil(queue.edit(for: server.id)?.isPublic, "The queued un-share is taken back")
        let online = FakeRowServer(rows: [server])
        await deliverQueue(to: online)
        XCTAssertEqual(online.row(server.id)?.isPublic, true)
    }

    /// `setPublic`'s success while a newer save has started, as the sheet takes it: the toggle's PATCH
    /// through the queue's write slot and into its delivered ledger (`PendingEdits.sendToggle`, batch B
    /// fix round 2), its landing, and then the carry (`carryingToggle`) instead of an adopt. The sheet's
    /// reference stays where the last row it read put it: the ledger shows the toggle as delivered after it.
    private func landToggleUnderANewerSave(_ patch: ItemPatch, in sheet: inout Sheet, editor: ItemEditor) async throws {
        let capturedAt = queue.captureTime()
        let saved = try await queue.sendToggle(patch, capturedAt: capturedAt, itemId: sheet.local.id, editor: editor)
        _ = DetailFieldEdits.landing(patch, capturedAt: capturedAt, as: saved, local: sheet.local,
                                     baseline: ItemDisplay.editableRow(sheet.snapshot), queue: queue,
                                     sheetIsOpen: true, at: queue.captureTime(), apply: { _ in })
        sheet.snapshot = DetailFieldEdits.carryingToggle(patch, snapshot: sheet.snapshot)
    }

    /// 4e re-review 2, New Breakage 2: an un-share lands while a newer save (the title's autosave) is in
    /// flight, so the sheet doesn't adopt its row; that autosave then fails, and no row is adopted at all.
    /// Then the user turns the switch back on, and that share fails. The sheet's last server row still
    /// said public: the switch stayed on with no error over a private item, the share lost without a
    /// word. Two things now tell the sheet what the toggle put on the server: the carry (its last server
    /// row takes the toggle's fields) and the delivered ledger (the toggle goes through it, fix round 2).
    func testAnUnshareThatLandedUnderANewerSaveIsWhatAFailedShareSettlesOn() async throws {
        let server = textRow(isPublic: true)
        var sheet = open(server)
        let known = queue.deliveryCount                                  // the row the sheet opened on was read here
        let online = FakeRowServer(rows: [server])
        sheet.local.isPublic = false                                     // the un-share, optimistic
        try await landToggleUnderANewerSave(ItemPatch(isPublic: false), in: &sheet, editor: onlineEditor(online))
        XCTAssertEqual(online.row(server.id)?.isPublic, false, "precondition: the un-share landed")

        sheet.local.isPublic = true                                      // the share; its PATCH fails
        let tookEffect = failToggle(to: true, noteBefore: nil, knownDeliveries: known, in: &sheet, at: 1)
        XCTAssertFalse(tookEffect, "The share failed: the section says so")
        XCTAssertFalse(sheet.local.isPublic, "The switch shows what the server holds: private")
        journal(sheet, closing: true, at: 2)
        await deliverQueue(to: online)
        XCTAssertEqual(online.row(server.id)?.isPublic, false, "A failed share is never published")
    }

    /// The ledger half: an Ask citation sheet opens on a queued share (the server private), and the app's
    /// flush delivers that share in a row the sheet never sees. The user turns the switch off; that
    /// un-share lands under a newer save. Then a share fails. Measured from the reference the sheet opened
    /// with, the delivered share counted as what the server holds, though the un-share landed after it:
    /// the switch stayed on with no error over a private item. The un-share goes through the delivered
    /// ledger now (fix round 2), as the newer of the two. (Round 2 of 4e moved the reference past every
    /// delivery here instead, which also hid a delivery of any other field: re-review N-1.)
    func testAnUnshareThatLandedUnderANewerSaveOutranksAShareDeliveredBeforeIt() async throws {
        let server = textRow()
        queue.record(itemId: server.id, patch: ItemPatch(isPublic: true), capturedAt: queue.captureTime())   // queued earlier
        var citation = open(server)
        let knownAtOpen = queue.deliveryCount
        XCTAssertTrue(citation.local.isPublic, "precondition: the sheet opens on the queued share")
        let online = FakeRowServer(rows: [server])
        await deliverQueue(to: online)                                   // the app's flush; no row reaches the sheet
        XCTAssertEqual(online.row(server.id)?.isPublic, true, "precondition: the share is on the server")

        citation.local.isPublic = false                                  // the un-share, optimistic
        try await landToggleUnderANewerSave(ItemPatch(isPublic: false), in: &citation, editor: onlineEditor(online))
        XCTAssertEqual(online.row(server.id)?.isPublic, false, "precondition: the un-share landed")

        citation.local.isPublic = true                                   // the share; its PATCH fails
        let tookEffect = failToggle(to: true, noteBefore: nil, knownDeliveries: knownAtOpen, in: &citation, at: 1)
        XCTAssertFalse(tookEffect, "The share failed: the section says so")
        XCTAssertFalse(citation.local.isPublic, "The switch shows what the server holds: private")
        journal(citation, closing: true, at: 2)
        await deliverQueue(to: online)
        XCTAssertEqual(online.row(server.id)?.isPublic, false, "A failed share is never published")
    }

    /// The carry half (fix round 2): a share lands while a newer save is in flight, so the sheet doesn't
    /// adopt its row. The user turns the switch off, and that un-share fails. The server is public, as the
    /// carried row says: the switch goes back on with the error. Without the carry the row still said
    /// private, and a share the queue delivered never turns a failed un-share back on (the A-3
    /// fail-safe): the switch settled off with no error over a public item.
    func testAShareThatLandedUnderANewerSaveIsWhatAFailedUnshareGoesBackTo() async throws {
        let server = textRow()
        var sheet = open(server)
        let known = queue.deliveryCount
        let online = FakeRowServer(rows: [server])
        sheet.local.isPublic = true                                      // the share, optimistic
        try await landToggleUnderANewerSave(ItemPatch(isPublic: true), in: &sheet, editor: onlineEditor(online))
        XCTAssertEqual(online.row(server.id)?.isPublic, true, "precondition: the share landed")

        sheet.local.isPublic = false                                     // the un-share; its PATCH fails
        let tookEffect = failToggle(to: false, noteBefore: nil, knownDeliveries: known, in: &sheet, at: 1)
        XCTAssertFalse(tookEffect, "The un-share failed: the section says so")
        XCTAssertTrue(sheet.local.isPublic, "The switch shows what the server holds: public")
        XCTAssertNil(queue.edit(for: server.id)?.isPublic, "Nothing queued changes the item's visibility")
    }

    /// 4e re-review, M-2's side effect: in an Ask citation sheet "Y"'s autosave failed, so "Y" stays
    /// queued. A share fails, and the flush `setPublic` then starts delivers "Y" along with the
    /// private — in a row the citation store never hands the sheet. The user types "X" (the server's
    /// old value) back: measured against a last server row that still said "X", it was never sent,
    /// and the server kept "Y". The sheet adopts the row its own flush delivered, as a library
    /// sheet's store hands it every flushed row.
    func testACitationSheetAdoptsTheRowItsOwnFlushDeliveredSoALaterRevertIsSent() async throws {
        let server = textRow(title: "X")
        var citation = open(server)
        citation.local.title = "Y"
        queue.record(itemId: server.id, patch: edits(citation).textPatch, capturedAt: queue.captureTime())   // its PATCH failed
        citation.local.isPublic = true
        _ = failToggle(to: true, noteBefore: nil, in: &citation, at: 1)
        XCTAssertFalse(citation.local.isPublic, "precondition: settled off, private queued again")

        let online = FakeRowServer(rows: [server])
        await deliverQueue(to: online)                                   // `setPublic`'s flush delivers "Y" too
        adopt(try XCTUnwrap(online.row(server.id)), in: &citation)       // …and its row reaches the sheet
        citation.local.title = "X"                                       // typed back
        XCTAssertEqual(edits(citation).textPatch, ItemPatch(title: "X"), "The user's last typed value is sent")
        journal(citation, closing: true, at: 3)
        await deliverQueue(to: online)
        XCTAssertEqual(online.row(server.id)?.title, "X", "The server ends with it")
    }

    /// Supersede only what moved on: a save that sent the title and the description, where only the
    /// description changed since, re-queues just the description.
    func testSupersedingReturnsOnlyTheFieldsThatMovedOn() throws {
        let server = textRow(description: "Meeting notes")
        var sheet = open(server)
        sheet.local.title = "Standup notes"
        sheet.local.description = "Meeting notes x"
        let save = try XCTUnwrap(autosave(sheet, at: 1))
        XCTAssertEqual(save.patch, ItemPatch(title: "Standup notes", description: "Meeting notes x"))

        sheet.local.description = "Meeting notes"
        XCTAssertEqual(edits(sheet).superseding(save.patch), ItemPatch(description: "Meeting notes"))
        sheet.local.supplementalNote = "For you"   // a field the save never sent isn't superseded
        XCTAssertEqual(edits(sheet).superseding(save.patch), ItemPatch(description: "Meeting notes"))
    }

    // MARK: - The landing sequence is StashKit's (re-review m-3)

    /// `ItemDetailView.save` hands every landed save to `DetailFieldEdits.landing`, so this fails if
    /// its supersede step goes: "Gro" lands after the user cleared the field inside the next
    /// debounce — the clear is queued before "Gro" is confirmed, and the adopted fields keep it.
    func testALandingQueuesWhatTheFieldMovedOnToBeforeItConfirms() throws {
        let server = audioRow(title: objectName)
        var sheet = open(server)
        sheet.local.title = "Gro"
        let sendGro = try XCTUnwrap(autosave(sheet, at: 1))
        sheet.local.title = ""   // its autosave is still in the debounce

        let adopted = DetailFieldEdits.landing(sendGro.patch, capturedAt: sendGro.capturedAt,
                                               as: applying(sendGro.patch, to: server), local: sheet.local,
                                               baseline: ItemDisplay.editableRow(sheet.snapshot), queue: queue,
                                               sheetIsOpen: true, at: t0.addingTimeInterval(2), apply: { _ in })
        XCTAssertEqual(adopted.title, "", "The adopted fields keep the clear")
        XCTAssertEqual(queuedTitle(sheet), "", "The clear was queued before \"Gro\" was confirmed")
    }

    /// Once the sheet has closed, its journal has already queued what the fields held, and a landing
    /// must not queue them again: they may be older than an edit made since in a newly opened sheet.
    func testALandingInAClosedSheetNeverQueuesItsFields() throws {
        let server = audioRow(title: objectName)
        let sheet = open(server)
        var typed = sheet
        typed.local.title = "Gro"
        let sendGro = try XCTUnwrap(autosave(typed, at: 1))
        typed.local.title = ""
        dismiss(typed, at: 2)   // the journal queues the clear

        var reopened = open(server)
        reopened.local.title = "Groceries"
        _ = try XCTUnwrap(autosave(reopened, at: 3))   // a newer edit, in a new sheet

        _ = DetailFieldEdits.landing(sendGro.patch, capturedAt: sendGro.capturedAt,
                                     as: applying(sendGro.patch, to: server), local: typed.local,
                                     baseline: ItemDisplay.editableRow(typed.snapshot), queue: queue,
                                     sheetIsOpen: false, at: t0.addingTimeInterval(4), apply: { _ in })
        XCTAssertEqual(queuedTitle(reopened), "Groceries", "The closed sheet's old fields never replace the newer edit")
    }

    // MARK: - A save a write ahead of it already delivered (4d review A-2, B-1, P-1)

    /// Lets every task already queued on the main actor run until it next waits — e.g. a flush
    /// started in a `Task` reaching its place in the item's write queue.
    private func settle() async {
        for _ in 0..<50 { await Task.yield() }
    }

    private func waitUntil(_ condition: () -> Bool, timeout: TimeInterval = 2) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline { try? await Task.sleep(for: .milliseconds(5)) }
    }

    /// A slow link: `server` holds every PATCH until released. `sheets` sends the sheet's saves and
    /// `flushes` the queue's flushes — one write queue, as in the app.
    private func slowLink(_ rows: [Item]) -> (server: FakeRowServer, sheets: ItemEditor, flushes: ItemEditor) {
        let server = FakeRowServer(rows: rows)
        server.gated = true
        let writeQueue = ItemWriteQueue()
        let refresher = { EmbeddingRefresher(syncer: RecordingSyncer(), idle: .milliseconds(10)) }
        return (server, ItemEditor(patcher: server, refresher: refresher(), writeQueue: writeQueue),
                ItemEditor(patcher: server, refresher: refresher(), writeQueue: writeQueue))
    }

    /// A rich note's paragraphs, in order — the text of each TipTap paragraph.
    private func paragraphs(_ content: String?) -> [String] {
        guard let data = content?.data(using: .utf8),
              let document = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let blocks = document["content"] as? [[String: Any]]
        else { return [] }
        return blocks.map { block in
            ((block["content"] as? [[String: Any]]) ?? []).compactMap { $0["text"] as? String }.joined()
        }
    }

    /// A rich note "first", on a slow link. Sheet 1 closes while a slow title save is in flight; its
    /// close's flush waits behind it. Reopened at once, "abc" is added and Done tapped: the note's
    /// save records the document (`flushNotes`) and waits behind that flush — which, at its turn,
    /// delivers the document itself. Returns the reopened sheet, the note save's result and capture.
    private func richNoteDeliveredByTheFlushAhead() async throws
        -> (row: Item, server: FakeRowServer, sheets: ItemEditor, sheet: Sheet, sent: SheetSave, capturedAt: Date) {
        var row = textRow()
        row.content = appendNoteParagraph(to: "{\"type\":\"doc\",\"content\":[]}", note: "first")
        let (server, sheets, flushes) = slowLink([row])
        let t = queue.captureTime()
        queue.record(itemId: row.id, patch: ItemPatch(title: "T"), capturedAt: t)
        let slow = Task { try await self.queue.send(ItemPatch(title: "T"), capturedAt: t, itemId: row.id, editor: sheets) }
        await waitUntil { server.heldCount == 1 }
        let close = Task { await self.queue.flush(editor: flushes, itemIds: [row.id]) }
        await settle()

        let sheet = open(row)
        let document = appendNoteParagraph(to: sheet.local.content, note: "abc")
        let c = queue.captureTime()
        queue.record(itemId: row.id, patch: ItemPatch(content: document), capturedAt: c)
        let noteSave = Task { try await self.queue.send(ItemPatch(content: document), capturedAt: c, itemId: row.id, editor: sheets) }
        await settle()

        server.gated = false
        server.release()
        _ = try await slow.value
        await close.value
        let sent = try await noteSave.value
        XCTAssertNil(sent.item, "precondition: the flush ahead delivered the document; the note's save had nothing left")
        XCTAssertEqual(paragraphs(server.row(row.id)?.content), ["first", "abc"], "precondition: the server has the note")
        return (row, server, sheets, sheet, sent, c)
    }

    /// The user adds `typed` to the notes box and taps Done: `flushNotes`' idempotence guard and
    /// append, saved through the queue.
    private func addNote(_ box: String, to sheet: Sheet, server: FakeRowServer, sheets: ItemEditor) async throws {
        let note = box.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !note.isEmpty, tipTapLastParagraphText(sheet.local.content) != note else { return }
        let next = appendNoteParagraph(to: sheet.local.content, note: note)
        let c = queue.captureTime()
        queue.record(itemId: sheet.local.id, patch: ItemPatch(content: next), capturedAt: c)
        _ = try await queue.send(ItemPatch(content: next), capturedAt: c, itemId: sheet.local.id, editor: sheets)
    }

    /// 4d review A-2 (probe R1), a library sheet: its store hands it the flush's row. The note's save
    /// had nothing left to send — and that is saved, not failed: the box must let go of "abc". Left
    /// in it, " def" added later went out as "abc def" after the "abc" paragraph — the note's text in
    /// the document twice, and a rich note can't be edited on iOS.
    func testARichNoteAFlushAheadAlreadyDeliveredLeavesTheBoxAndIsNeverAppendedTwice() async throws {
        let (row, server, sheets, start, sent, capturedAt) = try await richNoteDeliveredByTheFlushAhead()
        var sheet = start
        var box = "abc"
        adopt(try XCTUnwrap(server.row(row.id)), in: &sheet)   // the store's `onChange` hands the sheet the flush's row
        let landed = DetailFieldEdits.landing(sent, capturedAt: capturedAt, local: sheet.local, snapshot: sheet.snapshot,
                                              queue: queue, sheetIsOpen: true, at: queue.captureTime(), apply: { _ in })
        sheet.local = landed.fields
        sheet.snapshot = landed.row
        if DetailSaveOutcome(sent).isSaved { box = "" }        // `flushNotes`' bookkeeping (`removeSavedPrefix("abc")`)

        box += " def"
        try await addNote(box, to: sheet, server: server, sheets: sheets)
        XCTAssertEqual(paragraphs(server.row(row.id)?.content), ["first", "abc", "def"], "Each note once, in order")
    }

    /// The same in an Ask citation sheet, whose own store never hands it the flush's row: the save's
    /// landing is the only way the delivered document reaches the sheet. Without one the sheet kept
    /// the old document — "abc" missing on screen — and the next note, appended to that, replaced the
    /// server's document: "abc" was lost.
    func testARichNoteAFlushAheadAlreadyDeliveredIsInTheCitationSheetsDocument() async throws {
        let (row, server, sheets, start, sent, capturedAt) = try await richNoteDeliveredByTheFlushAhead()
        var sheet = start
        var box = "abc"
        let landed = DetailFieldEdits.landing(sent, capturedAt: capturedAt, local: sheet.local, snapshot: sheet.snapshot,
                                              queue: queue, sheetIsOpen: true, at: queue.captureTime(), apply: { _ in })
        sheet.local = landed.fields
        sheet.snapshot = landed.row
        XCTAssertEqual(paragraphs(sheet.local.content), ["first", "abc"], "The sheet shows the document the server got")
        if DetailSaveOutcome(sent).isSaved { box = "" }

        box += " def"
        try await addNote(box, to: sheet, server: server, sheets: sheets)
        XCTAssertEqual(paragraphs(server.row(row.id)?.content), ["first", "abc", "def"], "Nothing lost, nothing twice")
    }

    /// 4d review B-1, an Ask citation sheet (no store updates), server title "X". The user types "Y":
    /// its autosave queues behind a flush that waits on a slow write. They type "X" back. The flush
    /// delivers "Y", and the autosave has nothing left to send — so it had no landing, and the
    /// supersede step that queues a field the user moved on from never ran. The revert's own
    /// autosave then compared "X" with a last server row that still said "X", nothing queued: "X"
    /// was never sent, and the server kept "Y".
    func testACitationSheetsRevertIsSentWhenAFlushAheadDeliveredTheValueBeforeIt() async throws {
        let row = textRow(title: "X")
        let (server, sheets, flushes) = slowLink([row])
        var citation = open(row)
        let slowAt = queue.captureTime()
        queue.record(itemId: row.id, patch: ItemPatch(description: "slow"), capturedAt: slowAt)
        let slow = Task { try await self.queue.send(ItemPatch(description: "slow"), capturedAt: slowAt, itemId: row.id, editor: sheets) }
        await waitUntil { server.heldCount == 1 }
        let flush = Task { await self.queue.flush(editor: flushes, itemIds: [row.id]) }
        await settle()

        citation.local.title = "Y"
        let typedAt = queue.captureTime()
        let typed = edits(citation).textPatch
        queue.record(itemId: row.id, patch: typed, capturedAt: typedAt)
        let save = Task { try await self.queue.send(typed, capturedAt: typedAt, itemId: row.id, editor: sheets) }
        await settle()
        citation.local.title = "X"   // typed back; its autosave is still in the debounce

        server.gated = false
        server.release()
        _ = try await slow.value
        await flush.value
        let sent = try await save.value
        XCTAssertNil(sent.item, "precondition: the flush delivered \"Y\"; the autosave had nothing left")
        let landed = DetailFieldEdits.landing(sent, capturedAt: typedAt, local: citation.local, snapshot: citation.snapshot,
                                              queue: queue, sheetIsOpen: true, at: queue.captureTime(), apply: { _ in })
        citation.local = landed.fields
        citation.snapshot = landed.row
        XCTAssertEqual(citation.local.title, "X", "The field keeps the revert")

        let revert = edits(citation).textPatch   // the revert's autosave fires now
        XCTAssertEqual(revert, ItemPatch(title: "X"), "The revert's autosave sends it")
        if !revert.isEmpty {
            let revertAt = queue.captureTime()
            queue.record(itemId: row.id, patch: revert, capturedAt: revertAt)
            _ = try await queue.send(revert, capturedAt: revertAt, itemId: row.id, editor: sheets)
        }
        XCTAssertEqual(server.row(row.id)?.title, "X", "The user's last value reaches the server")
    }

    /// A guard (B-1's pre-4d control): the same sequence with a fixed-patch save (`ItemEditor.save`)
    /// — it lands "Y" after the flush, and its landing's supersede step queues "X": the revert's
    /// autosave sends it.
    func testACitationSheetsRevertIsSentWhenItsSaveLandsAfterTheFlushAhead() async throws {
        let row = textRow(title: "X")
        let (server, sheets, flushes) = slowLink([row])
        var citation = open(row)
        queue.record(itemId: row.id, patch: ItemPatch(description: "slow"), capturedAt: queue.captureTime())
        let slow = Task { try await sheets.save(itemId: row.id, patch: ItemPatch(description: "slow")) }
        await waitUntil { server.heldCount == 1 }
        let flush = Task { await self.queue.flush(editor: flushes, itemIds: [row.id]) }
        await settle()

        citation.local.title = "Y"
        let typedAt = queue.captureTime()
        let typed = edits(citation).textPatch
        queue.record(itemId: row.id, patch: typed, capturedAt: typedAt)
        let save = Task { try await sheets.save(itemId: row.id, patch: typed) }
        await settle()
        citation.local.title = "X"

        server.gated = false
        server.release()
        _ = try await slow.value
        await flush.value
        let result = try await save.value
        citation.local = DetailFieldEdits.landing(typed, capturedAt: typedAt, as: result, local: citation.local,
                                                  baseline: ItemDisplay.editableRow(citation.snapshot), queue: queue,
                                                  sheetIsOpen: true, at: queue.captureTime(), apply: { _ in })
        citation.snapshot = result
        let revert = edits(citation).textPatch
        XCTAssertEqual(revert, ItemPatch(title: "X"))
        _ = try await sheets.save(itemId: row.id, patch: revert)
        XCTAssertEqual(server.row(row.id)?.title, "X")
    }

    /// 4d review P-1 (pre-existing), a library sheet, server title "X". "Y" is typed and its autosave
    /// sent — recorded first, its PATCH waiting behind a slow write — and "X" typed back inside the
    /// next debounce. A flush ahead delivers "Y", and the store hands the sheet that row before the
    /// autosave's turn. Nothing is queued any more and the field equals the sheet's last server row,
    /// so `adopt` took "Y": the revert was gone from the field, and the debounce then sent nothing. A
    /// field one of the sheet's own saves is still sending stays as the user left it.
    func testAnOpenSheetsRevertSurvivesAFlushAheadDeliveringTheValueBeforeIt() async throws {
        let server = textRow(title: "X")
        var sheet = open(server)
        sheet.local.title = "Y"
        let typed = edits(sheet).textPatch
        queue.record(itemId: server.id, patch: typed, capturedAt: queue.captureTime())   // the autosave's write-ahead
        sheet.local.title = "X"                                                          // typed back, inside the debounce
        let online = FakeRowServer(rows: [server])
        await deliverQueue(to: online)                                                   // a flush ahead delivers "Y"

        let row = try XCTUnwrap(online.row(server.id))
        sheet.local = DetailFieldEdits(local: sheet.local, baseline: ItemDisplay.editableRow(sheet.snapshot),
                                       queued: queue.edit(for: server.id), sending: [typed])
            .adopting(row)                                                               // the store's `onChange` → `adopt`
        sheet.snapshot = row
        XCTAssertEqual(sheet.local.title, "X", "The user's last value stays in the field")
        XCTAssertEqual(edits(sheet).textPatch, ItemPatch(title: "X"), "…and the debounce sends it")
    }

    // MARK: - Every saved note reaches the sheet's document (4e review C-1)

    /// `ItemDetailView.save`'s tail in an Ask citation sheet, whose store holds no rows (no `onChange`
    /// adopt ever runs): the landing always runs; the newest save adopts its row and fields; an older
    /// one hands the sheet what it carried (`DetailFieldEdits.carrying`).
    private func landInCitationSheet(_ save: SheetSave, capturedAt: Date, isNewest: Bool, in sheet: inout Sheet) {
        let landed = DetailFieldEdits.landing(save, capturedAt: capturedAt, local: sheet.local, snapshot: sheet.snapshot,
                                              queue: queue, sheetIsOpen: true, at: queue.captureTime(), apply: { _ in })
        if isNewest {
            sheet.local = landed.fields
            sheet.snapshot = landed.row
        } else {
            (sheet.local, sheet.snapshot) = DetailFieldEdits.carrying(save, landed: landed, local: sheet.local,
                                                                       snapshot: sheet.snapshot)
        }
    }

    /// A rich note whose document is ["first"].
    private func richRow() -> Item {
        var row = textRow()
        row.content = appendNoteParagraph(to: "{\"type\":\"doc\",\"content\":[]}", note: "first")
        return row
    }

    /// 4e review C-1, its simplest form (probe B2; since 4d), in an Ask citation sheet on ["first"]:
    /// "abc" is added and Done tapped, and its save goes out slowly. The app comes back to the
    /// foreground, and its refresh flushes the queue behind the note's save. The user edits the
    /// title; that autosave records first and queues behind the flush — the newest save now. The
    /// note's save lands, but it isn't the newest, so the sheet never took its document; the flush
    /// delivers the title, and the title's save (nothing left to send) lands against the sheet's
    /// last server row: the old document. "abc" had left the box — it was saved — so "def" was
    /// appended to ["first"], and the server lost "abc".
    func testANoteSaveThatIsntTheNewestStillBringsItsDocumentToACitationSheet() async throws {
        let row = richRow()
        let (server, sheets, flushes) = slowLink([row])
        var citation = open(row)
        var box = "abc"
        let document = appendNoteParagraph(to: citation.local.content, note: "abc")
        let noteAt = queue.captureTime()
        queue.record(itemId: row.id, patch: ItemPatch(content: document), capturedAt: noteAt)
        let noteSave = Task { try await self.queue.send(ItemPatch(content: document), capturedAt: noteAt, itemId: row.id, editor: sheets) }
        await waitUntil { server.heldCount == 1 }
        let foregroundFlush = Task { await self.queue.flush(editor: flushes, itemIds: [row.id]) }
        await settle()
        citation.local.title = "Standup notes"                    // the newest save from here on
        let titlePatch = edits(citation).textPatch
        let titleAt = queue.captureTime()
        queue.record(itemId: row.id, patch: titlePatch, capturedAt: titleAt)
        let titleSave = Task { try await self.queue.send(titlePatch, capturedAt: titleAt, itemId: row.id, editor: sheets) }
        await settle()

        server.gated = false
        server.release()
        let noteSent = try await noteSave.value
        landInCitationSheet(noteSent, capturedAt: noteAt, isNewest: false, in: &citation)
        if DetailSaveOutcome(noteSent).isSaved { box = "" }      // `flushNotes`: `removeSavedPrefix("abc")`
        await foregroundFlush.value
        landInCitationSheet(try await titleSave.value, capturedAt: titleAt, isNewest: true, in: &citation)
        XCTAssertEqual(paragraphs(citation.local.content), ["first", "abc"], "The sheet shows the document the server holds")

        box += " def"
        try await addNote(box, to: citation, server: server, sheets: sheets)
        XCTAssertEqual(paragraphs(server.row(row.id)?.content), ["first", "abc", "def"], "The user's note is never lost")
    }

    /// C-1, variant A (new in 4e), in an Ask citation sheet: a location save hangs on the slow link,
    /// and the foreground flush queues behind it. "abc" is added (Done), then the title edited. The
    /// flush delivers both, so both saves come back with nothing left to send; only the title's is
    /// the newest, and it lands against the old document. (Before 4e, "abc" stayed in the box and
    /// went out merged as "abc def"; 4e's `isSaved` empties the box, so "abc" was lost.)
    func testANoteAFlushDeliveredBeforeALaterSaveStillBringsItsDocumentToACitationSheet() async throws {
        let row = richRow()
        let (server, sheets, flushes) = slowLink([row])
        var citation = open(row)
        citation.local.attributes.location = CapturedLocation(label: "Brooklyn", source: "manual")
        let slowPatch = ItemPatch(attributes: citation.local.attributes)
        let slowAt = queue.captureTime()
        queue.record(itemId: row.id, patch: slowPatch, capturedAt: slowAt)
        let location = citation.local.attributes.location
        let slow = Task { () throws -> SheetSave in   // `saveAttributes`: the save onto the server's attributes
            let saved = try await sheets.saveLocation(itemId: row.id, location: location)
            return SheetSave(item: saved, patch: slowPatch, serverHolds: slowPatch)
        }
        await waitUntil { server.heldCount == 1 }
        let foregroundFlush = Task { await self.queue.flush(editor: flushes, itemIds: [row.id]) }
        await settle()

        var box = "abc"
        let document = appendNoteParagraph(to: citation.local.content, note: "abc")
        let noteAt = queue.captureTime()
        queue.record(itemId: row.id, patch: ItemPatch(content: document), capturedAt: noteAt)
        let noteSave = Task { try await self.queue.send(ItemPatch(content: document), capturedAt: noteAt, itemId: row.id, editor: sheets) }
        await settle()
        citation.local.title = "Standup notes"                    // the newest save
        let titlePatch = edits(citation).textPatch
        let titleAt = queue.captureTime()
        queue.record(itemId: row.id, patch: titlePatch, capturedAt: titleAt)
        let titleSave = Task { try await self.queue.send(titlePatch, capturedAt: titleAt, itemId: row.id, editor: sheets) }
        await settle()

        server.gated = false
        server.release()
        landInCitationSheet(try await slow.value, capturedAt: slowAt, isNewest: false, in: &citation)
        await foregroundFlush.value
        let noteSent = try await noteSave.value
        XCTAssertNil(noteSent.item, "precondition: the flush delivered the note; its save had nothing left")
        landInCitationSheet(noteSent, capturedAt: noteAt, isNewest: false, in: &citation)
        if DetailSaveOutcome(noteSent).isSaved { box = "" }
        let titleSent = try await titleSave.value
        XCTAssertNil(titleSent.item, "precondition: the flush delivered the title too")
        landInCitationSheet(titleSent, capturedAt: titleAt, isNewest: true, in: &citation)
        XCTAssertEqual(paragraphs(citation.local.content), ["first", "abc"], "The sheet shows the document the server holds")

        box += " def"
        try await addNote(box, to: citation, server: server, sheets: sheets)
        XCTAssertEqual(paragraphs(server.row(row.id)?.content), ["first", "abc", "def"], "The user's note is never lost")
    }

    /// Found while fixing C-1 (pre-existing since the sheet opens on queued values, plan 15): a sheet
    /// opened on a queued, undelivered note document — a note closed offline — shows that document,
    /// which differs from the server's. A note added and saved there landed, but `adopting` kept the
    /// sheet's copy (it still differed from the last server row): the document on screen lacked the
    /// new note, and the next note, appended to that copy, replaced the server's document.
    func testANoteSavedInASheetOpenedOnAQueuedDocumentReachesThatSheet() async throws {
        let row = richRow()
        queue.record(itemId: row.id, patch: ItemPatch(content: appendNoteParagraph(to: row.content, note: "offline")),
                     capturedAt: queue.captureTime())                // closed offline: the note still queued
        let server = FakeRowServer(rows: [row])
        let editor = ItemEditor(patcher: server, refresher: EmbeddingRefresher(syncer: RecordingSyncer(), idle: .milliseconds(10)),
                                writeQueue: ItemWriteQueue())
        var sheet = open(row)
        XCTAssertEqual(paragraphs(sheet.local.content), ["first", "offline"], "precondition: the sheet shows the queued note")

        var box = "abc"
        let document = appendNoteParagraph(to: sheet.local.content, note: "abc")
        let at = queue.captureTime()
        queue.record(itemId: row.id, patch: ItemPatch(content: document), capturedAt: at)
        let sent = try await queue.send(ItemPatch(content: document), capturedAt: at, itemId: row.id, editor: editor)
        landInCitationSheet(sent, capturedAt: at, isNewest: true, in: &sheet)
        XCTAssertEqual(paragraphs(sheet.local.content), ["first", "offline", "abc"], "The sheet shows the document the server holds")
        if DetailSaveOutcome(sent).isSaved { box = "" }

        box += " def"
        try await addNote(box, to: sheet, server: server, sheets: editor)
        XCTAssertEqual(paragraphs(server.row(row.id)?.content), ["first", "offline", "abc", "def"], "Nothing lost")
    }

    // MARK: - Overlapping rich-note saves deliver each note once (4e re-review)

    /// 4e re-review (pre-existing, plan 15): two overlapping rich-note saves. Done with "abc" on a
    /// slow link; " def" typed; Done again while the first is on its way — that save carries "abc
    /// def" on the same base document. "abc" lands and leaves the box, "def" left; then "abc def"
    /// lands, but its removal — the whole "abc def" — no longer matched the box, so "def" stayed,
    /// and the next Done (or the close's journal) appended it a second time. A landing removes what
    /// of its text is still at the box's start, after what earlier landings took. Driven through
    /// the bookkeeping the sheet ships (`RichNoteBox.Ledger`; batch B fix round 1, review m-1).
    func testTwoOverlappingRichNoteSavesDeliverTheNotesTextOnce() async throws {
        let row = richRow()
        let (server, sheets, _) = slowLink([row])
        let n = RichNotes(open(row))
        n.box = "abc"
        let first = try XCTUnwrap(done(n, editor: sheets))
        await waitUntil { server.heldCount == 1 }
        n.box = "abc def"                                                // typed while "abc" is on its way
        let second = try XCTUnwrap(done(n, editor: sheets))
        await settle()

        server.gated = false
        server.release()
        await finish(first, isNewest: false, in: n)
        await finish(second, isNewest: true, in: n)
        XCTAssertEqual(n.box, "", "Every character the saves carried has left the box")

        await doneAndWait(n, editor: sheets)                             // the next Done: nothing to add
        XCTAssertEqual(paragraphs(server.row(row.id)?.content), ["first", "abc def"], "Each note once")
    }

    /// 4e re-review (C1q; pre-existing): a sheet opened on a queued, undelivered note ("offline"),
    /// then three overlapping note saves — "abc" (Done), "abc def" (typed, Done while "abc" is on
    /// its way), and, once "abc" has landed, the box's "def" (Done again). The landing of "abc"
    /// kept the sheet's document as it was — another note save was still queued — so the third save
    /// was built without "abc", and it landed last: "abc" was deleted from the server. A landed
    /// note document is the sheet's from then on, a queued one or not. Driven through the shipped
    /// bookkeeping, as above.
    func testOverlappingNoteSavesInASheetOpenedOnAQueuedDocumentNeverLoseANote() async throws {
        let row = richRow()
        queue.record(itemId: row.id, patch: ItemPatch(content: appendNoteParagraph(to: row.content, note: "offline")),
                     capturedAt: queue.captureTime())                    // closed offline: still queued
        let (server, sheets, _) = slowLink([row])
        let n = RichNotes(open(row))
        XCTAssertEqual(paragraphs(n.sheet.local.content), ["first", "offline"], "precondition: the queued note shows")
        n.box = "abc"
        let first = try XCTUnwrap(done(n, editor: sheets))
        await waitUntil { server.heldCount == 1 }
        n.box = "abc def"
        let second = try XCTUnwrap(done(n, editor: sheets))
        await settle()

        server.release()                                                 // "abc" lands; "abc def" is held next
        await finish(first, isNewest: false, in: n)
        XCTAssertEqual(paragraphs(n.sheet.local.content), ["first", "offline", "abc"], "The sheet shows the landed document")
        XCTAssertEqual(n.box, "def")
        let third = try XCTUnwrap(done(n, editor: sheets))               // Done a third time
        await waitUntil { server.heldCount == 1 }
        await settle()

        server.gated = false
        server.release()
        await finish(second, isNewest: false, in: n)
        await finish(third, isNewest: true, in: n)

        XCTAssertEqual(paragraphs(server.row(row.id)?.content), ["first", "offline", "abc", "def"], "No note lost, none twice")
        XCTAssertEqual(paragraphs(n.sheet.local.content), ["first", "offline", "abc", "def"], "The sheet shows it")
        XCTAssertEqual(n.box, "", "The box let go of everything saved")
    }

    // MARK: - A rich note's text leaves the box once the sheet shows it, in any order (batch B)

    /// One open sheet's rich-note state beside the queue: `ItemDetailView`'s notes box
    /// (`notesModel.draft`) and its ledger (`services.richNote`), written to from a flush's `apply`
    /// as the view's state is.
    @MainActor private final class RichNotes {
        var sheet: Sheet
        var box = ""
        var ledger = RichNoteBox.Ledger()
        init(_ sheet: Sheet) { self.sheet = sheet }
    }

    /// One note save `done` started: the box's text it took, the ledger's removals then, and the
    /// document it built and queued.
    private struct NoteSave {
        let typed: String
        let removedAt: String
        let document: String
        let capturedAt: Date
        let task: Task<SheetSave, Error>
    }

    private func onlineEditor(_ server: FakeRowServer) -> ItemEditor {
        ItemEditor(patcher: server, refresher: EmbeddingRefresher(syncer: RecordingSyncer(), idle: .milliseconds(10)),
                   writeQueue: ItemWriteQueue())
    }

    /// `flushNotes`, Done: nil when one of its guards returns; otherwise the box's text appended to the
    /// sheet's document as a new paragraph, recorded first (write-ahead), then sent.
    private func done(_ n: RichNotes, editor: ItemEditor) -> NoteSave? {
        let typed = n.box
        let note = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !note.isEmpty else { return nil }
        if tipTapLastParagraphText(n.sheet.local.content) == note {
            n.box = ""
            return nil
        }
        let document = appendNoteParagraph(to: n.sheet.local.content, note: note)
        let at = queue.captureTime()
        queue.record(itemId: n.sheet.local.id, patch: ItemPatch(content: document), capturedAt: at)
        let id = n.sheet.local.id
        let task = Task { try await self.queue.send(ItemPatch(content: document), capturedAt: at, itemId: id, editor: editor) }
        return NoteSave(typed: typed, removedAt: n.ledger.removed, document: document, capturedAt: at, task: task)
    }

    /// How that save ends in an Ask citation sheet (`save`, then `flushNotes`). Saved: its landing
    /// (`landInCitationSheet`), the box reconciled with the document the sheet now shows (`adopt`'s
    /// `reconcileNotesDraft`), then the save's own text taken. Failed: kept by the ledger, which also
    /// reconciles it with the document the sheet already shows. Returns whether it was saved.
    @discardableResult
    private func finish(_ save: NoteSave, isNewest: Bool, in n: RichNotes) async -> Bool {
        guard let sent = try? await save.task.value else {
            n.box = n.ledger.failed(save.typed, document: save.document, removedAt: save.removedAt,
                                    shown: n.sheet.local.content, box: n.box) ?? n.box
            return false
        }
        landInCitationSheet(sent, capturedAt: save.capturedAt, isNewest: isNewest, in: &n.sheet)
        n.box = n.ledger.reconcile(shown: n.sheet.local.content, box: n.box) ?? n.box
        n.box = n.ledger.saved(save.typed, removedAt: save.removedAt, box: n.box)
        return true
    }

    private func doneAndWait(_ n: RichNotes, editor: ItemEditor) async {
        guard let save = done(n, editor: editor) else { return }
        await finish(save, isNewest: true, in: n)
    }

    /// A server row reaching the open sheet (the store's `onChange` in a library sheet, or a row of
    /// the sheet's own flush), as `adopt` folds it in: the fields merged, then the box reconciled
    /// with the document the sheet now shows.
    private func adoptRow(_ row: Item, in n: RichNotes) {
        n.sheet.local = edits(n.sheet).adopting(row)
        n.sheet.snapshot = row
        n.box = n.ledger.reconcile(shown: n.sheet.local.content, box: n.box) ?? n.box
    }

    /// The app leaves the foreground with text in the box: the journal (`unconfirmedPatch`) queues it
    /// appended to the document the sheet shows, and the ledger keeps that draft.
    private func journalNote(_ n: RichNotes) {
        let note = n.box.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !note.isEmpty, tipTapLastParagraphText(n.sheet.local.content) != note else { return }
        let document = appendNoteParagraph(to: n.sheet.local.content, note: note)
        queue.record(itemId: n.sheet.local.id, patch: ItemPatch(content: document), capturedAt: queue.captureTime())
        n.ledger.journaled(n.box, document: document)
    }

    /// A share the user turns on fails too, and settles off: private is queued again (`setPublic`).
    private func failShare(in n: RichNotes, at time: TimeInterval) {
        n.sheet.local.isPublic = true
        _ = failToggle(to: true, noteBefore: nil, knownDeliveries: queue.deliveryCount, in: &n.sheet, at: time)
    }

    /// 4e re-review 2, New Breakage 1 (library sheets since fix round 1, Ask citation sheets since
    /// round 2): "abc" is added and Done tapped, and its save fails. The box keeps "abc", and its
    /// document stays queued. A share fails too, the flush `setPublic` then starts gets through and
    /// delivers that document, and the sheet adopts the row. Nothing knew the document held the box's
    /// text: "abc" stayed in the box, " def" was typed, and Done appended "abc def" after "abc".
    func testAFailedRichNoteThatTheSheetsOwnFlushDeliversIsNeverAppendedTwice() async throws {
        let row = richRow()
        let online = FakeRowServer(rows: [row])
        let editor = onlineEditor(online)
        let n = RichNotes(open(row))
        n.box = "abc"
        online.error = URLError(.notConnectedToInternet)
        let first = try XCTUnwrap(done(n, editor: editor))
        let saved = await finish(first, isNewest: true, in: n)
        XCTAssertFalse(saved, "precondition: the note's save failed")
        XCTAssertEqual(n.box, "abc", "precondition: the box keeps the note")

        failShare(in: n, at: 1)
        online.error = nil
        await queue.flush(editor: editor, itemIds: [row.id]) { incoming in self.adoptRow(incoming, in: n) }
        XCTAssertEqual(paragraphs(n.sheet.local.content), ["first", "abc"],
                       "precondition: the flush delivered the note, and the sheet shows it")
        XCTAssertEqual(n.box, "", "The note is in the document the sheet shows: it has left the box")

        n.box += " def"
        await doneAndWait(n, editor: editor)
        XCTAssertEqual(paragraphs(online.row(row.id)?.content), ["first", "abc", "def"], "Each note once")
        XCTAssertEqual(n.box, "")
    }

    /// The same through realtime, in a library sheet: the note's PATCH reaches the server but its
    /// response is lost, and the row's realtime echo reaches the sheet (the store's `onChange`)
    /// before the save reports its failure. The sheet shows ["first", "abc"] with "abc" still in the
    /// box, and no later row brings that document again.
    func testARichNoteWhoseEchoReachedTheSheetBeforeItsSaveFailedIsNeverAppendedTwice() async throws {
        let row = richRow()
        let online = FakeRowServer(rows: [row])
        let editor = onlineEditor(online)
        let n = RichNotes(open(row))
        n.box = "abc"
        let first = try XCTUnwrap(done(n, editor: editor))
        online.update(row.id) { $0.content = first.document }            // the PATCH lands; its response is lost
        online.error = URLError(.timedOut)
        adoptRow(try XCTUnwrap(online.row(row.id)), in: n)               // the realtime echo, through the store
        XCTAssertEqual(paragraphs(n.sheet.local.content), ["first", "abc"], "precondition: the sheet shows the echo")
        XCTAssertEqual(n.box, "abc", "precondition: the save hasn't reported yet")
        let saved = await finish(first, isNewest: true, in: n)
        XCTAssertFalse(saved, "precondition: as far as the sheet knows, the save failed")
        XCTAssertEqual(n.box, "", "The document the sheet shows holds the note: it leaves the box")

        online.error = nil
        n.box += " def"
        await doneAndWait(n, editor: editor)
        XCTAssertEqual(paragraphs(online.row(row.id)?.content), ["first", "abc", "def"], "Each note once")
    }

    /// Two failed note saves, "abc" and then "abc def" (more typed, Done again), before the sheet's
    /// own flush delivers the newer document: all of that text leaves the box once the sheet shows it.
    func testTwoFailedRichNoteSavesTheSheetsOwnFlushDeliversAreAppendedOnce() async throws {
        let row = richRow()
        let online = FakeRowServer(rows: [row])
        let editor = onlineEditor(online)
        let n = RichNotes(open(row))
        online.error = URLError(.notConnectedToInternet)
        n.box = "abc"
        await doneAndWait(n, editor: editor)
        n.box += " def"
        await doneAndWait(n, editor: editor)
        XCTAssertEqual(n.box, "abc def", "precondition: both saves failed; the box keeps the text")

        failShare(in: n, at: 1)
        online.error = nil
        await queue.flush(editor: editor, itemIds: [row.id]) { incoming in self.adoptRow(incoming, in: n) }
        XCTAssertEqual(paragraphs(n.sheet.local.content), ["first", "abc def"],
                       "precondition: the flush delivered the newer document")
        XCTAssertEqual(n.box, "", "The text the sheet shows has left the box")

        n.box += " ghi"
        await doneAndWait(n, editor: editor)
        XCTAssertEqual(paragraphs(online.row(row.id)?.content), ["first", "abc def", "ghi"], "Each note once")
    }

    /// "abc"'s save fails, and the sheet's own flush picks its document up on a slow link. While that
    /// is on its way the user types " def" and taps Done; that save waits behind the flush. The flush
    /// lands first: "abc" leaves the box at once (a Done then appends only "def"), and the later
    /// save's landing takes only what is left of its own text. Each note once, and the sheet shows
    /// what the server holds.
    func testAFailedRichNoteDeliveredWhileANewerNoteSaveWaitsBehindTheFlushLeavesTheBoxOnce() async throws {
        let row = richRow()
        let (server, sheets, flushes) = slowLink([row])
        server.gated = false
        server.error = URLError(.notConnectedToInternet)
        let n = RichNotes(open(row))
        n.box = "abc"
        await doneAndWait(n, editor: sheets)
        XCTAssertEqual(n.box, "abc", "precondition: the save failed")

        failShare(in: n, at: 1)
        server.error = nil
        server.gated = true
        let flush = Task {
            await self.queue.flush(editor: flushes, itemIds: [row.id]) { incoming in self.adoptRow(incoming, in: n) }
        }
        await waitUntil { server.heldCount == 1 }
        n.box += " def"
        let second = try XCTUnwrap(done(n, editor: sheets))              // waits behind the flush
        await settle()
        server.gated = false
        server.release()
        await flush.value
        XCTAssertEqual(n.box, "def", "The note the flush delivered left the box; what was typed since stays")

        await finish(second, isNewest: true, in: n)
        let serverDocument = paragraphs(server.row(row.id)?.content)
        XCTAssertEqual(serverDocument, ["first", "abc def"], "Each note once")
        XCTAssertEqual(paragraphs(n.sheet.local.content), serverDocument, "The sheet shows what the server holds")
        XCTAssertEqual(n.box, "")
    }

    /// The rule's other half: text leaves the box only once the document the sheet SHOWS holds it. A
    /// sheet opened on a queued, undelivered note ("offline", closed offline) keeps its own copy of
    /// the document over an incoming row (`adopting`). "abc"'s save fails, and the sheet's own flush
    /// delivers ["first", "offline", "abc"], yet the sheet still shows ["first", "offline"]. Taken
    /// off the box then, "abc" would be in neither place the next note is built from, and that note,
    /// appended to the sheet's copy, would replace the server's document.
    func testAFailedRichNoteStaysInTheBoxWhileTheSheetShowsItsOwnCopyOfTheDocument() async throws {
        let row = richRow()
        queue.record(itemId: row.id, patch: ItemPatch(content: appendNoteParagraph(to: row.content, note: "offline")),
                     capturedAt: queue.captureTime())                    // closed offline: still queued
        let online = FakeRowServer(rows: [row])
        let editor = onlineEditor(online)
        let n = RichNotes(open(row))
        XCTAssertEqual(paragraphs(n.sheet.local.content), ["first", "offline"], "precondition: the queued note shows")
        online.error = URLError(.notConnectedToInternet)
        n.box = "abc"
        await doneAndWait(n, editor: editor)
        failShare(in: n, at: 1)
        online.error = nil
        await queue.flush(editor: editor, itemIds: [row.id]) { incoming in self.adoptRow(incoming, in: n) }
        XCTAssertEqual(paragraphs(online.row(row.id)?.content), ["first", "offline", "abc"],
                       "precondition: the flush delivered it")
        XCTAssertEqual(paragraphs(n.sheet.local.content), ["first", "offline"], "precondition: the sheet keeps its own copy")
        XCTAssertEqual(n.box, "abc", "Not in the document the sheet shows: it stays in the box")

        n.box += " def"
        await doneAndWait(n, editor: editor)
        XCTAssertEqual(paragraphs(online.row(row.id)?.content), ["first", "offline", "abc def"], "Nothing lost, nothing twice")
    }

    /// The same rule for the journal's draft, which lost a note before (since plan 15, which opened
    /// sheets on queued values): a library sheet opened on a queued note, "abc" typed with no Done,
    /// and the app leaves the foreground, so the journal queues "abc" appended to the document the
    /// sheet shows. The refresh back in the foreground delivers it, and the store hands the sheet the
    /// row, over which the sheet keeps its own copy. "abc" left the box because the ROW's document
    /// held it, though the sheet's didn't; the next note, appended to the sheet's copy, then replaced
    /// the server's document, and "abc" was gone.
    func testAJournaledRichNoteStaysInTheBoxWhileTheSheetShowsItsOwnCopyOfTheDocument() async throws {
        let row = richRow()
        queue.record(itemId: row.id, patch: ItemPatch(content: appendNoteParagraph(to: row.content, note: "offline")),
                     capturedAt: queue.captureTime())
        let online = FakeRowServer(rows: [row])
        let editor = onlineEditor(online)
        let n = RichNotes(open(row))
        n.box = "abc"
        journalNote(n)
        await queue.flush(editor: editor, itemIds: [row.id]) { incoming in self.adoptRow(incoming, in: n) }
        XCTAssertEqual(paragraphs(online.row(row.id)?.content), ["first", "offline", "abc"],
                       "precondition: the refresh delivered it")
        XCTAssertEqual(paragraphs(n.sheet.local.content), ["first", "offline"], "precondition: the sheet keeps its own copy")
        XCTAssertEqual(n.box, "abc", "Not in the document the sheet shows: it stays in the box")

        n.box += " def"
        await doneAndWait(n, editor: editor)
        XCTAssertEqual(paragraphs(online.row(row.id)?.content), ["first", "offline", "abc def"], "The note is never lost")
    }

    /// Every journaled draft is kept until the sheet shows it, not only the newest (pre-existing since
    /// plan 15): "abc" in the box, the app leaves the foreground (journaled); back, the refresh's
    /// flush picks it up on a slow link; " def" is typed and the app leaves again ("abc def"
    /// journaled). The flush delivers "abc" and the sheet shows it, then the link drops. With only
    /// the newest draft kept, "abc" stayed in the box, and Done appended "abc def" after it.
    func testAnEarlierJournaledRichNoteDeliveredAfterALaterOneWasQueuedLeavesTheBox() async throws {
        let row = richRow()
        let (server, sheets, flushes) = slowLink([row])
        let n = RichNotes(open(row))
        n.box = "abc"
        journalNote(n)
        let flush = Task {
            await self.queue.flush(editor: flushes, itemIds: [row.id]) { incoming in
                self.adoptRow(incoming, in: n)
                server.error = URLError(.notConnectedToInternet)          // the link drops after this row
            }
        }
        await waitUntil { server.heldCount == 1 }
        n.box += " def"
        journalNote(n)                                                   // the app leaves the foreground again
        server.gated = false
        server.release()
        await flush.value
        XCTAssertEqual(paragraphs(n.sheet.local.content), ["first", "abc"], "precondition: the sheet shows the first draft")
        XCTAssertEqual(n.box, "def", "The note the sheet shows left the box; what was typed since stays")

        server.error = nil
        await doneAndWait(n, editor: sheets)
        XCTAssertEqual(paragraphs(server.row(row.id)?.content), ["first", "abc", "def"], "Each note once")
    }

    // MARK: - The notes box reads the document the sheet shows, in StashKit (batch B fix round 1, review m-2)

    /// A rich box after a row is folded into a sheet that keeps its own copy of the document (one opened on a queued
    /// note): the row's document holds the journaled "abc", the sheet's doesn't, so the box keeps it. The view used to
    /// make this choice itself, one innocent edit away from reading the row it was handed: "abc" then left the box
    /// into neither place the next note is built from (`testAJournaledRichNoteStaysInTheBox…`).
    func testARichBoxIsReconciledWithTheDocumentTheSheetShowsNotTheRowItWasHanded() {
        var ledger = RichNoteBox.Ledger()
        let own = appendNoteParagraph(to: richRow().content, note: "offline")      // the sheet's copy
        let journaled = appendNoteParagraph(to: own, note: "abc")
        ledger.journaled("abc", document: journaled)
        var incoming = richRow()
        incoming.content = journaled
        var shown = incoming
        shown.content = own
        let kept = ledger.adopting(incoming, shown: shown, isRich: true, notes: NotesDraftState(draft: "abc", savedDraft: ""))
        XCTAssertEqual(kept, NotesDraftState(draft: "abc", savedDraft: ""), "Not in the document the sheet shows: it stays in the box")
        shown.content = journaled
        XCTAssertEqual(ledger.adopting(incoming, shown: shown, isRich: true, notes: kept), NotesDraftState(draft: "", savedDraft: ""),
                       "Once the sheet shows it, it leaves the box")
    }

    /// The plain note's half of the same function: a plain draft the SERVER holds (the row) counts as saved, whatever
    /// copy of the note the sheet shows.
    func testAPlainDraftTheRowHoldsCountsAsSavedWhateverTheSheetShows() {
        var ledger = RichNoteBox.Ledger()
        var incoming = textRow()
        incoming.content = "abc"
        var shown = incoming
        shown.content = "offline"
        XCTAssertEqual(ledger.adopting(incoming, shown: shown, isRich: false, notes: NotesDraftState(draft: "abc", savedDraft: "offline")),
                       NotesDraftState(draft: "abc", savedDraft: "abc"))
    }

    // MARK: - The save error clears once what it reports has landed (batch B fix round 1, review I-1)

    /// A sheet's save of `patch`, recorded first (write-ahead) and then refused at the link: what the footer's
    /// "Couldn't save — try again." reports.
    private func failSave(_ patch: ItemPatch, itemId: UUID, server: FakeRowServer) async -> FailedSave {
        let at = queue.captureTime()
        queue.record(itemId: itemId, patch: patch, capturedAt: at)
        server.error = URLError(.notConnectedToInternet)
        _ = try? await queue.send(patch, capturedAt: at, itemId: itemId, editor: onlineEditor(server))
        server.error = nil
        return FailedSave(patch: patch, capturedAt: at)
    }

    /// Values seen from inside a flush's `apply` or a notification (`@MainActor`, so a `@Sendable` closure can write).
    @MainActor private final class Seen {
        var values: [Bool] = []
        var ids: [UUID] = []
    }

    /// 4e batch B review I-1, trigger A (both sheet kinds): a note's save fails, so "Couldn't save — try again." goes up,
    /// and a share fails too; the flush `setPublic` then starts gets through and delivers the note. The sheet adopts that
    /// row inside the flush's `apply`, before the queue updates its entry, and the old check (nothing queued for the item)
    /// kept the error. Nothing asked again: an Ask citation sheet is never handed a row, and a library sheet's store
    /// already held the one it adopted. The note was on the server, and the box was empty under the error.
    func testTheSaveErrorClearsWhenAFailedSharesFlushDeliversTheFailedNote() async throws {
        let row = richRow()
        let online = FakeRowServer(rows: [row])
        var sheet = open(row)
        let known = queue.deliveryCount                                  // the row the sheet opened on was read here
        let failed = await failSave(ItemPatch(content: appendNoteParagraph(to: sheet.local.content, note: "abc")),
                                    itemId: row.id, server: online)
        sheet.local.isPublic = true
        _ = failToggle(to: true, noteBefore: nil, knownDeliveries: known, in: &sheet, at: 1)
        XCTAssertFalse(DetailFieldEdits.haveLanded([failed], snapshot: sheet.snapshot, knownDeliveries: known, queue: queue),
                       "precondition: nothing has delivered the note yet")

        let seen = Seen()
        await queue.flush(editor: onlineEditor(online), itemIds: [row.id]) { incoming in
            seen.values.append(DetailFieldEdits.haveLanded([failed], snapshot: incoming,
                                                           knownDeliveries: self.queue.deliveryCount, queue: self.queue))   // `adopt`
        }
        XCTAssertEqual(seen.values, [true], "Inside the flush's apply, as the sheet adopts its row, the note is on the server")
        XCTAssertTrue(DetailFieldEdits.haveLanded([failed], snapshot: sheet.snapshot, knownDeliveries: known, queue: queue),
                      "…and so it is for a sheet that never sees the row (an Ask citation sheet), once the queue has delivered it")
    }

    /// Trigger B, a library sheet: the note's PATCH reaches the server but its response is lost, and the row's realtime
    /// echo reaches the sheet before the save reports its failure. The sheet's last server row holds the note when the
    /// error would go up, so it shouldn't: the write-ahead copy is still queued, and the old check waited for the queue.
    func testTheSaveErrorNeverStaysWhenTheSheetsServerRowAlreadyHoldsTheFailedNote() async throws {
        let row = richRow()
        let online = FakeRowServer(rows: [row])
        var sheet = open(row)
        let document = appendNoteParagraph(to: sheet.local.content, note: "abc")
        online.update(row.id) { $0.content = document }                  // the PATCH lands; its response is lost
        adopt(try XCTUnwrap(online.row(row.id)), in: &sheet)              // the realtime echo, through the store
        let known = queue.deliveryCount                                  // …read here
        let failed = await failSave(ItemPatch(content: document), itemId: row.id, server: online)
        XCTAssertNotNil(queue.edit(for: row.id)?.content, "precondition: the write-ahead copy is still queued")
        XCTAssertTrue(DetailFieldEdits.haveLanded([failed], snapshot: sheet.snapshot, knownDeliveries: known, queue: queue),
                      "The sheet's last server row holds the note: no error")
    }

    /// A guard: a failed note nothing has delivered keeps its error.
    func testTheSaveErrorStaysWhileTheFailedNoteIsOnlyQueued() async {
        let row = richRow()
        let sheet = open(row)
        let known = queue.deliveryCount
        let failed = await failSave(ItemPatch(content: appendNoteParagraph(to: sheet.local.content, note: "abc")),
                                    itemId: row.id, server: FakeRowServer(rows: [row]))
        XCTAssertFalse(DetailFieldEdits.haveLanded([failed], snapshot: sheet.snapshot, knownDeliveries: known, queue: queue))
    }

    /// The error reports every save that failed since the last one that worked, not only the newest: a title save
    /// fails, then a note save. The note's echo shows it on the server, but the title is only queued, so the error stays
    /// until a flush delivers the title too.
    func testTheSaveErrorWaitsForEverySaveThatFailedSinceTheLastOneThatWorked() async throws {
        let row = richRow()
        let online = FakeRowServer(rows: [row])
        var sheet = open(row)
        let title = await failSave(ItemPatch(title: "Standup notes"), itemId: row.id, server: online)
        let document = appendNoteParagraph(to: sheet.local.content, note: "abc")
        online.update(row.id) { $0.content = document }                  // the note's PATCH lands; its response is lost
        adopt(try XCTUnwrap(online.row(row.id)), in: &sheet)
        let known = queue.deliveryCount
        let note = await failSave(ItemPatch(content: document), itemId: row.id, server: online)
        XCTAssertFalse(DetailFieldEdits.haveLanded([title, note], snapshot: sheet.snapshot, knownDeliveries: known, queue: queue),
                       "The title is still only queued")
        await queue.flush(editor: onlineEditor(online), itemIds: [row.id])
        XCTAssertTrue(DetailFieldEdits.haveLanded([title, note], snapshot: sheet.snapshot, knownDeliveries: known, queue: queue),
                      "Both are on the server once the flush delivered the title")
    }

    /// A newer value of the same field, delivered, settles a save of it that failed: "Y"'s autosave failed, "Z" was
    /// typed and journaled as the app left the foreground, and the refresh delivered "Z". The error was about a value
    /// the user had moved on from; the sheet (an Ask citation sheet) never saw the row.
    func testTheSaveErrorClearsWhenANewerValueOfItsFieldIsDelivered() async throws {
        let row = textRow(title: "X")
        let online = FakeRowServer(rows: [row])
        let known = queue.deliveryCount                                  // the sheet's row, read before anything landed
        let failed = await failSave(ItemPatch(title: "Y"), itemId: row.id, server: online)
        queue.record(itemId: row.id, patch: ItemPatch(title: "Z"), capturedAt: queue.captureTime())   // the journal
        await queue.flush(editor: onlineEditor(online), itemIds: [row.id])
        XCTAssertEqual(online.row(row.id)?.title, "Z", "precondition: the newer value is on the server")
        XCTAssertTrue(DetailFieldEdits.haveLanded([failed], snapshot: row, knownDeliveries: known, queue: queue))
    }

    /// Honest the other way round: an edit the queue gave up on (refused by the server `maxRejections` times, then
    /// dropped with an error log) never landed, so its error stays. The old check, which waited only for the queue to be
    /// empty for the item, cleared it once the edit was dropped.
    func testTheSaveErrorStaysWhenTheQueueGivesUpOnTheFailedEdit() async throws {
        var clock = t0
        let dropping = PendingEdits(userId: userId, directory: directory.appendingPathComponent("dropping", isDirectory: true),
                                    now: { clock }, session: FakeSession(signedIn: userId))
        let row = textRow(title: "X")
        let online = FakeRowServer(rows: [row])
        let known = dropping.deliveryCount
        let at = dropping.captureTime()
        dropping.record(itemId: row.id, patch: ItemPatch(title: "Y"), capturedAt: at)
        online.error = NSError(domain: "PostgREST", code: 400)             // refused, not a dead link
        for _ in 0..<PendingEdits.maxRejections where dropping.edit(for: row.id) != nil {
            await dropping.flush(editor: onlineEditor(online), itemIds: [row.id])
            clock = clock.addingTimeInterval(PendingEdits.longestBackoff + 1)
        }
        XCTAssertNil(dropping.edit(for: row.id), "precondition: the queue gave the edit up")
        XCTAssertFalse(DetailFieldEdits.haveLanded([FailedSave(patch: ItemPatch(title: "Y"), capturedAt: at)],
                                                   snapshot: row, knownDeliveries: known, queue: dropping),
                       "It never landed: the error stays")
    }

    /// The queue says when a write of an item has landed, once its delivered ledger holds it, so an open sheet can settle
    /// its error whatever delivered the write: a flush its store never hands it a row from (an Ask citation sheet and
    /// the app's refresh), or a save of its own.
    func testTheQueuePostsEachLandedWriteOfAnItemOnceItsLedgerHoldsIt() async throws {
        let row = textRow(title: "X")
        let rowId = row.id
        let online = FakeRowServer(rows: [row])
        let seen = Seen()
        let watched: PendingEdits = queue
        let titleAt = queue.captureTime()
        let observer = NotificationCenter.default.addObserver(forName: .stashPendingEditDelivered, object: nil, queue: nil) { note in
            let id = note.userInfo?["itemId"] as? UUID
            MainActor.assumeIsolated {
                if let id { seen.ids.append(id) }
                seen.values.append(watched.undelivered(ItemPatch(title: "Y"), capturedAt: titleAt, itemId: rowId).isEmpty)
            }
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        queue.record(itemId: row.id, patch: ItemPatch(title: "Y"), capturedAt: titleAt)
        await queue.flush(editor: onlineEditor(online), itemIds: [row.id])                    // a flush
        let at = queue.captureTime()
        queue.record(itemId: row.id, patch: ItemPatch(description: "Notes"), capturedAt: at)
        _ = try await queue.send(ItemPatch(description: "Notes"), capturedAt: at, itemId: row.id,
                                 editor: onlineEditor(online))                                // a sheet's own save
        XCTAssertEqual(seen.ids, [row.id, row.id], "One post per landed write, naming its item")
        XCTAssertEqual(seen.values, [true, true], "Each post comes once the delivered ledger holds that write")
    }

    // MARK: - A stale row never vouches for a failed save; a landed toggle counts (batch B fix round 2)

    /// Re-review N-1, an Ask citation sheet (its store never hands it a row): "Z" is queued from an earlier session, and the
    /// sheet opens on the server's "Y" (its field shows "Z"). The app's refresh is sending "Z" when the user types "Y" back;
    /// that revert is saved — it differs from the queued "Z" — and waits behind the flush. The flush lands, and the revert
    /// fails right after it. The server holds "Z", but the sheet's last server row, read before the flush, says "Y", and it
    /// vouched for the failed revert: "Changes saved automatically" over the user's older value. The delivered ledger knew
    /// that row was stale: it delivered "Z" after the row was read.
    func testTheSaveErrorStaysWhenARevertFailsRightAfterTheRefreshDeliversTheQueuedValue() async throws {
        let row = textRow(title: "Y")
        queue.record(itemId: row.id, patch: ItemPatch(title: "Z"), capturedAt: queue.captureTime())   // an earlier session's
        let (server, sheets, flushes) = slowLink([row])
        var sheet = open(row)
        let known = queue.deliveryCount                                  // the row the sheet opened on was read here
        XCTAssertEqual(sheet.local.title, "Z", "precondition: the field shows the queued title")
        let refresh = Task { await self.queue.flush(editor: flushes, itemIds: [row.id]) }
        await waitUntil { server.heldCount == 1 }                        // the refresh's "Z" is on its way
        sheet.local.title = "Y"                                          // typed back
        let patch = edits(sheet).textPatch
        XCTAssertEqual(patch, ItemPatch(title: "Y"), "precondition: a revert over a queued value is saved")
        let at = queue.captureTime()
        queue.record(itemId: row.id, patch: patch, capturedAt: at)
        let save = Task { try await self.queue.send(patch, capturedAt: at, itemId: row.id, editor: sheets) }
        await settle()
        server.release()                                                 // "Z" lands…
        await waitUntil { self.queue.deliveryCount > known && server.heldCount == 1 }
        server.error = URLError(.notConnectedToInternet)                 // …and the link drops under the revert's PATCH
        server.gated = false
        server.release()
        let outcome = try? await save.value
        await refresh.value                                              // its second round (the revert) fails too
        XCTAssertNil(outcome, "precondition: the revert's save failed")
        XCTAssertEqual(server.row(row.id)?.title, "Z", "precondition: the server holds the older value")
        let failed = FailedSave(patch: patch, capturedAt: at)

        XCTAssertFalse(DetailFieldEdits.haveLanded([failed], snapshot: sheet.snapshot, knownDeliveries: known, queue: queue),
                       "The ledger delivered \"Z\" after the sheet's row was read: the revert isn't on the server")
        var library = sheet
        adopt(try XCTUnwrap(server.row(row.id)), in: &library)           // a library sheet, handed the flush's row
        XCTAssertFalse(DetailFieldEdits.haveLanded([failed], snapshot: library.snapshot,
                                                   knownDeliveries: queue.deliveryCount, queue: queue),
                       "…nor in a sheet that took the flush's row")
    }

    /// N-1 inside one sheet: "Z"'s autosave fails offline, the app's refresh is sending it when the user types "Y" — the
    /// server's value — back, and that revert fails right after the refresh delivered "Z". "Z" landed, "Y" didn't: the
    /// error stays. The sheet's last server row still said "Y".
    func testTheSaveErrorStaysWhenARevertTypedWhileTheRefreshSendsTheFailedValueFailsToo() async throws {
        let row = textRow(title: "Y")
        let (server, sheets, flushes) = slowLink([row])
        var sheet = open(row)
        let known = queue.deliveryCount
        sheet.local.title = "Z"
        let zPatch = edits(sheet).textPatch
        let zAt = queue.captureTime()
        queue.record(itemId: row.id, patch: zPatch, capturedAt: zAt)
        server.error = URLError(.notConnectedToInternet)
        server.gated = false
        _ = try? await queue.send(zPatch, capturedAt: zAt, itemId: row.id, editor: sheets)   // "Z"'s autosave fails offline
        server.error = nil
        server.gated = true
        let refresh = Task { await self.queue.flush(editor: flushes, itemIds: [row.id]) }
        await waitUntil { server.heldCount == 1 }                        // the refresh's "Z" is on its way
        sheet.local.title = "Y"
        let yPatch = edits(sheet).textPatch
        XCTAssertEqual(yPatch, ItemPatch(title: "Y"), "precondition: the revert is saved")
        let yAt = queue.captureTime()
        queue.record(itemId: row.id, patch: yPatch, capturedAt: yAt)
        let save = Task { try await self.queue.send(yPatch, capturedAt: yAt, itemId: row.id, editor: sheets) }
        await settle()
        let before = queue.deliveryCount
        server.release()                                                 // "Z" lands…
        await waitUntil { self.queue.deliveryCount > before && server.heldCount == 1 }
        server.error = URLError(.notConnectedToInternet)                 // …and the revert's PATCH fails
        server.gated = false
        server.release()
        let outcome = try? await save.value
        await refresh.value
        XCTAssertNil(outcome, "precondition: the revert's save failed")
        XCTAssertEqual(server.row(row.id)?.title, "Z", "precondition: the server holds the failed autosave's value")
        let failed = [FailedSave(patch: zPatch, capturedAt: zAt), FailedSave(patch: yPatch, capturedAt: yAt)]
        XCTAssertFalse(DetailFieldEdits.haveLanded(failed, snapshot: sheet.snapshot, knownDeliveries: known, queue: queue))
    }

    /// A guard for N-1's rule: the ledger outranks the sheet's last server row only for what it delivered AFTER that row
    /// was read. Here the refresh delivered "Z" and the sheet took that row; then "Y"'s PATCH reached the server with its
    /// response lost, and the row's realtime echo — read after the delivery — holds "Y". No error, as for any echo
    /// (trigger B).
    func testTheSaveErrorTrustsARowReadAfterTheLedgersDeliveryOfTheField() async throws {
        let row = textRow(title: "X")
        let online = FakeRowServer(rows: [row])
        var sheet = open(row)
        queue.record(itemId: row.id, patch: ItemPatch(title: "Z"), capturedAt: queue.captureTime())   // the journal
        await queue.flush(editor: onlineEditor(online), itemIds: [row.id])          // the refresh delivers "Z"
        adopt(try XCTUnwrap(online.row(row.id)), in: &sheet)                         // the store's `onChange`
        sheet.local.title = "Y"
        online.update(row.id) { $0.title = "Y" }                                    // "Y"'s PATCH lands; its response is lost
        adopt(try XCTUnwrap(online.row(row.id)), in: &sheet)                         // its realtime echo
        let known = queue.deliveryCount                                              // …the sheet's last server row
        let failed = await failSave(ItemPatch(title: "Y"), itemId: row.id, server: online)
        XCTAssertTrue(DetailFieldEdits.haveLanded([failed], snapshot: sheet.snapshot, knownDeliveries: known, queue: queue),
                      "The row read after the delivery holds \"Y\": no error")
    }

    /// Re-review N-2: a sticky note's save fails, so "Couldn't save — try again." goes up. The link is back, and the user
    /// makes the item private, confirming that the note is removed; the un-share lands. The server holds what they last
    /// asked for — private, no note — and nothing is left to retry for the note, yet the error stayed up: the toggle's
    /// PATCH went out past the delivered ledger, so its removal of the note didn't count as the newer value of the field it
    /// is. The toggle goes through the ledger now (`PendingEdits.sendToggle`), and it counts from the moment it lands (the
    /// queue's post), whether the sheet then adopts its row or carries it under a newer save.
    func testTheSaveErrorClearsWhenAnUnshareThatRemovesTheFailedStickyNoteLands() async throws {
        let row = textRow(note: "For you", isPublic: true)
        let online = FakeRowServer(rows: [row])
        var sheet = open(row)
        let known = queue.deliveryCount
        sheet.local.supplementalNote = "For you all"
        let note = await failSave(edits(sheet).textPatch, itemId: row.id, server: online)
        let title = await failSave(ItemPatch(title: "Standup notes"), itemId: row.id, server: online)
        let editor = onlineEditor(online)
        let toggle = editor.togglePublic(item: sheet.local, to: false)
        XCTAssertEqual(toggle, ItemPatch(supplementalNote: "", isPublic: false), "precondition: the un-share removes the note")
        sheet.local.isPublic = false
        sheet.local.supplementalNote = nil                               // optimistic, as `setPublic` does
        let seen = Seen()
        let shown = sheet.snapshot
        let watched: PendingEdits = queue
        let observer = NotificationCenter.default.addObserver(forName: .stashPendingEditDelivered, object: nil, queue: nil) { _ in
            MainActor.assumeIsolated {
                seen.values.append(DetailFieldEdits.haveLanded([note], snapshot: shown, knownDeliveries: known, queue: watched))
            }
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        let at = queue.captureTime()
        let saved = try await queue.sendToggle(toggle, capturedAt: at, itemId: row.id, editor: editor)
        sheet.local = DetailFieldEdits.landing(toggle, capturedAt: at, as: saved, local: sheet.local,
                                               baseline: ItemDisplay.editableRow(sheet.snapshot), queue: queue,
                                               sheetIsOpen: true, at: queue.captureTime(), apply: { _ in })
        sheet.snapshot = saved                                           // `adopt`
        let adopted = queue.deliveryCount
        XCTAssertEqual(online.row(row.id)?.isPublic, false, "precondition: the un-share landed")
        XCTAssertNil(online.row(row.id)?.supplementalNote, "precondition: …and removed the note")
        XCTAssertNil(queue.edit(for: row.id)?.supplementalNote, "precondition: nothing is left to retry for the note")

        XCTAssertEqual(seen.values, [true], "As the toggle lands (the queue's post), the failed note has been superseded")
        XCTAssertTrue(DetailFieldEdits.haveLanded([note], snapshot: sheet.snapshot, knownDeliveries: adopted, queue: queue),
                      "…and so it stays once the sheet takes the toggle's row")
        XCTAssertFalse(DetailFieldEdits.haveLanded([note, title], snapshot: sheet.snapshot, knownDeliveries: adopted,
                                                   queue: queue),
                       "A failed save of a field the toggle didn't carry keeps the error")
    }

    // MARK: - What the user just typed is never replaced by a flushed row (4e review M-1)

    /// 4e review M-1 (P-1 with no save of the field in flight): "Y"'s autosave failed offline, so "Y"
    /// stays queued and nothing is sending. Back online, the user types "X" — the server's value —
    /// and inside that revert's debounce a foreground flush delivers "Y"; the store hands the sheet
    /// the row. Nothing queued, nothing sending, the field equal to the sheet's last server row:
    /// `adopt` took "Y" — visibly — and the debounce then sent nothing. A field typed into since its
    /// last save started stays as the user left it.
    func testARevertTypedOverAFailedSaveSurvivesAFlushInsideItsDebounce() async throws {
        let server = textRow(title: "X")
        var sheet = open(server)
        sheet.local.title = "Y"
        queue.record(itemId: server.id, patch: edits(sheet).textPatch, capturedAt: queue.captureTime())   // its PATCH failed
        sheet.local.title = "X"                                          // typed back, inside the debounce
        let online = FakeRowServer(rows: [server])
        await deliverQueue(to: online)                                   // the foreground flush delivers "Y"

        let row = try XCTUnwrap(online.row(server.id))
        sheet.local = DetailFieldEdits(local: sheet.local, baseline: ItemDisplay.editableRow(sheet.snapshot),
                                       queued: queue.edit(for: server.id), typedSinceSave: [.title])
            .adopting(row)                                               // the store's `onChange` → `adopt`
        sheet.snapshot = row
        XCTAssertEqual(sheet.local.title, "X", "The user's last typed value stays in the field")
        XCTAssertEqual(edits(sheet).textPatch, ItemPatch(title: "X"), "…and the debounce sends it")
    }

    /// M-1 through a landing: "Y"'s autosave failed, so "Y" stays queued; a flush delivers it, and
    /// the user types "X" (the server's old value) back. Inside that debounce another field's save
    /// lands, with the server's row — title "Y". That landing keeps the typed title too.
    func testARevertTypedInTheDebounceSurvivesAnotherFieldsSaveLandingOnTheFlushedValue() async throws {
        let server = textRow(title: "X")
        var sheet = open(server)
        sheet.local.title = "Y"
        queue.record(itemId: server.id, patch: edits(sheet).textPatch, capturedAt: queue.captureTime())   // its PATCH failed
        let online = FakeRowServer(rows: [server])
        await deliverQueue(to: online)                                   // a flush delivers "Y"
        sheet.local.title = "X"                                          // typed back, inside the debounce
        let descriptionAt = queue.captureTime()
        queue.record(itemId: server.id, patch: ItemPatch(description: "Notes"), capturedAt: descriptionAt)
        let sent = try await queue.send(ItemPatch(description: "Notes"), capturedAt: descriptionAt, itemId: server.id,
                                        editor: ItemEditor(patcher: online,
                                                           refresher: EmbeddingRefresher(syncer: RecordingSyncer(), idle: .milliseconds(10)),
                                                           writeQueue: ItemWriteQueue()))
        XCTAssertEqual(sent.item?.title, "Y", "precondition: the row the description's save lands holds the flushed title")

        let landed = DetailFieldEdits.landing(sent, capturedAt: descriptionAt, local: sheet.local, snapshot: sheet.snapshot,
                                              queue: queue, sheetIsOpen: true, at: queue.captureTime(),
                                              typedSinceSave: [.title], apply: { _ in })
        XCTAssertEqual(landed.fields.title, "X", "The user's last typed value stays in the field")
    }

    /// M-1 across sheets: sheet 1 closes with "Y" queued; sheet 2 opens on the queued "Y", and the
    /// user types "X" (the server's value) back. Inside that debounce a flush delivers "Y". Sheet 2
    /// has no save in flight; the field it typed into keeps the user's value.
    func testARevertTypedInAReopenedSheetSurvivesTheFlushOfTheValueItOpenedOn() async throws {
        let server = textRow(title: "X")
        var first = open(server)
        first.local.title = "Y"
        dismiss(first, at: 1)                                            // the close journals "Y"
        var second = open(server)
        XCTAssertEqual(second.local.title, "Y", "precondition: sheet 2 opens on the queued title")
        second.local.title = "X"
        let online = FakeRowServer(rows: [server])
        await deliverQueue(to: online)

        let row = try XCTUnwrap(online.row(server.id))
        second.local = DetailFieldEdits(local: second.local, baseline: ItemDisplay.editableRow(second.snapshot),
                                        queued: queue.edit(for: server.id), typedSinceSave: [.title])
            .adopting(row)
        second.snapshot = row
        XCTAssertEqual(second.local.title, "X", "The user's last typed value stays in the field")
        XCTAssertEqual(edits(second).textPatch, ItemPatch(title: "X"), "…and the debounce sends it")
    }

    // MARK: - Every other field keeps its plain comparison with the server's row

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
