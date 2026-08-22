import XCTest
@testable import StashKit

final class StubChecker: SubscriptionChecking, @unchecked Sendable {
    var results: [Result<SubscriptionStatus, Error>] = []
    var trialCalls = 0
    func check() async throws -> SubscriptionStatus {
        guard !results.isEmpty else { throw CaptureError.badStatus(500) }
        return try results.removeFirst().get()
    }
    func createTrial() async throws { trialCalls += 1 }
}

/// Checker whose `check()` blocks on an externally-releasable continuation, so a test can hold a
/// `refresh()` in flight and assert on `canAddContent` mid-request — mirrors ItemStoreTests'
/// `GatedFetcher` (plan 2). `createTrial()` is a synchronous no-op; only `check()` needs gating.
final class GatedChecker: SubscriptionChecking, @unchecked Sendable {
    var gates: [CheckedContinuation<SubscriptionStatus, Error>] = []
    func check() async throws -> SubscriptionStatus {
        try await withCheckedThrowingContinuation { gates.append($0) }
    }
    func createTrial() async throws {}
    func release(_ index: Int, with status: SubscriptionStatus) { gates[index].resume(returning: status) }
    /// Simulates a `refresh()` that gets cancelled mid-flight (Settings' own 30s-poll `.task`,
    /// Task 7, cancels an in-flight `check()` the instant the user switches tabs) — releasing
    /// with `CancellationError` directly is simpler and more deterministic than racing a real
    /// `Task.cancel()` against this continuation, and exercises the exact same catch-block path.
    func releaseWithCancellation(_ index: Int) { gates[index].resume(throwing: CancellationError()) }
}

@MainActor
final class SubscriptionStoreTests: XCTestCase {
    func testActiveSubscriptionOpensGates() async {
        let checker = StubChecker()
        checker.results = [.success(SubscriptionStatus(subscribed: true, onTrial: false, daysLeft: nil))]
        let store = SubscriptionStore(checker: checker)
        await store.refresh()
        XCTAssertTrue(store.canAddContent)
        XCTAssertEqual(checker.trialCalls, 0)
    }
    func testNoSubscriptionSelfHealsOnce() async {
        let checker = StubChecker()
        let none = SubscriptionStatus(subscribed: false, onTrial: false, daysLeft: nil)
        let trial = SubscriptionStatus(subscribed: false, onTrial: true, daysLeft: 14)
        checker.results = [.success(none), .success(trial), .success(none)]
        let store = SubscriptionStore(checker: checker)
        await store.refresh()
        XCTAssertEqual(checker.trialCalls, 1)
        XCTAssertTrue(store.canAddContent)          // trial picked up on re-check
        await store.refresh()                        // later refresh sees `none` again…
        XCTAssertEqual(checker.trialCalls, 1)        // …but never re-creates a trial
    }
    func testLoadingFailsOpenThenErrorClosesGates() async {
        let checker = StubChecker()                  // empty results → throw
        let store = SubscriptionStore(checker: checker)
        XCTAssertTrue(store.canAddContent)           // pre-first-refresh: loading state fail-open
        await store.refresh()
        XCTAssertFalse(store.canAddContent)
        XCTAssertNotNil(store.lastError)
    }

    // Closes review Important: `isLoading` must be a one-shot first-check flag (web parity —
    // useSubscription's `loading` is `useState(true)`, only ever set `false`, never re-armed).
    // A later refresh (e.g. the web's 30s poll) that resets `isLoading = true` at entry would
    // transiently fail *open* for an unsubscribed user for the duration of that network
    // round-trip — a gate leak the web doesn't have.
    func testLaterRefreshDoesNotReopenGatesWhileInFlight() async {
        let checker = GatedChecker()
        let store = SubscriptionStore(checker: checker)
        let notSubscribed = SubscriptionStatus(subscribed: false, onTrial: false, daysLeft: nil)

        async let first: Void = store.refresh()          // blocks on gate 0 (initial check)
        try? await Task.sleep(for: .milliseconds(50))
        checker.release(0, with: notSubscribed)          // not-subscribed → one-time self-heal fires
        try? await Task.sleep(for: .milliseconds(50))
        checker.release(1, with: notSubscribed)          // self-heal's re-check, also not-subscribed
        await first
        XCTAssertFalse(store.canAddContent)              // gates closed once first refresh settles

        async let second: Void = store.refresh()         // triedTrial already true → single blocking check
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertFalse(store.canAddContent)              // must NOT fail open mid-poll
        checker.release(2, with: notSubscribed)
        await second
        XCTAssertFalse(store.canAddContent)
    }

