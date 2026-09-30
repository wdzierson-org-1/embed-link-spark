import Foundation

/// What an open detail sheet's fields hold that the server hasn't confirmed — the ONE rule its
/// debounced autosave, its dismiss/background journal and `adopt` (folding a fresher server row
/// into the open sheet) share (plan 16, Task 4 review I-1; Task 4c).
///
/// - `local`: the sheet's fields as the user left them.
/// - `baseline`: the server's last row as the fields show it (`ItemDisplay.editableRow(snapshot)`
///   — an object-name title reads as empty).
/// - `queued`: the item's entry in the durable `PendingEdits` queue. Every save records its fields
///   there when it STARTS and they leave once the server confirms them, so the entry holds saves
///   still in flight and failed ones alike.
///
/// **The title, the description and the sticky note read the queue.** Comparing a field with
/// `baseline` alone can't tell "never edited" from "edited, sent, then put back": a clear of a title
/// typed after "Gro" went out (I-1), a description whose " x" was sent and then deleted again, a
/// sticky note typed and cleared (Task 4c, re-review §9) — each looked like no edit at all while
/// the other value was in flight or queued. The sent value's response then refilled the field, and
/// the queue (or the close's flush) delivered it. So, per field:
/// - it needs saving when it differs from the server's OR from a value still queued for it
///   (`needsSave`) — the revert becomes a patch that supersedes the sent value through the queue's
///   latest-wins rule, the close's journal and flush included;
/// - `adopt` keeps it as the user left it while a write of it is still outstanding (`keeps`) — the
///   incoming row may predate that write;
/// - a save that lands after the user changed it re-queues the field's value before `adopt` reads
///   the queue (`superseding`, run by `landing`), so the confirm never leaves the sheet with
///   nothing but the old value to go by.
///
/// **Fields that don't read the queue here.** The notes (`content`): a rich note is append-only,
/// and a plain note's draft has its own queue-aware check (`PlainNoteDraft`). A location is saved
/// the moment it is committed (each revert is itself queued, latest-wins — no debounce gap), and
/// the Sharing switch is optimistic and never written ahead, so the queue holds it only when a close
/// caught a toggle in flight; both keep their plain comparison with `baseline`.
public struct DetailFieldEdits {
    public var local: Item
    public var baseline: Item
    public var queued: PendingEdit?

    public init(local: Item, baseline: Item, queued: PendingEdit?) {
        self.local = local
        self.baseline = baseline
        self.queued = queued
    }

    // MARK: - The rule, per field

    /// Whether a field must be (re)sent: it differs from the server's value, or from a value still
    /// queued for it (a revert that has to supersede a value sent a moment ago). Values are
    /// normalized `?? ""` by the callers; a queued sticky note of `""` is a queued clear.
    public static func needsSave(_ local: String, baseline: String, queued: String?) -> Bool {
        local != baseline || queued.map { $0 != local } ?? false
    }

    /// Whether `adopting` keeps a field as the user left it instead of taking an incoming row's: it
    /// differs from the server's value, or a write of it is still outstanding.
    public static func keeps(_ local: String, baseline: String, queued: String?) -> Bool {
        local != baseline || queued != nil
    }

    private var localTitle: String { local.title ?? "" }
    private var localDescription: String { local.description ?? "" }
    private var localNote: String { local.supplementalNote ?? "" }

    public var titleNeedsSave: Bool {
        Self.needsSave(localTitle, baseline: baseline.title ?? "", queued: queued?.title?.value)
    }

    public var keepsTitle: Bool {
        Self.keeps(localTitle, baseline: baseline.title ?? "", queued: queued?.title?.value)
    }

    public var descriptionNeedsSave: Bool {
        Self.needsSave(localDescription, baseline: baseline.description ?? "", queued: queued?.description?.value)
    }

    public var keepsDescription: Bool {
        Self.keeps(localDescription, baseline: baseline.description ?? "", queued: queued?.description?.value)
    }

    public var supplementalNoteNeedsSave: Bool {
        Self.needsSave(localNote, baseline: baseline.supplementalNote ?? "", queued: queued?.supplementalNote?.value)
    }

    public var keepsSupplementalNote: Bool {
        Self.keeps(localNote, baseline: baseline.supplementalNote ?? "", queued: queued?.supplementalNote?.value)
    }

    // MARK: - Saving, landing, adopting

    /// Title, description and sticky note, each when it needs saving — what the debounced autosave
    /// sends and the dismiss journal starts from. A cleared sticky note is `""` (null on the wire).
    public var textPatch: ItemPatch {
        var patch = ItemPatch()
        if titleNeedsSave { patch.title = localTitle }
        if descriptionNeedsSave { patch.description = localDescription }
        if supplementalNoteNeedsSave { patch.supplementalNote = localNote }
        return patch
    }

