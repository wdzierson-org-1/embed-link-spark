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

/// A RICH note's notes box (plan 16, Task 4e fix round 2): an append-only draft. Each Done saves
/// the box's text as a new paragraph of the document, and the text leaves the box once that save
/// is saved (`ItemDetailView.flushNotes`; `NotesEditorModel` holds the box). Saves can overlap:
/// Done with "abc" on a slow link, " def" typed, Done again — the second save carries "abc def",
/// built on the same document. When "abc" lands it leaves the box, so "def" is left; when "abc
/// def" lands, removing the whole "abc def" no longer matched the box, so "def" stayed, and the
/// next Done appended it a second time (4e re-review).
public enum RichNoteBox {
    /// The box once a save of `typed` — the box's text when that save took it — is saved: what of
    /// `typed` is still at the box's start leaves it, as `NotesEditorModel.removeSavedPrefix` takes a
    /// saved prefix off (with the whitespace after it); anything typed after stays. `removedSince`
    /// is what earlier saves' landings took off the box's start after this one took its text — it
    /// is gone already. Returns the box and what this landing took off it.
    public static func landing(of typed: String, removedSince: String, box: String) -> (box: String, removed: String) {
        var saved = typed
        if !removedSince.isEmpty, typed.hasPrefix(removedSince) {
            saved = String(typed.dropFirst(removedSince.count).drop(while: \.isWhitespace))
        }
        let after: String
        if saved.isEmpty {
            after = box
        } else if box == saved {
            after = ""
        } else if box.hasPrefix(saved) {
            after = String(box.dropFirst(saved.count).drop(while: \.isWhitespace))
        } else {
            after = box   // the box no longer starts with it (edited since): left as it is
        }
        return (after, String(box.dropLast(after.count)))
    }
}
