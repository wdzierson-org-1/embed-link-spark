import XCTest
@testable import StashKit

/// Port of src/utils/chatCitations.test.ts's `bakeCitationLinks` suite, adapted to
/// `ChatCitations.link`'s combined bake+track interface (`stash://item/<uuid>` hrefs instead of
/// `#item=<uuid>`, and the linked ids returned directly rather than re-extracted from the text
/// afterward — see `ChatCitations.swift`'s doc comment for why).
final class ChatCitationsTests: XCTestCase {
    private let sourceOne = ChatSource(id: UUID(), title: "Feeding notes", type: "text", url: nil, n: 1)
    private let sourceThree = ChatSource(id: UUID(), title: "My Note", type: "text", url: nil, n: 3)

    /// `[Title](#3)` → `[Title](stash://item/<uuid>)` (web: bakeCitationLinks's "rewrites linked
    /// titles to item links").
    func testLinkedTitleForm() {
        let result = ChatCitations.link(answer: "See [My Note](#3) for details.", sources: [sourceThree])
        XCTAssertEqual(result.text, "See [My Note](\(ChatCitations.itemLinkPrefix)\(sourceThree.id.uuidString)) for details.")
        XCTAssertEqual(result.linkedSourceIDs, [sourceThree.id])
    }

    /// Bare `[1]` → `[[1]](stash://item/<uuid>)` (web: "wraps bare bracket markers as bracketed
    /// links").
    func testBareMarkerForm() {
        let result = ChatCitations.link(answer: "Feed at 8am [1].", sources: [sourceOne])
        XCTAssertEqual(result.text, "Feed at 8am [[1]](\(ChatCitations.itemLinkPrefix)\(sourceOne.id.uuidString)).")
        XCTAssertEqual(result.linkedSourceIDs, [sourceOne.id])
    }

    /// Running `link` again on already-baked text is a no-op — the inner `[1]` of `[[1]](url)`
    /// is preceded by `[`, so the bare-marker pass skips it (web: "does not double-bake
    /// already-baked content"), and the baked href never matches the linked-title pass's `#\d+`
    /// pattern either.
    func testAlreadyLinkedSkipped() {
        let baked = ChatCitations.link(answer: "Feed at 8am [1].", sources: [sourceOne])
        let rebaked = ChatCitations.link(answer: baked.text, sources: [sourceOne])
        XCTAssertEqual(rebaked.text, baked.text)
    }

    /// A citation number with no matching source is left untouched (web: "leaves unknown numbers
    /// alone").
    func testUnknownNumberUntouched() {
        let result = ChatCitations.link(answer: "See [7] for details.", sources: [sourceOne, sourceThree])
        XCTAssertEqual(result.text, "See [7] for details.")
        XCTAssertTrue(result.linkedSourceIDs.isEmpty)
    }

    /// Both forms together in one answer, unknown numbers untouched among them (web: "handles
    /// both forms together and leaves unknown numbers alone").
    func testMultipleMarkers() {
        let input = "[My Note](#3) says X [1], and [7] is unknown."
        let result = ChatCitations.link(answer: input, sources: [sourceOne, sourceThree])
        XCTAssertEqual(result.text,
            "[My Note](\(ChatCitations.itemLinkPrefix)\(sourceThree.id.uuidString)) says X [[1]](\(ChatCitations.itemLinkPrefix)\(sourceOne.id.uuidString)), and [7] is unknown.")
        XCTAssertEqual(result.linkedSourceIDs, [sourceOne.id, sourceThree.id])
    }

    /// No sources (or sources without a citation number at all) → unchanged text, empty set (web:
    /// "is a no-op without citation numbers").
    func testNoSourcesUnchanged() {
        let unnumbered = ChatSource(id: UUID(), title: "x", type: nil, url: nil)
        let result = ChatCitations.link(answer: "Plain [1] text.", sources: [unnumbered])
        XCTAssertEqual(result.text, "Plain [1] text.")
        XCTAssertTrue(result.linkedSourceIDs.isEmpty)

        let empty = ChatCitations.link(answer: "Plain [1] text.", sources: [])
        XCTAssertEqual(empty.text, "Plain [1] text.")
        XCTAssertTrue(empty.linkedSourceIDs.isEmpty)
    }

    /// A non-numeric bracket (`[abc]`) is never a citation marker — untouched.
    func testMalformedBracketUntouched() {
        let result = ChatCitations.link(answer: "See [abc] for details.", sources: [sourceOne, sourceThree])
        XCTAssertEqual(result.text, "See [abc] for details.")
        XCTAssertTrue(result.linkedSourceIDs.isEmpty)
    }
}
