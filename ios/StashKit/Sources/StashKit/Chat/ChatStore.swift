import Foundation
import Observation

/// Errors internal to `ChatStore.ask` — never escape the store; caught locally to drive the
/// same rollback path as a transport-level throw (ChatMole.tsx:283-284,289 both funnel into one
/// `catch`).
private enum ChatStoreError: Error {
    case server(String)
    case emptyResponse
}

/// Port of ChatMole.tsx's `handleSend` / `ask` / `saveUrl` / `saveNote` (:169-315) — the Ask
/// surface's state machine. Routes free text via `classifyMessage`, then either drops a pending
/// `.saved` chip that settles (or reverts) once `CaptureAPI` responds, or streams an assistant
/// reply and rolls both sides of the exchange back on failure.
@MainActor
@Observable
public final class ChatStore {
    /// ChatMole's `sessionRef`: which conversation row sends persist into, when it last saw a
    /// message, and whether it was explicitly resumed (gap-exempt).
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

    public private(set) var messages: [ChatMessage] = []
    public private(set) var isStreaming = false
    public var errorMessage: String?
    /// Set alongside `errorMessage` when `ask` fails, carrying the question that was rolled back
    /// so the caller can restore it into the composer — Swift analog of ChatMole.tsx:293's
    /// `setInput(question)` (there's no shared `input` state to write back into here).
    public var errorRestoredInput: String?
    /// The current session's title (nil until auto-titled, or for a fresh thread).
    public private(set) var sessionTitle: String?
    /// True while an explicitly opened old conversation is on screen (drives the title pill;
    /// exempts the session from the 3h gap).
    public private(set) var isExplicitSession = false
    /// Non-nil when an explicitly loaded conversation was let go — drives the restore banner.
    public private(set) var lastLoaded: LetGoConversation?

    private let userId: UUID
    private let streamer: ChatStreaming
    private let history: ChatHistoryStoring
    private let capture: CaptureAPI
    private let accessToken: @Sendable () async throws -> String
    /// Injectable clock so gap-rule tests don't sleep for three hours.
    private let now: () -> Date
    /// How a `persist` call is scheduled once its `work` closure is built. Production default
    /// (`{ work in Task { await work() } }`) detaches — true fire-and-forget, matching
    /// ChatMole.tsx:121-131 (`void supabase.from('messages').insert(...).then(...)`, never
    /// awaited by the caller) and this codebase's own idiom for background-durable writes
    /// (EmbeddingRefresher.schedule, Debouncer) — so `ask` never blocks the next step of the
    /// send flow on a DB round-trip. Exists as an injection point purely so tests can swap in a
    /// dispatcher that collects `work` items instead of racing a detached `Task`, then drain them
    /// explicitly for deterministic assertions on `ChatHistoryStoring.persist` calls. The
    /// auto-title write rides the same dispatcher for the same reason.
    private let persistDispatch: (@escaping @Sendable () async -> Void) -> Void

    private var session = Session()
    private var historyLoaded = false

    public init(userId: UUID, streamer: ChatStreaming, history: ChatHistoryStoring, capture: CaptureAPI,
                accessToken: @escaping @Sendable () async throws -> String,
                now: @escaping () -> Date = { Date() },
                persistDispatch: @escaping (@escaping @Sendable () async -> Void) -> Void = { work in Task { await work() } }) {
        self.userId = userId
        self.streamer = streamer
        self.history = history
        self.capture = capture
        self.accessToken = accessToken
        self.now = now
        self.persistDispatch = persistDispatch
    }

    // MARK: - Session lifecycle (web 2026-08-27/28 model)