    // Review Critical (Task 7 fix round): a cancelled poll is not a failed check. Settings'
    // while-visible 30s poll (SubscriptionSection, Task 7) cancels an in-flight `refresh()` the
    // instant the user switches tabs mid-network-call — before this fix, `refresh()`'s catch-all
    // treated that `CancellationError` exactly like a real failure, wiping `status` to `nil` and
    // closing every gate (composer Save, Ask) app-wide for an already-subscribed user, with no
    // prompt way back short of revisiting Settings or a foreground cycle.
    func testCancelledRefreshLeavesStatusAndGatesUnchanged() async {
        let checker = GatedChecker()
        let store = SubscriptionStore(checker: checker)
        let trial = SubscriptionStatus(subscribed: false, onTrial: true, daysLeft: 5)

        // First refresh succeeds normally — gates open on a trial status.
        async let first: Void = store.refresh()
        try? await Task.sleep(for: .milliseconds(50))
        checker.release(0, with: trial)
        await first
        XCTAssertEqual(store.status, trial)
        XCTAssertTrue(store.canAddContent)

        // Second refresh blocks in check(), then is released with CancellationError instead of a
        // real result or a real failure — simulating the tab-switch-mid-poll cancellation above.
        async let second: Void = store.refresh()
        try? await Task.sleep(for: .milliseconds(50))
        checker.releaseWithCancellation(1)
        await second

        XCTAssertEqual(store.status, trial)     // untouched — NOT wiped to nil
        XCTAssertTrue(store.canAddContent)      // gates stay open
        XCTAssertNil(store.lastError)           // no spurious error surfaced either
    }

    // Plan-4 named requirement (docs/superpowers/plans/2026-08-11-ios-plan-3-parity.md's
    // post-review addendum): the CancellationError check above catches Swift-level task
    // cancellation, but Settings' poll cancels an in-flight URLSession request underneath
    // `checker.check()` — which surfaces as `URLError(.cancelled)`, a distinct type that
    // `is CancellationError` does not match. Same failure mode as the test above (status wiped,
    // gates slammed shut on an already-subscribed user) via a different transport-level shape.
    func testURLErrorCancelledTreatedAsCancellation() async {
        let checker = StubChecker()
        let trial = SubscriptionStatus(subscribed: false, onTrial: true, daysLeft: 5)
        checker.results = [.success(trial), .failure(URLError(.cancelled))]
        let store = SubscriptionStore(checker: checker)

        await store.refresh()
        XCTAssertEqual(store.status, trial)
        XCTAssertTrue(store.canAddContent)

        await store.refresh()   // throws URLError(.cancelled), not CancellationError

        XCTAssertEqual(store.status, trial)     // untouched — NOT wiped to nil
        XCTAssertTrue(store.canAddContent)      // gates stay open
        XCTAssertNil(store.lastError)           // no spurious error surfaced either
    }

    // Final-review Important finding: SubscriptionStore is app-lifetime (@State in StashApp)
    // and nothing observed `.signedOut`, so user A's status (and any gates A left open) would
    // persist verbatim into user B's session until B's own refresh() landed — indefinitely if
    // that refresh was ever cancelled. `reset()` (called from StashApp's session `.onChange` on
    // `.signedOut`) must put the store back in its exact pre-first-refresh state so the next
    // account's first refresh fails open identically to a fresh launch, AND gets its own
    // one-time trial self-heal rather than inheriting `triedTrial` already spent by the prior
    // account.
    func testResetClearsStatusAndRearmsLoadingAndSelfHealAcrossAccounts() async {
        let checker = StubChecker()
        let none = SubscriptionStatus(subscribed: false, onTrial: false, daysLeft: nil)
        let trial = SubscriptionStatus(subscribed: false, onTrial: true, daysLeft: 14)
        checker.results = [.success(none), .success(trial)]
        let store = SubscriptionStore(checker: checker)

        // Account A: a successful refresh that self-heals once, gates open.
        await store.refresh()
        XCTAssertEqual(checker.trialCalls, 1)
        XCTAssertTrue(store.canAddContent)

        store.reset()
        XCTAssertNil(store.status)
        XCTAssertNil(store.lastError)
        XCTAssertTrue(store.canAddContent)   // isLoading re-armed: fail-open, pre-first-check

        // Account B signs in: an identical none -> trial sequence must self-heal AGAIN —
        // triedTrial re-armed by reset(), so createTrial() fires a second time across the
        // reset boundary rather than staying permanently spent from account A.
        checker.results = [.success(none), .success(trial)]
        await store.refresh()
        XCTAssertEqual(checker.trialCalls, 2)
        XCTAssertTrue(store.canAddContent)
    }

