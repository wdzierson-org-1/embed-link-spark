import XCTest
@testable import StashKit

final class RecordingPatcher: ItemPatching, @unchecked Sendable {
    var patches: [(UUID, ItemPatch)] = []
    var deleted: [UUID] = []
    /// Plan 12 feedback round 3, Task 1: lets `testDeletePropagatesPatcherFailure` simulate the
    /// real `SupabaseItemPatcher.deleteItemCascade` throwing `.deleteMatchedNoRows` (or any other
    /// error) without touching the network — proves `ItemEditor.delete` is a pure pass-through
    /// that never swallows a delete failure.
    var deleteError: Error?
    var patchResult: Item!
    var tagsResult: [StashTag] = []
    var addedTags: [(name: String, userId: UUID, itemId: UUID)] = []
    var removedTags: [(tagId: UUID, itemId: UUID)] = []
    var suggestCalls: [(title: String, content: String, description: String, available: [String])] = []
    var suggestResult: [String] = []
    func patch(itemId: UUID, patch: ItemPatch) async throws -> Item { patches.append((itemId, patch)); return patchResult }
    func deleteItemCascade(itemId: UUID) async throws {
        if let deleteError { throw deleteError }
        deleted.append(itemId)
    }
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
             mimeType: nil, isPublic: isPublic, createdAt: .now, fileSize: nil, attributes: ItemAttributes())
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

    // MARK: - Delete (Plan 12 feedback round 3, Task 1)
    //
    // The actual root-cause fix (`SupabaseItemPatcher.deleteItemCascade` now decoding the
    // items DELETE's own representation payload and throwing `.deleteMatchedNoRows` on an
    // empty result) is real network behavior with no local seam to unit-test directly — see
    // that method's doc comment for the confirmed-live evidence. What IS unit-testable, and
    // what these two lock in, is `ItemEditor.delete`'s own contract: a clean delegation to the
    // patcher that neither swallows nor alters whatever it reports, in either direction.

    func testDeleteForwardsToPatcher() async throws {
        let patcher = RecordingPatcher()
        let editor = ItemEditor(patcher: patcher, refresher: EmbeddingRefresher(syncer: RecordingSyncer()))
        let itemId = UUID()

        try await editor.delete(itemId: itemId)

        XCTAssertEqual(patcher.deleted, [itemId])
    }

    /// Was the whole bug, one layer up: before this fix round, nothing in `ItemEditor`/
    /// `ItemDetailView` distinguished "the patcher reported success" from "the patcher reported
    /// nothing happened" — a delete that matched zero rows server-side (RLS, or the row was
    /// already gone) surfaced identically to a real one. This proves the propagation half of
    /// the fix: whatever error the patcher throws (including the new `.deleteMatchedNoRows`)
    /// reaches the caller unmodified, so `ItemDetailView.performDelete`'s catch block — and
    /// hence `deleteErrorMessage` — actually fires instead of the sheet dismissing on a no-op.
    func testDeletePropagatesPatcherFailure() async {
        let patcher = RecordingPatcher()
        patcher.deleteError = ItemEditorError.deleteMatchedNoRows
        let editor = ItemEditor(patcher: patcher, refresher: EmbeddingRefresher(syncer: RecordingSyncer()))

        do {
            try await editor.delete(itemId: UUID())
            XCTFail("Expected the patcher's delete failure to propagate")
        } catch {
            XCTAssertEqual(error as? ItemEditorError, .deleteMatchedNoRows)
        }
        XCTAssertTrue(patcher.deleted.isEmpty, "A failed delete must never be recorded as having succeeded")
    }

    /// Final wave (F6): `deleteResponseUnreadable` (a DELETE response that couldn't even be
    /// decoded) must reach the caller as its OWN distinct case, not fold into
    /// `.deleteMatchedNoRows` — `ItemDetailView.performDelete` keys its UI copy off this
    /// distinction (a decode failure gets the generic "try again", not the no-rows-matched
    /// "may not exist anymore" copy, which would misdescribe an unreadable response as a
    /// definitely-absent row).
    func testDeletePropagatesResponseUnreadableDistinctFromNoRows() async {
        let patcher = RecordingPatcher()
        patcher.deleteError = ItemEditorError.deleteResponseUnreadable
        let editor = ItemEditor(patcher: patcher, refresher: EmbeddingRefresher(syncer: RecordingSyncer()))

        do {
            try await editor.delete(itemId: UUID())
            XCTFail("Expected the patcher's delete failure to propagate")
        } catch {
            let itemError = error as? ItemEditorError
            XCTAssertEqual(itemError, .deleteResponseUnreadable)
            XCTAssertNotEqual(itemError, .deleteMatchedNoRows)
        }
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

    // MARK: - Attributes patch (Task 8)
    //
    // `ItemPatch.attributes` is a full-blob write (never a per-key merge, same convention as
    // every other field on this type) driven by the detail sheet's `LocationRow`. It must never
    // count toward `touchesTextFields` (web parity: `itemOperations.ts:100-101` gates the
    // embedding refresh on title/description/content/supplemental_note only — an attributes-only
    // save changes nothing `buildEmbeddingText` reads).

    func testAttributesPatchEncodesFullBlobInRestBody() throws {
        let attrs = ItemAttributes(location: CapturedLocation(label: "Testville", source: "manual"),
                                    link: LinkAttributes(flavor: "article"))
        let patch = ItemPatch(attributes: attrs)

        XCTAssertFalse(patch.isEmpty)
        let body = try XCTUnwrap(patch.restBody["attributes"] as? [String: Any])
        let location = try XCTUnwrap(body["location"] as? [String: Any])
        XCTAssertEqual(location["label"] as? String, "Testville")
        XCTAssertEqual(location["source"] as? String, "manual")
        let link = try XCTUnwrap(body["link"] as? [String: Any])
        XCTAssertEqual(link["flavor"] as? String, "article")
    }

    /// `attributes == nil` means "don't touch this column" — same convention as every other
    /// `Optional` field on `ItemPatch` — so the key must be entirely absent, not `null`.
    func testNilAttributesLeavesKeyOutOfRestBody() {
        let patch = ItemPatch(title: "T")
        XCTAssertFalse(patch.restBody.keys.contains("attributes"))
    }

    /// An attributes-only patch is a real, non-empty patch (so `ItemEditor.save` won't reject it
    /// as `.emptyPatch`), but it must never trip the text-field embedding-refresh gate.
    func testAttributesOnlyPatchIsNotEmptyButDoesNotTouchTextFields() {
        let patch = ItemPatch(attributes: ItemAttributes(location: CapturedLocation(label: "X", source: "manual")))
        XCTAssertFalse(patch.isEmpty)
        XCTAssertFalse(patch.touchesTextFields)
    }

    /// Clearing an item's only attribute is a real, intentional write of `{}` — distinct from
    /// `attributes == nil` ("don't touch the column" above) — so it must still be encoded and
    /// sent, never collapsed to "nothing to send" the way `ItemAttributes.nonEmptyJSONObject`
    /// (the capture-time convention) would.
    func testEmptyAttributesBlobStillEncodesAsEmptyObjectNotOmitted() throws {
        let patch = ItemPatch(attributes: ItemAttributes())
        let body = try XCTUnwrap(patch.restBody["attributes"] as? [String: Any])
        XCTAssertTrue(body.isEmpty)
    }

    /// End-to-end through `ItemEditor.save`: an attributes-only save reaches the patcher (so the
    /// PATCH itself still happens) but never schedules an embedding refresh — `RecordingSyncer`
    /// stays empty even after the refresher's own idle window elapses.
    func testSaveWithOnlyAttributesDoesNotScheduleEmbeddingRefresh() async throws {
        let patcher = RecordingPatcher()
        patcher.patchResult = snapshot()
        let syncer = RecordingSyncer()
        let editor = ItemEditor(patcher: patcher, refresher: EmbeddingRefresher(syncer: syncer, idle: .milliseconds(10)))
        let attrs = ItemAttributes(location: CapturedLocation(label: "Testville", source: "manual"))

        _ = try await editor.save(itemId: UUID(), patch: ItemPatch(attributes: attrs))

        XCTAssertEqual(patcher.patches.count, 1)
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertTrue(syncer.calls.isEmpty, "an attributes-only save must never schedule an embedding refresh")
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
