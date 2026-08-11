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
}
