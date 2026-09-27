import SwiftUI
import UIKit
import StashKit

/// The View tab: paginated card grid over the signed-in user's stash, with search,
/// pull-to-refresh, and infinite scroll. Presentation follows the web's library (`Index.tsx` +
/// `LibraryToolbar.tsx`): no wordmark/title (Will's call, plan 8) and no item count (plan 12 —
/// "hide the total number of items"), one compact pill search, cards over the page-level
/// animated gradient. No type chips and no tag filter — the chips never earned their space on a
/// phone, and tags are being deprecated product-wide.
///
/// Plan 15 (Task 3, "Instant library"): the `ItemStore` is owned at app scope
/// (`LibraryStoreProvider` → `MainTabView`), already hydrated from the disk cache and refreshed at
/// sign-in / foreground, so this view never starts cold — appearing only re-fetches page 1 when the
/// last refresh is more than 30 s old, and live changes arrive through the app-scope realtime feed.
/// Search asks the server (`LibrarySearch` → `search-items`, web parity) and shows the instant
/// local filter until it answers. Each card is ONE tap target (see `grid`).
struct LibraryView: View {
    let store: ItemStore
    var onSelect: (Item) -> Void = { _ in }

    @State private var search: LibrarySearch
    @State private var query = ""
    @State private var selectedItem: Item?
    @FocusState private var searchFocused: Bool
    /// Distance (in points) the grid has scrolled from rest, fed by `grid`'s scroll-offset
    /// preference; drives the search bar's fade/collapse (plan-12 device note 6).
    @State private var scrollOffset: CGFloat = 0

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    // Single column on phones (compact width); two-up only where there's real room (iPad).
    private var columns: [GridItem] {
        horizontalSizeClass == .regular
            ? [GridItem(.flexible()), GridItem(.flexible())]
            : [GridItem(.flexible())]
    }

    init(store: ItemStore, onSelect: @escaping (Item) -> Void = { _ in }) {
        self.store = store
        self.onSelect = onSelect
        _search = State(initialValue: LibrarySearch(store: store))
    }

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// The whole library; the instant local filter while a search is typed/in flight (or if the
    /// server can't be reached); and, once `search-items` answers, its results — literal matches
    /// first (`rankedSearchResults`), reaching `page_body` and pages not loaded yet.
    private var displayedItems: [Item] {
        let query = trimmedQuery
        guard !query.isEmpty else { return store.items }
        if let ids = search.serverIds(for: query) {
            return rankedSearchResults(query: query, rankedIds: ids, rowFor: store.item(withId:),
                                       localPool: store.items)
        }
        return store.items.filter { $0.matches(searchQuery: query) }
    }

    /// True while the server search for the CURRENT query hasn't answered yet.
    private var isAwaitingServerSearch: Bool {
        let query = trimmedQuery
        guard query.count >= LibrarySearch.minimumQueryLength else { return false }
        return search.query != query || search.phase == .pending
    }

    var body: some View {
        let items = displayedItems
        ZStack(alignment: .top) {
            Color(.systemBackground).ignoresSafeArea()
            // Page-level ambience, exactly like the web: the gradient lives behind the whole
            // tab (not inside any one component) and washes out before mid-screen.
            GradientBackdrop()
                .frame(height: 380)
                .ignoresSafeArea(edges: .top)

            VStack(spacing: 0) {
                searchBar(fadeProgress: searchFadeProgress(hasItems: !items.isEmpty))
                stateBody(items)
            }
        }
        // Hero images decode for exactly this width (`CardHeroSizing`), the same request the
        // app-scope prefetch makes — so a prefetched hero is drawn in the card's first frame.
        .environment(\.cardWidth, CardHeroSizing.cardWidth(regularWidth: horizontalSizeClass == .regular))
        .refreshable { await store.refresh() }
        .task { await store.refreshIfStale() }
        .onChange(of: query) { _, newValue in search.update(query: newValue) }
        .onChange(of: store.refreshCount) { _, _ in search.invalidateCache() }
        .sheet(item: $selectedItem) { item in
            ItemDetailView(item: item, store: store)
        }
    }

    // MARK: - Search (web LibraryToolbar's rounded-full pill, violet-tinted while focused)

