import Foundation

/// How one detail-sheet save ended — `ItemDetailView.save`'s result (plan 16 Task 4e, 4d review
/// A-2).
public enum DetailSaveOutcome: Equatable, Sendable {
    /// The PATCH went out, and the server returned this row.
    case landed(Item)
    /// Nothing was left to send: a write that landed first — a flush queued ahead of the save —
    /// had already put each of its fields, or a newer value of it, on the server
    /// (`PendingEdits.send`). The values ARE saved.
    case alreadyDelivered
    /// The PATCH failed; the values stay queued for the next flush.
    case failed

    /// A queue save's outcome (`PendingEdits.send` returned; it throws on failure).
    public init(_ save: SheetSave) {
        self = save.item.map(DetailSaveOutcome.landed) ?? .alreadyDelivered
    }

    /// Whether the save's values are on the server — `.landed` and `.alreadyDelivered` alike. Work
    /// that waits for the text to be saved (the notes draft's bookkeeping) runs on both: skipped
    /// for `.alreadyDelivered`, a rich note's sent paragraph stayed in the box, and the next Done
    /// appended it to the document a second time.
    public var isSaved: Bool { self != .failed }
}

/// The detail sheet's text fields that the queue-aware rules cover.
public enum SheetTextField: Hashable, Sendable {
    case title, description, supplementalNote
}

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
/// - `sending`: the patches of the sheet's own saves still in flight (only which fields they carry
///   is read). A flush queued ahead of such a save can deliver its value and confirm it before the
///   save's turn, so the queue no longer says the field is outstanding while the save is still on
///   its way (Task 4e, 4d review P-1).
/// - `typedSinceSave`: the fields the user has typed into since their last save started — what is
///   still in the autosave's debounce, recorded nowhere yet (Task 4e fix round 1, review M-1). A
///   flush can deliver a value queued earlier — a failed autosave's, or one another sheet left
///   queued — inside that debounce; without this, a revert typed over it (back to the server's
///   value) was replaced by the flushed row, visibly, and the debounce then sent nothing.
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
/// - `adopt` keeps it as the user left it while their change to it is still on its way — queued,
///   being sent, or typed and in the debounce (`keeps`) — the incoming row may predate that write,
///   or be a flush's delivery of a value the user has since moved on from (P-1, M-1);
/// - a save that lands after the user changed it re-queues the field's value before `adopt` reads
///   the queue (`superseding`, run by `landing`), so the confirm never leaves the sheet with
///   nothing but the old value to go by — and so does a save a flush had already delivered, landed
///   against the values that flush delivered (Task 4e, B-1).
///
/// **Fields that don't read the queue here.** The notes (`content`): a rich note is append-only,
/// and a plain note's draft has its own queue-aware check (`PlainNoteDraft`). A location is saved
/// the moment it is committed (each revert is itself queued, latest-wins — no debounce gap); it
/// keeps its plain comparison with `baseline`. The Sharing switch is optimistic and never written
/// ahead: a journal queues a toggle the server hasn't confirmed (`journaledSharing` — never a
/// share while the sheet stays open). A share that fails in front of the user settles the switch,
/// and the queue, on what the server holds as far as the client knows — its last server row, or a
/// Sharing value the app's queue delivered since; an un-share that fails is never turned back on
/// by a delivered share; and a switch that settles off has private queued again
/// (`undoingFailedToggle`, Tasks 4d and 4e).
public struct DetailFieldEdits {
    public var local: Item
    public var baseline: Item
    public var queued: PendingEdit?
    public var sending: [ItemPatch]
    public var typedSinceSave: Set<SheetTextField>

    public init(local: Item, baseline: Item, queued: PendingEdit?, sending: [ItemPatch] = [],
                typedSinceSave: Set<SheetTextField> = []) {
        self.local = local
        self.baseline = baseline
        self.queued = queued
        self.sending = sending
        self.typedSinceSave = typedSinceSave
    }

    // MARK: - The rule, per field

    /// Whether a field must be (re)sent: it differs from the server's value, or from a value still
    /// queued for it (a revert that has to supersede a value sent a moment ago). Values are
    /// normalized `?? ""` by the callers; a queued sticky note of `""` is a queued clear.
    public static func needsSave(_ local: String, baseline: String, queued: String?) -> Bool {
        local != baseline || queued.map { $0 != local } ?? false
    }

