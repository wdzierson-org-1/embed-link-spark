import XCTest
@testable import StashKit

/// Replays a fixed script of events for every call (then finishes, or throws `thrown`).
final class StubStreamer: ChatStreaming, @unchecked Sendable {
    var events: [SSEEvent] = []
    var thrown: Error?
    var lastHistory: [[String: String]] = []
    var askedMessages: [String] = []
    func stream(message: String, history: [[String: String]], accessToken: String) -> AsyncThrowingStream<SSEEvent, Error> {
        lastHistory = history
        askedMessages.append(message)
        return AsyncThrowingStream { c in
            for e in events { c.yield(e) }
            if let thrown { c.finish(throwing: thrown) } else { c.finish() }
        }
    }
}

/// Hands each stream's continuation to the test, so events arrive exactly when the test says —
/// for asserting what the thread shows MID-answer. Called on the main actor (from `ChatStore`).
final class ControlledStreamer: ChatStreaming, @unchecked Sendable {
    private(set) var continuations: [AsyncThrowingStream<SSEEvent, Error>.Continuation] = []
    private(set) var askedMessages: [String] = []
    func stream(message: String, history: [[String: String]], accessToken: String) -> AsyncThrowingStream<SSEEvent, Error> {
        let (stream, continuation) = AsyncThrowingStream<SSEEvent, Error>.makeStream()
        askedMessages.append(message)
        continuations.append(continuation)
        return stream
    }
}

/// `ChatHistoryStoring` is nonisolated-async, so these run off the main actor — state is locked.
final class StubHistory: ChatHistoryStoring, @unchecked Sendable {
    struct Persisted: Equatable {
        let conversationId: UUID
        let role: String
        let content: String
        let sourceItemIds: [UUID]?
    }

    private let lock = NSLock()
    private var _persisted: [Persisted] = []
    private var _createdIds: [UUID] = []
    private var _titlesSet: [(UUID, String)] = []
    private var _latestCallCount = 0

    var seeded: [ChatMessage] = []
    var latest: ChatSessions.Candidate?
    var generatedTitle: String?
    var listed: [ConversationListRow] = []
    /// When true, `latestConversation` suspends until `releaseLatest()` — the open-time
    /// resolution still in flight (L3).
    var holdLatest = false
    private let latestGate: AsyncStream<Void>
    private let latestGateContinuation: AsyncStream<Void>.Continuation

    init() {
        (latestGate, latestGateContinuation) = AsyncStream<Void>.makeStream()
    }

    var persisted: [Persisted] { locked { _persisted } }
    var createdIds: [UUID] { locked { _createdIds } }
    var titlesSet: [(UUID, String)] { locked { _titlesSet } }
    var latestCallCount: Int { locked { _latestCallCount } }

    func releaseLatest() {
        latestGateContinuation.yield()
        latestGateContinuation.finish()
    }

    func latestConversation(userId: UUID) async throws -> ChatSessions.Candidate? {
        locked { _latestCallCount += 1 }
        if holdLatest {
            for await _ in latestGate { break }
        }
        return latest
    }
    func createConversation(userId: UUID) async throws -> UUID {
        let id = UUID()
        locked { _createdIds.append(id) }
        return id
    }
    func loadHistory(conversationId: UUID, limit: Int) async throws -> [ChatMessage] { seeded }
    func persist(conversationId: UUID, role: String, content: String, sourceItemIds: [UUID]?) async {
        locked { _persisted.append(Persisted(conversationId: conversationId, role: role, content: content, sourceItemIds: sourceItemIds)) }
    }
    func generateTitle(for question: String) async -> String? { generatedTitle }
    func setTitle(conversationId: UUID, title: String) async { locked { _titlesSet.append((conversationId, title)) } }
    func listConversations(searchText: String?, pageLimit: Int, pageOffset: Int) async throws -> [ConversationListRow] { listed }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

@MainActor
final class ChatStoreTests: XCTestCase {
    /// Mutable clock for gap-rule tests — `advance` between calls simulates silence.
    final class Clock: @unchecked Sendable {
        var current = Date(timeIntervalSince1970: 1_756_400_000)
        func advance(hours: Double) { current += hours * 3600 }
    }