    /// Fully visible/expanded slot height at rest (pill height + the row's own top/bottom
    /// insets) — the number the fade below collapses from, so cards end up flush against the
    /// top edge with no leftover margin once it's gone (plan-12 device note 6).
    private let searchBarRestingHeight: CGFloat = 60
    /// Scroll distance over which the bar fades 1→0 (device note 6: "animate... out of view").
    private let searchFadeDistance: CGFloat = 60

    /// 0 at rest, 1 once the grid has scrolled `searchFadeDistance` points or more. Pinned to 0
    /// whenever there's no scrollable grid (`stateBody`'s empty/loading/error panes) so the bar
    /// never gets stuck faded from a stale offset carried over from a previous search.
    private func searchFadeProgress(hasItems: Bool) -> CGFloat {
        guard hasItems else { return 0 }
        return min(max(scrollOffset / searchFadeDistance, 0), 1)
    }

    /// The pill plus its Cancel affordance (device note 7) as one row, faded/collapsed by scroll.
    /// Deliberately NOT `.animation(value: scrollOffset)` — the fade must track the scroll
    /// gesture 1:1 (no lag behind the finger); only the Cancel button's appear/disappear
    /// (`searchFocused`) gets an explicit easing.
    private func searchBar(fadeProgress searchFadeProgress: CGFloat) -> some View {
        HStack(spacing: 8) {
            searchPill
            if searchFocused {
                Button("Cancel") {
                    query = ""
                    searchFocused = false
                }
                .font(StashType.bodyMedium())
                .foregroundStyle(StashColor.violet600)
                .accessibilityIdentifier("library.search.cancel")
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .frame(height: searchBarRestingHeight * (1 - searchFadeProgress), alignment: .top)
        .clipped()
        .opacity(Double(1 - searchFadeProgress))
        // Stop stealing taps once it's effectively invisible; still interactive at any opacity
        // above that so it stays usable while merely dimming, not just at full strength.
        .allowsHitTesting(searchFadeProgress < 0.99)
        .animation(.easeOut(duration: 0.2), value: searchFocused)
    }

    private var searchPill: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15))
                .foregroundStyle(searchFocused ? StashColor.violet600 : StashColor.faint)
            TextField("Search your stash", text: $query)
                .focused($searchFocused)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
                // Device note 7: submitting a search must be able to dismiss the keyboard too.
                .onSubmit { searchFocused = false }
                .accessibilityIdentifier("library.search")
            if !query.isEmpty {
                Button {
                    // Device note 7: clearing the query with no smart way to also drop the
                    // keyboard was the gap — clear AND dismiss in one tap.
                    query = ""
                    searchFocused = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(StashColor.faint)
                }
                .accessibilityIdentifier("library.search.clear")
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 42)
        .background(Color(.systemBackground), in: Capsule())
        .overlay(Capsule().strokeBorder(searchFocused ? StashColor.violet300 : StashColor.hairline,
                                        lineWidth: 1))
        .shadow(color: .black.opacity(0.05), radius: 3, y: 1)
        // Which answer the grid is showing — "searching" (server pending), "results" (server
        // answered) or "local" (short query / no query / server unreachable). Lets UI tests wait
        // for a search to settle before reading the grid; the container itself isn't a VoiceOver
        // stop (its children are).
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("library.search.pill")
        .accessibilityValue(searchStateValue)
    }

    private var searchStateValue: String {
        if isAwaitingServerSearch { return "searching" }
        return search.serverIds(for: trimmedQuery) != nil ? "results" : "local"
    }

    @ViewBuilder private func stateBody(_ items: [Item]) -> some View {
        if items.isEmpty {
            if store.isRefreshing && store.items.isEmpty {
                // Avoids a "Nothing here yet" flash while the first page is still in flight — only
                // on a first-ever launch now: a cached page shows instantly otherwise.
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityIdentifier("library.loading")
            } else if isAwaitingServerSearch {
                // Nothing matched locally, but the server (which also reads page_body and pages
                // not loaded yet) hasn't answered — don't claim "No matches" before it has.
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityIdentifier("library.searching")
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
                grid(items)
            }
        }
    }

    private func grid(_ items: [Item]) -> some View {
        ScrollView {
            // DESIGN.md §Space "Library gutter: 24px/24pt" (plan 14, was 14pt) — natural-height
            // cards, no forced masonry redistribution needed on the phone's single column.
            LazyVGrid(columns: columns, spacing: 24) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    Button {
                        // Device note 3/7: a card tap dismisses the keyboard before the sheet
                        // opens, rather than leaving it up behind the presented detail sheet.
                        searchFocused = false
                        selectedItem = item
                        onSelect(item)
                    } label: {
                        // Plan 15: the card is ONE tap target and its hit area is exactly what's
                        // drawn — without this shape, content that overflows a card (fill-scaled
                        // hero imagery) could still take taps outside it; see `CardHero.swift`.
                        ItemCardView(item: item)
                            .contentShape(RoundedRectangle(cornerRadius: StashRadius.card))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("card.\(index)")
                    .onAppear { Task { await store.loadMoreIfNeeded(current: item) } }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 12)
            // Feeds `scrollOffset` so `searchBar` can fade/collapse 1:1 with the gesture. The
            // textbook SwiftUI approach — a `GeometryReader` here reporting `.frame(in:
            // .named(...))` through a `PreferenceKey`, with `.coordinateSpace(name:)` on the
            // `ScrollView` — was tried first and does NOT work on this app's iOS 17 floor:
            // verified empirically (NSLog + a live `log stream` during a UI-test swipe) that the
            // preference fires once at initial layout and never again during an interactive
            // touch-driven scroll (pre-iOS-18 `ScrollView` moves content via UIKit without a
            // matching declarative geometry pass every frame — exactly the gap
            // `onScrollGeometryChange`, iOS 18+, was introduced to close). Below that floor, this
            // reads the same signal the reliable way instead: KVO straight on the real
            // `UIScrollView`'s `contentOffset`, found by walking up from an invisible marker
            // view planted here inside the scrolled content. Works identically on iOS 18+ too,
            // so one path covers the whole `iOS 17` deployment target without a version branch.
            .background(
                LibraryScrollOffsetObserver { newValue in scrollOffset = newValue }
            )
        }
        .accessibilityIdentifier("library.grid")
        .scrollDismissesKeyboard(.immediately)
    }
}

