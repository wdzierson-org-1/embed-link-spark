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
}
