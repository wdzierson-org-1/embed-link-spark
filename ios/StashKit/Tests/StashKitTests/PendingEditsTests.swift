import XCTest
@testable import StashKit

/// Server stand-in for `ItemEditor`/`PendingEdits` tests: applies each PATCH to an in-memory row and
/// returns it (like `SupabaseItemPatcher`), throws `itemNotFound` for an unknown id, and can fail
/// (`error`) or hold each PATCH until `release()` (`gated`). PATCHes are recorded when SENT.
final class FakeRowServer: ItemPatching, @unchecked Sendable {
    private let lock = NSLock()
    private var rows: [UUID: Item]
    private var sent: [(UUID, ItemPatch)] = []
    private var failure: Error?
    private var isGated = false
    private var gates: [CheckedContinuation<Void, Never>] = []

    init(rows: [Item]) {
        self.rows = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
    }

    var patches: [(UUID, ItemPatch)] { lock.withLock { sent } }
    var error: Error? {
        get { lock.withLock { failure } }
        set { lock.withLock { failure = newValue } }
    }
    var gated: Bool {
        get { lock.withLock { isGated } }
        set { lock.withLock { isGated = newValue } }
    }
    var heldCount: Int { lock.withLock { gates.count } }

    func row(_ id: UUID) -> Item? { lock.withLock { rows[id] } }
    func update(_ id: UUID, _ change: (inout Item) -> Void) {
        lock.withLock {
            guard var row = rows[id] else { return }
            change(&row)
            rows[id] = row
        }
    }

    func release() {
        let gate = lock.withLock { gates.isEmpty ? nil : gates.removeFirst() }
        gate?.resume()
    }

    func patch(itemId: UUID, patch: ItemPatch) async throws -> Item {
        let hold = lock.withLock { () -> Bool in
            sent.append((itemId, patch))
            return isGated
        }
        if hold {
            await withCheckedContinuation { continuation in lock.withLock { gates.append(continuation) } }
        }
        return try lock.withLock {
            if let failure { throw failure }
            guard var row = rows[itemId] else { throw ItemEditorError.itemNotFound }
            if let title = patch.title { row.title = title }
            if let description = patch.description { row.description = description }
            if let content = patch.content { row.content = content }
            if let note = patch.supplementalNote { row.supplementalNote = note.isEmpty ? nil : note }
            if let isPublic = patch.isPublic { row.isPublic = isPublic }
            if let attributes = patch.attributes { row.attributes = attributes }
            rows[itemId] = row
            return row
        }
    }

    func currentAttributes(itemId: UUID) async throws -> ItemAttributes? {
        try lock.withLock {
            if let failure { throw failure }
            return rows[itemId]?.attributes
        }
    }

    func deleteItemCascade(itemId: UUID) async throws { _ = lock.withLock { rows.removeValue(forKey: itemId) } }
    func itemTags(itemId: UUID) async throws -> [StashTag] { [] }
    func addTag(named: String, userId: UUID, itemId: UUID) async throws {}
    func removeTag(tagId: UUID, itemId: UUID) async throws {}
    func suggestTags(title: String, content: String, description: String, available: [String]) async throws -> [String] { [] }
}

/// Collects the rows a flush hands back (`@MainActor`, so a `@Sendable` apply closure can append).
@MainActor
final class AppliedRows {
    var rows: [Item] = []
}

@MainActor
final class PendingEditsTests: XCTestCase {
    private var directory: URL!
    private let t0 = Date(timeIntervalSince1970: 1_790_000_000)

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PendingEditsTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    /// Signed in as the queue's own user unless `sessionUserId` says otherwise.
    private func makeQueue(userId: UUID = UUID(), sessionUserId: UUID?? = nil) -> PendingEdits {
        let session = sessionUserId ?? userId
        return PendingEdits(userId: userId, directory: directory, sessionUserId: { session })
    }

