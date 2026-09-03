import XCTest
@testable import StashKit

final class DebouncerTests: XCTestCase {
    func testCoalescesBurstsToOneCall() async throws {
        let counter = Counter()
        let debouncer = Debouncer(interval: .milliseconds(50))
        for _ in 0..<5 { await debouncer.call { await counter.increment() } }
        try await Task.sleep(for: .milliseconds(200))
        let count = await counter.value
        XCTAssertEqual(count, 1)
    }

    /// `cancel()` (Plan 8, fix round 1) — `NotesEditorModel.flushNow`'s own explicit-save path
    /// calls this before running its immediate save, so a pending debounced call from the same
    /// draft can't ALSO fire afterward.
    func testCancelPreventsThePendingCallFromFiring() async throws {
        let counter = Counter()
        let debouncer = Debouncer(interval: .milliseconds(50))
        await debouncer.call { await counter.increment() }
        await debouncer.cancel()
        try await Task.sleep(for: .milliseconds(200))
        let count = await counter.value
        XCTAssertEqual(count, 0, "a cancelled call must never fire")
    }
}
actor Counter { var value = 0; func increment() { value += 1 } }
