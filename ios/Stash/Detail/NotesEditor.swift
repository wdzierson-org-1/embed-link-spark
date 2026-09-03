import SwiftUI
import StashKit

/// Modern inline notes editor for the detail sheet's Notes tab (Plan 8 Task 5), replacing
/// `NotesAppendComposer`. Borderless, auto-growing, on `wash` fill (radius 12) — no separate Save
/// button; autosaves 600ms after the last keystroke through the same `SaveStatus` the title/
/// description fields drive, so the footer reads "Saving…"/"Changes saved automatically" for
/// notes edits too (`ItemDetailView.saveChangedFields` doesn't cover `content` — it's explicitly
/// excluded from `changedFields`'s diff, per that function's own doc comment — so this view saves
/// directly through `editor.save`, same shape as `ItemDetailView`'s own debounced field paths).
///
/// Two modes, chosen by whether `item.content` parses as TipTap JSON — the same `{"type":"doc"`
/// prefix check `renderTipTap`/`appendNoteParagraph` already use inline (StashKit exposes no
/// shared `isTipTapJSON` helper, so `isTipTapJSON(_:)` below mirrors their check rather than
/// adding one to StashKit just for a boolean this task doesn't otherwise need there):
///
/// - **Plain-text notes**: the field IS the note — initialized with the full existing `content`,
///   fully editable, autosaved whole-field on debounce (same "replace the whole column" contract
///   as title/description, just its own field and its own slower debounce).
/// - **Rich notes (TipTap JSON)**: the existing document renders read-only above via
///   `renderTipTap` (this view now owns that job — previously `ItemDetailContent.notesBlock`,
///   deleted in this task), and the field is a perpetually-empty append draft: on debounce OR
///   blur, whatever's typed gets wrapped as a new paragraph and folded onto the existing document
///   via `appendNoteParagraph`, then the field clears — plan-2 safety preserved, the TipTap JSON
///   itself never round-trips through this plain-text field.
struct NotesEditor: View {
    let item: Item
    let editor: ItemEditor
    @Binding var saveStatus: SaveStatus
    /// Backs the `TextEditor`'s `.focused` — owned by `ItemDetailView` (its `notesFocused`), not
    /// declared as a local `@FocusState` here: a `.toolbar(placement: .keyboard)` attached at
    /// THIS view's own depth (several levels inside the sheet's `ScrollView`/`ItemDetailContent`'s
    /// tab-switch `@ViewBuilder`) never actually registered its accessory — confirmed live,
    /// `detail.dismissKeyboard` never appeared even right after focusing, unlike the identical
    /// pattern on `CaptureComposerView`'s own top-level body. The toolbar itself now lives on
    /// `ItemDetailView`, so only the focus BINDING is threaded down here.
    var isFocused: FocusState<Bool>.Binding
    var onSaved: (Item) -> Void

    @State private var draft: String
    @State private var savedDraft: String
    @State private var debouncer = Debouncer(interval: .milliseconds(600))

    private var isRich: Bool { Self.isTipTapJSON(item.content) }

    init(item: Item, editor: ItemEditor, saveStatus: Binding<SaveStatus>, isFocused: FocusState<Bool>.Binding,
         onSaved: @escaping (Item) -> Void) {
        self.item = item
        self.editor = editor
        self._saveStatus = saveStatus
        self.isFocused = isFocused
        self.onSaved = onSaved
        // A rich note's draft always starts empty (append-only); a plain note's draft starts as
        // the full existing text. Only takes effect the first time this view's identity is
        // established (SwiftUI preserves @State storage across re-renders thereafter) — same
        // convention `ItemDetailView`'s own `_item = State(initialValue: item)` documents.
        let initialDraft = Self.isTipTapJSON(item.content) ? "" : (item.content ?? "")
        _draft = State(initialValue: initialDraft)
        _savedDraft = State(initialValue: initialDraft)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if isRich, let content = item.content, !content.isEmpty {
                Text(renderTipTap(content))
                    .font(StashType.body())
                    .foregroundStyle(StashColor.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("detail.notesText")
            }

            field

            Text(isRich ? "Adding to a rich note" : "Editing note")
                .font(StashType.meta())
                .foregroundStyle(StashColor.faint)
                .accessibilityIdentifier("detail.notes.hint")
        }
        // Rich mode's append is a discrete, deliberate action (plan-2 safety) — flush it the
        // moment focus leaves, not just on the debounce, so tapping straight to Done right after
        // typing an append can't lose it to a cancelled debounce. Plain mode already gets an
        // equivalent safety net for free: its whole-field save is idempotent and re-fires on the
        // next edit regardless, same as title/description's debounce-only contract.
        .onChange(of: isFocused.wrappedValue) { wasFocused, focused in
            if wasFocused, !focused, isRich { Task { await flush() } }
        }
    }

    private var field: some View {
        ZStack(alignment: .topLeading) {
            if draft.isEmpty {
                Text("Add a note…")
                    .font(StashType.body())
                    .foregroundStyle(StashColor.faint)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 10)
                    .allowsHitTesting(false)
            }
            // Bounded-but-generous auto-grow (80–220pt) rather than a true unbounded
            // `fixedSize(vertical: true)` + `scrollDisabled` grow-to-fit — the latter forces a
            // SwiftUI/UIKit relayout of the TextEditor's own intrinsic size on every keystroke; a
            // fixed height range keeps the TextEditor's own intrinsic size constant while typing —
            // it still visually grows the sheet's outer ScrollView content up to `maxHeight`, then
            // scrolls internally beyond that, same shape "auto-growing" reads as in practice.
            TextEditor(text: $draft)
                .font(StashType.body())
                .foregroundStyle(StashColor.ink)
                .scrollContentBackground(.hidden)
                .autocorrectionDisabled()
                .focused(isFocused)
                .frame(minHeight: 80, maxHeight: 220)
                .padding(.horizontal, 7)
                .padding(.vertical, 6)
                .onChange(of: draft) { _, _ in scheduleSave() }
        }
        .background(StashColor.wash, in: RoundedRectangle(cornerRadius: StashRadius.input, style: .continuous))
        .accessibilityIdentifier("detail.notes.editor")
    }

    private func scheduleSave() {
        Task { await debouncer.call { await flush() } }
    }

    /// Same `@MainActor` reasoning as `ItemDetailView.saveChangedFields`: reached through
    /// `Debouncer`, its own (non-Main) actor, so this needs the explicit hop back before touching
    /// `@State`/the `saveStatus` binding.
    @MainActor
    private func flush() async {
        guard draft != savedDraft else { return }
        let typed = draft
        let newContent: String
        if isRich {
            let note = typed.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !note.isEmpty else { return }
            newContent = appendNoteParagraph(to: item.content, note: note)
        } else {
            newContent = typed
        }
        saveStatus = .saving
        do {
            let merged = try await editor.save(itemId: item.id, patch: ItemPatch(content: newContent))
            if isRich {
                draft = ""
                savedDraft = ""
            } else {
                savedDraft = typed
            }
            onSaved(merged)
            saveStatus = .saved
        } catch {
            saveStatus = .idle
        }
    }

    /// Mirrors the inline `{"type":"doc"` detection `renderTipTap`/`appendNoteParagraph` already
    /// carry (StashKit, `TipTapRenderer.swift`/`TipTapAppend.swift`) — kept local rather than
    /// promoted to a shared StashKit helper since this task doesn't otherwise touch that package.
    private static func isTipTapJSON(_ raw: String?) -> Bool {
        guard let raw, raw.hasPrefix("{"),
              let data = raw.data(using: .utf8),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return false }
        return root["type"] as? String == "doc"
    }
}
