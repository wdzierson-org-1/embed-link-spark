import SwiftUI
import StashKit

enum MainTab: Hashable { case add, ask, view, settings }

struct MainTabView: View {
    let userId: UUID
    /// Plan 15 ("Instant library"): the signed-in user's library, owned at app scope
    /// (`LibraryStoreProvider`) and kept current HERE — refreshed at sign-in and on foreground
    /// (30 s staleness rule), live through the realtime feed, first-page heroes prefetched — so the
    /// View tab is ready before it is ever tapped.
    let store: ItemStore

    // Plan 2: the app opens ready to capture.
    @State private var selection: MainTab

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.displayScale) private var displayScale

    init(userId: UUID, store: ItemStore) {
        self.userId = userId
        self.store = store
        // Test/verification hook (same family as `--uitest-reset-auth`): lets a headless run
        // land on a specific tab without scripting taps through the simulator window.
        let args = ProcessInfo.processInfo.arguments
        let initial: MainTab = if args.contains("--uitest-tab-view") { .view }
            else if args.contains("--uitest-tab-ask") { .ask }
            else if args.contains("--uitest-tab-settings") { .settings }
            else { .add }
        _selection = State(initialValue: initial)
        // Plan 15 (H5): detail-sheet edits the server hasn't confirmed yet (`PendingEdits`) are
        // shown over the library's rows and sent before every refresh fetches — sign-in/launch,
        // foreground, View-tab appear, pull-to-refresh. Done here, before any child's `.task`
        // can refresh; `store` is per signed-in user, so this runs once per session.
        if store.pendingEdits == nil {
            let pendingEdits = PendingEdits.shared(for: userId)
            let editor = DetailEditorFactory.make()
            store.installPendingEdits(pendingEdits) { apply in
                await pendingEdits.flush(editor: editor, apply: apply)
            }
        }
    }

    var body: some View {
        TabView(selection: $selection) {
            CaptureComposerView(userId: userId, switchToView: { selection = .view })
                // The other tabs get the tab bar's hairline for free because their scrollable
                // content extends under the bar; Add has no scroll view, so without this the
                // bar renders transparent and the separator line vanishes on this tab only.
                .toolbarBackground(.visible, for: .tabBar)
                .tabItem { Label("Add", systemImage: "plus.circle.fill") }
                .tag(MainTab.add)
            AskView(userId: userId)
                .tabItem { Label("Ask", systemImage: "bubble.left.and.text.bubble.right") }
                .tag(MainTab.ask)
            LibraryView(store: store)
                .tabItem { Label("View", systemImage: "square.grid.2x2") }
                .tag(MainTab.view)
            SettingsView(userId: userId)
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(MainTab.settings)
        }
        // AccentColor is filled with DESIGN.md violet600, but SwiftUI controls (tab bar
        // selection, back chevrons, cursors) read `.tint` at the view hierarchy's root before
        // they fall back to the asset catalog's global accent in some contexts — set both so
        // there's no gap between plain SwiftUI chrome and UIKit-bridged chrome (e.g. the
        // navigation bar's back button).
        .tint(StashColor.violet600)
        // Sign-in / cold launch: the cached page (if any) is already on screen; fetch page 1 now,
        // while the user is still on the Add tab.
        .task { await store.refreshIfStale() }
        // App-scope incremental realtime (insert/update → re-read just those rows) plus every
        // capture this app saves (`.stashItemCaptured`), shown at once. Cancelled with this view
        // on sign-out.
        .task { await store.runLiveUpdates(changes: RealtimeObserver()) }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await store.refreshIfStale() }
        }
        // Warm the first page's heroes (a cached page at launch, then after every refresh) so the
        // View tab draws real images on its first frame.
        .onAppear { prefetchFirstPageHeroes() }
        .onChange(of: store.refreshCount) { _, _ in prefetchFirstPageHeroes() }
    }

    /// The first 10 cards' hero images, requested exactly as `CardHero` will request them.
    private func prefetchFirstPageHeroes() {
        let cardWidth = CardHeroSizing.cardWidth(regularWidth: horizontalSizeClass == .regular)
        let requests = store.items.prefix(10).compactMap {
            CardHeroSizing.request(for: $0, cardWidth: cardWidth, scale: displayScale)
        }
        ImagePipeline.shared.prefetch(requests)
    }
}
