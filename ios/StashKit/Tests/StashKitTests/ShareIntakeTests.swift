import XCTest
@testable import StashKit

/// Reuses `RecordingPoster`/`itemJSON`/`noteJSON` (CaptureViewModelTests.swift / CaptureAPITests.swift)
/// and `UploadRecorder` (OutboxTests.swift) — all `internal`, same test target, no redeclaration.
final class ShareIntakeTests: XCTestCase {
    var dir: URL!            // Outbox directory
    var stagingDir: URL!     // StagedFileStore directory

    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appending(path: "share-intake-outbox-\(UUID().uuidString)")
        stagingDir = FileManager.default.temporaryDirectory.appending(path: "share-intake-staging-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.removeItem(at: stagingDir)
    }

    private func makeIntake(
        poster: RecordingPoster, outbox: Outbox? = nil, staging: StagedFileStore? = nil,
        directSendLimit: Int = 8 * 1024 * 1024,
        upload: @escaping @Sendable (URL, String, String) async throws -> Void = { _, _, _ in }
    ) -> ShareIntake {
        ShareIntake(userId: UUID(), capture: CaptureAPI(poster: poster),
                   outbox: outbox ?? Outbox(directory: dir),
                   staging: staging ?? StagedFileStore(userId: UUID(), directory: stagingDir),
                   directSendLimit: directSendLimit, accessToken: { "jwt" }, upload: upload)
    }

