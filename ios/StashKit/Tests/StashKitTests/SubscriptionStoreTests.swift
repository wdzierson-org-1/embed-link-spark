import XCTest
@testable import StashKit

final class StubChecker: SubscriptionChecking, @unchecked Sendable {
    var results: [Result<SubscriptionStatus, Error>] = []
    var trialCalls = 0
    private(set) var checkCalls = 0
    func check() async throws -> SubscriptionStatus {
        checkCalls += 1
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
    /// Simulates a check whose request gets cancelled mid-flight (surfacing as `CancellationError`)
    /// — releasing with it directly is simpler and more deterministic than racing a real
    /// `Task.cancel()` against this continuation, and exercises the exact same catch-block path.
    func releaseWithCancellation(_ index: Int) { gates[index].resume(throwing: CancellationError()) }
}

/// Records every `gateCacheWrite` call in order (`nil` = the key was removed).
final class GateCacheRecorder: @unchecked Sendable {
    private(set) var writes: [Bool?] = []
    func record(_ value: Bool?) { writes.append(value) }
}

/// A settable clock for the freshness throttle.
final class SubscriptionTestClock: @unchecked Sendable {
    var now = Date(timeIntervalSince1970: 1_800_000_000)
}

@MainActor
final class SubscriptionStoreTests: XCTestCase {
    private let active = SubscriptionStatus(subscribed: true, onTrial: false, daysLeft: nil)
    private let trial = SubscriptionStatus(subscribed: false, onTrial: true, daysLeft: 5)
    private let lapsed = SubscriptionStatus(subscribed: false, onTrial: false, daysLeft: nil)

    func testActiveSubscriptionOpensGates() async {
        let checker = StubChecker()
        checker.results = [.success(active)]
        let store = SubscriptionStore(checker: checker)
        await store.refresh()
        XCTAssertTrue(store.canAddContent)
        XCTAssertTrue(store.statusKnown)
        XCTAssertEqual(checker.trialCalls, 0)
    }

    func testNoSubscriptionSelfHealsOnce() async {
        let checker = StubChecker()
        let trial14 = SubscriptionStatus(subscribed: false, onTrial: true, daysLeft: 14)
        checker.results = [.success(lapsed), .success(trial14), .success(lapsed)]
        let store = SubscriptionStore(checker: checker)
        await store.refresh()
        XCTAssertEqual(checker.trialCalls, 1)
        XCTAssertTrue(store.canAddContent)           // trial picked up on re-check
        await store.refresh(force: true)             // later refresh sees `lapsed` again…
        XCTAssertEqual(checker.trialCalls, 1)        // …but never re-creates a trial
        XCTAssertFalse(store.canAddContent)
    }

    // MARK: - Plan 15 (H2): fail open until the server has answered

    // Web parity (`hasAccess = loading || !statusKnown || …`): a first check that fails (offline, a
    // 5xx, a Stripe hiccup) is "unknown", not "unsubscribed" — the gates stay open (the server
    // enforces the paywall itself) and the share extension's cache is not written, so a paying
    // user's offline launch no longer disables Save/Voice/Ask or the share sheet.
    func testErrorWithNoPriorStatusFailsOpenUntilKnown() async {
        let checker = StubChecker()                  // empty results → throw
        let recorder = GateCacheRecorder()
        let store = SubscriptionStore(checker: checker, gateCacheWrite: { recorder.record($0) })
        XCTAssertTrue(store.canAddContent)           // pre-first-refresh: loading state fail-open
        await store.refresh()
        XCTAssertFalse(store.isLoading)
        XCTAssertFalse(store.statusKnown)
        XCTAssertNil(store.status)
        XCTAssertTrue(store.canAddContent)
        XCTAssertTrue(store.canUseAI)
        XCTAssertEqual(store.lastError, "Couldn't check your subscription status.")
        XCTAssertEqual(recorder.writes, [], "no definitive answer → the extension's cached gate is left alone")
    }

    // The flip side: once the server has definitively said "neither subscribed nor trialing", a
    // later failed check keeps the gates closed (unknown after known keeps the known answer).
    func testErrorAfterADefinitiveLapsedAnswerKeepsGatesClosed() async {
        let checker = StubChecker()
        checker.results = [.success(lapsed), .success(lapsed), .failure(URLError(.notConnectedToInternet))]
        let recorder = GateCacheRecorder()
        let store = SubscriptionStore(checker: checker, gateCacheWrite: { recorder.record($0) })
        await store.refresh()                         // lapsed, self-heal re-check still lapsed
        XCTAssertTrue(store.statusKnown)
        XCTAssertFalse(store.canAddContent)
        await store.refresh(force: true)              // offline
        XCTAssertFalse(store.canAddContent)
        XCTAssertEqual(store.status, lapsed)
        XCTAssertNotNil(store.lastError)
        XCTAssertEqual(recorder.writes, [false], "only the definitive answer is cached")
    }