    /// Whether `adopting` keeps a field as the user left it instead of taking an incoming row's: it
    /// differs from the server's value, or the user's change to it is still on its way — queued, or
    /// `inProgress`: being sent by one of the sheet's own saves, or typed and still in the
    /// autosave's debounce.
    public static func keeps(_ local: String, baseline: String, queued: String?, inProgress: Bool = false) -> Bool {
        local != baseline || queued != nil || inProgress
    }

    private var localTitle: String { local.title ?? "" }
    private var localDescription: String { local.description ?? "" }
    private var localNote: String { local.supplementalNote ?? "" }

    /// The user typed into `field` since its last save started, or one of the sheet's saves (those
    /// `carries`) is still sending it.
    private func inProgress(_ field: SheetTextField, _ carries: (ItemPatch) -> Bool) -> Bool {
        typedSinceSave.contains(field) || sending.contains(where: carries)
    }

    public var titleNeedsSave: Bool {
        Self.needsSave(localTitle, baseline: baseline.title ?? "", queued: queued?.title?.value)
    }

    public var keepsTitle: Bool {
        Self.keeps(localTitle, baseline: baseline.title ?? "", queued: queued?.title?.value,
                   inProgress: inProgress(.title) { $0.title != nil })
    }

    public var descriptionNeedsSave: Bool {
        Self.needsSave(localDescription, baseline: baseline.description ?? "", queued: queued?.description?.value)
    }

    public var keepsDescription: Bool {
        Self.keeps(localDescription, baseline: baseline.description ?? "", queued: queued?.description?.value,
                   inProgress: inProgress(.description) { $0.description != nil })
    }

    public var supplementalNoteNeedsSave: Bool {
        Self.needsSave(localNote, baseline: baseline.supplementalNote ?? "", queued: queued?.supplementalNote?.value)
    }