    /// Copies `bytes` into a scratch source file, then stages it via `store` — mirrors how a real
    /// `SharedObject.file` comes to exist (`StagedFileStoreTests.makeSourceFile` + `stage`), so
    /// `stagedURL.pathExtension`/`fileSize(of:)` behave exactly like production call sites.
    private func stageFile(store: StagedFileStore, bytes: Data, ext: String) throws -> URL {
        let source = FileManager.default.temporaryDirectory.appending(path: "src-\(UUID().uuidString).\(ext)")
        try bytes.write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }
        return try store.stage(from: source, fileExtension: ext)
    }

    // MARK: - Brief Step 1, scenario 1: url + note

    func testURLWithNoteCallsAddURLWithNoteAsContent() async {
        let poster = RecordingPoster()
        let intake = makeIntake(poster: poster)

        let result = await intake.submit([.url("https://example.com")], note: "check this out", location: nil)

        XCTAssertEqual(result, ShareIntakeResult(saved: 1))
        XCTAssertEqual(poster.calls.map(\.path), ["add-url"])
        XCTAssertEqual(poster.calls[0].body["url"] as? String, "https://example.com")
        XCTAssertEqual(poster.calls[0].body["content"] as? String, "check this out")
    }

    // MARK: - Brief Step 1, scenario 2: url + 2 files + note

    func testURLPlusTwoFilesPutsNoteOnURLOnlyFilesAreNoteless() async throws {
        let poster = RecordingPoster()
        let store = StagedFileStore(userId: UUID(), directory: stagingDir)
        let staged1 = try stageFile(store: store, bytes: Data([0x01]), ext: "png")
        let staged2 = try stageFile(store: store, bytes: Data([0x02]), ext: "png")
        let intake = makeIntake(poster: poster, staging: store)

        let objects: [SharedObject] = [
            .url("https://example.com"),
            .file(stagedURL: staged1, mimeType: "image/png", fileName: nil, durationS: nil),
            .file(stagedURL: staged2, mimeType: "image/png", fileName: nil, durationS: nil),
        ]
        let result = await intake.submit(objects, note: "ctx", location: nil)

        XCTAssertEqual(result, ShareIntakeResult(saved: 3))
        XCTAssertEqual(poster.calls.map(\.path), ["add-url", "add-file", "add-file"])
        XCTAssertEqual(poster.calls[0].body["content"] as? String, "ctx")
        XCTAssertNil(poster.calls[1].body["content"], "the note already rode the URL unit")
        XCTAssertNil(poster.calls[2].body["content"])
    }

    // MARK: - Brief Step 1, scenario 3: small file

    func testSmallFileUploadsFromStagedURLThenAddFileWithNilContent() async throws {
        let poster = RecordingPoster()
        let store = StagedFileStore(userId: UUID(), directory: stagingDir)
        let staged = try stageFile(store: store, bytes: Data([0x01, 0x02, 0x03]), ext: "png")
        let recorder = UploadRecorder()
        let intake = makeIntake(poster: poster, staging: store, upload: { url, path, type in
            try await recorder.upload(fileURL: url, path: path, contentType: type)
        })

        let result = await intake.submit([.file(stagedURL: staged, mimeType: "image/png", fileName: nil, durationS: nil)],
                                         note: nil, location: nil)

        XCTAssertEqual(result, ShareIntakeResult(saved: 1))
        XCTAssertEqual(recorder.calls.count, 1)
        XCTAssertEqual(recorder.calls[0].fileURL, staged, "upload must be called with the STAGED url directly")
        XCTAssertEqual(recorder.calls[0].contentType, "image/png")
        XCTAssertEqual(poster.calls.map(\.path), ["add-file"])
        XCTAssertNil(poster.calls[0].body["content"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: staged.path),
                       "the staged file must be discarded once its bytes are durably uploaded and registered — " +
                       "otherwise sweepOrphans would later mint a duplicate entry for it")
    }

    // MARK: - Brief Step 1, scenario 4: big file

    func testBigFileNeverUploadsAndEnqueuesWithLocalFilePathRetainingTheStagedFile() async throws {
        let poster = RecordingPoster()
        let store = StagedFileStore(userId: UUID(), directory: stagingDir)
        let staged = try stageFile(store: store, bytes: Data(repeating: 0xAB, count: 20), ext: "bin")
        let recorder = UploadRecorder()
        let outbox = Outbox(directory: dir)
        let intake = makeIntake(poster: poster, outbox: outbox, staging: store, directSendLimit: 10,
                                upload: { url, path, type in try await recorder.upload(fileURL: url, path: path, contentType: type) })

        let result = await intake.submit([.file(stagedURL: staged, mimeType: "application/octet-stream", fileName: nil, durationS: nil)],
                                         note: nil, location: nil)

        XCTAssertEqual(result, ShareIntakeResult(queued: 1))
        XCTAssertTrue(recorder.calls.isEmpty, "a file over the direct-send limit must never be uploaded live")
        XCTAssertTrue(poster.calls.isEmpty, "nor must add-file ever be called for it")
        let pending = await outbox.pending()
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending[0].kind, .file)
        XCTAssertEqual(pending[0].payload["local_file_path"], staged.path)
        XCTAssertEqual(pending[0].payload["mime_type"], "application/octet-stream")
        XCTAssertTrue(FileManager.default.fileExists(atPath: staged.path),
                      "the staged file must be RETAINED — drain uploads it later from this exact path")
    }

    func testFileExactlyAtLimitTakesTheDirectSendPath() async throws {
        let poster = RecordingPoster()
        let store = StagedFileStore(userId: UUID(), directory: stagingDir)
        let staged = try stageFile(store: store, bytes: Data(repeating: 0x01, count: 10), ext: "bin")
        let recorder = UploadRecorder()
        let intake = makeIntake(poster: poster, staging: store, directSendLimit: 10,
                                upload: { url, path, type in try await recorder.upload(fileURL: url, path: path, contentType: type) })

        let result = await intake.submit([.file(stagedURL: staged, mimeType: "application/octet-stream", fileName: nil, durationS: nil)],
                                         note: nil, location: nil)

        XCTAssertEqual(result, ShareIntakeResult(saved: 1))
        XCTAssertEqual(recorder.calls.count, 1, "a file exactly AT the limit must still be sent directly, not queued")
    }

    // MARK: - Brief Step 1, scenario 5: poster throws on url

    func testURLSendFailureFallsBackToOutboxURLEntry() async throws {
        let poster = RecordingPoster(); poster.shouldFail = true
        let outbox = Outbox(directory: dir)
        let intake = makeIntake(poster: poster, outbox: outbox)

        let result = await intake.submit([.url("https://example.com")], note: "ctx", location: nil)

        XCTAssertEqual(result, ShareIntakeResult(queued: 1))
        let pending = await outbox.pending()
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending[0].kind, .url)
        XCTAssertEqual(pending[0].payload["url"], "https://example.com")
        XCTAssertEqual(pending[0].payload["content"], "ctx")
    }

    // MARK: - Brief Step 1, scenario 6: location threads to every unit

    func testLocationThreadsToEveryUnitsAttributes() async throws {
        let poster = RecordingPoster()
        let store = StagedFileStore(userId: UUID(), directory: stagingDir)
        let staged = try stageFile(store: store, bytes: Data([0x01]), ext: "jpg")
        let intake = makeIntake(poster: poster, staging: store)
        let location = CapturedLocation(label: "Testville", source: "device-geolocation")

        let objects: [SharedObject] = [
            .url("https://example.com"),
            .file(stagedURL: staged, mimeType: "image/jpeg", fileName: "photo.jpg", durationS: nil),
        ]
        let result = await intake.submit(objects, note: "hi", location: location)

        XCTAssertEqual(result, ShareIntakeResult(saved: 2))
        XCTAssertEqual(poster.calls.count, 2)
        for call in poster.calls {
            let loc = (call.body["attributes"] as? [String: Any])?["location"] as? [String: Any]
            XCTAssertEqual(loc?["label"] as? String, "Testville", "every unit must carry the same location")
        }
        let media = (poster.calls[1].body["attributes"] as? [String: Any])?["media"] as? [String: Any]
        XCTAssertEqual(media?["file_name"] as? String, "photo.jpg", "per-file media rides alongside the shared location")
    }

    // MARK: - Brief Step 1, scenario 7: outbox enqueue itself fails

    func testEnqueueFailureCountsAsFailedNotSilentlyLost() async throws {
        // A regular FILE at the outbox's directory path — `enqueue`'s write-inside-it must fail,
        // since a file can't contain another file.
        let blocked = FileManager.default.temporaryDirectory.appending(path: "blocked-\(UUID().uuidString)")
        try Data().write(to: blocked)
        defer { try? FileManager.default.removeItem(at: blocked) }
        let poster = RecordingPoster(); poster.shouldFail = true
        let intake = makeIntake(poster: poster, outbox: Outbox(directory: blocked))

        let result = await intake.submit([.url("https://example.com")], note: nil, location: nil)

        XCTAssertEqual(result, ShareIntakeResult(failed: 1), "a send failure whose Outbox fallback ALSO fails must be counted, never silent")
    }

    func testFileEnqueueFailureAlsoCountsAsFailed() async throws {
        let blocked = FileManager.default.temporaryDirectory.appending(path: "blocked-\(UUID().uuidString)")
        try Data().write(to: blocked)
        defer { try? FileManager.default.removeItem(at: blocked) }
        let store = StagedFileStore(userId: UUID(), directory: stagingDir)
        let staged = try stageFile(store: store, bytes: Data(repeating: 0x01, count: 20), ext: "bin")
        let poster = RecordingPoster()
        let intake = makeIntake(poster: poster, outbox: Outbox(directory: blocked), staging: store, directSendLimit: 10)

        let result = await intake.submit([.file(stagedURL: staged, mimeType: "application/octet-stream", fileName: nil, durationS: nil)],
                                         note: nil, location: nil)

        XCTAssertEqual(result, ShareIntakeResult(failed: 1))
        XCTAssertTrue(FileManager.default.fileExists(atPath: staged.path),
                      "a failed enqueue must still retain the staged file — sweepOrphans is the recovery net")
    }

    // MARK: - Disclosed additions beyond the brief's Step 1 list: `.text` objects

    func testTextObjectRoutesToAddNoteWithSharedTextAsContent() async {
        let poster = RecordingPoster()
        let intake = makeIntake(poster: poster)

        let result = await intake.submit([.text("selected text from safari")], note: nil, location: nil)

        XCTAssertEqual(result, ShareIntakeResult(saved: 1))
        XCTAssertEqual(poster.calls.map(\.path), ["add-note"])
        XCTAssertEqual(poster.calls[0].body["content"] as? String, "selected text from safari")
    }

    func testTextObjectWithNoteAppendsNoteAfterTheSharedText() async {
        let poster = RecordingPoster()
        let intake = makeIntake(poster: poster)

        let result = await intake.submit([.text("shared body")], note: "my own take", location: nil)

        XCTAssertEqual(result, ShareIntakeResult(saved: 1))
        let expected = appendNoteParagraph(to: "shared body", note: "my own take")
        XCTAssertEqual(poster.calls[0].body["content"] as? String, expected,
                       "note augments the shared text (appendNoteParagraph), never replaces or drops it")
    }

    func testNonFirstTextObjectNeverReceivesTheNote() async {
        let poster = RecordingPoster()
        let intake = makeIntake(poster: poster)

        let result = await intake.submit([.url("https://example.com"), .text("second unit text")],
                                         note: "goes to url only", location: nil)

        XCTAssertEqual(result, ShareIntakeResult(saved: 2))
        XCTAssertEqual(poster.calls.map(\.path), ["add-url", "add-note"])
        XCTAssertEqual(poster.calls[0].body["content"] as? String, "goes to url only")
        XCTAssertEqual(poster.calls[1].body["content"] as? String, "second unit text",
                       "the note must never leak onto a non-first unit")
    }

    // MARK: - Disclosed additions: failure-ladder nuance + batch bookkeeping

    // Locks down a deliberate, non-obvious design choice: an upload that itself SUCCEEDS but is
    // followed by an addFile failure must still fall back via `local_file_path` (never a maybe-
    // registered `file_path`) — mirrors `CaptureViewModel.submitVoiceNote` exactly.
    func testSmallFileUploadSucceedsButAddFileFailsStillFallsBackViaLocalFilePath() async throws {
        let poster = RecordingPoster(); poster.shouldFail = true
        let store = StagedFileStore(userId: UUID(), directory: stagingDir)
        let staged = try stageFile(store: store, bytes: Data([0x01]), ext: "png")
        let recorder = UploadRecorder()
        let outbox = Outbox(directory: dir)
        let intake = makeIntake(poster: poster, outbox: outbox, staging: store,
                                upload: { url, path, type in try await recorder.upload(fileURL: url, path: path, contentType: type) })

        let result = await intake.submit([.file(stagedURL: staged, mimeType: "image/png", fileName: nil, durationS: nil)],
                                         note: nil, location: nil)

        XCTAssertEqual(result, ShareIntakeResult(queued: 1))
        XCTAssertEqual(recorder.calls.count, 1, "the upload itself must still have been attempted (and succeeded)")
        let pending = await outbox.pending()
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending[0].payload["local_file_path"], staged.path,
                       "fallback must always re-stage via the LOCAL path, never trust an upload that may or may not be registered")
        XCTAssertNil(pending[0].payload["file_path"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: staged.path))
    }

    func testCountsAlwaysSumToObjectCountAcrossMixedOutcomes() async throws {
        let poster = RecordingPoster()   // live sends succeed
        let store = StagedFileStore(userId: UUID(), directory: stagingDir)
        let smallStaged = try stageFile(store: store, bytes: Data([0x01]), ext: "png")
        let bigStaged = try stageFile(store: store, bytes: Data(repeating: 0x02, count: 50), ext: "bin")
        let intake = makeIntake(poster: poster, staging: store, directSendLimit: 10)

        let objects: [SharedObject] = [
            .url("https://example.com"),
            .file(stagedURL: smallStaged, mimeType: "image/png", fileName: nil, durationS: nil),
            .file(stagedURL: bigStaged, mimeType: "application/octet-stream", fileName: nil, durationS: nil),
        ]
        let result = await intake.submit(objects, note: nil, location: nil)

        XCTAssertEqual(result.saved + result.queued + result.failed, objects.count, "no unit may ever be silently dropped")
        XCTAssertEqual(result, ShareIntakeResult(saved: 2, queued: 1))
    }

    func testEmptyObjectsProducesAllZeroResultWithNoCalls() async {
        let poster = RecordingPoster()
        let intake = makeIntake(poster: poster)

        let result = await intake.submit([], note: "irrelevant", location: nil)

        XCTAssertEqual(result, ShareIntakeResult())
        XCTAssertTrue(poster.calls.isEmpty)
    }

    // No session at all (accessToken throws): every unit must queue rather than ever attempting a
    // live send — spec's auth note / plan's "never block the share sheet" rule.
    func testNoSessionQueuesEverythingRatherThanAttemptingASend() async {
        let poster = RecordingPoster()
        let outbox = Outbox(directory: dir)
        let intake = ShareIntake(userId: UUID(), capture: CaptureAPI(poster: poster), outbox: outbox,
                                 staging: StagedFileStore(userId: UUID(), directory: stagingDir),
                                 accessToken: { throw CaptureError.badStatus(401) })

        let result = await intake.submit([.url("https://example.com")], note: "x", location: nil)

        XCTAssertEqual(result, ShareIntakeResult(queued: 1))
        XCTAssertTrue(poster.calls.isEmpty, "with no session, a live send must never even be attempted")
    }
}
