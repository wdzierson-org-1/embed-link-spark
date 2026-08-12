import XCTest
@testable import StashKit

/// Records every POST call (unlike `StubPoster`, which only keeps the last one) so tests can
/// assert exactly how many `add-*` calls a routing decision produced. Responds with `noteJSON`
/// for "add-note" and `itemJSON` for everything else, reusing Tasks 2-3's fixtures.
final class RecordingPoster: JSONPosting, @unchecked Sendable {
    var calls: [(path: String, body: [String: Any])] = []
    var shouldFail = false
    func post(path: String, body: [String: Any], accessToken: String) async throws -> Data {
        calls.append((path, body))
        if shouldFail { throw CaptureError.badStatus(500) }
        return path == "add-note" ? noteJSON : itemJSON
    }
}

@MainActor
final class CaptureViewModelTests: XCTestCase {
    var dir: URL!
    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appending(path: "capture-vm-\(UUID().uuidString)")
    }
    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    func makeViewModel(poster: RecordingPoster) -> CaptureViewModel {
        CaptureViewModel(
            userId: UUID(),
            api: CaptureAPI(poster: poster),
            outbox: Outbox(directory: dir),
            upload: { _, _, _ in },
            accessToken: { "jwt" }
        )
    }

    func testURLTextRoutesToAddURL() async {
        let poster = RecordingPoster()
        let vm = makeViewModel(poster: poster)
        vm.text = "check this out https://example.com cool"

        let outcome = await vm.submit()

        XCTAssertEqual(outcome, .saved(count: 1, dropped: 0))
        XCTAssertEqual(poster.calls.map(\.path), ["add-url"])
        XCTAssertEqual(poster.calls[0].body["url"] as? String, "https://example.com")
        XCTAssertEqual(poster.calls[0].body["content"] as? String, "check this out cool")
    }

    func testPlainTextRoutesToAddNote() async {
        let poster = RecordingPoster()
        let vm = makeViewModel(poster: poster)
        vm.text = "buy milk"

        let outcome = await vm.submit()

        XCTAssertEqual(outcome, .saved(count: 1, dropped: 0))
        XCTAssertEqual(poster.calls.map(\.path), ["add-note"])
        XCTAssertEqual(poster.calls[0].body["content"] as? String, "buy milk")
    }

    func testOneFileWithTextRoutesToAddFileWithContent() async {
        let poster = RecordingPoster()
        let vm = makeViewModel(poster: poster)
        vm.text = "my screenshot"
        vm.attachments = [CaptureAttachment(data: Data([0x01, 0x02]), fileExtension: "png",
                                            mimeType: "image/png", kind: .photo)]

        let outcome = await vm.submit()

        XCTAssertEqual(outcome, .saved(count: 1, dropped: 0))
        XCTAssertEqual(poster.calls.map(\.path), ["add-file"])
        XCTAssertEqual(poster.calls[0].body["content"] as? String, "my screenshot")
    }

    func testThreeFilesWithTextRoutesToThreeAddFilePlusOneAddNote() async {
        let poster = RecordingPoster()
        let vm = makeViewModel(poster: poster)
        vm.text = "batch upload"
        vm.attachments = (0..<3).map { _ in
            CaptureAttachment(data: Data([0x01]), fileExtension: "png", mimeType: "image/png", kind: .photo)
        }

        let outcome = await vm.submit()

        XCTAssertEqual(outcome, .saved(count: 4, dropped: 0))
        let fileCalls = poster.calls.filter { $0.path == "add-file" }
        let noteCalls = poster.calls.filter { $0.path == "add-note" }
        XCTAssertEqual(fileCalls.count, 3)
        XCTAssertTrue(fileCalls.allSatisfy { $0.body["content"] == nil })
        XCTAssertEqual(noteCalls.count, 1)
        XCTAssertEqual(noteCalls[0].body["content"] as? String, "batch upload")
    }

    func testFailureEnqueuesToOutboxAndReturnsQueued() async {
        let poster = RecordingPoster(); poster.shouldFail = true
        let vm = makeViewModel(poster: poster)
        vm.text = "offline note"

        let outcome = await vm.submit()

        XCTAssertEqual(outcome, .queued(count: 1, dropped: 0))
        let box = Outbox(directory: dir)
        let pending = await box.pending()
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending[0].payload["content"], "offline note")
    }

    // Fix round (review Important finding): oversized/upload-failed attachments were being
    // dropped print-only, with no way for the caller to know data was lost. Every drop must now
    // be counted and surfaced via `CaptureOutcome`.

    func testOversizedDocAloneIsRejectedWithNoNetworkCalls() async {
        let poster = RecordingPoster()
        let vm = makeViewModel(poster: poster)
        vm.attachments = [CaptureAttachment(data: Data(count: 21 * 1024 * 1024), fileExtension: "pdf",
                                            mimeType: "application/pdf", kind: .file)]

        let outcome = await vm.submit()

        XCTAssertEqual(outcome, .rejected(dropped: 1))
        XCTAssertTrue(poster.calls.isEmpty, "An oversized reject must never reach the network")
    }

    func testThreeAttachmentsWithOneOversizedSavesTwoAndDropsOne() async {
        let poster = RecordingPoster()
        let vm = makeViewModel(poster: poster)
        let smallPhotos = (0..<2).map { _ in
            CaptureAttachment(data: Data([0x01]), fileExtension: "png", mimeType: "image/png", kind: .photo)
        }
        let oversizedDoc = CaptureAttachment(data: Data(count: 21 * 1024 * 1024), fileExtension: "pdf",
                                             mimeType: "application/pdf", kind: .file)
        vm.attachments = smallPhotos + [oversizedDoc]

        let outcome = await vm.submit()

        XCTAssertEqual(outcome, .saved(count: 2, dropped: 1))
        XCTAssertEqual(poster.calls.filter { $0.path == "add-file" }.count, 2)
    }

    // MARK: - Voice notes (Task 6)
    //
    // `submitVoiceNote` is a separate, single-unit submit path, distinct from `submit()`'s
    // attachment routing: the recording's bytes are already durably on local disk (written by
    // `AVAudioRecorder` via `RecordingStore`, before this is ever called) — unlike a
    // `CaptureAttachment`'s in-memory `Data`, nothing is lost by queuing on ANY failure, so
    // (per the brief) there's no `UnqueueableFailure`-style distinction here: every failure mode
    // queues, never drops.

    func testSubmitVoiceNoteSuccessUploadsAndDeletesLocalFile() async throws {
        let poster = RecordingPoster()
        let vm = makeViewModel(poster: poster)
        let fileURL = FileManager.default.temporaryDirectory.appending(path: "voice-\(UUID().uuidString).m4a")
        try Data([0x01, 0x02, 0x03]).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let outcome = await vm.submitVoiceNote(fileURL: fileURL)

        XCTAssertEqual(outcome, .saved(count: 1, dropped: 0))
        XCTAssertEqual(poster.calls.map(\.path), ["add-file"])
        XCTAssertEqual(poster.calls[0].body["mime_type"] as? String, "audio/mp4")
        XCTAssertEqual(poster.calls[0].body["file_size"] as? Int, 3)
        XCTAssertNil(poster.calls[0].body["content"], "voice notes never attach the composer's text as content")
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path),
                       "the local recording must be deleted once its bytes are durably uploaded and registered")
    }

    func testSubmitVoiceNoteFailureRetainsFileAndEnqueuesOutboxEntryReferencingIt() async throws {
        let poster = RecordingPoster(); poster.shouldFail = true
        let vm = makeViewModel(poster: poster)
        let fileURL = FileManager.default.temporaryDirectory.appending(path: "voice-\(UUID().uuidString).m4a")
        try Data([0x0A, 0x0B]).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let outcome = await vm.submitVoiceNote(fileURL: fileURL)

        XCTAssertEqual(outcome, .queued(count: 1, dropped: 0))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path),
                      "a failed submit must never delete the only copy of the recording")
        let box = Outbox(directory: dir)
        let pending = await box.pending()
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending[0].payload["local_file_path"], fileURL.path,
                       "the queued entry must point at exactly the file that's still on disk")
        XCTAssertEqual(pending[0].payload["mime_type"], "audio/mp4")
    }
}
