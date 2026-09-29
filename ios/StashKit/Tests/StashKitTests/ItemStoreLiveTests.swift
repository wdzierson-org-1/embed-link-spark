import XCTest
@testable import StashKit

/// In-memory stand-in for the `items` table: pages are served newest-first with the same
/// `created_at < cursor` / LIMIT semantics as `SupabaseItemsFetcher`, and rows can be read by id.
/// `pageGate`, when set, suspends `fetchPage` until the test releases it.
final class FakeItemsServer: ItemsFetching, @unchecked Sendable {
    private let lock = NSLock()
    private var _rows: [Item]
    let pageSize: Int
    private(set) var pageCalls = 0
    private(set) var fetchItemsCalls: [Set<UUID>] = []
    private(set) var existenceCalls: [Set<UUID>] = []
    var failFetchItems = false
    var gatePages = false
    private var gates: [CheckedContinuation<Void, Never>] = []

    init(rows: [Item], pageSize: Int) {
        _rows = rows
        self.pageSize = pageSize
    }

    var rows: [Item] {
        get { lock.withLock { _rows } }
        set { lock.withLock { _rows = newValue } }
    }

    func fetchPage(userId: UUID, before: Date?, types: [ItemType]?, tagIds: [UUID]) async throws -> [Item] {
        let shouldGate = lock.withLock { () -> Bool in
            pageCalls += 1
            return gatePages
        }
        // Snapshot BEFORE suspending — the response reflects the table when the request "ran".
        let snapshot = rows
            .filter { types == nil || types!.contains($0.type) }
            .filter { before == nil || $0.createdAt < before! }
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(pageSize)
        if shouldGate {
            await withCheckedContinuation { continuation in lock.withLock { gates.append(continuation) } }
        }
        // Like URLSession: a request whose task was cancelled fails with a cancellation error.
        try Task.checkCancellation()
        return Array(snapshot)
    }

    func releasePage() {
        let gate = lock.withLock { gates.isEmpty ? nil : gates.removeFirst() }
        gate?.resume()
    }

    var pendingPageCount: Int { lock.withLock { gates.count } }

    func fetchDetail(id: UUID) async throws -> Item { fatalError("unused") }

    func fetchItems(ids: [UUID]) async throws -> [Item] {
        let fail = lock.withLock { () -> Bool in
            fetchItemsCalls.append(Set(ids))
            return failFetchItems
        }
        if fail { throw StubFetchError() }
        let wanted = Set(ids)
        return rows.filter { wanted.contains($0.id) }
    }

    func fetchExistingIds(_ ids: [UUID]) async throws -> Set<UUID> {
        lock.withLock { existenceCalls.append(Set(ids)) }
        return Set(rows.map(\.id)).intersection(ids)
    }
}

@MainActor
final class ItemStoreLiveTests: XCTestCase {
    private var cacheDirectory: URL!
    private let base = Date(timeIntervalSince1970: 1_790_000_000)

