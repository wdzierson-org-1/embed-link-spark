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
/// `libraryScroll` and `LibrarySearchRow`.
struct LibraryView: View {
    let store: ItemStore
    var onSelect: (Item) -> Void = { _ in }

    @State private var search: LibrarySearch
    @State private var query = ""
    @State private var selectedItem: Item?
    @FocusState private var searchFocused: Bool
    /// How far the search row has scrolled away (`LibrarySearchFade`). Only the row and the
    /// status-bar scrim read it — never this view's `body` — so a frame in the fade band doesn't
    /// re-run the tab (its search results, the grid's diff) (plan 16 review M-4).
    @State private var searchFade = LibrarySearchFade()
    /// The search row's laid-out height: the band the scroll snaps out of (`LibrarySearchRowSnap`),
    /// and what a state pane (loading, empty, no matches, error) leaves above itself, as when the row
    /// sat above it. 62 is its height at the default text size (plan 16: the pill is at least 44 pt
    /// tall, was a fixed 42); it grows with the text.
    @State private var searchRowHeight: CGFloat = 62
    /// The scroll view's visible height, inside its safe area — the keyboard's included, so it is
    /// smaller while the keyboard is up — as measured; nil until its first measurement. A state pane
    /// fills it below the search row (`stateBody`). Batch B: `containerRelativeFrame`, which sized
    /// the pane on its own, doesn't follow the keyboard on iOS 17.0. Logged on an iPhone 15 Pro, it
    /// kept reporting a height read before the keyboard last moved: the whole tab (710 pt) with the
    /// keyboard up after a fresh tap, and the keyboard-up height (456) after the keyboard had gone
    /// when the pill had been scrolled back to rest under the keyboard first, so "No matches" stayed
    /// centred above a keyboard that wasn't there (319 pt against 445). This measurement, logged the
    /// same way, followed the keyboard both ways (457 ↔ 710).
    @State private var visibleHeight: CGFloat?

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    /// Plan 16: while VoiceOver runs, the search row's snap stands aside — VoiceOver scrolls to
    /// what it focuses and by pages (three-finger swipes), and a snap re-aiming those scrolls would
    /// fight it. (Focusing the search field brings its row back in full either way —
    /// `LibrarySearchRow`.)
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled

    fileprivate static let searchRowID = "library.searchRow"

    /// `--uitest-search-no-snap` (UI tests only, compiled out of Release) turns the search row's snap
    /// off, so `LibraryDetailUITests` can sample the row part-way out between slow drags.
    private static let snapsSearchRow: Bool = {
        #if DEBUG
        return !ProcessInfo.processInfo.arguments.contains("--uitest-search-no-snap")
        #else
        return true
        #endif
    }()

