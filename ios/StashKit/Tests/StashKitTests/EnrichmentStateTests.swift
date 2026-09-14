import XCTest
@testable import StashKit

final class EnrichmentStateTests: XCTestCase {
    func testPendingExpiresAndTerminalStatesRemainReadable() {
        let now = Date(timeIntervalSince1970: 1_000)
        func attrs(_ status: String, timestamp: String) -> ItemAttributes {
            ItemAttributes(extra: ["enrichment": .object([
                "status": .string(status), "updated_at": .string(timestamp)
            ])])
        }
        XCTAssertEqual(attrs("pending", timestamp: "1970-01-01T00:15:00.000Z").enrichmentStatus(at: now), "pending")
        XCTAssertEqual(attrs("pending", timestamp: "1970-01-01T00:01:00Z").enrichmentStatus(at: now), "partial")
        XCTAssertEqual(attrs("complete", timestamp: "1970-01-01T00:01:00Z").enrichmentStatus(at: now), "complete")
        XCTAssertEqual(attrs("partial", timestamp: "1970-01-01T00:01:00Z").enrichmentStatus(at: now), "partial")
    }

    func testLegacyAndMalformedTimestampsDoNotSpinForever() {
        XCTAssertNil(ItemAttributes().enrichmentStatus(at: Date()))
        let malformed = ItemAttributes(extra: ["enrichment": .object([
            "status": .string("pending"), "updated_at": .string("invalid")
        ])])
        XCTAssertEqual(malformed.enrichmentStatus(at: Date()), "partial")
    }
}
