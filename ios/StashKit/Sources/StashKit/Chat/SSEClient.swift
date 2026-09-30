import Foundation

public struct ChatSource: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let title: String?
    public let type: String?
    public let url: String?
    /// The 1-based citation number the model used inline (`[3]` / `[Title](#3)`) — wire field
    /// `n` from chat-with-all-content's `sourceEntries.map(...)` (index.ts:529), the same value
    /// the web keys its `bakeCitationLinks` map by. `ChatCitations.link` uses this, never array
    /// order, to stay correct when a cited answer skips numbers (e.g. cites [2] and [5] but not
    /// [1]/[3]/[4] — `sources` then has 2 entries whose `n` are 2 and 5, not 1 and 2).
    public let n: Int?

    public init(id: UUID, title: String?, type: String?, url: String?, n: Int? = nil) {
        self.id = id
        self.title = title
        self.type = type
        self.url = url
        self.n = n
    }
}

/// What the server's agent loop is doing between tokens — chat-with-all-content's OPTIONAL
/// `data:{status}` frames, emitted while a retrieval tool runs (index.ts: `search_stash` →
/// `searching`, `browse_catalog` → `browsing`, `get_item` → `reading`). Plan 15 surfaces them in
/// the empty placeholder bubble so a multi-second tool round reads as progress, not a stall.
public enum ChatStreamStatus: Equatable, Sendable {
    case searching
    case browsing
    case reading

    /// Wire value → status; nil for anything this build doesn't know (the contract marks these
    /// frames optional, so a new server-side status is ignored rather than mis-labelled).
    public init?(wireValue: String) {
        switch wireValue {
        case "searching": self = .searching
        case "browsing": self = .browsing
        case "reading": self = .reading
        default: return nil
        }
    }

    /// The copy shown in the placeholder bubble until the first token lands.
    public var label: String {
        switch self {
        case .searching: "Searching your stash…"
        case .browsing: "Browsing your stash…"
        case .reading: "Reading…"
        }
    }
}

public enum SSEEvent: Equatable, Sendable {
    case delta(String)
    case status(ChatStreamStatus)
    case done(sources: [ChatSource])
    case serverError(String)
}

/// One SSE line → event. Mirrors ChatMole.tsx's reader: only `data:` lines matter; the payload
/// is JSON; delta / done+sources / error — plus the optional `status` frames the web ignores
/// (plan 15: iOS shows them in the placeholder bubble).
public func parseSSELine(_ line: String) -> SSEEvent? {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    guard trimmed.hasPrefix("data:") else { return nil }
    let payload = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
    guard let data = payload.data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return nil }
    if let delta = object["delta"] as? String { return .delta(delta) }
    if object["done"] as? Bool == true {
        let sourcesData = (try? JSONSerialization.data(withJSONObject: object["sources"] ?? [])) ?? Data("[]".utf8)
        let sources = (try? JSONDecoder().decode([ChatSource].self, from: sourcesData)) ?? []
        return .done(sources: sources)
    }
    if let message = object["error"] as? String { return .serverError(message) }
    if let wire = object["status"] as? String, let status = ChatStreamStatus(wireValue: wire) {
        return .status(status)
    }
    return nil
}

public protocol ChatStreaming: Sendable {
    func stream(message: String, history: [[String: String]], accessToken: String) -> AsyncThrowingStream<SSEEvent, Error>
}

/// Why `chat-with-all-content` refused a question before any answer streamed.
public enum ChatStreamError: Error, Equatable, Sendable {
    /// `403 {"error":"subscription_required", …}` — the function's server-side paywall
    /// (`_shared/entitlementGate.ts`, deployed v126): the account has neither an active trial nor a
    /// subscription. `ChatStore` reports it as `subscriptionRefusals` so the Ask tab shows its
    /// subscription-gate copy (and re-checks the subscription) instead of "Failed to get a response."
    case subscriptionRequired
    /// Any other non-2xx answer (`-1` when the response wasn't HTTP at all).
    case badStatus(Int)
}

/// Maps a non-2xx chat response to its `ChatStreamError`: only a 403 whose body carries
/// `"error": "subscription_required"` is the paywall — any other 403 (e.g. an agent-token refusal)
/// stays `.badStatus(403)`. Pure, for tests.
func chatStreamError(status: Int, body: Data) -> ChatStreamError {
    let error = ((try? JSONSerialization.jsonObject(with: body)) as? [String: Any])?["error"] as? String
    return status == 403 && error == "subscription_required" ? .subscriptionRequired : .badStatus(status)
}

/// A stream that ends cleanly (EOF) without a `done` frame finishes this sequence normally —
/// `ChatStore` is what notices the missing `done` and finalizes the partial answer (plan 15, L1).
public struct LiveChatStreamer: ChatStreaming {
    /// Error bodies are tiny JSON objects; never read more than this from a refusal.
    static let errorBodyLimit = 16 * 1024

    public init() {}
    public func stream(message: String, history: [[String: String]], accessToken: String) -> AsyncThrowingStream<SSEEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = URLRequest(url: StashConfig.supabaseURL.appending(path: "/functions/v1/chat-with-all-content"))
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue(StashConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
                    request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
                    request.httpBody = try JSONSerialization.data(withJSONObject: ["message": message, "conversationHistory": history])
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else { throw ChatStreamError.badStatus(-1) }
                    guard (200..<300).contains(http.statusCode) else {
                        var body = Data()
                        for try await byte in bytes {
                            body.append(byte)
                            if body.count >= Self.errorBodyLimit { break }
                        }
                        throw chatStreamError(status: http.statusCode, body: body)
                    }
                    for try await line in bytes.lines {
                        if let event = parseSSELine(line) { continuation.yield(event) }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
