import XCTest
@testable import StashKit

final class RecordingSyncer: EmbeddingSyncing, @unchecked Sendable {
    var calls: [(UUID, String)] = []
    func replaceEmbeddings(itemId: UUID, text: String) async throws { calls.append((itemId, text)) }
}

final class EmbeddingRefresherTests: XCTestCase {
    func fixture(title: String) -> Item {
        Item(id: UUID(uuidString: "6B1E0A4E-9F6A-4D5E-8F2F-0E7C1B2D3A4B")!, type: .text,
             title: title, content: "body", url: "https://x.com", filePath: nil,
             description: "desc", summary: "sum", pageBody: "pb", supplementalNote: "sn",
             mimeType: nil, isPublic: false, createdAt: .now, fileSize: nil, attributes: ItemAttributes())
    }
    func testEmbeddingTextOrderMatchesWeb() {
        let text = buildEmbeddingText(from: fixture(title: "T"))
        XCTAssertEqual(text, "T desc body sn https://x.com sum pb")
    }
    func testLatestRowWinsAfterIdle() async throws {
        let syncer = RecordingSyncer()
        let refresher = EmbeddingRefresher(syncer: syncer, idle: .milliseconds(60))
        await refresher.schedule(fixture(title: "first"))
        await refresher.schedule(fixture(title: "second"))
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(syncer.calls.count, 1)
        XCTAssertTrue(syncer.calls[0].1.hasPrefix("second"))
    }
}
