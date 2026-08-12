import SwiftUI
import StashKit

/// Toolbar for `LibraryView`: item count and a tag-filter button (badge when active). Sign Out
/// used to live here behind an avatar menu — Task 7 relocated it to the Settings tab (with a
/// confirm dialog), so this toolbar no longer needs a `SessionStore` reference at all.
struct LibraryToolbarContent: ToolbarContent {
    let store: ItemStore
    @Binding var showTagFilter: Bool

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
    }
}
