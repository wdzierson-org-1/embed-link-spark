import SwiftUI
import StashKit

/// The View tab: paginated card grid over the signed-in user's stash, with local search,
/// server-side type/tag filters, pull-to-refresh, and infinite scroll.
struct LibraryView: View {
    let userId: UUID
    var onSelect: (Item) -> Void = { _ in }

    @State private var store: ItemStore
    @State private var query = ""
    @State private var showTagFilter = false
    @State private var selectedItem: Item?

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    init(userId: UUID, onSelect: @escaping (Item) -> Void = { _ in }) {
        self.userId = userId
        self.onSelect = onSelect
        // Single source of truth for page size — the store's short-page "hasMore" check
        // and the fetcher's SQL LIMIT must agree, or pagination silently breaks.
        let stashPageSize = 50
        _store = State(initialValue: ItemStore(
            userId: userId,
            fetcher: SupabaseItemsFetcher(pageSize: stashPageSize),
            pageSize: stashPageSize
        ))
    }

    private var filteredItems: [Item] {
        query.isEmpty ? store.items : store.items.filter { $0.matches(searchQuery: query) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TypeChipRow(store: store)
                stateBody
            }
            .navigationTitle("Stash")
            .toolbar { LibraryToolbarContent(store: store, showTagFilter: $showTagFilter) }
            .searchable(text: $query, prompt: "Search")
            .searchSuggestions {
                // Only while the field is empty — once the user types, this must get out of
                // the way so filteredItems (live local narrowing) is what's on screen.
                if query.isEmpty {
                    Text("Ask Stash searches inside pages too")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("library.searchHint")
                }
            }
            .refreshable { await store.refresh() }
            .task { await store.refresh() }
            .task { await RealtimeObserver().observeItems(userId: userId) { await store.refresh() } }
            .onChange(of: store.typeFilter) { _, _ in Task { await store.refresh() } }
            .onChange(of: store.selectedTagIds) { _, _ in Task { await store.refresh() } }
            .sheet(isPresented: $showTagFilter) {
                TagFilterSheet(userId: userId, store: store)
            }
            .sheet(item: $selectedItem) { item in
                ItemDetailView(item: item, store: store)
            }
        }
    }

    @ViewBuilder private var stateBody: some View {
        if filteredItems.isEmpty {
            if store.isLoading && store.items.isEmpty {
                // Avoids a "Nothing here yet" flash while the first page is still in flight.
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityIdentifier("library.loading")
            } else if let error = store.loadError {
                LibraryStatePane(systemImage: "exclamationmark.triangle", title: "Couldn't load your stash",
                                  message: error, identifier: "library.error")
            } else if query.isEmpty {
                LibraryStatePane(systemImage: "tray", title: "Nothing here yet",
                                  message: "Save a link, note, or file to get started.", identifier: "library.empty")
            } else {
                LibraryStatePane(systemImage: "magnifyingglass", title: "No matches",
                                  message: "Try a different search term.", identifier: "library.empty")
            }
        } else {
            grid
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(Array(filteredItems.enumerated()), id: \.element.id) { index, item in
                    Button { selectedItem = item; onSelect(item) } label: { ItemCardView(item: item) }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("card.\(index)")
                        .onAppear { Task { await store.loadMoreIfNeeded(current: item) } }
                }
            }
            .padding(12)
        }
        .accessibilityIdentifier("library.grid")
    }
}