    /// Collects fire-and-forget persists so a test can drain them deterministically.
    final class PersistQueue {
        var pending: [@Sendable () async -> Void] = []
        func drain() async {
            while !pending.isEmpty {
                let work = pending.removeFirst()
                await work()
            }
        }
    }

    func makeStore(streamer: ChatStreaming, history: StubHistory = StubHistory(),
                   clock: Clock = Clock(), publishInterval: TimeInterval = 0.1,
                   persistQueue: PersistQueue? = nil) -> ChatStore {
        let dispatch: (@escaping @Sendable () async -> Void) -> Void
        if let persistQueue {
            dispatch = { persistQueue.pending.append($0) }
        } else {
            dispatch = { work in Task { await work() } }
        }
        return ChatStore(userId: UUID(), streamer: streamer, history: history, accessToken: { "jwt" },
                         now: { clock.current }, streamPublishInterval: publishInterval,
                         persistDispatch: dispatch)
    }

    /// Polls `condition` on the main actor (yielding between checks) until it holds or times out.
    func waitUntil(timeout: TimeInterval = 2, file: StaticString = #filePath, line: UInt = #line,
                   _ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline {
                XCTFail("Timed out waiting for condition", file: file, line: line)
                return
            }
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
    }

    // MARK: - Asking

    func testAskStreamsAndPersists() async {
        let streamer = StubStreamer()
        let sourceId = UUID()
        streamer.events = [.delta("Hel"), .delta("lo"),
                           .done(sources: [ChatSource(id: sourceId, title: "S", type: "text", url: nil)])]
        let history = StubHistory()
        let queue = PersistQueue()
        let store = makeStore(streamer: streamer, history: history, persistQueue: queue)
        await store.loadHistoryOnce()
        await store.send("what is hello?")
        await queue.drain()
        XCTAssertEqual(store.messages.count, 2)
        XCTAssertEqual(store.messages[1].content, "Hello")
        XCTAssertEqual(store.messages[1].sources.first?.id, sourceId)
        XCTAssertFalse(store.messages[1].isStreaming)
        XCTAssertFalse(store.messages[1].isInterrupted)
        XCTAssertEqual(history.persisted.map(\.role), ["user", "assistant"])
        XCTAssertEqual(history.persisted[1].sourceItemIds, [sourceId])
        // No prior conversation → the session row was created lazily on this first send, and
        // both halves of the exchange were written into it.
        XCTAssertEqual(history.createdIds.count, 1)
        XCTAssertEqual(history.persisted.map(\.conversationId), [history.createdIds[0], history.createdIds[0]])
        XCTAssertFalse(store.isStreaming)
    }

    /// M11: Ask is retrieval-only — a `remember:` prefix or a pasted link is a question now, not
    /// a save (web parity; `docs/ui-changes.md` 2026-08-27).
    func testRememberPrefixesAndLinksAreAskedNotSaved() async {
        let streamer = StubStreamer()
        streamer.events = [.delta("answer"), .done(sources: [])]
        let store = makeStore(streamer: streamer)
        await store.send("remember: buy milk")
        await store.send("what did I save from https://nytimes.com/2026/09/27/story?")
        XCTAssertEqual(streamer.askedMessages, ["remember: buy milk",
                                                "what did I save from https://nytimes.com/2026/09/27/story?"])
        XCTAssertEqual(store.messages.map(\.role), [.user, .assistant, .user, .assistant])
    }

    func testHistorySentAsPriorTurnsOnly() async {
        let streamer = StubStreamer()
        streamer.events = [.delta("x"), .done(sources: [])]
        let history = StubHistory()
        let clock = Clock()
        // A fresh (< 3h old) latest conversation continues on open, restoring its thread.
        history.latest = ChatSessions.Candidate(id: UUID(), title: "t", lastMessageAt: clock.current - 60)
        history.seeded = [ChatMessage(id: "1", role: .user, content: "q1"),
                          ChatMessage(id: "2", role: .assistant, content: "a1")]
        let store = makeStore(streamer: streamer, history: history, clock: clock)
        await store.loadHistoryOnce()
        await store.send("q2")
        XCTAssertEqual(streamer.lastHistory, [["role": "user", "content": "q1"],
                                              ["role": "assistant", "content": "a1"],
                                              ["role": "user", "content": "q2"]])
        XCTAssertTrue(history.createdIds.isEmpty, "A continuing session must not create a new row")
    }

