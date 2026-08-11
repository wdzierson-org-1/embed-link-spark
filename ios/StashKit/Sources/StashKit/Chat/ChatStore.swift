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
    public private(set) var messages: [ChatMessage] = []
    public private(set) var isStreaming = false
    public var errorMessage: String?
    /// Set alongside `errorMessage` when `ask` fails, carrying the question that was rolled back
    /// so the caller can restore it into the composer — Swift analog of ChatMole.tsx:293's
    /// `setInput(question)` (there's no shared `input` state to write back into here).
    public var errorRestoredInput: String?

    private let userId: UUID
    private let streamer: ChatStreaming
    private let history: ChatHistoryStoring
    private let capture: CaptureAPI
    private let accessToken: @Sendable () async throws -> String

    private var conversationId: UUID?
    private var historyLoaded = false

    public init(userId: UUID, streamer: ChatStreaming, history: ChatHistoryStoring, capture: CaptureAPI,
                accessToken: @escaping @Sendable () async throws -> String) {
        self.userId = userId
        self.streamer = streamer
        self.history = history
        self.capture = capture
        self.accessToken = accessToken
    }

    /// ChatMole.tsx:70-116 — loads (or starts) the durable thread. Idempotent, like the web's
    /// `historyLoadedRef` guard, so a view can call it from `.task` without double-loading.
    public func loadHistoryOnce() async {
        guard !historyLoaded else { return }
        historyLoaded = true
        do {
            let conversationId = try await history.loadOrCreateConversation(userId: userId)
            self.conversationId = conversationId
            let restored = try await history.loadHistory(conversationId: conversationId, limit: 60)
            if !restored.isEmpty, messages.isEmpty {
                messages = restored
            }
        } catch {
            print("Failed to load chat history (non-fatal): \(error)")
        }
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
        let userMessageId = "u-\(UUID().uuidString)"
        messages.append(ChatMessage(id: userMessageId, role: .user, content: question))
        await persistIfPossible(role: "user", content: question, sourceItemIds: nil)

        // Web parity: the history sent to the model is every prior user/assistant turn
        // *including* the question just appended above (ChatMole.tsx:243-245 reads
        // `messagesRef.current` after `pushMessage`) — the edge function also receives the
        // question separately as `message`, so it appears twice by design, not a bug here.
        let priorTurns = messages
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
                    await persistIfPossible(role: "assistant", content: streamed, sourceItemIds: sourceIds)
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

    private func setAssistantContent(id: String, content: String) {
        guard let idx = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[idx].content = content
    }

    private func setAssistantDone(id: String, sources: [ChatSource]) {
        guard let idx = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[idx].sources = sources
        messages[idx].isStreaming = false
    }

    private func persistIfPossible(role: String, content: String, sourceItemIds: [UUID]?) async {
        guard let conversationId else { return }
        await history.persist(conversationId: conversationId, role: role, content: content, sourceItemIds: sourceItemIds)
    }
}
