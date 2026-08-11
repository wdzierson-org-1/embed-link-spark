import SwiftUI
import StashKit

/// Toolbar for `LibraryView`: item count, tag-filter button (badge when active), and an
/// avatar menu holding Sign Out.
struct LibraryToolbarContent: ToolbarContent {
    let store: ItemStore
    @Binding var showTagFilter: Bool

    @Environment(SessionStore.self) private var session

    var body: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Text(store.items.count == 1 ? "1 item" : "\(store.items.count) items")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("library.itemCount")
        }
        ToolbarItem(placement: .navigationBarTrailing) {
            Button { showTagFilter = true } label: {
                Image(systemName: "tag")
            }
            .overlay(alignment: .topTrailing) {
                if !store.selectedTagIds.isEmpty {
                    Circle().fill(.red).frame(width: 8, height: 8).offset(x: 4, y: -4)
                }
            }
            .accessibilityIdentifier("library.tagFilterButton")
        }
        ToolbarItem(placement: .navigationBarTrailing) {
            Menu {
                Button("Sign Out", role: .destructive) {
                    Task { await session.signOut() }
                }
                .accessibilityIdentifier("library.signOut")
            } label: {
                Image(systemName: "person.crop.circle")
            }
            .accessibilityIdentifier("library.menu")
        }
    }
}
