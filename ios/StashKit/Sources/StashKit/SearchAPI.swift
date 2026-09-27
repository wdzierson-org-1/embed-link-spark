import Foundation
import Observation
import Supabase

/// Server-side library search (plan 15, Task 3): the `search-items` edge function — the same
/// hybrid semantic + keyword retrieval the web toolbar (`src/hooks/useServerSearch.ts`), Ask and
/// MCP use, which reaches `page_body`/`summary` and items on pages the phone hasn't loaded.
public protocol ItemSearching: Sendable {
    /// Relevance-ordered item ids for `query` (at most `limit`).
    func searchIds(query: String, limit: Int) async throws -> [UUID]
}

public struct SupabaseItemSearcher: ItemSearching {
    public init() {}

    public func searchIds(query: String, limit: Int) async throws -> [UUID] {
        let response: SearchItemsResponse = try await StashClient.shared.functions.invoke(
            "search-items",
            options: FunctionInvokeOptions(body: SearchItemsRequest(query: query, limit: limit))
        )
        return response.orderedIds
    }
}

struct SearchItemsRequest: Encodable, Sendable {
    let query: String
    let limit: Int
}

/// `POST /search-items` → `{ results: [{ id, title, type, url, created_at, description, snippet,
/// score }] }` (docs/PLATFORM_API.md). Only `id` is read — rows are re-read by id with
/// `Item.listColumns` so a search hit renders exactly like any other card.
struct SearchItemsResponse: Decodable, Sendable {
    struct Hit: Decodable, Sendable {
        let id: String
    }

    let results: [Hit]

    /// Server (relevance) order, first occurrence wins, malformed ids skipped.
    var orderedIds: [UUID] {
        var seen = Set<UUID>()
        return results.compactMap { UUID(uuidString: $0.id) }.filter { seen.insert($0).inserted }
    }
}

/// What the View tab shows for a query once server results are in (plan 15, Task 3).
///
/// Every server hit whose own card text literally contains the query (`matchesCardText`: title,
/// description, url, sticky note and the note as PLAIN text) comes first, in server relevance
/// order; then any loaded item that literally matches but the server didn't return (a
/// just-captured row not yet indexed, a partial word the keyword index doesn't stem to); then the
/// server's remaining — semantic-only — hits, in relevance order.
///
/// Why literal-first rather than the web's pure relevance order (an intentional iOS divergence):
/// `search-items` always returns its ~30 nearest neighbours, even for gibberish, and a sibling
/// fixture can outrank the exact match ("link one" ranks "link two" first). Pinning literal matches
/// to the top means the cards the instant local filter already showed never jump below semantic
/// neighbours when the server answers — results only grow — while everything the server adds
/// (page_body hits, older pages) still appears. `rowFor` resolves an id to a row (nil = unknown or
/// deleted → skipped).
public func rankedSearchResults(query: String, rankedIds: [UUID], rowFor: (UUID) -> Item?,
                                localPool: [Item]) -> [Item] {
    let needle = CardTextMatch.needle(query)
    var seen = Set<UUID>()
    var literal: [Item] = []
    var semantic: [Item] = []
    for id in rankedIds {
        guard seen.insert(id).inserted, let row = rowFor(id) else { continue }
        if CardTextMatch.contains(row, needle: needle) { literal.append(row) } else { semantic.append(row) }
    }
    let localOnly = localPool.filter { !seen.contains($0.id) && CardTextMatch.contains($0, needle: needle) }
    return literal + localOnly + semantic
}

public extension Item {
    /// Case-insensitive substring match over the text this item's card actually shows: title,
    /// description, url, sticky note, and `content` rendered to plain text. Unlike
    /// `matches(searchQuery:)` (the web `itemSearch.ts` port, which reads `content` raw), a rich
    /// note's TipTap JSON markup — "type", "doc", "paragraph", "text", "content" — never matches.
    func matchesCardText(searchQuery: String) -> Bool {
        CardTextMatch.contains(self, needle: CardTextMatch.needle(searchQuery))
    }
}

