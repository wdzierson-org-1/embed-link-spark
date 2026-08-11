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
}
