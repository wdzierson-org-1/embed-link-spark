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
    private var hidesRows = false
    private var gates: [CheckedContinuation<Void, Never>] = []

    /// The anon-key fallback: a send that went out without the user's token. RLS hides every row,
    /// so a PATCH matches nothing (`itemNotFound`) and an attributes read finds nothing — although
    /// the rows exist.
    var rlsHidesRows: Bool {
        get { lock.withLock { hidesRows } }
        set { lock.withLock { hidesRows = newValue } }
    }

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
            guard !hidesRows, var row = rows[itemId] else { throw ItemEditorError.itemNotFound }
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
            return hidesRows ? nil : rows[itemId]?.attributes
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

/// Session stand-in: who's signed in (nil = signed out), an optional "no valid token right now"
/// error (e.g. a refresh that can't reach the server), and the verifying read — made with a
/// verified token, so it sees the real rows even when a send's RLS view didn't.
final class FakeSession: PendingEditsSession, @unchecked Sendable {
    private let lock = NSLock()
    private var user: UUID?
    private var error: Error?
    private var readError: Error?
    private var reads = 0
    private let server: FakeRowServer?

    init(signedIn user: UUID?, server: FakeRowServer? = nil) {
        self.user = user
        self.server = server
    }

    var signedIn: UUID? {
        get { lock.withLock { user } }
        set { lock.withLock { user = newValue } }
    }
    var tokenError: Error? {
        get { lock.withLock { error } }
        set { lock.withLock { error = newValue } }
    }
    /// Thrown by the verifying read (e.g. `.unverifiable` for a 5xx) — nothing may be concluded.
    var verifyingReadError: Error? {
        get { lock.withLock { readError } }
        set { lock.withLock { readError = newValue } }
    }
    var verifyingReads: Int { lock.withLock { reads } }

    func accessToken(for userId: UUID) async throws -> String {
        let (user, error) = lock.withLock { (self.user, self.error) }
        if let error { throw error }
        guard user == userId else { throw PendingEditsSessionError.notSignedInAsOwner }
        return "valid-token"
    }

    func rowExists(itemId: UUID, accessToken: String) async throws -> Bool {
        let readError = lock.withLock { () -> Error? in
            reads += 1
            return self.readError
        }
        if let readError { throw readError }
        return server?.row(itemId) != nil
    }
}

/// Answers every request of a `URLSession` built with `StubbedHTTP.session()` with `respond`'s
/// canned status and body, and remembers the requests — for `SupabasePendingEditsSession.rowExists`.
final class StubbedHTTP: URLProtocol {
    private static let lock = NSLock()
    private static var responder: (URLRequest) -> (status: Int, body: Data) = { _ in (500, Data()) }
    private static var seen: [URLRequest] = []

    static var requests: [URLRequest] { lock.withLock { seen } }