enum CardTextMatch {
    /// Plain text of rich (TipTap JSON) notes, keyed by the raw content: ranking runs on every
    /// re-render of a searched grid (scrolling included), and parsing each note's JSON once is
    /// enough.
    private static let plainContent: NSCache<NSString, NSString> = {
        let cache = NSCache<NSString, NSString>()
        cache.countLimit = 1_000
        return cache
    }()

    static func needle(_ query: String) -> String {
        query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// `needle` must already be `needle(_:)`-normalized; an empty needle matches everything
    /// (same as `Item.matches(searchQuery:)`).
    static func contains(_ item: Item, needle: String) -> Bool {
        guard !needle.isEmpty else { return true }
        return [item.title, item.description, item.url, item.supplementalNote, plainText(item.content)]
            .contains { $0?.lowercased().contains(needle) ?? false }
    }

    /// Plain-text notes (valid platform-wide) pass through; only a JSON document is rendered.
    static func plainText(_ content: String?) -> String? {
        guard let content, content.hasPrefix("{") else { return content }
        if let cached = plainContent.object(forKey: content as NSString) { return cached as String }
        let plain = String(renderTipTap(content).characters)
        plainContent.setObject(plain as NSString, forKey: content as NSString)
        return plain
    }
}

/// Debounced server search for the View tab — a port of `useServerSearch.ts` (300 ms debounce,
/// ≥ 2 characters, limit 50, per-query result cache) that also makes sure every hit has a row to
/// render (`ItemStore.ensureRows`). While a request is pending, or if it fails, `serverIds(for:)`
/// is nil and the caller keeps showing the instant local filter.
@MainActor @Observable
public final class LibrarySearch {
    public enum Phase: Equatable, Sendable {
        /// Query shorter than `minimumQueryLength` — local filter only, no request.
        case inactive
        /// Debouncing or waiting on the server.
        case pending
        case results([UUID])
        case failed
    }

    public static let minimumQueryLength = 2
    public static let resultLimit = 50

    public private(set) var phase: Phase = .inactive
    /// The trimmed query `phase` belongs to.
    public private(set) var query = ""

    @ObservationIgnored private let searcher: ItemSearching
    @ObservationIgnored private let store: ItemStore
    @ObservationIgnored private let debounce: Duration
    @ObservationIgnored private var cachedIds: [String: [UUID]] = [:]
    @ObservationIgnored private var inFlight: Task<Void, Never>?

    public init(store: ItemStore, searcher: ItemSearching = SupabaseItemSearcher(),
                debounce: Duration = .milliseconds(300)) {
        self.store = store
        self.searcher = searcher
        self.debounce = debounce
    }

    /// Server ids for `rawQuery` if (and only if) they're the settled answer to exactly that query.
    public func serverIds(for rawQuery: String) -> [UUID]? {
        guard case .results(let ids) = phase, query == Self.normalize(rawQuery) else { return nil }
        return ids
    }

    /// Call on every query change (typing, clearing).
    public func update(query rawQuery: String) {
        let trimmed = Self.normalize(rawQuery)
        guard trimmed != query || phase == .failed else { return }
        inFlight?.cancel()
        inFlight = nil
        query = trimmed
        guard trimmed.count >= Self.minimumQueryLength else {
            phase = .inactive
            return
        }
        if let cached = cachedIds[trimmed] {
            phase = .results(cached)
            return
        }
        phase = .pending
        inFlight = Task { [weak self, debounce] in
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled else { return }
            await self?.run(trimmed)
        }
    }

    /// Forget cached answers (e.g. after the library refreshed) — the current results stay on
    /// screen; the next keystroke asks the server again.
    public func invalidateCache() {
        cachedIds.removeAll()
    }

    private func run(_ trimmed: String) async {
        do {
            let ids = try await searcher.searchIds(query: trimmed, limit: Self.resultLimit)
            guard !Task.isCancelled, trimmed == query else { return }
            await store.ensureRows(ids: ids)
            guard !Task.isCancelled, trimmed == query else { return }
            cachedIds[trimmed] = ids
            phase = .results(ids)
        } catch {
            guard !Task.isCancelled, trimmed == query else { return }
            phase = .failed
        }
    }

    static func normalize(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
