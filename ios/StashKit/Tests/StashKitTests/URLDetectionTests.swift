import XCTest
@testable import StashKit

/// The capture composer's URL helpers (formerly `MessageRoutingTests`, whose chat-as-capture
/// `classifyMessage` cases left with the router in plan 15 — Ask is retrieval-only).
final class URLDetectionTests: XCTestCase {
    func testDetectFirstURL() {
        XCTAssertEqual(detectFirstURL(in: "https://example.com/a?b=c"), "https://example.com/a?b=c")
        XCTAssertEqual(detectFirstURL(in: "read this https://example.com/post."), "https://example.com/post.",
                       "Raw match — trailing punctuation is the caller's to strip")
        XCTAssertEqual(detectFirstURL(in: "https://a.com and https://b.com"), "https://a.com", "First URL only")
        XCTAssertEqual(detectFirstURL(in: "note: check http://x.com"), "http://x.com",
                       "A 'note:' prefix no longer means anything special")
        // Non-BMP / CRLF regressions (grapheme vs UTF-16 offsets).
        XCTAssertEqual(detectFirstURL(in: "😀 https://example.com note-after"), "https://example.com")
        XCTAssertEqual(detectFirstURL(in: "line one\r\nhttps://a.co"), "https://a.co")
        XCTAssertNil(detectFirstURL(in: "what did I save about tokyo?"))
        XCTAssertNil(detectFirstURL(in: "ftp://not-http.example"))
    }

    func testStripTrailingPunctuation() {
        XCTAssertEqual(stripTrailingPunctuation("https://example.com/post."), "https://example.com/post")
        XCTAssertEqual(stripTrailingPunctuation("https://x.com/y),"), "https://x.com/y")
        XCTAssertEqual(stripTrailingPunctuation("https://x.com/wiki/(a)b"), "https://x.com/wiki/(a)b")
        XCTAssertEqual(stripTrailingPunctuation("https://x.com/?!;]"), "https://x.com/")
    }

    func testWholeWebURLPreservesEncodedQueryAndFragment() {
        let url = "https://example.com/video?name=navy%20jacket&filter=%3C%22tag%22%3E%5C%60&start=38#part%202"
        XCTAssertEqual(detectWholeWebURL(in: " \n\(url)\r\n"), url)
    }

    func testWholeWebURLRejectsRawControlCharacters() {
        for code in Array(0...31) + [127] {
            let control = String(UnicodeScalar(code)!)
            XCTAssertNil(detectWholeWebURL(in: "https://example.com/a\(control)b"), "raw control \(code)")
        }
    }
}
