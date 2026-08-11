import SwiftUI
import StashKit

/// Read-only detail sheet presented from a Library card tap: optional hero image (image
/// items only), header, an "Open Link" button for link items, and the segmented content
/// section. On appear, fetches the full row (adding `page_body`, which the grid's list query
/// omits) for types whose tabs need it, then merges it back into `store` so the list stays
/// current too. No editing, playback, or delete in this build — those ship in later plans.
struct ItemDetailView: View {
    @State private var item: Item
    let store: ItemStore

    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: ContentTabKey
    @State private var isLoadingDetail = false

    init(item: Item, store: ItemStore) {
        _item = State(initialValue: item)
        self.store = store
        _selectedTab = State(initialValue: contentTabsConfig(for: item.type).defaultTab)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if item.type == .image, let url = item.thumbnailURL {
                        heroImage(url)
                    }
                    ItemDetailHeader(item: item)
                    if item.type == .link, let urlString = item.url, let url = URL(string: urlString) {
                        Link(destination: url) {
                            Label("Open Link", systemImage: "arrow.up.right.square")
                        }
                        .accessibilityIdentifier("detail.openLink")
                    }
                    ItemDetailContent(item: item, selectedTab: $selectedTab, isLoadingDetail: isLoadingDetail)
                }
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.accessibilityIdentifier("detail.done")
                }
            }
        }
        .task { await loadDetailIfNeeded() }
    }

    private func heroImage(_ url: URL) -> some View {
        AsyncImage(url: url) { phase in
            if case .success(let image) = phase {
                image.resizable().aspectRatio(contentMode: .fit)
            } else {
                Color(.tertiarySystemFill).aspectRatio(4 / 3, contentMode: .fit)
            }
        }
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .accessibilityIdentifier("detail.heroImage")
    }

    /// list queries omit page_body (can be tens of KB/item); fetch the full row here instead.
    private func loadDetailIfNeeded() async {
        guard needsSourceContent(item.type) else { return }
        isLoadingDetail = true
        defer { isLoadingDetail = false }
        if let detail = try? await SupabaseItemsFetcher().fetchDetail(id: item.id) {
            item = detail
            store.applyDetail(detail)
        }
    }
}
