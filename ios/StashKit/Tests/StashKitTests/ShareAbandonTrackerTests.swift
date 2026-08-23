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

    /// Final fix wave: `ShareComposeView.cancel()` now delegates directly to
    /// `discardIfAbandoned()` (see that method's own doc comment for the BLOCKER this closed)
    /// instead of hand-rolling its own discard loop + `markConsumed()`. That means a Cancel TAP
    /// landing mid-load — `showsCancel` includes `.loading`, so this is genuinely reachable, not
    /// hypothetical — now produces exactly this discardIfAbandoned()-then-late-track() ordering,
    /// the same mechanism `testLateTrackAfterDiscardAlreadyRanDiscardsImmediately` above already
    /// covers for an interactive swipe. Kept as its own test (not folded into that one) specifically
    /// to document the Cancel-tap call site as a first-class caller of this exact ordering, since
    /// that's the scenario this fix wave was written to close.
    func testCancelDuringLoadDiscardsFilesOnceLoadCatchesUp() throws {
        let store = StagedFileStore(userId: UUID(), directory: dir)
        let staged = try stageFile(store: store)
        let tracker = ShareAbandonTracker()

        // Cancel tapped while ProviderLoader.load() is still staging files: track() hasn't run
        // yet, so the tracker has nothing recorded and this call is a real no-op — exactly like
        // production.
        tracker.discardIfAbandoned()
        XCTAssertTrue(FileManager.default.fileExists(atPath: staged.path), "sanity: nothing to discard yet")

        // load() finishes AFTER the Cancel tap and hands the tracker its full, final list.
        tracker.track(objects: [.file(stagedURL: staged, mimeType: "image/png", fileName: nil, durationS: nil)], staging: store)

        XCTAssertFalse(FileManager.default.fileExists(atPath: staged.path),
                       "a Cancel tap mid-load must discard every file load() goes on to stage, once load() catches the tracker up")
    }

    /// If Save was tapped (and therefore consumed) before the late track() arrives, the catch-up
    /// path must still respect `consumed` — the tracker's own invariant ("consumed always wins")
    /// must hold regardless of call order. An earlier version of this comment claimed the whole
    /// scenario "can't happen in production" reasoning only about Save (viewDidDisappear firing
    /// before load() completes implies the UI is already gone, so Save can't be tapped) — true as
    /// far as it went, but incomplete: Cancel was ALSO tappable mid-load (`showsCancel` includes
    /// `.loading`), and the PRE-fix-wave `cancel()` called `markConsumed()` directly rather than
    /// going through `discardIfAbandoned()`, so a mid-load Cancel tap could reach a
    /// consumed-before-track state too — the exact BLOCKER this fix wave closed (see
    /// `ShareComposeView.cancel()`'s own doc comment). Now that `cancel()` delegates to
    /// `discardIfAbandoned()` instead of calling `markConsumed()` itself, `markConsumed()` is
    /// called from exactly one call site (`save()`), so THIS specific ordering — discard already
    /// having run, then `consumed` becoming true, before a late `track()` arrives — genuinely can
    /// only happen via Save now, and Save can't be tapped once the UI backing it is already gone.
    /// Retained as a regression guard on the invariant itself, independent of reachability.
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
