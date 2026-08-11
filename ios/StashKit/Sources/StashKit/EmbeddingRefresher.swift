import Foundation
import Supabase

/// Port of the web's decoupled search-index refresh (itemOperations.ts:10-75):
/// saves resolve on the PATCH; embeddings regenerate on a per-item idle
/// debounce from the full merged row, latest-write-wins.
public func buildEmbeddingText(from item: Item) -> String {
    var parts: [String] = []
    if let t = item.title, !t.isEmpty { parts.append(t) }
    if let d = item.description, !d.isEmpty { parts.append(d) }
    if let c = item.content {
        let plain = String(renderTipTap(c).characters)
        if !plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { parts.append(plain) }
    }
    if let s = item.supplementalNote, !s.isEmpty { parts.append(s) }
    if let u = item.url, !u.isEmpty { parts.append(u) }
    if let s = item.summary, !s.isEmpty { parts.append(s) }
    if let p = item.pageBody, !p.isEmpty { parts.append(p) }
    return parts.joined(separator: " ").trimmingCharacters(in: .whitespaces)
}

public protocol EmbeddingSyncing: Sendable {
    func replaceEmbeddings(itemId: UUID, text: String) async throws
}

public struct SupabaseEmbeddingSyncer: EmbeddingSyncing {
    public init() {}
    public func replaceEmbeddings(itemId: UUID, text: String) async throws {
        try await StashClient.shared.from("embeddings").delete()
            .eq("item_id", value: itemId.uuidString).execute()
        try await StashClient.shared.functions.invoke("generate-embeddings",
            options: FunctionInvokeOptions(body: ["itemId": itemId.uuidString, "textContent": text]))
    }
}

public actor EmbeddingRefresher {
    private let syncer: EmbeddingSyncing
    private let idle: Duration
    private var pending: [UUID: Task<Void, Never>] = [:]

    public init(syncer: EmbeddingSyncing, idle: Duration = .seconds(4)) {
        self.syncer = syncer
        self.idle = idle
    }

    public func schedule(_ item: Item) {
        pending[item.id]?.cancel()
        pending[item.id] = Task { [idle, syncer] in
            try? await Task.sleep(for: idle)
            guard !Task.isCancelled else { return }
            let text = buildEmbeddingText(from: item)
            guard !text.isEmpty else { return }
            do { try await syncer.replaceEmbeddings(itemId: item.id, text: text) }
            catch { print("Embedding refresh failed (non-fatal): \(error)") }
        }
    }
}
