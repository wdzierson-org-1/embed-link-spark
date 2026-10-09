import XCTest
@testable import StashKit

/// Plan 15: `ShareIntake` is outbox-first on the idempotent `capture` endpoint. Reuses
/// `FakeCaptureServer` (CaptureTestSupport.swift) and `UploadRecorder` (OutboxTests.swift).
final class ShareIntakeTests: XCTestCase {
    var dir: URL!            // Outbox directory
    var stagingDir: URL!     // StagedFileStore directory
    let userId = UUID()

    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appending(path: "share-intake-outbox-\(UUID().uuidString)")
        stagingDir = FileManager.default.temporaryDirectory.appending(path: "share-intake-staging-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.removeItem(at: stagingDir)
    }

    private func makeIntake(
        server: FakeCaptureServer, outbox: Outbox? = nil, staging: StagedFileStore? = nil,
        directSendLimit: Int = 8 * 1024 * 1024,
        accessToken: @escaping @Sendable () async throws -> String = { "jwt" },
        upload: (@Sendable (URL, String, String) async throws -> Void)? = nil
    ) -> ShareIntake {
        ShareIntake(userId: userId, capture: CaptureAPI(transport: server),
                    outbox: outbox ?? Outbox(directory: dir),
                    staging: staging ?? StagedFileStore(userId: userId, directory: stagingDir),
                    directSendLimit: directSendLimit, accessToken: accessToken, upload: upload)
    }

