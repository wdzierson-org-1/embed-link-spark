import XCTest
@testable import StashKit

final class ItemRulesTests: XCTestCase {
    func fixture(type: ItemType = .text, title: String? = nil, content: String? = nil,
                 url: String? = nil, description: String? = nil, summary: String? = nil,
                 filePath: String? = nil, supplementalNote: String? = nil) -> Item {
        Item(id: UUID(), type: type, title: title, content: content, url: url,
             filePath: filePath, description: description, summary: summary,
             pageBody: nil, supplementalNote: supplementalNote, mimeType: nil,
             isPublic: false, createdAt: .now, fileSize: nil, attributes: ItemAttributes())
    }

    func testSearchMatchesSameFieldsAsWeb() {
        // web searches title, content, description, url, supplemental_note — NOT summary/page_body
        XCTAssertTrue(fixture(title: "Tokyo Guide").matches(searchQuery: "tokyo"))
        XCTAssertTrue(fixture(url: "https://ramen.jp").matches(searchQuery: "RAMEN"))
        XCTAssertTrue(fixture(supplementalNote: "sticky").matches(searchQuery: "stick"))
        XCTAssertFalse(fixture(summary: "only in summary").matches(searchQuery: "only"))
        XCTAssertTrue(fixture().matches(searchQuery: "   "))   // blank query matches all
    }

    func testDocumentProcessingFlag() {
        XCTAssertTrue(fixture(type: .document).isProcessingDocument)
        XCTAssertFalse(fixture(type: .document, summary: "done").isProcessingDocument)
        XCTAssertFalse(fixture(type: .image).isProcessingDocument)
    }

    /// A failed extraction (e.g. a PDF over OpenAI's 50 MB file-input limit) settles enrichment
    /// `partial` and never writes a summary — the card must stop shimmering, not stay redacted.
    func testDocumentStopsProcessingOnceEnrichmentSettles() {
        func document(enrichment status: String) -> Item {
            var item = fixture(type: .document)
            item.attributes = ItemAttributes(extra: ["enrichment": .object([
                "status": .string(status), "updated_at": .string(ISO8601DateFormatter().string(from: .now))
            ])])
            return item
        }
        XCTAssertTrue(document(enrichment: "pending").isProcessingDocument)
        XCTAssertFalse(document(enrichment: "partial").isProcessingDocument)
        XCTAssertFalse(document(enrichment: "complete").isProcessingDocument)
    }

    /// The web's 10-minute reading window (DOCUMENT_READING_WINDOW_MS): a row saved before the
    /// enrichment key existed, whose extraction failed, must not shimmer forever either.
    func testDocumentStopsProcessingTenMinutesAfterSave() {
        var old = fixture(type: .document)
        old.createdAt = Date.now.addingTimeInterval(-11 * 60)
        XCTAssertFalse(old.isProcessingDocument)
        var fresh = fixture(type: .document)
        fresh.createdAt = Date.now.addingTimeInterval(-9 * 60)
        XCTAssertTrue(fresh.isProcessingDocument)
    }

    func testContentTabs() {
        XCTAssertEqual(contentTabsConfig(for: .link).tabs.map(\.key), [.summary, .original])
        XCTAssertEqual(contentTabsConfig(for: .audio).tabs.map(\.key), [.summary, .transcript])
        XCTAssertEqual(contentTabsConfig(for: .audio).defaultTab, .transcript)
        XCTAssertEqual(contentTabsConfig(for: .image).tabs.map(\.key), [.notes])
    }

    func testThumbnailRule() {
        XCTAssertNil(fixture().thumbnailURL)
        XCTAssertEqual(fixture(filePath: "https://cdn.example.com/x.jpg").thumbnailURL?.host(),
                       "cdn.example.com")
        XCTAssertEqual(fixture(filePath: "u1/pic.png").thumbnailURL,
                       StashConfig.publicStorageURL(for: "u1/pic.png"))
    }
}