    private func makeItem(title: String = "Server title", content: String? = "server note",
                          attributes: ItemAttributes = ItemAttributes()) -> Item {
        Item(id: UUID(), type: .text, title: title, content: content, url: nil, filePath: nil,
             description: "Server description", summary: nil, pageBody: nil, supplementalNote: nil,
             mimeType: nil, isPublic: false, createdAt: t0, attributes: attributes)
    }

    /// A private write queue unless one is passed (to share it between two editors).
    private func makeEditor(_ server: FakeRowServer, syncer: RecordingSyncer = RecordingSyncer(),
                            writeQueue: ItemWriteQueue? = nil) -> ItemEditor {
        ItemEditor(patcher: server, refresher: EmbeddingRefresher(syncer: syncer, idle: .milliseconds(10)),
                   writeQueue: writeQueue ?? ItemWriteQueue())
    }

    private func fileExists(_ queue: PendingEdits, _ id: UUID) -> Bool {
        FileManager.default.fileExists(atPath: queue.fileURL(for: id).path)
    }

    private func waitUntil(_ condition: () -> Bool, timeout: TimeInterval = 2) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline { try? await Task.sleep(for: .milliseconds(5)) }
    }

    // MARK: - Merge

    func testRecordMergesLatestWinsPerField() {
        let queue = makeQueue()
        let id = UUID()
        queue.record(itemId: id, patch: ItemPatch(title: "newest"), capturedAt: t0.addingTimeInterval(10))
        // Captured earlier, recorded later (e.g. a failed save's value arriving after the dismiss).
        queue.record(itemId: id, patch: ItemPatch(title: "older", description: "desc"), capturedAt: t0)

        XCTAssertEqual(queue.edit(for: id)?.title?.value, "newest", "an older value recorded late never wins")
        XCTAssertEqual(queue.edit(for: id)?.description?.value, "desc", "fields merge independently")

        queue.record(itemId: id, patch: ItemPatch(title: "newer still"), capturedAt: t0.addingTimeInterval(20))
        XCTAssertEqual(queue.edit(for: id)?.title?.value, "newer still")
        XCTAssertEqual(queue.edit(for: id)?.revision, 3)
    }

    func testConfirmForgetsOnlyWhatTheServerNowHolds() {
        let queue = makeQueue()
        let id = UUID()
        queue.record(itemId: id, patch: ItemPatch(title: "A", description: "D"), capturedAt: t0)
        // Typed while the first save was in flight.
        queue.record(itemId: id, patch: ItemPatch(title: "AB"), capturedAt: t0.addingTimeInterval(5))

        queue.confirm(itemId: id, patch: ItemPatch(title: "A", description: "D"), capturedAt: t0)
        XCTAssertEqual(queue.edit(for: id)?.title?.value, "AB", "a newer, different value stays queued")
        XCTAssertNil(queue.edit(for: id)?.description)
        XCTAssertTrue(fileExists(queue, id))

        queue.confirm(itemId: id, patch: ItemPatch(title: "AB"), capturedAt: t0.addingTimeInterval(5))
        XCTAssertNil(queue.edit(for: id))
        XCTAssertFalse(fileExists(queue, id), "a fully confirmed item leaves no file behind")
    }

    func testConfirmOfTheSameValueRecordedAgainOnDismissForgetsIt() {
        let queue = makeQueue()
        let id = UUID()
        queue.record(itemId: id, patch: ItemPatch(content: "my note"), capturedAt: t0)            // before the PATCH
        queue.record(itemId: id, patch: ItemPatch(content: "my note"), capturedAt: t0.addingTimeInterval(1)) // dismiss
        queue.confirm(itemId: id, patch: ItemPatch(content: "my note"), capturedAt: t0)
        XCTAssertNil(queue.edit(for: id), "the server holds exactly that value now")
    }

    func testOverlayLaysQueuedValuesOverTheServerRow() {
        let queue = makeQueue()
        let media = MediaAttributes(durationS: 42, extra: ["kind": .string("voice_note")])
        var row = makeItem(attributes: ItemAttributes(media: media))
        row.supplementalNote = "old sticky"
        let other = makeItem(title: "untouched")
        let location = CapturedLocation(label: "Brooklyn, New York", source: "manual")
        queue.record(itemId: row.id, patch: ItemPatch(title: "Mine", content: "my note", supplementalNote: "",
                                                      isPublic: true, attributes: ItemAttributes(location: location)),
                     capturedAt: t0)

        let shown = queue.overlay(row)

        XCTAssertEqual(shown.title, "Mine")
        XCTAssertEqual(shown.content, "my note")
        XCTAssertNil(shown.supplementalNote, "\"\" is the clear-the-sticky-note convention")
        XCTAssertTrue(shown.isPublic)
        XCTAssertEqual(shown.attributes.location, location)
        XCTAssertEqual(shown.attributes.media, media, "only the location is taken from a queued attributes blob")
        XCTAssertEqual(shown.description, row.description)
        XCTAssertEqual(queue.overlay(other), other)
    }

    // MARK: - Durability

    func testQueuedEditsSurviveARelaunch() throws {
        let userId = UUID()
        let id = UUID()
        let tipTap = #"{"type":"doc","content":[{"type":"paragraph","content":[{"type":"text","text":"hello"}]}]}"#
        let location = CapturedLocation(label: "Brooklyn, New York", source: "manual", extra: ["place_id": .string("p1")])
        PendingEdits(userId: userId, directory: directory)
            .record(itemId: id, patch: ItemPatch(content: tipTap, supplementalNote: "", isPublic: true,
                                                 attributes: ItemAttributes(location: location)),
                    capturedAt: t0)

        // A relaunch (or a crash): a fresh instance over the same directory, nothing in memory.
        let reloaded = PendingEdits(userId: userId, directory: directory)
        let edit = try XCTUnwrap(reloaded.edit(for: id))
        XCTAssertEqual(edit.content?.value, tipTap, "the note is stored exactly as the editor held it")
        XCTAssertEqual(edit.content?.capturedAt, t0)
        XCTAssertEqual(edit.supplementalNote?.value, "")
        XCTAssertEqual(edit.isPublic?.value, true)
        XCTAssertEqual(edit.attributes?.value.location, location)
    }

    func testUnreadableOrForeignFilesNeverBreakTheQueue() throws {
        let userId = UUID()
        let kept = UUID()
        let torn = UUID()
        PendingEdits(userId: userId, directory: directory)
            .record(itemId: kept, patch: ItemPatch(title: "kept"), capturedAt: t0)
        let tornURL = directory.appendingPathComponent("\(torn.uuidString.lowercased()).json")
        try Data(#"{"version":1,"userId":"#.utf8).write(to: tornURL)
        try Data("junk".utf8).write(to: directory.appendingPathComponent(".stray-temp-file"))

        let reloaded = PendingEdits(userId: userId, directory: directory)
        XCTAssertEqual(reloaded.edit(for: kept)?.title?.value, "kept")
        XCTAssertNil(reloaded.edit(for: torn))
        XCTAssertFalse(FileManager.default.fileExists(atPath: tornURL.path), "an unreadable file is removed")

        let otherUser = PendingEdits(userId: UUID(), directory: directory)
        XCTAssertNil(otherUser.edit(for: kept), "an entry written for another user is never read")
    }

    func testDiscardForgetsTheItem() {
        let queue = makeQueue()
        let id = UUID()
        queue.record(itemId: id, patch: ItemPatch(title: "gone"), capturedAt: t0)
        queue.discard(itemId: id)
        XCTAssertNil(queue.edit(for: id))
        XCTAssertFalse(fileExists(queue, id))
    }

    // MARK: - Flush

    func testFlushSendsQueuedEditsForgetsThemAndRefreshesEmbeddings() async throws {
        let row = makeItem()
        let server = FakeRowServer(rows: [row])
        let syncer = RecordingSyncer()
        let queue = makeQueue()
        queue.record(itemId: row.id, patch: ItemPatch(title: "Offline title", content: "offline note"), capturedAt: t0)
        let applied = AppliedRows()

        await queue.flush(editor: makeEditor(server, syncer: syncer)) { applied.rows.append($0) }

        XCTAssertEqual(server.patches.map(\.1), [ItemPatch(title: "Offline title", content: "offline note")])
        XCTAssertEqual(server.row(row.id)?.title, "Offline title")
        XCTAssertNil(queue.edit(for: row.id))
        XCTAssertFalse(fileExists(queue, row.id), "a flushed edit's file is deleted")
        XCTAssertEqual(applied.rows.map(\.title), ["Offline title"], "the saved row is handed back to the store")
        try await Task.sleep(for: .milliseconds(120))
        XCTAssertEqual(syncer.calls.count, 1, "a flushed text change refreshes the item's embeddings")
    }

    func testFailedFlushKeepsTheEditAndCountsTheAttempt() async throws {
        let row = makeItem()
        let server = FakeRowServer(rows: [row])
        server.error = URLError(.notConnectedToInternet)
        let userId = UUID()
        let queue = makeQueue(userId: userId)
        queue.record(itemId: row.id, patch: ItemPatch(content: "typed offline"), capturedAt: t0)
        let editor = makeEditor(server)

        await queue.flush(editor: editor)

        XCTAssertEqual(queue.edit(for: row.id)?.content?.value, "typed offline")
        XCTAssertEqual(queue.edit(for: row.id)?.attempts, 1)
        let reloaded = PendingEdits(userId: userId, directory: directory)
        XCTAssertEqual(reloaded.edit(for: row.id)?.attempts, 1, "the attempt count is on disk too")
        XCTAssertEqual(reloaded.edit(for: row.id)?.content?.value, "typed offline")

        server.error = nil                                   // the network is back
        await queue.flush(editor: editor)
        XCTAssertNil(queue.edit(for: row.id))
        XCTAssertEqual(server.row(row.id)?.content, "typed offline")
    }

    func testFlushDropsTheEditOfADeletedItem() async {
        let queue = makeQueue()
        let id = UUID()
        queue.record(itemId: id, patch: ItemPatch(title: "edited, then deleted elsewhere"), capturedAt: t0)

        await queue.flush(editor: makeEditor(FakeRowServer(rows: [])))

        XCTAssertNil(queue.edit(for: id), "a row that no longer exists can't take the edit — never retried")
        XCTAssertFalse(fileExists(queue, id))
    }

    /// After an account switch, a flush still around for the previous user must neither send under
    /// the new user's session (RLS would match nothing) nor drop the edit as "deleted".
    func testAFlushUnderAnotherAccountsSessionSendsNothingAndKeepsTheEdit() async {
        let row = makeItem()
        let server = FakeRowServer(rows: [row])
        let owner = UUID()
        let queue = makeQueue(userId: owner, sessionUserId: .some(UUID()))
        queue.record(itemId: row.id, patch: ItemPatch(title: "the owner's edit"), capturedAt: t0)

        await queue.flush(editor: makeEditor(server))

        XCTAssertTrue(server.patches.isEmpty, "never sent under someone else's session")
        XCTAssertEqual(queue.edit(for: row.id)?.title?.value, "the owner's edit")
        XCTAssertEqual(queue.edit(for: row.id)?.attempts, 0)

        let signedOut = makeQueue(userId: owner, sessionUserId: .some(nil))
        await signedOut.flush(editor: makeEditor(FakeRowServer(rows: [])))
        XCTAssertEqual(signedOut.edit(for: row.id)?.title?.value, "the owner's edit",
                       "signed out: kept for the owner's next session, not dropped as deleted")
    }

    func testQueuedLocationLandsOnTheServersCurrentAttributes() async throws {
        let pendingTranscript = JSONValue.object(["status": .string("pending")])
        let doneTranscript = JSONValue.object(["status": .string("done"), "model": .string("diarize")])
        let row = makeItem(attributes: ItemAttributes(media: MediaAttributes(durationS: 30, extra: ["transcript": pendingTranscript])))
        let server = FakeRowServer(rows: [row])
        let queue = makeQueue()
        var edited = row.attributes
        edited.location = CapturedLocation(label: "Lisbon", source: "manual")
        queue.record(itemId: row.id, patch: ItemPatch(attributes: edited), capturedAt: t0)
        // While the edit waited, the server finished transcribing and rewrote `media.transcript`.
        server.update(row.id) { $0.attributes.media?.extra["transcript"] = doneTranscript }

        await queue.flush(editor: makeEditor(server))

        let sent = try XCTUnwrap(server.patches.first?.1.attributes)
        XCTAssertEqual(sent.location?.label, "Lisbon")
        XCTAssertEqual(sent.media?.extra["transcript"], doneTranscript,
                       "only the location is applied — the server's newer keys are never overwritten")
        XCTAssertNil(queue.edit(for: row.id))
    }

    func testQueuedLocationTheServerAlreadyHasIsConfirmedWithoutARequest() async {
        let location = CapturedLocation(label: "Lisbon", source: "manual")
        let row = makeItem(attributes: ItemAttributes(location: location))
        let server = FakeRowServer(rows: [row])
        let queue = makeQueue()
        queue.record(itemId: row.id, patch: ItemPatch(attributes: row.attributes), capturedAt: t0)

        await queue.flush(editor: makeEditor(server))

        XCTAssertTrue(server.patches.isEmpty)
        XCTAssertNil(queue.edit(for: row.id))
    }

    func testValuesRecordedDuringAFlushAreSentRightAfter() async {
        let row = makeItem()
        let server = FakeRowServer(rows: [row])
        server.gated = true
        let queue = makeQueue()
        queue.record(itemId: row.id, patch: ItemPatch(title: "first"), capturedAt: t0)
        let flush = Task { await queue.flush(editor: makeEditor(server)) }
        await waitUntil { server.heldCount == 1 }

        queue.record(itemId: row.id, patch: ItemPatch(title: "typed during the flight"), capturedAt: t0.addingTimeInterval(10))
        server.gated = false
        server.release()
        await flush.value

        XCTAssertEqual(server.patches.map(\.1.title), ["first", "typed during the flight"])
        XCTAssertEqual(server.row(row.id)?.title, "typed during the flight")
        XCTAssertNil(queue.edit(for: row.id))
    }

    /// The race the write queue exists for: a sheet's PATCH is still in flight when the flush of the
    /// (newer) queued value starts — the flush must go out after it, so the newest value lands last.
    func testAFlushNeverOvertakesAnEarlierWriteToTheSameItem() async throws {
        let row = makeItem()
        let server = FakeRowServer(rows: [row])
        let writeQueue = ItemWriteQueue()
        let sheetEditor = makeEditor(server, writeQueue: writeQueue)
        let flushEditor = makeEditor(server, writeQueue: writeQueue)
        server.gated = true
        let inFlight = Task { try await sheetEditor.save(itemId: row.id, patch: ItemPatch(title: "older")) }
        await waitUntil { server.heldCount == 1 }

        let queue = makeQueue()
        queue.record(itemId: row.id, patch: ItemPatch(title: "newer"), capturedAt: t0)
        let flush = Task { await queue.flush(editor: flushEditor) }
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(server.patches.count, 1, "the flush waits for the write already in flight")

        server.gated = false
        server.release()
        _ = try await inFlight.value
        await flush.value

        XCTAssertEqual(server.patches.map(\.1.title), ["older", "newer"])
        XCTAssertEqual(server.row(row.id)?.title, "newer", "the newest value lands last")
    }

    func testWritesToDifferentItemsDoNotWaitOnEachOther() async throws {
        let a = makeItem(title: "a")
        let b = makeItem(title: "b")
        let server = FakeRowServer(rows: [a, b])
        let editor = makeEditor(server)
        server.gated = true
        let slow = Task { try await editor.save(itemId: a.id, patch: ItemPatch(title: "a2")) }
        await waitUntil { server.heldCount == 1 }
        server.gated = false

        let saved = try await editor.save(itemId: b.id, patch: ItemPatch(title: "b2"))

        XCTAssertEqual(saved.title, "b2", "item b never waited on item a's stalled write")
        server.release()
        _ = try await slow.value
    }
}
