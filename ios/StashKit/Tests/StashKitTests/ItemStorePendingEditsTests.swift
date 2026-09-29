import XCTest
@testable import StashKit

/// Records what a test flusher saw, in order (`@MainActor`, so the flusher closure can append).
@MainActor
final class FlushLog {
    var events: [String] = []
}

/// Plan 15 (H5): `ItemStore` shows queued detail-sheet edits over the server's rows until they're
/// confirmed, keeps the server's own version reachable for the detail sheet, caches only the
/// server's version, and flushes the queue before each refresh fetches.
@MainActor
final class ItemStorePendingEditsTests: XCTestCase {
    private var root: URL!
    private let base = Date(timeIntervalSince1970: 1_790_000_000)

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ItemStorePendingEditsTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func row(_ minutesAgo: Int, title: String? = nil) -> Item {
        Item(id: UUID(), type: .text, title: title ?? "r\(minutesAgo)", content: "note \(minutesAgo)", url: nil,
             filePath: nil, description: nil, summary: nil, pageBody: nil, supplementalNote: nil,
             mimeType: nil, isPublic: false, createdAt: base.addingTimeInterval(Double(-60 * minutesAgo)))
    }

    private func makeQueue(_ userId: UUID) -> PendingEdits {
        PendingEdits(userId: userId, directory: root.appendingPathComponent("pending", isDirectory: true),
                     session: FakeSession(signedIn: userId))
    }

    private var cache: ItemCache { ItemCache(directory: root.appendingPathComponent("cache", isDirectory: true)) }

    func testInstallLaysQueuedEditsOverTheCachedPage() {
        let userId = UUID()
        let a = row(0, title: "Server title")
        let b = row(1)
        cache.save([a, b], userId: userId)
        let queue = makeQueue(userId)
        queue.record(itemId: a.id, patch: ItemPatch(title: "Typed offline"), capturedAt: base)
        let store = ItemStore(userId: userId, fetcher: FakeItemsServer(rows: [], pageSize: 50), pageSize: 50, cache: cache)

        store.installPendingEdits(queue) { _ in }

        XCTAssertEqual(store.item(withId: a.id)?.title, "Typed offline", "a relaunch shows the user's own edit at once")
        XCTAssertEqual(store.serverRow(withId: a.id)?.title, "Server title", "the server's version stays reachable")
        XCTAssertEqual(store.serverRow(withId: b.id), b)
        XCTAssertNil(store.serverRow(withId: UUID()))
    }

    func testRowsNeverRevertToTheServersCopyWhileAnEditIsQueued() async {
        let userId = UUID()
        let a = row(0, title: "Server title")
        let server = FakeItemsServer(rows: [a, row(1)], pageSize: 50)
        let store = ItemStore(userId: userId, fetcher: server, pageSize: 50)
        let queue = makeQueue(userId)
        store.installPendingEdits(queue) { _ in }              // offline: nothing is ever confirmed
        await store.refresh()
        queue.record(itemId: a.id, patch: ItemPatch(title: "Mine", content: "my note"), capturedAt: base)
        XCTAssertEqual(store.item(withId: a.id)?.title, "Mine", "recording updates the shown row at once")

        await store.refresh()                                  // page 1 brings the server's copy
        XCTAssertEqual(store.item(withId: a.id)?.title, "Mine")
        XCTAssertEqual(store.item(withId: a.id)?.content, "my note")

        var batch = ItemChangeBatch()
        batch.add(.upsert(a.id))
        await store.applyRemoteChanges(batch)                  // a realtime re-read, same story
        XCTAssertEqual(store.item(withId: a.id)?.title, "Mine")
        XCTAssertEqual(store.serverRow(withId: a.id)?.title, "Server title")
    }

