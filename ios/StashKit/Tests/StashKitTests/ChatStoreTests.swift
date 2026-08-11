import XCTest
@testable import StashKit

final class StubStreamer: ChatStreaming, @unchecked Sendable {
    var events: [SSEEvent] = []
    var thrown: Error?
    var lastHistory: [[String: String]] = []
    func stream(message: String, history: [[String: String]], accessToken: String) -> AsyncThrowingStream<SSEEvent, Error> {
        lastHistory = history
        return AsyncThrowingStream { c in
            for e in events { c.yield(e) }
            if let thrown { c.finish(throwing: thrown) } else { c.finish() }
        }
    }
}
final class StubHistory: ChatHistoryStoring, @unchecked Sendable {
    var persisted: [(String, String, [UUID]?)] = []
    var seeded: [ChatMessage] = []
    func loadOrCreateConversation(userId: UUID) async throws -> UUID { UUID() }
    func loadHistory(conversationId: UUID, limit: Int) async throws -> [ChatMessage] { seeded }
    func persist(conversationId: UUID, role: String, content: String, sourceItemIds: [UUID]?) async {
        persisted.append((role, content, sourceItemIds))
    }
}

@MainActor
final class ChatStoreTests: XCTestCase {
    func makeStore(streamer: StubStreamer, history: StubHistory = StubHistory(),
                   persistDispatch: @escaping (@escaping @Sendable () async -> Void) -> Void = { work in Task { await work() } }) -> ChatStore {
        ChatStore(userId: UUID(), streamer: streamer, history: history,
                  capture: CaptureAPI(poster: StubPoster()), accessToken: { "jwt" },
                  persistDispatch: persistDispatch)
    }

    func testAskStreamsAndPersists() async {
        let streamer = StubStreamer()
        let sourceId = UUID()
        streamer.events = [.delta("Hel"), .delta("lo"),
                           .done(sources: [ChatSource(id: sourceId, title: "S", type: "text", url: nil)])]
        let history = StubHistory()
        // ChatStore's `persist` calls are fire-and-forget (web parity — ChatMole.tsx:121-131 never
        // awaits its insert either), so a real `Task {}` dispatcher would race this test's
        // assertions. Collect the work instead and drain it explicitly for a deterministic result.
        var pendingPersists: [@Sendable () async -> Void] = []
        let store = makeStore(streamer: streamer, history: history,
                              persistDispatch: { work in pendingPersists.append(work) })
        await store.loadHistoryOnce()
        await store.send("what is hello?")
        for work in pendingPersists { await work() }
        XCTAssertEqual(store.messages.count, 2)
        XCTAssertEqual(store.messages[1].content, "Hello")
        XCTAssertEqual(store.messages[1].sources.first?.id, sourceId)
        XCTAssertFalse(store.messages[1].isStreaming)
        XCTAssertEqual(history.persisted.map(\.0), ["user", "assistant"])
        XCTAssertEqual(history.persisted[1].2, [sourceId])
    }

    func testServerErrorRollsBackAndRestoresInput() async {
        let streamer = StubStreamer()
        streamer.events = [.delta("par"), .serverError("boom")]
        let store = makeStore(streamer: streamer)
        await store.loadHistoryOnce()
        await store.send("failing question")
        XCTAssertTrue(store.messages.isEmpty)
        XCTAssertEqual(store.errorRestoredInput, "failing question")
        XCTAssertNotNil(store.errorMessage)
    }

    func testHistorySentAsPriorTurnsOnly() async {
        let streamer = StubStreamer()
        streamer.events = [.delta("x"), .done(sources: [])]
        let history = StubHistory()
        history.seeded = [ChatMessage(id: "1", role: .user, content: "q1", sources: [], savedItemTitle: nil, savedKind: nil, isStreaming: false),
                          ChatMessage(id: "2", role: .assistant, content: "a1", sources: [], savedItemTitle: nil, savedKind: nil, isStreaming: false)]
        let store = makeStore(streamer: streamer, history: history)
        await store.loadHistoryOnce()
        await store.send("q2")
        XCTAssertEqual(streamer.lastHistory, [["role": "user", "content": "q1"],
                                              ["role": "assistant", "content": "a1"],
                                              ["role": "user", "content": "q2"]])
    }

    func testSaveNoteRouteMakesChip() async {
        let streamer = StubStreamer()
        let store = makeStore(streamer: streamer)
        await store.loadHistoryOnce()
        await store.send("remember: buy milk")   // StubPoster returns empty Data → capture throws → chip removed + error
        XCTAssertTrue(store.messages.isEmpty)
        XCTAssertNotNil(store.errorMessage)
    }
}
