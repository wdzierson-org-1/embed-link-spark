import XCTest
@testable import StashKit

/// Records every two-step Storage upload `drain`/`sendNow` makes (the `upload` lane) so tests can
/// assert exactly what file URL/path/content-type it received. Takes the local file's `URL`
/// directly, not a loaded `Data` blob — proving the lane streams from disk is the point of
/// recording the URL. `bytesAtCallTime` snapshots the file's content AT THE MOMENT of the call (the
/// local file is deleted later in the same pass, once the checkpoint is on disk).
final class UploadRecorder: @unchecked Sendable {
    private(set) var calls: [(fileURL: URL, path: String, contentType: String, bytesAtCallTime: Data?)] = []
    var shouldFail = false

    func upload(fileURL: URL, path: String, contentType: String) async throws {
        if shouldFail { throw CaptureError.badStatus(500) }
        let bytesAtCallTime = try? Data(contentsOf: fileURL)
        calls.append((fileURL: fileURL, path: path, contentType: contentType, bytesAtCallTime: bytesAtCallTime))
    }

    var closure: @Sendable (URL, String, String) async throws -> Void {
        { [self] fileURL, path, contentType in try await upload(fileURL: fileURL, path: path, contentType: contentType) }
    }
}

/// Suspends every request until `release()` — for the reentrancy guard.
final class GatedTransport: CaptureTransporting, @unchecked Sendable {
    private let server = FakeCaptureServer()
    private var isReleased = false
    private let lock = NSLock()
    var calls: [TransportCall] { server.calls }

    func upload(_ request: URLRequest, fromFile bodyFile: URL) async throws -> (status: Int, body: Data) {
        // Read the body now — the caller deletes it once this returns.
        let body = try Data(contentsOf: bodyFile)
        let copy = FileManager.default.temporaryDirectory.appending(path: "gated-\(UUID().uuidString)")
        try body.write(to: copy)
        defer { try? FileManager.default.removeItem(at: copy) }
        while !lock.withLock({ isReleased }) { try await Task.sleep(for: .milliseconds(10)) }
        return try await server.upload(request, fromFile: copy)
    }

    func release() { lock.withLock { isReleased = true } }
}