    // MARK: - Failure handling (L1 + "SSE drop mid-answer: keep partial text, show retry")

    func testFailureBeforeTheFirstTokenRollsBackAndRestoresInput() async {
        let streamer = StubStreamer()
        streamer.thrown = URLError(.notConnectedToInternet)
        let queue = PersistQueue()
        let history = StubHistory()
        let store = makeStore(streamer: streamer, history: history, persistQueue: queue)
        await store.send("failing question")
        await queue.drain()
        XCTAssertTrue(store.messages.isEmpty)
        XCTAssertEqual(store.errorRestoredInput, "failing question")
        XCTAssertEqual(store.errorMessage, "Failed to get a response.")
        XCTAssertFalse(history.persisted.contains { $0.role == "assistant" })
    }

    /// Final wave B: chat-with-all-content's own paywall (`403 subscription_required`) rolls the
    /// exchange back like any pre-token failure, but is reported as a subscription refusal — the
    /// view shows its gate copy — never as the generic "Failed to get a response."
    func testAServerPaywallRefusalIsReportedAsASubscriptionRefusal() async {
        let streamer = StubStreamer()
        streamer.thrown = ChatStreamError.subscriptionRequired
        let queue = PersistQueue()
        let history = StubHistory()
        let store = makeStore(streamer: streamer, history: history, persistQueue: queue)

        await store.send("gated question")
        await queue.drain()

        XCTAssertTrue(store.messages.isEmpty, "the refused exchange is rolled back")
        XCTAssertEqual(store.errorRestoredInput, "gated question")
        XCTAssertNil(store.errorMessage, "not the generic failure copy")
        XCTAssertEqual(store.subscriptionRefusals, 1)
        XCTAssertFalse(store.isStreaming)
        XCTAssertFalse(history.persisted.contains { $0.role == "assistant" })

        // Every refusal is its own observable change; any other failure is still generic.
        await store.send("gated again")
        XCTAssertEqual(store.subscriptionRefusals, 2)
        streamer.thrown = ChatStreamError.badStatus(500)
        await store.send("server broke")
        XCTAssertEqual(store.subscriptionRefusals, 2)
        XCTAssertEqual(store.errorMessage, "Failed to get a response.")
    }

    func testServerErrorBeforeTheFirstTokenRollsBack() async {
        let streamer = StubStreamer()
        streamer.events = [.status(.searching), .serverError("boom")]
        let store = makeStore(streamer: streamer)
        await store.send("q")
        XCTAssertTrue(store.messages.isEmpty)
        XCTAssertEqual(store.errorRestoredInput, "q")
        XCTAssertNotNil(store.errorMessage)
    }

    func testEmptyAnswersRollBack() async {
        for events: [SSEEvent] in [[], [.done(sources: [])]] {
            let streamer = StubStreamer()
            streamer.events = events
            let store = makeStore(streamer: streamer)
            await store.send("q")
            XCTAssertTrue(store.messages.isEmpty, "events: \(events)")
            XCTAssertEqual(store.errorRestoredInput, "q")
        }
    }

    /// L1: a stream that ends cleanly without `done` used to leave the bubble "streaming"
    /// forever (blinking cursor, never persisted). It now finalizes the partial answer.
    func testStreamEndingWithoutDoneKeepsAndPersistsThePartialAnswer() async {
        let streamer = StubStreamer()
        streamer.events = [.delta("Part"), .delta("ial")]
        let history = StubHistory()
        let queue = PersistQueue()
        let store = makeStore(streamer: streamer, history: history, persistQueue: queue)
        await store.send("q")
        await queue.drain()
        XCTAssertEqual(store.messages.map(\.content), ["q", "Partial"])
        XCTAssertFalse(store.messages[1].isStreaming)
        XCTAssertTrue(store.messages[1].isInterrupted)
        XCTAssertNil(store.errorMessage, "The kept partial answer + retry is the message — no error banner")
        XCTAssertNil(store.errorRestoredInput)
        XCTAssertEqual(history.persisted.map(\.role), ["user", "assistant"])
        XCTAssertEqual(history.persisted[1].content, "Partial")
        XCTAssertFalse(store.isStreaming)
    }

