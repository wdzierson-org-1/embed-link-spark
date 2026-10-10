import XCTest
@testable import StashKit

@MainActor
final class LinkAddressEditTests: XCTestCase {
    private var directory: URL!
    private let userID = UUID()
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private let oldURL = "https://old.example/video"
    private let newURL = "https://new.example/article"

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("LinkAddress-\(UUID())")
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: directory) }

    private func row() -> Item {
        Item(id: UUID(), type: .link, title: "My title", content: "My notes", url: oldURL,
             filePath: "cover.jpg", description: "My description", summary: "Saved summary",
             pageBody: "Saved source", supplementalNote: "Sticky", mimeType: nil, isPublic: false,
             createdAt: t0, attributes: ItemAttributes(
                location: CapturedLocation(label: "Home", source: "manual"),
                link: LinkAttributes(flavor: "video", extra: ["canonical_url": .string(oldURL), "video_id": .string("old")]),
                media: MediaAttributes(durationS: 20),
                extra: ["future": .string("keep"), "enrichment": .object([
                    "evidence": .object(["canonical_url": .string(oldURL)]),
                    "protected_fields": .object(["title": .bool(true)]), "future": .number(42)
                ])]))
    }

    private func queue() -> PendingEdits {
        PendingEdits(userId: userID, directory: directory, session: FakeSession(signedIn: userID))
    }

    func testNormalizesWebAddressesAndRejectsOtherSchemesOrInvalidHosts() {
        XCTAssertEqual(LinkAddressEdit.normalize("  Example.COM/path?q=one#two  "), "https://example.com/path?q=one#two")
        XCTAssertEqual(LinkAddressEdit.normalize("http://example.com"), "http://example.com/")
        for raw in ["", "a b.com", "example.com/has space", "mailto:a@example.com", "javascript:alert(1)", "ftp://example.com", "https://localhost", "https://"] {
            XCTAssertNil(LinkAddressEdit.normalize(raw), raw)
        }
    }

    func testURLPatchIsARealMinimalWriteWithoutPersistingAnAttributesSnapshot() {
        let patch = ItemPatch(url: newURL)
        XCTAssertFalse(patch.isEmpty)
        XCTAssertEqual(patch.restBody["url"] as? String, newURL)
        XCTAssertEqual(Set(patch.restBody.keys), ["url"])
        XCTAssertNil(patch.attributes)
    }

    func testOverlayInvalidatesOldAddressFactsAndKeepsUserMetadata() {
        let before = row()
        let after = LinkAddressEdit.applying(newURL, to: before)
        XCTAssertEqual(after.url, newURL)
        XCTAssertNil(after.attributes.link)
        guard case .object(let enrichment) = after.attributes.extra["enrichment"] else { return XCTFail("Lost enrichment") }
        XCTAssertNil(enrichment["evidence"])
        XCTAssertEqual(enrichment["protected_fields"], .object(["title": .bool(true)]))
        XCTAssertEqual(enrichment["future"], .number(42))
        XCTAssertEqual(after.attributes.extra["future"], .string("keep"))
        XCTAssertEqual(after.attributes.location, before.attributes.location)
        XCTAssertEqual(after.attributes.media, before.attributes.media)
        XCTAssertEqual(after.title, before.title)
        XCTAssertEqual(after.content, before.content)
        XCTAssertEqual(after.summary, before.summary)
        XCTAssertEqual(after.pageBody, before.pageBody)
        XCTAssertEqual(after.filePath, before.filePath)
    }

    func testAssociatedMediaAddressEditPreservesUploadedPlaybackAndTranscript() {
        var audio = row()
        audio.type = .audio
        audio.filePath = "owner/recording.m4a"
        audio.attributes.media?.extra["transcript"] = .object(["status": .string("done")])
        let edited = LinkAddressEdit.applying(newURL, to: audio)
        XCTAssertEqual(edited.type, .audio)
        XCTAssertEqual(edited.filePath, audio.filePath)
        XCTAssertEqual(edited.pageBody, audio.pageBody)
        XCTAssertEqual(edited.attributes.media, audio.attributes.media)
    }

    func testRejectsEncodedWhitespaceInHost() {
        XCTAssertNil(LinkAddressEdit.normalize("https://exa%20mple.com/path"))
    }

    func testRejectsEmbeddedCredentialsAndDeceptiveUserInfo() {
        for address in ["https://user:pass@example.com/", "https://user@example.com/", "https://example.com@other.test/"] {
            XCTAssertNil(LinkAddressEdit.normalize(address))
        }
    }

    func testWritePreparationUsesFreshMetadataAndCombinesQueuedLocation() {
        let before = row()
        var fresh = before.attributes
        fresh.extra["arrived_while_offline"] = .string("preserve")
        fresh.media?.extra["transcript"] = .string("new server state")
        var queuedLocation = before.attributes
        queuedLocation.location = CapturedLocation(label: "Office", source: "manual")
        let prepared = LinkAddressEdit.preparing(ItemPatch(attributes: queuedLocation, url: newURL), currentAttributes: fresh)
        XCTAssertEqual(prepared.url, newURL)
        XCTAssertEqual(prepared.attributes?.location?.label, "Office")
        XCTAssertEqual(prepared.attributes?.extra["arrived_while_offline"], .string("preserve"))
        XCTAssertEqual(prepared.attributes?.media?.extra["transcript"], .string("new server state"))
        XCTAssertNil(prepared.attributes?.link)
    }

    func testDiskRelaunchRetainsURLIntentAndOverlaysFreshRows() throws {
        let before = row()
        let first = queue()
        first.record(itemId: before.id, patch: ItemPatch(url: newURL), capturedAt: t0)
        let reopened = queue()
        let edit = try XCTUnwrap(reopened.edit(for: before.id))
        XCTAssertEqual(edit.fieldPatch.url, newURL)
        XCTAssertNil(edit.attributes, "Store intent, never a stale metadata snapshot")
        let shown = edit.applied(to: before)
        XCTAssertEqual(shown.url, newURL)
        XCTAssertNil(shown.attributes.link)
        XCTAssertEqual(shown.content, before.content)
    }

    func testLegacyPendingJSONWithoutURLStillDecodes() throws {
        let before = row()
        let entry = PendingEdit(itemId: before.id, patch: ItemPatch(title: "Queued title"), capturedAt: t0)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(entry)) as? [String: Any])
        json.removeValue(forKey: "url")
        let decoded = try JSONDecoder().decode(PendingEdit.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(decoded.fieldPatch.title, "Queued title")
        XCTAssertNil(decoded.fieldPatch.url)
    }

    func testOlderResponseCannotDropOrRevertNewerCommittedAddress() throws {
        let before = row()
        let pending = queue()
        pending.record(itemId: before.id, patch: ItemPatch(url: newURL), capturedAt: t0)
        pending.record(itemId: before.id, patch: ItemPatch(url: oldURL), capturedAt: t0.addingTimeInterval(1))
        pending.confirm(itemId: before.id, patch: ItemPatch(url: newURL), capturedAt: t0)
        XCTAssertEqual(pending.edit(for: before.id)?.fieldPatch.url, oldURL)
        let local = before
        var response = before
        response.url = newURL
        let adopted = DetailFieldEdits(local: local, baseline: before, queued: pending.edit(for: before.id)).adopting(response)
        XCTAssertEqual(adopted.url, oldURL, "A revert to the baseline must survive an earlier response")
        XCTAssertNil(adopted.attributes.link)
    }

    func testLandingRequeuesAYoungerAddressAndPreservesOtherFields() {
        let before = row()
        let pending = queue()
        let sent = ItemPatch(url: newURL)
        pending.record(itemId: before.id, patch: sent, capturedAt: t0)
        var local = before
        local.url = "https://latest.example/"
        var saved = before
        saved.url = newURL
        let landed = DetailFieldEdits.landing(sent, capturedAt: t0, as: saved, local: local,
                                             baseline: before, queue: pending, sheetIsOpen: true,
                                             at: t0.addingTimeInterval(1), apply: { _ in })
        XCTAssertEqual(landed.url, local.url)
        XCTAssertEqual(pending.edit(for: before.id)?.fieldPatch.url, local.url)
        XCTAssertEqual(landed.content, before.content)
    }

    func testOfflineReplayReadsMetadataAgainAndPreservesChangesMadeWhileAway() async throws {
        let before = row()
        let server = FakeRowServer(rows: [before])
        server.error = URLError(.notConnectedToInternet)
        let editor = ItemEditor(patcher: server, refresher: EmbeddingRefresher(syncer: RecordingSyncer()),
                                writeQueue: ItemWriteQueue())
        let first = queue()
        let patch = ItemPatch(url: newURL)
        first.record(itemId: before.id, patch: patch, capturedAt: t0)
        do {
            _ = try await first.send(patch, capturedAt: t0, itemId: before.id, editor: editor)
            XCTFail("Offline save should fail and remain queued")
        } catch {}
        XCTAssertEqual(first.edit(for: before.id)?.fieldPatch.url, newURL)
        XCTAssertTrue(server.patches.isEmpty, "A failed fresh-metadata read must not send a stale blob")

        server.error = nil
        server.update(before.id) { $0.attributes.extra["new_server_fact"] = .string("keep") }
        let reopened = queue()
        await reopened.flush(editor: editor)
        let saved = try XCTUnwrap(server.row(before.id))
        XCTAssertEqual(saved.url, newURL)
        XCTAssertEqual(saved.attributes.extra["new_server_fact"], .string("keep"))
        XCTAssertNil(saved.attributes.link)
        XCTAssertEqual(saved.pageBody, before.pageBody)
        XCTAssertEqual(saved.content, before.content)
        XCTAssertNil(reopened.edit(for: before.id))
    }

    func testDeliveredURLSupersedesAnOlderWriteAndUpdatesAStillOpenSheet() async throws {
        let before = row()
        let server = FakeRowServer(rows: [before])
        let editor = ItemEditor(patcher: server, refresher: EmbeddingRefresher(syncer: RecordingSyncer()),
                                writeQueue: ItemWriteQueue())
        let pending = queue()
        let newer = ItemPatch(url: newURL)
        let newerTime = t0.addingTimeInterval(1)
        pending.record(itemId: before.id, patch: newer, capturedAt: newerTime)
        _ = try await pending.send(newer, capturedAt: newerTime, itemId: before.id, editor: editor)
        pending.confirm(itemId: before.id, patch: newer, capturedAt: newerTime)
        let lateOld = try await pending.send(ItemPatch(url: oldURL), capturedAt: t0,
                                            itemId: before.id, editor: editor)
        XCTAssertNil(lateOld.item)
        XCTAssertEqual(lateOld.serverHolds.url, newURL)
        XCTAssertEqual(server.patches.count, 1)
        XCTAssertEqual(pending.deliveries(for: before.id, after: 0).url, newURL)
        let delivered = try XCTUnwrap(DetailFieldEdits.receivingDeliveries(
            local: before, snapshot: before, knownDeliveries: 0, queue: pending))
        XCTAssertEqual(delivered.row.url, newURL)
        XCTAssertEqual(delivered.fields.url, newURL)
        XCTAssertNil(delivered.fields.attributes.link)
    }
}
