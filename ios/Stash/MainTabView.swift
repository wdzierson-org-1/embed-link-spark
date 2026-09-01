import SwiftUI

enum MainTab: Hashable { case add, ask, view, settings }

struct MainTabView: View {
    let userId: UUID

    // Plan 2: the app opens ready to capture. MainTabView holds no store of its own — a
    // successful capture reaches the View tab via its existing realtime subscription, not via
    // a value passed down from here (see CaptureViewModel's "Reconciliation note").
    @State private var selection: MainTab

    init(userId: UUID) {
        self.userId = userId
        // Test/verification hook (same family as `--uitest-reset-auth`): lets a headless run
        // land on a specific tab without scripting taps through the simulator window.
        let args = ProcessInfo.processInfo.arguments
        let initial: MainTab = if args.contains("--uitest-tab-view") { .view }
            else if args.contains("--uitest-tab-ask") { .ask }
            else if args.contains("--uitest-tab-settings") { .settings }
            else { .add }
        _selection = State(initialValue: initial)
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
            LibraryView(userId: userId)
                .tabItem { Label("View", systemImage: "square.grid.2x2") }
                .tag(MainTab.view)
            SettingsView(userId: userId)
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(MainTab.settings)
        }
    }
}