    func testNetworkDropOrServerErrorMidAnswerKeepsThePartialAnswer() async {
        let failures: [(events: [SSEEvent], thrown: Error?)] = [
            ([.delta("Half an answer")], URLError(.networkConnectionLost)),
            ([.delta("Half an answer"), .serverError("Stream interrupted")], nil),
        ]
        for failure in failures {
            let streamer = StubStreamer()
            streamer.events = failure.events
            streamer.thrown = failure.thrown
            let history = StubHistory()
            let queue = PersistQueue()
            let store = makeStore(streamer: streamer, history: history, persistQueue: queue)
            await store.send("q")
            await queue.drain()
            XCTAssertEqual(store.messages.map(\.content), ["q", "Half an answer"])
            XCTAssertTrue(store.messages[1].isInterrupted)
            XCTAssertNil(store.errorRestoredInput)
            XCTAssertEqual(history.persisted.last?.content, "Half an answer")
        }
    }

    /// The store stops reading at `done` (`break stream`), so an error the transport raises after
    /// it is never even observed; `ask`'s catch-side `sawDone` guard is only a backstop for that.
    func testTransportErrorAfterDoneChangesNothing() async {
        let streamer = StubStreamer()
        streamer.events = [.delta("complete"), .done(sources: [])]
        streamer.thrown = URLError(.networkConnectionLost)
        let store = makeStore(streamer: streamer)
        await store.send("q")
        XCTAssertEqual(store.messages.map(\.content), ["q", "complete"])
        XCTAssertFalse(store.messages[1].isInterrupted)
        XCTAssertNil(store.errorMessage)
    }

    func testRetryReasksTheInterruptedQuestionAsANewExchange() async {
        let streamer = ControlledStreamer()
        let store = makeStore(streamer: streamer)
        let first = Task { await store.send("what's in my notes?") }
        await waitUntil { streamer.continuations.count == 1 }
        streamer.continuations[0].yield(.delta("Half"))
        streamer.continuations[0].finish(throwing: URLError(.networkConnectionLost))
        await first.value
        let interruptedId = store.messages[1].id
        XCTAssertTrue(store.messages[1].isInterrupted)

        let retry = Task { await store.retry(messageId: interruptedId) }
        await waitUntil { streamer.continuations.count == 2 }
        streamer.continuations[1].yield(.delta("Full answer"))
        streamer.continuations[1].yield(.done(sources: []))
        streamer.continuations[1].finish()
        await retry.value

        XCTAssertEqual(streamer.askedMessages, ["what's in my notes?", "what's in my notes?"])
        XCTAssertEqual(store.messages.map(\.content), ["what's in my notes?", "Half", "what's in my notes?", "Full answer"])
        XCTAssertTrue(store.messages[1].isInterrupted, "The partial answer stays as the user saw it")
        XCTAssertFalse(store.messages[3].isInterrupted)
    }

    // MARK: - Streaming (M1 coalescing, status frames)

    func testDeltasAfterTheFirstTokenAreCoalesced() async {
        let streamer = ControlledStreamer()
        // A long interval: nothing but the first token and `done` may publish in this test.
        let store = makeStore(streamer: streamer, publishInterval: 60)
        let send = Task { await store.send("q") }
        await waitUntil { streamer.continuations.count == 1 }
        let stream = streamer.continuations[0]
        stream.yield(.delta("A"))
        await waitUntil { store.messages.last?.content == "A" }
        stream.yield(.delta("B"))
        stream.yield(.delta("C"))
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(store.messages.last?.content, "A", "Later deltas are held, not republished per token")
        stream.yield(.done(sources: []))
        stream.finish()
        await send.value
        XCTAssertEqual(store.messages.last?.content, "ABC")
    }

