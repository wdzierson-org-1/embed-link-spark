import SwiftUI
import StashKit

/// Tags manager (Task 7): list with usage counts, swipe-to-delete with a confirm dialog whose
/// copy mirrors `TagsSettings.tsx` (`handleDeleteTag`, :80-120) — delete-only, no rename/merge.
/// Deletion cascades `item_tags` first, then the tag row itself, in the web's own order
/// (:87-100): `from("item_tags").delete().eq("tag_id", …)` then `from("tags").delete().eq("id", …)`.
struct TagsSection: View {
    let userId: UUID

    @State private var tags: [StashTag] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var deleteTarget: StashTag?

    var body: some View {
        Section("Tags") {
            if isLoading {
                ProgressView()
            } else if tags.isEmpty {
                Text("You haven't created any tags yet.")
                    .font(.footnote)
                    .foregroundStyle(StashColor.muted)
            } else {
                ForEach(tags) { tag in
                    row(tag)
                }
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("settings.tags.error")
            }
        }
        .task { await load() }
        .confirmationDialog(
            "Delete the tag \"\(deleteTarget?.name ?? "")\"?",
            isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete Tag", role: .destructive) {
                if let target = deleteTarget { Task { await delete(target) } }
            }
            Button("Cancel", role: .cancel) { deleteTarget = nil }
        } message: {
            Text(deleteConfirmMessage)
        }
    }

    private var deleteConfirmMessage: String {
        guard let deleteTarget else { return "" }
        return "This tag will be removed from \(deleteTarget.usageCount) item(s). This action cannot be undone."
    }

    private func row(_ tag: StashTag) -> some View {
        HStack {
            Text(tag.name)
            Spacer()
            Text("\(tag.usageCount)")
                .font(.caption)
                .foregroundStyle(StashColor.muted)
        }
        .accessibilityIdentifier("settings.tags.row.\(tag.name)")
        .swipeActions {
            Button(role: .destructive) {
                deleteTarget = tag
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .accessibilityIdentifier("settings.tags.delete.\(tag.name)")
        }
    }

    // MARK: - Network

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            tags = try await fetchTags(userId: userId)
        } catch {
            errorMessage = "Couldn't load tags."
        }
    }

    private func delete(_ tag: StashTag) async {
        deleteTarget = nil
        errorMessage = nil
        do {
            try await StashClient.shared.from("item_tags").delete()
                .eq("tag_id", value: tag.id.uuidString).execute()
            try await StashClient.shared.from("tags").delete()
                .eq("id", value: tag.id.uuidString).execute()
            tags.removeAll { $0.id == tag.id }
        } catch {
            errorMessage = "Couldn't delete that tag — try again."
        }
    }
}
