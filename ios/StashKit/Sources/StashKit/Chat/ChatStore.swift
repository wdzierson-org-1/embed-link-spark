import Foundation
import Observation

/// Errors internal to `ChatStore.ask` — never escape the store; caught locally to drive the
/// same finalize-or-roll-back decision as a transport-level throw.
private enum ChatStoreError: Error {
    case server(String)
    case emptyResponse
    case endedWithoutDone
}

/// Port of ChatMole.tsx's `handleSend` / `ask` — the Ask surface's state machine.
///
/// Retrieval-only (plan 15, M11): every message is a question for `chat-with-all-content`. The
/// old chat-as-capture routing (a URL or a `remember:` prefix saved an item instead of answering)
/// is gone, matching the all-platform decision in `docs/ui-changes.md` (2026-08-27, "Mole is
/// retrieval-only"): capture belongs to the Add tab and the share sheet.
///
/// Plan 15 hardening, each unit-tested in `ChatStoreTests`:
/// - **H4 — an answer stays in its conversation.** Every write an exchange makes (both persists,
///   `lastMessageAt`, the auto-title) targets the conversation id resolved when the question was
///   sent, never whatever session is current when the answer lands. And the session can't be
///   switched out from under a live answer: `startNewChat` / `openConversation` are refused while
///   `isStreaming` (the view disables their buttons), and leaving the tab (`letGoIfExplicit`)
///   is deferred until the answer is finalized — so an answer is never dropped or cross-filed.
/// - **L1 + the iOS spec's "SSE drop mid-answer: keep partial text, show retry".** A stream that
///   ends without `done` (clean EOF, dropped connection, mid-answer server error) keeps and
///   persists the partial answer and marks it `isInterrupted` (the bubble offers `retry`); only a
///   failure before the first token rolls the exchange back.
/// - **M1 — coalesced streaming.** Deltas publish at most every `streamPublishInterval` (first
///   token immediately), not per token.
/// - **L3 — no split exchanges.** `send` waits for the open-time session resolution (or an
///   explicit open) still in flight, and every session switch bumps an epoch that makes any
///   older in-flight load drop its result instead of overwriting the session a send is using.
/// - The server's `status` frames show as `ChatMessage.streamStatus` until the first token.
@MainActor
@Observable
public final class ChatStore {
    /// ChatMole's `sessionRef`: which conversation row sends persist into, when it last saw a
    /// message, its title, and whether it was explicitly resumed (gap-exempt).
    private struct Session {
        var id: UUID?
        var title: String?
        var explicit = false
        var lastMessageAt: Date = .distantPast
    }

    /// A loaded-then-let-go conversation, restorable with one tap (web's `lastLoaded`).
    public struct LetGoConversation: Equatable, Sendable {
        public let id: UUID
        public let title: String?
    }

    /// The in-flight answer: which bubble it fills and the text received so far.
    private struct LiveAnswer {
        let assistantId: String
        var coalescer: StreamingTextCoalescer
    }

    public private(set) var messages: [ChatMessage] = []
    /// True from the moment a question is sent until its answer is finalized (done, interrupted,
    /// or rolled back) — including any wait for the session to resolve first.
    public private(set) var isStreaming = false
    public var errorMessage: String?
    /// Set alongside `errorMessage` when a question is rolled back (it failed before its first
    /// token), carrying the question so the caller can restore it into the composer — Swift
    /// analog of ChatMole.tsx's `setInput(question)`.
    public var errorRestoredInput: String?
    /// Non-nil when an explicitly loaded conversation was let go — drives the restore banner.
    public private(set) var lastLoaded: LetGoConversation?

    /// The current session's title (nil until auto-titled, or for a fresh thread).
    public var sessionTitle: String? { session.title }
    /// True while an explicitly opened old conversation is on screen (drives the title pill;
    /// exempts the session from the 3h gap).
    public var isExplicitSession: Bool { session.explicit }