    func testHeldTextIsPublishedWhileTheStreamPauses() async {
        let streamer = ControlledStreamer()
        let store = makeStore(streamer: streamer, publishInterval: 0.05)
        let send = Task { await store.send("q") }
        await waitUntil { streamer.continuations.count == 1 }
        let stream = streamer.continuations[0]
        stream.yield(.delta("A"))
        await waitUntil { store.messages.last?.content == "A" }
        stream.yield(.delta("B"))
        // No further events: the publish ticker must surface "B" on its own.
        await waitUntil { store.messages.last?.content == "AB" }
        stream.yield(.done(sources: []))
        stream.finish()
        await send.value
    }

    func testStatusFramesShowInThePlaceholderUntilTheFirstToken() async {
        let streamer = ControlledStreamer()
        let store = makeStore(streamer: streamer)
        let send = Task { await store.send("q") }
        await waitUntil { streamer.continuations.count == 1 }
        let stream = streamer.continuations[0]
        stream.yield(.status(.searching))
        await waitUntil { store.messages.last?.streamStatus == .searching }
        XCTAssertEqual(store.messages.last?.content, "")
        stream.yield(.status(.reading))
        await waitUntil { store.messages.last?.streamStatus == .reading }
        stream.yield(.delta("Hi"))
        await waitUntil { store.messages.last?.content == "Hi" }
        XCTAssertNil(store.messages.last?.streamStatus)
        // A later tool round never covers text that's already showing.
        stream.yield(.status(.searching))
        try? await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertNil(store.messages.last?.streamStatus)
        stream.yield(.done(sources: []))
        stream.finish()
        await send.value
        XCTAssertNil(store.messages.last?.streamStatus)
    }

    // MARK: - H4: an answer always lands in the conversation it started in

    func testSessionSwitchesAreRefusedWhileAnAnswerStreams() async {
        let streamer = ControlledStreamer()
        let history = StubHistory()
        history.seeded = [ChatMessage(id: "1", role: .user, content: "old q")]
        let queue = PersistQueue()
        let store = makeStore(streamer: streamer, history: history, persistQueue: queue)
        await store.loadHistoryOnce()
        let conversationA = UUID()
        await store.openConversation(id: conversationA, title: "Kyoto")

        let send = Task { await store.send("follow-up") }
        await waitUntil { streamer.continuations.count == 1 }
        XCTAssertTrue(store.isStreaming)

        store.startNewChat()
        await store.openConversation(id: UUID(), title: "Other")
        XCTAssertTrue(store.isExplicitSession)
        XCTAssertEqual(store.sessionTitle, "Kyoto")
        XCTAssertEqual(store.messages.count, 3, "old q + follow-up + the streaming answer stay on screen")

        streamer.continuations[0].yield(.delta("answer"))
        streamer.continuations[0].yield(.done(sources: []))
        streamer.continuations[0].finish()
        await send.value
        await queue.drain()

        XCTAssertEqual(store.messages.map(\.content), ["old q", "follow-up", "answer"])
        XCTAssertEqual(history.persisted.map(\.role), ["user", "assistant"])
        XCTAssertEqual(Set(history.persisted.map(\.conversationId)), [conversationA])
        XCTAssertTrue(history.titlesSet.isEmpty, "An already-titled conversation is never re-titled")
        // Once the answer landed, switching works again.
        store.startNewChat()
        XCTAssertTrue(store.messages.isEmpty)
        XCTAssertEqual(store.lastLoaded, ChatStore.LetGoConversation(id: conversationA, title: "Kyoto"))
    }

    func testLeavingTheTabMidAnswerLetsGoOnlyAfterTheAnswerLands() async {
        let streamer = ControlledStreamer()
        let history = StubHistory()
        history.seeded = [ChatMessage(id: "1", role: .user, content: "old q")]
        let queue = PersistQueue()
        let store = makeStore(streamer: streamer, history: history, persistQueue: queue)
        let conversationA = UUID()
        await store.openConversation(id: conversationA, title: "Kyoto")

        let send = Task { await store.send("follow-up") }
        await waitUntil { streamer.continuations.count == 1 }
        store.letGoIfExplicit()
        XCTAssertTrue(store.isExplicitSession, "The let-go waits for the answer")
        XCTAssertEqual(store.messages.count, 3)

        streamer.continuations[0].yield(.delta("answer"))
        streamer.continuations[0].yield(.done(sources: []))
        streamer.continuations[0].finish()
        await send.value
        await queue.drain()

        XCTAssertTrue(store.messages.isEmpty, "Let go once the answer was finalized")
        XCTAssertFalse(store.isExplicitSession)
        XCTAssertEqual(store.lastLoaded, ChatStore.LetGoConversation(id: conversationA, title: "Kyoto"))
        XCTAssertEqual(history.persisted.map(\.conversationId), [conversationA, conversationA])
        XCTAssertEqual(history.persisted.last?.content, "answer")
    }

