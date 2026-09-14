import SwiftUI
import StashKit

/// Compact editor sheet for a card's note (`CardNoteView`'s tap target) — DESIGN.md §Components
/// "Card note" (2026-09-13 housekeeping mirror, plan 14). Reuses `NotesEditorModel`
/// (`ios/Stash/Detail/NotesEditor.swift`) exactly the way the detail sheet's Notes tab does: a
/// rich (TipTap JSON) `content` renders read-only above via `renderTipTap`, and the field itself
/// is a perpetually-empty append draft that gets wrapped as a new paragraph and folded onto the
/// existing document on Save — the same "never flatten rich content to plain text" contract, just
/// with an explicit Save/Cancel pair instead of autosave-on-blur (the handoff doc's own brief:
/// "Save/Cancel should be explicit; native Return adds a line").
///
/// `.medium` detent, presented from `CardNoteView.sheet`. `onFinished(true)` fires only on a
/// genuinely confirmed save (never on Cancel or a no-op Save-with-nothing-changed) — the caller
/// uses that to drive the card's own wash/"Saved" acknowledgment; a failed save keeps the sheet
/// open with the draft intact and an inline error, matching every other save path in this app.
struct CardNoteEditorSheet: View {
    let item: Item
    let store: ItemStore
    var onFinished: (_ saved: Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var model: NotesEditorModel
    @State private var isSaving = false
    @State private var errorMessage: String?
    @FocusState private var isFocused: Bool

    /// Plan 14 fix wave: mirrors `NotesEditor`'s own halved footprint (44–110pt, `@ScaledMetric`
    /// relative to `.body`) exactly — this sheet can't embed `NotesEditor` itself without also
    /// adopting its autosave-on-blur/`DetailField` focus-enum wiring (owned by `ItemDetailView`, a
    /// Detail file explicitly out of scope this round), but there's no reason its field should keep
    /// its own pre-existing, larger 120–220pt frame once the detail sheet's equivalent field has
    /// been halved — same bounds, same Dynamic-Type growth, just still driven by this sheet's own
    /// explicit Save/Cancel rather than a debounce.
    @ScaledMetric(relativeTo: .body) private var minEditorHeight: CGFloat = 44
    @ScaledMetric(relativeTo: .body) private var maxEditorHeight: CGFloat = 110

    init(item: Item, store: ItemStore, onFinished: @escaping (_ saved: Bool) -> Void) {
        self.item = item
        self.store = store
        self.onFinished = onFinished
        _model = State(initialValue: NotesEditorModel(item: item))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if model.isRich, let content = item.content, !content.isEmpty {
                        Text(renderTipTap(content))
                            .font(StashType.body())
                            .foregroundStyle(StashColor.ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityIdentifier("cardNote.existing")
                    }
                    editorField
                }
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(StashType.meta())
                    .foregroundStyle(StashColor.destructive)
                    .accessibilityIdentifier("cardNote.error")
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 16)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .onAppear { isFocused = true }
    }

    private var header: some View {
        HStack {
            Text("Note")
                .font(StashType.bodySemibold(15))
                .foregroundStyle(StashColor.ink)
            Spacer()
            Button("Cancel") {
                onFinished(false)
                dismiss()
            }
            .font(StashType.bodyMedium())
            .foregroundStyle(StashColor.muted)
            .disabled(isSaving)
            .accessibilityIdentifier("cardNote.cancel")

            Button(isSaving ? "Saving…" : "Save") { Task { await save() } }
                .font(StashType.bodyMedium())
                .foregroundStyle(StashColor.violet600)
                .disabled(isSaving)
                .accessibilityIdentifier("cardNote.save")
        }
    }

    /// Same field shape/tokens as `NotesEditor.field` (detail sheet) minus its "Adds when you tap
    /// Done…" hint — the polish round's own brief ("without adding keyboard instructions to the
    /// touch UI") applies here, and this sheet already carries the instruction implicitly via its
    /// own explicit Save/Cancel buttons.
    private var editorField: some View {
        // Rich mode is an append-only draft onto an existing document (never the note itself, the
        // way plain mode's field is) — "Add to note…" says so; plain mode's field IS the whole
        // note, so it keeps the detail sheet's own "Add a note…" copy.
        let placeholder = model.isRich ? "Add to note…" : "Add a note…"
        return ZStack(alignment: .topLeading) {
            if model.draft.isEmpty {
                Text(placeholder)
                    .font(StashType.body())
                    .foregroundStyle(StashColor.faint)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 10)
                    .allowsHitTesting(false)
            }
            // Same bounded-but-generous auto-grow shape as `NotesEditor.field` (its own doc comment
            // has the full rationale): a fixed height range keeps the `TextEditor`'s intrinsic size
            // constant while typing, growing this sheet's outer `ScrollView` content up to
            // `maxEditorHeight`, then scrolling internally beyond that — the keyboard never moves.
            TextEditor(text: $model.draft)
                .font(StashType.body())
                .foregroundStyle(StashColor.ink)
                .scrollContentBackground(.hidden)
                .autocorrectionDisabled()
                .focused($isFocused)
                .frame(minHeight: minEditorHeight, maxHeight: maxEditorHeight)
                .padding(.horizontal, 6)
                .padding(.vertical, 6)
                .disabled(isSaving)
        }
        .background(StashColor.violet300.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: StashRadius.input, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StashRadius.input, style: .continuous)
                .strokeBorder(isFocused ? StashColor.violet300 : Color.clear, lineWidth: 1)
        )
        .accessibilityIdentifier("cardNote.editor")
        .accessibilityLabel("Card note")
    }

    /// Mirrors `ItemDetailView.flushNotes`'s rich/plain split exactly (see that method's own doc
    /// comment for the full rationale) — this sheet just triggers it explicitly on Save instead of
    /// on blur/debounce, and keeps the draft + shows an inline error on failure rather than
    /// silently retrying later.
    @MainActor
    private func save() async {
        guard model.draft != model.savedDraft else {
            // Unchanged Save just closes (handoff doc) — nothing to persist, nothing to
            // acknowledge.
            onFinished(false)
            dismiss()
            return
        }
        let typed = model.draft
        let newContent: String
        if model.isRich {
            let note = typed.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !note.isEmpty else {
                onFinished(false)
                dismiss()
                return
            }
            newContent = appendNoteParagraph(to: item.content, note: note)
        } else {
            newContent = typed
        }

        isSaving = true
        errorMessage = nil
        let editor = ItemEditor(patcher: SupabaseItemPatcher(),
                                 refresher: EmbeddingRefresher(syncer: SupabaseEmbeddingSyncer()))
        do {
            let merged = try await editor.save(itemId: item.id, patch: ItemPatch(content: newContent))
            store.applyDetail(merged)
            isSaving = false
            onFinished(true)
            dismiss()
        } catch {
            // Failure keeps the draft in the sheet and shows the error inline (handoff doc) —
            // `model.draft` is never touched on this path, so nothing typed is lost.
            isSaving = false
            errorMessage = "Couldn't save your note. Your changes are still here. Try again."
        }
    }
}
