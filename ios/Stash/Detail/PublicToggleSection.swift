import SwiftUI
import StashKit

/// Public/private toggle plus its sticky-note lifecycle (Task 9), porting
/// `EditItemDetailsTab.tsx`'s "Public Feed Toggle" + `EditItemSupplementalNoteSection`.
///
/// Sharing (`false → true`) applies immediately — matching the web's `handlePublicToggle`
/// (`onSave(..., { showSuccessToast: true, refreshItems: true })`, not debounced, unlike the
/// sticky-note text itself). Un-sharing (`true → false`) while a sticky note is present asks for
/// confirmation first (`useEditItemSheet.ts:133`, `EditItemDetailsTab.tsx:156-165`): sticky notes
/// only make sense on a shared item, so turning sharing off deletes the note in the same PATCH —
/// worth confirming since it's destructive to content the user typed.
///
/// Owns its own immediate save call against `editor` (same shape `NotesAppendComposer`
/// established for a subview that drives its own atomic action), separate from
/// `ItemDetailView`'s debounced field-autosave `saveStatus` — the sticky-note *text* itself still
/// rides that shared debounced path via the `supplementalNote` binding passed in.
struct PublicToggleSection: View {
    let item: Item
    let editor: ItemEditor
    @Binding var supplementalNote: String
    var onSaved: (Item) -> Void

    @State private var isToggling = false
    @State private var showUnshareConfirm = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            toggleRow
            if item.isPublic {
                stickyNoteField
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("detail.public.error")
            }
        }
        .confirmationDialog("Make private? The sticky note will be removed.",
                             isPresented: $showUnshareConfirm, titleVisibility: .visible) {
            Button("Make Private", role: .destructive) { Task { await apply(isPublic: false) } }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var toggleRow: some View {
        Toggle(isOn: Binding(
            get: { item.isPublic },
            set: { handleToggle($0) }
        )) {
            Label(item.isPublic ? "Public Feed" : "Private", systemImage: item.isPublic ? "globe" : "lock")
                .font(.subheadline.weight(.medium))
        }
        .disabled(isToggling)
        .accessibilityIdentifier("detail.public.toggle")
    }

    private var stickyNoteField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Sticky note")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField("Add a quick note…", text: $supplementalNote, axis: .vertical)
                .textFieldStyle(.plain)
                .padding(10)
                .background(Color.yellow.opacity(0.2), in: RoundedRectangle(cornerRadius: 10))
                .accessibilityIdentifier("detail.public.sticky")
            Text("This note appears as a yellow sticky note on the public feed card.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Actions

    /// Turning ON is always a direct save; turning OFF only interrupts for confirmation when
    /// there's an actual sticky note to lose (empty/nil note → straight through, no dialog).
    private func handleToggle(_ newValue: Bool) {
        if !newValue, let note = item.supplementalNote, !note.isEmpty {
            showUnshareConfirm = true
            return
        }
        Task { await apply(isPublic: newValue) }
    }

    private func apply(isPublic: Bool) async {
        isToggling = true
        errorMessage = nil
        defer { isToggling = false }
        let patch = editor.togglePublic(item: item, to: isPublic)
        do {
            let merged = try await editor.save(itemId: item.id, patch: patch)
            onSaved(merged)
        } catch {
            errorMessage = "Couldn't update — try again."
        }
    }
}