    private let userId: UUID
    private let streamer: ChatStreaming
    private let history: ChatHistoryStoring
    private let accessToken: @Sendable () async throws -> String
    /// Injectable clock so gap-rule tests don't sleep for three hours.
    private let now: () -> Date
    /// How often a streaming answer may republish (M1). 0 publishes every delta.
    private let streamPublishInterval: TimeInterval
    /// How a `persist` call is scheduled once its `work` closure is built. Production default
    /// (`{ work in Task { await work() } }`) detaches — true fire-and-forget, matching
    /// ChatMole.tsx's `void supabase.from('messages').insert(...)` — so `ask` never blocks on a
    /// DB round-trip. Tests swap in a dispatcher that collects `work` items and drains them
    /// explicitly. The auto-title write rides the same dispatcher for the same reason.
    private let persistDispatch: (@escaping @Sendable () async -> Void) -> Void

    private var session = Session()
    /// Bumped by every session switch; an async load captures it and drops its result if the
    /// session moved on meanwhile (L3, and an explicit open racing a new chat / let-go).
    @ObservationIgnored private var sessionEpoch = 0
    @ObservationIgnored private var historyRequested = false
    /// The open-time resolution or explicit open still loading, if any — `send` waits for it.
    @ObservationIgnored private var sessionLoad: Task<Void, Never>?
    /// The tab was left while an answer streamed into an explicit conversation — let go once the
    /// answer is finalized, unless the user comes back first (`cancelPendingLetGo`).
    @ObservationIgnored private var letGoPending = false
    @ObservationIgnored private var liveAnswer: LiveAnswer?

    public init(userId: UUID, streamer: ChatStreaming, history: ChatHistoryStoring,
                accessToken: @escaping @Sendable () async throws -> String,
                now: @escaping () -> Date = { Date() },
                streamPublishInterval: TimeInterval = 0.1,
                persistDispatch: @escaping (@escaping @Sendable () async -> Void) -> Void = { work in Task { await work() } }) {
        self.userId = userId
        self.streamer = streamer
        self.history = history
        self.accessToken = accessToken
        self.now = now
        self.streamPublishInterval = streamPublishInterval
        self.persistDispatch = persistDispatch
    }

    // MARK: - Session lifecycle (web 2026-08-27/28 model)

    /// Open-time resolution: continue the latest conversation iff it's under the 3h gap old,
    /// else start with an empty thread (the row is created lazily on first send). Idempotent,
    /// like the web's `historyLoadedRef` guard, so a view can call it from `.task` freely. The
    /// work runs in a store-owned task, so a view `.task` cancelled by a quick tab switch can't
    /// abort it half-way.
    public func loadHistoryOnce() async {
        if !historyRequested {
            historyRequested = true
            let startEpoch = sessionEpoch
            sessionLoad = Task { [weak self] in
                guard let self else { return }
                await self.resolveInitialSession(startEpoch: startEpoch)
            }
        }
        await sessionLoad?.value
    }

    private func resolveInitialSession(startEpoch: Int) async {
        do {
            let latest = try await history.latestConversation(userId: userId)
            // L3: a new chat / explicit open that happened meanwhile wins.
            guard startEpoch == sessionEpoch,
                  case .continueSession(let id, let title) = ChatSessions.resolveTarget(latest: latest, now: now())
            else { return }
            let epoch = claimSession(Session(id: id, title: title, explicit: false,
                                             lastMessageAt: latest?.lastMessageAt ?? now()))
            let restored = try await history.loadHistory(conversationId: id, limit: 60)
            guard epoch == sessionEpoch, messages.isEmpty, !restored.isEmpty else { return }
            messages = restored
        } catch {
            print("Failed to load chat history (non-fatal): \(error)")
        }
    }

    /// Open a specific conversation from the Conversations list: gap-exempt, title pill shown,
    /// and any remembered let-go conversation is superseded. Refused while an answer streams
    /// (H4 — the view disables the way in; this is the backstop).
    public func openConversation(id: UUID, title: String?) async {
        guard !isStreaming else { return }
        lastLoaded = nil
        letGoPending = false
        let epoch = claimSession(Session(id: id, title: title, explicit: true, lastMessageAt: now()))
        let load = Task { [weak self] in
            guard let self else { return }
            await self.loadExplicitConversation(id: id, epoch: epoch)
        }
        sessionLoad = load
        await load.value
    }

