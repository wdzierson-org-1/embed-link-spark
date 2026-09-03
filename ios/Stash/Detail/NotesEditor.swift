import SwiftUI
import Observation
import StashKit

/// Owns `NotesEditor`'s draft + debounce state (Plan 8 fix round 1, review finding #1) — hoisted
/// out of the view itself into a small `@Observable` reference type, owned by `ItemDetailView`
/// (`@State`, same one-per-sheet lifetime as `editor`), so the sheet can reach in and trigger an
/// explicit flush from its Done button and `onDisappear`: a SwiftUI `View` is a value type,
/// recreated on every render, so a parent has no way to call a method on a *specific* child view's
/// own local `@State` — hoisting the stateful behavior into a shared reference type both sides
/// read/write through is the standard SwiftUI fix for this.
///
/// Deliberately thin: draft state + the debounce timer alone. The actual save/generation-guard/
/// adopt logic lives on `ItemDetailView.flushNotes()` instead of here — it needs direct access to
/// `editor`/`saveGeneration`/`item.content`/`handleSaved`, none of which this model holds — and is
/// handed to this model as a plain closure (`perform`) at each call site.
@Observable
final class NotesEditorModel {
    var draft: String
    var savedDraft: String
    let isRich: Bool
    private var debouncer = Debouncer(interval: .milliseconds(600))

    init(item: Item) {
        self.isRich = Self.isTipTapJSON(item.content)
        // A rich note's draft always starts empty (append-only); a plain note's draft starts as
        // the full existing text. `isRich` itself is frozen here at construction, not recomputed
        // from `item.content` on every access — this model has the same one-per-sheet lifetime
        // `ItemDetailView.editor` does, so the mode is decided once, up front, and never flips
        // mid-session even if a later save round-trip changes the literal shape of `content`.
        let initial = isRich ? "" : (item.content ?? "")
        self.draft = initial
        self.savedDraft = initial
    }

    /// Debounced trigger — `perform` is `ItemDetailView.flushNotes()`, supplied fresh by
    /// `NotesEditor`'s `.onChange(of: model.draft)` on every keystroke.
    func scheduleSave(_ perform: @escaping () async -> Void) {
        Task { await debouncer.call { await perform() } }
    }

    /// Explicit, immediate flush (fix round 1) — the Done button / `onDisappear` path: cancels any
    /// pending debounce first so a fast "type then dismiss" sequence can't leave a stale debounced
    /// save racing this explicit one, then runs `perform` directly, with no 600ms wait. Both
    /// callers `await` this, so a dismiss genuinely waits for the save to land before the sheet
    /// closes — the exact gap that used to lose a note typed right before tapping Done.
    func flushNow(_ perform: @escaping () async -> Void) async {
        await debouncer.cancel()
        await perform()
    }

    /// Mirrors the inline `{"type":"doc"` detection `renderTipTap`/`appendNoteParagraph` already
    /// carry (StashKit, `TipTapRenderer.swift`/`TipTapAppend.swift`) — kept local rather than
    /// promoted to a shared StashKit helper.
    private static func isTipTapJSON(_ raw: String?) -> Bool {
        guard let raw, raw.hasPrefix("{"),
              let data = raw.data(using: .utf8),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return false }
        return root["type"] as? String == "doc"
    }
}

/// Modern inline notes editor for the detail sheet's Notes tab (Plan 8 Task 5). Borderless,
/// auto-growing, on `wash` fill (radius 12) — no separate Save button; autosaves 600ms after the
/// last keystroke through the same `SaveStatus` the title/description fields drive, so the footer
/// reads "Saving…"/"Changes saved automatically" for notes edits too. All the actual save/flush
/// mechanics live on `ItemDetailView`/`NotesEditorModel` (see their own doc comments) — this view
/// itself just renders `model.draft` and forwards keystroke/blur events to the closures it's
/// handed.
///
/// Two modes, chosen by whether `item.content` parses as TipTap JSON (`model.isRich`, frozen at
/// the model's construction):
///
/// - **Plain-text notes**: the field IS the note — initialized with the full existing `content`,
///   fully editable, autosaved whole-field on debounce (same "replace the whole column" contract
///   as title/description, just its own field and its own slower debounce).
/// - **Rich notes (TipTap JSON)**: the existing document renders read-only above via
///   `renderTipTap`, and the field is a perpetually-empty append draft: on debounce OR blur,
///   whatever's typed gets wrapped as a new paragraph and folded onto the existing document via
///   `appendNoteParagraph`, then the field clears — plan-2 safety preserved, the TipTap JSON
///   itself never round-trips through this plain-text field.
struct NotesEditor: View {
    let item: Item
    @Bindable var model: NotesEditorModel
    /// Backs the `TextEditor`'s `.focused` — owned by `ItemDetailView` (its `notesFocused`), not
    /// declared as a local `@FocusState` here: a `.toolbar(placement: .keyboard)` attached at THIS
    /// view's own depth never actually registered its accessory (confirmed live) — see
    /// `ItemDetailView`'s own doc comments for the full story. The toolbar lives there; only the
    /// focus BINDING is threaded down here.
    var isFocused: FocusState<Bool>.Binding
    var scheduleFlush: () -> Void
    var flushNow: () async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if model.isRich, let content = item.content, !content.isEmpty {
                Text(renderTipTap(content))
                    .font(StashType.body())
                    .foregroundStyle(StashColor.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("detail.notesText")
            }

            field

            Text(model.isRich ? "Adding to a rich note" : "Editing note")
                .font(StashType.meta())
                .foregroundStyle(StashColor.faint)
                .accessibilityIdentifier("detail.notes.hint")
        }
        // Fix round 1, review finding #1: flush on blur for BOTH modes now (previously rich-only)
        // — plain-mode notes were just as exposed as rich mode to "type then dismiss within the
        // 600ms debounce window" data loss. `ItemDetailView`'s Done button / `onDisappear` are the
        // other two flush points (`NotesEditorModel.flushNow`'s own doc comment).
        .onChange(of: isFocused.wrappedValue) { wasFocused, focused in
            if wasFocused, !focused { Task { await flushNow() } }
        }
    }

    private var field: some View {
        ZStack(alignment: .topLeading) {
            if model.draft.isEmpty {
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
            TextEditor(text: $model.draft)
                .font(StashType.body())
                .foregroundStyle(StashColor.ink)
                .scrollContentBackground(.hidden)
                .autocorrectionDisabled()
                .focused(isFocused)
                .frame(minHeight: 80, maxHeight: 220)
                .padding(.horizontal, 7)
                .padding(.vertical, 6)
                .onChange(of: model.draft) { _, _ in scheduleFlush() }
        }
        .background(StashColor.wash, in: RoundedRectangle(cornerRadius: StashRadius.input, style: .continuous))
        .accessibilityIdentifier("detail.notes.editor")
    }
}
