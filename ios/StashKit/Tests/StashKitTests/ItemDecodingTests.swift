import XCTest
@testable import StashKit

final class ItemDecodingTests: XCTestCase {
    let decoder = Item.decoder   // JSONDecoder configured by the model file

    func testDecodesListRow() throws {
        let json = """
        {"id":"6b1e0a4e-9f6a-4d5e-8f2f-0e7c1b2d3a4b","type":"link","title":"A page",
         "content":null,"url":"https://example.com","file_path":"u1/x.png",
         "description":"short","summary":null,"created_at":"2026-08-10T14:03:22.123456+00:00",
         "mime_type":null,"is_public":false,"supplemental_note":null}
        """.data(using: .utf8)!
        let item = try decoder.decode(Item.self, from: json)
        XCTAssertEqual(item.type, .link)
        XCTAssertEqual(item.title, "A page")
        XCTAssertNil(item.pageBody)
        XCTAssertEqual(Calendar(identifier: .gregorian).component(.year,
            from: item.createdAt), 2026)
    }

    func testUnknownTypeDoesNotThrow() throws {
        let json = """
        {"id":"6b1e0a4e-9f6a-4d5e-8f2f-0e7c1b2d3a4c","type":"hologram","title":null,
         "content":null,"url":null,"file_path":null,"description":null,"summary":null,
         "created_at":"2026-08-10T14:03:22+00:00","mime_type":null,"is_public":true,
         "supplemental_note":null}
        """.data(using: .utf8)!
        XCTAssertEqual(try decoder.decode(Item.self, from: json).type, .unknown)
    }

    /// `file_size` and `attributes` are the two Task 3 additions: `file_size` decodes like any
    /// other optional column, `attributes` decodes typed (`location`) while still round-tripping
    /// unknown keys via `ItemAttributes.extra`.
    func testItemDecodesAttributesAndFileSize() throws {
        let json = """
        {"id":"6b1e0a4e-9f6a-4d5e-8f2f-0e7c1b2d3a4d","type":"image","title":"Pic",
         "content":null,"url":null,"file_path":"u1/x.png","description":null,"summary":null,
         "created_at":"2026-08-10T14:03:22+00:00","mime_type":"image/png","file_size":204800,
         "is_public":false,"supplemental_note":null,
         "attributes":{"location":{"label":"Home","source":"manual"},"mood":"good"}}
        """.data(using: .utf8)!
        let item = try decoder.decode(Item.self, from: json)
        XCTAssertEqual(item.fileSize, 204800)
        XCTAssertEqual(item.attributes.location?.label, "Home")
        XCTAssertEqual(item.attributes.extra["mood"], .string("good"))
        XCTAssertFalse(item.attributes.isEmpty)
    }

    /// A missing `attributes` column (list rows that predate the migration, or any select that
    /// omits it) must decode to an empty `ItemAttributes`, never throw.
    func testItemDecodesMissingAttributesColumnAsEmpty() throws {
        let json = """
        {"id":"6b1e0a4e-9f6a-4d5e-8f2f-0e7c1b2d3a4e","type":"text","title":null,
         "content":null,"url":null,"file_path":null,"description":null,"summary":null,
         "created_at":"2026-08-10T14:03:22+00:00","mime_type":null,"is_public":false,
         "supplemental_note":null}
        """.data(using: .utf8)!
        let item = try decoder.decode(Item.self, from: json)
        XCTAssertTrue(item.attributes.isEmpty)
        XCTAssertNil(item.fileSize)
    }

    /// A `null` (not missing) `attributes` column — same tolerant fallback as missing.
    func testItemDecodesNullAttributesColumnAsEmpty() throws {
        let json = """
        {"id":"6b1e0a4e-9f6a-4d5e-8f2f-0e7c1b2d3a4f","type":"text","title":null,
         "content":null,"url":null,"file_path":null,"description":null,"summary":null,
         "created_at":"2026-08-10T14:03:22+00:00","mime_type":null,"is_public":false,
         "supplemental_note":null,"attributes":null,"file_size":null}
        """.data(using: .utf8)!
        let item = try decoder.decode(Item.self, from: json)
        XCTAssertTrue(item.attributes.isEmpty)
        XCTAssertNil(item.fileSize)
    }

    /// Review finding #1: before the fix, a single malformed known `attributes` key anywhere in
    /// a page threw out of `ItemAttributes.init(from:)`, which threw out of `Item.init(from:)`,
    /// which failed the whole `[Item]` array decode — `ItemStore` would then set `loadError` for
    /// the entire library, deterministically and permanently (pull-to-retry re-runs the same
    /// decode and fails the same way). All 3 items here must decode; only the middle one's
    /// `location` falls back to `extra`.
    func testArrayDecodeSurvivesOneItemsMalformedKnownAttributeKey() throws {
        let json = """
        [
          {"id":"6b1e0a4e-9f6a-4d5e-8f2f-0e7c1b2d3a51","type":"text","title":null,"content":null,
           "url":null,"file_path":null,"description":null,"summary":null,
           "created_at":"2026-08-10T14:03:22+00:00","mime_type":null,"is_public":false,
           "supplemental_note":null,"attributes":{"location":{"label":"L1","source":"manual"}}},
          {"id":"6b1e0a4e-9f6a-4d5e-8f2f-0e7c1b2d3a52","type":"text","title":null,"content":null,
           "url":null,"file_path":null,"description":null,"summary":null,
           "created_at":"2026-08-10T14:03:22+00:00","mime_type":null,"is_public":false,
           "supplemental_note":null,"attributes":{"location":"not-an-object"}},
          {"id":"6b1e0a4e-9f6a-4d5e-8f2f-0e7c1b2d3a53","type":"text","title":null,"content":null,
           "url":null,"file_path":null,"description":null,"summary":null,
           "created_at":"2026-08-10T14:03:22+00:00","mime_type":null,"is_public":false,
           "supplemental_note":null,"attributes":{"location":{"label":"L3","source":"manual"}}}
        ]
        """.data(using: .utf8)!
        let items = try decoder.decode([Item].self, from: json)
        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(items[0].attributes.location?.label, "L1")
        XCTAssertNil(items[1].attributes.location)
        XCTAssertEqual(items[1].attributes.extra["location"], .string("not-an-object"))
        XCTAssertEqual(items[2].attributes.location?.label, "L3")
    }

    // Pin: these strings are the wire contract with the web ITEM_LIST_COLUMNS selects.
    // A drift here (column renamed/reordered/added upstream) should fail loudly, not silently
    // under- or over-fetch columns.
    func testListColumnsMatchWebContractLiterally() {
        XCTAssertEqual(Item.listColumns,
            "id,type,title,content,url,file_path,description,summary,created_at,mime_type,file_size,is_public,supplemental_note,attributes")
        XCTAssertEqual(Item.detailColumns, Item.listColumns + ",page_body")
    }
}
