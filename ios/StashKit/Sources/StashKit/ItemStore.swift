import Foundation
import Observation
import Supabase

public enum TypeFilter: String, CaseIterable, Sendable {
    case all, links, notes, docs, media, collections

    public var predicateTypes: [ItemType]? {
        switch self {
        case .all: return nil
        case .links: return [.link]
        case .notes: return [.text]
        case .docs: return [.document]
        case .media: return [.image, .audio, .video]
        case .collections: return [.collection]
        }
    }

    public var label: String {
        switch self {
        case .all: "All"; case .links: "Links"; case .notes: "Notes"
        case .docs: "Docs"; case .media: "Media"; case .collections: "Collections"
        }
    }
}

public protocol ItemsFetching: Sendable {
    func fetchPage(userId: UUID, before: Date?, types: [ItemType]?, tagIds: [UUID]) async throws -> [Item]
    func fetchDetail(id: UUID) async throws -> Item
}

public struct SupabaseItemsFetcher: ItemsFetching {
    let pageSize: Int
    public init(pageSize: Int = 50) { self.pageSize = pageSize }

    public func fetchPage(userId: UUID, before: Date?, types: [ItemType]?, tagIds: [UUID]) async throws -> [Item] {
        // RLS scopes rows to the JWT owner; user_id filter kept for parity with web
        var query = StashClient.shared
            .from("items")
            .select(tagIds.isEmpty ? Item.listColumns : Item.listColumns + ",item_tags!inner(tag_id)")
            .eq("user_id", value: userId.uuidString)
        if let types { query = query.in("type", values: types.map(\.rawValue)) }
        if !tagIds.isEmpty { query = query.in("item_tags.tag_id", values: tagIds.map(\.uuidString)) }
        if let before {
            query = query.lt("created_at", value: before)
        }
        let data = try await query
            .order("created_at", ascending: false)
            .limit(pageSize)
            .execute().data
        return try Item.decoder.decode([Item].self, from: data)
    }

    public func fetchDetail(id: UUID) async throws -> Item {
        let data = try await StashClient.shared.from("items")
            .select(Item.detailColumns).eq("id", value: id.uuidString)
            .single().execute().data
        return try Item.decoder.decode(Item.self, from: data)
    }
}

@MainActor @Observable
public final class ItemStore {
    public private(set) var items: [Item] = []
    public private(set) var isLoading = false
    public private(set) var hasMore = true
    public var typeFilter: TypeFilter = .all
    public var selectedTagIds: [UUID] = []
    public var loadError: String?

    private let userId: UUID
    private let fetcher: ItemsFetching
    private let pageSize: Int

    /// Bumped at the start of every `load(reset:)`. Lets a load that's still in flight
    /// recognize a newer load has since started, so it can discard its own (stale) result
    /// instead of clobbering the newer one's — see final-review Important #3.
    private var loadGeneration = 0

    public init(userId: UUID, fetcher: ItemsFetching, pageSize: Int = 50) {
        self.userId = userId
        self.fetcher = fetcher
        self.pageSize = pageSize
    }

    public func refresh() async {
        await load(reset: true)
    }

    public func loadMoreIfNeeded(current: Item) async {
        guard hasMore, !isLoading, current.id == items.last?.id else { return }
        await load(reset: false)
    }

    /// Merge a full detail fetch (with page_body) back into the list.
    public func applyDetail(_ item: Item) {
        if let idx = items.firstIndex(where: { $0.id == item.id }) { items[idx] = item }
    }

    /// Prepend a freshly-captured item (composer calls this on capture success) so it appears
    /// immediately without waiting on a full refresh. No-op if already present.
    public func applyNew(_ item: Item) {
        guard !items.contains(where: { $0.id == item.id }) else { return }
        items.insert(item, at: 0)
    }

    private func load(reset: Bool) async {
        loadGeneration += 1
        let generation = loadGeneration
        isLoading = true
        defer { if generation == loadGeneration { isLoading = false } }
        loadError = nil
        let cursor = reset ? nil : items.last?.createdAt
        do {
            let page = try await fetcher.fetchPage(userId: userId, before: cursor,
                                                   types: typeFilter.predicateTypes,
                                                   tagIds: selectedTagIds)
            guard generation == loadGeneration else { return }   // a newer load has since started; drop this stale result
            if reset { items = page } else {
                let known = Set(items.map(\.id))
                items += page.filter { !known.contains($0.id) }
            }
            hasMore = page.count == pageSize
        } catch {
            guard generation == loadGeneration else { return }
            loadError = "Couldn't load your stash. Pull to retry."
        }
    }
}