    func testFailedFirstCheckThenSuccessBecomesKnown() async {
        let checker = StubChecker()
        checker.results = [.failure(CaptureError.badStatus(503)), .success(lapsed), .success(lapsed)]
        let recorder = GateCacheRecorder()
        let store = SubscriptionStore(checker: checker, gateCacheWrite: { recorder.record($0) })
        await store.refresh()
        XCTAssertTrue(store.canAddContent)            // unknown → open
        await store.refresh()                         // no success yet → not throttled
        XCTAssertTrue(store.statusKnown)
        XCTAssertFalse(store.canAddContent)
        XCTAssertNil(store.lastError)
        XCTAssertEqual(recorder.writes, [false])
    }

    // Closes review Important: `isLoading` must be a one-shot first-check flag (web parity —
    // useSubscription's `loading` is `useState(true)`, only ever set `false`, never re-armed).
    // A later refresh that reset `isLoading = true` at entry would transiently fail *open* for a
    // known-unsubscribed user for the duration of that network round-trip.
    func testLaterRefreshDoesNotReopenGatesWhileInFlight() async {
        let checker = GatedChecker()
        let store = SubscriptionStore(checker: checker)

        async let first: Void = store.refresh()          // blocks on gate 0 (initial check)
        try? await Task.sleep(for: .milliseconds(50))
        checker.release(0, with: lapsed)                 // not-subscribed → one-time self-heal fires
        try? await Task.sleep(for: .milliseconds(50))
        checker.release(1, with: lapsed)                 // self-heal's re-check, also not-subscribed
        await first
        XCTAssertFalse(store.canAddContent)              // gates closed once first refresh settles

        async let second: Void = store.refresh(force: true)   // triedTrial already true → one check
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertFalse(store.canAddContent)              // must NOT fail open mid-poll
        checker.release(2, with: lapsed)
        await second
        XCTAssertFalse(store.canAddContent)
    }

    // A cancelled check is not a failed check: before the Task 7 fix round, a cancellation wiped
    // `status`, closing every gate for an already-subscribed user.
    func testCancelledRefreshLeavesStatusAndGatesUnchanged() async {
        let checker = GatedChecker()
        let store = SubscriptionStore(checker: checker)

        async let first: Void = store.refresh()
        try? await Task.sleep(for: .milliseconds(50))
        checker.release(0, with: trial)
        await first
        XCTAssertEqual(store.status, trial)
        XCTAssertTrue(store.canAddContent)

        async let second: Void = store.refresh(force: true)
        try? await Task.sleep(for: .milliseconds(50))
        checker.releaseWithCancellation(1)
        await second

        XCTAssertEqual(store.status, trial)     // untouched — NOT wiped to nil
        XCTAssertTrue(store.canAddContent)      // gates stay open
        XCTAssertNil(store.lastError)           // no spurious error surfaced either
    }

    // Cancellation can surface from underneath `checker.check()`'s network call as a
    // transport-level `URLError(.cancelled)` instead of `CancellationError` — same handling.
    func testURLErrorCancelledTreatedAsCancellation() async {
        let checker = StubChecker()
        checker.results = [.success(trial), .failure(URLError(.cancelled))]
        let store = SubscriptionStore(checker: checker)

        await store.refresh()
        XCTAssertEqual(store.status, trial)
        XCTAssertTrue(store.canAddContent)

        await store.refresh(force: true)   // throws URLError(.cancelled), not CancellationError

        XCTAssertEqual(store.status, trial)
        XCTAssertTrue(store.canAddContent)
        XCTAssertNil(store.lastError)
    }