    /// For a save that just landed, before `adopt` reads the queue: each field `sent` carried whose
    /// value the user has changed since — to be queued as the newer edit, so the confirm can't drop
    /// the only record that the field moved on (e.g. cleared inside its debounce while "Gro" was in
    /// flight). Fields `sent` didn't carry are left out. Empty when nothing moved on.
    public func superseding(_ sent: ItemPatch) -> ItemPatch {
        var patch = ItemPatch()
        if let title = sent.title, title != localTitle { patch.title = localTitle }
        if let description = sent.description, description != localDescription { patch.description = localDescription }
        if let note = sent.supplementalNote, note != localNote { patch.supplementalNote = localNote }
        return patch
    }

    /// A detail-sheet save of `sent` (captured at `capturedAt`) just landed as `saved`: the whole
    /// landing, in its one safe order (re-review m-3 — the sheet calls only this):
    /// 1. while the sheet is open, the values its fields moved on to since `sent` was captured are
    ///    queued at `now` (`superseding`) — this must come before step 3 reads the queue: once
    ///    `sent` is confirmed, nothing else remembers that the field moved on, so `adopting` would
    ///    put the sent value back (e.g. "Gro" landing just after the user cleared it). A closed
    ///    sheet's journal has already queued its fields, and they may be older than an edit made
    ///    since in a newly opened sheet, so a closed sheet queues nothing here;
    /// 2. `sent` is confirmed — each field forgotten unless a later value was recorded;
    /// 3. `saved` is folded into the fields against the queue as it now stands (`adopting`).
    /// Returns the fields to show if the sheet adopts `saved`.
    @MainActor
    public static func landing(_ sent: ItemPatch, capturedAt: Date, as saved: Item, local: Item,
                               baseline: Item, queue: PendingEdits, sheetIsOpen: Bool, at now: Date) -> Item {
        if sheetIsOpen {
            let moved = DetailFieldEdits(local: local, baseline: baseline, queued: queue.edit(for: saved.id))
                .superseding(sent)
            if !moved.isEmpty { queue.record(itemId: saved.id, patch: moved, capturedAt: now) }
        }
        queue.confirm(itemId: saved.id, patch: sent, capturedAt: capturedAt)
        return DetailFieldEdits(local: local, baseline: baseline, queued: queue.edit(for: saved.id)).adopting(saved)
    }

    /// `incoming` (a fresher server row — our own save coming back, realtime, the `page_body`
    /// fetch, a transcription) folded into the fields: every field the user has changed keeps what
    /// they typed; everything else takes the server's. A new object-name title reads as empty.
    public func adopting(_ incoming: Item) -> Item {
        var next = mergePreservingDetail(
            local: local,
            incoming: ItemDisplay.editableRow(incoming),
            hasUnsavedTitle: keepsTitle,
            hasUnsavedDescription: keepsDescription,
            hasUnsavedSupplementalNote: keepsSupplementalNote,
            hasUnsavedLocation: false,
            hasUnsavedContent: (local.content ?? "") != (baseline.content ?? "")
        )
        if local.attributes.location != baseline.attributes.location {
            next.attributes.location = local.attributes.location
        }
        if local.isPublic != baseline.isPublic { next.isPublic = local.isPublic }
        return next
    }

    // MARK: - A failed un-share (Task 4c)

    /// The sticky note to put back after an un-share FAILED, or nil to leave the field as it is.
    ///
    /// Making an item private clears its sticky note in the same PATCH (`ItemEditor.togglePublic`),
    /// and the sheet empties the field at once (optimistic). If that PATCH fails, nothing changed on
    /// the server — but now that the field reads the queue, an empty field under a queued,
    /// undelivered note reads as the user clearing it, and the next autosave (or the close) would
    /// send that clear. So the note comes back when the field is still empty and `noteBefore` — the
    /// field before the un-share — is still what the server holds (`baseline`) or what the queue
    /// will deliver.
    public func noteAfterFailedUnshare(noteBefore: String?) -> String? {
        guard localNote.isEmpty, let noteBefore, !noteBefore.isEmpty else { return nil }
        let holders = [baseline.supplementalNote, queued?.supplementalNote?.value]
        return holders.contains(noteBefore) ? noteBefore : nil
    }

    /// A failed un-share, undone in the fields and the queue: `local` with its sticky note put back
    /// (`noteAfterFailedUnshare`) — and, when the restored note now needs saving over what the
    /// queue holds, the note queued again at `now`. That case: a save of the note that landed while
    /// the un-share was in flight queued the field's optimistically emptied value (`superseding`),
    /// a clear that must never be sent.
    @MainActor
    public static func undoingFailedUnshare(noteBefore: String?, local: Item, baseline: Item,
                                            queue: PendingEdits, at now: Date) -> Item {
        let edits = DetailFieldEdits(local: local, baseline: baseline, queued: queue.edit(for: local.id))
        guard let note = edits.noteAfterFailedUnshare(noteBefore: noteBefore) else { return local }
        var restored = local
        restored.supplementalNote = note
        let after = DetailFieldEdits(local: restored, baseline: baseline, queued: queue.edit(for: local.id))
        if after.supplementalNoteNeedsSave {
            queue.record(itemId: local.id, patch: ItemPatch(supplementalNote: note), capturedAt: now)
        }
        return restored
    }
}