final class OutboxTests: XCTestCase {
    var dir: URL!
    var filesDir: URL!
    let userId = UUID()

    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appending(path: "outbox-\(UUID().uuidString)")
        filesDir = FileManager.default.temporaryDirectory.appending(path: "outbox-files-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: filesDir, withIntermediateDirectories: true)
    }
    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.removeItem(at: filesDir)
    }

    private func api(_ server: FakeCaptureServer, oneShotLimit: Int = CaptureAPI.oneShotFileLimit) -> CaptureAPI {
        CaptureAPI(transport: server, oneShotLimit: oneShotLimit)
    }

    private func localFile(_ bytes: Data = Data([0x01, 0x02, 0x03, 0x04]), ext: String = "m4a") throws -> URL {
        let url = filesDir.appending(path: "local-\(UUID().uuidString).\(ext)")
        try bytes.write(to: url)
        return url
    }

    @discardableResult
    private func fileEntry(_ box: Outbox, local: URL, mime: String = "audio/mp4") async throws -> OutboxEntry {
        try await box.enqueue(.file, payload: ["local_file_path": local.path, "mime_type": mime, "is_public": "false"])
    }

    // MARK: - Basics

    func testEnqueuePersistsAcrossInstancesAndReturnsTheEntry() async throws {
        let box = Outbox(directory: dir)
        let entry = try await box.enqueue(.note, payload: ["content": "offline note", "is_public": "false"])
        XCTAssertEqual(entry.status, .pending)
        XCTAssertNil(entry.transferStartedAt)
        let rehydrated = Outbox(directory: dir)
        let pending = await rehydrated.pending()
        XCTAssertEqual(pending, [entry])
        let lookedUp = await rehydrated.entry(id: entry.id)
        XCTAssertEqual(lookedUp, entry)
    }

    func testDrainSendsAndRemoves() async throws {
        let box = Outbox(directory: dir)
        let entry = try await box.enqueue(.note, payload: ["content": "n1", "is_public": "false"])
        let server = FakeCaptureServer()
        let sent = await box.drain(api: api(server), accessToken: "jwt", userId: userId)
        XCTAssertEqual(sent, 1)
        XCTAssertEqual(server.captures.map(\.kind), ["note"])
        XCTAssertEqual(server.captures.first?.captureId, entry.id.uuidString.lowercased())
        let after = await box.pending()
        XCTAssertTrue(after.isEmpty)
    }

    func testDrainFailureRetainsAndIncrementsAttempts() async throws {
        let box = Outbox(directory: dir)
        try await box.enqueue(.note, payload: ["content": "n1", "is_public": "false"])
        let server = FakeCaptureServer()
        server.captureBehaviors = [.respond(500, #"{"error":"boom"}"#)]
        let sent = await box.drain(api: api(server), accessToken: "jwt", userId: userId)
        XCTAssertEqual(sent, 0)
        let after = await box.pending()
        XCTAssertEqual(after.count, 1)
        XCTAssertEqual(after[0].attempts, 1)
        XCTAssertEqual(after[0].status, .pending)
    }

    func testOldestFirstOrdering() async throws {
        let box = Outbox(directory: dir)
        try await box.enqueue(.note, payload: ["content": "first", "is_public": "false"])
        try await box.enqueue(.note, payload: ["content": "second", "is_public": "false"])
        let pending = await box.pending()
        XCTAssertEqual(pending.map { $0.payload["content"] }, ["first", "second"])
        let server = FakeCaptureServer()
        _ = await box.drain(api: api(server), accessToken: "jwt", userId: userId)
        XCTAssertEqual(server.captures.map { $0.meta["content"] as? String }, ["first", "second"])
    }

    func testReentrantDrainNoOps() async throws {
        let box = Outbox(directory: dir)
        try await box.enqueue(.note, payload: ["content": "n1", "is_public": "false"])
        let gated = GatedTransport()
        let gatedAPI = CaptureAPI(transport: gated)
        async let first = box.drain(api: gatedAPI, accessToken: "jwt", userId: userId)
        try await Task.sleep(for: .milliseconds(50))     // first drain is now suspended in its request
        let second = await box.drain(api: gatedAPI, accessToken: "jwt", userId: userId)
        XCTAssertEqual(second, 0)        // re-entrant call no-ops
        gated.release()
        let sent = await first
        XCTAssertEqual(sent, 1)
        XCTAssertEqual(gated.calls.count, 1, "exactly one request")
        let after = await box.pending()
        XCTAssertTrue(after.isEmpty)
    }

    func testDrainURLPayload() async throws {
        let box = Outbox(directory: dir)
        try await box.enqueue(.url, payload: ["url": "https://example.com", "content": "ctx", "is_public": "true"])
        let server = FakeCaptureServer()
        let sent = await box.drain(api: api(server), accessToken: "jwt", userId: userId)
        XCTAssertEqual(sent, 1)
        let call = try XCTUnwrap(server.captures.first)
        XCTAssertEqual(call.kind, "url")
        XCTAssertEqual(call.meta["url"] as? String, "https://example.com")
        XCTAssertEqual(call.meta["content"] as? String, "ctx")
        XCTAssertEqual(call.meta["is_public"] as? Bool, true)
    }

    func testDrainAlreadyUploadedFilePayload() async throws {
        let box = Outbox(directory: dir)
        let path = "\(userId.uuidString.lowercased())/x.png"
        try await box.enqueue(.file, payload: ["file_path": path, "mime_type": "image/png", "file_size": "1234", "is_public": "false"])
        let server = FakeCaptureServer()
        let recorder = UploadRecorder()
        let sent = await box.drain(api: api(server), accessToken: "jwt", userId: userId, upload: recorder.closure)
        XCTAssertEqual(sent, 1)
        XCTAssertTrue(recorder.calls.isEmpty, "bytes already in Storage are never re-uploaded")
        let call = try XCTUnwrap(server.captures.first)
        XCTAssertFalse(call.isMultipart)
        XCTAssertEqual(call.meta["file_path"] as? String, path)
        XCTAssertEqual(call.meta["file_size"] as? Int, 1234)
        XCTAssertEqual(call.meta["mime_type"] as? String, "image/png")
        XCTAssertEqual(call.meta["is_public"] as? Bool, false)
    }

    // Task 5: `attributes_json` — the Outbox's text-only payload can't hold a nested object, so the
    // blob rides as a JSON string; the capture request must carry it as a real `attributes` object.
    func testFileEntryRoundTripsAttributesJSON() async throws {
        let box = Outbox(directory: dir)
        let attributes = ItemAttributes(location: CapturedLocation(label: "Testville", source: "manual"),
                                        media: MediaAttributes(durationS: 12, fileName: "clip.mp4"))
        let attributesJSON = String(data: try JSONEncoder().encode(attributes), encoding: .utf8)!
        try await box.enqueue(.file, payload: [
            "file_path": "\(userId.uuidString.lowercased())/x.png", "mime_type": "image/png", "file_size": "1234",
            "is_public": "false", "attributes_json": attributesJSON,
        ])
        let server = FakeCaptureServer()

        let sent = await box.drain(api: api(server), accessToken: "jwt", userId: userId)

        XCTAssertEqual(sent, 1)
        let body = try XCTUnwrap(server.captures.first?.attributes)
        XCTAssertEqual((body["location"] as? [String: Any])?["label"] as? String, "Testville")
        XCTAssertEqual((body["media"] as? [String: Any])?["file_name"] as? String, "clip.mp4")
    }

    // Cross-account capture leak (Critical, final review): `defaultDirectory(userId:)` must resolve
    // to a distinct, deterministic path per user so two accounts can never share an Outbox.
    func testPerUserDirectoriesAreIsolated() {
        let uid1 = UUID()
        let uid2 = UUID()
        let dir1 = Outbox.defaultDirectory(userId: uid1)
        let dir2 = Outbox.defaultDirectory(userId: uid2)
        XCTAssertNotEqual(dir1, dir2, "two different users must resolve to two different Outbox directories")
        XCTAssertEqual(dir1.lastPathComponent, uid1.uuidString.lowercased())
        XCTAssertEqual(dir2.lastPathComponent, uid2.uuidString.lowercased())
        XCTAssertEqual(dir1.deletingLastPathComponent().lastPathComponent, "StashOutbox")
        XCTAssertEqual(dir2.deletingLastPathComponent().lastPathComponent, "StashOutbox")
        XCTAssertEqual(dir1, Outbox.defaultDirectory(userId: uid1))
    }

    func testDefaultDirectoryDelegatesToAppGroupUserScopedURL() {
        let uid = UUID()
        XCTAssertEqual(Outbox.defaultDirectory(userId: uid), AppGroup.userScopedURL("StashOutbox", userId: uid))
    }

    func testCrossDirectoryDrainNeverSendsAnotherDirectorysEntries() async throws {
        let dirA = FileManager.default.temporaryDirectory.appending(path: "outbox-userA-\(UUID().uuidString)")
        let dirB = FileManager.default.temporaryDirectory.appending(path: "outbox-userB-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: dirA)
            try? FileManager.default.removeItem(at: dirB)
        }
        let boxA = Outbox(directory: dirA)
        try await boxA.enqueue(.note, payload: ["content": "user A's offline note", "is_public": "false"])
        let boxB = Outbox(directory: dirB)
        let pendingB = await boxB.pending()
        XCTAssertTrue(pendingB.isEmpty)

        let server = FakeCaptureServer()
        let sentB = await boxB.drain(api: api(server), accessToken: "user-b-jwt", userId: UUID())
        XCTAssertEqual(sentB, 0, "draining dirB must never send dirA's queued entry under user B's token")
        XCTAssertTrue(server.calls.isEmpty)
        let pendingA = await boxA.pending()
        XCTAssertEqual(pendingA.count, 1)
        XCTAssertEqual(pendingA[0].payload["content"], "user A's offline note")
    }

    // MARK: - Local files: one-shot (≤ limit) — plan 15

    func testSmallLocalFileGoesAsOneMultipartRequestAndIsDeletedAfter() async throws {
        let box = Outbox(directory: dir)
        let bytes = Data([0x01, 0x02, 0x03, 0x04])
        let local = try localFile(bytes)
        let entry = try await fileEntry(box, local: local)
        let server = FakeCaptureServer()
        let recorder = UploadRecorder()

        let sent = await box.drain(api: api(server), accessToken: "jwt", userId: userId, upload: recorder.closure)

        XCTAssertEqual(sent, 1)
        XCTAssertTrue(recorder.calls.isEmpty, "a file within the one-shot limit never touches the storage lane")
        XCTAssertEqual(server.calls.count, 1, "ONE request carries meta and bytes together")
        let call = try XCTUnwrap(server.captures.first)
        XCTAssertTrue(call.isMultipart)
        XCTAssertEqual(call.captureId, entry.id.uuidString.lowercased())
        XCTAssertEqual(call.meta["mime_type"] as? String, "audio/mp4")
        XCTAssertEqual(call.meta["file_size"] as? Int, 4)
        XCTAssertEqual(call.filePart?.data, bytes)
        XCTAssertFalse(FileManager.default.fileExists(atPath: local.path), "the local copy is redundant once captured")
        let after = await box.pending()
        XCTAssertTrue(after.isEmpty)
    }

    func testOneShotFailureKeepsTheEntryAndTheLocalFile() async throws {
        let box = Outbox(directory: dir)
        let local = try localFile()
        try await fileEntry(box, local: local)
        let server = FakeCaptureServer()
        server.captureBehaviors = [.fail(URLError(.notConnectedToInternet))]

        let sent = await box.drain(api: api(server), accessToken: "jwt", userId: userId)

        XCTAssertEqual(sent, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: local.path), "a failed send must never delete the only copy")
        let after = await box.pending()
        XCTAssertEqual(after.first?.attempts, 1)
        XCTAssertEqual(after.first?.payload["local_file_path"], local.path)
    }

    // MARK: - Local files: two-step (> limit) — plan 15

    func testBigLocalFileUploadsToTheDeterministicPathThenCapturesByFilePath() async throws {
        let box = Outbox(directory: dir)
        let bytes = Data([0x01, 0x02, 0x03, 0x04])
        let local = try localFile(bytes)
        let entry = try await fileEntry(box, local: local)
        let server = FakeCaptureServer()
        let recorder = UploadRecorder()

        let sent = await box.drain(api: api(server, oneShotLimit: 3), accessToken: "jwt", userId: userId,
                                   upload: recorder.closure)

        XCTAssertEqual(sent, 1)
        XCTAssertEqual(recorder.calls.count, 1, "the bytes go to Storage exactly once")
        XCTAssertEqual(recorder.calls[0].fileURL, local, "the lane streams the FILE — never a loaded Data blob")
        XCTAssertEqual(recorder.calls[0].bytesAtCallTime, bytes)
        XCTAssertEqual(recorder.calls[0].contentType, "audio/mp4")
        let expectedPath = "\(userId.uuidString.lowercased())/\(entry.id.uuidString.lowercased()).m4a"
        XCTAssertEqual(recorder.calls[0].path, expectedPath, "deterministic per entry: <uid>/<entryId>.<ext>")
        let call = try XCTUnwrap(server.captures.first)
        XCTAssertFalse(call.isMultipart, "the second half is a JSON capture")
        XCTAssertEqual(call.meta["file_path"] as? String, expectedPath)
        XCTAssertEqual(call.meta["file_size"] as? Int, 4, "file_size is captured before the local copy is deleted")
        XCTAssertEqual(call.captureId, entry.id.uuidString.lowercased())
        XCTAssertFalse(FileManager.default.fileExists(atPath: local.path))
        let after = await box.pending()
        XCTAssertTrue(after.isEmpty)
    }

    func testDefaultStorageLaneUsesTheTransportWithUpsert() async throws {
        let box = Outbox(directory: dir)
        let bytes = Data([0x09, 0x08, 0x07, 0x06])
        let local = try localFile(bytes)
        let entry = try await fileEntry(box, local: local)
        let server = FakeCaptureServer()

        let sent = await box.drain(api: api(server, oneShotLimit: 1), accessToken: "jwt", userId: userId)   // upload: nil

        XCTAssertEqual(sent, 1)
        let storage = try XCTUnwrap(server.storageUploads.first)
        XCTAssertEqual(storage.header("x-upsert"), "true")
        XCTAssertEqual(storage.header("Authorization"), "Bearer jwt", "the default lane reuses drain's own token")
        let path = "\(userId.uuidString.lowercased())/\(entry.id.uuidString.lowercased()).m4a"
        XCTAssertEqual(server.objects[path], bytes)
    }

    func testTwoStepUploadFailureRetainsEntryAndKeepsTheLocalCopy() async throws {
        let box = Outbox(directory: dir)
        let local = try localFile(Data([0x09, 0x08]))
        try await fileEntry(box, local: local)
        let recorder = UploadRecorder(); recorder.shouldFail = true
        let server = FakeCaptureServer()

        let sent = await box.drain(api: api(server, oneShotLimit: 1), accessToken: "jwt", userId: userId,
                                   upload: recorder.closure)

        XCTAssertEqual(sent, 0)
        XCTAssertTrue(server.captures.isEmpty, "capture must never be reached when the upload itself failed")
        XCTAssertTrue(FileManager.default.fileExists(atPath: local.path))
        let after = await box.pending()
        XCTAssertEqual(after.count, 1)
        XCTAssertEqual(after[0].attempts, 1)
        XCTAssertEqual(after[0].payload["local_file_path"], local.path, "retried as a local-file upload, not downgraded")
    }

    // The upload can succeed while the capture that follows fails (or the process dies first): the
    // checkpoint (`file_path` set — it wins over `local_file_path`) must be on disk BEFORE the
    // capture is attempted, and a retry must never re-upload. Verified across two drains on a
    // rehydrated Outbox.
    func testTwoStepUploadSucceedsButCaptureFailsPersistsCheckpointThenRetryNeverReuploads() async throws {
        let box = Outbox(directory: dir)
        let local = try localFile(Data([0x0A, 0x0B, 0x0C]))
        let entry = try await fileEntry(box, local: local)
        let recorder = UploadRecorder()
        let server = FakeCaptureServer()
        server.captureBehaviors = [.respond(500, #"{"error":"boom"}"#)]

        let firstSent = await box.drain(api: api(server, oneShotLimit: 1), accessToken: "jwt", userId: userId,
                                        upload: recorder.closure)
        XCTAssertEqual(firstSent, 0)
        XCTAssertEqual(recorder.calls.count, 1)
        let uploadedPath = recorder.calls[0].path
        XCTAssertFalse(FileManager.default.fileExists(atPath: local.path), "local copy is redundant once uploaded")

        let rehydrated = Outbox(directory: dir)
        let afterFirst = await rehydrated.pending()
        XCTAssertEqual(afterFirst.count, 1)
        XCTAssertEqual(afterFirst[0].payload["file_path"], uploadedPath)
        XCTAssertEqual(afterFirst[0].payload["local_file_path"], local.path,
                       "the local reference is kept (file_path wins) so the file is never unreferenced")
        XCTAssertEqual(afterFirst[0].payload["file_size"], "3")
        XCTAssertEqual(afterFirst[0].attempts, 1)

        let secondSent = await rehydrated.drain(api: api(server, oneShotLimit: 1), accessToken: "jwt", userId: userId,
                                                upload: recorder.closure)
        XCTAssertEqual(secondSent, 1)
        XCTAssertEqual(recorder.calls.count, 1, "a retry must never re-upload")
        XCTAssertEqual(server.captures.last?.meta["file_path"] as? String, uploadedPath)
        XCTAssertEqual(Set(server.captures.compactMap(\.captureId)), [entry.id.uuidString.lowercased()])
        let afterSecond = await rehydrated.pending()
        XCTAssertTrue(afterSecond.isEmpty)
    }

    // Direct ordering proof for the checkpoint: observes the ON-DISK entry at the exact instant the
    // capture request goes out, not just the final state after `drain` returns.
    func testTwoStepPersistsTheCheckpointToDiskBeforeTheCaptureRequest() async throws {
        let box = Outbox(directory: dir)
        let local = try localFile(Data([0x01, 0x02]))
        try await fileEntry(box, local: local)
        let server = FakeCaptureServer()
        server.captureBehaviors = [.respond(500, "{}")]
        let directory = dir!
        let snapshot = SnapshotBox()
        server.onRequest = { call in
            guard call.isCapture else { return }
            snapshot.payload = await Outbox(directory: directory).pending().first?.payload
        }

        _ = await box.drain(api: api(server, oneShotLimit: 1), accessToken: "jwt", userId: userId,
                            upload: UploadRecorder().closure)

        let payload = try XCTUnwrap(snapshot.payload, "the capture request must have gone out")
        XCTAssertNotNil(payload["file_path"], "the checkpoint must already be on disk when capture is attempted")
        XCTAssertEqual(payload["local_file_path"], local.path, "the local reference stays alongside file_path")
        XCTAssertFalse(FileManager.default.fileExists(atPath: local.path),
                       "the local copy goes only after the checkpoint is durable — before the capture request")
        XCTAssertFalse(try XCTUnwrap(server.captures.first).isMultipart, "file_path wins: a JSON capture")
    }

    // MARK: - Crash windows around local-file cleanup (plan 15 review)

    /// A process killed after the checkpoint was written but BEFORE the local copy was deleted
    /// leaves [entry with file_path + local_file_path, local file still present]. The file is still
    /// referenced, so `sweepOrphans` must NOT re-enqueue it under a second capture id; the next
    /// drain sends JSON with the same id and then deletes the file.
    func testKillBetweenCheckpointAndLocalDeleteNeverMintsASecondCaptureId() async throws {
        let box = Outbox(directory: dir)
        let staging = StagedFileStore(userId: userId, directory: filesDir)
        let local = try staging.stage(data: Data([0x01, 0x02, 0x03]), fileExtension: "mov")
        let entry = try await box.enqueue(.file, payload: [
            "local_file_path": local.path, "file_path": "\(userId.uuidString.lowercased())/\(UUID()).mov",
            "mime_type": "video/quicktime", "file_size": "3", "is_public": "false",
        ])
        let recordings = RecordingStore(userId: userId, directory: filesDir.appending(path: "rec"))
        let farFuture: @Sendable () -> Date = { Date().addingTimeInterval(3600) }

        let swept = await sweepOrphans(userId: userId, outbox: box, recordings: recordings, staging: staging, now: farFuture)

        XCTAssertEqual(swept, 0, "a checkpointed entry still references its local file")
        let server = FakeCaptureServer()
        let sent = await box.drain(api: api(server), accessToken: "jwt", userId: userId)
        XCTAssertEqual(sent, 1)
        XCTAssertEqual(server.captures.map(\.captureId), [entry.id.uuidString.lowercased()])
        XCTAssertFalse(try XCTUnwrap(server.captures.first).isMultipart)
        XCTAssertTrue(server.storageUploads.isEmpty, "never re-uploaded")
        XCTAssertFalse(FileManager.default.fileExists(atPath: local.path), "deleted once captured")
        let after = await box.pending()
        XCTAssertTrue(after.isEmpty)
    }

    /// Completion deletes the local file FIRST: if it can't (made undeletable here), the entry is
    /// kept — still naming the file — so the file is never unreferenced, `sweepOrphans` never
    /// re-enqueues it, and the next pass replays idempotently (same capture id, still one item).
    func testCompletionDeletesTheLocalFileBeforeTheEntry() async throws {
        let box = Outbox(directory: dir)
        let lockedDir = filesDir.appending(path: "locked")
        try FileManager.default.createDirectory(at: lockedDir, withIntermediateDirectories: true)
        let local = lockedDir.appending(path: "clip.m4a")
        try Data([0x01, 0x02]).write(to: local)
        let entry = try await fileEntry(box, local: local)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: lockedDir.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: lockedDir.path) }
        let server = FakeCaptureServer()

        let result = await box.sendNow(id: entry.id, api: api(server), userId: userId, accessToken: "jwt")

        guard case .sent = result else { return XCTFail("expected .sent, got \(result)") }
        XCTAssertTrue(FileManager.default.fileExists(atPath: local.path), "fixture: the file really is undeletable")
        let kept = await box.entry(id: entry.id)
        XCTAssertEqual(kept?.payload["local_file_path"], local.path, "the entry must outlive a local file it couldn't delete")
        let staging = StagedFileStore(userId: userId, directory: lockedDir)
        let recordings = RecordingStore(userId: userId, directory: filesDir.appending(path: "rec"))
        let swept = await sweepOrphans(userId: userId, outbox: box, recordings: recordings, staging: staging,
                                       now: { Date().addingTimeInterval(3600) })
        XCTAssertEqual(swept, 0, "the file is still referenced — no second capture id")

        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: lockedDir.path)
        let sent = await box.drain(api: api(server), accessToken: "jwt", userId: userId)

        XCTAssertEqual(sent, 1)
        XCTAssertEqual(server.createdItemCount, 1, "the replay was a duplicate — still one item")
        XCTAssertEqual(Set(server.captures.compactMap(\.captureId)), [entry.id.uuidString.lowercased()])
        XCTAssertFalse(FileManager.default.fileExists(atPath: local.path))
        let after = await box.pending()
        XCTAssertTrue(after.isEmpty)
    }

    /// A process killed after the local file was deleted but before the entry was removed leaves
    /// [entry, no local file]: the next pass drops it (the capture already landed) — one item, and
    /// nothing for `sweepOrphans` to find.
    func testKillBetweenLocalDeleteAndEntryRemovalLeavesOneItem() async throws {
        let box = Outbox(directory: dir)
        let local = try localFile(Data([0x07]))
        let entry = try await fileEntry(box, local: local)
        let server = FakeCaptureServer()
        server.captureBehaviors = [.applyThenFail(URLError(.networkConnectionLost))]
        _ = await box.sendNow(id: entry.id, api: api(server), userId: userId, accessToken: "jwt")
        XCTAssertEqual(server.createdItemCount, 1)
        try FileManager.default.removeItem(at: local)   // the state that kill leaves behind

        let sent = await box.drain(api: api(server), accessToken: "jwt", userId: userId)

        XCTAssertEqual(sent, 0)
        XCTAssertEqual(server.captures.count, 1, "nothing left to send")
        XCTAssertEqual(server.createdItemCount, 1)
        let after = await box.pending()
        XCTAssertTrue(after.isEmpty, "the orphaned entry is dropped")
    }

    /// If the checkpoint can't be written, the local copy is kept at that point — and still deleted
    /// once the capture succeeds (the in-memory entry keeps naming it).
    func testLocalFileIsDeletedAfterSuccessEvenWhenTheCheckpointWriteFailed() async throws {
        let box = Outbox(directory: dir)
        let local = try localFile(Data([0x01, 0x02, 0x03]))
        let entry = try await fileEntry(box, local: local)
        let entryFile = dir.appending(path: "\(entry.id.uuidString).json")
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: entryFile.path)   // writes fail
        defer { try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: entryFile.path) }
        let server = FakeCaptureServer()

        let result = await box.sendNow(id: entry.id, api: api(server, oneShotLimit: 1), userId: userId,
                                       accessToken: "jwt", upload: UploadRecorder().closure)

        guard case .sent = result else { return XCTFail("expected .sent, got \(result)") }
        let onDisk = try JSONDecoder().decode(OutboxEntry.self, from: Data(contentsOf: entryFile))
        XCTAssertNil(onDisk.payload["file_path"], "fixture: the checkpoint write really failed")
        XCTAssertFalse(FileManager.default.fileExists(atPath: local.path),
                       "a successful capture must still delete the local copy")
    }

    func test413FallsBackToTheTwoStepLaneWithinTheSameSend() async throws {
        let box = Outbox(directory: dir)
        let local = try localFile(Data([0x01, 0x02, 0x03]))
        let entry = try await fileEntry(box, local: local)
        let server = FakeCaptureServer()
        server.captureBehaviors = [.respond(413, #"{"error":"file_too_large"}"#)]
        let recorder = UploadRecorder()

        let sent = await box.drain(api: api(server), accessToken: "jwt", userId: userId, upload: recorder.closure)

        XCTAssertEqual(sent, 1, "413 is not a failure — the same send retries through Storage")
        XCTAssertEqual(server.captures.count, 2)
        XCTAssertTrue(server.captures[0].isMultipart)
        XCTAssertFalse(server.captures[1].isMultipart)
        XCTAssertEqual(recorder.calls.count, 1)
        XCTAssertEqual(server.captures[1].meta["file_path"] as? String, recorder.calls[0].path)
        XCTAssertEqual(server.captures.map(\.captureId), [entry.id.uuidString.lowercased(), entry.id.uuidString.lowercased()])
        let after = await box.pending()
        XCTAssertTrue(after.isEmpty)
    }

    func testRepeatedOneShotFailuresSwitchToTheTwoStepLane() async throws {
        let box = Outbox(directory: dir)
        let local = try localFile(Data([0x05]))
        try await fileEntry(box, local: local)
        let server = FakeCaptureServer()
        server.captureBehaviors = Array(repeating: .respond(546, #"{"code":"WORKER_LIMIT"}"#), count: CaptureAPI.oneShotMaxAttempts)
        let recorder = UploadRecorder()

        for _ in 0..<CaptureAPI.oneShotMaxAttempts {
            _ = await box.drain(api: api(server), accessToken: "jwt", userId: userId, upload: recorder.closure)
        }
        XCTAssertTrue(recorder.calls.isEmpty)
        XCTAssertTrue(server.captures.allSatisfy(\.isMultipart))

        let sent = await box.drain(api: api(server), accessToken: "jwt", userId: userId, upload: recorder.closure)

        XCTAssertEqual(sent, 1)
        XCTAssertEqual(recorder.calls.count, 1, "after \(CaptureAPI.oneShotMaxAttempts) failed one-shots the storage lane takes over")
        XCTAssertFalse(try XCTUnwrap(server.captures.last).isMultipart)
    }

    // Dropping an entry is permanent and data-destroying, so its branch — the file referenced by
    // `local_file_path` no longer exists — gets its own test.
    func testDrainMissingLocalFileDropsEntryPermanentlyWithoutUploadingOrSending() async throws {
        let box = Outbox(directory: dir)
        let goneFile = filesDir.appending(path: "gone-\(UUID().uuidString).m4a")
        try await box.enqueue(.file, payload: ["local_file_path": goneFile.path, "mime_type": "audio/mp4", "is_public": "false"])
        let recorder = UploadRecorder()
        let server = FakeCaptureServer()

        let sent = await box.drain(api: api(server), accessToken: "jwt", userId: userId, upload: recorder.closure)

        XCTAssertEqual(sent, 0, "a dropped entry was never delivered, so it must not count as sent")
        XCTAssertTrue(recorder.calls.isEmpty)
        XCTAssertTrue(server.calls.isEmpty)
        let after = await box.pending()
        XCTAssertTrue(after.isEmpty, "retrying a permanently-failed entry can never succeed")
    }

    // MARK: - Idempotency (plan 15)

    /// The response to the first attempt is lost AFTER the server created the item. The retry
    /// carries the same capture id; the server answers `duplicate: true` with the same item, the
    /// entry completes, and the server holds exactly ONE item.
    func testIdempotentResendAfterALostResponseCreatesNoSecondItem() async throws {
        let box = Outbox(directory: dir)
        let entry = try await box.enqueue(.url, payload: ["url": "https://example.com", "content": "", "is_public": "false"])
        let server = FakeCaptureServer()
        server.captureBehaviors = [.applyThenFail(URLError(.networkConnectionLost))]

        let firstSent = await box.drain(api: api(server), accessToken: "jwt", userId: userId)
        XCTAssertEqual(firstSent, 0)
        XCTAssertEqual(server.createdItemCount, 1, "the server did create the item — only the answer was lost")
        let retained = await box.pending()
        XCTAssertEqual(retained.first?.attempts, 1)

        let captured = expectation(forNotification: .stashItemCaptured, object: nil) { note in
            (note.userInfo?["duplicate"] as? Bool) == true && note.userInfo?["item"] is Item
        }
        let secondSent = await box.drain(api: api(server), accessToken: "jwt", userId: userId)

        XCTAssertEqual(secondSent, 1, "a duplicate replay completes the entry")
        XCTAssertEqual(server.createdItemCount, 1, "no second item")
        XCTAssertEqual(server.captures.map(\.captureId), [entry.id.uuidString.lowercased(), entry.id.uuidString.lowercased()],
                       "both attempts carried the entry id as the capture id")
        let after = await box.pending()
        XCTAssertTrue(after.isEmpty)
        await fulfillment(of: [captured], timeout: 2)
    }

    func testSuccessPostsStashItemCapturedWithTheItem() async throws {
        let box = Outbox(directory: dir)
        let entry = try await box.enqueue(.note, payload: ["content": "hello", "is_public": "false"])
        let server = FakeCaptureServer()
        let expectedUserId = userId
        let captured = expectation(forNotification: .stashItemCaptured, object: nil) { note in
            guard let item = note.userInfo?["item"] as? Item else { return false }
            return item.content == "hello" && (note.userInfo?["duplicate"] as? Bool) == false
                && (note.userInfo?["userId"] as? UUID) == expectedUserId
        }

        let result = await box.sendNow(id: entry.id, api: api(server), userId: userId, accessToken: "jwt")

        guard case .sent(let capture) = result else { return XCTFail("expected .sent, got \(result)") }
        XCTAssertEqual(capture.item?.content, "hello")
        await fulfillment(of: [captured], timeout: 2)
    }

    // MARK: - sendNow (plan 15)

    func testSendNowSendsOnlyThatEntry() async throws {
        let box = Outbox(directory: dir)
        try await box.enqueue(.note, payload: ["content": "older", "is_public": "false"])
        let target = try await box.enqueue(.note, payload: ["content": "mine", "is_public": "false"])
        let server = FakeCaptureServer()

        let result = await box.sendNow(id: target.id, api: api(server), userId: userId, accessToken: "jwt")

        guard case .sent = result else { return XCTFail("expected .sent, got \(result)") }
        XCTAssertEqual(server.captures.map { $0.meta["content"] as? String }, ["mine"])
        let remaining = await box.pending()
        XCTAssertEqual(remaining.map { $0.payload["content"] }, ["older"])
    }

    func testSendNowOnAParkedEntryDoesNothing() async throws {
        let box = Outbox(directory: dir)
        let entry = try await box.enqueue(.note, payload: ["content": "gated", "is_public": "false"], status: .parked)
        let server = FakeCaptureServer()
        let result = await box.sendNow(id: entry.id, api: api(server), userId: userId, accessToken: "jwt")
        XCTAssertEqual(result, .parked)
        XCTAssertTrue(server.calls.isEmpty)
    }

    func testSendNowLeavesAFreshTransferToItsBackgroundSession() async throws {
        let box = Outbox(directory: dir)
        let entry = try await box.enqueue(.note, payload: ["content": "bg", "is_public": "false"], status: .transferring)
        let server = FakeCaptureServer()
        let result = await box.sendNow(id: entry.id, api: api(server), userId: userId, accessToken: "jwt")
        XCTAssertEqual(result, .inFlight)
        XCTAssertTrue(server.calls.isEmpty)
    }

    func testSendNowOnAClaimedEntryIsInFlight() async throws {
        let box = Outbox(directory: dir)
        let entry = try await box.enqueue(.note, payload: ["content": "x", "is_public": "false"])
        let otherProcess = Outbox(directory: dir)
        let claimed = await otherProcess.claimEntry(id: entry.id)
        XCTAssertTrue(claimed)
        let server = FakeCaptureServer()
        let result = await box.sendNow(id: entry.id, api: api(server), userId: userId, accessToken: "jwt")
        XCTAssertEqual(result, .inFlight)
        XCTAssertTrue(server.calls.isEmpty)
    }

    func testSendNowUnknownIdIsNotFound() async {
        let result = await Outbox(directory: dir).sendNow(id: UUID(), api: api(FakeCaptureServer()), userId: userId, accessToken: "jwt")
        XCTAssertEqual(result, .notFound)
    }

    func testCaptureInProgressLeavesPendingWithoutCountingAnAttempt() async throws {
        let box = Outbox(directory: dir)
        let entry = try await box.enqueue(.note, payload: ["content": "x", "is_public": "false"])
        let server = FakeCaptureServer()
        server.captureBehaviors = [.respond(409, captureInProgressBody)]

        let result = await box.sendNow(id: entry.id, api: api(server), userId: userId, accessToken: "jwt")

        XCTAssertEqual(result, .pending)
        let after = await box.entry(id: entry.id)
        XCTAssertEqual(after?.status, .pending)
        XCTAssertEqual(after?.attempts, 0, "409 means another attempt is mid-flight — not a failed attempt")
        let claimURL = dir.appending(path: "\(entry.id.uuidString).claim")
        XCTAssertFalse(FileManager.default.fileExists(atPath: claimURL.path))
    }

    // MARK: - Transferring (plan 15)

    func testEnqueueTransferringStampsTheStartTime() async throws {
        let startedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let box = Outbox(directory: dir, now: { startedAt })
        let entry = try await box.enqueue(.note, payload: ["content": "x", "is_public": "false"], status: .transferring)
        XCTAssertEqual(entry.status, .transferring)
        XCTAssertEqual(entry.transferStartedAt, startedAt)
        let persisted = await Outbox(directory: dir).entry(id: entry.id)
        XCTAssertEqual(persisted?.transferStartedAt, startedAt)
    }

    func testDrainSkipsAFreshTransfer() async throws {
        let box = Outbox(directory: dir)
        try await box.enqueue(.note, payload: ["content": "bg", "is_public": "false"], status: .transferring)
        let server = FakeCaptureServer()
        let sent = await box.drain(api: api(server), accessToken: "jwt", userId: userId)
        XCTAssertEqual(sent, 0)
        XCTAssertTrue(server.calls.isEmpty, "a background transfer younger than staleTransferInterval owns the entry")
    }

    func testDrainResendsAStaleTransfer() async throws {
        let longAgo = Date().addingTimeInterval(-(Outbox.staleTransferInterval + 60))
        let extensionBox = Outbox(directory: dir, now: { longAgo })
        let entry = try await extensionBox.enqueue(.note, payload: ["content": "bg", "is_public": "false"], status: .transferring)
        let server = FakeCaptureServer()

        let sent = await Outbox(directory: dir).drain(api: api(server), accessToken: "jwt", userId: userId)

        XCTAssertEqual(sent, 1, "a transfer older than staleTransferInterval is resent (the server dedupes if it landed)")
        XCTAssertEqual(server.captures.first?.captureId, entry.id.uuidString.lowercased())
        XCTAssertEqual(Outbox.staleTransferInterval, 600)
    }

    func testDrainResendsATransferWithNoStartTime() async throws {
        let id = UUID()
        let json = """
        {"id":"\(id.uuidString)","kind":"note","payload":{"content":"x","is_public":"false"},
         "createdAt":\(Date().timeIntervalSinceReferenceDate),"attempts":0,"status":"transferring"}
        """
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(json.utf8).write(to: dir.appending(path: "\(id.uuidString).json"))
        let server = FakeCaptureServer()

        let sent = await Outbox(directory: dir).drain(api: api(server), accessToken: "jwt", userId: userId)

        XCTAssertEqual(sent, 1)
        XCTAssertEqual(server.captures.first?.captureId, id.uuidString.lowercased())
    }

    func testAFailedResendOfAStaleTransferBecomesPendingAndCountsTheAttempt() async throws {
        let longAgo = Date().addingTimeInterval(-(Outbox.staleTransferInterval + 60))
        let entry = try await Outbox(directory: dir, now: { longAgo })
            .enqueue(.note, payload: ["content": "bg", "is_public": "false"], status: .transferring)
        let server = FakeCaptureServer()
        server.captureBehaviors = [.respond(503, "{}")]

        _ = await Outbox(directory: dir).drain(api: api(server), accessToken: "jwt", userId: userId)

        let after = await Outbox(directory: dir).entry(id: entry.id)
        XCTAssertEqual(after?.status, .pending)
        XCTAssertNil(after?.transferStartedAt)
        XCTAssertEqual(after?.attempts, 1)
    }

    // MARK: - Background-transfer helpers (plan 15, Task 4)

    func testMarkTransferringStampsNowAndSkipsParked() async throws {
        let now = Date(timeIntervalSince1970: 1_900_000_000)
        let box = Outbox(directory: dir, now: { now })
        let pending = try await box.enqueue(.note, payload: ["content": "p", "is_public": "false"])
        let parked = try await box.enqueue(.note, payload: ["content": "g", "is_public": "false"], status: .parked)

        let marked = await box.markTransferring(ids: [pending.id, parked.id, UUID()])

        XCTAssertEqual(marked.map(\.id), [pending.id])
        let reread = await box.entry(id: pending.id)
        XCTAssertEqual(reread?.status, .transferring)
        XCTAssertEqual(reread?.transferStartedAt, now)
        let stillParked = await box.entry(id: parked.id)
        XCTAssertEqual(stillParked?.status, .parked, "a gated entry is never handed to a transfer")
    }

    func testMarkPendingOptionallyCountsAnAttempt() async throws {
        let box = Outbox(directory: dir)
        let entry = try await box.enqueue(.note, payload: ["content": "x", "is_public": "false"], status: .transferring)

        await box.markPending(id: entry.id, incrementAttempts: false)
        var reread = await box.entry(id: entry.id)
        XCTAssertEqual(reread?.status, .pending)
        XCTAssertNil(reread?.transferStartedAt)
        XCTAssertEqual(reread?.attempts, 0)

        await box.markPending(id: entry.id, incrementAttempts: true)
        reread = await box.entry(id: entry.id)
        XCTAssertEqual(reread?.attempts, 1)

        await box.markPending(id: UUID(), incrementAttempts: true)   // unknown id: no-op, no file created
        let all = await box.pending()
        XCTAssertEqual(all.count, 1)
    }

    func testParkParksAnExistingEntry() async throws {
        let box = Outbox(directory: dir)
        let entry = try await box.enqueue(.note, payload: ["content": "x", "is_public": "false"], status: .transferring)
        await box.park(id: entry.id)
        let reread = await box.entry(id: entry.id)
        XCTAssertEqual(reread?.status, .parked)
        XCTAssertNil(reread?.transferStartedAt)
        XCTAssertEqual(reread?.attempts, 0)
    }

    func testCompleteRemovesEntryClaimAndLocalFile() async throws {
        let box = Outbox(directory: dir)
        let local = try localFile()
        let entry = try await fileEntry(box, local: local)
        let claimed = await box.claimEntry(id: entry.id)
        XCTAssertTrue(claimed)

        let removed = await box.complete(id: entry.id)

        XCTAssertEqual(removed?.id, entry.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: local.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appending(path: "\(entry.id.uuidString).claim").path))
        let all = await box.pending()
        XCTAssertTrue(all.isEmpty)
        let again = await box.complete(id: entry.id)
        XCTAssertNil(again, "completing twice (e.g. drain beat the transfer delegate) is a harmless no-op")
    }

    func testCheckpointRecordsTheStoragePathAndDropsTheLocalCopy() async throws {
        let box = Outbox(directory: dir)
        let local = try localFile(Data(repeating: 7, count: 42))
        let entry = try await fileEntry(box, local: local)

        let checkpointed = await box.checkpoint(id: entry.id, filePath: "\(userId.uuidString.lowercased())/x.m4a")

        XCTAssertEqual(checkpointed?.payload["file_path"], "\(userId.uuidString.lowercased())/x.m4a")
        XCTAssertEqual(checkpointed?.payload["local_file_path"], local.path,
                       "kept alongside file_path (which wins) until the entry is completed")
        XCTAssertEqual(checkpointed?.payload["file_size"], "42")
        XCTAssertFalse(FileManager.default.fileExists(atPath: local.path))
        let persisted = await Outbox(directory: dir).entry(id: entry.id)
        XCTAssertEqual(persisted, checkpointed)
        let unknown = await box.checkpoint(id: UUID(), filePath: "x")
        XCTAssertNil(unknown)
    }

    /// A status update must never resurrect an entry another process completed while this send
    /// was in flight (e.g. the background-transfer delegate finished it first).
    func testAFailureAfterAConcurrentCompletionDoesNotResurrectTheEntry() async throws {
        let box = Outbox(directory: dir)
        let entry = try await box.enqueue(.note, payload: ["content": "x", "is_public": "false"])
        let server = FakeCaptureServer()
        server.captureBehaviors = [.respond(500, "{}")]
        let directory = dir!
        server.onRequest = { _ in _ = await Outbox(directory: directory).complete(id: entry.id) }

        _ = await box.drain(api: api(server), accessToken: "jwt", userId: userId)

        let after = await box.pending()
        XCTAssertTrue(after.isEmpty)
    }

    // MARK: - Cross-process drain claims (Plan 5 Task 3)

    func testClaimedEntryIsSkippedByASecondOutbox() async throws {
        let boxA = Outbox(directory: dir)
        let entry = try await boxA.enqueue(.note, payload: ["content": "n1", "is_public": "false"])
        let claimed = await boxA.claimEntry(id: entry.id)
        XCTAssertTrue(claimed, "the first claim on a never-claimed entry must succeed")

        let boxB = Outbox(directory: dir)
        let server = FakeCaptureServer()
        let sent = await boxB.drain(api: api(server), accessToken: "jwt", userId: userId)

        XCTAssertEqual(sent, 0, "an entry already claimed by another process must be skipped, not sent")
        let pending = await boxB.pending()
        XCTAssertEqual(pending.count, 1)
        let claimURL = dir.appending(path: "\(entry.id.uuidString).claim")
        XCTAssertTrue(FileManager.default.fileExists(atPath: claimURL.path),
                      "a second process's drain must never remove a live claim it doesn't own")
    }

    func testStaleClaimIsReclaimed() async throws {
        let stalePast = Date().addingTimeInterval(-700)   // > the 600s staleClaimInterval
        let crashedBox = Outbox(directory: dir, now: { stalePast })
        let entry = try await crashedBox.enqueue(.note, payload: ["content": "n1", "is_public": "false"])
        let claimed = await crashedBox.claimEntry(id: entry.id)
        XCTAssertTrue(claimed)

        let box = Outbox(directory: dir)   // real clock — reclaims the stale claim above
        let sent = await box.drain(api: api(FakeCaptureServer()), accessToken: "jwt", userId: userId)

        XCTAssertEqual(sent, 1, "a claim older than staleClaimInterval must be reclaimed and the entry sent")
        let pending = await box.pending()
        XCTAssertTrue(pending.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appending(path: "\(entry.id.uuidString).claim").path))
    }

    func testFailedSendReleasesClaim() async throws {
        let box = Outbox(directory: dir)
        let entry = try await box.enqueue(.note, payload: ["content": "n1", "is_public": "false"])
        let server = FakeCaptureServer()
        server.captureBehaviors = [.respond(500, "{}")]
        let sent = await box.drain(api: api(server), accessToken: "jwt", userId: userId)

        XCTAssertEqual(sent, 0)
        let after = await box.pending()
        XCTAssertEqual(after[0].attempts, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appending(path: "\(entry.id.uuidString).claim").path),
                       "a failed send must release its claim so a retry can pick the entry up")
    }

    // MARK: - Stale self-claims (plan 15 review)

    private let appName = "it.gostash.stash"

    private func claim(_ entryId: UUID, as owner: ClaimOwner) async -> Bool {
        await Outbox(directory: dir, claimOwner: owner).claimEntry(id: entryId)
    }

    /// The app is one process at a time: a FRESH claim stamped by the app's own bundle under
    /// another pid was left by a previous app process that died mid-send — reclaim it now, not
    /// 10 minutes later.
    func testTheAppReclaimsAClaimLeftByItsOwnPreviousProcessImmediately() async throws {
        let box = Outbox(directory: dir, claimOwner: ClaimOwner(name: appName, pid: 2002, isSingleProcessApp: true))
        let entry = try await box.enqueue(.note, payload: ["content": "x", "is_public": "false"])
        let claimed = await claim(entry.id, as: ClaimOwner(name: appName, pid: 1001, isSingleProcessApp: true))
        XCTAssertTrue(claimed)
        let server = FakeCaptureServer()

        let sent = await box.drain(api: api(server), accessToken: "jwt", userId: userId)

        XCTAssertEqual(sent, 1, "a dead predecessor's claim must not block the relaunched app")
    }

    /// Everything else keeps the age rule: the share extension (processes can overlap the app's),
    /// this very process (same pid: a live, in-flight send), and any non-app host.
    func testOtherFreshClaimsStillBlock() async throws {
        let app = ClaimOwner(name: appName, pid: 2002, isSingleProcessApp: true)
        let cases: [(owner: ClaimOwner, why: String)] = [
            (ClaimOwner(name: "it.gostash.stash.share", pid: 3003, isSingleProcessApp: false), "the share extension"),
            (ClaimOwner(name: appName, pid: 2002, isSingleProcessApp: true), "this same process"),
        ]
        for (owner, why) in cases {
            let box = Outbox(directory: dir, claimOwner: app)
            let entry = try await box.enqueue(.note, payload: ["content": why, "is_public": "false"])
            let claimed = await claim(entry.id, as: owner)
            XCTAssertTrue(claimed)
            let sent = await box.sendNow(id: entry.id, api: api(FakeCaptureServer()), userId: userId, accessToken: "jwt")
            XCTAssertEqual(sent, .inFlight, "a fresh claim by \(why) must be honored")
        }
        // Outside the app (the extension, or `swift test`), even same-name/different-pid claims keep
        // the age rule — only the app can know no other process of itself is alive.
        let extensionBox = Outbox(directory: dir, claimOwner: ClaimOwner(name: appName, pid: 4004, isSingleProcessApp: false))
        let entry = try await extensionBox.enqueue(.note, payload: ["content": "ext", "is_public": "false"])
        let claimed = await claim(entry.id, as: ClaimOwner(name: appName, pid: 1001, isSingleProcessApp: false))
        XCTAssertTrue(claimed)
        let sent = await extensionBox.sendNow(id: entry.id, api: api(FakeCaptureServer()), userId: userId, accessToken: "jwt")
        XCTAssertEqual(sent, .inFlight)
    }

    func testClaimStampsKeepTheirOnDiskFormat() {
        let owner = ClaimOwner(name: "it.gostash.stash", pid: 42, isSingleProcessApp: true)
        XCTAssertEqual(owner.stamp, "it.gostash.stash#42")
        XCTAssertTrue(owner.isDeadPredecessor(ofStamp: "it.gostash.stash#41"))
        XCTAssertFalse(owner.isDeadPredecessor(ofStamp: "it.gostash.stash#42"))
        XCTAssertFalse(owner.isDeadPredecessor(ofStamp: "it.gostash.stash.share#41"))
        XCTAssertFalse(owner.isDeadPredecessor(ofStamp: "garbage"))
    }

    // MARK: - 413 meta_too_large (plan 15 review)

    /// A capture whose meta is over the endpoint's 1 MiB limit (a huge pasted note) is a plain
    /// failed attempt — ONE request, no two-step detour that would only 413 again.
    func testMetaTooLargeIsAnOrdinaryFailedAttemptNotATwoStepLoop() async throws {
        let box = Outbox(directory: dir)
        let note = try await box.enqueue(.note, payload: ["content": String(repeating: "x", count: 64), "is_public": "false"])
        let local = try localFile(Data([0x01]))
        let file = try await fileEntry(box, local: local)
        let server = FakeCaptureServer()
        server.captureBehaviors = Array(repeating: .respond(413, #"{"error":"meta_too_large","max_bytes":1048576}"#), count: 2)
        let recorder = UploadRecorder()

        let noteResult = await box.sendNow(id: note.id, api: api(server), userId: userId, accessToken: "jwt", upload: recorder.closure)
        let fileResult = await box.sendNow(id: file.id, api: api(server), userId: userId, accessToken: "jwt", upload: recorder.closure)

        XCTAssertEqual(noteResult, .pending)
        XCTAssertEqual(fileResult, .pending)
        XCTAssertEqual(server.calls.count, 2, "exactly one request each")
        XCTAssertTrue(recorder.calls.isEmpty, "never switched to the storage lane")
        let noteAfter = await box.entry(id: note.id)
        let fileAfter = await box.entry(id: file.id)
        XCTAssertEqual(noteAfter?.attempts, 1)
        XCTAssertEqual(fileAfter?.attempts, 1)
    }

    // MARK: - Plan 14 T3: park-on-403

    func testDrainParksEntryOn403SubscriptionRequiredWithoutIncrementingAttempts() async throws {
        let box = Outbox(directory: dir)
        try await box.enqueue(.note, payload: ["content": "n1", "is_public": "false"])
        let server = FakeCaptureServer()
        server.captureBehaviors = [.respond(403, subscriptionRequiredBody)]
        let sent = await box.drain(api: api(server), accessToken: "jwt", userId: userId)

        XCTAssertEqual(sent, 0)
        let after = await box.pending()
        XCTAssertEqual(after.count, 1)
        XCTAssertEqual(after[0].status, .parked)
        XCTAssertEqual(after[0].attempts, 0, "a park is not a failed send attempt")
    }

    func testAnOther403BodyIsAnOrdinaryFailureNotAPark() async throws {
        let box = Outbox(directory: dir)
        try await box.enqueue(.note, payload: ["content": "n1", "is_public": "false"])
        let server = FakeCaptureServer()
        server.captureBehaviors = [.respond(403, #"{"error":"Agent tokens are only accepted by the MCP endpoint"}"#)]
        _ = await box.drain(api: api(server), accessToken: "jwt", userId: userId)
        let after = await box.pending()
        XCTAssertEqual(after[0].status, .pending)
        XCTAssertEqual(after[0].attempts, 1)
    }

    func testDrainSkipsParkedEntriesEntirelyOnSubsequentPasses() async throws {
        let box = Outbox(directory: dir)
        try await box.enqueue(.note, payload: ["content": "parked-one", "is_public": "false"])
        let server = FakeCaptureServer()
        server.captureBehaviors = [.respond(403, subscriptionRequiredBody)]
        _ = await box.drain(api: api(server), accessToken: "jwt", userId: userId)

        let sent = await box.drain(api: api(server), accessToken: "jwt", userId: userId)   // would succeed now

        XCTAssertEqual(sent, 0)
        XCTAssertEqual(server.captures.count, 1, "no request is ever made for a parked entry")
        let after = await box.pending()
        XCTAssertEqual(after[0].status, .parked)
        XCTAssertEqual(after[0].attempts, 0)
    }

    func testUnparkAllRestoresPendingAndPersistsAcrossInstances() async throws {
        let box = Outbox(directory: dir)
        try await box.enqueue(.note, payload: ["content": "n1", "is_public": "false"])
        let server = FakeCaptureServer()
        server.captureBehaviors = [.respond(403, subscriptionRequiredBody)]
        _ = await box.drain(api: api(server), accessToken: "jwt", userId: userId)
        let parked = await box.pending()
        XCTAssertEqual(parked.first?.status, .parked)

        let unparkedCount = await box.unparkAll()
        XCTAssertEqual(unparkedCount, 1)

        let rehydrated = Outbox(directory: dir)
        let afterUnpark = await rehydrated.pending()
        XCTAssertEqual(afterUnpark.first?.status, .pending)
        let sent = await rehydrated.drain(api: api(server), accessToken: "jwt", userId: userId)
        XCTAssertEqual(sent, 1)
    }

    func testUnparkAllOnNothingParkedIsANoOp() async throws {
        let box = Outbox(directory: dir)
        try await box.enqueue(.note, payload: ["content": "ordinary", "is_public": "false"])
        let unparkedCount = await box.unparkAll()
        XCTAssertEqual(unparkedCount, 0)
        let pending = await box.pending()
        XCTAssertEqual(pending.first?.status, .pending)
    }

    func testClearAllRemovesEntriesAndClaimSidecarsRegardlessOfStatus() async throws {
        let box = Outbox(directory: dir)
        try await box.enqueue(.note, payload: ["content": "one", "is_public": "false"])
        try await box.enqueue(.note, payload: ["content": "two", "is_public": "false"], status: .parked)
        try await box.enqueue(.note, payload: ["content": "three", "is_public": "false"], status: .transferring)
        _ = await box.claimEntry(id: UUID())   // a stray claim sidecar too

        await box.clearAll()

        let after = await box.pending()
        XCTAssertTrue(after.isEmpty)
        let remaining = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        XCTAssertTrue(remaining.isEmpty, "clearAll must remove every .json entry and .claim sidecar")
    }

    // MARK: - Back-compat decoding

    func testEntryWithNoStatusKeyDecodesAsPendingForBackwardCompatibility() throws {
        // A pre-plan-14 entry: no `status`, no `transferStartedAt`. OutboxEntry.createdAt is a plain
        // `Date`, which JSONEncoder/Decoder encode as a `Double` (secondsSinceReferenceDate).
        let id = UUID()
        let json = """
        {"id":"\(id.uuidString)","kind":"note","payload":{"content":"legacy","is_public":"false"},
         "createdAt":\(Date().timeIntervalSinceReferenceDate),"attempts":0}
        """
        let entry = try JSONDecoder().decode(OutboxEntry.self, from: Data(json.utf8))
        XCTAssertEqual(entry.status, .pending)
        XCTAssertNil(entry.transferStartedAt)
    }

    /// A pre-plan-15 entry on disk (plan-14 shape: `status` but no `transferStartedAt`, a
    /// `local_file_path` recording) decodes unchanged and drains through `capture` with its own
    /// UUID as the capture id — no migration needed.
    func testAPrePlan15EntryOnDiskDrainsThroughCaptureWithItsIdAsTheKey() async throws {
        let id = UUID()
        let local = try localFile(Data([0x01, 0x02]))
        let json = """
        {"id":"\(id.uuidString)","kind":"file","status":"pending","attempts":2,
         "payload":{"local_file_path":"\(local.path)","mime_type":"audio\\/mp4","is_public":"false"},
         "createdAt":\(Date().timeIntervalSinceReferenceDate)}
        """
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(json.utf8).write(to: dir.appending(path: "\(id.uuidString).json"))
        let box = Outbox(directory: dir)
        let decoded = await box.entry(id: id)
        XCTAssertEqual(decoded?.attempts, 2)
        XCTAssertEqual(decoded?.status, .pending)
        XCTAssertNil(decoded?.transferStartedAt)

        let server = FakeCaptureServer()
        let sent = await box.drain(api: api(server), accessToken: "jwt", userId: userId)

        XCTAssertEqual(sent, 1)
        XCTAssertEqual(server.captures.first?.captureId, id.uuidString.lowercased())
        XCTAssertEqual(server.captures.first?.meta["mime_type"] as? String, "audio/mp4")
    }

    func testTransferStartedAtRoundTripsThroughEncoding() throws {
        let entry = OutboxEntry(id: UUID(), kind: .url, payload: ["url": "x"], createdAt: Date(), attempts: 0,
                                status: .transferring, transferStartedAt: Date(timeIntervalSince1970: 1_000))
        let decoded = try JSONDecoder().decode(OutboxEntry.self, from: try JSONEncoder().encode(entry))
        XCTAssertEqual(decoded, entry)
    }
}

/// Mutable holder a `@Sendable` hook can write into.
final class SnapshotBox: @unchecked Sendable {
    var payload: [String: String]?
}

/// Mutable count holder a `@Sendable` hook can write into.
final class SnapshotCount: @unchecked Sendable {
    var value: Int?
}