    func testComingBackBeforeTheAnswerLandsKeepsTheConversation() async {
        let streamer = ControlledStreamer()
        let history = StubHistory()
        history.seeded = [ChatMessage(id: "1", role: .user, content: "old q")]
        let store = makeStore(streamer: streamer, history: history)
        await store.openConversation(id: UUID(), title: "Kyoto")

        let send = Task { await store.send("follow-up") }
        await waitUntil { streamer.continuations.count == 1 }
        store.letGoIfExplicit()
        store.cancelPendingLetGo()
        streamer.continuations[0].yield(.delta("answer"))
        streamer.continuations[0].yield(.done(sources: []))
        streamer.continuations[0].finish()
        await send.value

        XCTAssertEqual(store.messages.map(\.content), ["old q", "follow-up", "answer"])
        XCTAssertTrue(store.isExplicitSession)
        XCTAssertNil(store.lastLoaded)
    }

    func testAutoTitleOnNewSessionFirstExchange() async {
        let streamer = StubStreamer()
        streamer.events = [.delta("x"), .done(sources: [])]
        let history = StubHistory()
        history.generatedTitle = "Generated Title"
        let queue = PersistQueue()
        let store = makeStore(streamer: streamer, history: history, persistQueue: queue)
        await store.loadHistoryOnce()
        await store.send("what did I save about MCP?")
        // Optimistic fallback lands synchronously (no "Untitled" flash)…
        XCTAssertEqual(store.sessionTitle, "what did I save about MCP?")
        await queue.drain()
        await Task.yield()
        // …and the generated title replaces it once the dispatch drains — written to the
        // exchange's own conversation.
        XCTAssertEqual(store.sessionTitle, "Generated Title")
        XCTAssertEqual(history.titlesSet.count, 1)
        XCTAssertEqual(history.titlesSet.first?.0, history.createdIds.first)
        XCTAssertEqual(history.titlesSet.first?.1, "Generated Title")
    }

    // MARK: - L3: an early send can't split an exchange across two conversations

    func testSendBeforeTheOpenTimeResolutionWaitsForIt() async {
        let streamer = StubStreamer()
        streamer.events = [.delta("x"), .done(sources: [])]
        let history = StubHistory()
        let clock = Clock()
        let latestId = UUID()
        history.latest = ChatSessions.Candidate(id: latestId, title: "t", lastMessageAt: clock.current - 60)
        history.seeded = [ChatMessage(id: "1", role: .user, content: "q1"),
                          ChatMessage(id: "2", role: .assistant, content: "a1")]
        history.holdLatest = true
        let queue = PersistQueue()
        let store = makeStore(streamer: streamer, history: history, clock: clock, persistQueue: queue)

        let load = Task { await store.loadHistoryOnce() }
        await waitUntil { history.latestCallCount == 1 }
        let send = Task { await store.send("early question") }
        await waitUntil { store.isStreaming }
        try? await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertTrue(streamer.askedMessages.isEmpty, "The send waits for the session to resolve")
        XCTAssertTrue(history.createdIds.isEmpty)

        history.releaseLatest()
        await load.value
        await send.value
        await queue.drain()

        XCTAssertTrue(history.createdIds.isEmpty, "The early send continues the latest session instead of minting a second one")
        XCTAssertEqual(history.persisted.map(\.conversationId), [latestId, latestId])
        XCTAssertEqual(store.messages.map(\.content), ["q1", "a1", "early question", "x"])
    }