    func testRefreshFlushesBeforeItFetches() async {
        let userId = UUID()
        let a = row(0)
        let server = FakeItemsServer(rows: [a], pageSize: 50)
        let store = ItemStore(userId: userId, fetcher: server, pageSize: 50)
        let queue = makeQueue(userId)
        let log = FlushLog()
        store.installPendingEdits(queue) { _ in log.events.append("flush with \(server.pageCalls) page reads") }

        await store.refresh()
        XCTAssertEqual(log.events, [], "an empty queue sends nothing")

        queue.record(itemId: a.id, patch: ItemPatch(title: "queued"), capturedAt: base)
        await store.refresh()
        XCTAssertEqual(log.events, ["flush with 1 page reads"], "the flush ran before this refresh read page 1")
        XCTAssertEqual(server.pageCalls, 2)
    }

    func testAStalledFlushNeverHoldsTheRefresh() async {
        let userId = UUID()
        let a = row(0, title: "Server title")
        let server = FakeItemsServer(rows: [a, row(1)], pageSize: 50)
        let store = ItemStore(userId: userId, fetcher: server, pageSize: 50, pendingFlushGrace: .milliseconds(50))
        let queue = makeQueue(userId)
        store.installPendingEdits(queue) { _ in try? await Task.sleep(for: .seconds(1)) }   // a PATCH on a dead link
        queue.record(itemId: a.id, patch: ItemPatch(title: "Mine"), capturedAt: base)

        let started = Date()
        await store.refresh()

        XCTAssertLessThan(Date().timeIntervalSince(started), 0.8, "page 1 was read without waiting out the PATCH")
        XCTAssertEqual(store.items.count, 2)
        XCTAssertEqual(store.item(withId: a.id)?.title, "Mine", "the overlay covers the gap")
    }

    func testAFlushedEditBecomesTheServersRow() async {
        let userId = UUID()
        let a = row(0, title: "Server title")
        let store = ItemStore(userId: userId, fetcher: FakeItemsServer(rows: [a], pageSize: 50), pageSize: 50)
        await store.refresh()
        let patchServer = FakeRowServer(rows: [a])
        let editor = ItemEditor(patcher: patchServer, refresher: EmbeddingRefresher(syncer: RecordingSyncer()),
                                writeQueue: ItemWriteQueue())
        let queue = makeQueue(userId)
        store.installPendingEdits(queue) { apply in await queue.flush(editor: editor, apply: apply) }
        queue.record(itemId: a.id, patch: ItemPatch(title: "Offline title"), capturedAt: base)

        await store.flushPendingEdits()

        XCTAssertTrue(queue.isEmpty)
        XCTAssertEqual(store.item(withId: a.id)?.title, "Offline title")
        XCTAssertEqual(store.serverRow(withId: a.id)?.title, "Offline title", "no overlay left — it's the server's now")
    }

    func testAConfirmedEditKeepsWhatTheRowShows() {
        let userId = UUID()
        let a = row(0, title: "Server title")
        cache.save([a], userId: userId)
        let store = ItemStore(userId: userId, fetcher: FakeItemsServer(rows: [], pageSize: 50), pageSize: 50, cache: cache)
        let queue = makeQueue(userId)
        store.installPendingEdits(queue) { _ in }
        queue.record(itemId: a.id, patch: ItemPatch(title: "Mine"), capturedAt: base)

        // Confirmed by a PATCH whose response went to another store (e.g. a citation sheet's).
        queue.confirm(itemId: a.id, patch: ItemPatch(title: "Mine"), capturedAt: base)

        XCTAssertEqual(store.item(withId: a.id)?.title, "Mine", "never flashes back to the pre-edit copy")
        XCTAssertEqual(store.serverRow(withId: a.id)?.title, "Mine")
    }

    func testTheCacheHoldsTheServersCopyNotTheOverlay() async {
        let userId = UUID()
        let a = row(0, title: "Server title")
        let store = ItemStore(userId: userId, fetcher: FakeItemsServer(rows: [a], pageSize: 50), pageSize: 50, cache: cache)
        let queue = makeQueue(userId)
        store.installPendingEdits(queue) { _ in }
        queue.record(itemId: a.id, patch: ItemPatch(title: "Mine"), capturedAt: base)
        await store.refresh()
        XCTAssertEqual(store.item(withId: a.id)?.title, "Mine")

        await store.flushCacheWrites()

        XCTAssertEqual(cache.load(userId: userId).first?.title, "Server title",
                       "queued values live in their own queue and are laid over again at launch")
    }
}
