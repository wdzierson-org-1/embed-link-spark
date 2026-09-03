import XCTest
@testable import StashKit

/// `SaveGeneration` (Plan 8, fix round 1, review finding #2) — the stale-save-response guard
/// extracted so `ItemDetailView`'s field-vs-notes autosave race is independently testable outside
/// a View. The `@MainActor` isolation itself (matching `ItemStore`/`SubscriptionStore`'s own
/// generation counters) isn't separately exercised here — these tests only need to run on the
/// main actor themselves (`@MainActor` on the class), which async XCTest methods do freely.
@MainActor
final class SaveGenerationTests: XCTestCase {
    func testNextIncrementsMonotonically() {
        let generation = SaveGeneration()
        XCTAssertEqual(generation.next(), 1)
        XCTAssertEqual(generation.next(), 2)
        XCTAssertEqual(generation.next(), 3)
    }

    func testIsLatestTrueOnlyForTheMostRecentGeneration() {
        let generation = SaveGeneration()
        let first = generation.next()
        let second = generation.next()
        XCTAssertFalse(generation.isLatest(first), "an older generation must no longer read as latest")
        XCTAssertTrue(generation.isLatest(second), "the most recently issued generation is latest")
    }

    /// Simulates the exact race this type exists for: two saves dispatch in order (field, then
    /// notes), but their responses land REVERSED (notes' response arrives first). Only the
    /// genuinely-latest dispatch (notes, generation 2) should ever pass `isLatest`.
    func testOutOfOrderResponsesOnlyLatestDispatchWins() {
        let generation = SaveGeneration()
        let fieldSaveGeneration = generation.next()   // dispatched first
        let notesSaveGeneration = generation.next()   // dispatched second, still the newest

        // Notes' response arrives first.
        XCTAssertTrue(generation.isLatest(notesSaveGeneration))
        // Field's response arrives after, but it's the STALE one — must be dropped.
        XCTAssertFalse(generation.isLatest(fieldSaveGeneration))
    }
}
