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
    var latest: ChatSessions.Candidate?
    var createdIds: [UUID] = []
    var generatedTitle: String?
    var titlesSet: [(UUID, String)] = []
    var listed: [ConversationListRow] = []

    func latestConversation(userId: UUID) async throws -> ChatSessions.Candidate? { latest }
    func createConversation(userId: UUID) async throws -> UUID {
        let id = UUID()
        createdIds.append(id)
        return id
    }
    func loadHistory(conversationId: UUID, limit: Int) async throws -> [ChatMessage] { seeded }
    func persist(conversationId: UUID, role: String, content: String, sourceItemIds: [UUID]?) async {
        persisted.append((role, content, sourceItemIds))
    }
    func generateTitle(for question: String) async -> String? { generatedTitle }
    func setTitle(conversationId: UUID, title: String) async { titlesSet.append((conversationId, title)) }
    func listConversations(searchText: String?, pageLimit: Int, pageOffset: Int) async throws -> [ConversationListRow] { listed }
}

@MainActor
final class ChatStoreTests: XCTestCase {
    /// Mutable clock for gap-rule tests — `advance` between calls simulates silence.
    final class Clock: @unchecked Sendable {
        var current = Date(timeIntervalSince1970: 1_756_400_000)
        func advance(hours: Double) { current += hours * 3600 }
    }

    func makeStore(streamer: StubStreamer, history: StubHistory = StubHistory(),
                   clock: Clock = Clock(),
                   persistDispatch: @escaping (@escaping @Sendable () async -> Void) -> Void = { work in Task { await work() } }) -> ChatStore {
        ChatStore(userId: UUID(), streamer: streamer, history: history,
                  capture: CaptureAPI(poster: StubPoster()), accessToken: { "jwt" },
                  now: { clock.current },
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
        // No prior conversation → the session row was created lazily on this first send.
        XCTAssertEqual(history.createdIds.count, 1)
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
        let clock = Clock()
        // A fresh (< 3h old) latest conversation continues on open, restoring its thread.
        history.latest = ChatSessions.Candidate(id: UUID(), title: "t", lastMessageAt: clock.current - 60)
        history.seeded = [ChatMessage(id: "1", role: .user, content: "q1", sources: [], savedItemTitle: nil, savedKind: nil, isStreaming: false),
                          ChatMessage(id: "2", role: .assistant, content: "a1", sources: [], savedItemTitle: nil, savedKind: nil, isStreaming: false)]
        let store = makeStore(streamer: streamer, history: history, clock: clock)
        await store.loadHistoryOnce()
        await store.send("q2")
        XCTAssertEqual(streamer.lastHistory, [["role": "user", "content": "q1"],
                                              ["role": "assistant", "content": "a1"],
                                              ["role": "user", "content": "q2"]])
        XCTAssertTrue(history.createdIds.isEmpty, "A continuing session must not create a new row")
    }

    func testSaveNoteRouteMakesChip() async {
        let streamer = StubStreamer()
        let store = makeStore(streamer: streamer)
        await store.loadHistoryOnce()
        await store.send("remember: buy milk")   // StubPoster returns empty Data → capture throws → chip removed + error
        XCTAssertTrue(store.messages.isEmpty)
        XCTAssertNotNil(store.errorMessage)
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

    func testAutoTitleOnNewSessionFirstExchange() async {
        let streamer = StubStreamer()
        streamer.events = [.delta("x"), .done(sources: [])]
        let history = StubHistory()
        history.generatedTitle = "Generated Title"
        var pending: [@Sendable () async -> Void] = []
        let store = makeStore(streamer: streamer, history: history,
                              persistDispatch: { pending.append($0) })
        await store.loadHistoryOnce()
        await store.send("what did I save about MCP?")
        // Optimistic fallback lands synchronously (no "Untitled" flash)…
        XCTAssertEqual(store.sessionTitle, "what did I save about MCP?")
        for work in pending { await work() }
        await Task.yield()
        // …and the generated title replaces it once the dispatch drains.
        XCTAssertEqual(store.sessionTitle, "Generated Title")
        XCTAssertEqual(history.titlesSet.count, 1)
        XCTAssertEqual(history.titlesSet.first?.1, "Generated Title")
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
