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

    func testContentTabs() {
        XCTAssertEqual(contentTabsConfig(for: .link).tabs.map(\.key), [.summary, .original, .notes])
        XCTAssertEqual(contentTabsConfig(for: .audio).tabs.map(\.key), [.notes, .transcript])
        XCTAssertEqual(contentTabsConfig(for: .audio).defaultTab, .notes)
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