/// See `LibraryView.grid`'s trailing comment for why this exists instead of the usual
/// GeometryReader/PreferenceKey trick. Invisible and zero-size; must sit inside the
/// `ScrollView`'s own content so walking `superview` reaches the real `UIScrollView`.
private struct LibraryScrollOffsetObserver: UIViewRepresentable {
    var onChange: (CGFloat) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        // `didMoveToWindow` (not a post-`makeUIView` `DispatchQueue.main.async` guess) is the
        // correct hook: it fires once this view's FULL ancestor chain — up through the real
        // `UIScrollView` and into the window — actually exists. An async dispatch fired too
        // early here only ever saw one wrapper level (`PlatformViewHost<...>`) with a still-nil
        // superview above it, silently finding no scroll view (verified empirically).
        view.onWindowAttach = { [weak view] in
            guard let view else { return }
            context.coordinator.attach(from: view, onChange: onChange)
        }
        return view
    }

    func updateUIView(_ uiView: ProbeView, context: Context) {
        guard context.coordinator.observation == nil, uiView.window != nil else { return }
        context.coordinator.attach(from: uiView, onChange: onChange)
    }

    /// Zero-size marker `UIView` that reports the one moment it's safe to walk up for the
    /// enclosing `UIScrollView`.
    final class ProbeView: UIView {
        var onWindowAttach: (() -> Void)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window != nil { onWindowAttach?() }
        }
    }

    final class Coordinator {
        var observation: NSKeyValueObservation?

        func attach(from view: UIView, onChange: @escaping (CGFloat) -> Void) {
            guard observation == nil else { return }
            var ancestor = view.superview
            while let candidate = ancestor {
                if let scrollView = candidate as? UIScrollView {
                    onChange(max(0, scrollView.contentOffset.y + scrollView.adjustedContentInset.top))
                    observation = scrollView.observe(\.contentOffset, options: [.new]) { scrollView, _ in
                        onChange(max(0, scrollView.contentOffset.y + scrollView.adjustedContentInset.top))
                    }
                    return
                }
                ancestor = candidate.superview
            }
        }
    }
}
