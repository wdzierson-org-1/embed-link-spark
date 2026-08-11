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

@MainActor
final class ItemStoreTests: XCTestCase {
    func makeItem(minutesAgo: Int) -> Item {
        Item(id: UUID(), type: .text, title: "t\(minutesAgo)", content: nil, url: nil,
             filePath: nil, description: nil, summary: nil, pageBody: nil,
             supplementalNote: nil, mimeType: nil, isPublic: false,
             createdAt: Date(timeIntervalSinceNow: Double(-60 * minutesAgo)))
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
}
