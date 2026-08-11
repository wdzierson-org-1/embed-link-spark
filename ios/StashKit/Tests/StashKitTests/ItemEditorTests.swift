import XCTest
@testable import StashKit

final class RecordingPatcher: ItemPatching, @unchecked Sendable {
    var patches: [(UUID, ItemPatch)] = []
    var deleted: [UUID] = []
    var patchResult: Item!
    var tagsResult: [StashTag] = []
    var addedTags: [(name: String, userId: UUID, itemId: UUID)] = []
    var removedTags: [(tagId: UUID, itemId: UUID)] = []
    var suggestCalls: [(title: String, content: String, description: String, available: [String])] = []
    var suggestResult: [String] = []
    func patch(itemId: UUID, patch: ItemPatch) async throws -> Item { patches.append((itemId, patch)); return patchResult }
    func deleteItemCascade(itemId: UUID) async throws { deleted.append(itemId) }
    func itemTags(itemId: UUID) async throws -> [StashTag] { tagsResult }
    func addTag(named: String, userId: UUID, itemId: UUID) async throws { addedTags.append((named, userId, itemId)) }
    func removeTag(tagId: UUID, itemId: UUID) async throws { removedTags.append((tagId, itemId)) }
    func suggestTags(title: String, content: String, description: String, available: [String]) async throws -> [String] {
        suggestCalls.append((title, content, description, available))
        return suggestResult
    }
}

@MainActor
final class ItemEditorTests: XCTestCase {
    func snapshot(title: String? = "T", note: String? = nil, isPublic: Bool = false) -> Item {
        Item(id: UUID(), type: .text, title: title, content: nil, url: nil, filePath: nil,
             description: "D", summary: nil, pageBody: nil, supplementalNote: note,
             mimeType: nil, isPublic: isPublic, createdAt: .now)
    }

    func testChangedFieldsDiffIsMinimal() {
        let patch = changedFields(from: snapshot(), title: "T", description: "D2", supplementalNote: "")
        XCTAssertNil(patch.title)                       // unchanged → omitted
        XCTAssertEqual(patch.description, "D2")
        XCTAssertNil(patch.supplementalNote)            // "" vs nil → unchanged
        XCTAssertFalse(patch.isEmpty)
        XCTAssertTrue(patch.touchesTextFields)
    }

    func testNoOpDiffIsEmpty() {
        let patch = changedFields(from: snapshot(), title: "T", description: "D", supplementalNote: "")
        XCTAssertTrue(patch.isEmpty)
    }

    func testSaveSkipsEmptyPatch() async throws {
        let patcher = RecordingPatcher()
        let editor = ItemEditor(patcher: patcher, refresher: EmbeddingRefresher(syncer: RecordingSyncer(), idle: .milliseconds(10)))
        _ = try? await editor.save(itemId: UUID(), patch: ItemPatch())
        XCTAssertTrue(patcher.patches.isEmpty)
    }

    func testUnshareWithNoteClearsSticky() {
        let editor = ItemEditor(patcher: RecordingPatcher(), refresher: EmbeddingRefresher(syncer: RecordingSyncer()))
        let patch = editor.togglePublic(item: snapshot(note: "sticky", isPublic: true), to: false)
        XCTAssertEqual(patch.isPublic, false)
        XCTAssertEqual(patch.supplementalNote, "")       // maps to null in restBody
        XCTAssertTrue(patch.restBody.keys.contains("supplemental_note"))
        let toPublic = editor.togglePublic(item: snapshot(note: nil, isPublic: false), to: true)
        XCTAssertNil(toPublic.supplementalNote)          // sharing never touches the note
    }

    // MARK: - Tag pass-throughs (Task 9)
    //
    // Thin forwards to `patcher` — these just confirm the forwarding happens with the right
    // arguments and the return value comes straight back, not new logic of their own.

    func testItemTagsForwardsToPatcherAndReturnsItsResult() async throws {
        let patcher = RecordingPatcher()
        let tag = StashTag(id: UUID(), name: "ios-test", usageCount: 3)
        patcher.tagsResult = [tag]
        let editor = ItemEditor(patcher: patcher, refresher: EmbeddingRefresher(syncer: RecordingSyncer()))
        let itemId = UUID()

        let result = try await editor.itemTags(itemId: itemId)

        XCTAssertEqual(result, [tag])
    }

    func testAddTagForwardsArgumentsToPatcher() async throws {
        let patcher = RecordingPatcher()
        let editor = ItemEditor(patcher: patcher, refresher: EmbeddingRefresher(syncer: RecordingSyncer()))
        let itemId = UUID()
        let userId = UUID()

        try await editor.addTag(named: "plan2-smoke", userId: userId, itemId: itemId)

        XCTAssertEqual(patcher.addedTags.count, 1)
        XCTAssertEqual(patcher.addedTags.first?.name, "plan2-smoke")
        XCTAssertEqual(patcher.addedTags.first?.userId, userId)
        XCTAssertEqual(patcher.addedTags.first?.itemId, itemId)
    }

    func testRemoveTagForwardsArgumentsToPatcher() async throws {
        let patcher = RecordingPatcher()
        let editor = ItemEditor(patcher: patcher, refresher: EmbeddingRefresher(syncer: RecordingSyncer()))
        let tagId = UUID()
        let itemId = UUID()

        try await editor.removeTag(tagId: tagId, itemId: itemId)

        XCTAssertEqual(patcher.removedTags.count, 1)
        XCTAssertEqual(patcher.removedTags.first?.tagId, tagId)
        XCTAssertEqual(patcher.removedTags.first?.itemId, itemId)
    }

    func testSuggestTagsForwardsArgumentsAndReturnsResult() async throws {
        let patcher = RecordingPatcher()
        patcher.suggestResult = ["cooking", "travel"]
        let editor = ItemEditor(patcher: patcher, refresher: EmbeddingRefresher(syncer: RecordingSyncer()))

        let result = try await editor.suggestTags(title: "T", content: "C", description: "D", available: ["cooking", "travel", "work"])

        XCTAssertEqual(result, ["cooking", "travel"])
        XCTAssertEqual(patcher.suggestCalls.count, 1)
        XCTAssertEqual(patcher.suggestCalls.first?.title, "T")
        XCTAssertEqual(patcher.suggestCalls.first?.available, ["cooking", "travel", "work"])
    }
}
