import XCTest
@testable import StashKit

final class RecordingSyncer: EmbeddingSyncing, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [UUID] = []
    /// Thrown by every call when set (the call is still recorded).
    var error: Error?

    var calls: [UUID] { lock.withLock { recorded } }

    func refreshEmbeddings(itemId: UUID) async throws {
        lock.withLock { recorded.append(itemId) }
        if let error { throw error }
    }
}

/// Collects `EmbeddingRefresher`'s failure reports.
final class FailureLog: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [UUID] = []
    var itemIds: [UUID] { lock.withLock { entries } }
    func record(_ itemId: UUID) { lock.withLock { entries.append(itemId) } }
}

final class EmbeddingRefresherTests: XCTestCase {
    func fixture(title: String, id: UUID = UUID(uuidString: "6B1E0A4E-9F6A-4D5E-8F2F-0E7C1B2D3A4B")!) -> Item {
        Item(id: id, type: .text,
             title: title, content: "body", url: "https://x.com", filePath: nil,
             description: "desc", summary: "sum", pageBody: "pb", supplementalNote: "sn",
             mimeType: nil, isPublic: false, createdAt: .now, fileSize: nil, attributes: ItemAttributes())
    }

    /// A burst of saves to one item asks the server once, after the burst — and asks for exactly
    /// that item: the server rebuilds from the saved row (generate-embeddings v120 ignores any
    /// client-built text, so none is sent).
    func testABurstOfSavesAsksOnceAfterTheIdleWindow() async throws {
        let syncer = RecordingSyncer()
        let refresher = EmbeddingRefresher(syncer: syncer, idle: .milliseconds(60))
        let item = fixture(title: "first")
        await refresher.schedule(item)
        await refresher.schedule(fixture(title: "second"))
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(syncer.calls, [item.id])
    }

    func testDifferentItemsAreRefreshedIndependently() async throws {
        let syncer = RecordingSyncer()
        let refresher = EmbeddingRefresher(syncer: syncer, idle: .milliseconds(30))
        let a = fixture(title: "a", id: UUID())
        let b = fixture(title: "b", id: UUID())
        await refresher.schedule(a)
        await refresher.schedule(b)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(Set(syncer.calls), [a.id, b.id])
    }

    /// v120's compare-and-swap answers `409 item_changed` when the row changed mid-generation —
    /// benign (the change brings its own re-index), so it is never reported as a failure; any
    /// other error still is.
    func testItemChangedIsBenignButOtherFailuresAreReported() async throws {
        let syncer = RecordingSyncer()
        syncer.error = EmbeddingRefreshError.itemChanged
        let failures = FailureLog()
        let refresher = EmbeddingRefresher(syncer: syncer, idle: .milliseconds(10)) { itemId, _ in failures.record(itemId) }
        let item = fixture(title: "t")

        await refresher.schedule(item)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(syncer.calls, [item.id])
        XCTAssertEqual(failures.itemIds, [], "item_changed is not a failure")

        syncer.error = URLError(.notConnectedToInternet)
        await refresher.schedule(item)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(failures.itemIds, [item.id])
    }
}
