import Foundation
import Supabase

/// Port of the web's decoupled search-index refresh (itemOperations.ts:10-75): saves resolve on the
/// PATCH; the item's embeddings are rebuilt on a per-item idle debounce after a text edit.
///
/// The SERVER decides what gets embedded. Deployed `generate-embeddings` v120 (verified against its
/// source, final wave B) reads the item's current saved row itself (`requireItemAccess`: the
/// caller's JWT must own the item — the v119 IDOR is closed), builds the text
/// (`enrichmentSearchText`), generates first and then replaces the item's rows by compare-and-swap
/// (`replace_item_embeddings`), so a failed provider call never erases the old index. It ignores
/// any `textContent` a caller sends — the old client-built text (`buildEmbeddingText`) is gone, and
/// the request is just `{ itemId }`.
public protocol EmbeddingSyncing: Sendable {
    /// Asks the server to rebuild `itemId`'s embeddings from its current saved row.
    func refreshEmbeddings(itemId: UUID) async throws
}

/// Why a rebuild request didn't go through.
public enum EmbeddingRefreshError: Error, Equatable, Sendable {
    /// `409 {"success":false,"reason":"item_changed"}`: the row changed while its index was being
    /// generated, so the compare-and-swap kept the old rows. Benign — whatever changed it (a newer
    /// save, which schedules its own refresh; an enrichment write, which re-indexes server-side)
    /// brings the index up to date.
    case itemChanged
}

/// Asks `generate-embeddings` to rebuild the item's index. The client never deletes `embeddings`
/// rows itself (plan 15, M10): the function replaces them atomically on its own.
public struct SupabaseEmbeddingSyncer: EmbeddingSyncing {
    public init() {}
    public func refreshEmbeddings(itemId: UUID) async throws {
        do {
            try await StashClient.shared.functions.invoke(
                "generate-embeddings",
                options: FunctionInvokeOptions(body: ["itemId": itemId.uuidString.lowercased()]))
        } catch FunctionsError.httpError(let code, _) where code == 409 {
            throw EmbeddingRefreshError.itemChanged
        }
    }
}

public actor EmbeddingRefresher {
    private let syncer: EmbeddingSyncing
    private let idle: Duration
    private let reportFailure: @Sendable (UUID, Error) -> Void
    private var pending: [UUID: Task<Void, Never>] = [:]

    /// `reportFailure` is told about real failures only — never about a benign `itemChanged`
    /// (tests observe it; the default just logs).
    public init(syncer: EmbeddingSyncing, idle: Duration = .seconds(4),
                reportFailure: @escaping @Sendable (UUID, Error) -> Void = { itemId, error in
                    print("Embedding refresh failed for \(itemId) (non-fatal): \(error)")
                }) {
        self.syncer = syncer
        self.idle = idle
        self.reportFailure = reportFailure
    }

    /// Rebuilds `item`'s index once edits to it have been idle for `idle` — a burst of saves to one
    /// item asks once. Only the id is used: the server reads the saved row itself.
    public func schedule(_ item: Item) {
        let itemId = item.id
        pending[itemId]?.cancel()
        pending[itemId] = Task { [idle, syncer, reportFailure] in
            try? await Task.sleep(for: idle)
            guard !Task.isCancelled else { return }
            do {
                try await syncer.refreshEmbeddings(itemId: itemId)
            } catch EmbeddingRefreshError.itemChanged {
                // Benign — see `EmbeddingRefreshError.itemChanged`.
            } catch {
                reportFailure(itemId, error)
            }
        }
    }
}
