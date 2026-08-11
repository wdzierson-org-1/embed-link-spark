import SwiftUI
import StashKit

/// Multi-select tag picker. Writes straight into the shared `ItemStore.selectedTagIds`
/// (a reference type) so `LibraryView` observes the change and re-fetches.
struct TagFilterSheet: View {
    let userId: UUID
    let store: ItemStore

    @Environment(\.dismiss) private var dismiss
    @State private var tags: [StashTag] = []
    @State private var isLoading = true
    @State private var loadError: String?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                } else if let loadError {
                    Text(loadError).foregroundStyle(.secondary)
                } else if tags.isEmpty {
                    Text("No tags yet").foregroundStyle(.secondary)
                } else {
                    tagList
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Filter by Tag")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Clear") { store.selectedTagIds = [] }
                        .disabled(store.selectedTagIds.isEmpty)
                        .accessibilityIdentifier("tagfilter.clear")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("tagfilter.done")
                }
            }
        }
        .task { await load() }
    }

    private var tagList: some View {
        List(tags) { tag in
            Button {
                toggle(tag)
            } label: {
                HStack {
                    Text(tag.name).foregroundStyle(.primary)
                    Spacer()
                    Text("\(tag.usageCount)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if store.selectedTagIds.contains(tag.id) {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.tint)
                    }
                }
            }
            .accessibilityIdentifier("tagfilter.tag.\(tag.name)")
        }
        .accessibilityIdentifier("library.tagList")
    }

    private func toggle(_ tag: StashTag) {
        if let idx = store.selectedTagIds.firstIndex(of: tag.id) {
            store.selectedTagIds.remove(at: idx)
        } else {
            store.selectedTagIds.append(tag.id)
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            tags = try await fetchTags(userId: userId)
        } catch {
            loadError = "Couldn't load tags."
        }
    }
}
