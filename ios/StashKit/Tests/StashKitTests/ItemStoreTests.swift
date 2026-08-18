import XCTest
@testable import StashKit

struct StubFetchError: Error {}

final class StubFetcher: ItemsFetching, @unchecked Sendable {
    var pages: [[Item]] = []
    var calls: [(before: Date?, types: [ItemType]?)] = []
    var shouldThrow = false
    func fetchPage(userId: UUID, before: Date?, types: [ItemType]?, tagIds: [UUID]) async throws -> [Item] {
        calls.append((before, types))
        if shouldThrow { throw StubFetchError() }
        return pages.isEmpty ? [] : pages.removeFirst()
    }
    func fetchDetail(id: UUID) async throws -> Item { fatalError("unused") }
}

/// Fetcher whose `fetchPage` blocks on an externally-releasable continuation, so a test can
/// control the completion order of two concurrent refreshes.
final class GatedFetcher: ItemsFetching, @unchecked Sendable {
    var gates: [CheckedContinuation<[Item], Error>] = []
    var pendingTypes: [[ItemType]?] = []
    func fetchPage(userId: UUID, before: Date?, types: [ItemType]?, tagIds: [UUID]) async throws -> [Item] {
        pendingTypes.append(types)
        return try await withCheckedThrowingContinuation { gates.append($0) }
    }
    func fetchDetail(id: UUID) async throws -> Item { fatalError("unused") }
    func release(_ index: Int, with items: [Item]) { gates[index].resume(returning: items) }
}

@MainActor
final class ItemStoreTests: XCTestCase {
    func makeItem(minutesAgo: Int) -> Item {
        Item(id: UUID(), type: .text, title: "t\(minutesAgo)", content: nil, url: nil,
             filePath: nil, description: nil, summary: nil, pageBody: nil,
             supplementalNote: nil, mimeType: nil, isPublic: false,
             createdAt: Date(timeIntervalSinceNow: Double(-60 * minutesAgo)),
             fileSize: nil, attributes: ItemAttributes())
    }

    func testPaginationAdvancesCursorAndStops() async {
        let fetcher = StubFetcher()
        let first = (0..<50).map(makeItem)
        let second = (50..<70).map(makeItem)
        fetcher.pages = [first, second]
        let store = ItemStore(userId: UUID(), fetcher: fetcher, pageSize: 50)

        await store.refresh()
        XCTAssertEqual(store.items.count, 50)
        XCTAssertTrue(store.hasMore)

        await store.loadMoreIfNeeded(current: store.items.last!)
        XCTAssertEqual(store.items.count, 70)
        XCTAssertFalse(store.hasMore)                       // short page → no more
        XCTAssertEqual(fetcher.calls.count, 2)
        XCTAssertEqual(fetcher.calls[1].before, first.last!.createdAt)  // cursor = oldest loaded
    }

    func testRefreshDedupesById() async {
        let fetcher = StubFetcher()
        let a = makeItem(minutesAgo: 1)
        fetcher.pages = [[a], [a]]                          // same row returned twice
        let store = ItemStore(userId: UUID(), fetcher: fetcher, pageSize: 1)
        await store.refresh()
        await store.loadMoreIfNeeded(current: a)
        XCTAssertEqual(store.items.count, 1)
    }

    func testFilterChangeResetsPaging() async {
        let fetcher = StubFetcher()
        fetcher.pages = [[makeItem(minutesAgo: 1)], [makeItem(minutesAgo: 2)]]
        let store = ItemStore(userId: UUID(), fetcher: fetcher, pageSize: 50)
        await store.refresh()
        store.typeFilter = .links
        await store.refresh()
        XCTAssertEqual(fetcher.calls.last?.types, [ItemType.link])
        XCTAssertNil(fetcher.calls.last?.before)            // cursor reset
    }

    // Closes ledgered T9#4: the catch path in ItemStore.load(reset:) was implemented
    // (loadError set on throw, cleared at the top of every load) but never exercised.
    func testFailedRefreshSetsLoadErrorAndRetainsItemsThenClearsOnRetry() async {
        let fetcher = StubFetcher()
        let item = makeItem(minutesAgo: 1)
        fetcher.pages = [[item]]
        let store = ItemStore(userId: UUID(), fetcher: fetcher, pageSize: 50)

        await store.refresh()
        XCTAssertEqual(store.items.count, 1)
        XCTAssertNil(store.loadError)

        fetcher.shouldThrow = true
        await store.refresh()
        XCTAssertNotNil(store.loadError)
        XCTAssertEqual(store.items.count, 1)                // stale items retained despite failed refresh

        fetcher.shouldThrow = false
        fetcher.pages = [[item]]
        await store.refresh()
        XCTAssertNil(store.loadError)                       // cleared by the next successful refresh
        XCTAssertEqual(store.items.count, 1)
    }

    // Closes final-review Important #3 (refresh reentrancy): a slow, stale refresh that
    // completes AFTER a newer refresh must not clobber the newer refresh's results.
    func testStaleRefreshCannotOverwriteNewerOne() async {
        let fetcher = GatedFetcher()
        let store = ItemStore(userId: UUID(), fetcher: fetcher, pageSize: 50)
        let old = makeItem(minutesAgo: 99)
        let new = makeItem(minutesAgo: 1)

        async let first: Void = store.refresh()          // starts, blocks on gate 0
        try? await Task.sleep(for: .milliseconds(50))
        async let second: Void = store.refresh()         // starts, blocks on gate 1
        try? await Task.sleep(for: .milliseconds(50))

        fetcher.release(1, with: [new])                  // newer refresh completes first
        try? await Task.sleep(for: .milliseconds(50))
        fetcher.release(0, with: [old])                  // stale refresh completes last
        _ = await (first, second)

        XCTAssertEqual(store.items.map(\.id), [new.id])  // stale result dropped
    }

    func testApplyNewPrependsOnceOnly() async {
        let fetcher = StubFetcher()
        let store = ItemStore(userId: UUID(), fetcher: fetcher, pageSize: 50)
        let item = makeItem(minutesAgo: 0)
        store.applyNew(item)
        store.applyNew(item)
        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(store.items.first?.id, item.id)
    }
}
