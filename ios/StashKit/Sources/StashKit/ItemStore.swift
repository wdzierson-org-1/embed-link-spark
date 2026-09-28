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
    /// Rows for exactly these ids (list columns), any order; ids that no longer exist are simply
    /// absent. Used by realtime re-reads and search hits outside the loaded pages.
    func fetchItems(ids: [UUID]) async throws -> [Item]
    /// The subset of `ids` that still exist — the cheap existence check `ItemStore.refresh()` runs
    /// over rows it holds beyond page 1.
    func fetchExistingIds(_ ids: [UUID]) async throws -> Set<UUID>
}

public enum ItemsFetchingError: Error { case unsupported }

public extension ItemsFetching {
    func fetchItems(ids: [UUID]) async throws -> [Item] { throw ItemsFetchingError.unsupported }
    func fetchExistingIds(_ ids: [UUID]) async throws -> Set<UUID> {
        Set(try await fetchItems(ids: ids).map(\.id))
    }
}

public struct SupabaseItemsFetcher: ItemsFetching {
    let pageSize: Int
    public init(pageSize: Int = 50) { self.pageSize = pageSize }

    /// PostgREST `in.(…)` rides the URL — 100 UUIDs keeps each request comfortably small.
    static let idChunkSize = 100

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

    public func fetchItems(ids: [UUID]) async throws -> [Item] {
        var rows: [Item] = []
        for chunk in Self.chunks(of: ids) {
            let data = try await StashClient.shared.from("items")
                .select(Item.listColumns)
                .in("id", values: chunk.map(\.uuidString))
                .execute().data
            rows += try Item.decoder.decode([Item].self, from: data)
        }
        return rows
    }

    public func fetchExistingIds(_ ids: [UUID]) async throws -> Set<UUID> {
        struct Row: Decodable { let id: UUID }
        var existing = Set<UUID>()
        for chunk in Self.chunks(of: ids) {
            let data = try await StashClient.shared.from("items")
                .select("id")
                .in("id", values: chunk.map(\.uuidString))
                .execute().data
            existing.formUnion(try JSONDecoder().decode([Row].self, from: data).map(\.id))
        }
        return existing
    }

    static func chunks(of ids: [UUID]) -> [[UUID]] {
        stride(from: 0, to: ids.count, by: idChunkSize).map { Array(ids[$0..<min($0 + idChunkSize, ids.count)]) }
    }
}

/// The signed-in user's library, newest first (plan 15, "Instant library").
///
/// **Lifetime.** One store per signed-in session, created at app scope (`LibraryStoreProvider`),
/// not inside `LibraryView` — so the View tab is populated before it is first shown, and switching
/// tabs never re-fetches.
///
/// **Cold start.** With an `ItemCache`, `init` synchronously hydrates the last saved first page, so
/// the very first frame shows cards. The cache is rewritten (coalesced, off the main thread) after
/// every change to the first page.
///
/// **Refresh = merge, never truncate.** `refresh()` re-reads page 1 and merges it in: rows inside
/// page 1's time window are replaced by the server's (anything missing there was deleted), rows
/// OLDER than that window — pages the user already scrolled to — are kept, and a cheap existence
/// check then retires any of those (and any search-only rows) that were deleted meanwhile. A
/// realtime change or local edit that lands while a refresh is in flight is never overwritten by
/// that refresh's older snapshot.
///
/// **Incremental.** `applyRemoteChanges(_:)` (realtime), `upsert(_:)` (captures, search rows),
/// `remove(ids:)` and `applyDetail(_:)` (detail-sheet saves) patch rows in place.
///
/// **`items` vs. detached rows.** `items` is always a contiguous newest-first window of the
/// library (the pagination cursor is its last row). A row fetched from outside that window — a
/// server-search hit on a page not loaded yet — is held as a *detached* row: resolvable through
/// `item(withId:)`, kept fresh by realtime and detail saves, but never spliced into `items`.
///
/// **Pending edits (plan 15, H5).** Once `installPendingEdits(_:flusher:)` has run, every row that
/// enters the store (cache, refresh, pages, realtime, detail saves) is shown with the user's
/// not-yet-confirmed detail-sheet edits laid over it, so the list never reverts to the server's
/// older copy while an edit waits in `PendingEdits`. The server's own version stays reachable
/// through `serverRow(withId:)` (what a detail sheet diffs against), and is what the disk cache
/// stores. `refresh()` flushes the queue before it fetches.
@MainActor @Observable
public final class ItemStore {
    /// Sends queued edits; `apply` folds each saved row back into the store.
    public typealias PendingEditsFlusher = @MainActor (_ apply: @escaping @MainActor @Sendable (Item) -> Void) async -> Void

