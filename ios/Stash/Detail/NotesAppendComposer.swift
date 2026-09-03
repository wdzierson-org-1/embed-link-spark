import SwiftUI
import StashKit

/// Append-only notes composer: the iOS build deliberately doesn't ship a rich-text editor for
/// `content` (plan-2 spec — "append-only per spec"). A typed note gets wrapped as its own
/// paragraph and tacked onto whatever's already there via `appendNoteParagraph`, then saved
/// immediately — unlike title/description there's no "in-progress draft" worth debouncing here,
/// each tap of Add is its own explicit, atomic action.
struct NotesAppendComposer: View {
    let item: Item
    let editor: ItemEditor
    var onSaved: (Item) -> Void

    @State private var draft = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var trimmedDraft: String { draft.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Add to Notes")
                .font(StashType.bodySemibold(12))
                .foregroundStyle(StashColor.muted)
            HStack(alignment: .top, spacing: 8) {
                TextField("Add a note…", text: $draft, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("detail.notesComposer.field")
                Button {
                    Task { await append() }
                } label: {
                    if isSaving {
                        ProgressView()
                    } else {
                        Text("Add")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSaving || trimmedDraft.isEmpty)
                .accessibilityIdentifier("detail.notesComposer.add")
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(StashType.meta())
                    .foregroundStyle(StashColor.destructive)
                    .accessibilityIdentifier("detail.notesComposer.error")
            }
        }
    }

    private func append() async {
        let note = trimmedDraft
        guard !note.isEmpty else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        let newContent = appendNoteParagraph(to: item.content, note: note)
        do {
            let merged = try await editor.save(itemId: item.id, patch: ItemPatch(content: newContent))
            draft = ""
            onSaved(merged)
        } catch {
            errorMessage = "Couldn't save — try again."
        }
    }
}
