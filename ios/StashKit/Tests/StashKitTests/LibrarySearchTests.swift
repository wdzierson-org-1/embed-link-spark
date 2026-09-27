import XCTest
@testable import StashKit

final class StubSearcher: ItemSearching, @unchecked Sendable {
    private let lock = NSLock()
    var answers: [String: [UUID]] = [:]
    var shouldThrow = false
    var gate = false
    private(set) var queries: [String] = []
    private var gates: [CheckedContinuation<Void, Never>] = []

    func searchIds(query: String, limit: Int) async throws -> [UUID] {
        let (gated, fail) = lock.withLock { () -> (Bool, Bool) in
            queries.append(query)
            return (gate, shouldThrow)
        }
        if gated { await withCheckedContinuation { c in lock.withLock { gates.append(c) } } }
        if fail { throw StubFetchError() }
        return lock.withLock { answers[query] ?? [] }
    }

    func release() {
        let next = lock.withLock { gates.isEmpty ? nil : gates.removeFirst() }
        next?.resume()
    }

    var pending: Int { lock.withLock { gates.count } }
    var callCount: Int { lock.withLock { queries.count } }
}

final class SearchResponseTests: XCTestCase {
    func testResponseKeepsServerOrderDedupesAndSkipsMalformedIds() throws {
        let a = UUID(), b = UUID()
        let json = """
        {"results":[{"id":"\(b.uuidString.lowercased())","score":0.9,"title":"B"},
                    {"id":"\(a.uuidString)","score":0.5},
                    {"id":"\(b.uuidString)","score":0.1},
                    {"id":"not-a-uuid"}]}
        """
        let response = try JSONDecoder().decode(SearchItemsResponse.self, from: Data(json.utf8))
        XCTAssertEqual(response.orderedIds, [b, a])
    }

    func testRequestBodyMatchesTheWebHook() throws {
        let body = try JSONEncoder().encode(SearchItemsRequest(query: "persimmon", limit: 50))
        let object = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        XCTAssertEqual(object?["query"] as? String, "persimmon")
        XCTAssertEqual(object?["limit"] as? Int, 50)
    }
}

final class RankedSearchResultsTests: XCTestCase {
    private func item(_ title: String, minutesAgo: Int = 0, pageBodyOnly: Bool = false) -> Item {
        Item(id: UUID(), type: .text, title: title, content: nil, url: nil, filePath: nil,
             description: nil, summary: nil, pageBody: pageBodyOnly ? "persimmon" : nil,
             supplementalNote: nil, mimeType: nil, isPublic: false,
             createdAt: Date(timeIntervalSince1970: 1_790_000_000 - Double(minutesAgo * 60)))
    }

    func testLiteralMatchesComeFirstInRelevanceOrderThenLocalOnlyThenSemantic() {
        let linkTwo = item("UITEST-FIXTURE: link two")
        let linkOne = item("UITEST-FIXTURE: link one")
        let video = item("Rick Astley")
        let otherLiteral = item("another link one mention")
        let localOnly = item("link one draft (not indexed yet)")
        let rows = Dictionary(uniqueKeysWithValues: [linkTwo, linkOne, video, otherLiteral].map { ($0.id, $0) })

        let results = rankedSearchResults(
            query: "link one",
            rankedIds: [linkTwo.id, linkOne.id, video.id, otherLiteral.id],
            rowFor: { rows[$0] },
            localPool: [localOnly, linkOne])

        XCTAssertEqual(results.map(\.id), [linkOne.id, otherLiteral.id, localOnly.id, linkTwo.id, video.id])
    }

    /// A rich note's `content` is TipTap JSON: its markup ("doc", "type", "paragraph", "text") must
    /// never make it a literal match — only the words the card shows.
    func testRichNotesRankOnTheirTextNotTheirTipTapMarkup() {
        let doc = #"{"type":"doc","content":[{"type":"paragraph","content":[{"type":"text","text":"Buy persimmons"}]}]}"#
        func note(_ title: String, content: String?) -> Item {
            Item(id: UUID(), type: .text, title: title, content: content, url: nil, filePath: nil,
                 description: nil, summary: nil, pageBody: nil, supplementalNote: nil, mimeType: nil,
                 isPublic: false, createdAt: Date(timeIntervalSince1970: 1_790_000_000))
        }
        let richNote = note("Groceries", content: doc)
        let realHit = note("Doc review checklist", content: nil)
        let localRich = note("Errands", content: doc)            // only the markup says "doc"
        let localPlain = note("Weekend", content: "docs to sign") // a plain-text note that does
        let rows = [richNote.id: richNote, realHit.id: realHit]

        let byMarkupWord = rankedSearchResults(query: "doc", rankedIds: [richNote.id, realHit.id],
                                               rowFor: { rows[$0] }, localPool: [localRich, localPlain])
        XCTAssertEqual(byMarkupWord.map(\.id), [realHit.id, localPlain.id, richNote.id],
                       "the rich note stays a (semantic) server hit, never a literal one; the local rich note drops out")

        for markup in ["type", "paragraph", "text", "content"] {
            XCTAssertFalse(richNote.matchesCardText(searchQuery: markup), "'\(markup)' is TipTap markup, not note text")
        }
        XCTAssertTrue(richNote.matchesCardText(searchQuery: "  PERSIMMONS "), "the note's own words still match")

        let byNoteText = rankedSearchResults(query: "persimmons", rankedIds: [realHit.id, richNote.id],
                                             rowFor: { rows[$0] }, localPool: [localRich])
        XCTAssertEqual(byNoteText.map(\.id), [richNote.id, localRich.id, realHit.id])
    }

