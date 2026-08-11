import XCTest
@testable import StashKit

final class MessageRoutingTests: XCTestCase {
    func testRouting() {
        let cases: [(String, RoutedMessage)] = [
            ("remember: buy milk", .saveNote("buy milk")),
            ("SAVE:  spaced  ", .saveNote("spaced")),
            ("note: https://x.com is great", .saveNote("https://x.com is great")),  // prefix wins over URL
            ("https://example.com/a?b=c", .saveURL(url: "https://example.com/a?b=c", note: "")),
            ("read this https://example.com/post.", .saveURL(url: "https://example.com/post", note: "read this")),
            // TS removes the FULL raw match ("https://x.com/y),") from the note, then trims
            ("https://x.com/y), context after", .saveURL(url: "https://x.com/y", note: "context after")),
            ("what did I save about tokyo?", .ask),
            ("   ", .ask),
        ]
        for (input, expected) in cases {
            XCTAssertEqual(classifyMessage(input), expected, "input: \(input)")
        }
    }
}
