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
}
actor Counter { var value = 0; func increment() { value += 1 } }