    func testPageBodyOnlyHitsKeepServerOrderAndUnknownIdsAreSkipped() {
        let deep = item("Analysis of results", pageBodyOnly: true)
        let second = item("Fruit notes", pageBodyOnly: true)
        let rows = [deep.id: deep, second.id: second]

        let results = rankedSearchResults(query: "persimmon", rankedIds: [second.id, UUID(), deep.id, second.id],
                                          rowFor: { rows[$0] }, localPool: [])

        XCTAssertEqual(results.map(\.id), [second.id, deep.id], "server order, duplicates and deleted ids dropped")
    }
}

@MainActor
final class LibrarySearchTests: XCTestCase {
    private func row(_ title: String) -> Item {
        Item(id: UUID(), type: .text, title: title, content: nil, url: nil, filePath: nil,
             description: nil, summary: nil, pageBody: nil, supplementalNote: nil, mimeType: nil,
             isPublic: false, createdAt: Date())
    }

    private func waitUntil(_ condition: () -> Bool, timeout: TimeInterval = 2) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline { try? await Task.sleep(for: .milliseconds(5)) }
    }

    func testShortQueriesStayLocalAndLongerOnesPublishServerIdsWithRows() async {
        let hit = row("persimmon notes")
        let server = FakeItemsServer(rows: [hit], pageSize: 50)
        let store = ItemStore(userId: UUID(), fetcher: server, pageSize: 50)
        let searcher = StubSearcher()
        searcher.answers["pe"] = [hit.id]
        let search = LibrarySearch(store: store, searcher: searcher, debounce: .milliseconds(10))

        search.update(query: "p")
        XCTAssertEqual(search.phase, .inactive)
        XCTAssertEqual(searcher.callCount, 0, "≥ 2 characters before asking the server")

        search.update(query: " pe ")
        XCTAssertEqual(search.phase, .pending)
        XCTAssertNil(search.serverIds(for: "pe"), "pending → caller keeps the local filter")

        await waitUntil { search.phase != .pending }
        XCTAssertEqual(search.phase, .results([hit.id]))
        XCTAssertEqual(search.serverIds(for: "pe "), [hit.id])
        XCTAssertNil(search.serverIds(for: "per"), "results only answer the query they were for")
        XCTAssertEqual(store.item(withId: hit.id), hit, "every hit has a row to render")
    }

    func testDebounceCoalescesTypingIntoOneRequest() async {
        let store = ItemStore(userId: UUID(), fetcher: FakeItemsServer(rows: [], pageSize: 50), pageSize: 50)
        let searcher = StubSearcher()
        let search = LibrarySearch(store: store, searcher: searcher, debounce: .milliseconds(40))

        for prefix in ["pe", "per", "pers", "persi"] { search.update(query: prefix) }
        await waitUntil { search.phase != .pending }

        XCTAssertEqual(searcher.queries, ["persi"])
    }

    func testAnOlderAnswerNeverReplacesANewerQuery() async {
        let store = ItemStore(userId: UUID(), fetcher: FakeItemsServer(rows: [], pageSize: 50), pageSize: 50)
        let searcher = StubSearcher()
        let old = UUID(), new = UUID()
        searcher.answers = ["ab": [old], "abc": [new]]
        searcher.gate = true
        let search = LibrarySearch(store: store, searcher: searcher, debounce: .milliseconds(1))

        search.update(query: "ab")
        await waitUntil { searcher.pending == 1 }
        search.update(query: "abc")
        await waitUntil { searcher.pending == 2 }
        searcher.release()                      // "ab" answers late
        try? await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(search.phase, .pending, "the stale answer was dropped")
        searcher.release()
        await waitUntil { search.phase != .pending }

        XCTAssertEqual(search.phase, .results([new]))
    }

    func testFailureFallsBackToTheLocalFilterAndCachedQueriesAnswerInstantly() async {
        let store = ItemStore(userId: UUID(), fetcher: FakeItemsServer(rows: [], pageSize: 50), pageSize: 50)
        let searcher = StubSearcher()
        let id = UUID()
        searcher.answers["ok"] = [id]
        let search = LibrarySearch(store: store, searcher: searcher, debounce: .milliseconds(1))

        searcher.shouldThrow = true
        search.update(query: "boom")
        await waitUntil { search.phase != .pending }
        XCTAssertEqual(search.phase, .failed)
        XCTAssertNil(search.serverIds(for: "boom"))

        searcher.shouldThrow = false
        search.update(query: "ok")
        await waitUntil { search.phase != .pending }
        search.update(query: "")
        XCTAssertEqual(search.phase, .inactive)
        search.update(query: "ok")
        XCTAssertEqual(search.phase, .results([id]), "cached per query — no second request")
        XCTAssertEqual(searcher.queries, ["boom", "ok"])
    }
}
