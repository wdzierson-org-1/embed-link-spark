import XCTest
@testable import StashKit

final class MessageRoutingTests: XCTestCase {
    func testRouting() {
        let cases: [(String, RoutedMessage)] = [
            ("remember: buy milk", .saveNote("buy milk")),
            ("SAVE:  spaced  ", .saveNote("spaced")),
            ("note: https://x.com is great", .saveNote("https://x.com is great")),  // prefix wins over URL
            // CRLF-after-colon regression tests: Swift Regex matches "\r\n" as ONE grapheme
            // spanning 2 UTF-16 units, so a UTF-16-offset->Character-offset walk overshoots.
            ("note:\r\nbuy milk", .saveNote("buy milk")),
            ("remember:\r\n\r\ncall mom", .saveNote("call mom")),
            ("https://example.com/a?b=c", .saveURL(url: "https://example.com/a?b=c", note: "")),
            ("read this https://example.com/post.", .saveURL(url: "https://example.com/post", note: "read this")),
            // TS removes the FULL raw match ("https://x.com/y),") from the note, then trims
            ("https://x.com/y), context after", .saveURL(url: "https://x.com/y", note: "context after")),
            // TS's replace() only removes FIRST occurrence (string arg, not regex)
            ("https://a.com and https://a.com again", .saveURL(url: "https://a.com", note: "and https://a.com again")),
            // Non-BMP (emoji) character regression tests: must preserve preceding context without corruption
            ("😀 https://example.com note-after", .saveURL(url: "https://example.com", note: "😀 note-after")),
            ("😀 https://a.co", .saveURL(url: "https://a.co", note: "😀")),
            ("what did I save about tokyo?", .ask),
            ("   ", .ask),
        ]
        for (input, expected) in cases {
            XCTAssertEqual(classifyMessage(input), expected, "input: \(input)")
        }
    }
}
