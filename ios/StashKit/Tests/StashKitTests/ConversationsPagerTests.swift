import XCTest
@testable import StashKit

/// Scripted `list_conversations` backend: each call suspends until the test answers it, so the
/// test controls exactly which response lands when.
@MainActor
final class ScriptedConversations {
    struct Call {
        let searchText: String?
        let offset: Int
        let reply: CheckedContinuation<[ConversationListRow], Error>
    }
    private(set) var calls: [Call] = []

    func fetch(_ searchText: String?, _ limit: Int, _ offset: Int) async throws -> [ConversationListRow] {
        try await withCheckedThrowingContinuation { continuation in
            calls.append(Call(searchText: searchText, offset: offset, reply: continuation))
        }
    }
}

@MainActor
final class ConversationsPagerTests: XCTestCase {
    private func rows(_ titles: [String], total: Int) -> [ConversationListRow] {
        titles.map { ConversationListRow(id: UUID(), title: $0, lastMessageAt: Date(), messageCount: 2,
                                         preview: nil, totalCount: total) }
    }

    private func waitForCalls(_ backend: ScriptedConversations, _ count: Int) async {
        let deadline = Date().addingTimeInterval(2)
        while backend.calls.count < count, Date() < deadline {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTAssertEqual(backend.calls.count, count)
    }

    func testFirstPageThenNextPageAppends() async {
        let backend = ScriptedConversations()
        let pager = ConversationsPager(pageSize: 2, fetch: backend.fetch)
        let first = Task { await pager.loadFirstPage(query: "") }
        await waitForCalls(backend, 1)
        XCTAssertNil(backend.calls[0].searchText, "Blank query lists everything")
        XCTAssertTrue(pager.isLoading)
        backend.calls[0].reply.resume(returning: rows(["a", "b"], total: 3))
        await first.value
        XCTAssertEqual(pager.rows.map(\.title), ["a", "b"])
        XCTAssertTrue(pager.hasMore)

        let next = Task { await pager.loadNextPage() }
        await waitForCalls(backend, 2)
        XCTAssertEqual(backend.calls[1].offset, 2)
        backend.calls[1].reply.resume(returning: rows(["c"], total: 3))
        await next.value
        XCTAssertEqual(pager.rows.map(\.title), ["a", "b", "c"])
        XCTAssertFalse(pager.hasMore)
        XCTAssertFalse(pager.isLoading)
    }

    /// M6: typing restarts the debounced load, which cancels the in-flight request — that's not
    /// a failure. The list stays and no error shows.
    func testCancellationIsNotAnError() async {
        for cancellation: Error in [CancellationError(), URLError(.cancelled)] {
            let backend = ScriptedConversations()
            let pager = ConversationsPager(fetch: backend.fetch)
            let first = Task { await pager.loadFirstPage(query: "") }
            await waitForCalls(backend, 1)
            backend.calls[0].reply.resume(returning: rows(["kept"], total: 1))
            await first.value

            let second = Task { await pager.loadFirstPage(query: "ky") }
            await waitForCalls(backend, 2)
            backend.calls[1].reply.resume(throwing: cancellation)
            await second.value
            XCTAssertNil(pager.loadError, "\(cancellation)")
            XCTAssertEqual(pager.rows.map(\.title), ["kept"])
            XCTAssertFalse(pager.isLoading)
        }
    }

    func testRealFailureShowsTheErrorState() async {
        let backend = ScriptedConversations()
        let pager = ConversationsPager(fetch: backend.fetch)
        let first = Task { await pager.loadFirstPage(query: "") }
        await waitForCalls(backend, 1)
        backend.calls[0].reply.resume(throwing: URLError(.notConnectedToInternet))
        await first.value
        XCTAssertEqual(pager.loadError, "Couldn't load conversations.")
        XCTAssertTrue(pager.rows.isEmpty)
        XCTAssertFalse(pager.isLoading)
    }

    func testSupersededFirstPageIsDropped() async {
        let backend = ScriptedConversations()
        let pager = ConversationsPager(fetch: backend.fetch)
        let older = Task { await pager.loadFirstPage(query: "ky") }
        await waitForCalls(backend, 1)
        let newer = Task { await pager.loadFirstPage(query: "kyoto") }
        await waitForCalls(backend, 2)
        backend.calls[1].reply.resume(returning: rows(["Kyoto trip"], total: 1))
        await newer.value
        backend.calls[0].reply.resume(returning: rows(["Kyiv", "Kyoto trip"], total: 2))
        await older.value
        XCTAssertEqual(pager.rows.map(\.title), ["Kyoto trip"], "The older query's late page must not replace newer results")
        XCTAssertEqual(pager.totalCount, 1)
        XCTAssertFalse(pager.isLoading)
    }

    /// M6's related race: an old query's next page finishing after a new search's first page
    /// used to append old-query rows to the new results.
    func testStaleNextPageIsDropped() async {
        let backend = ScriptedConversations()
        let pager = ConversationsPager(pageSize: 1, fetch: backend.fetch)
        let first = Task { await pager.loadFirstPage(query: "") }
        await waitForCalls(backend, 1)
        backend.calls[0].reply.resume(returning: rows(["all-1"], total: 5))
        await first.value

        let staleNext = Task { await pager.loadNextPage() }
        await waitForCalls(backend, 2)
        let search = Task { await pager.loadFirstPage(query: "tokyo") }
        await waitForCalls(backend, 3)
        XCTAssertEqual(backend.calls[2].searchText, "tokyo")
        backend.calls[2].reply.resume(returning: rows(["Tokyo"], total: 1))
        await search.value
        backend.calls[1].reply.resume(returning: rows(["all-2"], total: 5))
        await staleNext.value

        XCTAssertEqual(pager.rows.map(\.title), ["Tokyo"])
        XCTAssertEqual(pager.totalCount, 1)
        XCTAssertFalse(pager.isLoading)
    }

    func testNextPageContinuesTheActiveQueryAndDedupes() async {
        let backend = ScriptedConversations()
        let pager = ConversationsPager(pageSize: 2, fetch: backend.fetch)
        let first = Task { await pager.loadFirstPage(query: "kyoto") }
        await waitForCalls(backend, 1)
        let page = rows(["a", "b"], total: 4)
        backend.calls[0].reply.resume(returning: page)
        await first.value

        let next = Task { await pager.loadNextPage() }
        await waitForCalls(backend, 2)
        XCTAssertEqual(backend.calls[1].searchText, "kyoto")
        // A row that shifted pages (new activity) comes back twice — shown once.
        backend.calls[1].reply.resume(returning: [page[1]] + rows(["c"], total: 4))
        await next.value
        XCTAssertEqual(pager.rows.map(\.title), ["a", "b", "c"])
    }
}
