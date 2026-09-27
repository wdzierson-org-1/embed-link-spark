import Foundation
import Observation

/// The Conversations screen's paging state (server-paged `list_conversations`, 25 a page, search
/// over titles + message contents), pulled out of `ConversationsListView` so it's unit-tested.
///
/// Plan 15 (M6, Conversations half): every load is tagged with a generation, so a response for
/// a superseded query — a first page overtaken by newer typing, or an older query's next page
/// finishing after a new search's first page — is dropped instead of replacing or appending to
/// the current results. Cancellation (the debounced `.task(id:)` restarting as the user types, or
/// the screen being popped) is not a failure: it never shows the error state or wipes the list.
@MainActor
@Observable
public final class ConversationsPager {
    public typealias Fetch = @MainActor (_ searchText: String?, _ limit: Int, _ offset: Int) async throws -> [ConversationListRow]

    public private(set) var rows: [ConversationListRow] = []
    public private(set) var totalCount = 0
    public private(set) var isLoading = false
    public private(set) var loadError: String?

    public let pageSize: Int
    private let fetch: Fetch
    @ObservationIgnored private var generation = 0
    /// The query the current `rows` belong to — next pages always continue THAT query, never
    /// whatever is in the search field right now.
    @ObservationIgnored private var activeSearchText: String?

    public init(pageSize: Int = 25, fetch: @escaping Fetch) {
        self.pageSize = pageSize
        self.fetch = fetch
    }

    public var hasMore: Bool { rows.count < totalCount }

    /// Replaces the list with page 1 of `query` (blank → every conversation).
    public func loadFirstPage(query: String) async {
        generation += 1
        let myGeneration = generation
        let searchText = Self.normalized(query)
        activeSearchText = searchText
        isLoading = true
        loadError = nil
        do {
            let page = try await fetch(searchText, pageSize, 0)
            guard myGeneration == generation else { return }
            rows = page
            totalCount = page.first?.totalCount ?? 0
            isLoading = false
        } catch {
            guard myGeneration == generation else { return }
            isLoading = false
            // A cancelled load is superseded or abandoned, not failed: keep what's on screen.
            guard !Self.isCancellation(error) else { return }
            rows = []
            totalCount = 0
            loadError = "Couldn't load conversations."
        }
    }

    /// Appends the next page of the active query. Non-fatal on failure (scrolling retriggers).
    public func loadNextPage() async {
        guard !isLoading, hasMore else { return }
        let myGeneration = generation
        isLoading = true
        do {
            let page = try await fetch(activeSearchText, pageSize, rows.count)
            guard myGeneration == generation else { return }
            let known = Set(rows.map(\.id))
            rows.append(contentsOf: page.filter { !known.contains($0.id) })
            totalCount = page.first?.totalCount ?? totalCount
        } catch {
            guard myGeneration == generation else { return }
        }
        isLoading = false
    }

    private static func normalized(_ query: String) -> String? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : query
    }

    /// Same test `SubscriptionStore` uses: Swift's `CancellationError`, or URLSession's
    /// `URLError(.cancelled)` (what a cancelled supabase-swift request actually throws).
    static func isCancellation(_ error: Error) -> Bool {
        error is CancellationError || (error as? URLError)?.code == .cancelled
    }
}
