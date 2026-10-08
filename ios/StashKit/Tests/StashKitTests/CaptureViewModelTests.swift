import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import StashKit

/// Plan 15: the composer is outbox-first on the idempotent `capture` endpoint — every test drives
/// it through `FakeCaptureServer` (CaptureTestSupport.swift), which models the endpoint's receipts.
@MainActor
final class CaptureViewModelTests: XCTestCase {
    var dir: URL!
    var stagingDir: URL!
    let userId = UUID()

    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appending(path: "capture-vm-\(UUID().uuidString)")
        stagingDir = FileManager.default.temporaryDirectory.appending(path: "capture-vm-staging-\(UUID().uuidString)")
    }
    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.removeItem(at: stagingDir)
    }

    func makeViewModel(server: FakeCaptureServer,
                       accessToken: @escaping @Sendable () async throws -> String = { "jwt" },
                       awaitPendingLocation: (@Sendable (TimeInterval) async -> CapturedLocation?)? = nil) -> CaptureViewModel {
        CaptureViewModel(
            userId: userId,
            api: CaptureAPI(transport: server),
            outbox: Outbox(directory: dir),
            staging: StagedFileStore(userId: userId, directory: stagingDir),
            accessToken: accessToken,
            awaitPendingLocation: awaitPendingLocation
        )
    }

    private func stagedFiles() -> [URL] {
        StagedFileStore(userId: userId, directory: stagingDir).pendingStaged()
    }

    // MARK: - Routing

    func testURLTextRoutesToAURLCapture() async {
        let server = FakeCaptureServer()
        let vm = makeViewModel(server: server)
        vm.text = "check this out https://example.com cool"

        let outcome = await vm.submit()

        XCTAssertEqual(outcome, .saved(count: 1, dropped: 0))
        XCTAssertEqual(server.captures.map(\.kind), ["url"])
        XCTAssertEqual(server.captures[0].meta["url"] as? String, "https://example.com")
        XCTAssertEqual(server.captures[0].meta["content"] as? String, "check this out cool")
    }

    func testPlainTextRoutesToANoteCapture() async {
        let server = FakeCaptureServer()
        let vm = makeViewModel(server: server)
        vm.text = "buy milk"

        let outcome = await vm.submit()

        XCTAssertEqual(outcome, .saved(count: 1, dropped: 0))
        XCTAssertEqual(server.captures.map(\.kind), ["note"])
        XCTAssertEqual(server.captures[0].meta["content"] as? String, "buy milk")
        let pending = await Outbox(directory: dir).pending()
        XCTAssertTrue(pending.isEmpty, "a delivered capture leaves nothing behind in the Outbox")
    }

    func testOneFileWithTextRoutesToOneFileCaptureWithContent() async {
        let server = FakeCaptureServer()
        let vm = makeViewModel(server: server)
        vm.text = "my screenshot"
        vm.attachments = [CaptureAttachment(data: Data([0x01, 0x02]), fileExtension: "png",
                                            mimeType: "image/png", kind: .photo)]

        let outcome = await vm.submit()

        XCTAssertEqual(outcome, .saved(count: 1, dropped: 0))
        XCTAssertEqual(server.captures.map(\.kind), ["file"])
        XCTAssertEqual(server.captures[0].meta["content"] as? String, "my screenshot")
        XCTAssertTrue(server.captures[0].isMultipart, "a small file rides one multipart request")
        XCTAssertTrue(stagedFiles().isEmpty, "the staged copy is removed once the capture lands")
    }

    // Single-object model (Global Constraints): N attachments always save as N items; the typed note
    // rides `content` on the FIRST unit only.
    func testMultiFileWithTextPutsNoteOnFirstOnly() async {
        let server = FakeCaptureServer()
        let vm = makeViewModel(server: server)
        vm.text = "batch upload"
        vm.attachments = (0..<3).map { _ in
            CaptureAttachment(data: Data([0x01]), fileExtension: "png", mimeType: "image/png", kind: .photo)
        }

        let outcome = await vm.submit()

        XCTAssertEqual(outcome, .saved(count: 3, dropped: 0))
        XCTAssertEqual(server.captures.map(\.kind), ["file", "file", "file"], "no separate note item")
        XCTAssertEqual(server.captures[0].meta["content"] as? String, "batch upload")
        XCTAssertNil(server.captures[1].meta["content"])
        XCTAssertNil(server.captures[2].meta["content"])
        XCTAssertEqual(Set(server.captures.compactMap(\.captureId)).count, 3, "every unit has its own capture id")
    }

    func testURLPlusFilesNoteGoesToURLFirst() async {
        let server = FakeCaptureServer()
        let vm = makeViewModel(server: server)
        vm.text = "check this out https://example.com cool"
        vm.attachments = (0..<2).map { _ in
            CaptureAttachment(data: Data([0x01]), fileExtension: "png", mimeType: "image/png", kind: .photo)
        }

        let outcome = await vm.submit()

        XCTAssertEqual(outcome, .saved(count: 3, dropped: 0))
        XCTAssertEqual(server.captures.map(\.kind), ["url", "file", "file"])
        XCTAssertEqual(server.captures[0].meta["url"] as? String, "https://example.com")
        XCTAssertEqual(server.captures[0].meta["content"] as? String, "check this out cool")
        XCTAssertNil(server.captures[1].meta["content"])
        XCTAssertNil(server.captures[2].meta["content"])
    }

    func testSingleAttachmentWithURLTextMakesTwoUnitsNoteOnURL() async {
        let server = FakeCaptureServer()
        let vm = makeViewModel(server: server)
        vm.text = "check this https://example.com"
        vm.attachments = [CaptureAttachment(data: Data([0x01]), fileExtension: "png", mimeType: "image/png", kind: .photo)]

        let outcome = await vm.submit()

        XCTAssertEqual(outcome, .saved(count: 2, dropped: 0))
        XCTAssertEqual(server.captures.map(\.kind), ["url", "file"])
        XCTAssertEqual(server.captures[0].meta["content"] as? String, "check this")
        XCTAssertNil(server.captures[1].meta["content"], "the note already rode the URL unit")
    }

    // `pendingLocation` threads into EVERY unit's attributes, alongside each file's own media facts.
    func testAttributesThreadToEveryUnit() async {
        let server = FakeCaptureServer()
        let vm = makeViewModel(server: server)
        vm.pendingLocation = CapturedLocation(label: "Testville", source: "device-geolocation")
        vm.attachments = [
            // Not decodable as an image → staged as its original bytes (never dropped), name kept.
            CaptureAttachment(data: Data([0x01]), fileExtension: "jpg", mimeType: "image/jpeg",
                              kind: .photo, fileName: "one.jpg", durationS: nil),
            CaptureAttachment(data: Data([0x02]), fileExtension: "mp4", mimeType: "video/mp4",
                              kind: .file, fileName: "two.mp4", durationS: 9.5),
        ]

        let outcome = await vm.submit()

        XCTAssertEqual(outcome, .saved(count: 2, dropped: 0))
        XCTAssertEqual(server.captures.count, 2)
        for call in server.captures {
            XCTAssertEqual((call.attributes?["location"] as? [String: Any])?["label"] as? String, "Testville")
        }
        let media0 = server.captures[0].attributes?["media"] as? [String: Any]
        XCTAssertEqual(media0?["file_name"] as? String, "one.jpg")
        XCTAssertNil(media0?["duration_s"])
        XCTAssertEqual(server.captures[0].meta["file_name"] as? String, "one.jpg")
        let media1 = server.captures[1].attributes?["media"] as? [String: Any]
        XCTAssertEqual(media1?["file_name"] as? String, "two.mp4")
        XCTAssertEqual(media1?["duration_s"] as? Double, 9.5)
        XCTAssertEqual(server.captures[1].meta["mime_type"] as? String, "video/mp4")
    }

    // MARK: - Plan 15: photos are prepared before upload

    func testPhotoAttachmentIsResizedToAJPEGBeforeUpload() async throws {
        let server = FakeCaptureServer()
        let vm = makeViewModel(server: server)
        let png = try encodeImages([makeSplitImage(width: 3000, height: 2000, left: (1, 0, 0), right: (0, 0, 1))], as: .png)
        vm.attachments = [CaptureAttachment(data: png, fileExtension: "png", mimeType: "image/png",
                                            kind: .photo, fileName: "IMG_0001.PNG")]

        let outcome = await vm.submit()

        XCTAssertEqual(outcome, .saved(count: 1, dropped: 0))
        let call = try XCTUnwrap(server.captures.first)
        XCTAssertEqual(call.meta["mime_type"] as? String, "image/jpeg")
        XCTAssertEqual(call.meta["file_name"] as? String, "IMG_0001.jpg", "extension swapped when re-encoded")
        XCTAssertEqual((call.attributes?["media"] as? [String: Any])?["file_name"] as? String, "IMG_0001.jpg")
        let filePart = try XCTUnwrap(call.filePart)
        XCTAssertEqual(filePart.contentType, "image/jpeg")
        let uploaded = try XCTUnwrap(decodeImage(filePart.data))
        XCTAssertEqual(uploaded.typeIdentifier, UTType.jpeg.identifier)
        XCTAssertEqual(max(uploaded.width, uploaded.height), 2560)
        XCTAssertEqual(call.meta["file_size"] as? Int, filePart.data.count, "file_size describes the bytes actually sent")
    }

    // MARK: - Plan 15: queue instead of drop

    /// The behavior change: a network failure used to DROP an attachment (its upload never
    /// landed); now the bytes are staged to disk and written to the Outbox first, so the unit is
    /// queued and a later drain delivers it — under the same capture id.
    func testNetworkFailureQueuesTheAttachmentInsteadOfDroppingIt() async throws {
        let server = FakeCaptureServer()
        server.captureBehaviors = [.fail(URLError(.notConnectedToInternet))]
        let vm = makeViewModel(server: server)
        let bytes = Data([0x0A, 0x0B, 0x0C])
        vm.attachments = [CaptureAttachment(data: bytes, fileExtension: "pdf", mimeType: "application/pdf",
                                            kind: .file, fileName: "Doc.pdf")]

        let outcome = await vm.submit()

        XCTAssertEqual(outcome, .queued(count: 1, dropped: 0), "a failed send is no longer a drop")
        XCTAssertEqual(vm.pendingOutboxCount, 1)
        let pending = await Outbox(directory: dir).pending()
        XCTAssertEqual(pending.count, 1)
        let staged = try XCTUnwrap(pending[0].payload["local_file_path"])
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: staged)), bytes, "the staged copy holds the exact bytes")
        XCTAssertEqual(pending[0].payload["file_name"], "Doc.pdf")

        await vm.drainOutbox()

        XCTAssertEqual(vm.pendingOutboxCount, 0)
        XCTAssertEqual(server.captures.count, 2)
        XCTAssertEqual(server.captures[1].filePart?.data, bytes)
        XCTAssertEqual(server.captures[0].captureId, server.captures[1].captureId, "the retry reuses the capture id")
        XCTAssertFalse(FileManager.default.fileExists(atPath: staged))
    }

    // MARK: - Plan 15 review: the whole batch is durable before any network call

    /// Every unit is on disk before the token is fetched (it may refresh over the network) and
    /// before the first capture request — a kill while unit 1 uploads can't lose units 2…N.
    func testEveryUnitIsEnqueuedBeforeTheTokenFetchAndTheFirstSend() async throws {
        let server = FakeCaptureServer()
        let directory = dir!
        let atFirstRequest = SnapshotCount()
        server.onRequest = { _ in
            if atFirstRequest.value == nil { atFirstRequest.value = await Outbox(directory: directory).pending().count }
        }
        let atTokenFetch = SnapshotCount()
        let vm = makeViewModel(server: server, accessToken: {
            atTokenFetch.value = await Outbox(directory: directory).pending().count
            return "jwt"
        })
        vm.text = "three things https://example.com"
        vm.attachments = [
            CaptureAttachment(data: Data([0x01]), fileExtension: "png", mimeType: "image/png", kind: .photo),
            CaptureAttachment(data: Data([0x02]), fileExtension: "pdf", mimeType: "application/pdf", kind: .file),
        ]

        let outcome = await vm.submit()

        XCTAssertEqual(outcome, .saved(count: 3, dropped: 0))
        XCTAssertEqual(atTokenFetch.value, 3, "all three units were in the Outbox before the token fetch")
        XCTAssertEqual(atFirstRequest.value, 3, "…and before the first capture request")
    }

    // MARK: - Badge

    /// Background-transfer entries complete on their own — they're not the composer's backlog.
    func testPendingOutboxCountExcludesTransferringEntries() async throws {
        let box = Outbox(directory: dir)
        try await box.enqueue(.note, payload: ["content": "bg", "is_public": "false"], status: .transferring)
        try await box.enqueue(.note, payload: ["content": "waiting", "is_public": "false"])
        let server = FakeCaptureServer()
        server.captureBehaviors = [.fail(URLError(.notConnectedToInternet))]
        let vm = makeViewModel(server: server)

        await vm.drainOutbox()   // the pending one fails; the transferring one isn't touched

        XCTAssertEqual(vm.pendingOutboxCount, 1)
    }

    /// A capture landing anywhere in the app (launch drain, background transfer) re-reads the badge.
    func testStashItemCapturedRefreshesTheBadge() async throws {
        let vm = makeViewModel(server: FakeCaptureServer())
        XCTAssertEqual(vm.pendingOutboxCount, 0)
        try await Outbox(directory: dir).enqueue(.note, payload: ["content": "queued elsewhere", "is_public": "false"])

        let item = try XCTUnwrap(try CaptureTransport.result(
            status: 200, body: JSONSerialization.data(withJSONObject: ["item": FakeCaptureServer.row(kind: "note", meta: [:])])).item)
        await postStashItemCaptured(item, duplicate: false, userId: UUID())

        for _ in 0..<100 where vm.pendingOutboxCount != 1 { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(vm.pendingOutboxCount, 1, "the badge re-reads the Outbox when a capture lands")
    }

    func testFailureEnqueuesToOutboxAndReturnsQueued() async {
        let server = FakeCaptureServer()
        server.captureBehaviors = [.respond(500, "{}")]
        let vm = makeViewModel(server: server)
        vm.text = "offline note"

        let outcome = await vm.submit()

        XCTAssertEqual(outcome, .queued(count: 1, dropped: 0))
        let pending = await Outbox(directory: dir).pending()
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending[0].payload["content"], "offline note")
        XCTAssertEqual(pending[0].attempts, 1)
    }

    /// A lost response (the server created the item, the phone never heard back) is queued, and
    /// the next drain completes it as a duplicate — exactly one item server-side.
    func testLostResponseIsRetriedIdempotentlyByTheNextDrain() async {
        let server = FakeCaptureServer()
        server.captureBehaviors = [.applyThenFail(URLError(.timedOut))]
        let vm = makeViewModel(server: server)
        vm.text = "https://example.com/story"

        let outcome = await vm.submit()
        XCTAssertEqual(outcome, .queued(count: 1, dropped: 0))

        await vm.drainOutbox()

        XCTAssertEqual(server.createdItemCount, 1, "no duplicate item")
        XCTAssertEqual(vm.pendingOutboxCount, 0)
    }

    func testNoSessionStillWritesEveryUnitToTheOutbox() async {
        let server = FakeCaptureServer()
        let vm = makeViewModel(server: server, accessToken: { throw CaptureError.badStatus(401) })
        vm.text = "later"

        let outcome = await vm.submit()

        XCTAssertEqual(outcome, .queued(count: 1, dropped: 0))
        XCTAssertTrue(server.calls.isEmpty, "no session → nothing is sent")
        let pending = await Outbox(directory: dir).pending()
        XCTAssertEqual(pending.count, 1)
    }

    func testSubmitPostsStashItemCaptured() async {
        let server = FakeCaptureServer()
        let vm = makeViewModel(server: server)
        vm.text = "announce me"
        let captured = expectation(forNotification: .stashItemCaptured, object: nil) { note in
            (note.userInfo?["item"] as? Item)?.content == "announce me"
        }

        _ = await vm.submit()

        await fulfillment(of: [captured], timeout: 2)
    }

    // Plan 14 fix wave B (#8, #9): a LIVE 403 subscription_required parks the entry immediately,
    // and a parked entry never inflates the outbox badge.
    func testForegroundSubscriptionRequiredParksEntryInsteadOfPending() async {
        let server = FakeCaptureServer()
        server.captureBehaviors = [.respond(403, subscriptionRequiredBody)]
        let vm = makeViewModel(server: server)
        vm.text = "gate-blocked note"

        let outcome = await vm.submit()

        XCTAssertEqual(outcome, .queued(count: 1, dropped: 0))
        let all = await Outbox(directory: dir).pending()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.status, .parked, "a live subscriptionRequired 403 must leave the entry parked")
        XCTAssertEqual(all.first?.attempts, 0, "parking is not a failed attempt")
    }

    func testPendingOutboxCountExcludesParkedEntries() async {
        let server = FakeCaptureServer()
        server.captureBehaviors = [.respond(403, subscriptionRequiredBody)]
        let vm = makeViewModel(server: server)
        vm.text = "gate-blocked note"

        _ = await vm.submit()

        XCTAssertEqual(vm.pendingOutboxCount, 0, "the gate strip explains a parked entry, not the badge")
    }

    func testOrdinaryFailureStillEnqueuesAsPendingAndCountsTowardBadge() async {
        let server = FakeCaptureServer()
        server.captureBehaviors = [.respond(500, "{}")]
        let vm = makeViewModel(server: server)
        vm.text = "offline note"

        _ = await vm.submit()

        XCTAssertEqual(vm.pendingOutboxCount, 1)
        let all = await Outbox(directory: dir).pending()
        XCTAssertEqual(all.first?.status, .pending)
    }

    // Size limits are the one pre-send rejection left: an oversized non-photo is never staged,
    // enqueued, or sent.

    func testOversizedDocAloneIsRejectedWithNoNetworkCalls() async {
        let server = FakeCaptureServer()
        let vm = makeViewModel(server: server)
        vm.attachments = [CaptureAttachment(data: Data(count: 101 * 1024 * 1024), fileExtension: "pdf",
                                            mimeType: "application/pdf", kind: .file)]

        let outcome = await vm.submit()

        XCTAssertEqual(outcome, .rejected(dropped: 1))
        XCTAssertTrue(server.calls.isEmpty, "an oversized reject must never reach the network")
        XCTAssertTrue(stagedFiles().isEmpty, "nor be staged")
        let pending = await Outbox(directory: dir).pending()
        XCTAssertTrue(pending.isEmpty)
    }

    /// Plan 15 6D: the composer refuses an oversized pick from its file size alone, with this same
    /// helper, before reading the bytes — so the helper must be the exact rule `submit()` applies.
    func testByteLimitIs100MBForEveryFileAndPhotosHaveNone() {
        let mb = 1_048_576
        XCTAssertNil(CaptureAttachment.byteLimit(kind: .photo, mimeType: "image/heic"))
        XCTAssertNil(CaptureAttachment.byteLimit(kind: .photo, mimeType: "video/quicktime"),
                     "kind decides, not the MIME type: a photo is always prepared, never size-rejected")
        XCTAssertEqual(CaptureAttachment.byteLimit(kind: .file, mimeType: "video/quicktime"), 100 * mb)
        XCTAssertEqual(CaptureAttachment.byteLimit(kind: .file, mimeType: "audio/mp4"), 100 * mb)
        XCTAssertEqual(CaptureAttachment.byteLimit(kind: .file, mimeType: "application/pdf"), 100 * mb)
        XCTAssertEqual(CaptureAttachment.byteLimit(kind: .file, mimeType: "application/octet-stream"), 100 * mb)
    }

    func testSubmitAcceptsAFileAtExactlyItsByteLimitAndRejectsOneByteMore() async throws {
        let limit = try XCTUnwrap(CaptureAttachment.byteLimit(kind: .file, mimeType: "application/pdf"))

        let atLimit = FakeCaptureServer()
        let vmAtLimit = makeViewModel(server: atLimit)
        vmAtLimit.attachments = [CaptureAttachment(data: Data(count: limit), fileExtension: "pdf",
                                                   mimeType: "application/pdf", kind: .file)]
        let accepted = await vmAtLimit.submit()
        XCTAssertEqual(accepted, .saved(count: 1, dropped: 0))

        let overLimit = FakeCaptureServer()
        let vmOverLimit = makeViewModel(server: overLimit)
        vmOverLimit.attachments = [CaptureAttachment(data: Data(count: limit + 1), fileExtension: "pdf",
                                                     mimeType: "application/pdf", kind: .file)]
        let rejected = await vmOverLimit.submit()
        XCTAssertEqual(rejected, .rejected(dropped: 1))
        XCTAssertTrue(overLimit.calls.isEmpty)
    }

    func testThreeAttachmentsWithOneOversizedSavesTwoAndDropsOne() async {
        let server = FakeCaptureServer()
        let vm = makeViewModel(server: server)
        let smallPhotos = (0..<2).map { _ in
            CaptureAttachment(data: Data([0x01]), fileExtension: "png", mimeType: "image/png", kind: .photo)
        }
        let oversizedDoc = CaptureAttachment(data: Data(count: 101 * 1024 * 1024), fileExtension: "pdf",
                                             mimeType: "application/pdf", kind: .file)
        vm.attachments = smallPhotos + [oversizedDoc]

        let outcome = await vm.submit()

        XCTAssertEqual(outcome, .saved(count: 2, dropped: 1))
        XCTAssertEqual(server.captures.count, 2)
    }

    // MARK: - Voice notes

    func testSubmitVoiceNoteSuccessSendsOneFileCaptureAndDeletesLocalFile() async throws {
        let server = FakeCaptureServer()
        let vm = makeViewModel(server: server)
        let fileURL = FileManager.default.temporaryDirectory.appending(path: "voice-\(UUID().uuidString).m4a")
        try Data([0x01, 0x02, 0x03]).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let outcome = await vm.submitVoiceNote(fileURL: fileURL)

        XCTAssertEqual(outcome, .saved(count: 1, dropped: 0))
        XCTAssertEqual(server.captures.map(\.kind), ["file"])
        let call = server.captures[0]
        XCTAssertEqual(call.meta["mime_type"] as? String, "audio/mp4")
        XCTAssertEqual(call.meta["file_size"] as? Int, 3)
        XCTAssertNil(call.meta["content"], "voice notes never attach the composer's text as content")
        XCTAssertEqual(call.filePart?.data, Data([0x01, 0x02, 0x03]))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path),
                       "the local recording is deleted once the capture lands")
        let pending = await Outbox(directory: dir).pending()
        XCTAssertTrue(pending.isEmpty)
    }

    func testSubmitVoiceNoteFailureRetainsFileAndEnqueuesOutboxEntryReferencingIt() async throws {
        let server = FakeCaptureServer()
        server.captureBehaviors = [.respond(500, "{}")]
        let vm = makeViewModel(server: server)
        let fileURL = FileManager.default.temporaryDirectory.appending(path: "voice-\(UUID().uuidString).m4a")
        try Data([0x0A, 0x0B]).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let outcome = await vm.submitVoiceNote(fileURL: fileURL)

        XCTAssertEqual(outcome, .queued(count: 1, dropped: 0))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path), "a failed send never deletes the only copy")
        let pending = await Outbox(directory: dir).pending()
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending[0].payload["local_file_path"], fileURL.path)
        XCTAssertEqual(pending[0].payload["mime_type"], "audio/mp4")
        XCTAssertEqual(pending[0].payload["file_size"], "2")
    }

    func testVoiceNoteCarriesMediaAttributes() async throws {
        let server = FakeCaptureServer()
        let vm = makeViewModel(server: server)
        vm.pendingLocation = CapturedLocation(label: "Testville", source: "device-geolocation")
        let fileURL = FileManager.default.temporaryDirectory.appending(path: "voice-\(UUID().uuidString).m4a")
        try Data([0x01, 0x02]).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let outcome = await vm.submitVoiceNote(fileURL: fileURL, durationS: 12.5)

        XCTAssertEqual(outcome, .saved(count: 1, dropped: 0))
        let attributes = try XCTUnwrap(server.captures.first?.attributes)
        XCTAssertEqual((attributes["location"] as? [String: Any])?["label"] as? String, "Testville")
        XCTAssertEqual((attributes["media"] as? [String: Any])?["duration_s"] as? Double, 12.5)
    }

    // MARK: - Location resolution wait (Task 6)
    //
    // NO hook is a true no-op that never touches `pendingLocation`; once a hook IS wired, its
    // result unconditionally REPLACES `pendingLocation`, nil included — a pin the user turned off
    // (or that failed) must be able to clear a location a previous toggle-on cycle left behind.

    func testNoHookIsANoOpAndNeverTouchesAnExistingValue() async {
        let vm = makeViewModel(server: FakeCaptureServer())
        vm.pendingLocation = CapturedLocation(label: "AlreadySet", source: "device-geolocation")
        await vm.awaitPendingLocation(timeout: 2.5)
        XCTAssertEqual(vm.pendingLocation?.label, "AlreadySet")
    }

    func testHookResultReplacesPendingLocationEvenOverwritingADirectlySetValue() async {
        let vm = makeViewModel(server: FakeCaptureServer(),
                               awaitPendingLocation: { _ in CapturedLocation(label: "Resolved", source: "device-geolocation") })
        vm.pendingLocation = CapturedLocation(label: "Stale", source: "device-geolocation")
        await vm.awaitPendingLocation(timeout: 2.5)
        XCTAssertEqual(vm.pendingLocation?.label, "Resolved")
    }

    func testHookReturningNilClearsAPreviouslySetPendingLocation() async {
        let vm = makeViewModel(server: FakeCaptureServer(), awaitPendingLocation: { _ in nil })
        vm.pendingLocation = CapturedLocation(label: "FromAnEarlierSave", source: "device-geolocation")
        await vm.awaitPendingLocation(timeout: 2.5)
        XCTAssertNil(vm.pendingLocation, "a wired hook resolving nil must clear a stale pendingLocation")
    }

    func testSubmitCallsAwaitPendingLocationBeforeSnapshottingAttributes() async {
        let server = FakeCaptureServer()
        let vm = makeViewModel(server: server,
                               awaitPendingLocation: { _ in CapturedLocation(label: "JustResolved", source: "device-geolocation") })
        vm.text = "note while pin resolves"

        let outcome = await vm.submit()

        XCTAssertEqual(outcome, .saved(count: 1, dropped: 0))
        XCTAssertEqual((server.captures[0].attributes?["location"] as? [String: Any])?["label"] as? String, "JustResolved")
    }

    // Pins the literal "≤2.5s" budget (Global Constraints) at the `submit()` call site itself.
    func testSubmitAwaitsExactlyTheDocumentedTimeoutBudget() async {
        let server = FakeCaptureServer()
        let vm = makeViewModel(server: server, awaitPendingLocation: { timeout in
            timeout == 2.5 ? CapturedLocation(label: "SawExpectedTimeout", source: "device-geolocation") : nil
        })
        vm.text = "note"

        _ = await vm.submit()

        XCTAssertEqual((server.captures[0].attributes?["location"] as? [String: Any])?["label"] as? String,
                       "SawExpectedTimeout", "submit() must await with the documented ≤2.5s budget")
    }

    func testSubmitVoiceNoteCallsAwaitPendingLocationBeforeSnapshottingAttributes() async throws {
        let server = FakeCaptureServer()
        let vm = makeViewModel(server: server,
                               awaitPendingLocation: { _ in CapturedLocation(label: "VoiceResolved", source: "device-geolocation") })
        let fileURL = FileManager.default.temporaryDirectory.appending(path: "voice-\(UUID().uuidString).m4a")
        try Data([0x01]).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let outcome = await vm.submitVoiceNote(fileURL: fileURL)

        XCTAssertEqual(outcome, .saved(count: 1, dropped: 0))
        XCTAssertEqual((server.captures[0].attributes?["location"] as? [String: Any])?["label"] as? String, "VoiceResolved")
    }

    // End-to-end: a location left over from an earlier batch must not ride along once the hook
    // resolves nil — no `attributes` at all (never-send-`{}`).
    func testSubmitDoesNotAttachAStaleLocationOnceTheHookResolvesNil() async {
        let server = FakeCaptureServer()
        let vm = makeViewModel(server: server, awaitPendingLocation: { _ in nil })
        vm.pendingLocation = CapturedLocation(label: "FromAnEarlierSave", source: "device-geolocation")
        vm.text = "a fresh note with the pin off"

        let outcome = await vm.submit()

        XCTAssertEqual(outcome, .saved(count: 1, dropped: 0))
        XCTAssertNil(server.captures[0].meta["attributes"], "the stale location must be cleared")
    }

    // MARK: - Plan 15 final wave: durable before the pin wait (mirrors the share sheet)

    /// Save with the pin still resolving: the form clears and the capture is in the Outbox BEFORE
    /// the ≤ 2.5 s pin wait starts — a kill during that wait loses nothing — and the location that
    /// arrives within it is merged into the queued entry, so the capture still carries it.
    func testSubmitWritesTheOutboxBeforeWaitingOnAResolvingPinThenAddsTheLateLocation() async throws {
        let server = FakeCaptureServer()
        let pin = ResolvingPin()
        let vm = makeViewModel(server: server, awaitPendingLocation: { await pin.resolution(timeout: $0) })
        vm.text = "saved while the pin resolves https://example.com/pin"
        vm.attachments = [CaptureAttachment(data: Data([0x01]), fileExtension: "pdf", mimeType: "application/pdf",
                                            kind: .file, fileName: "notes.pdf")]

        let submission = Task { await vm.submit() }
        for _ in 0..<300 where !pin.isWaiting { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(pin.isWaiting, "submit() should be waiting on the resolving pin")

        XCTAssertEqual(vm.text, "", "the form cleared at Save")
        let queued = await Outbox(directory: dir).pending()
        XCTAssertEqual(queued.map(\.kind), [.url, .file], "every unit is on disk before the pin wait")
        XCTAssertNil(queued[0].payload["attributes_json"], "no location yet on the URL")
        XCTAssertFalse(queued[1].payload["attributes_json"]?.contains("location") ?? false)
        XCTAssertTrue(server.captures.isEmpty, "nothing is sent before the pin had its chance")

        pin.resolve(CapturedLocation(label: "Late Pin", source: "device-geolocation"))
        let outcome = await submission.value

        XCTAssertEqual(outcome, .saved(count: 2, dropped: 0))
        XCTAssertEqual(server.captures.count, 2)
        for call in server.captures {
            XCTAssertEqual((call.attributes?["location"] as? [String: Any])?["label"] as? String, "Late Pin")
        }
        XCTAssertEqual((server.captures[1].attributes?["media"] as? [String: Any])?["file_name"] as? String,
                       "notes.pdf", "the file's media facts survive the merge")
    }

    /// A pin that doesn't resolve within the wait leaves the queued capture exactly as it was
    /// saved — still sent, just without a location.
    func testSubmitSendsWithoutALocationWhenTheResolvingPinComesUpEmpty() async throws {
        let server = FakeCaptureServer()
        let pin = ResolvingPin()
        let vm = makeViewModel(server: server, awaitPendingLocation: { await pin.resolution(timeout: $0) })
        vm.text = "the pin never resolves"

        let submission = Task { await vm.submit() }
        for _ in 0..<300 where !pin.isWaiting { try await Task.sleep(for: .milliseconds(10)) }
        let queued = await Outbox(directory: dir).pending()
        XCTAssertEqual(queued.count, 1)
        pin.resolve(nil)
        let outcome = await submission.value

        XCTAssertEqual(outcome, .saved(count: 1, dropped: 0))
        XCTAssertNil(server.captures[0].meta["attributes"])
    }

    /// The voice-note path is enqueue-first too: the recording's entry (with its visibility and
    /// duration) exists before the pin wait, and the late location is merged in before the send.
    func testSubmitVoiceNoteWritesItsEntryBeforeWaitingOnAResolvingPin() async throws {
        let server = FakeCaptureServer()
        let pin = ResolvingPin()
        let vm = makeViewModel(server: server, awaitPendingLocation: { await pin.resolution(timeout: $0) })
        let fileURL = FileManager.default.temporaryDirectory.appending(path: "voice-\(UUID().uuidString).m4a")
        try Data([0x01, 0x02]).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let submission = Task { await vm.submitVoiceNote(fileURL: fileURL, durationS: 4) }
        for _ in 0..<300 where !pin.isWaiting { try await Task.sleep(for: .milliseconds(10)) }
        let queued = await Outbox(directory: dir).pending()
        XCTAssertEqual(queued.count, 1, "the recording's entry is written before the pin wait")
        XCTAssertEqual(queued.first?.payload["local_file_path"], fileURL.path)
        XCTAssertTrue(server.captures.isEmpty)

        pin.resolve(CapturedLocation(label: "Voice Late", source: "device-geolocation"))
        let outcome = await submission.value

        XCTAssertEqual(outcome, .saved(count: 1, dropped: 0))
        let attributes = try XCTUnwrap(server.captures.first?.attributes)
        XCTAssertEqual((attributes["location"] as? [String: Any])?["label"] as? String, "Voice Late")
        XCTAssertEqual((attributes["media"] as? [String: Any])?["duration_s"] as? Double, 4)
    }
}

/// A location pin that is still resolving when Save is tapped: an immediate look
/// (`timeout == 0`) finds nothing, and a real wait parks until the test resolves it.
private final class ResolvingPin: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<CapturedLocation?, Never>?
    private var resolved = false
    private var result: CapturedLocation?

    var isWaiting: Bool { lock.withLock { continuation != nil } }

    func resolution(timeout: TimeInterval) async -> CapturedLocation? {
        guard timeout > 0 else { return nil }
        return await withCheckedContinuation { continuation in
            let answerNow = lock.withLock { () -> Bool in
                if resolved { return true }
                self.continuation = continuation
                return false
            }
            if answerNow { continuation.resume(returning: lock.withLock { result }) }
        }
    }

    func resolve(_ location: CapturedLocation?) {
        let waiting = lock.withLock { () -> CheckedContinuation<CapturedLocation?, Never>? in
            resolved = true
            result = location
            defer { continuation = nil }
            return continuation
        }
        waiting?.resume(returning: location)
    }
}