    public private(set) var items: [Item] = []
    public private(set) var isRefreshing = false
    public private(set) var isLoadingMore = false
    public var isLoading: Bool { isRefreshing || isLoadingMore }
    public private(set) var hasMore = true
    public var typeFilter: TypeFilter = .all
    public var selectedTagIds: [UUID] = []
    public var loadError: String?
    /// When the last successful page-1 refresh landed (nil = not yet this session).
    public private(set) var lastRefreshedAt: Date?
    /// Bumped after every successful page-1 refresh (hero prefetch keys off it).
    public private(set) var refreshCount = 0
    /// True when `items` came from the disk cache and no refresh has landed yet.
    public private(set) var isShowingCachedPage = false
    /// Rows outside the contiguous window (see the type doc comment).
    public private(set) var detachedItems: [UUID: Item] = [:]

    /// A refresh older than this (seconds) is stale: foreground / View-tab appear re-fetch then.
    public static let staleInterval: TimeInterval = 30

    public let userId: UUID
    @ObservationIgnored private let fetcher: ItemsFetching
    @ObservationIgnored private let pageSize: Int
    @ObservationIgnored private let cache: ItemCache?
    @ObservationIgnored private let now: @Sendable () -> Date

    /// Bumped at the start of every `refresh()`; a refresh whose token is no longer current when
    /// its fetch returns drops its (stale) result — see final-review Important #3.
    @ObservationIgnored private var refreshGeneration = 0
    /// Bumped whenever `items` is REPLACED (filter change) rather than merged, so a page load that
    /// started against the old window can't append onto the new one.
    @ObservationIgnored private var windowGeneration = 0
    /// The filter the current `items` window was loaded under.
    @ObservationIgnored private var loadedFilterKey: String?
    /// Monotonic stamp for local mutations; `touchedAt[id]` is the stamp of the last incremental
    /// change to that row, so a refresh that started before it keeps the local (newer) version.
    @ObservationIgnored private var mutationClock = 0
    @ObservationIgnored private var touchedAt: [UUID: Int] = [:]
    /// Ids removed this session — a stale snapshot (refresh, page, search) can never resurrect them.
    @ObservationIgnored private var tombstones: Set<UUID> = []
    @ObservationIgnored private var cacheWriteTask: Task<Void, Never>?
    @ObservationIgnored private var cacheDirty = false
    @ObservationIgnored private(set) var isClosed = false

    /// The signed-in user's queue of unconfirmed detail-sheet edits (nil until installed).
    @ObservationIgnored public private(set) var pendingEdits: PendingEdits?
    @ObservationIgnored private var pendingEditsFlusher: PendingEditsFlusher?
    /// The server's version of every row currently shown with pending edits laid over it.
    @ObservationIgnored private var serverVersions: [UUID: Item] = [:]
    /// How long a refresh waits for the flush it started before fetching page 1 anyway — a stalled
    /// PATCH must never hold the library hostage (the overlay covers the gap).
    @ObservationIgnored private let pendingFlushGrace: Duration

