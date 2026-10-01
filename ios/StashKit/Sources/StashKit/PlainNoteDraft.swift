import Foundation

/// A PLAIN note's draft in the detail sheet (not TipTap: the field is the whole note, saved whole)
/// measured against what it was last saved as AND the item's durable edit queue (plan 16, Task 4c)
/// — the notes editor's own counterpart to `DetailFieldEdits.needsSave`.
///
/// - `draft`: the field as the user left it (`NotesEditorModel.draft`).
/// - `saved`: `NotesEditorModel.savedDraft` — the seed (the queue overlay, so a sheet opened on a
///   queued, undelivered note starts with that note here, though the server hasn't confirmed it),
///   then each save that landed.
/// - `queued`: the `content` the queue still holds for the item — a save in flight, or one that
///   failed and waits for the next flush.
///
/// Comparing `draft` with `saved` alone can't tell "never typed" from "typed, sent, then cleared
/// again": a plain note "" → "abc" (sent) → cleared looked like no edit, so neither the debounced
/// save nor the close's journal sent the clear, and "abc" landed for good. The draft needs saving
/// when it differs from `saved` OR from a value still queued for it; a clear then supersedes "abc"
/// through the queue's latest-wins rule.
///
/// Rich (TipTap) notes don't use this: their draft is an append-only buffer — a paragraph that was
/// sent can't be taken back by clearing the draft, and it leaves the field once it lands.
public struct PlainNoteDraft: Equatable, Sendable {
    public var draft: String
    public var saved: String
    public var queued: String?

    public init(draft: String, saved: String, queued: String?) {
        self.draft = draft
        self.saved = saved
        self.queued = queued
    }

    /// Whether the draft must be (re)sent: it differs from what the server confirmed, or from a
    /// value still queued for the note.
    public var needsSave: Bool {
        draft != saved || queued.map { $0 != draft } ?? false
    }
}
