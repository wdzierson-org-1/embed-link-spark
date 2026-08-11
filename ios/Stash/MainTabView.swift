import SwiftUI

enum MainTab: Hashable { case add, ask, view, settings }

struct MainTabView: View {
    // Launch on View until the Add composer exists (plan 2 flips this to .add)
    @State private var selection: MainTab = .view

    var body: some View {
        TabView(selection: $selection) {
            PlaceholderPane(title: "Add", note: "Capture arrives in plan 2")
                .tabItem { Label("Add", systemImage: "plus.circle.fill") }
                .tag(MainTab.add)
            PlaceholderPane(title: "Ask", note: "Ask Stash arrives in plan 4")
                .tabItem { Label("Ask", systemImage: "bubble.left.and.text.bubble.right") }
                .tag(MainTab.ask)
            Text("View")   // replaced by LibraryView in Task 10
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
