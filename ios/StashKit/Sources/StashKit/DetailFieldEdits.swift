import Foundation

/// What an open detail sheet's fields hold that the server hasn't confirmed — the ONE rule its
/// debounced autosave, its dismiss/background journal and `adopt` (folding a fresher server row
/// into the open sheet) share (plan 16, Task 4 review I-1).
///
/// - `local`: the sheet's fields as the user left them.
/// - `baseline`: the server's last row as the fields show it (`ItemDisplay.editableRow(snapshot)`
///   — an object-name title reads as empty).
/// - `queued`: the item's entry in the durable `PendingEdits` queue. Every save records its fields
///   there when it STARTS and they leave once the server confirms them, so the entry holds saves
///   still in flight and failed ones alike.
///
/// **The title reads the queue (I-1).** Comparing the field with `baseline` alone can't tell "never
/// typed in" from "typed, sent, then cleared again": an object-name title's baseline is `""`, so a
/// clear after "Gro" went out (in flight, or failed and queued) looked like no edit at all — the
/// "Gro" response then refilled the field, and the queue (or the dismiss flush) wrote "Gro" to the
/// server, where it also blocked the transcription job's AI title for good. So:
/// - the title needs saving when it differs from the server's OR from a value still queued for it
///   (`titleNeedsSave`) — the clear becomes a patch that supersedes "Gro" through the queue's
///   latest-wins rule, the dismiss journal and flush included;
/// - `adopt` keeps the typed title while a write of it is still outstanding (`keepsTitle`) — the
///   incoming row may predate it;
/// - a save that lands after the user changed the title re-queues the field's value before it is
///   confirmed (`superseding`), so the confirm never leaves the sheet with nothing but the old
///   value to go by.
///
/// Every other field keeps its plain comparison with `baseline` (unchanged; plan 16 scope).
public struct DetailFieldEdits {
    public var local: Item
    public var baseline: Item
    public var queued: PendingEdit?

    public init(local: Item, baseline: Item, queued: PendingEdit?) {
        self.local = local
        self.baseline = baseline
        self.queued = queued
    }

    private var localTitle: String { local.title ?? "" }
    private var baselineTitle: String { baseline.title ?? "" }
    private var queuedTitle: String? { queued?.title?.value }

    /// Whether the title must be (re)sent: it differs from the server's, or from a value still
    /// queued for it (a clear that has to supersede a title typed and sent a moment ago).
    public var titleNeedsSave: Bool {
        localTitle != baselineTitle || queuedTitle.map { $0 != localTitle } ?? false
    }

    /// Whether `adopting` keeps the title as typed instead of taking an incoming row's: it differs
    /// from the server's, or a write of it is still outstanding.
    public var keepsTitle: Bool {
        localTitle != baselineTitle || queuedTitle != nil
    }

    /// Title, description and sticky note, as the debounced autosave sends them and the dismiss
    /// journal starts from.
    public var textPatch: ItemPatch {
        var patch = changedFields(from: baseline, title: localTitle, description: local.description ?? "",
                                  supplementalNote: local.supplementalNote ?? "")
        patch.title = titleNeedsSave ? localTitle : nil
        return patch
    }

    /// For a save that just landed, BEFORE it's confirmed: the title the field holds now, when the
    /// user changed it after the save captured `sent` — to be queued as the newer edit, so the
    /// confirm can't drop the only record that the field moved on (e.g. cleared inside its
    /// debounce while "Gro" was in flight). Empty otherwise.
    public func superseding(_ sent: ItemPatch) -> ItemPatch {
        guard let sentTitle = sent.title, sentTitle != localTitle else { return ItemPatch() }
        return ItemPatch(title: localTitle)
    }

    /// `incoming` (a fresher server row — our own save coming back, realtime, the `page_body`
    /// fetch, a transcription) folded into the fields: every field the user has changed keeps what
    /// they typed; everything else takes the server's. A new object-name title reads as empty.
    public func adopting(_ incoming: Item) -> Item {
        var next = mergePreservingDetail(
            local: local,
            incoming: ItemDisplay.editableRow(incoming),
            hasUnsavedTitle: keepsTitle,
            hasUnsavedDescription: (local.description ?? "") != (baseline.description ?? ""),
            hasUnsavedSupplementalNote: (local.supplementalNote ?? "") != (baseline.supplementalNote ?? ""),
            hasUnsavedLocation: false,
            hasUnsavedContent: (local.content ?? "") != (baseline.content ?? "")
        )
        if local.attributes.location != baseline.attributes.location {
            next.attributes.location = local.attributes.location
        }
        if local.isPublic != baseline.isPublic { next.isPublic = local.isPublic }
        return next
    }
}
