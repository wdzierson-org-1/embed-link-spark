import Foundation

/// Monotonic generation counter guarding against stale-save-response races (Plan 8, fix round 1,
/// review finding #2) — `ItemDetailView` has TWO independent debounced autosave paths (field edits
/// at 400ms, notes at 600ms), each dispatching its own `editor.save` call and, on success, folding
/// the response into the shared `item`/`snapshot` state via `adopt(_:)`. Network responses can
/// land out of dispatch order (a slower/earlier request's response arriving AFTER a faster/later
/// one's), so without a guard, an older save's response landing last could revert a field a newer
/// save already committed.
///
/// The pattern: every save site captures `let gen = saveGeneration.next()` immediately before
/// starting its network call, then — once the response arrives — checks
/// `saveGeneration.isLatest(gen)` before applying it. A response whose generation no longer
/// matches the current one is a stale echo of a save that's since been superseded by a newer one
/// and should be dropped, not applied over whatever that newer save (or an even-newer one already
/// in flight) has already committed.
///
/// `@MainActor` (a class with a plain `Int`, not a separate actor requiring `await` at every call
/// site) rather than a general-purpose actor — deliberately mirrors the shape already established
/// twice in this codebase for the exact same "drop a stale async response" problem:
/// `ItemStore.loadGeneration`/`SubscriptionStore.refreshGeneration` (both a plain `Int` on an
/// already-`@MainActor` type). Every one of `ItemDetailView`'s save call sites is itself already
/// `@MainActor`-isolated, so calls here are synchronous from all of them — extracted into its own
/// tiny type here (rather than inlined as `@State private var saveGeneration = 0` a third time)
/// purely so the generation-drop logic itself is independently unit-testable outside a View.
@MainActor
public final class SaveGeneration {
    private var current = 0

    public init() {}

    /// Call once, right before starting a new save's network request. The returned value is this
    /// save's identity for the later `isLatest(_:)` check.
    public func next() -> Int {
        current += 1
        return current
    }

    /// Call once a save's response has arrived, before applying it. `false` means a NEWER save has
    /// since started (via another `next()` call) — this response is stale and should be dropped.
    public func isLatest(_ generation: Int) -> Bool {
        generation == current
    }
}