    static func session(respond: @escaping (URLRequest) -> (status: Int, body: Data)) -> URLSession {
        lock.withLock {
            responder = respond
            seen = []
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubbedHTTP.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let answer = Self.lock.withLock { () -> (status: Int, body: Data) in
            Self.seen.append(request)
            return Self.responder(request)
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: answer.status, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: answer.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// A send the server answered and refused (not a transport failure).
struct ServerRefusal: Error {}

/// A clock a test can move.
final class TestClock {
    var now: Date
    init(_ now: Date) { self.now = now }
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

    /// Signed in as the queue's own user (verifying reads answered from `server`) unless a
    /// `session` is passed; the real clock unless `clock` is.
    private func makeQueue(userId: UUID = UUID(), server: FakeRowServer? = nil, session: FakeSession? = nil,
                           clock: TestClock? = nil) -> PendingEdits {
        let now: () -> Date = clock.map { clock in { clock.now } } ?? Date.init
        return PendingEdits(userId: userId, directory: directory, now: now,
                            session: session ?? FakeSession(signedIn: userId, server: server))
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

    /// Offline (or timed out): the edit stays exactly as it was — not counted, not backed off — so
    /// the first flush after the network returns sends it.
    func testTransportFailuresKeepTheEditWithoutCountingOrBackingOff() async throws {
        let row = makeItem()
        let server = FakeRowServer(rows: [row])
        server.error = URLError(.notConnectedToInternet)
        let userId = UUID()
        let queue = makeQueue(userId: userId, server: server)
        queue.record(itemId: row.id, patch: ItemPatch(content: "typed offline"), capturedAt: t0)
        let editor = makeEditor(server)

        await queue.flush(editor: editor)
        server.error = URLError(.timedOut)
        await queue.flush(editor: editor)

        XCTAssertEqual(server.patches.count, 2, "no backoff after a transport failure")
        XCTAssertEqual(queue.edit(for: row.id)?.content?.value, "typed offline")
        XCTAssertEqual(queue.edit(for: row.id)?.attempts, 0)
        XCTAssertNil(queue.edit(for: row.id)?.nextAttemptAt)

        server.error = nil                                   // the network is back
        await queue.flush(editor: editor)
        XCTAssertNil(queue.edit(for: row.id))
        XCTAssertEqual(server.row(row.id)?.content, "typed offline")
    }

    func testARefusedSendIsCountedAndBacksOffExponentially() async throws {
        let row = makeItem()
        let server = FakeRowServer(rows: [row])
        server.error = ServerRefusal()
        let clock = TestClock(t0)
        let userId = UUID()
        let queue = makeQueue(userId: userId, server: server, clock: clock)
        queue.record(itemId: row.id, patch: ItemPatch(title: "refused"), capturedAt: t0)
        let editor = makeEditor(server)

        await queue.flush(editor: editor)
        XCTAssertEqual(queue.edit(for: row.id)?.attempts, 1)
        XCTAssertEqual(queue.edit(for: row.id)?.nextAttemptAt, t0.addingTimeInterval(30))
        XCTAssertEqual(PendingEdits(userId: userId, directory: directory).edit(for: row.id)?.attempts, 1,
                       "the count and the backoff are on disk too")

        await queue.flush(editor: editor)
        XCTAssertEqual(server.patches.count, 1, "not sent again before its backoff passes")

        clock.now = t0.addingTimeInterval(31)
        await queue.flush(editor: editor)
        XCTAssertEqual(server.patches.count, 2)
        XCTAssertEqual(queue.edit(for: row.id)?.nextAttemptAt, clock.now.addingTimeInterval(60), "doubles")
        XCTAssertEqual(PendingEdits.backoff(afterRejections: 12), 6 * 60 * 60, "capped at 6 h")

        server.error = nil
        clock.now = clock.now.addingTimeInterval(61)
        await queue.flush(editor: editor)
        XCTAssertNil(queue.edit(for: row.id), "delivered once the server accepts it")
    }

    func testANewValueIsDueAtOnceEvenWhileAnOlderOneBacksOff() async {
        let row = makeItem()
        let server = FakeRowServer(rows: [row])
        server.error = ServerRefusal()
        let clock = TestClock(t0)
        let queue = makeQueue(server: server, clock: clock)
        queue.record(itemId: row.id, patch: ItemPatch(title: "too long?"), capturedAt: t0)
        await queue.flush(editor: makeEditor(server))
        XCTAssertNotNil(queue.edit(for: row.id)?.nextAttemptAt)

        server.error = nil
        queue.record(itemId: row.id, patch: ItemPatch(title: "fixed"), capturedAt: t0.addingTimeInterval(1))
        await queue.flush(editor: makeEditor(server))

        XCTAssertEqual(server.row(row.id)?.title, "fixed")
        XCTAssertNil(queue.edit(for: row.id))
    }

    func testAnEditRefusedTwentyTimesIsDropped() async {
        let row = makeItem()
        let server = FakeRowServer(rows: [row])
        server.error = ServerRefusal()
        let clock = TestClock(t0)
        let queue = makeQueue(server: server, clock: clock)
        queue.record(itemId: row.id, patch: ItemPatch(content: "never accepted"), capturedAt: t0)
        let editor = makeEditor(server)

        for round in 1...PendingEdits.maxRejections {
            await queue.flush(editor: editor)
            XCTAssertEqual(server.patches.count, round)
            clock.now = clock.now.addingTimeInterval(7 * 60 * 60)   // past any backoff
        }

        XCTAssertNil(queue.edit(for: row.id), "given up after \(PendingEdits.maxRejections) refusals")
        XCTAssertFalse(fileExists(queue, row.id))
    }

    func testFlushDropsTheEditOfADeletedItem() async {
        let server = FakeRowServer(rows: [])
        let owner = UUID()
        let session = FakeSession(signedIn: owner, server: server)
        let queue = makeQueue(userId: owner, session: session)
        let id = UUID()
        queue.record(itemId: id, patch: ItemPatch(title: "edited, then deleted elsewhere"), capturedAt: t0)

        await queue.flush(editor: makeEditor(server))

        XCTAssertEqual(session.verifyingReads, 1, "dropped only after a verified read found no row")
        XCTAssertNil(queue.edit(for: id), "a row that no longer exists can't take the edit — never retried")
        XCTAssertFalse(fileExists(queue, id))
    }

    /// The review's case: a token refresh fails and supabase-swift sends the anon key instead, so
    /// RLS makes the PATCH match zero rows although the item exists. That must never read as
    /// "deleted" — the verified read finds the row, and the note stays queued.
    func testAZeroRowAnswerFromAFallbackTokenNeverDropsTheEdit() async {
        let row = makeItem()
        let server = FakeRowServer(rows: [row])
        server.rlsHidesRows = true
        let owner = UUID()
        let session = FakeSession(signedIn: owner, server: server)
        let queue = makeQueue(userId: owner, session: session)
        queue.record(itemId: row.id, patch: ItemPatch(content: "my queued note"), capturedAt: t0)

        await queue.flush(editor: makeEditor(server))

        XCTAssertEqual(server.patches.count, 1, "the send went out and matched nothing")
        XCTAssertEqual(session.verifyingReads, 1)
        XCTAssertEqual(queue.edit(for: row.id)?.content?.value, "my queued note", "never discarded unsent")
        XCTAssertTrue(fileExists(queue, row.id))

        // The same for a queued location, whose current-attributes read comes back empty.
        var located = row.attributes
        located.location = CapturedLocation(label: "Lisbon", source: "manual")
        queue.record(itemId: row.id, patch: ItemPatch(attributes: located), capturedAt: t0.addingTimeInterval(1))
        await queue.flush(editor: makeEditor(server))
        XCTAssertNotNil(queue.edit(for: row.id)?.attributes)
    }

    /// No valid token right now (the refresh can't reach the server): nothing is sent — not even as
    /// anon — and nothing is concluded or counted.
    func testNoValidTokenMeansNothingIsSent() async {
        let row = makeItem()
        let server = FakeRowServer(rows: [row])
        let owner = UUID()
        let session = FakeSession(signedIn: owner, server: server)
        session.tokenError = URLError(.notConnectedToInternet)
        let queue = makeQueue(userId: owner, session: session)
        queue.record(itemId: row.id, patch: ItemPatch(title: "waiting"), capturedAt: t0)

        await queue.flush(editor: makeEditor(server))

        XCTAssertTrue(server.patches.isEmpty)
        XCTAssertEqual(queue.edit(for: row.id)?.title?.value, "waiting")
        XCTAssertEqual(queue.edit(for: row.id)?.attempts, 0)
        XCTAssertNil(queue.edit(for: row.id)?.nextAttemptAt)
    }

    /// After an account switch, a flush still around for the previous user must neither send under
    /// the new user's session (RLS would match nothing) nor drop the edit as "deleted".
    func testAFlushUnderAnotherAccountsSessionSendsNothingAndKeepsTheEdit() async {
        let row = makeItem()
        let server = FakeRowServer(rows: [row])
        let owner = UUID()
        let queue = makeQueue(userId: owner, session: FakeSession(signedIn: UUID(), server: server))
        queue.record(itemId: row.id, patch: ItemPatch(title: "the owner's edit"), capturedAt: t0)

        await queue.flush(editor: makeEditor(server))

        XCTAssertTrue(server.patches.isEmpty, "never sent under someone else's session")
        XCTAssertEqual(queue.edit(for: row.id)?.title?.value, "the owner's edit")
        XCTAssertEqual(queue.edit(for: row.id)?.attempts, 0)

        let signedOut = makeQueue(userId: owner, session: FakeSession(signedIn: nil))
        await signedOut.flush(editor: makeEditor(FakeRowServer(rows: [])))
        XCTAssertEqual(signedOut.edit(for: row.id)?.title?.value, "the owner's edit",
                       "signed out: kept for the owner's next session, not dropped as deleted")
    }

    // MARK: - Sheet start

    /// The review's case: an Ask citation opens the sheet on a raw server row. The sheet must start
    /// from the queued note (so a new edit builds on it) while diffing against the server's copy.
    func testASheetOpenedOnARawCitationRowStartsFromTheQueuedNote() {
        let queue = makeQueue()
        let raw = makeItem(content: "server's older note")
        queue.record(itemId: raw.id, patch: ItemPatch(content: "queued, undelivered note"), capturedAt: t0)

        let citation = queue.sheetStart(for: raw, serverRow: nil)
        XCTAssertEqual(citation.shown.content, "queued, undelivered note")
        XCTAssertEqual(citation.server, raw, "the diff baseline stays the server's copy")

        // A library card is already overlaid; the store supplies the server's copy.
        let card = queue.sheetStart(for: queue.overlay(raw), serverRow: raw)
        XCTAssertEqual(card.shown.content, "queued, undelivered note")
        XCTAssertEqual(card.server, raw)
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

    // MARK: - Re-journaling and the refusal budget (final wave B)

    /// The sheet re-journals everything unconfirmed on every dismiss and every trip to the
    /// background. Recording a value that is already queued must not count as a change — otherwise
    /// each app switch would reset the backoff of an edit the server keeps refusing.
    func testReJournalingAnUnchangedValueKeepsItsBackoff() async throws {
        let row = makeItem()
        let server = FakeRowServer(rows: [row])
        server.error = ServerRefusal()
        let clock = TestClock(t0)
        let userId = UUID()
        let queue = makeQueue(userId: userId, server: server, clock: clock)
        queue.record(itemId: row.id, patch: ItemPatch(title: "refused"), capturedAt: t0)
        await queue.flush(editor: makeEditor(server))
        let refused = try XCTUnwrap(queue.edit(for: row.id))
        XCTAssertEqual(refused.attempts, 1)
        XCTAssertEqual(refused.nextAttemptAt, t0.addingTimeInterval(30))

        clock.now = t0.addingTimeInterval(5)
        queue.record(itemId: row.id, patch: ItemPatch(title: "refused"), capturedAt: clock.now)   // dismiss journal

        XCTAssertEqual(queue.edit(for: row.id), refused, "nothing changed — not the value, backoff, count or revision")
        XCTAssertEqual(PendingEdits(userId: userId, directory: directory).edit(for: row.id), refused)
        await queue.flush(editor: makeEditor(server))
        XCTAssertEqual(server.patches.count, 1, "still backing off")
    }

    /// A genuinely new value is due at once AND gets a fresh refusal budget: it was never refused.
    func testAGenuinelyNewValueStartsAFreshRefusalBudget() async throws {
        let row = makeItem()
        let server = FakeRowServer(rows: [row])
        server.error = ServerRefusal()
        let clock = TestClock(t0)
        let queue = makeQueue(server: server, clock: clock)
        queue.record(itemId: row.id, patch: ItemPatch(title: "refused"), capturedAt: t0)
        let editor = makeEditor(server)
        for _ in 1...3 {
            await queue.flush(editor: editor)
            clock.now = clock.now.addingTimeInterval(7 * 60 * 60)
        }
        XCTAssertEqual(queue.edit(for: row.id)?.attempts, 3)

        queue.record(itemId: row.id, patch: ItemPatch(description: "a new field"), capturedAt: clock.now)

        let edit = try XCTUnwrap(queue.edit(for: row.id))
        XCTAssertEqual(edit.attempts, 0)
        XCTAssertNil(edit.nextAttemptAt)
        XCTAssertEqual(edit.title?.value, "refused", "the older value stays queued alongside it")
    }

    /// For a queued location only the location is ever applied, so a re-journaled blob whose other
    /// keys moved on (the server rewrote `media.transcript` meanwhile) is not a new value either.
    func testReJournalingTheSameLocationIsNotAChange() throws {
        let queue = makeQueue()
        let id = UUID()
        let location = CapturedLocation(label: "Lisbon", source: "manual")
        queue.record(itemId: id, patch: ItemPatch(attributes: ItemAttributes(location: location)), capturedAt: t0)
        let queued = try XCTUnwrap(queue.edit(for: id))

        let newerBlob = ItemAttributes(location: location,
                                       media: MediaAttributes(extra: ["transcript": .object(["status": .string("done")])]))
        queue.record(itemId: id, patch: ItemPatch(attributes: newerBlob), capturedAt: t0.addingTimeInterval(9))
        XCTAssertEqual(queue.edit(for: id), queued)

        let moved = CapturedLocation(label: "Porto", source: "manual")
        queue.record(itemId: id, patch: ItemPatch(attributes: ItemAttributes(location: moved)), capturedAt: t0.addingTimeInterval(10))
        XCTAssertEqual(queue.edit(for: id)?.attributes?.value.location, moved)
        XCTAssertEqual(queue.edit(for: id)?.revision, queued.revision + 1)
    }

    // MARK: - Verification (final wave B)

    /// A zero-row answer whose verifying read gets no clear answer (a 5xx, a garbled body):
    /// nothing may be concluded — the edit is kept exactly as it was, neither discarded nor counted.
    func testAnUnverifiableZeroRowAnswerKeepsTheEditUntouched() async throws {
        let row = makeItem()
        let server = FakeRowServer(rows: [row])
        server.rlsHidesRows = true
        let owner = UUID()
        let session = FakeSession(signedIn: owner, server: server)
        session.verifyingReadError = PendingEditsSessionError.unverifiable
        let queue = makeQueue(userId: owner, session: session)
        queue.record(itemId: row.id, patch: ItemPatch(content: "keep me"), capturedAt: t0)
        let before = try XCTUnwrap(queue.edit(for: row.id))

        await queue.flush(editor: makeEditor(server))

        XCTAssertEqual(server.patches.count, 1)
        XCTAssertEqual(session.verifyingReads, 1)
        XCTAssertEqual(queue.edit(for: row.id), before, "not discarded, not counted, not backed off")
        XCTAssertTrue(fileExists(queue, row.id))
    }

    func testRowExistsAsksPostgRESTWithExactlyTheVerifiedToken() async throws {
        let itemId = UUID()
        let session = SupabasePendingEditsSession(urlSession: StubbedHTTP.session { _ in
            (200, Data(#"[{"id":"\#(itemId.uuidString.lowercased())"}]"#.utf8))
        })

        let exists = try await session.rowExists(itemId: itemId, accessToken: "verified-jwt")

        XCTAssertTrue(exists)
        let request = try XCTUnwrap(StubbedHTTP.requests.first)
        let url = try XCTUnwrap(request.url)
        XCTAssertEqual(url.host, StashConfig.supabaseURL.host)
        XCTAssertEqual(url.path, "/rest/v1/items")
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(query.first { $0.name == "id" }?.value, "eq.\(itemId.uuidString.lowercased())")
        XCTAssertEqual(query.first { $0.name == "select" }?.value, "id")
        XCTAssertEqual(request.httpMethod ?? "GET", "GET")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer verified-jwt")
        XCTAssertEqual(request.value(forHTTPHeaderField: "apikey"), StashConfig.supabaseAnonKey)
    }

    func testRowExistsAnswersOnlyFromAClearReply() async throws {
        let itemId = UUID()
        let gone = SupabasePendingEditsSession(urlSession: StubbedHTTP.session { _ in (200, Data("[]".utf8)) })
        let goneAnswer = try await gone.rowExists(itemId: itemId, accessToken: "t")
        XCTAssertFalse(goneAnswer, "200 [] — the only reply that means \"no such row\"")

        for (status, body) in [(401, #"{"message":"JWT expired"}"#), (503, ""), (200, "<html>proxy</html>")] {
            let session = SupabasePendingEditsSession(urlSession: StubbedHTTP.session { _ in (status, Data(body.utf8)) })
            do {
                _ = try await session.rowExists(itemId: itemId, accessToken: "t")
                XCTFail("HTTP \(status) '\(body)' must not be read as an answer")
            } catch {
                XCTAssertEqual(error as? PendingEditsSessionError, .unverifiable, "HTTP \(status)")
            }
        }
    }

    // MARK: - Direct location saves (final wave B)

    /// The detail sheet's own location save goes onto the server's CURRENT attributes, never the
    /// sheet's copy: keys production wrote meanwhile (the transcription job's `media.transcript`,
    /// enrichment's `enrichment.*`) are not rolled back.
    func testSaveLocationReplacesOnlyTheLocationOnTheServersCurrentAttributes() async throws {
        let stale = ItemAttributes(media: MediaAttributes(durationS: 30, extra: ["transcript": .object(["status": .string("pending")])]))
        let row = makeItem(attributes: stale)
        let server = FakeRowServer(rows: [row])
        let done = JSONValue.object(["status": .string("done"), "chunks_done": .number(1)])
        let enrichment = JSONValue.object(["status": .string("complete"),
                                           "protected_fields": .object(["title": .bool(true)])])
        server.update(row.id) {
            $0.attributes.media?.extra["transcript"] = done
            $0.attributes.media?.extra["kind"] = .string("voice_note")
            $0.attributes.extra["enrichment"] = enrichment
        }
        let lisbon = CapturedLocation(label: "Lisbon", source: "manual")

        let saved = try await makeEditor(server).saveLocation(itemId: row.id, location: lisbon)

        let sent = try XCTUnwrap(server.patches.first?.1)
        XCTAssertEqual(sent, ItemPatch(attributes: server.row(row.id)?.attributes), "one attributes-only PATCH")
        XCTAssertEqual(saved.attributes.location, lisbon)
        XCTAssertEqual(saved.attributes.media?.extra["transcript"], done, "the server's newer transcript status survives")
        XCTAssertEqual(saved.attributes.media?.extra["kind"], .string("voice_note"))
        XCTAssertEqual(saved.attributes.extra["enrichment"], enrichment, "enrichment state survives")
        XCTAssertEqual(saved.attributes.media?.durationS, 30)

        // Removing it works the same way.
        let cleared = try await makeEditor(server).saveLocation(itemId: row.id, location: nil)
        XCTAssertNil(cleared.attributes.location)
        XCTAssertEqual(cleared.attributes.extra["enrichment"], enrichment)
    }

    func testSaveLocationOnAnUnreadableRowFailsWithoutWriting() async {
        let row = makeItem()
        let server = FakeRowServer(rows: [row])
        server.rlsHidesRows = true
        do {
            _ = try await makeEditor(server).saveLocation(itemId: row.id,
                                                         location: CapturedLocation(label: "Lisbon", source: "manual"))
            XCTFail("expected itemNotFound")
        } catch {
            XCTAssertEqual(error as? ItemEditorError, .itemNotFound)
        }
        XCTAssertTrue(server.patches.isEmpty, "no blind whole-blob write when the current one can't be read")
    }
}