    /// Open-time resolution: continue the latest conversation iff it's under the 3h gap old,
    /// else start with an empty thread (the row is created lazily on first send). Idempotent,
    /// like the web's `historyLoadedRef` guard, so a view can call it from `.task` freely.
    public func loadHistoryOnce() async {
        guard !historyLoaded else { return }
        historyLoaded = true
        do {
            let latest = try await history.latestConversation(userId: userId)
            guard case .continueSession(let id, let title) = ChatSessions.resolveTarget(latest: latest, now: now())
            else { return }
            session = Session(id: id, title: title, explicit: false,
                              lastMessageAt: latest?.lastMessageAt ?? now())
            sessionTitle = title
            let restored = try await history.loadHistory(conversationId: id, limit: 60)
            if !restored.isEmpty, messages.isEmpty {
                messages = restored
            }
        } catch {
            print("Failed to load chat history (non-fatal): \(error)")
        }
    }

    /// Open a specific conversation from the Conversations list: gap-exempt, title pill shown,
    /// and any remembered let-go conversation is superseded.
    public func openConversation(id: UUID, title: String?) async {
        lastLoaded = nil
        session = Session(id: id, title: title, explicit: true, lastMessageAt: now())
        sessionTitle = title
        isExplicitSession = true
        do {
            messages = try await history.loadHistory(conversationId: id, limit: 200)
        } catch {
            messages = []
            errorMessage = "Couldn't load that conversation — try again."
        }
    }

    /// Fresh context on demand — the old thread stays reachable in Conversations (and via the
    /// restore banner if it was an explicit load).
    public func startNewChat() {
        if session.explicit, let id = session.id {
            lastLoaded = LetGoConversation(id: id, title: session.title)
        }
        resetToFreshSession()
    }