    private func loadExplicitConversation(id: UUID, epoch: Int) async {
        do {
            let loaded = try await history.loadHistory(conversationId: id, limit: 200)
            guard epoch == sessionEpoch else { return }
            messages = loaded
        } catch {
            guard epoch == sessionEpoch else { return }
            messages = []
            errorMessage = "Couldn't load that conversation — try again."
        }
    }

    /// Fresh context on demand — the old thread stays reachable in Conversations (and via the
    /// restore banner if it was an explicit load). Refused while an answer streams (H4).
    public func startNewChat() {
        guard !isStreaming else { return }
        if session.explicit, let id = session.id {
            lastLoaded = LetGoConversation(id: id, title: session.title)
        }
        resetToFreshSession()
    }

    /// The iOS analog of collapsing the web mole: leaving the Ask tab lets go of an explicitly
    /// loaded old conversation — the thread clears (reopening shows a mostly clean slate) and
    /// the conversation is remembered for the one-tap restore banner. An implicit (gap-window)
    /// session is untouched. While an answer streams the let-go waits for it to be finalized
    /// (H4): the answer lands and persists in its conversation first, then the thread clears.
    public func letGoIfExplicit() {
        guard session.explicit, session.id != nil else { return }
        if isStreaming {
            letGoPending = true
            return
        }
        performLetGo()
    }

    /// Back on the Ask tab before a deferred let-go ran: keep the conversation on screen.
    public func cancelPendingLetGo() {
        letGoPending = false
    }

    public func restorePrevious() async {
        guard let previous = lastLoaded else { return }
        await openConversation(id: previous.id, title: previous.title)
    }

    /// Pass-through for the Conversations screen (server-paged; search matches titles and
    /// message contents).
    public func listConversations(searchText: String?, pageLimit: Int, pageOffset: Int) async throws -> [ConversationListRow] {
        try await history.listConversations(searchText: searchText, pageLimit: pageLimit, pageOffset: pageOffset)
    }

    private func performLetGo() {
        guard session.explicit, let id = session.id else { return }
        lastLoaded = LetGoConversation(id: id, title: session.title)
        resetToFreshSession()
    }

    private func resetToFreshSession() {
        messages = []
        claimSession(Session())
    }

    /// Every session switch goes through here, so in-flight loads for the previous session can
    /// tell they were superseded. Returns the new epoch.
    @discardableResult
    private func claimSession(_ newSession: Session) -> Int {
        sessionEpoch += 1
        session = newSession
        return sessionEpoch
    }

    /// Returns the conversation id to persist into, creating a new session row when the 3h gap
    /// elapsed (`isNew: true`). Explicitly resumed sessions are exempt from the gap. A stale
    /// session still on screen clears first — the new session starts a fresh thread.
    private func ensureSessionForSend() async -> (id: UUID?, isNew: Bool) {
        if let id = session.id, session.explicit || now().timeIntervalSince(session.lastMessageAt) < ChatSessions.sessionGap {
            return (id, false)
        }
        if session.id != nil { messages = [] }
        let id = try? await history.createConversation(userId: userId)
        claimSession(Session(id: id, title: nil, explicit: false, lastMessageAt: now()))
        return (id, true)
    }

    // MARK: - Send

    /// ChatMole.tsx `handleSend` — one question in flight at a time.
    public func send(_ raw: String) async {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isStreaming else { return }

        errorMessage = nil
        errorRestoredInput = nil
        isStreaming = true
        defer {
            isStreaming = false
            if letGoPending {
                letGoPending = false
                performLetGo()
            }
        }
        // L3: resolve against the session the user is looking at, not a half-loaded one.
        await sessionLoad?.value
        await ask(text)
    }

    /// Re-asks the question behind an interrupted answer as a new exchange (the partial answer
    /// stays in the thread and in history, exactly as the user saw it).
    public func retry(messageId: String) async {
        guard !isStreaming,
              let index = messages.firstIndex(where: { $0.id == messageId }),
              messages[index].role == .assistant, messages[index].isInterrupted,
              let question = messages[..<index].last(where: { $0.role == .user })?.content
        else { return }
        await send(question)
    }

    // MARK: - Ask (ChatMole.tsx ask())

