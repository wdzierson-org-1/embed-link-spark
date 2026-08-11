import SwiftUI

enum MainTab: Hashable { case add, ask, view, settings }

struct MainTabView: View {
    let userId: UUID

    // Plan 2: the app opens ready to capture. MainTabView holds no store of its own — a
    // successful capture reaches the View tab via its existing realtime subscription, not via
    // a value passed down from here (see CaptureViewModel's "Reconciliation note").
    @State private var selection: MainTab = .add

    var body: some View {
        TabView(selection: $selection) {
            CaptureComposerView(userId: userId, switchToView: { selection = .view })
                .tabItem { Label("Add", systemImage: "plus.circle.fill") }
                .tag(MainTab.add)
            PlaceholderPane(title: "Ask", note: "Ask Stash arrives in plan 4")
                .tabItem { Label("Ask", systemImage: "bubble.left.and.text.bubble.right") }
                .tag(MainTab.ask)
            LibraryView(userId: userId)
                .tabItem { Label("View", systemImage: "square.grid.2x2") }
                .tag(MainTab.view)
            PlaceholderPane(title: "Settings", note: "Settings arrive in plan 5")
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(MainTab.settings)
        }
    }
}

struct PlaceholderPane: View {
    let title: String
    let note: String
    var body: some View {
        VStack(spacing: 8) {
            Text(title).font(.title2.bold())
            Text(note).foregroundStyle(.secondary)
        }
    }
}
