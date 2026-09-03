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

public enum SSEEvent: Equatable, Sendable {
    case delta(String)
    case done(sources: [ChatSource])
    case serverError(String)
}

/// One SSE line → event. Mirrors ChatMole.tsx:272-285 exactly: only `data:`
/// lines matter; the payload is JSON; delta / done+sources / error.
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
    return nil
}

public protocol ChatStreaming: Sendable {
    func stream(message: String, history: [[String: String]], accessToken: String) -> AsyncThrowingStream<SSEEvent, Error>
}

public struct LiveChatStreamer: ChatStreaming {
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
                    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                        throw CaptureError.badStatus((response as? HTTPURLResponse)?.statusCode ?? -1)
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