    /// `--uitest-library-error-banner` (UI tests only, compiled out of Release): the refresh-error
    /// banner over the cards, with a sample message, so the accessibility screenshot matrix can
    /// shoot it (plan 16) — a real one needs a failed refresh.
    private static let showsSampleErrorBanner: Bool = {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("--uitest-library-error-banner")
        #else
        return false
        #endif
    }()

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
            LibraryStatusBarScrim(fade: searchFade)
        }
        // Hero images decode for exactly this width (`CardHeroSizing`), the same request the
        // app-scope prefetch makes — so a prefetched hero is drawn in the card's first frame.
        .environment(\.cardWidth, CardHeroSizing.cardWidth(regularWidth: horizontalSizeClass == .regular))
        .refreshable { await store.refresh() }
        .task { await store.refreshIfStale() }
        .onChange(of: query) { _, newValue in search.update(query: newValue) }
        .onChange(of: store.refreshCount) { _, _ in search.invalidateCache() }
        // Plan 16 (2a review N6): never a focused search under the detail sheet. Its Cancel carries
        // the hardware ⌘. (`.cancelAction`), which could reach it from inside the sheet through the
        // responder chain and clear the query; the card tap drops the focus first (`open`), and
        // this catches any other way a sheet comes up.
        .onChange(of: selectedItem?.id) { _, id in
            if id != nil { searchFocused = false }
        }
        .sheet(item: $selectedItem) { item in
            ItemDetailView(item: item, store: store)
        }
    }

    /// A card tap: the search field (and its Cancel, with the ⌘. shortcut) lets go first, then the
    /// sheet opens — the keyboard never stays up behind it (device note 3/7) and nothing in the
    /// sheet can reach the search (review N6).
    private func open(_ item: Item) {
        searchFocused = false
        selectedItem = item
        onSelect(item)
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
    ///
    /// Plan 16 review: the row never RESTS part-way out (`LibrarySearchRowSnap`, M-2), the status
    /// bar never sits over scrolled content (`LibraryStatusBarScrim`, M-1), and the row owns its
    /// fade (`LibrarySearchRow`, M-4).
    private func libraryScroll(_ items: [Item]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    LibrarySearchRow(query: $query, focused: $searchFocused, proxy: proxy, fade: searchFade,
                                     searchState: searchStateValue)
                        .id(Self.searchRowID)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { searchRowHeight = $0 }
                    stateBody(items)
                }
            }
            .scrollTargetBehavior(LibrarySearchRowSnap(rowHeight: searchRowHeight,
                                                       isEnabled: Self.snapsSearchRow && !voiceOverEnabled))
            // `library.grid` names the scroll view while it shows cards (UI tests scroll and
            // pull to refresh through it), as when only the grid scrolled.
            .accessibilityIdentifier(items.isEmpty ? "library.scroll" : "library.grid")
            .scrollDismissesKeyboard(.immediately)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { visibleHeight = $0 }
        }
    }

    /// Which answer the grid is showing — "searching" (server pending), "results" (server answered)
    /// or "local" (short query / no query / server unreachable); the search pill's
    /// `accessibilityValue`, so UI tests can wait for a search to settle before reading the grid.
    private var searchStateValue: String {
        if isAwaitingServerSearch { return "searching" }
        return search.serverIds(for: trimmedQuery) != nil ? "results" : "local"
    }

    // MARK: - Body below the search row

    @ViewBuilder private func stateBody(_ items: [Item]) -> some View {
        if items.isEmpty {
            // The rest of the tab below the search row, as when the row sat above the pane — at
            // least the scroll view's visible height less the row, and taller when the pane's text
            // needs it. That height is `visibleHeight`, which follows the keyboard (batch B); until
            // its first measurement the container itself supplies it, so the first frame is already
            // centred (no viewport height that starts at 0, review N-2).
            ZStack {
                if let visibleHeight {
                    Color.clear.frame(height: max(visibleHeight - searchRowHeight, 0))
                } else {
                    Color.clear
                        .containerRelativeFrame(.vertical) { length, _ in max(length - searchRowHeight, 0) }
                }
                statePane
            }
            .frame(maxWidth: .infinity)
        } else {
            if let error = store.loadError {
                LibraryErrorBanner(message: error) { Task { await store.refresh() } }
            } else if Self.showsSampleErrorBanner {
                LibraryErrorBanner(message: "The Internet connection appears to be offline.") {}
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
                    open(item)
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

// MARK: - Search row (plan 16)

/// How much of the View tab's search row is still in view below the scroll view's top edge — 1 at
/// rest (and while the list is pulled down), 0 once it has scrolled all the way under that edge.
/// Written by the row's `LibraryScrollVisibilityObserver`; read only by the row (its fade) and the
/// status-bar scrim. `LibraryView` holds it but never reads it, so a change re-renders those two
/// small views and nothing else (review M-4).
@MainActor @Observable
private final class LibrarySearchFade {
    var visibility: CGFloat = 1
}

/// The search pill (web LibraryToolbar's rounded-full pill, violet-tinted while focused) plus its
/// Cancel affordance (device note 7) as one row — the first element of the View tab's scroll
/// content — fading as it scrolls up under the top edge by its OWN position (`fade`), 1:1 with the
/// gesture: deliberately no `.animation` on the fade, so it never lags the finger; only the Cancel
/// button's appear/disappear gets an explicit easing. Fully opaque while focused. The observer
/// sits behind the fade, so it keeps measuring at any opacity.
///
/// Its own view (review M-4): the fade is read here, not in `LibraryView.body`, so a frame in the
/// fade band re-renders this row — not the tab's search results or the grid.
///
/// Plan 16 (HIG + accessibility):
/// - Cancel is the shared `StashCancelButton` on its paper capsule (the row sits on the gradient
///   wash, where violet text fails contrast): the `textButton` role, one line at every size, a 44 pt
///   target that overhangs instead of growing the row, ⌘. on a hardware keyboard — and, as before,
///   it clears the query too (the iOS search convention; its VoiceOver hint says so). At the
///   accessibility sizes it sits under the pill (`rowLayout`).
/// - The pill is at least 44 pt tall (it was a fixed 42 that clipped large text); the field is
///   reading text (17) with a `muted` placeholder — "Search" at the accessibility sizes, where
///   "Search your stash" doesn't fit the pill — and the magnifier grows with it.
/// - The clear × takes a 44 pt target (`.stashPlain`) that stops short of the field, so a tap at the
///   end of a long query never clears it, and has a name.
/// - VoiceOver: when the field gets VoiceOver's focus while the row is part-way or all the way
///   out (it stays in the accessibility tree at its 1 % fade floor), the row scrolls back to rest
///   at full opacity, so what VoiceOver outlines is what the user sees; and after Cancel or the ×
///   (both vanish with the keyboard) VoiceOver's focus lands on the field, not wherever it falls.
private struct LibrarySearchRow: View {
    @Binding var query: String
    var focused: FocusState<Bool>.Binding
    /// Scrolls the row back to rest when its field is focused part-way out.
    let proxy: ScrollViewProxy
    let fade: LibrarySearchFade
    /// `LibraryView.searchStateValue` — the pill's `accessibilityValue`.
    let searchState: String

    /// VoiceOver's focus on the search field (not the keyboard's).
    @AccessibilityFocusState private var fieldHasVoiceOverFocus: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled

    /// Beside the pill at the standard sizes; at the accessibility sizes Cancel goes on its own line
    /// under it (trailing), so the field keeps the row's width — beside a 37 pt "Cancel" it had
    /// room for four or five characters of the query. `AnyLayout` keeps the field the same view
    /// (and its focus) if the text size changes while it's up.
    private var rowLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .trailing, spacing: 12))
            : AnyLayout(HStackLayout(spacing: 8))
    }

    var body: some View {
        let isFocused = focused.wrappedValue
        let visibility = fade.visibility
        rowLayout {
            pill(isFocused: isFocused)
            if isFocused {
                StashCancelButton(identifier: "library.search.cancel", onWash: true,
                                  hint: "Clears the search and hides the keyboard") {
                    query = ""
                    focused.wrappedValue = false
                    moveVoiceOverToField()
                }
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
        .opacity(isFocused ? 1 : max(Double(visibility), 0.01))
        // Stop stealing taps once it's effectively invisible; still interactive at any opacity
        // above that so it stays usable while merely dimming, not just at full strength.
        .allowsHitTesting(isFocused || visibility > 0.01)
        .animation(.easeOut(duration: 0.2), value: isFocused)
        .background(LibraryScrollVisibilityObserver { [fade] in fade.visibility = $0 })
        // Never part-way out while its field has focus: a tap into a part-way pill (only a list
        // barely taller than the screen can leave it there — see `LibrarySearchRowSnap`) brings it
        // all the way back, and a scroll drops the keyboard (and the focus) before it moves the
        // row (`.scrollDismissesKeyboard`) — so typing always happens in full view.
        .onChange(of: isFocused) { _, nowFocused in
            guard nowFocused, fade.visibility < 1 else { return }
            withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(LibraryView.searchRowID, anchor: .top) }
        }
        // Plan 16 (Task 4 review M-3): VoiceOver reaches the field from anywhere in the list — it
        // stays in the tree at the 1 % fade floor — so bring its row back to rest when it does.
        // (A target of 0 is one the row's snap leaves alone.)
        .onChange(of: fieldHasVoiceOverFocus) { _, hasFocus in
            guard hasFocus, fade.visibility < 1 else { return }
            withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(LibraryView.searchRowID, anchor: .top) }
        }
        #if DEBUG
        // `--uitest-voiceover-focus-search-after <seconds>` (UI tests only, compiled out of Release):
        // moves VoiceOver's focus to the field that long after the row appears — what VoiceOver's
        // own navigation does when a swipe lands on it. XCUITest's touches and keys never reach
        // VoiceOver, so this is how the plan-16 VoiceOver probe puts it there.
        .task {
            let arguments = ProcessInfo.processInfo.arguments
            guard let index = arguments.firstIndex(of: "--uitest-voiceover-focus-search-after"),
                  index + 1 < arguments.count, let seconds = Double(arguments[index + 1]) else { return }
            try? await Task.sleep(for: .seconds(seconds))
            fieldHasVoiceOverFocus = true
        }
        #endif
    }

    /// Cancel and the × both disappear as they act (with the keyboard): VoiceOver's focus goes to
    /// the field they belonged to rather than jumping wherever it falls. Only while VoiceOver runs —
    /// otherwise the focus state has no one to hand it to, and would stay set.
    private func moveVoiceOverToField() {
        guard voiceOverEnabled else { return }
        fieldHasVoiceOverFocus = true
    }

    private func pill(isFocused: Bool) -> some View {
        HStack(spacing: 8) {
            // Scales with the field's text (15 beside its 17, at every size); decorative — the
            // field says what it's for. A tap on it falls through to the pill (focuses the field).
            Image(systemName: "magnifyingglass")
                .stashFont(.custom(.book, size: 15, relativeTo: StashType.Role.reading.textStyle))
                .foregroundStyle(isFocused ? StashColor.violet600 : StashColor.muted)
                .accessibilityHidden(true)
                .allowsHitTesting(false)
            TextField("Search your stash", text: $query,
                      prompt: Text(dynamicTypeSize.isAccessibilitySize ? "Search" : "Search your stash")
                        .foregroundStyle(StashColor.muted))
                .stashFont(.reading)
                .focused(focused)
                .accessibilityFocused($fieldHasVoiceOverFocus)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
                // Device note 7: submitting a search must be able to dismiss the keyboard too.
                .onSubmit { focused.wrappedValue = false }
                .accessibilityIdentifier("library.search")
            if !query.isEmpty {
                Button {
                    // Device note 7: clearing the query with no smart way to also drop the
                    // keyboard was the gap — clear AND dismiss in one tap.
                    query = ""
                    focused.wrappedValue = false
                    moveVoiceOverToField()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(StashColor.muted)
                }
                .buttonStyle(.stashPlain)
                .stashIconControl("Clear search", systemImage: "xmark.circle.fill")
                .accessibilityIdentifier("library.search.clear")
                // 2b review M-4: the 44 pt target overhangs the glyph by (44 − its width) / 2 — 11.9
                // pt at Large, 13.7 at xSmall — and the later sibling wins an overlap, so with the
                // 8 pt row spacing alone it covered the last ~4 pt of the field: a tap meant for the
                // end of a long query cleared it. 6 pt more keeps the target clear of the field at
                // every text size (what's left between them is the pill's, whose tap focuses the
                // field). The glyph stays put; the field ends 6 pt sooner.
                .padding(.leading, 6)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .frame(minHeight: 44)
        // The whole pill — at least 44 pt tall — takes the tap that focuses the field, as a system
        // search field does: the field itself is only its line of text (~22 pt) and the magnifier.
        // The pill's fill takes those taps from behind, so a tap on the text still reaches the
        // field (caret) and the clear × keeps its own.
        .background {
            Capsule()
                .fill(Color(.systemBackground))
                .onTapGesture { focused.wrappedValue = true }
        }
        .overlay(Capsule().strokeBorder(isFocused ? StashColor.violet300 : StashColor.hairline, lineWidth: 1))
        .shadow(color: .black.opacity(0.05), radius: 3, y: 1)
        // The container itself isn't a VoiceOver stop (its children are).
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("library.search.pill")
        .accessibilityValue(searchState)
    }
}

/// Review M-2: the search row never comes to REST part-way out — half faded, partly under the
/// clock. A scroll that would come to rest inside the row goes to the nearer end instead: all the
/// way back, or all the way out (clamped to how far the content can scroll, so a list barely taller
/// than the screen can still reach its end). Any other resting place, a fling that carries past
/// the row, and a pull to refresh are left alone — as UIKit's hide-on-scroll search bar behaves.
///
/// `ScrollTarget` coordinates are measured from the resting position (0 at rest, measured on the
/// iOS 17.2 simulator: a release 14 pt down reported `minY` 14 while UIKit's `contentOffset` was
/// −45 under a 59 pt inset), and `contentSize − containerSize` is the furthest the list scrolls.
private struct LibrarySearchRowSnap: ScrollTargetBehavior {
    var rowHeight: CGFloat
    var isEnabled: Bool

    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        guard isEnabled, rowHeight > 0 else { return }
        let resting = target.rect.minY
        guard resting > 0, resting < rowHeight else { return }
        let furthest = max(context.contentSize.height - context.containerSize.height, 0)
        target.rect.origin.y = min(resting < rowHeight / 2 ? 0 : rowHeight, furthest)
    }
}

/// Review M-1: once the search row scrolls away, cards run on up under the status bar — the clock
/// and battery would sit on whatever scrolled there (unreadable over a dark hero image), and the
/// pill itself faded out right under them. This fills the top safe area with the page's own
/// background colour, fading in as the row fades out (opacity 1 − visibility): invisible at rest,
/// opaque once the row is gone, so the status bar always sits on paper once content is under it —
/// identical on iOS 17 and 26 (this tab has no bar at the top for iOS 26's scroll-edge effect). A
/// short ramp of the same colour below the band lets content fade into it instead of being cut.
private struct LibraryStatusBarScrim: View {
    let fade: LibrarySearchFade

    var body: some View {
        VStack(spacing: 0) {
            // A zero-height view on the safe area's top edge whose background extends into the top
            // safe area (`ignoresSafeAreaEdges`) — exactly the band the status bar occupies.
            Color.clear
                .frame(height: 0)
                .background(Color(.systemBackground), ignoresSafeAreaEdges: .top)
            LinearGradient(colors: [Color(.systemBackground), Color(.systemBackground).opacity(0)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 12)
        }
        .opacity(1 - Double(fade.visibility))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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
        ///
        /// Review N-1: with nothing scheduled, an unchanged value is dropped right here, so deep in
        /// the list a scroll frame costs one rect conversion and no main-queue hop at all.
        private func report(_ value: CGFloat) {
            let alreadyScheduled = pending != nil
            if !alreadyScheduled, value == lastReported { return }
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
