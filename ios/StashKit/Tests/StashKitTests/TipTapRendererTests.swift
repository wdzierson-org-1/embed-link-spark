import XCTest
@testable import StashKit

final class TipTapRendererTests: XCTestCase {
    func testPlainTextPassthrough() {
        XCTAssertEqual(String(renderTipTap("just text").characters), "just text")
        XCTAssertEqual(String(renderTipTap(nil).characters), "")
    }

    func testDocWithParagraphHeadingAndBullets() {
        let doc = """
        {"type":"doc","content":[
          {"type":"heading","attrs":{"level":2},"content":[{"type":"text","text":"Title"}]},
          {"type":"paragraph","content":[{"type":"text","text":"Hello "},
            {"type":"text","marks":[{"type":"bold"}],"text":"bold"}]},
          {"type":"bulletList","content":[
            {"type":"listItem","content":[{"type":"paragraph","content":[{"type":"text","text":"one"}]}]},
            {"type":"listItem","content":[{"type":"paragraph","content":[{"type":"text","text":"two"}]}]}]}
        ]}
        """
        let out = String(renderTipTap(doc).characters)
        XCTAssertTrue(out.contains("Title"))
        XCTAssertTrue(out.contains("Hello bold"))
        XCTAssertTrue(out.contains("• one"))
        XCTAssertTrue(out.contains("• two"))
    }
}