    func testNewChatDuringTheOpenTimeResolutionIsNotOverridden() async {
        let streamer = StubStreamer()
        streamer.events = [.delta("x"), .done(sources: [])]
        let history = StubHistory()
        let clock = Clock()
        history.latest = ChatSessions.Candidate(id: UUID(), title: "old", lastMessageAt: clock.current - 60)
        history.seeded = [ChatMessage(id: "1", role: .user, content: "q1")]
        history.holdLatest = true
        let store = makeStore(streamer: streamer, history: history, clock: clock)

        let load = Task { await store.loadHistoryOnce() }
        await waitUntil { history.latestCallCount == 1 }
        store.startNewChat()
        history.releaseLatest()
        await load.value

        XCTAssertTrue(store.messages.isEmpty, "A late resolution must not restore over a new chat")
        XCTAssertNil(store.sessionTitle)
        await store.send("fresh question")
        XCTAssertEqual(history.createdIds.count, 1)
        XCTAssertEqual(streamer.lastHistory, [])
    }

    // MARK: - Sessions (web 2026-08-27/28 model)

    func testStaleSessionStartsFreshAndSendsNoHistory() async {
        let streamer = StubStreamer()
        streamer.events = [.delta("x"), .done(sources: [])]
        let history = StubHistory()
        let clock = Clock()
        history.latest = ChatSessions.Candidate(id: UUID(), title: "old",
                                                 lastMessageAt: clock.current - 4 * 3600)
        history.seeded = [ChatMessage(id: "1", role: .user, content: "stale turn")]
        let store = makeStore(streamer: streamer, history: history, clock: clock)
        await store.loadHistoryOnce()
        XCTAssertTrue(store.messages.isEmpty, "A 4h-old session must not restore onto the screen")
        await store.send("new question")
        XCTAssertEqual(history.createdIds.count, 1, "The gap must mint a new session row")
        XCTAssertEqual(streamer.lastHistory, [], "A brand-new session sends no prior turns")
    }

    func testGapDuringOpenSessionMintsNewRowAndClearsThread() async {
        let streamer = StubStreamer()
        streamer.events = [.delta("x"), .done(sources: [])]
        let history = StubHistory()
        let clock = Clock()
        history.latest = ChatSessions.Candidate(id: UUID(), title: "t", lastMessageAt: clock.current - 60)
        history.seeded = [ChatMessage(id: "1", role: .user, content: "q1"),
                          ChatMessage(id: "2", role: .assistant, content: "a1")]
        let store = makeStore(streamer: streamer, history: history, clock: clock)
        await store.loadHistoryOnce()
        XCTAssertEqual(store.messages.count, 2)
        clock.advance(hours: 3.5)
        await store.send("later question")
        XCTAssertEqual(history.createdIds.count, 1)
        XCTAssertEqual(streamer.lastHistory, [])
        // Stale thread cleared; only the new exchange remains on screen.
        XCTAssertEqual(store.messages.map(\.content), ["later question", "x"])
    }

    func testOpenConversationIsGapExempt() async {
        let streamer = StubStreamer()
        streamer.events = [.delta("x"), .done(sources: [])]
        let history = StubHistory()
        history.seeded = [ChatMessage(id: "1", role: .user, content: "old q")]
        let clock = Clock()
        let store = makeStore(streamer: streamer, history: history, clock: clock)
        await store.loadHistoryOnce()
        let oldId = UUID()
        await store.openConversation(id: oldId, title: "Kyoto")
        XCTAssertTrue(store.isExplicitSession)
        XCTAssertEqual(store.sessionTitle, "Kyoto")
        XCTAssertEqual(store.messages.count, 1)
        clock.advance(hours: 30)
        await store.send("follow-up")
        XCTAssertTrue(history.createdIds.isEmpty, "Explicit resumes are exempt from the gap")
    }

    func testLetGoRemembersAndRestoreReloads() async {
        let streamer = StubStreamer()
        let history = StubHistory()
        history.seeded = [ChatMessage(id: "1", role: .user, content: "old q")]
        let store = makeStore(streamer: streamer, history: history)
        await store.loadHistoryOnce()
        await store.openConversation(id: UUID(), title: "Kyoto")

        store.letGoIfExplicit()
        XCTAssertTrue(store.messages.isEmpty)
        XCTAssertFalse(store.isExplicitSession)
        XCTAssertEqual(store.lastLoaded?.title, "Kyoto")

        await store.restorePrevious()
        XCTAssertNil(store.lastLoaded)
        XCTAssertTrue(store.isExplicitSession)
        XCTAssertEqual(store.messages.count, 1)
    }