    // `reset()` (StashApp, on `.signedOut`) must put the store back in its exact pre-first-refresh
    // state so the next account's first refresh fails open identically to a fresh launch, gets its
    // own one-time trial self-heal, and isn't throttled by the previous account's last check.
    func testResetClearsStatusAndRearmsLoadingSelfHealAndThrottleAcrossAccounts() async {
        let checker = StubChecker()
        let trial14 = SubscriptionStatus(subscribed: false, onTrial: true, daysLeft: 14)
        checker.results = [.success(lapsed), .success(trial14)]
        let store = SubscriptionStore(checker: checker)

        // Account A: a successful refresh that self-heals once, gates open.
        await store.refresh()
        XCTAssertEqual(checker.trialCalls, 1)
        XCTAssertTrue(store.canAddContent)

        store.reset()
        XCTAssertNil(store.status)
        XCTAssertFalse(store.statusKnown)
        XCTAssertNil(store.lastError)
        XCTAssertTrue(store.isLoading)
        XCTAssertTrue(store.canAddContent)   // isLoading re-armed: fail-open, pre-first-check

        // Account B signs in moments later: its (non-forced) refresh must still ask the server
        // and self-heal AGAIN.
        checker.results = [.success(lapsed), .success(trial14)]
        await store.refresh()
        XCTAssertEqual(checker.checkCalls, 4)
        XCTAssertEqual(checker.trialCalls, 2)
        XCTAssertTrue(store.canAddContent)
    }

    // An in-flight `refresh()` started before sign-out can't clobber the next account's freshly
    // reset state when it resolves late.
    func testStaleRefreshCannotClobberAfterReset() async {
        let checker = GatedChecker()
        let store = SubscriptionStore(checker: checker)

        async let first: Void = store.refresh()
        try? await Task.sleep(for: .milliseconds(50))
        checker.release(0, with: trial)
        await first
        XCTAssertEqual(store.status, trial)

        async let second: Void = store.refresh(force: true)
        try? await Task.sleep(for: .milliseconds(50))
        store.reset()
        XCTAssertNil(store.status)
        XCTAssertTrue(store.isLoading)

        checker.release(1, with: active)   // whatever A's in-flight request returns, after B signed in
        await second

        XCTAssertNil(store.status)          // stale resolve dropped, not applied over B's reset state
        XCTAssertTrue(store.isLoading)      // B's fail-open state untouched by A's late resolve
        XCTAssertTrue(store.canAddContent)
        XCTAssertNil(store.lastError)
    }

    // Web parity ("fail-open subscription errors"): a transient error doesn't wipe the last known
    // status — an errored check means unknown, not unsubscribed.
    func testTransientErrorKeepsLastKnownStatus() async {
        let checker = StubChecker()
        checker.results = [.success(trial), .failure(CaptureError.badStatus(500))]
        let recorder = GateCacheRecorder()
        let store = SubscriptionStore(checker: checker, gateCacheWrite: { recorder.record($0) })

        await store.refresh()
        XCTAssertEqual(store.status, trial)
        XCTAssertTrue(store.canAddContent)
        XCTAssertNil(store.lastError)

        await store.refresh(force: true)

        XCTAssertEqual(store.status, trial)
        XCTAssertTrue(store.canAddContent)
        XCTAssertEqual(store.lastError, "Couldn't check your subscription status.")
        XCTAssertEqual(recorder.writes, [true], "the failed check wrote nothing")
    }

    // MARK: - Gate cache (share extension)

    func testRefreshWritesTheDefinitiveGateToTheCache() async {
        let checker = StubChecker()
        checker.results = [.success(active)]
        let recorder = GateCacheRecorder()
        let store = SubscriptionStore(checker: checker, gateCacheWrite: { recorder.record($0) })

        await store.refresh()

        XCTAssertEqual(recorder.writes, [true])
    }

    // The first answer is written as what the server said — not the pre-flip fail-open `true`
    // every first check briefly reads while `isLoading` is still set.
    func testFirstDefinitiveLapsedAnswerCachesClosed() async {
        let checker = StubChecker()
        checker.results = [.success(lapsed), .success(lapsed)]
        let recorder = GateCacheRecorder()
        let store = SubscriptionStore(checker: checker, gateCacheWrite: { recorder.record($0) })

        await store.refresh()

        XCTAssertEqual(recorder.writes, [false])
    }

    // `reset()` removes the cached gate ("unknown", which the extension treats as open) rather
    // than leaving the previous account's answer — open or closed — for the next one.
    func testResetRemovesTheCachedGate() async {
        let checker = StubChecker()
        checker.results = [.success(lapsed), .success(lapsed)]
        let recorder = GateCacheRecorder()
        let store = SubscriptionStore(checker: checker, gateCacheWrite: { recorder.record($0) })

        await store.refresh()
        XCTAssertEqual(recorder.writes, [false])
        XCTAssertFalse(store.canAddContent)

        store.reset()

        XCTAssertEqual(recorder.writes, [false, nil])
    }

    // MARK: - Plan 15 (snappiness): throttle + one check at a time