    // Plan-4 named requirement (docs/superpowers/plans/2026-08-11-ios-plan-3-parity.md's
    // post-review addendum): `reset()` above closes the unconditional cross-account bleed, but an
    // in-flight `refresh()` started before sign-out had no generation guard and could still
    // clobber the next account's freshly-reset state when it resolved late (narrow race: a
    // same-device account switch inside the ~1s network window). Mirrors `ItemStore.loadGeneration`
    // (ItemStore.swift final-review Important #3): `reset()` bumps a generation token so any
    // refresh already in flight recognizes, on resolution, that it's stale and drops its result.
    func testStaleRefreshCannotClobberAfterReset() async {
        let checker = GatedChecker()
        let store = SubscriptionStore(checker: checker)
        let trial = SubscriptionStatus(subscribed: false, onTrial: true, daysLeft: 5)
        let otherAccountActive = SubscriptionStatus(subscribed: true, onTrial: false, daysLeft: nil)

        // Account A: refresh #1 completes normally — gates open on a trial status.
        async let first: Void = store.refresh()
        try? await Task.sleep(for: .milliseconds(50))
        checker.release(0, with: trial)
        await first
        XCTAssertEqual(store.status, trial)

        // Refresh #2 starts and blocks in check(); before it resolves, the session ends and
        // `reset()` fires — simulating the same-device account-switch race the addendum names.
        async let second: Void = store.refresh()
        try? await Task.sleep(for: .milliseconds(50))
        store.reset()
        XCTAssertNil(store.status)
        XCTAssertTrue(store.isLoading)

        // Refresh #2 finally resolves — with a *different* account's active status, standing in
        // for whatever A's in-flight request happens to return after B has already signed in.
        checker.release(1, with: otherAccountActive)
        await second

        XCTAssertNil(store.status)          // stale resolve dropped, not applied over B's reset state
        XCTAssertTrue(store.isLoading)      // B's fail-open state untouched by A's late resolve
        XCTAssertTrue(store.canAddContent)  // still fails open (isLoading), not falsely closed either
        XCTAssertNil(store.lastError)
    }

    // Web parity (plan-4 Task 6b, commit 42c2e67: "fail-open subscription errors"): a transient
    // error checking subscription status does NOT wipe the last known status — an errored check
    // means unknown, not unsubscribed. Keeps gates open on a prior success while connection
    // hiccups or other transient failures resolve. Non-cancellation errors (distinguished from
    // cancellation by the early guard above) still set `lastError` for UI reporting.
    func testTransientErrorKeepsLastKnownStatus() async {
        let checker = StubChecker()
        let trial = SubscriptionStatus(subscribed: false, onTrial: true, daysLeft: 5)
        checker.results = [.success(trial), .failure(CaptureError.badStatus(500))]
        let store = SubscriptionStore(checker: checker)

        // First refresh succeeds — gates open on a trial status.
        await store.refresh()
        XCTAssertEqual(store.status, trial)
        XCTAssertTrue(store.canAddContent)
        XCTAssertNil(store.lastError)

        // Second refresh hits a transient error.
        await store.refresh()

        // Status must remain: unknown ≠ unsubscribed, so gates stay open.
        XCTAssertEqual(store.status, trial)
        XCTAssertTrue(store.canAddContent)
        // Error is recorded for UI to show.
        XCTAssertEqual(store.lastError, "Couldn't check your subscription status.")
    }
}
