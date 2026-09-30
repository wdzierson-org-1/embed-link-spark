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
///
/// Plan 16: every state scrolls in one scroll view whose first element is the search row — see
/// `libraryScroll`.
struct LibraryView: View {
    let store: ItemStore
    var onSelect: (Item) -> Void = { _ in }

    @State private var search: LibrarySearch
    @State private var query = ""
    @State private var selectedItem: Item?
    @FocusState private var searchFocused: Bool
    /// How much of the search row is still in view below the scroll view's top edge — 1 at rest
    /// (and while the list is pulled down), 0 once it has scrolled all the way under that edge.
    /// Measured by `LibraryScrollVisibilityObserver`, planted behind the row; drives its fade
    /// (plan-12 device note 6, rebuilt in plan 16).
    @State private var searchVisibility: CGFloat = 1
    /// The search row's laid-out height and the tab's own height: a state pane (loading, empty, no
    /// matches, error) fills what the row leaves, as it did when the row sat above it.
    @State private var searchRowHeight: CGFloat = 60
    @State private var viewportHeight: CGFloat = 0

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private static let searchRowID = "library.searchRow"

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
    /// first (`rankedSearchResults`), reaching `page_body` and pages not loaded yet. The local
    /// filter matches the same plain card text the ranking does (`matchesCardText` — a rich note
    /// is read as its words, never its TipTap JSON), so a card can't match while the server is
    /// pending and then drop out (or jump) once it answers.
    private var displayedItems: [Item] {
        let query = trimmedQuery
        guard !query.isEmpty else { return store.items }
        if let ids = search.serverIds(for: query) {
            return rankedSearchResults(query: query, rankedIds: ids, rowFor: store.item(withId:),
                                       localPool: store.items)
        }
        return store.items.filter { $0.matchesCardText(searchQuery: query) }
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

            libraryScroll(items)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { viewportHeight = $0 }
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

    // MARK: - Scroll surface (plan 16)

    /// One scroll view for every state — cards, loading, searching, empty, error — whose first
    /// element is the search row. The row used to sit ABOVE the grid and collapse its own height
    /// (clipped) as the grid scrolled, while the grid's top edge slid up behind it: part-way, the
    /// first card covered the pill's lower half (Will's 2026-09-30 device screenshot). Inside the
    /// content it just scrolls away with the cards — nothing collapses or clips, a card can never
    /// overlap it, and once it's gone the list runs to the top of the screen. One scroll view for
    /// every state also keeps the row (and its field's focus) the same view while typing flips the
    /// body between cards and a state pane.
    private func libraryScroll(_ items: [Item]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    searchRow
                        .id(Self.searchRowID)
                    stateBody(items)
                }
            }
            // `library.grid` names the scroll view while it shows cards (UI tests scroll and
            // pull to refresh through it), as when only the grid scrolled.
            .accessibilityIdentifier(items.isEmpty ? "library.scroll" : "library.grid")
            .scrollDismissesKeyboard(.immediately)
            // Never part-way out while its field has focus: a tap into a half-scrolled pill brings
            // it all the way back, and a scroll drops the keyboard (and the focus) before it moves
            // the row (`.scrollDismissesKeyboard`) — so typing always happens in full view.
            .onChange(of: searchFocused) { _, focused in
                guard focused, searchVisibility < 1 else { return }
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(Self.searchRowID, anchor: .top) }
            }
        }
    }

    // MARK: - Search (web LibraryToolbar's rounded-full pill, violet-tinted while focused)

    /// The pill plus its Cancel affordance (device note 7) as one row, fading as it scrolls up
    /// under the top edge — by its OWN position (`searchVisibility`), 1:1 with the gesture:
    /// deliberately no `.animation` on the fade, so it never lags the finger; only the Cancel
    /// button's appear/disappear (`searchFocused`) gets an explicit easing. Fully opaque while
    /// focused. The observer sits behind the fade, so it keeps measuring at any opacity.
    private var searchRow: some View {
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
        // Never quite 0: SwiftUI drops a fully transparent view from the accessibility tree
        // (measured: the field vanished from it the moment the row's fade hit 0), and the search
        // field should stay reachable from anywhere in the list like any other scrolled-away
        // content — VoiceOver scrolls it back into view. 1% is invisible.
        .opacity(searchFocused ? 1 : max(Double(searchVisibility), 0.01))
        // Stop stealing taps once it's effectively invisible; still interactive at any opacity
        // above that so it stays usable while merely dimming, not just at full strength.
        .allowsHitTesting(searchFocused || searchVisibility > 0.01)
        .animation(.easeOut(duration: 0.2), value: searchFocused)
        .background(LibraryScrollVisibilityObserver { searchVisibility = $0 })
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { searchRowHeight = $0 }
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

    // MARK: - Body below the search row

    @ViewBuilder private func stateBody(_ items: [Item]) -> some View {
        if items.isEmpty {
            statePane
                // The rest of the tab below the search row, as when the row sat above the pane.
                .frame(maxWidth: .infinity, minHeight: max(viewportHeight - searchRowHeight, 0))
        } else {
            if let error = store.loadError {
                LibraryErrorBanner(message: error) { Task { await store.refresh() } }
            }
            grid(items)
        }
    }

    @ViewBuilder private var statePane: some View {
        if store.isRefreshing && store.items.isEmpty {
            // Avoids a "Nothing here yet" flash while the first page is still in flight — only
            // on a first-ever launch now: a cached page shows instantly otherwise.
            ProgressView()
                .accessibilityIdentifier("library.loading")
        } else if isAwaitingServerSearch {
            // Nothing matched locally, but the server (which also reads page_body and pages
            // not loaded yet) hasn't answered — don't claim "No matches" before it has.
            ProgressView()
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
    }

    private func grid(_ items: [Item]) -> some View {
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
    }
}

/// Reports how much of the view it's planted behind is still in view below its scroll view's top
/// edge: 1 while all of it is (or the content is pulled down past the top), 0 once all of it has
/// scrolled under that edge — the search row's fade (plan 16). Invisible; must sit inside the
/// `ScrollView`'s own content so walking `superview` reaches the real `UIScrollView`.
///
/// Why KVO and not the textbook SwiftUI approach: a `GeometryReader` reporting `.frame(in:
/// .named(...))` through a `PreferenceKey`, with `.coordinateSpace(name:)` on the `ScrollView`,
/// was tried first (plan 12) and does NOT work on this app's iOS 17 floor — verified empirically
/// (NSLog + a live `log stream` during a UI-test swipe) that the preference fires once at initial
/// layout and never again during an interactive touch-driven scroll (pre-iOS-18 `ScrollView` moves
/// content via UIKit without a matching declarative geometry pass every frame — exactly the gap
/// `onScrollGeometryChange`, iOS 18+, was introduced to close). This reads the same signal the
/// reliable way instead: KVO straight on the real `UIScrollView`'s `contentOffset`, then the
/// probe's own frame in the scroll view's coordinates, so the row fades by where IT is. Works
/// identically on iOS 18+ too, so one path covers the whole iOS 17 deployment target.
///
/// Reports are never delivered synchronously (final wave B): the KVO callback also fires when
/// SwiftUI's OWN layout moves the content — the grid's content changes — i.e. inside a view
/// update, and writing `@State` there is undefined behavior. That was the "Modifying state during
/// view update" runtime issue every UI test logged once it reached the View tab (unified-log
/// backtraces: the state setter ← this KVO handler, 15 times in one `testLibrarySmoke`). See
/// `Coordinator.report`.
private struct LibraryScrollVisibilityObserver: UIViewRepresentable {
    var onChange: (CGFloat) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        context.coordinator.onChange = onChange
        // `didMoveToWindow` (not a post-`makeUIView` `DispatchQueue.main.async` guess) is the
        // correct hook: it fires once this view's FULL ancestor chain — up through the real
        // `UIScrollView` and into the window — actually exists. An async dispatch fired too
        // early here only ever saw one wrapper level (`PlatformViewHost<...>`) with a still-nil
        // superview above it, silently finding no scroll view (verified empirically).
        view.onWindowAttach = { [weak view, weak coordinator = context.coordinator] in
            guard let view, let coordinator else { return }
            coordinator.attach(from: view)
        }
        // The row's own size changing (first layout, Dynamic Type) moves its bottom edge without
        // any scrolling — measure again then too.
        view.onLayout = { [weak coordinator = context.coordinator] in coordinator?.measure() }
        return view
    }

    func updateUIView(_ uiView: ProbeView, context: Context) {
        context.coordinator.onChange = onChange
        guard !context.coordinator.isAttached, uiView.window != nil else { return }
        context.coordinator.attach(from: uiView)
    }

    /// Marker `UIView` that reports the one moment it's safe to walk up for the enclosing
    /// `UIScrollView`, and its own layouts.
    final class ProbeView: UIView {
        var onWindowAttach: (() -> Void)?
        var onLayout: (() -> Void)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window != nil { onWindowAttach?() }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            onLayout?()
        }
    }

    final class Coordinator {
        var onChange: ((CGFloat) -> Void)?
        private var observation: NSKeyValueObservation?
        private weak var probe: UIView?
        private weak var scrollView: UIScrollView?
        /// The newest value not handed over yet (non-nil while a hand-over is scheduled).
        private var pending: CGFloat?
        private var lastReported: CGFloat?

        var isAttached: Bool { observation != nil }

        func attach(from view: UIView) {
            guard observation == nil else { return }
            var ancestor = view.superview
            while let candidate = ancestor {
                if let scrollView = candidate as? UIScrollView {
                    probe = view
                    self.scrollView = scrollView
                    observation = scrollView.observe(\.contentOffset, options: [.new]) { [weak self] _, _ in
                        self?.measure()
                    }
                    measure()
                    return
                }
                ancestor = candidate.superview
            }
        }

        func measure() {
            guard let probe, let scrollView else { return }
            report(Self.visibility(of: probe, in: scrollView))
        }

        /// The share of `probe`'s height below the scroll view's visible top edge (the top of its
        /// safe area, in content coordinates), clamped to 0...1. An unlaid-out probe counts as
        /// fully visible.
        private static func visibility(of probe: UIView, in scrollView: UIScrollView) -> CGFloat {
            let frame = probe.convert(probe.bounds, to: scrollView)
            guard frame.height > 0 else { return 1 }
            let visibleTop = scrollView.contentOffset.y + scrollView.adjustedContentInset.top
            return min(max((frame.maxY - visibleTop) / frame.height, 0), 1)
        }

        /// Hands the newest value to SwiftUI on the next main-queue turn — outside whatever view
        /// update may be running now — coalescing a burst into one write and skipping a value that
        /// didn't change (so once the row is fully out, scrolling on writes nothing at all). That
        /// turn normally comes before the next frame is drawn, so the fade still tracks the finger.
        private func report(_ value: CGFloat) {
            let alreadyScheduled = pending != nil
            pending = value
            guard !alreadyScheduled else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, let value = self.pending else { return }
                self.pending = nil
                guard value != self.lastReported else { return }
                self.lastReported = value
                self.onChange?(value)
            }
        }
    }
}
