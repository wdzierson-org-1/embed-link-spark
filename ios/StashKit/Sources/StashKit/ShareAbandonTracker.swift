import Foundation

/// Tracks whether one share's staged files have been handed off to `ShareIntake.submit` — Fix
/// round 1 (Important review finding): only an explicit Cancel button used to discard staged
/// files, so an ABANDONED share sheet (swiped away — a normal iOS gesture, not just Cancel/Save)
/// left them on disk with no Outbox entry pointing at them; `sweepOrphans`' 60s grace period would
/// eventually auto-enqueue and upload them on the next app launch — a share the user quietly
/// declined to send appearing in Stash anyway.
///
/// DECISION (adopted): any dismissal without a completed Save = abandonment = discard.
///
/// Lives in StashKit (moved here in Task 7 fix round 2) rather than the share extension target:
/// this bookkeeping has no UIKit/extension-only dependency (`SharedObject`/`StagedFileStore` are
/// both already StashKit types), and this is the SECOND fix round to touch this exact class —
/// worth `swift test` coverage rather than relying on live/manual verification a third time.
///
/// **Consumed boundary (Fix round 2, Important review finding).** `markConsumed()` must be the
/// very FIRST statement a caller runs in direct response to the user's Save tap — before ANY
/// `await`, including a location resolution that can itself suspend for several seconds. The Save
/// TAP is the intent boundary, not whatever `ShareIntake.submit` does internally afterward: a
/// suspension point is exactly where a concurrent `viewDidDisappear` — driven by a swipe-to-dismiss
/// gesture the OS can deliver at any time, with no app code in the loop — gets a chance to run on
/// the same actor and call `discardIfAbandoned()` while `consumed` is still `false`, deleting files
/// out from under an in-flight save. Once `markConsumed()` has run, `ShareIntake`'s OWN internal
/// logic owns every staged file's lifecycle (discards on a successful direct send; deliberately
/// RETAINS a file for a queued Outbox entry) and this tracker must never touch them again,
/// including during any post-submit outcome-display window before the extension's UI actually
/// tears down. `ShareViewController.viewDidDisappear` calls `discardIfAbandoned()`
/// UNCONDITIONALLY on every teardown (explicit Cancel, a completed Save, OR a swipe) — the
/// `consumed` guard is what makes that safe to call unconditionally rather than needing the caller
/// to know which case it is.
///
/// **Mid-load staging (Fix round 2, disclosed residual, closed).** A share's files are staged
/// progressively, one per attachment, over the course of `ProviderLoader.load()` — but
/// `track(objects:staging:)` below is only ever called ONCE, after `load()` returns with its full,
/// final list. A swipe that lands while `load()` is still running fires `discardIfAbandoned()`
/// before `track` has recorded anything at all, so that call finds nothing to discard — and since
/// `discardIfAbandoned()` was never going to be called again on its own, every file `load()` went
/// on to stage (including ones staged BEFORE the swipe) would sit on disk with nothing ever
/// discarding them, left for `sweepOrphans`' 60s grace period to auto-save a share the user
/// actually abandoned. `discardHasRun` below closes this: it latches the instant
/// `discardIfAbandoned()` first runs, regardless of whether it found anything to act on, and a LATE
/// `track()` call that arrives after that point immediately re-runs the discard logic against the
/// objects it just received — catching every file `load()` ever staged, not just the ones staged
/// after the swipe.
///
/// `@MainActor`: every call site (`ShareComposeView`'s own methods, `UIViewController` lifecycle
/// callbacks) already runs on the main actor; this just makes that explicit.
@MainActor
public final class ShareAbandonTracker {
    private var consumed = false
    private var objects: [SharedObject] = []
    private var staging: StagedFileStore?
    /// Set the first time `discardIfAbandoned()` runs, whether or not it found anything to discard
    /// — see this type's own header comment ("Mid-load staging") for why a LATE `track()` call
    /// needs to know this happened already.
    private var discardHasRun = false

    public init() {}

    /// Called once `load()` finishes populating `objects`/`staging` — a no-op past
    /// `markConsumed()`. If `discardIfAbandoned()` has ALREADY run by the time this arrives (the
    /// mid-load swipe case — see header comment), immediately discards what was just recorded
    /// instead of leaving it for a second `discardIfAbandoned()` call that will never come.
    public func track(objects: [SharedObject], staging: StagedFileStore) {
        guard !consumed else { return }
        self.objects = objects
        self.staging = staging
        if discardHasRun {
            discardIfAbandoned()
        }
    }

    /// Every currently-tracked staged file is owned elsewhere from this point on —
    /// `discardIfAbandoned()` becomes a permanent no-op after this call. Callers MUST call this
    /// synchronously, before any `await`, as the first action taken in response to the user's Save
    /// tap — see this type's own header comment ("Consumed boundary") for why.
    public func markConsumed() {
        consumed = true
    }

    /// Discards every currently-tracked staged file. A no-op once `markConsumed()` has fired, or if
    /// nothing has been tracked YET (e.g. the `.noSession` branch, which never stages anything, or
    /// a swipe that lands before `track()` has run at all — see `track`'s own late-catch-up
    /// handling above for that case). Safe to call more than once: a repeat call simply finds an
    /// already-emptied list.
    public func discardIfAbandoned() {
        discardHasRun = true
        guard !consumed, let staging else { return }
        for object in objects {
            if case .file(let url, _, _, _) = object { staging.discard(url) }
        }
        objects = []
    }
}
