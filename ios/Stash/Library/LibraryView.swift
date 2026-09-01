import SwiftUI
import StashKit

/// The View tab: paginated card grid over the signed-in user's stash, with local search,
/// pull-to-refresh, and infinite scroll. Presentation follows the web's library (`Index.tsx` +
/// `LibraryToolbar.tsx`): wordmark header with the item count, one compact pill search, cards
/// over the page-level animated gradient. No type chips and no tag filter — the chips never
/// earned their space on a phone, and tags are being deprecated product-wide.
struct LibraryView: View {
    let userId: UUID
    var onSelect: (Item) -> Void = { _ in }

    @State private var store: ItemStore
    @State private var query = ""
    @State private var selectedItem: Item?
    @FocusState private var searchFocused: Bool

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    // Single column on phones (compact width); two-up only where there's real room (iPad).
    private var columns: [GridItem] {
        horizontalSizeClass == .regular
            ? [GridItem(.flexible()), GridItem(.flexible())]
            : [GridItem(.flexible())]
    }

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
        ZStack(alignment: .top) {
            Color(.systemBackground).ignoresSafeArea()
            // Page-level ambience, exactly like the web: the gradient lives behind the whole
            // tab (not inside any one component) and washes out before mid-screen.
            GradientBackdrop()
                .frame(height: 380)
                .ignoresSafeArea(edges: .top)

            VStack(spacing: 10) {
                StashHeader {
                    Text(store.items.count == 1 ? "1 item" : "\(store.items.count) items")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("library.itemCount")
                }
                searchPill
                    .padding(.horizontal, 16)
                stateBody
            }
        }
        .refreshable { await store.refresh() }
        .task { await store.refresh() }
        .task { await RealtimeObserver().observeItems(userId: userId) { await store.refresh() } }
        .sheet(item: $selectedItem) { item in
            ItemDetailView(item: item, store: store)
        }
    }

    // MARK: - Search (web LibraryToolbar's rounded-full pill, violet-tinted while focused)

    private var searchPill: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15))
                .foregroundStyle(searchFocused ? StashColor.violet : StashColor.gray400)
            TextField("Search your stash", text: $query)
                .focused($searchFocused)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
                .accessibilityIdentifier("library.search")
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(StashColor.gray400)
                }
                .accessibilityIdentifier("library.search.clear")
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 42)
        .background(Color(.systemBackground), in: Capsule())
        .overlay(Capsule().strokeBorder(searchFocused ? StashColor.violet300 : StashColor.gray300,
                                        lineWidth: 1))
        .shadow(color: .black.opacity(0.05), radius: 3, y: 1)
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
            VStack(spacing: 0) {
                if let error = store.loadError {
                    LibraryErrorBanner(message: error) { Task { await store.refresh() } }
                }
                grid
            }
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(Array(filteredItems.enumerated()), id: \.element.id) { index, item in
                    Button { selectedItem = item; onSelect(item) } label: { ItemCardView(item: item) }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("card.\(index)")
                        .onAppear { Task { await store.loadMoreIfNeeded(current: item) } }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 12)
        }
        .accessibilityIdentifier("library.grid")
        .scrollDismissesKeyboard(.immediately)
    }
}