    private func ask(_ question: String) async {
        // Session resolution happens BEFORE the user turn is appended (web ask()) — a stale
        // session clears the on-screen thread first, so the new exchange starts clean.
        let (conversationId, isNew) = await ensureSessionForSend()
        // H4: every write below targets `conversationId`; the auto-title decision uses the
        // title state this conversation had when the question was sent.
        let titledAtStart = session.title != nil

        let userMessageId = "u-\(UUID().uuidString)"
        messages.append(ChatMessage(id: userMessageId, role: .user, content: question))
        touch(conversationId)
        persist(role: "user", content: question, sourceItemIds: nil, into: conversationId)

        // Web parity: for a continuing session the history sent to the model is every prior
        // user/assistant turn *including* the question just appended above — the edge function
        // also receives the question separately as `message`, so it appears twice by design. A
        // brand-new session sends none (ChatMole.tsx: "the old session's messages must not leak
        // into the request").
        let priorTurns = isNew ? [] : messages.map { ["role": $0.role.rawValue, "content": $0.content] }

        let assistantId = "a-\(UUID().uuidString)"
        messages.append(ChatMessage(id: assistantId, role: .assistant, content: "", isStreaming: true))
        liveAnswer = LiveAnswer(assistantId: assistantId,
                                coalescer: StreamingTextCoalescer(interval: streamPublishInterval))
        let ticker = startPublishTicker()
        defer {
            ticker?.cancel()
            liveAnswer = nil
        }

        var sawDone = false
        do {
            let token = try await accessToken()
            stream: for try await event in streamer.stream(message: question, history: priorTurns, accessToken: token) {
                switch event {
                case .status(let status):
                    setAssistantStatus(id: assistantId, status: status)
                case .delta(let text):
                    if let publish = liveAnswer?.coalescer.append(text, at: Self.monotonicNow()) {
                        setAssistantContent(id: assistantId, content: publish)
                    }
                case .done(let sources):
                    sawDone = true
                    let streamed = liveAnswer?.coalescer.text ?? ""
                    guard !streamed.isEmpty else { throw ChatStoreError.emptyResponse }
                    // Bake citation markers into stable item links BEFORE persisting — web parity
                    // (ChatMole.tsx: `persistMessage('assistant', baked, …)`), so a reloaded
                    // answer's citations stay clickable without `sources` (`ChatCitations`).
                    let baked = ChatCitations.link(answer: streamed, sources: sources).text
                    setAssistantDone(id: assistantId, content: baked, sources: sources)
                    persist(role: "assistant", content: baked,
                            sourceItemIds: sources.isEmpty ? nil : sources.map(\.id), into: conversationId)
                    touch(conversationId)
                    autoTitleIfNeeded(question: question, conversationId: conversationId, titledAtStart: titledAtStart)
                    break stream
                case .serverError(let message):
                    throw ChatStoreError.server(message)
                }
            }
            if !sawDone { throw ChatStoreError.endedWithoutDone }
        } catch {
            let partial = liveAnswer?.coalescer.text ?? ""
            // Already finalized and persisted — a transport error after `done` changes nothing.
            if sawDone, !partial.isEmpty { return }
            if partial.isEmpty {
                messages.removeAll { $0.id == userMessageId || $0.id == assistantId }
                errorRestoredInput = question
                errorMessage = "Failed to get a response."
            } else {
                finalizeInterrupted(id: assistantId, partial: partial, conversationId: conversationId)
            }
        }
    }

    /// ChatMole.tsx's auto-title branch, after the first completed exchange of an untitled
    /// session: `generate-title` (falling back to the question), clipped to 80 chars, written
    /// fire-and-forget to THIS exchange's conversation. The visible title updates optimistically
    /// with the fallback — only while that conversation is still the one on screen — so the
    /// title pill never shows "Untitled" for a session the user is actively in; the generated
    /// title replaces it when the dispatch completes.
    private func autoTitleIfNeeded(question: String, conversationId: UUID?, titledAtStart: Bool) {
        guard let conversationId else { return }
        let onScreen = session.id == conversationId
        let alreadyTitled = onScreen ? session.title != nil : titledAtStart
        guard !alreadyTitled else { return }
        let fallback = String(question.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        if onScreen { session.title = fallback }
        let history = self.history
        persistDispatch { [weak self] in
            let title = String((await history.generateTitle(for: question) ?? fallback).prefix(80))
            await history.setTitle(conversationId: conversationId, title: title)
            await MainActor.run { [weak self] in
                guard let self, self.session.id == conversationId else { return }
                self.session.title = title
            }
        }
    }

    // MARK: - Streaming bubble updates

    private func setAssistantStatus(id: String, status: ChatStreamStatus) {
        guard let index = messages.firstIndex(where: { $0.id == id }),
              messages[index].content.isEmpty, messages[index].streamStatus != status
        else { return }
        messages[index].streamStatus = status
    }

    private func setAssistantContent(id: String, content: String) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        var message = messages[index]
        message.content = content
        message.streamStatus = nil
        messages[index] = message
    }

