import XCTest
@testable import StashKit

/// Plan 16, Task 4c: a PLAIN note (not TipTap — the field is the whole note) reads the edit queue.
/// Its draft needs saving when it differs from what the server last confirmed (`saved`) OR from a
/// value still queued for it (sent and in flight, or failed and waiting). With only the first
/// check, a note typed and sent ("abc"), cleared, and closed before "abc" landed was never sent
/// again — the server ended with "abc".
@MainActor
final class PlainNoteDraftTests: XCTestCase {
    private var directory: URL!
    private let t0 = Date(timeIntervalSince1970: 1_790_000_000)

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlainNoteDraftTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testAnUntouchedDraftNeedsNoSave() {
        XCTAssertFalse(PlainNoteDraft(draft: "", saved: "", queued: nil).needsSave)
        XCTAssertFalse(PlainNoteDraft(draft: "abc", saved: "abc", queued: nil).needsSave)
    }

    func testATypedDraftNeedsSaving() {
        XCTAssertTrue(PlainNoteDraft(draft: "abc", saved: "", queued: nil).needsSave)
    }

    /// The bug: cleared while "abc" is in flight (or queued after a failed send). The draft is back
    /// at what the server last confirmed, which alone reads as "nothing to save".
    func testAClearWhileTheTypedTextIsQueuedNeedsSaving() {
        XCTAssertTrue(PlainNoteDraft(draft: "", saved: "", queued: "abc").needsSave)
        XCTAssertTrue(PlainNoteDraft(draft: "abc", saved: "abc", queued: "abcd").needsSave,
                      "A revert to the confirmed text while an edit of it is queued, too")
    }

    /// A draft the queue holds but the server doesn't have yet is still unconfirmed — sent again
    /// by the next save as before (the queue merges the equal value, so nothing changes there).
    func testADraftTheQueueHoldsButTheServerHasNotConfirmedIsStillUnsaved() {
        XCTAssertTrue(PlainNoteDraft(draft: "abc", saved: "", queued: "abc").needsSave)
    }

    /// A sheet reopened on a queued, undelivered note starts with it as both draft and `saved`: the
    /// queue delivers it, and there's nothing more to send.
    func testADraftSeededFromTheQueueNeedsNothingMore() {
        XCTAssertFalse(PlainNoteDraft(draft: "abc", saved: "abc", queued: "abc").needsSave)
    }

    /// End to end with a real queue, in `ItemDetailView`'s order: "abc" is recorded and sent; the
    /// note is cleared and the sheet closed before "abc" lands — the close journals what the check
    /// says; "abc" lands and is confirmed; the close's flush then delivers the clear.
    func testAClearClosedWhileTheTextIsInFlightIsWhatTheServerEndsWith() async throws {
        let userId = UUID()
        let row = Item(id: UUID(), type: .text, title: "Groceries", content: "", url: nil, filePath: nil,
                       description: nil, summary: nil, pageBody: nil, supplementalNote: nil, mimeType: nil,
                       isPublic: false, createdAt: t0, attributes: ItemAttributes())
        let server = FakeRowServer(rows: [row])
        let queue = PendingEdits(userId: userId, directory: directory, session: FakeSession(signedIn: userId, server: server))
        func queuedContent() -> String? { queue.edit(for: row.id)?.content?.value }

        let typed = PlainNoteDraft(draft: "abc", saved: "", queued: queuedContent())
        XCTAssertTrue(typed.needsSave)
        queue.record(itemId: row.id, patch: ItemPatch(content: "abc"), capturedAt: t0)   // sent: in flight

        let cleared = PlainNoteDraft(draft: "", saved: "", queued: queuedContent())
        XCTAssertTrue(cleared.needsSave, "The close must journal the clear: \"abc\" is still on its way")
        queue.record(itemId: row.id, patch: ItemPatch(content: ""), capturedAt: t0.addingTimeInterval(1))

        server.update(row.id) { $0.content = "abc" }   // "abc" lands …
        queue.confirm(itemId: row.id, patch: ItemPatch(content: "abc"), capturedAt: t0)   // … and is confirmed
        XCTAssertEqual(queuedContent(), "", "The newer clear stays queued")

        await queue.flush(editor: ItemEditor(patcher: server,
                                             refresher: EmbeddingRefresher(syncer: RecordingSyncer(), idle: .milliseconds(10)),
                                             writeQueue: ItemWriteQueue()))
        XCTAssertEqual(server.row(row.id)?.content, "", "The server ends with the clear, not \"abc\"")
        XCTAssertNil(queue.edit(for: row.id))
    }
}
