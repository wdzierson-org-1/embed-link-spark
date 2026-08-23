import XCTest
@testable import StashKit

/// `ShareAbandonTracker` moved into StashKit in Task 7 fix round 2 specifically so its
/// consumed/discard/late-track contract could be locked down under `swift test` rather than relying
/// on live/manual verification a third time — this is the second fix round to touch this exact
/// class. Mirrors `StagedFileStoreTests`' own temp-directory-per-test setup. `@MainActor` on the
/// whole test class (same pattern `SubscriptionStoreTests` uses for its own `@MainActor` subject)
/// so every call below is a same-actor, non-suspending call — exactly how `ShareComposeView`/
/// `ShareViewController` (both implicitly MainActor-isolated) call this type in production.
@MainActor
final class ShareAbandonTrackerTests: XCTestCase {
    var dir: URL!
    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appending(path: "abandon-tracker-\(UUID().uuidString)")
    }
    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    /// Mirrors `ShareIntakeTests.stageFile` — stages real bytes so `discard` has an actual file on
    /// disk to remove, and existence checks are meaningful.
    private func stageFile(store: StagedFileStore, ext: String = "png") throws -> URL {
        let source = FileManager.default.temporaryDirectory.appending(path: "src-\(UUID().uuidString).\(ext)")
        try Data([0x01, 0x02, 0x03]).write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }
        return try store.stage(from: source, fileExtension: ext)
    }

    // MARK: - Baseline discard/consume contract (Fix round 1, now testable)

    func testDiscardIfAbandonedRemovesTrackedFileObjectsWhenNotConsumed() throws {
        let store = StagedFileStore(userId: UUID(), directory: dir)
        let staged = try stageFile(store: store)
        let tracker = ShareAbandonTracker()

        tracker.track(objects: [.file(stagedURL: staged, mimeType: "image/png", fileName: nil, durationS: nil)], staging: store)
        tracker.discardIfAbandoned()

        XCTAssertFalse(FileManager.default.fileExists(atPath: staged.path), "an abandoned share's staged file must be discarded")
    }

    func testDiscardIfAbandonedLeavesNonFileObjectsAlone() throws {
        let store = StagedFileStore(userId: UUID(), directory: dir)
        let tracker = ShareAbandonTracker()

        tracker.track(objects: [.url("https://example.com"), .text("hello")], staging: store)

        // Must not crash / throw on non-.file cases — there is nothing to discard for either.
        tracker.discardIfAbandoned()
    }

    func testMarkConsumedPreventsDiscardIfAbandoned() throws {
        let store = StagedFileStore(userId: UUID(), directory: dir)
        let staged = try stageFile(store: store)
        let tracker = ShareAbandonTracker()
        tracker.track(objects: [.file(stagedURL: staged, mimeType: "image/png", fileName: nil, durationS: nil)], staging: store)

        tracker.markConsumed()
        tracker.discardIfAbandoned()

        XCTAssertTrue(FileManager.default.fileExists(atPath: staged.path),
                      "a file already handed off to ShareIntake must never be discarded by the tracker")
    }

    func testTrackIsANoOpAfterConsumed() throws {
        let store = StagedFileStore(userId: UUID(), directory: dir)
        let staged = try stageFile(store: store)
        let tracker = ShareAbandonTracker()
        tracker.markConsumed()

        // A track() call arriving after consumption (shouldn't happen in practice — load() always
        // precedes save() — but must be inert if it ever did) must not re-arm discarding.
        tracker.track(objects: [.file(stagedURL: staged, mimeType: "image/png", fileName: nil, durationS: nil)], staging: store)
        tracker.discardIfAbandoned()

        XCTAssertTrue(FileManager.default.fileExists(atPath: staged.path))
    }

    func testDiscardIfAbandonedWithNothingTrackedIsANoOp() {
        let tracker = ShareAbandonTracker()
        // No track() call at all (the `.noSession` branch never stages anything) — must not crash.
        tracker.discardIfAbandoned()
    }

    func testDiscardIfAbandonedIsSafeToCallTwice() throws {
        let store = StagedFileStore(userId: UUID(), directory: dir)
        let staged = try stageFile(store: store)
        let tracker = ShareAbandonTracker()
        tracker.track(objects: [.file(stagedURL: staged, mimeType: "image/png", fileName: nil, durationS: nil)], staging: store)

        tracker.discardIfAbandoned()
        tracker.discardIfAbandoned()   // must not throw/crash on an already-removed file

        XCTAssertFalse(FileManager.default.fileExists(atPath: staged.path))
    }

    // MARK: - Fix round 2: late track() after the view already disappeared mid-load

    /// The exact residual gap fix round 2 closes: a swipe fires `discardIfAbandoned()` while
    /// `ProviderLoader.load()` is still staging files, so `track()` hasn't run yet and that call
    /// finds nothing. `track()` must catch up the instant it finally runs, discarding everything
    /// `load()` staged — not leaving it for `sweepOrphans` to recover minutes later.
    func testLateTrackAfterDiscardAlreadyRanDiscardsImmediately() throws {
        let store = StagedFileStore(userId: UUID(), directory: dir)
        let staged = try stageFile(store: store)
        let tracker = ShareAbandonTracker()

        // Simulates viewDidDisappear firing before load() has staged anything the tracker knows
        // about yet: staging is still nil, so this is a real no-op, exactly like production.
        tracker.discardIfAbandoned()
        XCTAssertTrue(FileManager.default.fileExists(atPath: staged.path), "sanity: nothing to discard yet")

        // load() finishes AFTER the swipe and hands the tracker its full, final list.
        tracker.track(objects: [.file(stagedURL: staged, mimeType: "image/png", fileName: nil, durationS: nil)], staging: store)

        XCTAssertFalse(FileManager.default.fileExists(atPath: staged.path),
                       "track() arriving after the view already disappeared must discard immediately")
    }

    /// Multiple files staged progressively — ALL of them (not just ones staged after the swipe)
    /// must be caught by the late track() catch-up, since none of them were registered before the
    /// swipe fired the first (no-op) discardIfAbandoned() call.
    func testLateTrackDiscardsEveryFileEvenOnesStagedBeforeTheSwipe() throws {
        let store = StagedFileStore(userId: UUID(), directory: dir)
        let first = try stageFile(store: store)
        let second = try stageFile(store: store)
        let tracker = ShareAbandonTracker()

        tracker.discardIfAbandoned()   // the mid-load swipe
        tracker.track(objects: [
            .file(stagedURL: first, mimeType: "image/png", fileName: nil, durationS: nil),
            .file(stagedURL: second, mimeType: "image/png", fileName: nil, durationS: nil),
        ], staging: store)

        XCTAssertFalse(FileManager.default.fileExists(atPath: first.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: second.path))
    }

    /// If Save was tapped (and therefore consumed) before the late track() arrives, the catch-up
    /// path must still respect `consumed` — this can't actually happen in production (viewDidDisappear
    /// firing before load() completes means the UI is already gone, so Save can't be tapped), but
    /// the tracker's own invariant ("consumed always wins") must hold regardless of call order.
    func testLateTrackAfterDiscardRanRespectsConsumedIfSetFirst() throws {
        let store = StagedFileStore(userId: UUID(), directory: dir)
        let staged = try stageFile(store: store)
        let tracker = ShareAbandonTracker()

        tracker.discardIfAbandoned()
        tracker.markConsumed()
        tracker.track(objects: [.file(stagedURL: staged, mimeType: "image/png", fileName: nil, durationS: nil)], staging: store)

        XCTAssertTrue(FileManager.default.fileExists(atPath: staged.path),
                      "consumed must win even against the late-track discard catch-up")
    }
}