    func testNonForcedRefreshInsideTheFreshnessWindowSkipsTheNetwork() async {
        let clock = SubscriptionTestClock()
        let checker = StubChecker()
        checker.results = [.success(active), .success(active)]
        let store = SubscriptionStore(checker: checker, now: { clock.now })

        await store.refresh()
        XCTAssertEqual(checker.checkCalls, 1)

        clock.now += 60                    // a Control Center pull a minute later
        await store.refresh()
        XCTAssertEqual(checker.checkCalls, 1)

        clock.now += SubscriptionStore.freshnessInterval
        await store.refresh()
        XCTAssertEqual(checker.checkCalls, 2)
    }

    /// 6C carry (final wave): only an open answer is throttled. After a definitive "no" the very
    /// next foreground asks again — someone who just subscribed on the web gets in at once, not
    /// `freshnessInterval` later.
    func testADefinitiveNoIsNeverThrottled() async {
        let clock = SubscriptionTestClock()
        let checker = StubChecker()
        checker.results = [.success(lapsed), .success(lapsed), .success(active)]
        let store = SubscriptionStore(checker: checker, now: { clock.now })

        await store.refresh()                 // lapsed, and the one-time self-heal re-check agrees
        XCTAssertEqual(checker.checkCalls, 2)
        XCTAssertFalse(store.canAddContent)

        clock.now += 20                       // subscribed on the web, back in the app
        await store.refresh()

        XCTAssertEqual(checker.checkCalls, 3, "a closed gate is re-checked on every refresh")
        XCTAssertTrue(store.canAddContent)

        clock.now += 20                       // now open → the throttle applies again
        await store.refresh()
        XCTAssertEqual(checker.checkCalls, 3)
    }

    func testForcedRefreshAlwaysAsksTheServer() async {
        let clock = SubscriptionTestClock()
        let checker = StubChecker()
        checker.results = [.success(active), .success(trial)]
        let store = SubscriptionStore(checker: checker, now: { clock.now })

        await store.refresh()
        clock.now += 5
        await store.refresh(force: true)   // Settings, right after the launch check

        XCTAssertEqual(checker.checkCalls, 2)
        XCTAssertEqual(store.status, trial)
    }

    func testAFailedCheckDoesNotStartTheFreshnessWindow() async {
        let clock = SubscriptionTestClock()
        let checker = StubChecker()
        checker.results = [.failure(URLError(.timedOut)), .success(active)]
        let store = SubscriptionStore(checker: checker, now: { clock.now })

        await store.refresh()
        clock.now += 1
        await store.refresh()              // the next foreground tries again at once

        XCTAssertEqual(checker.checkCalls, 2)
        XCTAssertEqual(store.status, active)
    }

    // A cold launch fires the "signed in" refresh and the first `.active` refresh together; they
    // must share one `check-subscription` request.
    func testConcurrentRefreshesShareOneCheck() async {
        let checker = GatedChecker()
        let store = SubscriptionStore(checker: checker)

        async let launch: Void = store.refresh()
        async let foreground: Void = store.refresh()
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(checker.gates.count, 1)

        checker.release(0, with: active)
        await launch
        await foreground

        XCTAssertEqual(checker.gates.count, 1)
        XCTAssertEqual(store.status, active)
    }

    // Settings appearing while the launch check is still out joins it rather than sending a
    // second request.
    func testForcedRefreshJoinsTheCheckAlreadyInFlight() async {
        let checker = GatedChecker()
        let store = SubscriptionStore(checker: checker)

        async let launch: Void = store.refresh()
        try? await Task.sleep(for: .milliseconds(50))
        async let settings: Void = store.refresh(force: true)
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(checker.gates.count, 1)

        checker.release(0, with: trial)
        await launch
        await settings

        XCTAssertEqual(checker.gates.count, 1)
        XCTAssertEqual(store.status, trial)
    }

    // After a sign-out, the next account's refresh must not wait on (and inherit nothing from) the
    // previous account's check that was still in flight.
    func testRefreshAfterResetDoesNotJoinThePreviousAccountsCheck() async {
        let checker = GatedChecker()
        let store = SubscriptionStore(checker: checker)

        async let accountA: Void = store.refresh()
        try? await Task.sleep(for: .milliseconds(50))
        store.reset()
        async let accountB: Void = store.refresh()
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(checker.gates.count, 2, "B's refresh must ask the server itself")

        checker.release(1, with: active)
        await accountB
        XCTAssertEqual(store.status, active)

        checker.release(0, with: lapsed)   // A's answer lands late…
        await accountA
        XCTAssertEqual(store.status, active, "…and is dropped")
        XCTAssertTrue(store.canAddContent)
    }
}
