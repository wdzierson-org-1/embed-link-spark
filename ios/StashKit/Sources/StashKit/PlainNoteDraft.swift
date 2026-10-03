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

extension RichNoteBox {
    /// A note document a detail sheet queued without seeing it land: `typed`, the box's text then,
    /// appended to the document the sheet showed, as `document`. Either the dismiss/background
    /// journal's draft, or a note save that failed: its write-ahead copy stays queued, and any later
    /// write of the item delivers it. `removedAt` is the ledger's `removed` when the text was taken.
    public struct QueuedDraft: Equatable, Sendable {
        public let typed: String
        public let document: String
        public let removedAt: String
    }

    /// What a detail sheet keeps beside a rich note's box (`ItemDetailView`'s `services.richNote`),
    /// so that each piece of typed text is in exactly one of the two places the next note is built
    /// from: the document the sheet shows, or the box.
    ///
    /// **The rule.** Text leaves the box when a save of it is saved (`saved`), or once the document
    /// the sheet SHOWS is one the sheet queued that text as (`reconcile`). The second covers every
    /// document the sheet sent without seeing it land, whatever delivers it and in whatever order:
    /// a flush (the sheet's own `setPublic` flush, the app's foreground refresh), or a realtime echo
    /// of a PATCH whose response was lost, even one that reached the sheet before the save reported
    /// its failure (`failed` checks the document already shown).
    ///
    /// - Batch B (4e re-review 2, New Breakage 1): a failed save's document wasn't kept. The sheet's
    ///   own flush delivered it, the sheet adopted it, and the text stayed in the box, so the next
    ///   Done appended it again: ["first", "abc", "abc def"].
    /// - It is the document the sheet SHOWS, never an incoming row's. A sheet opened on a queued,
    ///   undelivered note keeps its own copy over a row (`DetailFieldEdits.adopting`). Text taken
    ///   off the box when only the row held it was in neither place, and the next note, appended to
    ///   the sheet's copy, replaced the server's document (pre-existing for the journal's draft).
    /// - Every draft is kept until the sheet shows its document, not only the newest: a flush can
    ///   be delivering an older one while a newer one is queued (pre-existing for the journal).
    ///   A draft whose document the sheet never shows is never matched, and costs nothing else.
    public struct Ledger: Equatable, Sendable {
        /// Everything taken off the start of the box so far, in order (fix round 2): append-only. A
        /// save notes it as it takes the box's text; when that save lands, what was taken since is
        /// gone already (`RichNoteBox.landing`'s `removedSince`), so the same text never leaves the
        /// box twice.
        public private(set) var removed = ""
        /// The documents queued from the box that the sheet hasn't shown yet, oldest first; one
        /// per document.
        public private(set) var queued: [QueuedDraft] = []

        public init() {}

        /// A save of `typed`, taken from the box when `removed` stood at `removedAt`, is saved (it
        /// landed, or a flush ahead of it delivered its document). Returns the box.
        public mutating func saved(_ typed: String, removedAt: String, box: String) -> String {
            take(typed, removedAt: removedAt, from: box)
        }

        /// The journal queued the box's `typed` as `document`.
        public mutating func journaled(_ typed: String, document: String) {
            keep(QueuedDraft(typed: typed, document: document, removedAt: removed))
        }

        /// A save of `typed` (taken when `removed` stood at `removedAt`) failed, and its `document`
        /// stays queued. `shown` is the document the sheet shows now: a realtime echo may have
        /// brought it already. Returns the box when it changed, nil otherwise.
        public mutating func failed(_ typed: String, document: String, removedAt: String,
                                    shown: String?, box: String) -> String? {
            keep(QueuedDraft(typed: typed, document: document, removedAt: removedAt))
            return reconcile(shown: shown, box: box)
        }

        /// The sheet now shows `document` (its fields after a row was folded in, or a save landed):
        /// a draft queued as that document is in it, and what of its text is still at the box's
        /// start leaves the box. Returns the box when a draft matched, nil otherwise.
        public mutating func reconcile(shown document: String?, box: String) -> String? {
            guard let document, let index = queued.firstIndex(where: { $0.document == document }) else { return nil }
            let draft = queued.remove(at: index)
            return take(draft.typed, removedAt: draft.removedAt, from: box)
        }

        private mutating func keep(_ draft: QueuedDraft) {
            queued.removeAll { $0.document == draft.document }
            queued.append(draft)
        }

        private mutating func take(_ typed: String, removedAt: String, from box: String) -> String {
            let next = RichNoteBox.landing(of: typed, removedSince: String(removed.dropFirst(removedAt.count)), box: box)
            removed += next.removed
            return next.box
        }
    }
}