    public init(userId: UUID, fetcher: ItemsFetching, pageSize: Int = 50, cache: ItemCache? = nil,
                now: @escaping @Sendable () -> Date = { Date() },
                pendingFlushGrace: Duration = .seconds(2)) {
        self.userId = userId
        self.fetcher = fetcher
        self.pageSize = pageSize
        self.cache = cache
        self.now = now
        self.pendingFlushGrace = pendingFlushGrace
        if let cache {
            let cached = cache.load(userId: userId)
            if !cached.isEmpty {
                items = cached
                hasMore = cached.count >= pageSize
                isShowingCachedPage = true
                loadedFilterKey = filterKey
            }
        }
    }

    // MARK: - Reading

    /// A row by id — from the loaded window or the detached (search-hit) rows.
    public func item(withId id: UUID) -> Item? {
        if let row = detachedItems[id] { return row }
        return items.first { $0.id == id }
    }

    /// The row as the SERVER last reported it — without pending edits laid over it. A detail sheet
    /// diffs against this, so a queued value still counts as unsaved there. `nil` when the store
    /// doesn't hold the row.
    public func serverRow(withId id: UUID) -> Item? {
        guard let shown = item(withId: id) else { return nil }
        return serverVersions[id] ?? shown
    }

    /// True when no refresh has landed yet, or the last one is older than `staleInterval`.
    public var needsRefresh: Bool {
        guard let lastRefreshedAt else { return true }
        return now().timeIntervalSince(lastRefreshedAt) >= Self.staleInterval
    }

    // MARK: - Loading

    /// Foreground / View-tab-appear entry point: refreshes only when stale and not already
    /// refreshing (pull-to-refresh calls `refresh()` directly).
    public func refreshIfStale() async {
        guard needsRefresh, !isRefreshing else { return }
        await refresh()
    }

    /// Re-reads page 1 and merges it in. The work runs in its own (unstructured) task: the store is
    /// app-scoped, so a caller going away mid-refresh — `LibraryView`'s `.task` is cancelled on a
    /// tab switch — must neither abort the refresh nor turn that cancellation into a
    /// "Couldn't load your stash" error. The caller still awaits the result.
    public func refresh() async {
        await Task { await self.performRefresh() }.value
    }

    private func performRefresh() async {
        refreshGeneration += 1
        let generation = refreshGeneration
        isRefreshing = true
        loadError = nil
        // Plan 15 (H5): queued detail-sheet edits go out first, so the page read next already has
        // them — bounded, so a stalled PATCH can't delay the page (the overlay shows them anyway).
        await flushPendingEditsBeforeFetch()
        guard generation == refreshGeneration, !isClosed else { return }
        let startedAt = mutationClock
        let key = filterKey
        let fetched: [Item]
        do {
            fetched = try await fetcher.fetchPage(userId: userId, before: nil,
                                                  types: typeFilter.predicateTypes, tagIds: selectedTagIds)
        } catch {
            if generation == refreshGeneration {
                isRefreshing = false
                loadError = "Couldn't load your stash. Pull to retry."
            }
            return
        }
        guard generation == refreshGeneration, !isClosed else { return }
        isRefreshing = false
        let page = fetched.map(overlaid)

        if key != loadedFilterKey {
            // A different filter: the old window is meaningless — replace, don't merge.
            windowGeneration += 1
            items = page.filter { !tombstones.contains($0.id) }
            hasMore = page.count == pageSize
            loadedFilterKey = key
        } else {
            let merged = Self.mergeFirstPage(current: items, page: page, pageSize: pageSize,
                                             keepLocal: rowsTouched(after: startedAt), tombstones: tombstones)
            items = merged.items
            if page.count < pageSize {
                hasMore = false
            } else if !merged.keptOlderRows {
                hasMore = true
            }
        }
        isShowingCachedPage = false
        lastRefreshedAt = now()
        refreshCount += 1
        scheduleCacheWrite()
        await retireDeletedRowsBeyondFirstPage(page: page, generation: generation)
    }

    public func loadMoreIfNeeded(current: Item) async {
        guard hasMore, !isLoadingMore, current.id == items.last?.id else { return }
        await loadMore()
    }

