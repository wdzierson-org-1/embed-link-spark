import XCTest
@testable import StashKit

/// Plan 15 Task 4: the share extension's background transfers — the task description format, the
/// pure completion decision, `start`, the completion handling (whichever process runs it), the
/// app's events flow, and the maintenance helpers. The real background `URLSession` needs the
/// system's transfer daemon, so a `FakeUploadSession` stands in for it; the Outbox, request
/// building and body files are all real.
final class BackgroundCaptureTransfersTests: XCTestCase {
    var outboxDir: URL!
    var stagingDir: URL!
    var bodyDir: URL!
    let userId = UUID()

    override func setUp() {
        let root = FileManager.default.temporaryDirectory.appending(path: "bg-transfers-\(UUID().uuidString)")
        outboxDir = root.appending(path: "outbox")
        stagingDir = root.appending(path: "staging")
        bodyDir = root.appending(path: "StashTransfers")
        try? FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: outboxDir.deletingLastPathComponent())
    }

    // MARK: - Fixtures

    /// Records what `start` hands the session — the body is read at start time, since a
    /// completion deletes its body file.
    final class FakeUploadSession: BackgroundUploadSession, @unchecked Sendable {
        struct Upload {
            let request: URLRequest
            let file: URL
            let taskDescription: String
            let body: Data
            var descriptor: BackgroundTransferDescriptor? { BackgroundTransferDescriptor(taskDescription: taskDescription) }
            var meta: [String: Any] { (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:] }
        }
        private let lock = NSLock()
        private var _uploads: [Upload] = []
        private var _invalidated = false
        var onInvalidate: (() -> Void)?

        var uploads: [Upload] { lock.withLock { _uploads } }
        var invalidated: Bool { lock.withLock { _invalidated } }

        func startUpload(_ request: URLRequest, fromFile file: URL, taskDescription: String) {
            let upload = Upload(request: request, file: file, taskDescription: taskDescription,
                                body: (try? Data(contentsOf: file)) ?? Data())
            lock.withLock { _uploads.append(upload) }
        }

        func finishTasksAndInvalidate() {
            lock.withLock { _invalidated = true }
            onInvalidate?()
        }
    }

    final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var _value = 0
        var value: Int { lock.withLock { _value } }
        func increment() { lock.withLock { _value += 1 } }
    }

    final class TestClock: @unchecked Sendable {
        private let lock = NSLock()
        private var _now: Date
        init(_ now: Date) { _now = now }
        var now: Date {
            get { lock.withLock { _now } }
            set { lock.withLock { _now = newValue } }
        }
    }

    struct Harness {
        let transfers: BackgroundCaptureTransfers
        let session: FakeUploadSession
        let sessionsCreated: Counter
        let outbox: Outbox
        let server: FakeCaptureServer
    }

    /// A `BackgroundCaptureTransfers` over this test's directories, a fake session, and (for the
    /// foreground fallback) `server`.
    func makeHarness(outbox: Outbox? = nil, token: String? = "jwt", postsNotifications: Bool = true,
                     oneShotLimit: Int = CaptureAPI.oneShotFileLimit,
                     server: FakeCaptureServer = FakeCaptureServer()) -> Harness {
        let outbox = outbox ?? Outbox(directory: outboxDir)
        let session = FakeUploadSession()
        let created = Counter()
        let transfers = BackgroundCaptureTransfers(
            bodyDirectory: bodyDir,
            outboxForUser: { _ in outbox },
            accessTokenForUser: { _ in token },
            postsCaptureNotifications: postsNotifications,
            oneShotLimit: oneShotLimit,
            sessionFactory: { _ in
                created.increment()
                return session
            },
            foregroundSend: { outbox, entryId, userId, token in
                _ = await outbox.sendNow(id: entryId, api: CaptureAPI(transport: server), userId: userId, accessToken: token)
            })
        return Harness(transfers: transfers, session: session, sessionsCreated: created, outbox: outbox, server: server)
    }

    func stageFile(bytes: Data, ext: String) throws -> URL {
        let url = stagingDir.appending(path: "\(UUID().uuidString).\(ext)")
        try bytes.write(to: url)
        return url
    }

    func enqueueURL(_ outbox: Outbox, note: String = "n") async throws -> OutboxEntry {
        try await outbox.enqueue(.url, payload: ["url": "https://example.com/\(UUID().uuidString)", "content": note,
                                                 "is_public": "false"], status: .transferring)
    }

    func enqueueFile(_ outbox: Outbox, at url: URL, mime: String = "image/jpeg", name: String = "IMG_1.jpg") async throws -> OutboxEntry {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        return try await outbox.enqueue(.file, payload: ["local_file_path": url.path, "mime_type": mime, "file_size": String(size),
                                                         "file_name": name, "is_public": "false"], status: .transferring)
    }

    func bodyFiles() -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: bodyDir, includingPropertiesForKeys: nil)) ?? []
    }

    /// The server's 200 for a capture (`item` null → an idempotent replay of a deleted row).
    func captureOK(kind: String = "url", content: String = "n", duplicate: Bool = false, item: Bool = true) -> Data {
        let row: Any = item ? FakeCaptureServer.row(kind: kind, meta: ["content": content]) : NSNull()
        return try! JSONSerialization.data(withJSONObject: ["item": row, "duplicate": duplicate])
    }

    /// Delivers one finished task the way the delegate does (body in two chunks), then waits for
    /// its completion to be applied.
    func finish(_ harness: Harness, upload: FakeUploadSession.Upload, taskIdentifier: Int = 1,
                status: Int?, body: Data = Data(), error: Error? = nil) async {
        if !body.isEmpty {
            let split = body.count / 2
            harness.transfers.didReceive(body.prefix(split), forTask: taskIdentifier)
            harness.transfers.didReceive(body.suffix(from: split), forTask: taskIdentifier)
        }
        harness.transfers.didComplete(taskIdentifier: taskIdentifier, taskDescription: upload.taskDescription,
                                      statusCode: status, error: error)
        await harness.transfers.waitForIdle()
    }

    // MARK: - Task description

    func testDescriptorFormatIsUserEntryPhaseLowercased() {
        let entryId = UUID()
        let descriptor = BackgroundTransferDescriptor(userId: userId, entryId: entryId, phase: .capture)
        XCTAssertEqual(descriptor.taskDescription,
                       "\(userId.uuidString.lowercased())|\(entryId.uuidString.lowercased())|capture")
        XCTAssertEqual(BackgroundTransferDescriptor(taskDescription: descriptor.taskDescription), descriptor)
        let storage = BackgroundTransferDescriptor(userId: userId, entryId: entryId, phase: .storage)
        XCTAssertEqual(BackgroundTransferDescriptor(taskDescription: storage.taskDescription), storage)
        XCTAssertEqual(BackgroundTransferDescriptor(taskDescription: "\(userId.uuidString)|\(entryId.uuidString)|storage"),
                       storage, "upper-case ids parse too")
    }

    func testDescriptorRejectsAnythingElse() {
        let a = UUID().uuidString, b = UUID().uuidString
        for bad in [nil, "", "x", "\(a)|\(b)", "\(a)|\(b)|upload", "\(a)|\(b)|capture|extra", "nope|\(b)|capture",
                    "\(a)|nope|capture", "\(a)||capture"] {
            XCTAssertNil(BackgroundTransferDescriptor(taskDescription: bad), "\(bad ?? "nil") must not parse")
        }
    }

    // MARK: - Decision (pure)

    func decide(_ phase: BackgroundTransferPhase, _ status: Int?, _ body: String = "", error: Error? = nil)
        -> BackgroundTransferDecision {
        BackgroundTransferDecision.decide(phase: phase, statusCode: status, body: Data(body.utf8), error: error)
    }

    /// `decide` for the `capture` phase.
    func decide(_ status: Int?, _ body: String = "", error: Error? = nil) -> BackgroundTransferDecision {
        decide(.capture, status, body, error: error)
    }

    func testDecision2xxCaptureCompletesWithTheItem() throws {
        let body = captureOK(content: "hello")
        guard case .complete(let result) = BackgroundTransferDecision.decide(phase: .capture, statusCode: 200, body: body, error: nil) else {
            return XCTFail("expected .complete")
        }
        XCTAssertEqual(result.item?.content, "hello")
        XCTAssertFalse(result.duplicate)
        XCTAssertEqual(BackgroundTransferDecision.decide(phase: .capture, statusCode: 201, body: body, error: nil),
                       .complete(try CaptureTransport.result(status: 201, body: body)))
    }

    func testDecisionDuplicateWithDeletedRowStillCompletes() {
        XCTAssertEqual(BackgroundTransferDecision.decide(phase: .capture, statusCode: 200,
                                                         body: captureOK(duplicate: true, item: false), error: nil),
                       .complete(CaptureResult(item: nil, duplicate: true)))
    }

    func testDecision2xxThatIsNotTheEndpointsJSONIsARetry() {
        XCTAssertEqual(decide(200, "<html>proxy</html>"), .retry(countsAsAttempt: true))
        XCTAssertEqual(decide(200, ""), .retry(countsAsAttempt: true))
    }

    func testDecision2xxStorageCheckpointsThenCaptures() {
        XCTAssertEqual(decide(.storage, 200, #"{"Key":"stash-media/u/e.jpg"}"#), .checkpointThenCapture)
        XCTAssertEqual(decide(.storage, 200), .checkpointThenCapture)
    }

    func testDecision403SubscriptionRequiredParksAnyOther403Retries() {
        XCTAssertEqual(decide(403, subscriptionRequiredBody), .park)
        XCTAssertEqual(decide(403, #"{"error":"agent tokens cannot capture"}"#), .retry(countsAsAttempt: true))
        XCTAssertEqual(decide(.storage, 403, #"{"statusCode":"403","error":"Unauthorized"}"#), .retry(countsAsAttempt: true))
    }

    func testDecision409InProgressRetriesWithoutCountingAnAttempt() {
        XCTAssertEqual(decide(409, captureInProgressBody), .retry(countsAsAttempt: false))
        XCTAssertEqual(decide(409, #"{"error":"conflict"}"#), .retry(countsAsAttempt: true))
    }

    func testDecision413FileTooLargeGoesTwoStepOther413sRetry() {
        XCTAssertEqual(decide(413, #"{"error":"file_too_large"}"#), .retryTwoStep)
        XCTAssertEqual(decide(413, #"{"error":"meta_too_large"}"#), .retry(countsAsAttempt: true))
        XCTAssertEqual(decide(413, "Request Entity Too Large"), .retry(countsAsAttempt: true))
        XCTAssertEqual(decide(.storage, 413, #"{"statusCode":"413","error":"Payload too large"}"#), .retry(countsAsAttempt: true))
    }

    func testDecisionOther4xxAnd5xxRetryCountingAnAttempt() {
        for status in [400, 404, 422, 429, 500, 502, 503, 504] {
            XCTAssertEqual(decide(status, #"{"error":"x"}"#), .retry(countsAsAttempt: true), "status \(status)")
            XCTAssertEqual(decide(.storage, status, #"{"error":"x"}"#), .retry(countsAsAttempt: true), "storage status \(status)")
        }
    }

    func testDecisionTransportErrorsRetryCountingAnAttemptExceptSessionInUse() {
        for code: URLError.Code in [.timedOut, .notConnectedToInternet, .networkConnectionLost, .cancelled, .cannotConnectToHost] {
            XCTAssertEqual(decide(nil, error: URLError(code)), .retry(countsAsAttempt: true), "\(code)")
        }
        XCTAssertEqual(decide(nil, error: URLError(.backgroundSessionInUseByAnotherProcess)), .retry(countsAsAttempt: false),
                       "nothing was sent: another process was connected to the session")
        XCTAssertEqual(decide(nil, error: NSError(domain: NSURLErrorDomain, code: NSURLErrorBackgroundSessionInUseByAnotherProcess)),
                       .retry(countsAsAttempt: false))
        XCTAssertEqual(decide(nil, error: CocoaError(.fileReadNoSuchFile)), .retry(countsAsAttempt: true))
    }

    func testDecisionTransportErrorWinsOverAPartialResponse() {
        XCTAssertEqual(BackgroundTransferDecision.decide(phase: .capture, statusCode: 200, body: captureOK(),
                                                         error: URLError(.networkConnectionLost)),
                       .retry(countsAsAttempt: true))
    }

    func testDecisionWithNeitherStatusNorErrorRetries() {
        XCTAssertEqual(decide(nil), .retry(countsAsAttempt: true))
    }

    // MARK: - start

    func testStartWritesTheJSONBodyToTheTransfersDirectoryAndStartsACaptureTask() async throws {
        let harness = makeHarness(token: "tok")
        let entry = try await enqueueURL(harness.outbox, note: "my note")

        let batch = await harness.transfers.start(entries: [entry], userId: userId, accessToken: "tok")

        XCTAssertEqual(batch.started, [entry.id])
        XCTAssertEqual(batch.notStarted, [])
        let upload = try XCTUnwrap(harness.session.uploads.first)
        XCTAssertEqual(harness.session.uploads.count, 1)
        XCTAssertEqual(upload.descriptor, BackgroundTransferDescriptor(userId: userId, entryId: entry.id, phase: .capture))
        XCTAssertEqual(upload.request.url?.path, "/functions/v1/capture")
        XCTAssertEqual(upload.request.httpMethod, "POST")
        XCTAssertEqual(upload.request.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
        XCTAssertEqual(upload.request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(upload.file.deletingLastPathComponent().standardizedFileURL, bodyDir.standardizedFileURL,
                       "the body lives in the App Group transfers directory, readable after the extension is gone")
        XCTAssertTrue(upload.file.lastPathComponent.hasPrefix(entry.id.uuidString.lowercased() + "-"))
        XCTAssertEqual(upload.meta["capture_id"] as? String, entry.id.uuidString.lowercased())
        XCTAssertEqual(upload.meta["kind"] as? String, "url")
        XCTAssertEqual(upload.meta["content"] as? String, "my note")
        let stored = await harness.outbox.entry(id: entry.id)
        XCTAssertEqual(stored?.status, .transferring)
    }

    func testStartSendsASmallFileAsOneMultipartCapture() async throws {
        let harness = makeHarness()
        let staged = try stageFile(bytes: Data([0xFF, 0xD8, 0x01, 0x02]), ext: "jpg")
        let entry = try await enqueueFile(harness.outbox, at: staged)

        _ = await harness.transfers.start(entries: [entry], userId: userId, accessToken: "jwt")

        let upload = try XCTUnwrap(harness.session.uploads.first)
        XCTAssertEqual(upload.descriptor?.phase, .capture)
        XCTAssertTrue(upload.request.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data") ?? false)
        XCTAssertTrue(upload.file.lastPathComponent.hasSuffix(".multipart"))
        XCTAssertTrue(upload.body.range(of: Data([0xFF, 0xD8, 0x01, 0x02])) != nil, "the file bytes ride the body")
        XCTAssertTrue(FileManager.default.fileExists(atPath: staged.path), "the staged file stays until the capture lands")
    }

    func testStartSendsABigFileToStorageFirstStreamingTheStagedFileItself() async throws {
        let harness = makeHarness(oneShotLimit: 8)
        let staged = try stageFile(bytes: Data(repeating: 0xAB, count: 20), ext: "mov")
        let entry = try await enqueueFile(harness.outbox, at: staged, mime: "video/quicktime", name: "clip.mov")

        let batch = await harness.transfers.start(entries: [entry], userId: userId, accessToken: "jwt")

        XCTAssertEqual(batch.started, [entry.id])
        let upload = try XCTUnwrap(harness.session.uploads.first)
        XCTAssertEqual(upload.descriptor?.phase, .storage)
        XCTAssertEqual(upload.request.url?.path,
                       "/storage/v1/object/stash-media/\(userId.uuidString.lowercased())/\(entry.id.uuidString.lowercased()).mov")
        XCTAssertEqual(upload.request.value(forHTTPHeaderField: "x-upsert"), "true")
        XCTAssertEqual(upload.file.standardizedFileURL, staged.standardizedFileURL)
        XCTAssertTrue(bodyFiles().isEmpty, "a Storage upsert writes no body file")
    }

    func testStartRestampsTheTransferAtTheMomentItStarts() async throws {
        let clock = TestClock(Date(timeIntervalSince1970: 1_900_000_000))
        let outbox = Outbox(directory: outboxDir, now: { clock.now })
        let harness = makeHarness(outbox: outbox)
        let entry = try await enqueueURL(outbox)
        clock.now = Date(timeIntervalSince1970: 1_900_000_042)

        _ = await harness.transfers.start(entries: [entry], userId: userId, accessToken: "jwt")

        let stored = await outbox.entry(id: entry.id)
        XCTAssertEqual(stored?.transferStartedAt, Date(timeIntervalSince1970: 1_900_000_042))
    }

    func testStartLeavesAnEntryItCannotBuildPendingAndReportsIt() async throws {
        let harness = makeHarness()
        let missing = stagingDir.appending(path: "gone.jpg")
        let unreadable = try await enqueueFile(harness.outbox, at: missing)
        let foreign = try await harness.outbox.enqueue(.file, payload: ["file_path": "\(UUID().uuidString.lowercased())/x.jpg",
                                                                        "mime_type": "image/jpeg", "is_public": "false"],
                                                       status: .transferring)
        let fine = try await enqueueURL(harness.outbox)

        let batch = await harness.transfers.start(entries: [unreadable, foreign, fine], userId: userId, accessToken: "jwt")

        XCTAssertEqual(batch.started, [fine.id])
        XCTAssertEqual(batch.notStarted, [unreadable.id, foreign.id])
        for id in [unreadable.id, foreign.id] {
            let stored = await harness.outbox.entry(id: id)
            XCTAssertEqual(stored?.status, .pending)
            XCTAssertEqual(stored?.attempts, 0, "nothing was sent, so no attempt is counted")
        }
        XCTAssertEqual(harness.session.uploads.count, 1)
        XCTAssertEqual(bodyFiles().count, 1, "no body is left behind for an entry that didn't start")
    }

    func testStartSkipsAnEntryParkedInTheMeantimeAndLeavesNoBody() async throws {
        let harness = makeHarness()
        let entry = try await enqueueURL(harness.outbox)
        await harness.outbox.park(id: entry.id)

        let batch = await harness.transfers.start(entries: [entry], userId: userId, accessToken: "jwt")

        XCTAssertEqual(batch.started, [])
        XCTAssertEqual(batch.notStarted, [])
        XCTAssertTrue(harness.session.uploads.isEmpty)
        XCTAssertTrue(bodyFiles().isEmpty)
        let stored = await harness.outbox.entry(id: entry.id)
        XCTAssertEqual(stored?.status, .parked)
    }

    func testStartReusesOneSessionPerProcess() async throws {
        let harness = makeHarness()
        let first = try await enqueueURL(harness.outbox)
        _ = await harness.transfers.start(entries: [first], userId: userId, accessToken: "jwt")
        let second = try await enqueueURL(harness.outbox)
        _ = await harness.transfers.start(entries: [second], userId: userId, accessToken: "jwt")
        XCTAssertEqual(harness.sessionsCreated.value, 1)
        XCTAssertEqual(harness.session.uploads.count, 2)
    }

    // MARK: - Completion

    func test2xxCaptureCompletesTheEntryDeletesStagedAndBodyFilesAndPostsInApp() async throws {
        let harness = makeHarness()
        let staged = try stageFile(bytes: Data([0x01, 0x02, 0x03]), ext: "jpg")
        let entry = try await enqueueFile(harness.outbox, at: staged)
        _ = await harness.transfers.start(entries: [entry], userId: userId, accessToken: "jwt")
        let upload = try XCTUnwrap(harness.session.uploads.first)
        XCTAssertTrue(FileManager.default.fileExists(atPath: upload.file.path))
        let expectedUser = userId
        let posted = expectation(forNotification: .stashItemCaptured, object: nil) { note in
            (note.userInfo?["item"] as? Item) != nil && (note.userInfo?["duplicate"] as? Bool) == false
                && (note.userInfo?["userId"] as? UUID) == expectedUser
        }

        await finish(harness, upload: upload, status: 200, body: captureOK(kind: "file"))

        let gone = await harness.outbox.entry(id: entry.id)
        XCTAssertNil(gone, "the entry is completed")
        XCTAssertFalse(FileManager.default.fileExists(atPath: staged.path), "the staged file is deleted with it")
        XCTAssertTrue(bodyFiles().isEmpty, "the request body is always deleted")
        await fulfillment(of: [posted], timeout: 2)
    }

    func test2xxCaptureInTheExtensionPostsNothing() async throws {
        let harness = makeHarness(postsNotifications: false)
        let entry = try await enqueueURL(harness.outbox)
        _ = await harness.transfers.start(entries: [entry], userId: userId, accessToken: "jwt")
        let posted = expectation(forNotification: .stashItemCaptured, object: nil)
        posted.isInverted = true

        await finish(harness, upload: harness.session.uploads[0], status: 200, body: captureOK())

        let gone = await harness.outbox.entry(id: entry.id)
        XCTAssertNil(gone)
        await fulfillment(of: [posted], timeout: 0.3)
    }

    func test2xxDuplicateOfADeletedRowCompletesWithoutPosting() async throws {
        let harness = makeHarness()
        let entry = try await enqueueURL(harness.outbox)
        _ = await harness.transfers.start(entries: [entry], userId: userId, accessToken: "jwt")
        let posted = expectation(forNotification: .stashItemCaptured, object: nil)
        posted.isInverted = true

        await finish(harness, upload: harness.session.uploads[0], status: 200, body: captureOK(duplicate: true, item: false))

        let gone = await harness.outbox.entry(id: entry.id)
        XCTAssertNil(gone)
        await fulfillment(of: [posted], timeout: 0.3)
    }

    func test2xxStorageCheckpointsThenStartsTheJSONCaptureInTheSameSession() async throws {
        let clock = TestClock(Date(timeIntervalSince1970: 1_900_000_000))
        let outbox = Outbox(directory: outboxDir, now: { clock.now })
        let harness = makeHarness(outbox: outbox, token: "fresh", oneShotLimit: 8)
        let staged = try stageFile(bytes: Data(repeating: 0xCD, count: 32), ext: "mp4")
        let entry = try await enqueueFile(outbox, at: staged, mime: "video/mp4", name: "clip.mp4")
        _ = await harness.transfers.start(entries: [entry], userId: userId, accessToken: "old")
        clock.now = Date(timeIntervalSince1970: 1_900_000_600)

        await finish(harness, upload: harness.session.uploads[0], status: 200, body: Data(#"{"Key":"k"}"#.utf8))

        let path = "\(userId.uuidString.lowercased())/\(entry.id.uuidString.lowercased()).mp4"
        let checkpointed = await outbox.entry(id: entry.id)
        XCTAssertEqual(checkpointed?.payload["file_path"], path, "checkpointed before anything else")
        XCTAssertEqual(checkpointed?.status, .transferring)
        XCTAssertEqual(checkpointed?.transferStartedAt, clock.now, "re-stamped for the follow-up")
        XCTAssertFalse(FileManager.default.fileExists(atPath: staged.path), "the local copy goes once the checkpoint is on disk")
        XCTAssertEqual(harness.session.uploads.count, 2)
        let followUp = harness.session.uploads[1]
        XCTAssertEqual(followUp.descriptor, BackgroundTransferDescriptor(userId: userId, entryId: entry.id, phase: .capture))
        XCTAssertEqual(followUp.request.value(forHTTPHeaderField: "Authorization"), "Bearer fresh", "a fresh token for the follow-up")
        XCTAssertEqual(followUp.meta["file_path"] as? String, path)
        XCTAssertEqual(followUp.meta["capture_id"] as? String, entry.id.uuidString.lowercased())
        XCTAssertEqual(harness.sessionsCreated.value, 1, "same session")

        await finish(harness, upload: followUp, taskIdentifier: 2, status: 200, body: captureOK(kind: "file"))
        let done = await outbox.entry(id: entry.id)
        XCTAssertNil(done)
        XCTAssertTrue(bodyFiles().isEmpty)
    }

    func test2xxStorageWithoutATokenLeavesTheCheckpointedEntryPendingForTheApp() async throws {
        let harness = makeHarness(token: nil, oneShotLimit: 8)
        let staged = try stageFile(bytes: Data(repeating: 0x01, count: 16), ext: "mov")
        let entry = try await enqueueFile(harness.outbox, at: staged, mime: "video/quicktime", name: "a.mov")
        _ = await harness.transfers.start(entries: [entry], userId: userId, accessToken: "jwt")

        await finish(harness, upload: harness.session.uploads[0], status: 200)

        let stored = await harness.outbox.entry(id: entry.id)
        XCTAssertEqual(stored?.status, .pending)
        XCTAssertEqual(stored?.attempts, 0)
        XCTAssertNotNil(stored?.payload["file_path"], "the upload is recorded — the app only sends the JSON capture")
        XCTAssertEqual(harness.session.uploads.count, 1)
    }

    func test403SubscriptionRequiredParks() async throws {
        let harness = makeHarness()
        let entry = try await enqueueURL(harness.outbox)
        _ = await harness.transfers.start(entries: [entry], userId: userId, accessToken: "jwt")

        await finish(harness, upload: harness.session.uploads[0], status: 403, body: Data(subscriptionRequiredBody.utf8))

        let stored = await harness.outbox.entry(id: entry.id)
        XCTAssertEqual(stored?.status, .parked)
        XCTAssertEqual(stored?.attempts, 0)
        XCTAssertNil(stored?.transferStartedAt)
        XCTAssertTrue(bodyFiles().isEmpty)
    }

    func test409LeavesTheEntryPendingWithoutCountingAnAttempt() async throws {
        let harness = makeHarness()
        let entry = try await enqueueURL(harness.outbox)
        _ = await harness.transfers.start(entries: [entry], userId: userId, accessToken: "jwt")

        await finish(harness, upload: harness.session.uploads[0], status: 409, body: Data(captureInProgressBody.utf8))

        let stored = await harness.outbox.entry(id: entry.id)
        XCTAssertEqual(stored?.status, .pending)
        XCTAssertEqual(stored?.attempts, 0)
        XCTAssertNil(stored?.transferStartedAt)
    }

    func test5xxAnd4xxAndTransportFailuresLeaveTheEntryPendingCountingAnAttempt() async throws {
        for (index, failure) in [(Int?.some(500), nil as URLError?), (Int?.some(400), nil), (nil, URLError(.timedOut))].enumerated() {
            let harness = makeHarness()
            let entry = try await enqueueURL(harness.outbox)
            _ = await harness.transfers.start(entries: [entry], userId: userId, accessToken: "jwt")

            await finish(harness, upload: harness.session.uploads[0], taskIdentifier: index,
                         status: failure.0, body: Data(#"{"error":"boom"}"#.utf8), error: failure.1)

            let stored = await harness.outbox.entry(id: entry.id)
            XCTAssertEqual(stored?.status, .pending, "case \(index)")
            XCTAssertEqual(stored?.attempts, 1, "case \(index)")
            XCTAssertTrue(bodyFiles().isEmpty, "case \(index)")
            await harness.outbox.complete(id: entry.id)
        }
    }

    func testSessionInUseByAnotherProcessLeavesPendingWithoutCountingAnAttempt() async throws {
        let harness = makeHarness()
        let entry = try await enqueueURL(harness.outbox)
        _ = await harness.transfers.start(entries: [entry], userId: userId, accessToken: "jwt")

        await finish(harness, upload: harness.session.uploads[0], status: nil,
                     error: URLError(.backgroundSessionInUseByAnotherProcess))

        let stored = await harness.outbox.entry(id: entry.id)
        XCTAssertEqual(stored?.status, .pending)
        XCTAssertEqual(stored?.attempts, 0)
    }

    func test413FileTooLargeFlagsTheEntryForTheTwoStepLane() async throws {
        let harness = makeHarness()
        let staged = try stageFile(bytes: Data([0x01, 0x02]), ext: "jpg")
        let entry = try await enqueueFile(harness.outbox, at: staged)
        _ = await harness.transfers.start(entries: [entry], userId: userId, accessToken: "jwt")
        XCTAssertEqual(harness.session.uploads[0].descriptor?.phase, .capture)

        await finish(harness, upload: harness.session.uploads[0], status: 413, body: Data(#"{"error":"file_too_large"}"#.utf8))

        let stored = try await XCTUnwrapAsync(await harness.outbox.entry(id: entry.id))
        XCTAssertEqual(stored.status, .pending)
        XCTAssertGreaterThanOrEqual(stored.attempts, CaptureAPI.oneShotMaxAttempts)
        XCTAssertTrue(CaptureTransport.requiresTwoStep(stored), "its next send goes through Storage")

        // …and a later background start of it does exactly that.
        await harness.outbox.markTransferring(ids: [entry.id])
        _ = await harness.transfers.start(entries: [stored], userId: userId, accessToken: "jwt")
        XCTAssertEqual(harness.session.uploads.last?.descriptor?.phase, .storage)
    }

    func testACompletionForAnEntryAlreadyGoneOnlyDeletesItsBody() async throws {
        let harness = makeHarness()
        let entry = try await enqueueURL(harness.outbox)
        _ = await harness.transfers.start(entries: [entry], userId: userId, accessToken: "jwt")
        await harness.outbox.complete(id: entry.id)   // e.g. a drain resent it and it landed
        let posted = expectation(forNotification: .stashItemCaptured, object: nil)
        posted.isInverted = true

        await finish(harness, upload: harness.session.uploads[0], status: 200, body: captureOK(duplicate: true))

        XCTAssertTrue(bodyFiles().isEmpty)
        let stillGone = await harness.outbox.entry(id: entry.id)
        XCTAssertNil(stillGone, "never resurrected")
        await fulfillment(of: [posted], timeout: 0.3)
    }

    func testAFailureNeverUnparksAnEntryButASuccessStillCompletesIt() async throws {
        let harness = makeHarness()
        let failing = try await enqueueURL(harness.outbox)
        let landing = try await enqueueURL(harness.outbox)
        _ = await harness.transfers.start(entries: [failing, landing], userId: userId, accessToken: "jwt")
        await harness.outbox.park(id: failing.id)
        await harness.outbox.park(id: landing.id)

        await finish(harness, upload: harness.session.uploads[0], taskIdentifier: 1, status: 500)
        await finish(harness, upload: harness.session.uploads[1], taskIdentifier: 2, status: 200, body: captureOK())

        let parked = await harness.outbox.entry(id: failing.id)
        XCTAssertEqual(parked?.status, .parked)
        XCTAssertEqual(parked?.attempts, 0)
        let completed = await harness.outbox.entry(id: landing.id)
        XCTAssertNil(completed)
    }

    func testATaskThisCodeDidntCreateIsIgnored() async throws {
        let harness = makeHarness()
        let entry = try await enqueueURL(harness.outbox)
        harness.transfers.didComplete(taskIdentifier: 9, taskDescription: "someone else's task", statusCode: 200, error: nil)
        harness.transfers.didComplete(taskIdentifier: 10, taskDescription: nil, statusCode: 500, error: nil)
        await harness.transfers.waitForIdle()
        let stored = await harness.outbox.entry(id: entry.id)
        XCTAssertEqual(stored?.status, .transferring)
        XCTAssertEqual(stored?.attempts, 0)
    }

    func testResponseBodiesAreKeptPerTask() async throws {
        let harness = makeHarness()
        let a = try await enqueueURL(harness.outbox, note: "a")
        let b = try await enqueueURL(harness.outbox, note: "b")
        _ = await harness.transfers.start(entries: [a, b], userId: userId, accessToken: "jwt")
        // Interleaved chunks for two tasks: task 1 → 409, task 2 → 200.
        let conflict = Data(captureInProgressBody.utf8), ok = captureOK()
        harness.transfers.didReceive(conflict.prefix(5), forTask: 1)
        harness.transfers.didReceive(ok.prefix(7), forTask: 2)
        harness.transfers.didReceive(conflict.suffix(from: 5), forTask: 1)
        harness.transfers.didReceive(ok.suffix(from: 7), forTask: 2)
        harness.transfers.didComplete(taskIdentifier: 1, taskDescription: harness.session.uploads[0].taskDescription,
                                      statusCode: 409, error: nil)
        harness.transfers.didComplete(taskIdentifier: 2, taskDescription: harness.session.uploads[1].taskDescription,
                                      statusCode: 200, error: nil)
        await harness.transfers.waitForIdle()

        let first = await harness.outbox.entry(id: a.id)
        XCTAssertEqual(first?.status, .pending)
        XCTAssertEqual(first?.attempts, 0, "a clean 409, not a garbled body")
        let second = await harness.outbox.entry(id: b.id)
        XCTAssertNil(second)
    }

    // MARK: - The extension's post-confirmation check

    func testEntriesNeedingForegroundSendAreTheBouncedAndTheNotStarted() async throws {
        let harness = makeHarness()
        let lands = try await enqueueURL(harness.outbox)
        let bounces = try await enqueueURL(harness.outbox)
        let inFlight = try await enqueueURL(harness.outbox)
        let unbuildable = try await enqueueFile(harness.outbox, at: stagingDir.appending(path: "missing.jpg"))
        let batch = await harness.transfers.start(entries: [lands, bounces, inFlight, unbuildable], userId: userId, accessToken: "jwt")
        harness.transfers.didReceive(captureOK(), forTask: 1)
        harness.transfers.didComplete(taskIdentifier: 1, taskDescription: harness.session.uploads[0].taskDescription,
                                      statusCode: 200, error: nil)
        harness.transfers.didComplete(taskIdentifier: 2, taskDescription: harness.session.uploads[1].taskDescription,
                                      statusCode: nil, error: URLError(.backgroundSessionInUseByAnotherProcess))

        let needed = await harness.transfers.entriesNeedingForegroundSend(in: batch)

        XCTAssertEqual(Set(needed), [bounces.id, unbuildable.id])
        let stillTransferring = await harness.outbox.entry(id: inFlight.id)
        XCTAssertEqual(stillTransferring?.status, .transferring, "a live task is left alone")
    }

    func testALostConnectionHandsTheWholeBatchToTheForeground() async throws {
        let harness = makeHarness()
        let a = try await enqueueURL(harness.outbox)
        let b = try await enqueueURL(harness.outbox)
        let batch = await harness.transfers.start(entries: [a, b], userId: userId, accessToken: "jwt")

        harness.transfers.sessionDidBecomeInvalid(harness.session, error: URLError(.backgroundSessionInUseByAnotherProcess))
        let needed = await harness.transfers.entriesNeedingForegroundSend(in: batch)

        XCTAssertEqual(Set(needed), [a.id, b.id])
        for id in [a.id, b.id] {
            let stored = await harness.outbox.entry(id: id)
            XCTAssertEqual(stored?.status, .pending)
            XCTAssertEqual(stored?.attempts, 0)
        }
        // The next share in this (possibly reused) process connects afresh.
        let next = try await enqueueURL(harness.outbox)
        _ = await harness.transfers.start(entries: [next], userId: userId, accessToken: "jwt")
        XCTAssertEqual(harness.sessionsCreated.value, 2)
    }

    // MARK: - Events flow (app)

    func testHandleEventsIgnoresOtherSessions() {
        let harness = makeHarness()
        XCTAssertFalse(harness.transfers.handleEvents(forBackgroundURLSession: "com.other.session") {})
        XCTAssertEqual(harness.sessionsCreated.value, 0)
    }

    func testHandleEventsReconnectsAppliesEventsThenInvalidatesAndCallsTheHandlerOnMain() async throws {
        let harness = makeHarness()
        let entry = try await enqueueURL(harness.outbox)
        let description = BackgroundTransferDescriptor(userId: userId, entryId: entry.id, phase: .capture).taskDescription
        let entryFile = outboxDir.appending(path: "\(entry.id.uuidString).json")
        let order = OrderLog()
        harness.session.onInvalidate = { order.append("invalidate") }
        let handled = expectation(description: "completion handler")
        let isMain = OrderLog()

        XCTAssertTrue(harness.transfers.handleEvents(forBackgroundURLSession: BackgroundCaptureTransfers.sessionIdentifier) {
            isMain.append(Thread.isMainThread ? "main" : "background")
            order.append(FileManager.default.fileExists(atPath: entryFile.path) ? "handler (entry pending)" : "handler (entry done)")
            handled.fulfill()
        })
        XCTAssertEqual(harness.sessionsCreated.value, 1, "the app reconnects when the system asks")
        harness.transfers.didReceive(captureOK(), forTask: 4)
        harness.transfers.didComplete(taskIdentifier: 4, taskDescription: description, statusCode: 200, error: nil)
        harness.transfers.didFinishEvents(for: harness.session)

        await fulfillment(of: [handled], timeout: 2)
        XCTAssertEqual(order.entries, ["invalidate", "handler (entry done)"])
        XCTAssertEqual(isMain.entries, ["main"])
        XCTAssertTrue(harness.session.invalidated)
    }

    func testFinishEventsWithNoHandlerWaitingStaysConnected() async throws {
        let harness = makeHarness(postsNotifications: false)
        let first = try await enqueueURL(harness.outbox)
        _ = await harness.transfers.start(entries: [first], userId: userId, accessToken: "jwt")

        harness.transfers.didFinishEvents(for: harness.session)
        await harness.transfers.waitForIdle()

        XCTAssertFalse(harness.session.invalidated, "the extension never invalidates — a start could be in progress")
        let second = try await enqueueURL(harness.outbox)
        _ = await harness.transfers.start(entries: [second], userId: userId, accessToken: "jwt")
        XCTAssertEqual(harness.sessionsCreated.value, 1)
    }

    func testWhileWindingDownNoSecondSessionIsCreatedAndAFollowUpGoesOutInTheForeground() async throws {
        let server = FakeCaptureServer()
        let harness = makeHarness(oneShotLimit: 8, server: server)
        let staged = try stageFile(bytes: Data(repeating: 0x02, count: 24), ext: "mov")
        let entry = try await enqueueFile(harness.outbox, at: staged, mime: "video/quicktime", name: "b.mov")
        let handled = expectation(description: "first handler")
        harness.transfers.handleEvents(forBackgroundURLSession: BackgroundCaptureTransfers.sessionIdentifier) { handled.fulfill() }
        harness.transfers.didFinishEvents(for: harness.session)
        await fulfillment(of: [handled], timeout: 2)
        XCTAssertTrue(harness.session.invalidated)

        // A second wake-up while the first session still finishes its tasks: no second session
        // object for the identifier, events go to the one still connected.
        let second = expectation(description: "second handler")
        harness.transfers.handleEvents(forBackgroundURLSession: BackgroundCaptureTransfers.sessionIdentifier) { second.fulfill() }
        XCTAssertEqual(harness.sessionsCreated.value, 1)

        // Its Storage upsert lands: the follow-up can't use the winding-down session, so the
        // small JSON capture goes out in the foreground right away.
        let storageTask = BackgroundTransferDescriptor(userId: userId, entryId: entry.id, phase: .storage).taskDescription
        harness.transfers.didComplete(taskIdentifier: 7, taskDescription: storageTask, statusCode: 200, error: nil)
        harness.transfers.didFinishEvents(for: harness.session)
        await fulfillment(of: [second], timeout: 2)

        XCTAssertEqual(server.captures.count, 1)
        XCTAssertEqual(server.captures.first?.meta["file_path"] as? String,
                       "\(userId.uuidString.lowercased())/\(entry.id.uuidString.lowercased()).mov")
        XCTAssertEqual(server.captures.first?.captureId, entry.id.uuidString.lowercased())
        let done = await harness.outbox.entry(id: entry.id)
        XCTAssertNil(done)

        // Once it's invalid, a later wake-up connects a fresh session.
        harness.transfers.sessionDidBecomeInvalid(harness.session, error: nil)
        harness.transfers.handleEvents(forBackgroundURLSession: BackgroundCaptureTransfers.sessionIdentifier) {}
        XCTAssertEqual(harness.sessionsCreated.value, 2)
    }

    func testStartWhileThisProcessIsWindingDownLeavesTheShareForTheForeground() async throws {
        let harness = makeHarness()
        let handled = expectation(description: "handler")
        harness.transfers.handleEvents(forBackgroundURLSession: BackgroundCaptureTransfers.sessionIdentifier) { handled.fulfill() }
        harness.transfers.didFinishEvents(for: harness.session)
        await fulfillment(of: [handled], timeout: 2)
        let entry = try await enqueueURL(harness.outbox)

        let batch = await harness.transfers.start(entries: [entry], userId: userId, accessToken: "jwt")

        XCTAssertEqual(batch.started, [])
        XCTAssertEqual(batch.notStarted, [entry.id])
        let stored = await harness.outbox.entry(id: entry.id)
        XCTAssertEqual(stored?.status, .pending)
        let needed = await harness.transfers.entriesNeedingForegroundSend(in: batch)
        XCTAssertEqual(needed, [entry.id])
    }

    func testALostConnectionReleasesAWaitingEventsHandler() {
        let harness = makeHarness()
        let released = expectation(description: "handler released")
        harness.transfers.handleEvents(forBackgroundURLSession: BackgroundCaptureTransfers.sessionIdentifier) { released.fulfill() }

        harness.transfers.sessionDidBecomeInvalid(harness.session, error: URLError(.backgroundSessionInUseByAnotherProcess))

        wait(for: [released], timeout: 2)
    }

    // MARK: - Maintenance

    func testSweepStaleBodyFilesRemovesOnlyOldOnes() throws {
        try FileManager.default.createDirectory(at: bodyDir, withIntermediateDirectories: true)
        let now = Date()
        let old = bodyDir.appending(path: "\(UUID().uuidString.lowercased())-a.json")
        let young = bodyDir.appending(path: "\(UUID().uuidString.lowercased())-b.multipart")
        try Data("{}".utf8).write(to: old)
        try Data("{}".utf8).write(to: young)
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-4 * 3600)], ofItemAtPath: old.path)
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-60)], ofItemAtPath: young.path)

        XCTAssertEqual(BackgroundCaptureTransfers.sweepStaleBodyFiles(in: bodyDir, now: now), 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: old.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: young.path))
        XCTAssertEqual(BackgroundCaptureTransfers.sweepStaleBodyFiles(in: bodyDir.appending(path: "nope"), now: now), 0)
    }

    func testReleaseStaleTransfersFlipsOnlyTransfersOlderThanTheInterval() async throws {
        let clock = TestClock(Date(timeIntervalSince1970: 1_900_000_000))
        let outbox = Outbox(directory: outboxDir, now: { clock.now })
        let old = try await enqueueURL(outbox)
        clock.now = Date(timeIntervalSince1970: 1_900_000_050)
        let fresh = try await enqueueURL(outbox)
        let pending = try await outbox.enqueue(.url, payload: ["url": "https://example.com", "is_public": "false"])

        let released = await BackgroundCaptureTransfers.releaseStaleTransfers(
            in: outbox, olderThan: 30, now: Date(timeIntervalSince1970: 1_900_000_060))

        XCTAssertEqual(released, 1)
        let oldNow = await outbox.entry(id: old.id)
        XCTAssertEqual(oldNow?.status, .pending)
        XCTAssertEqual(oldNow?.attempts, 0)
        let freshNow = await outbox.entry(id: fresh.id)
        XCTAssertEqual(freshNow?.status, .transferring)
        let pendingNow = await outbox.entry(id: pending.id)
        XCTAssertEqual(pendingNow?.status, .pending)
    }

    func testConfigurationMatchesThePlan() {
        let configuration = BackgroundCaptureTransfers.makeConfiguration()
        XCTAssertEqual(configuration.identifier, "it.gostash.stash.capture-transfers")
        XCTAssertEqual(configuration.sharedContainerIdentifier, "group.it.gostash.stash")
        XCTAssertFalse(configuration.isDiscretionary)
        #if os(iOS)
        XCTAssertTrue(configuration.sessionSendsLaunchEvents)
        #endif
        XCTAssertEqual(configuration.timeoutIntervalForResource, 3600)
    }

    // MARK: - Review fixes: rejected tokens (a task can outlive its token)

    func testDescriptorCarriesTheOneRefreshMarker() {
        let entryId = UUID()
        let refreshed = BackgroundTransferDescriptor(userId: userId, entryId: entryId, phase: .storage, refreshed: true)
        XCTAssertEqual(refreshed.taskDescription,
                       "\(userId.uuidString.lowercased())|\(entryId.uuidString.lowercased())|storage|refreshed")
        XCTAssertEqual(BackgroundTransferDescriptor(taskDescription: refreshed.taskDescription), refreshed)
        XCTAssertEqual(BackgroundTransferDescriptor(taskDescription: "\(userId.uuidString)|\(entryId.uuidString)|capture")?.refreshed,
                       false, "a task started by the first build (3 parts) still parses")
        XCTAssertNil(BackgroundTransferDescriptor(taskDescription: "\(userId.uuidString)|\(entryId.uuidString)|capture|other"))
    }

    func testDecisionA401RefreshesTheTokenOnceThenCountsAnAttempt() {
        XCTAssertEqual(decide(401, #"{"code":401,"message":"Invalid JWT"}"#), .refreshTokenAndRetry)
        XCTAssertEqual(decide(.storage, 401), .refreshTokenAndRetry)
        XCTAssertEqual(BackgroundTransferDecision.decide(phase: .capture, statusCode: 401, body: Data(), error: nil,
                                                         afterTokenRefresh: true),
                       .retry(countsAsAttempt: true), "only one refresh retry per phase")
    }

    func testDecisionStorageJWTExpiredRefreshesTheTokenAnyOtherStorageRefusalDoesNot() {
        XCTAssertEqual(decide(.storage, 400, #"{"statusCode":"403","error":"Unauthorized","message":"jwt expired"}"#),
                       .refreshTokenAndRetry)
        XCTAssertEqual(decide(.storage, 403, #"{"statusCode":"400","error":"InvalidJWT","message":"invalid JWT"}"#),
                       .refreshTokenAndRetry)
        XCTAssertEqual(decide(.storage, 403, #"{"statusCode":"403","error":"Unauthorized","message":"new row violates row-level security policy"}"#),
                       .retry(countsAsAttempt: true))
        XCTAssertEqual(decide(403, #"{"error":"jwt looks odd"}"#), .retry(countsAsAttempt: true),
                       "the capture endpoint only signals a bad token with 401")
    }

    func testRejectedTokenRestartsTheSamePhaseOnceWithAFreshTokenWithoutCountingAnAttempt() async throws {
        let harness = makeHarness(token: "fresh")
        let entry = try await enqueueURL(harness.outbox)
        _ = await harness.transfers.start(entries: [entry], userId: userId, accessToken: "expired")
        XCTAssertEqual(harness.session.uploads[0].request.value(forHTTPHeaderField: "Authorization"), "Bearer expired")

        await finish(harness, upload: harness.session.uploads[0], taskIdentifier: 1, status: 401,
                     body: Data(#"{"code":401,"message":"Invalid JWT"}"#.utf8))

        XCTAssertEqual(harness.session.uploads.count, 2, "the same phase is restarted in the same session")
        let retry = harness.session.uploads[1]
        XCTAssertEqual(retry.descriptor, BackgroundTransferDescriptor(userId: userId, entryId: entry.id, phase: .capture,
                                                                      refreshed: true))
        XCTAssertEqual(retry.request.value(forHTTPHeaderField: "Authorization"), "Bearer fresh")
        XCTAssertEqual(retry.meta["capture_id"] as? String, entry.id.uuidString.lowercased(), "same idempotency key")
        let restarted = await harness.outbox.entry(id: entry.id)
        XCTAssertEqual(restarted?.status, .transferring)
        XCTAssertEqual(restarted?.attempts, 0, "a rejected token isn't a failed attempt")
        XCTAssertEqual(bodyFiles().count, 1, "only the retry's body is on disk")

        // The retry is rejected too: no third try — back to the Outbox, attempt counted.
        await finish(harness, upload: retry, taskIdentifier: 2, status: 401)
        XCTAssertEqual(harness.session.uploads.count, 2)
        let pending = await harness.outbox.entry(id: entry.id)
        XCTAssertEqual(pending?.status, .pending)
        XCTAssertEqual(pending?.attempts, 1)
        XCTAssertTrue(bodyFiles().isEmpty)
    }

    func testAnExpiredTokenOnAStorageUploadRestartsTheUploadThenTheCaptureFollows() async throws {
        let harness = makeHarness(token: "fresh", oneShotLimit: 8)
        let staged = try stageFile(bytes: Data(repeating: 0x07, count: 40), ext: "mov")
        let entry = try await enqueueFile(harness.outbox, at: staged, mime: "video/quicktime", name: "v.mov")
        _ = await harness.transfers.start(entries: [entry], userId: userId, accessToken: "expired")

        await finish(harness, upload: harness.session.uploads[0], taskIdentifier: 1, status: 400,
                     body: Data(#"{"statusCode":"403","error":"Unauthorized","message":"jwt expired"}"#.utf8))

        let retry = harness.session.uploads[1]
        XCTAssertEqual(retry.descriptor?.phase, .storage)
        XCTAssertEqual(retry.descriptor?.refreshed, true)
        XCTAssertEqual(retry.request.value(forHTTPHeaderField: "Authorization"), "Bearer fresh")
        XCTAssertEqual(retry.file.standardizedFileURL, staged.standardizedFileURL)
        let restarted = await harness.outbox.entry(id: entry.id)
        XCTAssertEqual(restarted?.transferPhase, .storage)

        await finish(harness, upload: retry, taskIdentifier: 2, status: 200)
        let followUp = harness.session.uploads[2]
        XCTAssertEqual(followUp.descriptor, BackgroundTransferDescriptor(userId: userId, entryId: entry.id, phase: .capture),
                       "the capture phase gets its own refresh retry if it needs one")
        XCTAssertNotNil(followUp.meta["file_path"])
    }

    func testARejectedTokenWithNoSessionLeftGoesBackToTheOutboxUncounted() async throws {
        let harness = makeHarness(token: nil)
        let entry = try await enqueueURL(harness.outbox)
        _ = await harness.transfers.start(entries: [entry], userId: userId, accessToken: "expired")

        await finish(harness, upload: harness.session.uploads[0], status: 401)

        XCTAssertEqual(harness.session.uploads.count, 1)
        let stored = await harness.outbox.entry(id: entry.id)
        XCTAssertEqual(stored?.status, .pending)
        XCTAssertEqual(stored?.attempts, 0)
    }

    func testARejectedTokenWhileWindingDownIsSentInTheForegroundWithTheFreshToken() async throws {
        let server = FakeCaptureServer()
        let harness = makeHarness(token: "fresh", server: server)
        let entry = try await enqueueURL(harness.outbox)
        let handled = expectation(description: "handler")
        harness.transfers.handleEvents(forBackgroundURLSession: BackgroundCaptureTransfers.sessionIdentifier) { handled.fulfill() }
        harness.transfers.didFinishEvents(for: harness.session)
        await fulfillment(of: [handled], timeout: 2)

        let task = BackgroundTransferDescriptor(userId: userId, entryId: entry.id, phase: .capture).taskDescription
        harness.transfers.didComplete(taskIdentifier: 3, taskDescription: task, statusCode: 401, error: nil)
        await harness.transfers.waitForIdle()

        XCTAssertEqual(server.captures.count, 1)
        XCTAssertEqual(server.captures.first?.header("Authorization"), "Bearer fresh")
        let done = await harness.outbox.entry(id: entry.id)
        XCTAssertNil(done)
    }

    // MARK: - Review fixes: bounded response bodies

    func testAnOversizedSuccessBodyStillCompletesTheCapture() async throws {
        let harness = makeHarness()
        let entry = try await enqueueURL(harness.outbox)
        _ = await harness.transfers.start(entries: [entry], userId: userId, accessToken: "jwt")
        // A `duplicate: true` answer with a huge row: 3 MiB in 1 MiB chunks, over the 2 MiB cap.
        let chunk = Data(repeating: 0x61, count: 1 << 20)
        for _ in 0..<3 { harness.transfers.didReceive(chunk, forTask: 9) }
        harness.transfers.didComplete(taskIdentifier: 9, taskDescription: harness.session.uploads[0].taskDescription,
                                      statusCode: 200, error: nil)
        await harness.transfers.waitForIdle()

        let done = await harness.outbox.entry(id: entry.id)
        XCTAssertNil(done, "2xx: the server has it, even if its row can't be read back")
        XCTAssertEqual(BackgroundTransferDecision.decide(phase: .capture, statusCode: 200, body: Data("{".utf8), error: nil,
                                                         bodyTruncated: true),
                       .complete(CaptureResult(item: nil, duplicate: false)))
    }

    func testALostConnectionAlsoDeletesTheBatchsRequestBodies() async throws {
        let harness = makeHarness()
        let entry = try await enqueueURL(harness.outbox)
        let batch = await harness.transfers.start(entries: [entry], userId: userId, accessToken: "jwt")
        XCTAssertEqual(bodyFiles().count, 1)

        harness.transfers.sessionDidBecomeInvalid(harness.session, error: URLError(.backgroundSessionInUseByAnotherProcess))
        _ = await harness.transfers.entriesNeedingForegroundSend(in: batch)

        XCTAssertTrue(bodyFiles().isEmpty, "the foreground send writes its own body")
    }

    // MARK: - Review fixes: stale bounds, checkpoints and drains

    func testStartRecordsEachTransfersPhase() async throws {
        let harness = makeHarness(oneShotLimit: 8)
        let url = try await enqueueURL(harness.outbox)
        let staged = try stageFile(bytes: Data(repeating: 1, count: 20), ext: "mov")
        let big = try await enqueueFile(harness.outbox, at: staged, mime: "video/quicktime", name: "b.mov")
        _ = await harness.transfers.start(entries: [url, big], userId: userId, accessToken: "jwt")
        let urlNow = await harness.outbox.entry(id: url.id)
        let bigNow = await harness.outbox.entry(id: big.id)
        XCTAssertEqual(urlNow?.transferPhase, .capture)
        XCTAssertEqual(bigNow?.transferPhase, .storage)
    }

    func testAnUncheckpointedStorageUploadGetsTheLongStaleBound() {
        let started = Date(timeIntervalSince1970: 1_900_000_000)
        var entry = OutboxEntry(id: UUID(), kind: .file, payload: ["local_file_path": "/x.mov"], createdAt: started,
                                attempts: 0, status: .transferring, transferStartedAt: started, transferPhase: .storage)
        XCTAssertFalse(Outbox.isEligibleForSend(entry, now: started.addingTimeInterval(700)),
                       "a big upload can legitimately run for the whole resource timeout")
        XCTAssertFalse(Outbox.isEligibleForSend(entry, now: started.addingTimeInterval(3600)))
        XCTAssertTrue(Outbox.isEligibleForSend(entry, now: started.addingTimeInterval(Outbox.staleStorageTransferInterval + 1)))
        XCTAssertGreaterThanOrEqual(Outbox.staleStorageTransferInterval, BackgroundCaptureTransfers.makeConfiguration().timeoutIntervalForResource)

        entry.payload["file_path"] = "\(userId.uuidString.lowercased())/x.mov"
        XCTAssertTrue(Outbox.isEligibleForSend(entry, now: started.addingTimeInterval(700)),
                      "once checkpointed only the JSON capture is left: the short bound applies")
        entry.transferPhase = .capture
        entry.payload["file_path"] = nil
        XCTAssertTrue(Outbox.isEligibleForSend(entry, now: started.addingTimeInterval(700)))
        XCTAssertFalse(Outbox.isEligibleForSend(entry, now: started.addingTimeInterval(500)))
    }

    func testAnEntryWrittenByTheFirstPlan15BuildDecodesWithoutAPhase() throws {
        let json = #"{"id":"\#(UUID().uuidString)","kind":"url","payload":{"url":"https://example.com"},"createdAt":0,"attempts":0,"status":"transferring","transferStartedAt":0}"#
        let entry = try JSONDecoder().decode(OutboxEntry.self, from: Data(json.utf8))
        XCTAssertEqual(entry.status, .transferring)
        XCTAssertNil(entry.transferPhase)
        let roundTripped = try JSONDecoder().decode(OutboxEntry.self, from: JSONEncoder().encode(entry))
        XCTAssertEqual(roundTripped, entry)
    }

    func testPendingAndParkClearThePhase() async throws {
        let outbox = Outbox(directory: outboxDir)
        let entry = try await enqueueURL(outbox)
        await outbox.markTransferring(ids: [entry.id], phase: .storage)
        let marked = await outbox.entry(id: entry.id)
        XCTAssertEqual(marked?.transferPhase, .storage)
        await outbox.markPending(id: entry.id, incrementAttempts: false)
        let pending = await outbox.entry(id: entry.id)
        XCTAssertNil(pending?.transferPhase)
        await outbox.markTransferring(ids: [entry.id], phase: .capture)
        await outbox.park(id: entry.id)
        let parked = await outbox.entry(id: entry.id)
        XCTAssertNil(parked?.transferPhase)
    }

    /// The data-loss sequence from the review: a drain resends a big file whose background Storage
    /// upload is still running; the background upload lands and checkpoints (deleting the local
    /// copy) while the drain's own upload is in flight; the drain's upload then fails. Its failure
    /// write-back must not restore its older copy of the entry (no `file_path`, a local path that
    /// no longer exists), or the next drain drops an entry whose bytes are safely in Storage.
    func testADrainFailureKeepsACheckpointABackgroundUploadWroteMeanwhile() async throws {
        let server = FakeCaptureServer()
        let outbox = Outbox(directory: outboxDir)
        let staged = try stageFile(bytes: Data(repeating: 0x05, count: 32), ext: "mov")
        let entry = try await outbox.enqueue(.file, payload: ["local_file_path": staged.path, "mime_type": "video/quicktime",
                                                              "file_name": "clip.mov", "is_public": "false"])
        let path = "\(userId.uuidString.lowercased())/\(entry.id.uuidString.lowercased()).mov"
        let directory = outboxDir!
        server.onRequest = { call in
            // The background task's completion, applied by another process, mid-drain.
            if call.isStorage { await Outbox(directory: directory).checkpoint(id: entry.id, filePath: path) }
        }
        server.storageBehaviors = [.fail(URLError(.networkConnectionLost))]
        let api = CaptureAPI(transport: server, oneShotLimit: 8)

        _ = await outbox.drain(api: api, accessToken: "jwt", userId: userId)

        let afterFailure = await outbox.entry(id: entry.id)
        XCTAssertEqual(afterFailure?.payload["file_path"], path, "the checkpoint survives the drain's failure write-back")
        XCTAssertEqual(afterFailure?.status, .pending)
        XCTAssertEqual(afterFailure?.attempts, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: staged.path))

        server.onRequest = nil
        let sent = await outbox.drain(api: api, accessToken: "jwt", userId: userId)
        XCTAssertEqual(sent, 1, "the next drain sends the JSON capture instead of dropping the entry")
        XCTAssertEqual(server.captures.last?.meta["file_path"] as? String, path)
        XCTAssertEqual(server.createdItemCount, 1)
        let gone = await outbox.entry(id: entry.id)
        XCTAssertNil(gone)
    }

    /// A process killed between a background Storage upload's checkpoint and its follow-up
    /// capture: the entry is still `.transferring` (storage phase), but checkpointed — the drain
    /// sends its JSON capture after the short bound, not the one-hour one.
    func testAKillBetweenCheckpointAndFollowUpIsResentAfterTheShortBound() async throws {
        let server = FakeCaptureServer()
        let clock = TestClock(Date(timeIntervalSince1970: 1_900_000_000))
        let outbox = Outbox(directory: outboxDir, now: { clock.now })
        let staged = try stageFile(bytes: Data(repeating: 0x09, count: 32), ext: "mov")
        let entry = try await outbox.enqueue(.file, payload: ["local_file_path": staged.path, "mime_type": "video/quicktime",
                                                              "file_name": "k.mov", "is_public": "false"], status: .transferring)
        await outbox.markTransferring(ids: [entry.id], phase: .storage)
        let path = "\(userId.uuidString.lowercased())/\(entry.id.uuidString.lowercased()).mov"
        await outbox.checkpoint(id: entry.id, filePath: path)   // …and the process dies here
        let api = CaptureAPI(transport: server, oneShotLimit: 8)

        clock.now = clock.now.addingTimeInterval(Outbox.staleTransferInterval - 1)
        let early = await outbox.drain(api: api, accessToken: "jwt", userId: userId)
        XCTAssertEqual(early, 0)

        clock.now = clock.now.addingTimeInterval(2)
        let sent = await outbox.drain(api: api, accessToken: "jwt", userId: userId)
        XCTAssertEqual(sent, 1)
        XCTAssertTrue(server.storageUploads.isEmpty, "never re-uploaded")
        XCTAssertEqual(server.captures.first?.meta["file_path"] as? String, path)
    }

    func testAStorageCompletionMakesTheEntrySendableBeforeTheFollowUpStarts() async throws {
        // With no token, the follow-up can't start — the checkpointed entry must already be
        // `.pending` (drain-eligible now), not stuck `.transferring` behind a stale bound.
        let harness = makeHarness(token: nil, oneShotLimit: 8)
        let staged = try stageFile(bytes: Data(repeating: 0x03, count: 24), ext: "mov")
        let entry = try await enqueueFile(harness.outbox, at: staged, mime: "video/quicktime", name: "p.mov")
        _ = await harness.transfers.start(entries: [entry], userId: userId, accessToken: "jwt")

        await finish(harness, upload: harness.session.uploads[0], status: 200)

        let stored = try await XCTUnwrapAsync(await harness.outbox.entry(id: entry.id))
        XCTAssertEqual(stored.status, .pending)
        XCTAssertNil(stored.transferPhase)
        XCTAssertTrue(Outbox.isEligibleForSend(stored, now: Date()))
    }
}

/// Thread-safe ordered log of events.
final class OrderLog: @unchecked Sendable {
    private let lock = NSLock()
    private var _entries: [String] = []
    var entries: [String] { lock.withLock { _entries } }
    func append(_ entry: String) { lock.withLock { _entries.append(entry) } }
}

/// `XCTUnwrap` for an optional produced by an `await` expression.
func XCTUnwrapAsync<T>(_ value: @autoclosure () async throws -> T?, file: StaticString = #filePath,
                       line: UInt = #line) async throws -> T {
    let resolved = try await value()
    return try XCTUnwrap(resolved, file: file, line: line)
}