    /// `content` here is the BAKED text, not the raw streamed accumulator — matching the web's
    /// `{...m, content: baked, sources}`, so the in-memory message, what gets persisted, and what
    /// a reload sees are the same string from this point on.
    private func setAssistantDone(id: String, content: String, sources: [ChatSource]) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        var message = messages[index]
        message.content = content
        message.sources = sources
        message.isStreaming = false
        message.streamStatus = nil
        messages[index] = message
    }

    /// The stream ended before `done` with text already shown: keep it (flushing anything the
    /// coalescer held back), persist it into the exchange's conversation, and mark it for retry.
    /// No sources arrive without `done`, so nothing is baked; unresolved `[Title](#N)` markers
    /// render as plain text (`ChatCitations.stripUnresolvedMarkers`).
    private func finalizeInterrupted(id: String, partial: String, conversationId: UUID?) {
        if let index = messages.firstIndex(where: { $0.id == id }) {
            var message = messages[index]
            message.content = partial
            message.isStreaming = false
            message.streamStatus = nil
            message.isInterrupted = true
            messages[index] = message
        }
        persist(role: "assistant", content: partial, sourceItemIds: nil, into: conversationId)
        touch(conversationId)
    }

    /// Publishes whatever the coalescer held back, every `streamPublishInterval`, so a pause in
    /// the stream never strands the tail of the text. Nil when every delta publishes anyway.
    private func startPublishTicker() -> Task<Void, Never>? {
        guard streamPublishInterval > 0 else { return nil }
        let nanoseconds = UInt64(streamPublishInterval * 1_000_000_000)
        return Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: nanoseconds)
                guard !Task.isCancelled else { return }
                self?.flushLiveAnswer()
            }
        }
    }

    private func flushLiveAnswer() {
        guard let assistantId = liveAnswer?.assistantId,
              let text = liveAnswer?.coalescer.flush(at: Self.monotonicNow())
        else { return }
        setAssistantContent(id: assistantId, content: text)
    }

    private static func monotonicNow() -> TimeInterval {
        ProcessInfo.processInfo.systemUptime
    }

    // MARK: - Persistence

    /// `lastMessageAt` only moves for the session the exchange belongs to, and only while it's
    /// still the current one (a session no longer on screen has no gap rule to feed).
    private func touch(_ conversationId: UUID?) {
        guard let conversationId, session.id == conversationId else { return }
        session.lastMessageAt = now()
    }

    /// Builds the persist call and hands it to `persistDispatch` rather than awaiting it — the
    /// closure captures only `Sendable` values (never `self`), so it's safe to run detached. The
    /// target conversation is always explicit (H4), never read from the live session.
    private func persist(role: String, content: String, sourceItemIds: [UUID]?, into conversationId: UUID?) {
        guard let conversationId else { return }
        let history = self.history
        persistDispatch {
            await history.persist(conversationId: conversationId, role: role, content: content, sourceItemIds: sourceItemIds)
        }
    }

    #if DEBUG
    /// Proof-of-rendering hook only (Plan 8 Task 4) — replaces the thread with fixture messages
    /// directly, bypassing `ask()`'s real session/network machinery entirely. Exists because the
    /// standing test account is subscription-gate-blocked for real Ask answers (see
    /// `testAskSmoke`'s own doc comment), so citation-link rendering has no live-answer path to
    /// screenshot; `AskView`'s `--uitest-seed-citation-bubble` launch argument is the only caller.
    /// Compiled out of Release entirely.
    public func seedForScreenshot(_ messages: [ChatMessage]) {
        self.messages = messages
    }
    #endif
}