    public var keepsSupplementalNote: Bool {
        Self.keeps(localNote, baseline: baseline.supplementalNote ?? "", queued: queued?.supplementalNote?.value,
                   inProgress: inProgress(.supplementalNote) { $0.supplementalNote != nil })
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
    /// 3. `apply` hands `saved` to the list (`ItemStore.applyDetail`), laid over the queue as it
    ///    NOW stands (review m-1). Laid before the confirm, a row kept a value the confirm then
    ///    dropped — an un-share removes the sticky note in its own PATCH, so a note still queued
    ///    from before it is dropped, yet the store re-lays a row only from what is still queued;
    /// 4. `saved` is folded into the fields against the same queue (`adopting`, with the sheet's
    ///    `sending` and `typedSinceSave`: a field the user has typed into since, or that another
    ///    of its saves is sending, stays as they left it — fix round 1, review M-1) — and a note
    ///    document `sent` carried is the server's from here on (below).
    /// Returns the fields to show if the sheet adopts `saved`. Every save and every Sharing toggle
    /// that lands goes through here.
    ///
    /// **The note document** (Task 4e fix round 1, found with review C-1). A note is never edited in
    /// place: the notes editor's draft is appended to the document, or replaces a plain note whole,
    /// and the save carries the result. So once a save that carried `content` lands, the document
    /// the server holds is the one the sheet must show — the next note is appended to it. `adopting`
    /// alone kept the sheet's copy whenever it differed from the last server row: a sheet opened on
    /// a queued, undelivered note (closed offline) kept that copy after a note saved on top of it
    /// landed, and the next note, appended to the copy, replaced the server's document.
    ///
    /// Fix round 2 (4e re-review): that holds while another note save is still queued too. Round
    /// 1 kept the sheet's copy then, and overlapping note saves lost one: "abc" landed, its paragraph
    /// left the notes box, the sheet's document still lacked it, and the next note — built on that
    /// document — landed last. Nothing the user typed is in neither place: what a newer save carries
    /// beyond the landed document is still in the box (`RichNoteBox.landing`).
    @MainActor
    public static func landing(_ sent: ItemPatch, capturedAt: Date, as saved: Item, local: Item,
                               baseline: Item, queue: PendingEdits, sheetIsOpen: Bool, at now: Date,
                               sending: [ItemPatch] = [], typedSinceSave: Set<SheetTextField> = [],
                               apply: (Item) -> Void) -> Item {
        if sheetIsOpen {
            let moved = DetailFieldEdits(local: local, baseline: baseline, queued: queue.edit(for: saved.id))
                .superseding(sent)
            if !moved.isEmpty { queue.record(itemId: saved.id, patch: moved, capturedAt: now) }
        }
        queue.confirm(itemId: saved.id, patch: sent, capturedAt: capturedAt)
        apply(saved)
        let after = DetailFieldEdits(local: local, baseline: baseline, queued: queue.edit(for: saved.id),
                                     sending: sending, typedSinceSave: typedSinceSave)
        var fields = after.adopting(saved)
        if sent.content != nil { fields.content = saved.content }
        return fields
    }

    /// A save through the queue (`PendingEdits.send`, captured at `capturedAt`) came back: its
    /// landing, against what the server now holds for each of its fields (`save.serverHolds`) —
    /// and the row the sheet takes as the server's from here on (`row`, its next `snapshot`).
    ///
    /// - The PATCH went out: `row` is the row it returned, and `apply` hands it to the list. A field
    ///   the save left out (delivered first) is landed against that write's value too.
    /// - Nothing was left to send (Task 4e, 4d review A-2 and B-1): a write that landed first — a
    ///   flush queued ahead of the save — delivered every field already. That is saved, and it
    ///   lands like any save: `row` is `snapshot` with the values that write delivered. Skipped,
    ///   the supersede step never ran, so a field the user had moved on from meanwhile ("Y", then
    ///   "X" typed back over a server "X") was never sent; and a sheet whose store never sees the
    ///   flush's row (an Ask citation sheet) would keep its old note document — the next note,
    ///   appended to that, would replace the one the flush delivered. The list isn't handed that
    ///   row: the write that delivered the values handed it its own.
    @MainActor
    public static func landing(_ save: SheetSave, capturedAt: Date, local: Item, snapshot: Item,
                               queue: PendingEdits, sheetIsOpen: Bool, at now: Date,
                               sending: [ItemPatch] = [], typedSinceSave: Set<SheetTextField> = [],
                               apply: (Item) -> Void) -> (row: Item, fields: Item) {
        let baseline = ItemDisplay.editableRow(snapshot)
        guard let saved = save.item else {
            let row = PendingEdit(itemId: snapshot.id, patch: save.serverHolds, capturedAt: now).applied(to: snapshot)
            let fields = landing(save.serverHolds, capturedAt: capturedAt, as: row, local: local, baseline: baseline,
                                 queue: queue, sheetIsOpen: sheetIsOpen, at: now, sending: sending,
                                 typedSinceSave: typedSinceSave, apply: { _ in })
            return (row, fields)
        }
        let fields = landing(save.serverHolds, capturedAt: capturedAt, as: saved, local: local, baseline: baseline,
                             queue: queue, sheetIsOpen: sheetIsOpen, at: now, sending: sending,
                             typedSinceSave: typedSinceSave, apply: apply)
        return (saved, fields)
    }

    /// A save that landed while a newer one has started (`ItemDetailView.save`'s `SaveGeneration`
    /// gate): the sheet doesn't adopt its row — the newest save's landing decides the fields — but
    /// what the server now holds for this save's fields becomes the sheet's last server row now
    /// (Task 4e fix round 1, review C-1). The newest save may have nothing left to send, and then it
    /// lands against `snapshot`; a sheet whose store never hands it a flushed row (an Ask citation
    /// sheet) has no other way to learn what this one delivered. Skipped, a note's save landed
    /// unseen: "abc" had left the box (it was saved), the newest save landed against the old
    /// document, and the next note — appended to that — deleted "abc" from the server.
    ///
    /// - `snapshot` takes `save.serverHolds`, every field the save covered, as the server holds it.
    /// - The note document goes into the fields as well — the next note is appended to it — as
    ///   `landing` decided it (`landed.fields`). The other text fields stay as the user left them:
    ///   the queue-aware rules keep or take them at the newest save's landing, and a baseline that
    ///   is stale for them costs at most a redundant send.
    public static func carrying(_ save: SheetSave, landed: (row: Item, fields: Item), local: Item,
                                snapshot: Item) -> (local: Item, snapshot: Item) {
        let server = PendingEdit(itemId: snapshot.id, patch: save.serverHolds, capturedAt: .distantPast).applied(to: snapshot)
        var fields = local
        if save.serverHolds.content != nil { fields.content = landed.fields.content }
        return (fields, server)
    }

    /// A Sharing toggle's PATCH (`patch`) succeeded while a newer save had started
    /// (`ItemDetailView.setPublic`'s `SaveGeneration` gate): the sheet doesn't adopt its row, the
    /// newest save decides the fields. But what the toggle put on the server must still reach what
    /// the sheet knows of the server's Sharing value, the one thing a later failed toggle settles on
    /// (`undoingFailedToggle`, Task 4e fix round 2; in StashKit since batch B):
    /// - `snapshot`, the sheet's last server row, takes the toggle's fields. Skipped, an un-share
    ///   that landed this way left the row saying public; when the newer save then failed (so no row
    ///   was adopted) and a share failed, the switch stayed on with no error over a private item.
    /// - `knownDeliveries`, the queue's `deliveryCount` when the sheet last learned the server's
    ///   Sharing value, moves on to now (never back). The toggle's value is newer than anything the
    ///   queue delivered before it landed. Skipped, a share the queue delivered before that un-share
    ///   still counted as what the server holds: the switch stayed on with no error, and the close
    ///   published the item. A delivery that landed between the toggle's PATCH returning and this
    ///   call counts as seen too: the read-to-adopt approximation `ItemDetailView.adopt` documents.
    @MainActor
    public static func carryingToggle(_ patch: ItemPatch, snapshot: Item, knownDeliveries: Int,
                                      queue: PendingEdits) -> (snapshot: Item, knownDeliveries: Int) {
        let server = PendingEdit(itemId: snapshot.id, patch: patch, capturedAt: .distantPast).applied(to: snapshot)
        return (server, max(knownDeliveries, queue.deliveryCount))
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

    // MARK: - Sharing (Task 4d, review P-4)

    /// The Sharing value a journal queues, or nil: the switch's, when the server hasn't confirmed it
    /// — it differs from the server's, or from a Sharing value still queued (Task 4e, 4d review
    /// A-1: a sheet opened on a queued share, the switch turned back off — off equals the server's
    /// value, yet the queued share would publish the item at the next flush) — except a SHARE while
    /// the sheet stays open (`closing == false`: the app only leaving the foreground). A share is
    /// never written ahead; while it is in flight its own PATCH owns it. If that fails, the switch
    /// settles on what the server holds in front of the user — and a copy queued meanwhile would
    /// publish the item at the next flush anyway (review P-4). Left out, the worst case is a share
    /// lost when the app is killed mid-flight: the item stays private (privacy first). An un-share
    /// is always queued — it fails safe — and closing the sheet queues either: the user never sees
    /// a failure then, and the close's flush retries what they last saw (plan 15).
    public func journaledSharing(closing: Bool) -> Bool? {
        let unconfirmed = local.isPublic != baseline.isPublic
            || (queued?.isPublic.map { $0.value != local.isPublic } ?? false)
        guard unconfirmed, closing || !local.isPublic else { return nil }
        return local.isPublic
    }

    /// A Sharing toggle to `target` FAILED: the fields to show, with the queue settled to match —
    /// the one call `ItemDetailView.setPublic`'s failure makes (review P-4, F1). `local.isPublic ==
    /// target` afterwards means the switch stays where the user put it, so there is no error to
    /// show: for a share, the server holds `target` as far as the client knows; for an un-share, the
    /// sheet's last server row (or an un-share the queue delivered) says private, and private is
    /// queued again — over a share the queue delivered, the item is public until that lands (batch
    /// B, 4e re-review 2).
    ///
    /// - A closed sheet changes nothing (as `landing`): its journal queued the toggle the user last
    ///   saw, and the close's flush retries it — they never saw it fail.
    /// - The switch shows what the server holds as far as the sheet knows (`baseline`). Normally
    ///   that is the old value: the switch goes back, and a failed un-share's sticky note comes back
    ///   (`undoingFailedUnshare`). But a flush may have delivered the toggle already (an un-share
    ///   the background journal queued), or another device made the same change, or the sheet
    ///   opened on a queued toggle the user has just turned back to the server's value — the toggle
    ///   took effect, and the switch stays where they put it. Flipping it back would have the close
    ///   journal (and the next flush) undo what the server holds: an un-shared item made public.
    /// - What the server holds is what the client knows of it: `baseline`, the sheet's last server
    ///   row, and anything the app's queue delivered after that row was read — `knownDeliveries` is
    ///   the queue's `deliveryCount` then (Task 4e fix rounds 1–2, review M-4). An Ask citation
    ///   sheet's store never hands it a flushed row, so its row can predate the app's own delivery
    ///   of a queued Sharing value — in any order: before the toggle, or during it. Opened on a queued
    ///   un-share and turned on, the switch stayed on with no error over a private item, and the
    ///   share was lost without a word; now it shows private, with the error. A failed UN-share is
    ///   never turned back on by such a delivery (a queued share delivered underneath it): it keeps
    ///   the fail-safe below — private is queued again, the user's choice and the safe one.
    /// - Then the queue must say the same as the switch, so a later flush never changes the item's
    ///   visibility to something the user isn't looking at. Left ON (the server is public): any other
    ///   queued Sharing value is taken back (`PendingEdits.withdrawSharing`). Left OFF: private is
    ///   recorded again (Task 4e, 4d review A-3 and B-2). Taking back a queued share isn't enough
    ///   there, because `baseline` can be wrong in the dangerous direction: an Ask citation sheet's
    ///   store never sees the row a flush delivered (a queued share published underneath it), and a
    ///   share the server applied but whose response was lost leaves every sheet's row private. The
    ///   cost is one PATCH of a value the server usually holds already; a failed share is never
    ///   published later, whatever reached the server meanwhile. Settling off after a failed
    ///   un-share re-records its note removal too: a note still queued is cleared, never delivered
    ///   to the private item (a later share would publish it again).
    @MainActor
    public static func undoingFailedToggle(to target: Bool, noteBefore: String?, knownDeliveries: Int? = nil,
                                           local: Item, baseline: Item,
                                           queue: PendingEdits, sheetIsOpen: Bool, at now: Date) -> Item {
        guard sheetIsOpen else { return local }
        var settled = local
        settled.isPublic = baseline.isPublic
        if let known = knownDeliveries, let delivered = queue.deliveredSharing(for: local.id, after: known),
           target || !delivered {
            settled.isPublic = delivered
        }
        if !target {
            if settled.isPublic {
                settled = undoingFailedUnshare(noteBefore: noteBefore, local: settled, baseline: baseline,
                                               queue: queue, sheetIsOpen: sheetIsOpen, at: now)
            } else {
                let edits = DetailFieldEdits(local: settled, baseline: baseline, queued: queue.edit(for: local.id))
                if edits.supplementalNoteNeedsSave {
                    queue.record(itemId: local.id, patch: ItemPatch(supplementalNote: edits.localNote), capturedAt: now)
                }
            }
        }
        if settled.isPublic {
            queue.withdrawSharing(itemId: local.id, otherThan: true)
        } else {
            var reassert = ItemPatch(isPublic: false)
            if !target, let noteBefore, !noteBefore.isEmpty { reassert.supplementalNote = "" }
            queue.record(itemId: local.id, patch: reassert, capturedAt: now)
        }
        return settled
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
    ///
    /// Only while the sheet is open (review F1). The un-share's PATCH outlives the sheet, and a
    /// sheet closed during it has journaled the toggle the user last saw — private, the note
    /// removed, as they confirmed — which the close's flush delivers (plan 15). Putting the note
    /// back over that clear would make the item private WITH the note, and a later re-share would
    /// publish it again. So a closed sheet returns `local` untouched, as `landing` does.
    @MainActor
    public static func undoingFailedUnshare(noteBefore: String?, local: Item, baseline: Item,
                                            queue: PendingEdits, sheetIsOpen: Bool, at now: Date) -> Item {
        guard sheetIsOpen else { return local }
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