    func testLetGoIsNoOpForImplicitSession() async {
        let streamer = StubStreamer()
        let history = StubHistory()
        let clock = Clock()
        history.latest = ChatSessions.Candidate(id: UUID(), title: "t", lastMessageAt: clock.current - 60)
        history.seeded = [ChatMessage(id: "1", role: .user, content: "q1")]
        let store = makeStore(streamer: streamer, history: history, clock: clock)
        await store.loadHistoryOnce()
        store.letGoIfExplicit()
        XCTAssertEqual(store.messages.count, 1, "An implicit (gap-window) session survives tab switches")
        XCTAssertNil(store.lastLoaded)
    }

    func testStartNewChatForcesNewSession() async {
        let streamer = StubStreamer()
        streamer.events = [.delta("x"), .done(sources: [])]
        let history = StubHistory()
        let clock = Clock()
        history.latest = ChatSessions.Candidate(id: UUID(), title: "t", lastMessageAt: clock.current - 60)
        history.seeded = [ChatMessage(id: "1", role: .user, content: "q1")]
        let store = makeStore(streamer: streamer, history: history, clock: clock)
        await store.loadHistoryOnce()
        store.startNewChat()
        XCTAssertTrue(store.messages.isEmpty)
        await store.send("fresh question")
        XCTAssertEqual(history.createdIds.count, 1, "Start-new-chat bypasses the gap rule on next send")
        XCTAssertEqual(streamer.lastHistory, [])
    }
}

final class ChatSessionsTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_756_400_000)

    func testResolveTargetGapBoundaries() {
        let id = UUID()
        let fresh = ChatSessions.Candidate(id: id, title: "t", lastMessageAt: base - (3 * 3600 - 1))
        XCTAssertEqual(ChatSessions.resolveTarget(latest: fresh, now: base),
                       .continueSession(id: id, title: "t"))
        let stale = ChatSessions.Candidate(id: id, title: "t", lastMessageAt: base - 3 * 3600)
        XCTAssertEqual(ChatSessions.resolveTarget(latest: stale, now: base), .new)
        XCTAssertEqual(ChatSessions.resolveTarget(latest: nil, now: base), .new)
        let missingTimestamp = ChatSessions.Candidate(id: id, title: nil, lastMessageAt: nil)
        XCTAssertEqual(ChatSessions.resolveTarget(latest: missingTimestamp, now: base), .new)
    }

    func testBucketLabels() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        // A fixed Wednesday noon, so Today/Yesterday/This week are all unambiguous.
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 26, hour: 12))!
        let day: (Int, Int, Int) -> Date = { y, m, d in
            calendar.date(from: DateComponents(year: y, month: m, day: d, hour: 9))!
        }
        XCTAssertEqual(ChatSessions.bucketLabel(for: day(2026, 8, 26), now: now, calendar: calendar), "Today")
        XCTAssertEqual(ChatSessions.bucketLabel(for: day(2026, 8, 25), now: now, calendar: calendar), "Yesterday")
        XCTAssertEqual(ChatSessions.bucketLabel(for: day(2026, 8, 24), now: now, calendar: calendar), "This week")
        XCTAssertEqual(ChatSessions.bucketLabel(for: day(2026, 8, 14), now: now, calendar: calendar), "August")
        XCTAssertEqual(ChatSessions.bucketLabel(for: day(2025, 12, 30), now: now, calendar: calendar), "December 2025")
    }

    func testParseTimestampAcceptsBothPrecisions() {
        XCTAssertNotNil(ChatSessions.parseTimestamp("2026-08-29T12:34:56.789+00:00"))
        XCTAssertNotNil(ChatSessions.parseTimestamp("2026-08-29T12:34:56+00:00"))
        XCTAssertNil(ChatSessions.parseTimestamp(nil))
        XCTAssertNil(ChatSessions.parseTimestamp("not a date"))
    }
}