    /// The iOS analog of collapsing the web mole: leaving the Ask tab lets go of an explicitly
    /// loaded old conversation — the thread clears (reopening shows a mostly clean slate) and
    /// the conversation is remembered for the one-tap restore banner. A non-explicit session
    /// just drops its (already false) explicit flag, exactly like the web.
    public func letGoIfExplicit() {
        guard session.explicit, let id = session.id else {
            session.explicit = false
            return
        }
        lastLoaded = LetGoConversation(id: id, title: session.title)
        resetToFreshSession()
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

    private func resetToFreshSession() {
        messages = []
        session = Session()
        sessionTitle = nil
        isExplicitSession = false
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
        session = Session(id: id, title: nil, explicit: false, lastMessageAt: now())
        sessionTitle = nil
        isExplicitSession = false
        return (id, true)
    }

    /// ChatMole.tsx:298-315 — classify then route; one send in flight at a time.
    public func send(_ raw: String) async {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isStreaming else { return }

        errorMessage = nil
        errorRestoredInput = nil
        isStreaming = true
        defer { isStreaming = false }

        switch classifyMessage(text) {
        case .saveURL(let url, let note):
            await saveURL(url, note: note)
        case .saveNote(let note):
            await saveNote(note)
        case .ask:
            await ask(text)
        }
    }

    // MARK: - Save routes (ChatMole.tsx:173-225)

    private func saveURL(_ url: String, note: String) async {
        let pendingId = "saved-\(UUID().uuidString)"
        messages.append(ChatMessage(id: pendingId, role: .saved, content: url,
                                    savedItemTitle: "Saving…", savedKind: "link"))
        do {
            let token = try await accessToken()
            let item = try await capture.addURL(url, note: note, isPublic: false, accessToken: token)
            let title = item.title.flatMap { $0.isEmpty ? nil : $0 } ?? url
            setSavedTitle(id: pendingId, title: title)
        } catch {
            messages.removeAll { $0.id == pendingId }
            errorMessage = "Could not save link. Please try again."
        }
    }

    private func saveNote(_ note: String) async {
        let pendingId = "saved-\(UUID().uuidString)"
        messages.append(ChatMessage(id: pendingId, role: .saved, content: note,
                                    savedItemTitle: "Saving…", savedKind: "note"))
        do {
            let token = try await accessToken()
            let item = try await capture.addNote(content: note, title: nil, isPublic: false, accessToken: token)
            let fallback = String(note.prefix(60))
            let title = item.title.flatMap { $0.isEmpty ? nil : $0 } ?? fallback
            setSavedTitle(id: pendingId, title: title)
        } catch {
            messages.removeAll { $0.id == pendingId }
            errorMessage = "Could not save note. Please try again."
        }
    }

    private func setSavedTitle(id: String, title: String) {
        guard let idx = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[idx].savedItemTitle = title
    }

    // MARK: - Ask (ChatMole.tsx:227-296)

    private func ask(_ question: String) async {
        // Session resolution happens BEFORE the user turn is appended (web ask():289) — a stale
        // session clears the on-screen thread first, so the new exchange starts clean.
        let (conversationId, isNew) = await ensureSessionForSend()

        let userMessageId = "u-\(UUID().uuidString)"
        messages.append(ChatMessage(id: userMessageId, role: .user, content: question))
        session.lastMessageAt = now()
        persistIfPossible(role: "user", content: question, sourceItemIds: nil)

        // Web parity: for a continuing session the history sent to the model is every prior
        // user/assistant turn *including* the question just appended above — the edge function
        // also receives the question separately as `message`, so it appears twice by design. A
        // brand-new session sends none (ChatMole.tsx: "the old session's messages must not leak
        // into the request").
        let priorTurns = isNew ? [] : messages
            .filter { $0.role == .user || $0.role == .assistant }
            .map { ["role": $0.role.rawValue, "content": $0.content] }

        let assistantId = "a-\(UUID().uuidString)"
        messages.append(ChatMessage(id: assistantId, role: .assistant, content: "", isStreaming: true))

        do {
            let token = try await accessToken()
            var streamed = ""
            for try await event in streamer.stream(message: question, history: priorTurns, accessToken: token) {
                switch event {
                case .delta(let text):
                    streamed += text
                    setAssistantContent(id: assistantId, content: streamed)
                case .done(let sources):
                    setAssistantDone(id: assistantId, sources: sources)
                    let sourceIds = sources.isEmpty ? nil : sources.map(\.id)
                    persistIfPossible(role: "assistant", content: streamed, sourceItemIds: sourceIds)
                    session.lastMessageAt = now()
                    autoTitleIfNeeded(question: question, conversationId: conversationId)
                case .serverError(let message):
                    throw ChatStoreError.server(message)
                }
            }
            guard !streamed.isEmpty else { throw ChatStoreError.emptyResponse }
        } catch {
            messages.removeAll { $0.id == userMessageId || $0.id == assistantId }
            errorRestoredInput = question
            errorMessage = "Failed to get a response."
        }
    }

    /// ChatMole.tsx's auto-title branch, after the first completed exchange of an untitled
    /// session: `generate-title` (falling back to the question), clipped to 80 chars, written
    /// fire-and-forget. The visible `sessionTitle` updates optimistically with the fallback so
    /// the Conversations list and title pill never show "Untitled" for a session the user is
    /// actively in; the generated title replaces it when the dispatch completes.
    private func autoTitleIfNeeded(question: String, conversationId: UUID?) {
        guard sessionTitle == nil, let conversationId else { return }
        let fallback = String(question.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        sessionTitle = fallback
        session.title = fallback
        let history = self.history
        persistDispatch { [weak self] in
            let title = String((await history.generateTitle(for: question) ?? fallback).prefix(80))
            await history.setTitle(conversationId: conversationId, title: title)
            await MainActor.run { [weak self] in
                guard let self, self.session.id == conversationId else { return }
                self.sessionTitle = title
                self.session.title = title
            }
        }
    }

    private func setAssistantContent(id: String, content: String) {
        guard let idx = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[idx].content = content
    }

    private func setAssistantDone(id: String, sources: [ChatSource]) {
        guard let idx = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[idx].sources = sources
        messages[idx].isStreaming = false
    }

    /// Builds the persist call and hands it to `persistDispatch` rather than awaiting it — the
    /// closure captures only `Sendable` values (never `self`), so it's safe to run detached.
    private func persistIfPossible(role: String, content: String, sourceItemIds: [UUID]?) {
        guard let conversationId = session.id else { return }
        let history = self.history
        persistDispatch {
            await history.persist(conversationId: conversationId, role: role, content: content, sourceItemIds: sourceItemIds)
        }
    }
}
