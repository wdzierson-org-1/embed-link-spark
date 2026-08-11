import XCTest
@testable import StashKit

final class RecordingPatcher: ItemPatching, @unchecked Sendable {
    var patches: [(UUID, ItemPatch)] = []
    var deleted: [UUID] = []
    var patchResult: Item!
    func patch(itemId: UUID, patch: ItemPatch) async throws -> Item { patches.append((itemId, patch)); return patchResult }
    func deleteItemCascade(itemId: UUID) async throws { deleted.append(itemId) }
    func itemTags(itemId: UUID) async throws -> [StashTag] { [] }
    func addTag(named: String, userId: UUID, itemId: UUID) async throws {}
    func removeTag(tagId: UUID, itemId: UUID) async throws {}
    func suggestTags(title: String, content: String, description: String, available: [String]) async throws -> [String] { [] }
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
}