    /// Copies `bytes` into a scratch source file, then stages it via `store` — mirrors how a real
    /// `SharedObject.file` comes to exist.
    private func stageFile(store: StagedFileStore, bytes: Data, ext: String) throws -> URL {
        let source = FileManager.default.temporaryDirectory.appending(path: "src-\(UUID().uuidString).\(ext)")
        try bytes.write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }
        return try store.stage(from: source, fileExtension: ext)
    }

    // MARK: - url + note

    func testYouTubeURLSharedAsPlainTextSendsURLCapture() async {
        let server = FakeCaptureServer()
        let intake = makeIntake(server: server)
        let url = "https://youtube.com/watch?v=_U-O5lYhJ7Q&si=N1xyTmW5PSajXyPK"

        let result = await intake.submit([.text(" \n\(url)\n ")], note: "watch later", location: nil)

        XCTAssertEqual(result, ShareIntakeResult(saved: 1))
        XCTAssertEqual(server.captures.map(\.kind), ["url"])
        XCTAssertEqual(server.captures.first?.meta["url"] as? String, url)
        XCTAssertEqual(server.captures.first?.meta["content"] as? String, "watch later")
    }

    func testPlainTextURLBackgroundHandoffCarriesURLAndNote() async {
        let server = FakeCaptureServer()
        let intake = makeIntake(server: server)
        let url = "https://youtu.be/kYkIdXwW2AE?si=coT_PmgpGgcdndlj&t=38"

        let entries = await intake.enqueueForTransfer([.text(url)], note: "listen", location: nil)

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.kind, .url)
        XCTAssertEqual(entries.first?.payload["url"], url)
        XCTAssertEqual(entries.first?.payload["content"], "listen")
        XCTAssertTrue(server.captures.isEmpty, "handoff must remain outbox-first")
    }

    func testProseContainingURLRemainsASharedNote() async {
        let server = FakeCaptureServer()
        let intake = makeIntake(server: server)
        let text = "Research notes: https://youtube.com/watch?v=YGgNBcIgI4s explains the topic."

        _ = await intake.submit([.text(text)], note: nil, location: nil)

        XCTAssertEqual(server.captures.map(\.kind), ["note"])
        XCTAssertEqual(server.captures.first?.meta["content"] as? String, text)
        XCTAssertNil(server.captures.first?.meta["url"])
    }

    func testCredentialAndMalformedURLsRemainSharedNotes() async {
        let server = FakeCaptureServer()
        let intake = makeIntake(server: server)
        let texts = [
            "https://someone:secret@example.com/video",
            "https://someone@example.com/video",
            "https://example.com/\\video",
            "https://example.com/<video>",
            "https://example.com/\"video\"",
            "https://example.com/`video`",
            "https://example.com/vi\u{0000}deo",
            "https://example.com/vi\u{007F}deo",
        ]

        _ = await intake.submit(texts.map(SharedObject.text), note: nil, location: nil)

        XCTAssertEqual(server.captures.map(\.kind), Array(repeating: "note", count: texts.count))
        XCTAssertEqual(server.captures.compactMap { $0.meta["content"] as? String }, texts)
        XCTAssertTrue(server.captures.allSatisfy { $0.meta["url"] == nil })
    }

    func testOnlyWholeHTTPURLsArePromotedFromSharedText() {
        let notes: [SharedObject] = [
            .text("file:///private/tmp/movie.mp4"),
            .text("youtube.com/watch?v=YGgNBcIgI4s"),
            .text("https://"),
            .text("https:///watch?v=YGgNBcIgI4s"),
            .text("https://youtube.com/watch?v=one https://youtube.com/watch?v=two"),
            .text("A title\nhttps://youtube.com/watch?v=YGgNBcIgI4s"),
        ]
        XCTAssertEqual(ShareIntake.reorderURLFirst(notes), notes)
    }

    func testPlainTextURLIsPromotedBeforeURLFirstOrdering() {
        let url = "https://youtube.com/watch?v=YGgNBcIgI4s&si=eghyyWDS4gvPWLR4"
        XCTAssertEqual(ShareIntake.reorderURLFirst([.text("context"), .text(url)]),
                       [.url(url), .text("context")])
    }

    func testURLWithNoteSendsAURLCaptureWithNoteAsContent() async {
        let server = FakeCaptureServer()
        let intake = makeIntake(server: server)

        let result = await intake.submit([.url("https://example.com")], note: "check this out", location: nil)

        XCTAssertEqual(result, ShareIntakeResult(saved: 1))
        XCTAssertEqual(server.captures.map(\.kind), ["url"])
        XCTAssertEqual(server.captures[0].meta["url"] as? String, "https://example.com")
        XCTAssertEqual(server.captures[0].meta["content"] as? String, "check this out")
        XCTAssertEqual(server.captures[0].meta["is_public"] as? Bool, false)
        let pending = await Outbox(directory: dir).pending()
        XCTAssertTrue(pending.isEmpty, "a delivered share leaves nothing queued")
    }

    // MARK: - url + 2 files + note

    func testURLPlusTwoFilesPutsNoteOnURLOnlyFilesAreNoteless() async throws {
        let server = FakeCaptureServer()
        let store = StagedFileStore(userId: userId, directory: stagingDir)
        let staged1 = try stageFile(store: store, bytes: Data([0x01]), ext: "png")
        let staged2 = try stageFile(store: store, bytes: Data([0x02]), ext: "png")
        let intake = makeIntake(server: server, staging: store)

        let objects: [SharedObject] = [
            .url("https://example.com"),
            .file(stagedURL: staged1, mimeType: "image/png", fileName: nil, durationS: nil),
            .file(stagedURL: staged2, mimeType: "image/png", fileName: nil, durationS: nil),
        ]
        let result = await intake.submit(objects, note: "ctx", location: nil)

        XCTAssertEqual(result, ShareIntakeResult(saved: 3))
        XCTAssertEqual(server.captures.map(\.kind), ["url", "file", "file"])
        XCTAssertEqual(server.captures[0].meta["content"] as? String, "ctx")
        XCTAssertNil(server.captures[1].meta["content"], "the note already rode the URL unit")
        XCTAssertNil(server.captures[2].meta["content"])
    }

    // MARK: - Plan 15 review: the whole share is durable before any network call

    func testEveryObjectIsEnqueuedBeforeTheTokenFetchAndTheFirstSend() async throws {
        let server = FakeCaptureServer()
        let directory = dir!
        let atFirstRequest = SnapshotCount()
        server.onRequest = { _ in
            if atFirstRequest.value == nil { atFirstRequest.value = await Outbox(directory: directory).pending().count }
        }
        let atTokenFetch = SnapshotCount()
        let store = StagedFileStore(userId: userId, directory: stagingDir)
        let staged = try stageFile(store: store, bytes: Data([0x01]), ext: "png")
        let intake = makeIntake(server: server, staging: store, accessToken: {
            atTokenFetch.value = await Outbox(directory: directory).pending().count
            return "jwt"
        })

        let result = await intake.submit([.url("https://example.com"), .text("quote"),
                                          .file(stagedURL: staged, mimeType: "image/png", fileName: nil, durationS: nil)],
                                         note: "n", location: nil)

        XCTAssertEqual(result, ShareIntakeResult(saved: 3))
        XCTAssertEqual(atTokenFetch.value, 3, "all three objects were in the Outbox before the token fetch")
        XCTAssertEqual(atFirstRequest.value, 3, "…and before the first capture request")
    }

    // MARK: - small file

    func testSmallFileGoesAsOneMultipartCaptureAndTheStagedCopyIsDiscarded() async throws {
        let server = FakeCaptureServer()
        let store = StagedFileStore(userId: userId, directory: stagingDir)
        let bytes = Data([0x01, 0x02, 0x03])
        let staged = try stageFile(store: store, bytes: bytes, ext: "png")
        let recorder = UploadRecorder()
        let intake = makeIntake(server: server, staging: store, upload: recorder.closure)

        let result = await intake.submit([.file(stagedURL: staged, mimeType: "image/png", fileName: "shot.png", durationS: nil)],
                                         note: nil, location: nil)

        XCTAssertEqual(result, ShareIntakeResult(saved: 1))
        XCTAssertTrue(recorder.calls.isEmpty, "within the one-shot limit, no separate storage upload")
        let call = try XCTUnwrap(server.captures.first)
        XCTAssertTrue(call.isMultipart)
        XCTAssertEqual(call.filePart?.data, bytes)
        XCTAssertEqual(call.meta["mime_type"] as? String, "image/png")
        XCTAssertEqual(call.meta["file_size"] as? Int, 3)
        XCTAssertEqual(call.meta["file_name"] as? String, "shot.png")
        XCTAssertNil(call.meta["content"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: staged.path),
                       "the staged file must be discarded once captured — otherwise sweepOrphans would " +
                       "later mint a duplicate entry for it")
    }

    // MARK: - big file (over the foreground direct-send limit)

    func testBigFileIsQueuedNotSentAndTheStagedFileIsRetained() async throws {
        let server = FakeCaptureServer()
        let store = StagedFileStore(userId: userId, directory: stagingDir)
        let staged = try stageFile(store: store, bytes: Data(repeating: 0xAB, count: 20), ext: "bin")
        let outbox = Outbox(directory: dir)
        let intake = makeIntake(server: server, outbox: outbox, staging: store, directSendLimit: 10)

        let result = await intake.submit([.file(stagedURL: staged, mimeType: "application/octet-stream", fileName: nil, durationS: nil)],
                                         note: nil, location: nil)

        XCTAssertEqual(result, ShareIntakeResult(queued: 1))
        XCTAssertTrue(server.calls.isEmpty, "a file over the direct-send limit is never sent from the share sheet")
        let pending = await outbox.pending()
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending[0].kind, .file)
        XCTAssertEqual(pending[0].status, .pending)
        XCTAssertEqual(pending[0].payload["local_file_path"], staged.path)
        XCTAssertEqual(pending[0].payload["mime_type"], "application/octet-stream")
        XCTAssertEqual(pending[0].payload["file_size"], "20")
        XCTAssertTrue(FileManager.default.fileExists(atPath: staged.path), "the app's drain sends it later from this path")
    }

    func testFileExactlyAtLimitTakesTheDirectSendPath() async throws {
        let server = FakeCaptureServer()
        let store = StagedFileStore(userId: userId, directory: stagingDir)
        let staged = try stageFile(store: store, bytes: Data(repeating: 0x01, count: 10), ext: "bin")
        let intake = makeIntake(server: server, staging: store, directSendLimit: 10)

        let result = await intake.submit([.file(stagedURL: staged, mimeType: "application/octet-stream", fileName: nil, durationS: nil)],
                                         note: nil, location: nil)

        XCTAssertEqual(result, ShareIntakeResult(saved: 1))
        XCTAssertEqual(server.captures.count, 1, "a file exactly AT the limit is still sent directly")
    }

    // MARK: - send failures queue

    func testURLSendFailureLeavesAQueuedURLEntry() async throws {
        let server = FakeCaptureServer()
        server.captureBehaviors = [.respond(500, "{}")]
        let outbox = Outbox(directory: dir)
        let intake = makeIntake(server: server, outbox: outbox)

        let result = await intake.submit([.url("https://example.com")], note: "ctx", location: nil)

        XCTAssertEqual(result, ShareIntakeResult(queued: 1))
        let pending = await outbox.pending()
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending[0].kind, .url)
        XCTAssertEqual(pending[0].payload["url"], "https://example.com")
        XCTAssertEqual(pending[0].payload["content"], "ctx")
        XCTAssertEqual(pending[0].attempts, 1)
        XCTAssertEqual(server.captures.first?.captureId, pending[0].id.uuidString.lowercased(),
                       "the queued entry keeps the capture id its first attempt used")
    }

    func testFileSendFailureKeepsTheStagedFileForTheRetry() async throws {
        let server = FakeCaptureServer()
        server.captureBehaviors = [.fail(URLError(.networkConnectionLost))]
        let store = StagedFileStore(userId: userId, directory: stagingDir)
        let staged = try stageFile(store: store, bytes: Data([0x01]), ext: "png")
        let outbox = Outbox(directory: dir)
        let intake = makeIntake(server: server, outbox: outbox, staging: store)

        let result = await intake.submit([.file(stagedURL: staged, mimeType: "image/png", fileName: nil, durationS: nil)],
                                         note: nil, location: nil)

        XCTAssertEqual(result, ShareIntakeResult(queued: 1))
        let pending = await outbox.pending()
        XCTAssertEqual(pending.first?.payload["local_file_path"], staged.path)
        XCTAssertNil(pending.first?.payload["file_path"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: staged.path))
    }

    func testSubscriptionRequiredParksTheSharedEntry() async {
        let server = FakeCaptureServer()
        server.captureBehaviors = [.respond(403, subscriptionRequiredBody)]
        let outbox = Outbox(directory: dir)
        let intake = makeIntake(server: server, outbox: outbox)

        let result = await intake.submit([.url("https://example.com")], note: nil, location: nil)

        XCTAssertEqual(result, ShareIntakeResult(queued: 1))
        let pending = await outbox.pending()
        XCTAssertEqual(pending.first?.status, .parked)
    }

    // MARK: - location threads to every unit

    func testLocationThreadsToEveryUnitsAttributes() async throws {
        let server = FakeCaptureServer()
        let store = StagedFileStore(userId: userId, directory: stagingDir)
        let staged = try stageFile(store: store, bytes: Data([0x01]), ext: "jpg")
        let intake = makeIntake(server: server, staging: store)
        let location = CapturedLocation(label: "Testville", source: "device-geolocation")

        let objects: [SharedObject] = [
            .url("https://example.com"),
            .file(stagedURL: staged, mimeType: "image/jpeg", fileName: "photo.jpg", durationS: nil),
        ]
        let result = await intake.submit(objects, note: "hi", location: location)

        XCTAssertEqual(result, ShareIntakeResult(saved: 2))
        XCTAssertEqual(server.captures.count, 2)
        for call in server.captures {
            XCTAssertEqual((call.attributes?["location"] as? [String: Any])?["label"] as? String, "Testville")
        }
        XCTAssertEqual((server.captures[1].attributes?["media"] as? [String: Any])?["file_name"] as? String, "photo.jpg")
    }

    // MARK: - the Outbox write itself fails

    func testEnqueueFailureCountsAsFailedNotSilentlyLost() async throws {
        // A regular FILE at the outbox's directory path — `enqueue`'s write-inside-it must fail.
        let blocked = FileManager.default.temporaryDirectory.appending(path: "blocked-\(UUID().uuidString)")
        try Data().write(to: blocked)
        defer { try? FileManager.default.removeItem(at: blocked) }
        let server = FakeCaptureServer()
        let intake = makeIntake(server: server, outbox: Outbox(directory: blocked))

        let result = await intake.submit([.url("https://example.com")], note: nil, location: nil)

        XCTAssertEqual(result, ShareIntakeResult(failed: 1), "an Outbox write failure must be counted, never silent")
        XCTAssertTrue(server.calls.isEmpty, "outbox-first: nothing is sent that wasn't persisted first")
    }

    func testFileEnqueueFailureAlsoCountsAsFailedAndKeepsTheStagedFile() async throws {
        let blocked = FileManager.default.temporaryDirectory.appending(path: "blocked-\(UUID().uuidString)")
        try Data().write(to: blocked)
        defer { try? FileManager.default.removeItem(at: blocked) }
        let store = StagedFileStore(userId: userId, directory: stagingDir)
        let staged = try stageFile(store: store, bytes: Data(repeating: 0x01, count: 20), ext: "bin")
        let intake = makeIntake(server: FakeCaptureServer(), outbox: Outbox(directory: blocked), staging: store)

        let result = await intake.submit([.file(stagedURL: staged, mimeType: "application/octet-stream", fileName: nil, durationS: nil)],
                                         note: nil, location: nil)

        XCTAssertEqual(result, ShareIntakeResult(failed: 1))
        XCTAssertTrue(FileManager.default.fileExists(atPath: staged.path), "sweepOrphans is the recovery net")
    }

    // MARK: - `.text` objects

    func testTextObjectSendsANoteCaptureWithTheSharedText() async {
        let server = FakeCaptureServer()
        let intake = makeIntake(server: server)

        let result = await intake.submit([.text("selected text from safari")], note: nil, location: nil)

        XCTAssertEqual(result, ShareIntakeResult(saved: 1))
        XCTAssertEqual(server.captures.map(\.kind), ["note"])
        XCTAssertEqual(server.captures[0].meta["content"] as? String, "selected text from safari")
    }

    func testTextObjectWithNoteAppendsNoteAfterTheSharedText() async {
        let server = FakeCaptureServer()
        let intake = makeIntake(server: server)

        let result = await intake.submit([.text("shared body")], note: "my own take", location: nil)

        XCTAssertEqual(result, ShareIntakeResult(saved: 1))
        XCTAssertEqual(server.captures[0].meta["content"] as? String, appendNoteParagraph(to: "shared body", note: "my own take"),
                       "note augments the shared text, never replaces or drops it")
    }

    func testNonFirstTextObjectNeverReceivesTheNote() async {
        let server = FakeCaptureServer()
        let intake = makeIntake(server: server)

        let result = await intake.submit([.url("https://example.com"), .text("second unit text")],
                                         note: "goes to url only", location: nil)

        XCTAssertEqual(result, ShareIntakeResult(saved: 2))
        XCTAssertEqual(server.captures.map(\.kind), ["url", "note"])
        XCTAssertEqual(server.captures[0].meta["content"] as? String, "goes to url only")
        XCTAssertEqual(server.captures[1].meta["content"] as? String, "second unit text")
    }

    func testTextSendFailureLeavesAQueuedNoteEntry() async {
        let server = FakeCaptureServer()
        server.captureBehaviors = [.respond(500, "{}")]
        let outbox = Outbox(directory: dir)
        let intake = makeIntake(server: server, outbox: outbox)

        let result = await intake.submit([.text("shared body")], note: nil, location: nil)

        XCTAssertEqual(result, ShareIntakeResult(queued: 1))
        let pending = await outbox.pending()
        XCTAssertEqual(pending.first?.kind, .note)
        XCTAssertEqual(pending.first?.payload["content"], "shared body")
    }

    // MARK: - queued entries carry note + attributes

    func testQueuedURLEntryCarriesAttributesJSONForLocation() async throws {
        let server = FakeCaptureServer()
        server.captureBehaviors = [.respond(500, "{}")]
        let outbox = Outbox(directory: dir)
        let intake = makeIntake(server: server, outbox: outbox)

        _ = await intake.submit([.url("https://example.com")], note: "ctx",
                                location: CapturedLocation(label: "Testville", source: "device-geolocation"))

        let pending = await outbox.pending()
        let json = try XCTUnwrap(pending.first?.payload["attributes_json"])
        let decoded = try JSONDecoder().decode(ItemAttributes.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.location?.label, "Testville")
    }

    func testBigFileQueuedEntryCarriesNoteNameAndAttributesJSON() async throws {
        let store = StagedFileStore(userId: userId, directory: stagingDir)
        let staged = try stageFile(store: store, bytes: Data(repeating: 0xAB, count: 20), ext: "bin")
        let outbox = Outbox(directory: dir)
        let intake = makeIntake(server: FakeCaptureServer(), outbox: outbox, staging: store, directSendLimit: 10)

        let result = await intake.submit(
            [.file(stagedURL: staged, mimeType: "application/octet-stream", fileName: "big.bin", durationS: nil)],
            note: "big file note", location: CapturedLocation(label: "Testville", source: "device-geolocation"))

        XCTAssertEqual(result, ShareIntakeResult(queued: 1))
        let pending = await outbox.pending()
        XCTAssertEqual(pending.first?.payload["content"], "big file note")
        XCTAssertEqual(pending.first?.payload["file_name"], "big.bin")
        let json = try XCTUnwrap(pending.first?.payload["attributes_json"])
        let decoded = try JSONDecoder().decode(ItemAttributes.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.location?.label, "Testville")
        XCTAssertEqual(decoded.media?.fileName, "big.bin")
    }

    // MARK: - batch bookkeeping

    func testCountsAlwaysSumToObjectCountAcrossMixedOutcomes() async throws {
        let server = FakeCaptureServer()
        let store = StagedFileStore(userId: userId, directory: stagingDir)
        let smallStaged = try stageFile(store: store, bytes: Data([0x01]), ext: "png")
        let bigStaged = try stageFile(store: store, bytes: Data(repeating: 0x02, count: 50), ext: "bin")
        let intake = makeIntake(server: server, staging: store, directSendLimit: 10)

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
        let server = FakeCaptureServer()
        let result = await makeIntake(server: server).submit([], note: "irrelevant", location: nil)
        XCTAssertEqual(result, ShareIntakeResult())
        XCTAssertTrue(server.calls.isEmpty)
    }

    // No session at all: every unit is still written to the Outbox, none is sent.
    func testNoSessionQueuesEverythingRatherThanAttemptingASend() async {
        let server = FakeCaptureServer()
        let outbox = Outbox(directory: dir)
        let intake = makeIntake(server: server, outbox: outbox, accessToken: { throw CaptureError.badStatus(401) })

        let result = await intake.submit([.url("https://example.com")], note: "x", location: nil)

        XCTAssertEqual(result, ShareIntakeResult(queued: 1))
        XCTAssertTrue(server.calls.isEmpty, "with no session, a live send must never even be attempted")
        let pending = await outbox.pending()
        XCTAssertEqual(pending.count, 1)
    }

    // MARK: - enqueueForTransfer (plan 15, for Task 4)

    func testEnqueueForTransferWritesTransferringEntriesInOrderWithoutSending() async throws {
        let server = FakeCaptureServer()
        let store = StagedFileStore(userId: userId, directory: stagingDir)
        let staged = try stageFile(store: store, bytes: Data([0x01, 0x02]), ext: "jpg")
        let startedAt = Date(timeIntervalSince1970: 1_950_000_000)
        let outbox = Outbox(directory: dir, now: { startedAt })
        let intake = makeIntake(server: server, outbox: outbox, staging: store)
        let location = CapturedLocation(label: "Testville", source: "device-geolocation")

        let entries = await intake.enqueueForTransfer(
            [.url("https://example.com"), .text("quote"),
             .file(stagedURL: staged, mimeType: "image/jpeg", fileName: "IMG_1.jpg", durationS: nil)],
            note: "  my note  ", location: location)

        XCTAssertTrue(server.calls.isEmpty, "the background session sends them — nothing goes out here")
        XCTAssertEqual(entries.map(\.kind), [.url, .note, .file])
        XCTAssertTrue(entries.allSatisfy { $0.status == .transferring && $0.transferStartedAt == startedAt })
        XCTAssertEqual(entries[0].payload["content"], "my note", "the trimmed note rides the first object only")
        XCTAssertEqual(entries[1].payload["content"], "quote")
        XCTAssertEqual(entries[2].payload["local_file_path"], staged.path)
        XCTAssertEqual(entries[2].payload["file_size"], "2")
        XCTAssertEqual(entries[2].payload["file_name"], "IMG_1.jpg")
        XCTAssertNil(entries[2].payload["content"])
        let persisted = await outbox.pending()
        XCTAssertEqual(Set(persisted.map(\.id)), Set(entries.map(\.id)))
        XCTAssertTrue(FileManager.default.fileExists(atPath: staged.path), "the transfer still needs the staged file")

        // A drain right away leaves them to the background transfer (their stamp is fresh).
        let appOutbox = Outbox(directory: dir)
        let sentNow = await appOutbox.drain(api: CaptureAPI(transport: server), accessToken: "jwt", userId: userId)
        XCTAssertEqual(sentNow, 0)
    }

    // MARK: - Background hand-off helpers (plan 15, Task 4)

    func testUsableTransferTokenNeedsFiveMinutesOfValidityLeft() {
        let now = Date(timeIntervalSince1970: 1_900_000_000)
        XCTAssertEqual(ShareIntake.usableTransferToken("t", expiresAt: now.addingTimeInterval(3600), now: now), "t")
        XCTAssertEqual(ShareIntake.usableTransferToken("t", expiresAt: now.addingTimeInterval(300), now: now), "t")
        XCTAssertNil(ShareIntake.usableTransferToken("t", expiresAt: now.addingTimeInterval(299), now: now))
        XCTAssertNil(ShareIntake.usableTransferToken("t", expiresAt: now.addingTimeInterval(-10), now: now), "already expired")
    }

    func testRefreshedTransferTokenReturnsTheRefreshedToken() async {
        let token = await ShareIntake.refreshedTransferToken(timeout: 2) { "refreshed" }
        XCTAssertEqual(token, "refreshed")
    }

    func testRefreshedTransferTokenIsNilWhenTheRefreshFails() async {
        let token = await ShareIntake.refreshedTransferToken(timeout: 2) { throw CaptureError.badStatus(400) }
        XCTAssertNil(token)
    }

    func testRefreshedTransferTokenGivesUpAtTheTimeoutEvenIfTheRefreshIgnoresCancellation() async {
        let started = Date()
        let token = await ShareIntake.refreshedTransferToken(timeout: 0.2) {
            // Ignores cancellation on purpose: the caller must not wait for it anyway.
            let until = Date().addingTimeInterval(3)
            while Date() < until { try? await Task.sleep(for: .milliseconds(50)) }
            return "too late"
        }
        XCTAssertNil(token)
        XCTAssertLessThan(Date().timeIntervalSince(started), 1.5, "bounded by the timeout, not by the refresh")
    }

    // MARK: - withDeadline (final wave: composer picks, background-wake token fetches)

    func testWithDeadlineReturnsTheWorksResultWhenItFinishesInTime() async {
        let value = await withDeadline(.seconds(2), fallback: "fallback") { "done" }
        XCTAssertEqual(value, "done")
    }

    /// A stalled transfer (an iCloud photo that never arrives) must not hold its caller: the
    /// fallback comes back at the deadline even though the work ignores cancellation.
    func testWithDeadlineGivesUpAtTheDeadlineEvenIfTheWorkIgnoresCancellation() async {
        let started = Date()
        let value = await withDeadline(.milliseconds(200), fallback: "timed out") { () -> String in
            let until = Date().addingTimeInterval(3)
            while Date() < until { try? await Task.sleep(for: .milliseconds(50)) }
            return "too late"
        }
        XCTAssertEqual(value, "timed out")
        XCTAssertLessThan(Date().timeIntervalSince(started), 1.5, "bounded by the deadline, not by the work")
    }

    /// Final wave review: the timer doesn't outlive a quick answer (it used to sleep out the whole
    /// deadline — up to 60 s for a composer pick).
    func testWithDeadlineStopsItsTimerOnceTheWorkAnswers() async throws {
        let timerCancelled = SnapshotCount()
        let value = await withDeadline(fallback: "fallback", deadline: {
            try? await Task.sleep(for: .seconds(30))
            if Task.isCancelled { timerCancelled.value = 1 }
        }) { "done" }
        XCTAssertEqual(value, "done")
        for _ in 0..<200 where timerCancelled.value == nil { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(timerCancelled.value, 1, "the timer is cancelled as soon as the work has answered")
    }

    func testWithDeadlineCancelsTheWorkItGaveUpOn() async throws {
        let cancelled = SnapshotCount()
        _ = await withDeadline(.milliseconds(100), fallback: 0) { () -> Int in
            try? await Task.sleep(for: .seconds(5))
            if Task.isCancelled { cancelled.value = 1 }
            return 1
        }
        for _ in 0..<100 where cancelled.value == nil { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(cancelled.value, 1, "the abandoned work is told to stop")
    }

    func testSendInForegroundSendsTheGivenEntriesOverTheIdempotentEndpoint() async throws {
        let server = FakeCaptureServer()
        let outbox = Outbox(directory: dir)
        let intake = makeIntake(server: server, outbox: outbox)
        let entries = await intake.enqueueForTransfer([.url("https://example.com/a"), .url("https://example.com/b")],
                                                      note: nil, location: nil, status: .pending)

        let result = await intake.sendInForeground(entries.map(\.id), accessToken: "jwt", timeout: 5)

        XCTAssertEqual(result, ShareIntakeResult(saved: 2))
        XCTAssertEqual(server.captures.map(\.captureId), entries.map { $0.id.uuidString.lowercased() })
        let left = await outbox.pending()
        XCTAssertTrue(left.isEmpty)
    }

    func testSendInForegroundStopsAtItsDeadlineAndLeavesTheRestForTheApp() async throws {
        let transport = SlowTransport(delay: .milliseconds(500))
        let outbox = Outbox(directory: dir)
        let intake = ShareIntake(userId: userId, capture: CaptureAPI(transport: transport), outbox: outbox,
                                 staging: StagedFileStore(userId: userId, directory: stagingDir), accessToken: { "jwt" })
        let entries = await intake.enqueueForTransfer(
            [.url("https://example.com/1"), .url("https://example.com/2"), .url("https://example.com/3")], note: nil,
            location: nil, status: .pending)
        let started = Date()

        let result = await intake.sendInForeground(entries.map(\.id), accessToken: "jwt", timeout: 0.75)

        XCTAssertLessThan(Date().timeIntervalSince(started), 1.5, "never runs past its bound")
        XCTAssertEqual(result, ShareIntakeResult(saved: 1, queued: 2))
        let second = await outbox.entry(id: entries[1].id)
        XCTAssertEqual(second?.status, .pending, "the request cut off at the deadline stays queued")
        XCTAssertEqual(second?.attempts, 1)
        let third = await outbox.entry(id: entries[2].id)
        XCTAssertEqual(third?.attempts, 0, "never tried — left untouched for the app")
        XCTAssertEqual(transport.completedCount, 1)
    }

    func testSendInForegroundLeavesFilesOverTheDirectSendLimitForTheApp() async throws {
        let server = FakeCaptureServer()
        let store = StagedFileStore(userId: userId, directory: stagingDir)
        let staged = try stageFile(store: store, bytes: Data(repeating: 0x01, count: 64), ext: "mov")
        let outbox = Outbox(directory: dir)
        let intake = makeIntake(server: server, outbox: outbox, staging: store, directSendLimit: 16)
        let entries = await intake.enqueueForTransfer(
            [.file(stagedURL: staged, mimeType: "video/quicktime", fileName: nil, durationS: nil)], note: nil,
            location: nil, status: .pending)

        let result = await intake.sendInForeground(entries.map(\.id), accessToken: "jwt")

        XCTAssertEqual(result, ShareIntakeResult(queued: 1))
        XCTAssertTrue(server.calls.isEmpty)
    }

    // MARK: - Late location (plan 15 review: the confirmation never waits on the pin)

    func testEnqueueForTransferCanPersistPendingForTheApp() async throws {
        let outbox = Outbox(directory: dir)
        let intake = makeIntake(server: FakeCaptureServer(), outbox: outbox)

        let entries = await intake.enqueueForTransfer([.url("https://example.com")], note: "n", location: nil, status: .pending)

        XCTAssertEqual(entries.map(\.status), [.pending])
        XCTAssertNil(entries.first?.transferStartedAt)
    }

    func testAttachLocationMergesIntoEveryEntrysAttributesKeepingTheRest() async throws {
        let store = StagedFileStore(userId: userId, directory: stagingDir)
        let staged = try stageFile(store: store, bytes: Data([0x01, 0x02]), ext: "jpg")
        let outbox = Outbox(directory: dir)
        let server = FakeCaptureServer()
        let intake = makeIntake(server: server, outbox: outbox, staging: store)
        let entries = await intake.enqueueForTransfer(
            [.url("https://example.com"), .file(stagedURL: staged, mimeType: "image/jpeg", fileName: "IMG_7.jpg", durationS: nil)],
            note: "late pin", location: nil, status: .pending)
        XCTAssertNil(entries[0].payload["attributes_json"], "no location yet")

        let updated = await intake.attachLocation(CapturedLocation(label: "Testville", source: "device-geolocation"),
                                                  to: entries)

        XCTAssertEqual(updated.map(\.id), entries.map(\.id))
        for entry in updated {
            let attributes = try XCTUnwrap(CaptureTransport.attributesObject(from: entry.payload["attributes_json"]))
            XCTAssertEqual((attributes["location"] as? [String: Any])?["label"] as? String, "Testville")
        }
        let fileAttributes = try XCTUnwrap(CaptureTransport.attributesObject(from: updated[1].payload["attributes_json"]))
        XCTAssertEqual((fileAttributes["media"] as? [String: Any])?["file_name"] as? String, "IMG_7.jpg", "media kept")
        XCTAssertEqual(updated[0].payload["content"], "late pin", "the rest of the payload untouched")
        let persisted = await outbox.entry(id: entries[1].id)
        XCTAssertEqual(persisted?.payload["attributes_json"], updated[1].payload["attributes_json"], "written to disk")

        // What the server then receives carries the location.
        _ = await intake.sendInForeground(updated.map(\.id), accessToken: "jwt")
        XCTAssertEqual((server.captures.first?.attributes?["location"] as? [String: Any])?["label"] as? String, "Testville")
    }

    func testAttachLocationSkipsAnEntryTheAppAlreadySent() async throws {
        let outbox = Outbox(directory: dir)
        let intake = makeIntake(server: FakeCaptureServer(), outbox: outbox)
        let entries = await intake.enqueueForTransfer([.url("https://example.com/a"), .url("https://example.com/b")],
                                                      note: nil, location: nil, status: .pending)
        await outbox.complete(id: entries[0].id)

        let updated = await intake.attachLocation(CapturedLocation(label: "Testville", source: "device-geolocation"),
                                                  to: entries)

        XCTAssertEqual(updated.map(\.id), [entries[1].id])
        let resurrected = await outbox.entry(id: entries[0].id)
        XCTAssertNil(resurrected, "never re-created")
    }

    // MARK: - `ProviderLoader` ordering decision — `reorderURLFirst`

    func testReorderURLFirstMovesURLToFront() {
        let objects: [SharedObject] = [.text("a"), .url("https://example.com"), .text("b")]
        XCTAssertEqual(ShareIntake.reorderURLFirst(objects), [.url("https://example.com"), .text("a"), .text("b")])
    }

    func testReorderURLFirstIsNoOpWhenNoURLPresent() {
        let objects: [SharedObject] = [.text("a"), .text("b")]
        XCTAssertEqual(ShareIntake.reorderURLFirst(objects), objects)
    }

    func testReorderURLFirstIsNoOpWhenURLAlreadyFirst() {
        let objects: [SharedObject] = [.url("https://example.com"), .text("a")]
        XCTAssertEqual(ShareIntake.reorderURLFirst(objects), objects)
    }

    func testReorderURLFirstOnEmptyOrURLOnlyObjectsIsANoOp() {
        XCTAssertEqual(ShareIntake.reorderURLFirst([]), [])
        XCTAssertEqual(ShareIntake.reorderURLFirst([.url("https://example.com")]), [.url("https://example.com")])
    }
}

/// A capture transport where every request takes `delay` and honors cancellation (like
/// `URLSession`'s async API): a request cancelled mid-flight throws, a finished one answers 200.
private final class SlowTransport: CaptureTransporting, @unchecked Sendable {
    private let delay: Duration
    private let lock = NSLock()
    private var _completed = 0
    var completedCount: Int { lock.withLock { _completed } }

    init(delay: Duration) { self.delay = delay }

    func upload(_ request: URLRequest, fromFile bodyFile: URL) async throws -> (status: Int, body: Data) {
        try await Task.sleep(for: delay)
        lock.withLock { _completed += 1 }
        let body = try JSONSerialization.data(withJSONObject: ["item": FakeCaptureServer.row(kind: "url", meta: [:]),
                                                               "duplicate": false])
        return (200, body)
    }
}