    private func loadMore() async {
        let window = windowGeneration
        let cursor = items.last?.createdAt
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page = try await fetcher.fetchPage(userId: userId, before: cursor,
                                                   types: typeFilter.predicateTypes, tagIds: selectedTagIds)
            guard window == windowGeneration, !isClosed else { return }
            let known = Set(items.map(\.id))
            let fresh = page.filter { !known.contains($0.id) && !tombstones.contains($0.id) }.map(overlaid)
            for row in fresh { detachedItems[row.id] = nil }   // a search hit now joins the window
            items += fresh
            hasMore = page.count == pageSize
        } catch {
            guard window == windowGeneration else { return }
            loadError = "Couldn't load your stash. Pull to retry."
        }
    }

    // MARK: - Incremental updates

    /// Merge a full detail fetch (with page_body) or a detail-sheet save back into the list. `item`
    /// must be the server's row (a fetch or PATCH response); pending edits are laid over it here.
    public func applyDetail(_ item: Item) {
        guard !tombstones.contains(item.id) else { return }
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = overlaid(item)
            touch(item.id)
            if index < pageSize { scheduleCacheWrite() }
        } else if detachedItems[item.id] != nil {
            detachedItems[item.id] = overlaid(item)
            touch(item.id)
        }
    }

    /// Prepend a freshly-captured item so it appears immediately without waiting on a full
    /// refresh. No-op if already present.
    public func applyNew(_ item: Item) {
        guard self.item(withId: item.id) == nil else { return }
        upsert([item])
    }

    /// A `.stashItemCaptured` delivery. Only this store's user's captures count — the poster tags
    /// each one with `userInfo["userId"]`, and one without it (an older poster) is treated as
    /// someone else's, so a late capture or drain for one account can never land in another's grid
    /// or cache after an account switch. Insert-if-absent (`applyNew`): a capture-time snapshot
    /// must never overwrite (or `touch`) a newer realtime/refresh row already shown.
    public func applyCaptured(_ item: Item, ownerId: UUID?) {
        guard ownerId == userId else { return }
        applyNew(item)
    }

    /// Insert or replace rows (realtime re-reads, captures, search hits). A row inside the loaded
    /// window (or newer than it) is placed by `created_at`; an older row is only kept as a
    /// detached row if it already was one. A list-column row never erases an already-loaded
    /// `page_body` (list reads don't select it — nil means "not fetched", not "cleared").
    /// Incoming rows are the server's; pending edits are laid over them here.
    public func upsert(_ incoming: [Item]) {
        var touchedHead = false
        for var row in incoming where !tombstones.contains(row.id) {
            touch(row.id)
            if let index = items.firstIndex(where: { $0.id == row.id }) {
                if row.pageBody == nil { row.pageBody = items[index].pageBody }
                row = overlaid(row)
                if !matchesFilter(row) {
                    items.remove(at: index)
                } else if row.createdAt == items[index].createdAt {
                    items[index] = row
                } else {
                    items.remove(at: index)
                    insertSorted(row)
                }
                touchedHead = touchedHead || index < pageSize
            } else if let existing = detachedItems[row.id] {
                if row.pageBody == nil { row.pageBody = existing.pageBody }
                row = overlaid(row)
                if belongsInWindow(row), matchesFilter(row) {
                    detachedItems[row.id] = nil
                    insertSorted(row)
                    touchedHead = true
                } else {
                    detachedItems[row.id] = row
                }
            } else if belongsInWindow(row), matchesFilter(row), selectedTagIds.isEmpty {
                insertSorted(overlaid(row))
                touchedHead = true
            }
        }
        if touchedHead { scheduleCacheWrite() }
    }

    /// Remove rows for good this session (deleted server-side).
    public func remove(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        tombstones.formUnion(ids)
        let before = items.count
        items.removeAll { ids.contains($0.id) }
        for id in ids {
            detachedItems[id] = nil
            serverVersions[id] = nil
        }
        if items.count != before { scheduleCacheWrite() }
    }

    /// Applies one coalesced realtime batch: deletes drop out immediately; inserts/updates re-read
    /// just those rows with the list columns. An id that no longer exists by the time it's re-read
    /// was deleted in between. A failed re-read marks the store stale so the next foreground /
    /// View-tab appear refreshes (no error banner for a change the user didn't ask for).
    public func applyRemoteChanges(_ batch: ItemChangeBatch) async {
        remove(ids: batch.deleted)
        let ids = batch.upserted.subtracting(batch.deleted)
        guard !ids.isEmpty, !isClosed else { return }
        do {
            let rows = try await fetcher.fetchItems(ids: Array(ids))
            guard !isClosed else { return }
            upsert(rows)
            remove(ids: ids.subtracting(rows.map(\.id)))
        } catch {
            lastRefreshedAt = nil
        }
    }

    /// Makes sure every id has a row to render (server-search hits on pages not loaded yet):
    /// unknown ids are read by id and kept as detached rows (or joined to the window when they
    /// fall inside it). Failures are swallowed — the hits that do resolve still render.
    public func ensureRows(ids: [UUID]) async {
        let missing = ids.filter { item(withId: $0) == nil && !tombstones.contains($0) }
        guard !missing.isEmpty, let rows = try? await fetcher.fetchItems(ids: missing), !isClosed else { return }
        var joined: [Item] = []
        for row in rows where !tombstones.contains(row.id) && item(withId: row.id) == nil {
            if belongsInWindow(row), matchesFilter(row) {
                joined.append(row)
            } else {
                detachedItems[row.id] = overlaid(row)
            }
        }
        if !joined.isEmpty { upsert(joined) }
    }

    // MARK: - Live updates (app scope)

    /// Keeps the store live for the signed-in session: realtime row changes are applied
    /// incrementally, and every capture this app saves (`.stashItemCaptured`, posted by the capture
    /// pipeline with the saved `Item` — a composer save, a voice note, an Outbox drain, a background
    /// share completing in-app) is shown at once, before its realtime echo arrives. Runs until
    /// the calling task is cancelled (sign-out tears down the owner).
    public func runLiveUpdates(changes: ItemChangeObserving, notifications: NotificationCenter = .default) async {
        let userId = userId
        await withTaskGroup(of: Void.self) { group in
            group.addTask { [weak self] in
                await changes.observeItemChanges(userId: userId) { [weak self] batch in
                    await self?.applyRemoteChanges(batch)
                }
            }
            group.addTask { [weak self] in
                for await note in notifications.notifications(named: .stashItemCaptured) {
                    guard let item = note.userInfo?["item"] as? Item else { continue }
                    await self?.applyCaptured(item, ownerId: note.userInfo?["userId"] as? UUID)
                }
            }
            // Either feed ending (the task was cancelled, or the realtime observer gave up) ends both.
            await group.next()
            group.cancelAll()
        }
    }

    /// Stops all further cache writes and waits for an in-flight one, so a sign-out purge that
    /// runs after this can't be undone by a late write.
    public func close() async {
        isClosed = true
        cacheWriteTask?.cancel()
        await cacheWriteTask?.value
        cacheWriteTask = nil
    }

    /// Waits for any scheduled cache write to finish (tests, and callers that need the snapshot
    /// on disk now).
    public func flushCacheWrites() async {
        while let task = cacheWriteTask { await task.value }
    }

    // MARK: - Pending detail-sheet edits (plan 15, H5)

    /// Connects the user's `PendingEdits`: every shown row gets its queued values laid over it
    /// (now, and whenever the queue changes), and `refresh()` runs `flusher` before each fetch.
    /// Idempotent for the same queue (the app calls it from `MainTabView.init`, which re-runs).
    public func installPendingEdits(_ pendingEdits: PendingEdits, flusher: @escaping PendingEditsFlusher) {
        guard self.pendingEdits !== pendingEdits else { return }
        self.pendingEdits = pendingEdits
        pendingEditsFlusher = flusher
        pendingEdits.onChange = { [weak self] ids in self?.reapplyPendingEdits(ids) }
        reapplyPendingEdits(nil)
    }

    /// Sends every queued edit now and folds the saved rows in.
    public func flushPendingEdits() async {
        guard let flusher = pendingEditsFlusher, let pendingEdits, !pendingEdits.isEmpty else { return }
        await flusher { [weak self] saved in self?.applyDetail(saved) }
    }

    private func flushPendingEditsBeforeFetch() async {
        guard pendingEditsFlusher != nil, let pendingEdits, !pendingEdits.isEmpty else { return }
        let flush = Task { await self.flushPendingEdits() }
        await Self.wait(for: flush, atMost: pendingFlushGrace)
    }

    /// Resumes when `task` finishes or `limit` passes, whichever is first; `task` keeps running.
    private static func wait(for task: Task<Void, Never>, atMost limit: Duration) async {
        let gate = OneShotGate()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            gate.continuation = continuation
            let timer = Task { @MainActor in
                try? await Task.sleep(for: limit)
                gate.open()
            }
            Task { @MainActor in
                await task.value
                timer.cancel()
                gate.open()
            }
        }
    }

    /// `row` (the server's version) with any queued edits laid over it; remembers the server's
    /// version for `serverRow(withId:)` while an overlay is shown.
    private func overlaid(_ row: Item) -> Item {
        guard let edit = pendingEdits?.edit(for: row.id) else {
            serverVersions[row.id] = nil
            return row
        }
        serverVersions[row.id] = row
        return edit.applied(to: row)
    }

    /// Re-lays the queue over the shown rows (`nil` = every row). A row whose entry is gone keeps
    /// what it shows: the queue only forgets a value once the server has confirmed it (or the item
    /// is gone), so the shown value IS the server's.
    private func reapplyPendingEdits(_ ids: Set<UUID>?) {
        guard let pendingEdits else { return }
        func relaid(_ shown: Item) -> Item {
            guard let edit = pendingEdits.edit(for: shown.id) else {
                serverVersions[shown.id] = nil
                return shown
            }
            let server = serverVersions[shown.id] ?? shown
            serverVersions[shown.id] = server
            return edit.applied(to: server)
        }
        var changedHead = false
        for index in items.indices where ids?.contains(items[index].id) ?? true {
            let next = relaid(items[index])
            if next != items[index] {
                items[index] = next
                changedHead = changedHead || index < pageSize
            }
        }
        for id in ids ?? Set(detachedItems.keys) {
            guard let shown = detachedItems[id] else { continue }
            let next = relaid(shown)
            if next != shown { detachedItems[id] = next }
        }
        if changedHead { scheduleCacheWrite() }
    }

    // MARK: - Merge (pure)

    struct MergeResult: Equatable {
        let items: [Item]
        /// Whether rows older than page 1's window were carried over (older pages stay loaded).
        let keptOlderRows: Bool
    }

    /// Merges a fresh first page into the current window (see the type doc comment). `keepLocal`
    /// are ids changed locally after the refresh was requested — their current row wins over the
    /// page's snapshot (and a row inserted locally but absent from the snapshot is kept).
    static func mergeFirstPage(current: [Item], page: [Item], pageSize: Int, keepLocal: Set<UUID>,
                               tombstones: Set<UUID>) -> MergeResult {
        let currentById = Dictionary(current.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var result: [Item] = []
        var seen = Set<UUID>()
        for var row in page where !tombstones.contains(row.id) && seen.insert(row.id).inserted {
            if let local = currentById[row.id] {
                if keepLocal.contains(row.id) {
                    row = local
                } else if row.pageBody == nil {
                    row.pageBody = local.pageBody
                }
            }
            result.append(row)
        }
        let pageIsComplete = page.count < pageSize
        let boundary = page.last?.createdAt
        var keptOlderRows = false
        for row in current where !seen.contains(row.id) && !tombstones.contains(row.id) {
            if keepLocal.contains(row.id) {
                result.append(row)                      // changed locally after the snapshot
            } else if !pageIsComplete, let boundary, row.createdAt <= boundary {
                result.append(row)                      // an older page (or a boundary tie)
                keptOlderRows = true
            }
            // else: inside page 1's window but absent from it → deleted server-side.
            seen.insert(row.id)
        }
        let order = Dictionary(result.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
        result.sort { lhs, rhs in
            lhs.createdAt != rhs.createdAt ? lhs.createdAt > rhs.createdAt : order[lhs.id]! < order[rhs.id]!
        }
        return MergeResult(items: result, keptOlderRows: keptOlderRows)
    }

    // MARK: - Private

    private var filterKey: String {
        let types = typeFilter.predicateTypes?.map(\.rawValue).sorted().joined(separator: ",") ?? "*"
        let tags = selectedTagIds.map(\.uuidString).sorted().joined(separator: ",")
        return "\(types)|\(tags)"
    }

    private func matchesFilter(_ row: Item) -> Bool {
        guard let types = typeFilter.predicateTypes else { return true }
        return types.contains(row.type)
    }

    /// A row belongs to the contiguous window when it's at least as new as the window's oldest
    /// row — or when the window already holds the whole library.
    private func belongsInWindow(_ row: Item) -> Bool {
        guard hasMore, let oldest = items.last else { return true }
        return row.createdAt >= oldest.createdAt
    }

    private func insertSorted(_ row: Item) {
        let index = items.firstIndex { $0.createdAt < row.createdAt } ?? items.endIndex
        items.insert(row, at: index)
    }

    private func touch(_ id: UUID) {
        mutationClock += 1
        touchedAt[id] = mutationClock
    }

    private func rowsTouched(after stamp: Int) -> Set<UUID> {
        Set(touchedAt.lazy.filter { $0.value > stamp }.map(\.key))
    }

    /// Rows the merge kept from beyond page 1, plus detached search rows, are checked for
    /// existence in one small ids-only read; any that are gone were deleted (here or on another
    /// device — realtime can't report deletes on this table, see `RealtimeObserver`).
    private func retireDeletedRowsBeyondFirstPage(page: [Item], generation: Int) async {
        let pageIds = Set(page.map(\.id))
        var candidates = items.filter { !pageIds.contains($0.id) }.map(\.id)
        candidates += detachedItems.keys
        guard !candidates.isEmpty,
              let existing = try? await fetcher.fetchExistingIds(candidates),
              generation == refreshGeneration, !isClosed
        else { return }
        let checkedAt = Set(candidates)
        // A row re-inserted locally since the check started is live by definition.
        let missing = checkedAt.subtracting(existing).filter { item(withId: $0) != nil }
        remove(ids: missing)
    }

    private func scheduleCacheWrite() {
        guard let cache, !isClosed else { return }
        cacheDirty = true
        guard cacheWriteTask == nil else { return }
        let userId = userId
        cacheWriteTask = Task { [weak self] in
            // Coalesce bursts (a refresh + a few realtime rows) into one write.
            try? await Task.sleep(for: .milliseconds(250))
            while let self, self.cacheDirty, !self.isClosed {
                self.cacheDirty = false
                let snapshot = self.cacheSnapshot()
                _ = await Task.detached(priority: .utility) {
                    cache.save(snapshot, userId: userId)
                }.value
            }
            self?.cacheWriteTask = nil
        }
    }

    /// What the disk cache holds: the first page as the SERVER has it (pending edits live in their
    /// own durable queue and are laid over again at launch), without `page_body` — opened
    /// articles/transcripts can be tens of KB each and the cache is decoded synchronously on every
    /// launch; a detail sheet re-reads it on open.
    func cacheSnapshot() -> [Item] {
        items.prefix(pageSize).map { shown in
            var row = serverVersions[shown.id] ?? shown
            row.pageBody = nil
            return row
        }
    }
}

/// Resumes a continuation exactly once — whichever of `ItemStore.wait(for:atMost:)`'s two racers
/// gets there first.
@MainActor
private final class OneShotGate {
    var continuation: CheckedContinuation<Void, Never>?

    func open() {
        continuation?.resume()
        continuation = nil
    }
}
