import XCTest
@testable import StashKit

final class TipTapAppendTests: XCTestCase {
    func testEmptyContentBecomesPlainNote() {
        XCTAssertEqual(appendNoteParagraph(to: nil, note: "hi"), "hi")
        XCTAssertEqual(appendNoteParagraph(to: "", note: "hi"), "hi")
    }
    func testPlainTextGetsSeparatedAppend() {
        XCTAssertEqual(appendNoteParagraph(to: "existing", note: "more"), "existing\n\nmore")
    }
    func testDocJSONGetsParagraphNode() throws {
        let doc = #"{"type":"doc","content":[{"type":"paragraph","content":[{"type":"text","text":"a"}]}]}"#
        let out = appendNoteParagraph(to: doc, note: "b")
        let root = try JSONSerialization.jsonObject(with: Data(out.utf8)) as! [String: Any]
        let content = root["content"] as! [[String: Any]]
        XCTAssertEqual(content.count, 2)
        let last = content[1]
        XCTAssertEqual(last["type"] as? String, "paragraph")
        let text = ((last["content"] as! [[String: Any]])[0])["text"] as? String
        XCTAssertEqual(text, "b")
        // Round-trips through the renderer
        XCTAssertTrue(String(renderTipTap(out).characters).contains("b"))
    }
    func testNonDocJSONTreatedAsPlainText() {
        XCTAssertEqual(appendNoteParagraph(to: #"{"weird":1}"#, note: "n"), "{\"weird\":1}\n\nn")
    }
}
