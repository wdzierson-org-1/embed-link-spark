import XCTest
@testable import StashKit

@MainActor
final class ChatRenderCacheTests: XCTestCase {
    private let sourceId = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private let extraId = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!

    private func answer(_ content: String, id: String = "a-1") -> ChatMessage {
        ChatMessage(id: id, role: .assistant, content: content,
                    sources: [ChatSource(id: sourceId, title: "Feeding Notes", type: "text", url: nil, n: 1),
                              ChatSource(id: extraId, title: "Almanac", type: "text", url: nil, n: nil)])
    }

    func testDerivesLinksExtrasAndBlocks() {
        let rendered = ChatRenderedAnswer(message: answer("Per [Feeding Log](#1), go slow [1].\n\n- one\n- **two**"))
        XCTAssertEqual(rendered.linkedSourceIDs, [sourceId])
        XCTAssertEqual(rendered.extraSources.map(\.id), [extraId], "Only the never-linked source becomes a chip")
        XCTAssertTrue(rendered.displayText.contains("](#item=11111111-1111-1111-1111-111111111111)"))
        XCTAssertEqual(rendered.blocks.count, 2)
        guard case .paragraph(let paragraph) = rendered.blocks[0], case .bullets(let items) = rendered.blocks[1] else {
            return XCTFail("Unexpected blocks: \(rendered.blocks)")
        }
        // Inline markdown is parsed once, into real links / emphasis rather than raw syntax.
        XCTAssertEqual(String(paragraph.characters), "Per Feeding Log, go slow [1].")
        XCTAssertTrue(paragraph.runs.contains { $0.link?.fragment == "item=11111111-1111-1111-1111-111111111111" })
        XCTAssertEqual(items.map { String($0.characters) }, ["one", "two"])
    }

    func testUnresolvedMarkersRenderAsPlainText() {
        let rendered = ChatRenderedAnswer(message: ChatMessage(id: "a", role: .assistant, content: "See [Old Title](#7)."))
        XCTAssertEqual(rendered.displayText, "See Old Title.")
        XCTAssertTrue(rendered.linkedSourceIDs.isEmpty)
    }

    func testMemoizedPerMessageIdAndContent() {
        let cache = ChatRenderCache()
        let first = cache.answer(for: answer("Hello [1]"))
        XCTAssertEqual(cache.answer(for: answer("Hello [1]")), first)
        XCTAssertEqual(cache.derivations, 1, "Same id + content + sources is a hit")

        _ = cache.answer(for: answer("Hello [1] world"))
        XCTAssertEqual(cache.derivations, 2, "New content re-derives")
        _ = cache.answer(for: answer("Hello [1] world", id: "a-2"))
        XCTAssertEqual(cache.derivations, 3, "Keyed by message id")

        var resourced = answer("Hello [1] world")
        resourced.sources = []
        let rederived = cache.answer(for: resourced)
        XCTAssertEqual(cache.derivations, 4, "Sources arriving with `done` re-derive")
        XCTAssertTrue(rederived.linkedSourceIDs.isEmpty)
    }

    func testBoundedByCapacity() {
        let cache = ChatRenderCache(capacity: 2)
        _ = cache.answer(for: answer("one", id: "1"))
        _ = cache.answer(for: answer("two", id: "2"))
        _ = cache.answer(for: answer("three", id: "3"))   // evicts "1"
        _ = cache.answer(for: answer("three", id: "3"))
        XCTAssertEqual(cache.derivations, 3)
        _ = cache.answer(for: answer("one", id: "1"))
        XCTAssertEqual(cache.derivations, 4, "The oldest entry was evicted")
    }
}