    override func setUpWithError() throws {
        cacheDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ItemStoreLiveTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: cacheDirectory)
    }

    /// `minutesAgo` 0 is the newest row.
    private func row(_ minutesAgo: Int, title: String? = nil, type: ItemType = .text) -> Item {
        Item(id: UUID(), type: type, title: title ?? "r\(minutesAgo)", content: nil, url: nil,
             filePath: nil, description: nil, summary: nil, pageBody: nil, supplementalNote: nil,
             mimeType: nil, isPublic: false, createdAt: base.addingTimeInterval(Double(-60 * minutesAgo)))
    }

    private func waitUntil(_ condition: () -> Bool, timeout: TimeInterval = 2) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline { try? await Task.sleep(for: .milliseconds(5)) }
    }

    // MARK: - Cache hydrate / write

    func testInitHydratesSynchronouslyFromTheDiskCache() {
        let userId = UUID()
        let cache = ItemCache(directory: cacheDirectory)
        let cached = (0..<3).map { row($0) }
        cache.save(cached, userId: userId)

        let store = ItemStore(userId: userId, fetcher: FakeItemsServer(rows: [], pageSize: 50), pageSize: 50, cache: cache)

        XCTAssertEqual(store.items, cached, "cards must be available before any await")
        XCTAssertTrue(store.isShowingCachedPage)
        XCTAssertFalse(store.hasMore, "a short cached page means the whole library was cached")
        XCTAssertTrue(store.needsRefresh, "a cached page is never a substitute for a refresh")
    }

    func testRefreshWritesTheFirstPageToTheCache() async {
        let userId = UUID()
        let cache = ItemCache(directory: cacheDirectory)
        let server = FakeItemsServer(rows: (0..<60).map { row($0) }, pageSize: 50)
        let store = ItemStore(userId: userId, fetcher: server, pageSize: 50, cache: cache)

        await store.refresh()
        await store.loadMoreIfNeeded(current: store.items.last!)
        XCTAssertEqual(store.items.count, 60)
        await store.flushCacheWrites()

        XCTAssertEqual(cache.load(userId: userId).map(\.id), Array(store.items.prefix(50)).map(\.id),
                       "only the first page is cached")
        XCTAssertFalse(store.isShowingCachedPage)
    }

    func testCloseStopsCacheWritesSoAPurgeSticks() async {
        let userId = UUID()
        let cache = ItemCache(directory: cacheDirectory)
        let server = FakeItemsServer(rows: (0..<3).map { row($0) }, pageSize: 50)
        let store = ItemStore(userId: userId, fetcher: server, pageSize: 50, cache: cache)
        await store.refresh()
        await store.close()
        cache.deleteAll()

        store.upsert([row(-1)])                       // would normally schedule a write
        await store.flushCacheWrites()
        try? await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(cache.load(userId: userId), [], "a closed store must never re-create the purged file")
    }

    // MARK: - Merge refresh

    func testRefreshMergesPageOneWithoutDroppingOlderPages() async {
        let server = FakeItemsServer(rows: (0..<120).map { row($0) }, pageSize: 50)
        let store = ItemStore(userId: UUID(), fetcher: server, pageSize: 50)
        await store.refresh()
        await store.loadMoreIfNeeded(current: store.items.last!)
        XCTAssertEqual(store.items.count, 100)

        let newest = row(-5, title: "brand new")
        let deleted = server.rows[10]
        server.rows = [newest] + server.rows.filter { $0.id != deleted.id }

        await store.refresh()

        XCTAssertEqual(store.items.first?.id, newest.id, "new row merged in at the top")
        XCTAssertFalse(store.items.contains { $0.id == deleted.id }, "row missing from page 1's window was deleted")
        XCTAssertEqual(store.items.count, 100, "older pages stay loaded (+1 new −1 deleted)")
        XCTAssertEqual(store.items.map(\.createdAt), store.items.map(\.createdAt).sorted(by: >))
        XCTAssertTrue(store.hasMore)
    }

    func testRefreshRetiresRowsDeletedBeyondPageOne() async {
        let server = FakeItemsServer(rows: (0..<120).map { row($0) }, pageSize: 50)
        let store = ItemStore(userId: UUID(), fetcher: server, pageSize: 50)
        await store.refresh()
        await store.loadMoreIfNeeded(current: store.items.last!)
        let deepRow = store.items[75]
        server.rows.removeAll { $0.id == deepRow.id }

        await store.refresh()

        XCTAssertFalse(store.items.contains { $0.id == deepRow.id })
        XCTAssertEqual(store.items.count, 99)
        XCTAssertEqual(server.existenceCalls.last?.count, 50, "one ids-only check over the rows beyond page 1")
    }

    func testCompleteFirstPageReplacesTheWindow() async {
        let server = FakeItemsServer(rows: (0..<10).map { row($0) }, pageSize: 50)
        let store = ItemStore(userId: UUID(), fetcher: server, pageSize: 50)
        await store.refresh()
        server.rows.removeFirst(2)

        await store.refresh()

        XCTAssertEqual(store.items.map(\.id), server.rows.map(\.id))
        XCTAssertFalse(store.hasMore)
    }

    func testMergeKeepsLoadedPageBodyForListRows() async {
        var detail = row(1)
        let server = FakeItemsServer(rows: [row(0), detail], pageSize: 50)
        let store = ItemStore(userId: UUID(), fetcher: server, pageSize: 50)
        await store.refresh()
        detail.pageBody = "full text"
        store.applyDetail(detail)

        await store.refresh()
        XCTAssertEqual(store.item(withId: detail.id)?.pageBody, "full text",
                       "list reads never select page_body — nil means not fetched, not cleared")
    }

    /// Plan 15 review: a realtime change can mean a new `page_body` (re-scrape / re-transcription),
    /// which list re-reads never return — the loaded copy is dropped so the next open fetches it.
    func testARealtimeChangeDropsTheLoadedPageBody() async {
        var detail = row(1)
        let server = FakeItemsServer(rows: [row(0), detail], pageSize: 50)
        let store = ItemStore(userId: UUID(), fetcher: server, pageSize: 50)
        await store.refresh()
        detail.pageBody = "the old transcript"
        store.applyDetail(detail)

        var batch = ItemChangeBatch()
        batch.add(.upsert(detail.id))
        await store.applyRemoteChanges(batch)

        XCTAssertNil(store.item(withId: detail.id)?.pageBody, "the next detail open must read it fresh")
    }

    /// …and a refresh keeps it only for rows that didn't change.
    func testRefreshKeepsPageBodyOnlyForUnchangedRows() async {
        var unchanged = row(0)
        var changed = row(1)
        let server = FakeItemsServer(rows: [unchanged, changed], pageSize: 50)
        let store = ItemStore(userId: UUID(), fetcher: server, pageSize: 50)
        await store.refresh()
        unchanged.pageBody = "still good"
        changed.pageBody = "stale"
        store.applyDetail(unchanged)
        store.applyDetail(changed)
        server.rows = server.rows.map { $0.id == changed.id ? { var r = $0; r.summary = "re-scraped"; return r }($0) : $0 }

        await store.refresh()

        XCTAssertEqual(store.item(withId: unchanged.id)?.pageBody, "still good")
        XCTAssertNil(store.item(withId: changed.id)?.pageBody)
        XCTAssertEqual(store.item(withId: changed.id)?.summary, "re-scraped")
    }

    func testInFlightRefreshNeverOverwritesNewerLocalChanges() async {
        let original = row(1, title: "old title")
        let doomed = row(2)
        let server = FakeItemsServer(rows: [row(0), original, doomed], pageSize: 50)
        let store = ItemStore(userId: UUID(), fetcher: server, pageSize: 50)
        await store.refresh()

        server.gatePages = true
        let refresh = Task { await store.refresh() }   // snapshot taken now: old title, doomed present
        await waitUntil { server.pendingPageCount == 1 }

        var renamed = original
        renamed.title = "new title"
        server.rows = server.rows.map { $0.id == original.id ? renamed : $0 }.filter { $0.id != doomed.id }
        await store.applyRemoteChanges({ var b = ItemChangeBatch(); b.add(.upsert(original.id)); return b }())
        store.remove(ids: [doomed.id])

        server.releasePage()
        await refresh.value

        XCTAssertEqual(store.item(withId: original.id)?.title, "new title", "the stale snapshot lost to the realtime row")
        XCTAssertNil(store.item(withId: doomed.id), "a stale snapshot can't resurrect a removed row")
    }

    func testStaleRefreshResultIsDroppedByTheGenerationToken() async {
        let server = FakeItemsServer(rows: [row(5, title: "stale")], pageSize: 50)
        let store = ItemStore(userId: UUID(), fetcher: server, pageSize: 50)
        server.gatePages = true
        let first = Task { await store.refresh() }      // will answer "stale"
        await waitUntil { server.pendingPageCount == 1 }
        server.rows = [row(0, title: "fresh")]
        let second = Task { await store.refresh() }     // will answer "fresh"
        await waitUntil { server.pendingPageCount == 2 }

        // Release in order: the first (stale) request's gate opens first but its generation is old.
        server.releasePage()
        server.releasePage()
        await first.value
        await second.value

        XCTAssertEqual(store.items.map(\.title), ["fresh"])
    }

    func testACallerGoingAwayNeitherAbortsTheRefreshNorReportsAnError() async {
        let server = FakeItemsServer(rows: [row(0, title: "fresh")], pageSize: 50)
        let store = ItemStore(userId: UUID(), fetcher: server, pageSize: 50)
        server.gatePages = true
        let caller = Task { await store.refresh() }      // e.g. LibraryView's `.task`
        await waitUntil { server.pendingPageCount == 1 }
        caller.cancel()                                  // the user switched tabs
        server.releasePage()
        await caller.value

        XCTAssertEqual(store.items.map(\.title), ["fresh"])
        XCTAssertNil(store.loadError)
        XCTAssertFalse(store.needsRefresh)
    }

    func testFilterChangeReplacesTheWindowInsteadOfMerging() async {
        let rows = (0..<120).map { row($0, type: $0 % 2 == 0 ? .text : .link) }
        let server = FakeItemsServer(rows: rows, pageSize: 50)
        let store = ItemStore(userId: UUID(), fetcher: server, pageSize: 50)
        await store.refresh()
        await store.loadMoreIfNeeded(current: store.items.last!)

        store.typeFilter = .links
        await store.refresh()

        XCTAssertEqual(store.items.count, 50)
        XCTAssertTrue(store.items.allSatisfy { $0.type == .link })
    }

    // MARK: - Staleness

    func testRefreshIfStaleHonoursThirtySeconds() async {
        final class Clock: @unchecked Sendable { var now = Date(timeIntervalSince1970: 0) }
        let clock = Clock()
        let server = FakeItemsServer(rows: [row(0)], pageSize: 50)
        let store = ItemStore(userId: UUID(), fetcher: server, pageSize: 50, now: { clock.now })

        await store.refreshIfStale()
        XCTAssertEqual(server.pageCalls, 1, "never refreshed → stale")
        clock.now = clock.now.addingTimeInterval(29)
        await store.refreshIfStale()
        XCTAssertEqual(server.pageCalls, 1, "29 s later → still fresh")
        clock.now = clock.now.addingTimeInterval(1)
        await store.refreshIfStale()
        XCTAssertEqual(server.pageCalls, 2, "30 s → stale again")
    }

    // MARK: - Incremental (realtime)

    func testRemoteChangesRefetchOnlyTheChangedIds() async {
        let server = FakeItemsServer(rows: (0..<5).map { row($0) }, pageSize: 50)
        let store = ItemStore(userId: UUID(), fetcher: server, pageSize: 50)
        await store.refresh()
        let pageCallsBefore = server.pageCalls

        var edited = server.rows[2]
        edited.title = "edited elsewhere"
        let inserted = row(-1, title: "inserted elsewhere")
        server.rows = [inserted] + server.rows.map { $0.id == edited.id ? edited : $0 }
        var batch = ItemChangeBatch()
        batch.add(.upsert(edited.id))
        batch.add(.upsert(inserted.id))

        await store.applyRemoteChanges(batch)

        XCTAssertEqual(server.fetchItemsCalls, [[edited.id, inserted.id]])
        XCTAssertEqual(server.pageCalls, pageCallsBefore, "no page-1 re-query")
        XCTAssertEqual(store.items.first?.id, inserted.id)
        XCTAssertEqual(store.item(withId: edited.id)?.title, "edited elsewhere")
        XCTAssertEqual(store.items.count, 6)
    }

    func testRemoteDeletesAndVanishedRowsDropOut() async {
        let server = FakeItemsServer(rows: (0..<5).map { row($0) }, pageSize: 50)
        let store = ItemStore(userId: UUID(), fetcher: server, pageSize: 50)
        await store.refresh()
        let deleted = server.rows[0], vanished = server.rows[3]
        server.rows.removeAll { $0.id == deleted.id || $0.id == vanished.id }
        var batch = ItemChangeBatch()
        batch.add(.delete(deleted.id))
        batch.add(.upsert(vanished.id))   // updated, then deleted before we re-read it

        await store.applyRemoteChanges(batch)

        XCTAssertEqual(store.items.count, 3)
        XCTAssertNil(store.item(withId: deleted.id))
        XCTAssertNil(store.item(withId: vanished.id))
    }

    func testFailedReReadMarksTheStoreStaleInsteadOfShowingAnError() async {
        let server = FakeItemsServer(rows: [row(0)], pageSize: 50)
        let store = ItemStore(userId: UUID(), fetcher: server, pageSize: 50)
        await store.refresh()
        XCTAssertFalse(store.needsRefresh)
        server.failFetchItems = true
        var batch = ItemChangeBatch()
        batch.add(.upsert(server.rows[0].id))

        await store.applyRemoteChanges(batch)

        XCTAssertTrue(store.needsRefresh)
        XCTAssertNil(store.loadError)
    }

    func testLiveUpdatesApplyBatchesFromTheObserver() async {
        struct OneShotObserver: ItemChangeObserving {
            let batch: ItemChangeBatch
            func observeItemChanges(userId: UUID, onBatch: @escaping @Sendable (ItemChangeBatch) async -> Void) async {
                await onBatch(batch)
            }
        }
        let server = FakeItemsServer(rows: [row(1)], pageSize: 50)
        let store = ItemStore(userId: UUID(), fetcher: server, pageSize: 50)
        await store.refresh()
        let inserted = row(0)
        server.rows.insert(inserted, at: 0)
        var batch = ItemChangeBatch()
        batch.add(.upsert(inserted.id))

        await store.runLiveUpdates(changes: OneShotObserver(batch: batch))

        XCTAssertEqual(store.items.first?.id, inserted.id)
    }

    func testCapturedItemsShowUpImmediatelyWithoutARefresh() async {
        struct QuietFeed: ItemChangeObserving {
            func observeItemChanges(userId: UUID, onBatch: @escaping @Sendable (ItemChangeBatch) async -> Void) async {
                while !Task.isCancelled { try? await Task.sleep(for: .milliseconds(10)) }
            }
        }
        let center = NotificationCenter()
        let userId = UUID()
        let server = FakeItemsServer(rows: [row(1)], pageSize: 50)
        let store = ItemStore(userId: userId, fetcher: server, pageSize: 50)
        await store.refresh()
        let pageCalls = server.pageCalls
        let live = Task { await store.runLiveUpdates(changes: QuietFeed(), notifications: center) }
        try? await Task.sleep(for: .milliseconds(50))    // let both feeds subscribe

        let captured = row(0, title: "just captured")
        center.post(name: .stashItemCaptured, object: nil,
                     userInfo: ["item": captured, "duplicate": false, "userId": userId])
        await waitUntil { store.items.first?.id == captured.id }
        // An idempotent replay of the same capture posts the same row again — still one card.
        center.post(name: .stashItemCaptured, object: nil,
                     userInfo: ["item": captured, "duplicate": true, "userId": userId])
        // Another account's capture (a late drain after an account switch) and an untagged one
        // (an older poster) never reach this user's grid.
        center.post(name: .stashItemCaptured, object: nil,
                     userInfo: ["item": row(-1, title: "someone else's"), "duplicate": false, "userId": UUID()])
        center.post(name: .stashItemCaptured, object: nil,
                     userInfo: ["item": row(-2, title: "untagged"), "duplicate": false])
        try? await Task.sleep(for: .milliseconds(60))

        XCTAssertEqual(store.items.map(\.id), [captured.id, server.rows[0].id])
        XCTAssertEqual(server.pageCalls, pageCalls, "no refresh needed")
        live.cancel()
        await live.value                                  // both feeds end with the task
    }

    /// Coordinator follow-up (View-tab review): a capture is shown only for its own user, and only
    /// if the row isn't there yet — the capture-time snapshot never overwrites a newer row.
    func testCapturedItemIsInsertIfAbsentForItsOwnUserOnly() async {
        let userId = UUID()
        let enriched = row(0, title: "Enriched title")
        let server = FakeItemsServer(rows: [enriched, row(1)], pageSize: 50)
        let store = ItemStore(userId: userId, fetcher: server, pageSize: 50)
        await store.refresh()

        var captureSnapshot = enriched
        captureSnapshot.title = nil                     // what the capture endpoint returned earlier
        store.applyCaptured(captureSnapshot, ownerId: userId)
        XCTAssertEqual(store.item(withId: enriched.id)?.title, "Enriched title",
                       "a capture-time snapshot must never overwrite the newer row already shown")

        store.applyCaptured(row(-1, title: "other account"), ownerId: UUID())
        store.applyCaptured(row(-2, title: "no owner"), ownerId: nil)
        XCTAssertEqual(store.items.count, 2, "captures for another (or an unknown) user are ignored")

        let fresh = row(-3, title: "mine")
        store.applyCaptured(fresh, ownerId: userId)
        XCTAssertEqual(store.items.first?.id, fresh.id, "this user's new capture shows at once")
    }

    /// Coordinator follow-up (View-tab review): the launch cache never carries `page_body`.
    func testCacheNeverStoresPageBody() async {
        let userId = UUID()
        let cache = ItemCache(directory: cacheDirectory)
        var opened = row(0)
        let server = FakeItemsServer(rows: [opened, row(1)], pageSize: 50)
        let store = ItemStore(userId: userId, fetcher: server, pageSize: 50, cache: cache)
        await store.refresh()
        opened.pageBody = String(repeating: "article text ", count: 2_000)
        store.applyDetail(opened)
        XCTAssertNotNil(store.item(withId: opened.id)?.pageBody, "the session keeps it in memory")

        await store.flushCacheWrites()

        let cached = cache.load(userId: userId)
        XCTAssertEqual(cached.map(\.id), store.items.map(\.id))
        XCTAssertTrue(cached.allSatisfy { $0.pageBody == nil }, "page_body must never be written to the cache")
    }

    func testUpsertPlacesRowsByDateAndIgnoresRowsOlderThanTheWindow() async {
        let server = FakeItemsServer(rows: (0..<60).map { row($0 * 2) }, pageSize: 50)
        let store = ItemStore(userId: UUID(), fetcher: server, pageSize: 50)
        await store.refresh()
        XCTAssertTrue(store.hasMore)

        let middle = row(3)                              // between r2 and r4
        let tooOld = row(500)                            // older than the loaded window
        store.upsert([middle, tooOld])

        XCTAssertEqual(store.items.firstIndex { $0.id == middle.id }, 2)
        XCTAssertNil(store.item(withId: tooOld.id), "it will arrive with its own page")
    }

    // MARK: - Search rows

    func testEnsureRowsKeepsHitsOutsideTheWindowResolvableAndLive() async {
        let server = FakeItemsServer(rows: (0..<120).map { row($0) }, pageSize: 50)
        let store = ItemStore(userId: UUID(), fetcher: server, pageSize: 50)
        await store.refresh()
        let deep = server.rows[100]

        await store.ensureRows(ids: [deep.id, store.items[0].id])

        XCTAssertEqual(server.fetchItemsCalls, [[deep.id]], "only unknown ids are read")
        XCTAssertEqual(store.items.count, 50, "a detached hit is never spliced into the window")
        XCTAssertEqual(store.item(withId: deep.id), deep)

        var edited = deep
        edited.title = "edited in the detail sheet"
        store.applyDetail(edited)
        XCTAssertEqual(store.item(withId: deep.id)?.title, "edited in the detail sheet")

        // Deleted elsewhere → the next refresh's existence check retires it.
        server.rows.removeAll { $0.id == deep.id }
        await store.refresh()
        XCTAssertNil(store.item(withId: deep.id))
    }

    func testDetachedRowJoinsTheWindowWhenItsPageLoads() async {
        let server = FakeItemsServer(rows: (0..<80).map { row($0) }, pageSize: 50)
        let store = ItemStore(userId: UUID(), fetcher: server, pageSize: 50)
        await store.refresh()
        let deep = server.rows[60]
        await store.ensureRows(ids: [deep.id])
        XCTAssertNotNil(store.detachedItems[deep.id])

        await store.loadMoreIfNeeded(current: store.items.last!)

        XCTAssertNil(store.detachedItems[deep.id])
        XCTAssertEqual(store.items.filter { $0.id == deep.id }.count, 1)
    }
}
