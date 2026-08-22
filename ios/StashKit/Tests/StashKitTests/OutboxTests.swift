import XCTest
@testable import StashKit

/// Actor stub that suspends send() until release() is called, then responds with noteJSON.
/// Used to test reentrancy guards.
actor SlowPoster: JSONPosting {
    private var isReleased = false
    let response = noteJSON

    func post(path: String, body: [String: Any], accessToken: String) async throws -> Data {
        while !isReleased {
            try await Task.sleep(for: .milliseconds(10))
        }
        return response
    }

    func release() {
        isReleased = true
    }
}

/// `drain`'s `upload` parameter for tests that never enqueue a `local_file_path` entry, so it's
/// never actually invoked — passed explicitly (rather than relying on the default
/// `uploadToStorageFromFile`) so none of these tests can ever reach real network/Supabase Storage
/// code by accident. `(URL, String, String)` since Task 4: `drain`'s local-file lane now streams
/// straight from disk (never `Data(contentsOf:)`s the file itself).
private let noOpUpload: @Sendable (URL, String, String) async throws -> Void = { _, _, _ in }

/// Records every `upload` call `drain` makes for a `local_file_path` entry (unlike `noOpUpload`,
/// which discards everything) so tests can assert exactly what file URL/path/content-type it
/// received. Task 4: takes the local file's `URL` directly, not a loaded `Data` blob — proving
/// `drain` never materializes the file's bytes itself is exactly the point of recording the URL.
/// `bytesAtCallTime` snapshots the file's content AT THE MOMENT of the call (by reading it here,
/// inside this already-`@unchecked Sendable` recorder, rather than via a `var` captured by the
/// `@Sendable` upload closure itself, which trips "mutation of captured var in
/// concurrently-executing code") — the local file is deleted later in the same `drain` pass, so
/// this is the only point a test can still read its bytes from disk directly.
final class UploadRecorder: @unchecked Sendable {
    private(set) var calls: [(fileURL: URL, path: String, contentType: String, bytesAtCallTime: Data?)] = []
    var shouldFail = false

    func upload(fileURL: URL, path: String, contentType: String) async throws {
        if shouldFail { throw CaptureError.badStatus(500) }
        let bytesAtCallTime = try? Data(contentsOf: fileURL)
        calls.append((fileURL: fileURL, path: path, contentType: contentType, bytesAtCallTime: bytesAtCallTime))
    }
}

/// `JSONPosting` that always throws — for testing an `addFile` call that fails AFTER a
/// `local_file_path` entry's upload already succeeded, distinct from `StubPoster` returning a
/// malformed response (that's a decode-time failure; this is the POST itself failing).
private final class ThrowingPoster: JSONPosting, @unchecked Sendable {
    func post(path: String, body: [String: Any], accessToken: String) async throws -> Data {
        throw CaptureError.badStatus(500)
    }
}

/// `JSONPosting` that snapshots whatever `OutboxEntry` is ON DISK (via a fresh `Outbox` over the
/// same directory — a distinct actor instance, so reading it never contends with `drain`'s own
/// in-flight call) at the exact instant it's invoked, then throws. This directly observes whether
/// a `local_file_path` entry's upload-succeeded transition was durably persisted BEFORE `send`
/// was ever attempted — the one thing a same-process `catch` block can't prove, since Swift's
/// `do`/`catch` share the enclosing scope's mutable `entry`, so asserting only on the FINAL state
/// after `drain` returns can't distinguish "persisted before send" from "persisted only in the
/// catch block after send failed" (both produce the same final on-disk state for an ordinary
/// in-process throw — they only differ for a real crash mid-`send`, which no unit test can
/// trigger directly).
private final class SnapshotPoster: JSONPosting, @unchecked Sendable {
    private let directory: URL
    private(set) var payloadAtCallTime: [String: String]?

    init(directory: URL) { self.directory = directory }

    func post(path: String, body: [String: Any], accessToken: String) async throws -> Data {
        payloadAtCallTime = await Outbox(directory: directory).pending().first?.payload
        throw CaptureError.badStatus(500)
    }
}

final class OutboxTests: XCTestCase {
    var dir: URL!
    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appending(path: "outbox-\(UUID().uuidString)")
    }
    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    func makeStub(responding: Data) -> StubPoster { let s = StubPoster(); s.response = responding; return s }

    func testEnqueuePersistsAcrossInstances() async throws {
        let box = Outbox(directory: dir)
        try await box.enqueue(.note, payload: ["content": "offline note", "is_public": "false"])
        let rehydrated = Outbox(directory: dir)
        let pending = await rehydrated.pending()
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending[0].payload["content"], "offline note")
    }

    func testDrainSendsAndRemoves() async throws {
        let box = Outbox(directory: dir)
        try await box.enqueue(.note, payload: ["content": "n1", "is_public": "false"])
        let api = CaptureAPI(poster: makeStub(responding: noteJSON))
        let sent = await box.drain(api: api, accessToken: "jwt", userId: UUID(), upload: noOpUpload)
        XCTAssertEqual(sent, 1)
        let after = await box.pending()
        XCTAssertTrue(after.isEmpty)
    }

    func testDrainFailureRetainsAndIncrementsAttempts() async throws {
        let box = Outbox(directory: dir)
        try await box.enqueue(.note, payload: ["content": "n1", "is_public": "false"])
        let failing = StubPoster(); failing.response = Data("{}".utf8)   // malformed → throw
        let sent = await box.drain(api: CaptureAPI(poster: failing), accessToken: "jwt", userId: UUID(), upload: noOpUpload)
        XCTAssertEqual(sent, 0)
        let after = await box.pending()
        XCTAssertEqual(after.count, 1)
        XCTAssertEqual(after[0].attempts, 1)
    }

    func testOldestFirstOrdering() async throws {
        let box = Outbox(directory: dir)
        try await box.enqueue(.note, payload: ["content": "first", "is_public": "false"])
        try await box.enqueue(.note, payload: ["content": "second", "is_public": "false"])
        let pending = await box.pending()
        XCTAssertEqual(pending.map { $0.payload["content"] }, ["first", "second"])
    }

    func testReentrantDrainNoOps() async throws {
        let box = Outbox(directory: dir)
        try await box.enqueue(.note, payload: ["content": "n1", "is_public": "false"])
        let slow = SlowPoster()
        async let first = box.drain(api: CaptureAPI(poster: slow), accessToken: "jwt", userId: UUID(), upload: noOpUpload)
        try await Task.sleep(for: .milliseconds(50))     // first drain is now suspended in send
        let second = await box.drain(api: CaptureAPI(poster: slow), accessToken: "jwt", userId: UUID(), upload: noOpUpload)
        XCTAssertEqual(second, 0)        // re-entrant call no-ops
        await slow.release()
        let sent = await first
        XCTAssertEqual(sent, 1)
        let after = await box.pending()
        XCTAssertTrue(after.isEmpty)     // exactly one send, entry removed once
    }

    func testDrainURLPayload() async throws {
        let box = Outbox(directory: dir)
        try await box.enqueue(.url, payload: ["url": "https://example.com", "content": "ctx", "is_public": "true"])
        let stub = StubPoster(); stub.response = itemJSON
        let api = CaptureAPI(poster: stub)
        let sent = await box.drain(api: api, accessToken: "jwt", userId: UUID(), upload: noOpUpload)
        XCTAssertEqual(sent, 1)
        XCTAssertEqual(stub.lastPath, "add-url")
        XCTAssertEqual(stub.lastBody["url"] as? String, "https://example.com")
        XCTAssertEqual(stub.lastBody["content"] as? String, "ctx")
        XCTAssertEqual(stub.lastBody["is_public"] as? Bool, true)
    }

    func testDrainFilePayload() async throws {
        let box = Outbox(directory: dir)
        try await box.enqueue(.file, payload: ["file_path": "u/x.png", "mime_type": "image/png", "file_size": "1234", "is_public": "false"])
        let stub = StubPoster(); stub.response = itemJSON
        let api = CaptureAPI(poster: stub)
        let sent = await box.drain(api: api, accessToken: "jwt", userId: UUID(), upload: noOpUpload)
        XCTAssertEqual(sent, 1)
        XCTAssertEqual(stub.lastPath, "add-file")
        XCTAssertEqual(stub.lastBody["file_path"] as? String, "u/x.png")
        XCTAssertEqual(stub.lastBody["file_size"] as? Int, 1234)
        XCTAssertEqual(stub.lastBody["mime_type"] as? String, "image/png")
        XCTAssertEqual(stub.lastBody["is_public"] as? Bool, false)
    }

    // Task 5: `attributes_json` — the Outbox's own text-only `[String: String]` payload can't hold
    // a nested attributes object directly, so `CaptureViewModel.enqueue` serializes the blob to a
    // JSON string under this key; `drain` must decode it back and forward it to `addFile` as a
    // real `attributes` object, exactly like the live-send path would have.
    func testFileEntryRoundTripsAttributesJSON() async throws {
        let box = Outbox(directory: dir)
        let attributes = ItemAttributes(location: CapturedLocation(label: "Testville", source: "manual"),
                                        media: MediaAttributes(durationS: 12, fileName: "clip.mp4"))
        let attributesJSON = String(data: try JSONEncoder().encode(attributes), encoding: .utf8)!
        try await box.enqueue(.file, payload: [
            "file_path": "u/x.png", "mime_type": "image/png", "file_size": "1234",
            "is_public": "false", "attributes_json": attributesJSON,
        ])
        let stub = StubPoster(); stub.response = itemJSON
        let api = CaptureAPI(poster: stub)

        let sent = await box.drain(api: api, accessToken: "jwt", userId: UUID(), upload: noOpUpload)

        XCTAssertEqual(sent, 1)
        let body = try XCTUnwrap(stub.lastBody["attributes"] as? [String: Any])
        let location = try XCTUnwrap(body["location"] as? [String: Any])
        XCTAssertEqual(location["label"] as? String, "Testville")
        let media = try XCTUnwrap(body["media"] as? [String: Any])
        XCTAssertEqual(media["file_name"] as? String, "clip.mp4")
    }

    // Cross-account capture leak (Critical, final review): `defaultDirectory()` used to be a
    // single path shared by every account that ever signed into this device, so the composer's
    // launch-time drain (which always runs under whatever session is CURRENT, not whichever
    // session queued a given entry) could silently create user A's offline-queued note/URL in
    // user B's account after an account switch. `defaultDirectory(userId:)` must resolve to a
    // distinct, deterministic path per user so two different accounts can never share an Outbox.
    func testPerUserDirectoriesAreIsolated() {
        // Real Application Support, not a tmp override — `defaultDirectory` intentionally has no
        // injection seam (it's the one place that must always agree with itself across app
        // launches), so this asserts PATH SHAPE rather than touching the filesystem: two
        // different UUIDs must yield two different paths, each under StashOutbox and suffixed
        // with that UUID lowercased.
        let uid1 = UUID()
        let uid2 = UUID()

        let dir1 = Outbox.defaultDirectory(userId: uid1)
        let dir2 = Outbox.defaultDirectory(userId: uid2)

        XCTAssertNotEqual(dir1, dir2, "two different users must resolve to two different Outbox directories")
        XCTAssertEqual(dir1.lastPathComponent, uid1.uuidString.lowercased())
        XCTAssertEqual(dir2.lastPathComponent, uid2.uuidString.lowercased())
        XCTAssertEqual(dir1.deletingLastPathComponent().lastPathComponent, "StashOutbox")
        XCTAssertEqual(dir2.deletingLastPathComponent().lastPathComponent, "StashOutbox")

        // Same user, mixed-case UUID string input elsewhere in the app (e.g. Session.user.id
        // formatting) must still resolve to the SAME directory — the path segment is always the
        // lowercased form, never whatever case the caller happened to have.
        let dir1Again = Outbox.defaultDirectory(userId: uid1)
        XCTAssertEqual(dir1, dir1Again)
    }

    // Task 2 (App Group): `defaultDirectory` now delegates to `AppGroup.userScopedURL` instead of
    // computing the Application-Support-plus-"StashOutbox" formula inline — this proves the
    // WIRING directly (distinct from `testPerUserDirectoriesAreIsolated` above, which only
    // asserts the resulting path SHAPE and would keep passing even if some future refactor
    // reimplemented the same shape without actually going through `AppGroup`).
    func testDefaultDirectoryDelegatesToAppGroupUserScopedURL() {
        let uid = UUID()
        XCTAssertEqual(Outbox.defaultDirectory(userId: uid), AppGroup.userScopedURL("StashOutbox", userId: uid))
    }

    // Behavioral companion to the path-shape assertion above: two `Outbox`es rooted at two
    // different (tmp, here — real per-user directories in the app) directories must be fully
    // isolated end-to-end — not just "different paths" but "an entry enqueued in one is never
    // visible, sendable, or drainable from the other."
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
        XCTAssertTrue(pendingB.isEmpty, "a fresh directory must never see another directory's queued entry")

        let stub = StubPoster(); stub.response = noteJSON
        let sentB = await boxB.drain(api: CaptureAPI(poster: stub), accessToken: "user-b-jwt", userId: UUID(), upload: noOpUpload)
        XCTAssertEqual(sentB, 0, "draining dirB must never send dirA's queued entry under user B's token")

        let pendingA = await boxA.pending()
        XCTAssertEqual(pendingA.count, 1, "user A's entry must survive untouched by user B's drain")
        XCTAssertEqual(pendingA[0].payload["content"], "user A's offline note")
    }

    // MARK: - Task 4: recording durability (`local_file_path` entries)
    //
    // The app's recorder (Task 6) writes audio straight to local disk via `RecordingStore` and
    // enqueues a `.file` entry carrying `local_file_path` (instead of an already-uploaded
    // `file_path`, unlike every other `.file` entry) *before* any network call ever happens — so
    // the upload itself has to happen inside `drain`, not before enqueueing like every other
    // attachment (Task 3's `CaptureViewModel.prepare`).

    func testDrainUploadsLocalFileThenRegistersItAndDeletesTheLocalCopy() async throws {
        let box = Outbox(directory: dir)
        let localFile = FileManager.default.temporaryDirectory.appending(path: "rec-\(UUID().uuidString).m4a")
        let bytes = Data([0x01, 0x02, 0x03, 0x04])
        try bytes.write(to: localFile)
        defer { try? FileManager.default.removeItem(at: localFile) }
        try await box.enqueue(.file, payload: [
            "local_file_path": localFile.path,
            "mime_type": "audio/mp4",
            "is_public": "false",
        ])

        let userId = UUID()
        let recorder = UploadRecorder()
        let stub = StubPoster(); stub.response = itemJSON
        let sent = await box.drain(api: CaptureAPI(poster: stub), accessToken: "jwt", userId: userId,
                                   upload: { fileURL, path, contentType in
                                       try await recorder.upload(fileURL: fileURL, path: path, contentType: contentType)
                                   })

        XCTAssertEqual(sent, 1)
        XCTAssertEqual(recorder.calls.count, 1, "the local file's bytes must be uploaded exactly once")
        XCTAssertEqual(recorder.calls[0].fileURL, localFile,
                       "drain must hand the upload closure the FILE URL directly — never a loaded Data blob")
        XCTAssertEqual(recorder.calls[0].bytesAtCallTime, bytes, "the file's content must still be intact at upload time")
        XCTAssertEqual(recorder.calls[0].contentType, "audio/mp4")
        let uploadedPath = recorder.calls[0].path
        XCTAssertTrue(uploadedPath.hasPrefix("\(userId.uuidString.lowercased())/"),
                      "the upload path must be scoped under the draining user's id")
        XCTAssertTrue(uploadedPath.hasSuffix(".m4a"))

        XCTAssertEqual(stub.lastPath, "add-file", "addFile must be called AFTER the upload, with the fresh path")
        XCTAssertEqual(stub.lastBody["file_path"] as? String, uploadedPath)

        XCTAssertFalse(FileManager.default.fileExists(atPath: localFile.path),
                       "the local recording is redundant once its bytes are durably uploaded")
        let after = await box.pending()
        XCTAssertTrue(after.isEmpty)
    }

    func testDrainLocalFileUploadFailureRetainsEntryAndKeepsTheLocalCopy() async throws {
        let box = Outbox(directory: dir)
        let localFile = FileManager.default.temporaryDirectory.appending(path: "rec-\(UUID().uuidString).m4a")
        try Data([0x09, 0x08]).write(to: localFile)
        defer { try? FileManager.default.removeItem(at: localFile) }
        try await box.enqueue(.file, payload: [
            "local_file_path": localFile.path,
            "mime_type": "audio/mp4",
            "is_public": "false",
        ])

        let recorder = UploadRecorder(); recorder.shouldFail = true
        let stub = StubPoster(); stub.response = itemJSON
        let sent = await box.drain(api: CaptureAPI(poster: stub), accessToken: "jwt", userId: UUID(),
                                   upload: { fileURL, path, contentType in
                                       try await recorder.upload(fileURL: fileURL, path: path, contentType: contentType)
                                   })

        XCTAssertEqual(sent, 0)
        XCTAssertNil(stub.lastPath, "addFile must never be reached when the upload itself failed")
        XCTAssertTrue(FileManager.default.fileExists(atPath: localFile.path),
                      "an upload failure must never delete the only copy of the recording")
        let after = await box.pending()
        XCTAssertEqual(after.count, 1)
        XCTAssertEqual(after[0].attempts, 1)
        XCTAssertEqual(after[0].payload["local_file_path"], localFile.path,
                       "the entry must be retried as a local-file upload again, not silently downgraded")
    }

    // Task review fix round (Critical + Important): the upload can succeed while the immediately
    // following `addFile` still fails (or the process dies before `addFile` resolves) — this
    // interleaving must persist the upload-succeeded transition to disk (`file_path` set,
    // `local_file_path` gone) BEFORE `send` is even attempted, so a crash between upload and
    // send can never leave an on-disk entry that still points at a `local_file_path` whose file
    // has already been deleted (which would hit the missing-file branch and silently drop an
    // entry whose bytes are actually safe in storage). Verified end-to-end across two SEPARATE
    // `drain` calls against a freshly rehydrated `Outbox` (same directory) — not just in-memory
    // state — because the persisted-to-disk shape is exactly what a relaunch-after-crash reads.
    func testDrainUploadSucceedsButAddFileFailsPersistsTransitionThenRetryNeverReuploads() async throws {
        let box = Outbox(directory: dir)
        let localFile = FileManager.default.temporaryDirectory.appending(path: "rec-\(UUID().uuidString).m4a")
        let bytes = Data([0x0A, 0x0B, 0x0C])
        try bytes.write(to: localFile)
        defer { try? FileManager.default.removeItem(at: localFile) }
        try await box.enqueue(.file, payload: [
            "local_file_path": localFile.path,
            "mime_type": "audio/mp4",
            "is_public": "false",
        ])

        let userId = UUID()
        let recorder = UploadRecorder()
        let uploadClosure: @Sendable (URL, String, String) async throws -> Void = { fileURL, path, contentType in
            try await recorder.upload(fileURL: fileURL, path: path, contentType: contentType)
        }

        // First drain: upload succeeds, addFile (the poster itself) throws.
        let firstSent = await box.drain(api: CaptureAPI(poster: ThrowingPoster()), accessToken: "jwt",
                                        userId: userId, upload: uploadClosure)
        XCTAssertEqual(firstSent, 0)
        XCTAssertEqual(recorder.calls.count, 1, "the upload must have gone through exactly once")
        let uploadedPath = recorder.calls[0].path

        XCTAssertFalse(FileManager.default.fileExists(atPath: localFile.path),
                       "local copy is redundant once the upload itself succeeded")

        // Re-read from disk via a FRESH Outbox instance — this is the persisted state a relaunch
        // after a crash would actually see, not in-memory state carried over within this test.
        let rehydrated = Outbox(directory: dir)
        let afterFirst = await rehydrated.pending()
        XCTAssertEqual(afterFirst.count, 1)
        XCTAssertEqual(afterFirst[0].payload["file_path"], uploadedPath,
                       "the transitioned entry must be persisted with the uploaded path")
        XCTAssertNil(afterFirst[0].payload["local_file_path"],
                     "local_file_path must be cleared on disk so a retry never re-uploads")
        XCTAssertEqual(afterFirst[0].attempts, 1)

        // Second drain, working poster this time: must send using the ALREADY-uploaded path —
        // never touching `upload` again.
        let stub = StubPoster(); stub.response = itemJSON
        let secondSent = await rehydrated.drain(api: CaptureAPI(poster: stub), accessToken: "jwt",
                                                 userId: userId, upload: uploadClosure)
        XCTAssertEqual(secondSent, 1)
        XCTAssertEqual(recorder.calls.count, 1, "a retry must never re-upload — one call across both drains")
        XCTAssertEqual(stub.lastPath, "add-file")
        XCTAssertEqual(stub.lastBody["file_path"] as? String, uploadedPath)

        let afterSecond = await rehydrated.pending()
        XCTAssertTrue(afterSecond.isEmpty)
    }

    // Direct ordering proof for the same fix (Critical, task review) — genuinely RED against the
    // pre-fix code (see task-4-report.md's fix round): observes the ON-DISK entry at the exact
    // instant `send`/`addFile` is invoked, rather than only the final state after `drain`
    // returns. The test above can't tell "persisted before send" apart from "persisted only in
    // the catch block after send failed" for an ordinary in-process throw; this one can, because
    // it inspects disk DURING the call instead of after.
    func testDrainPersistsTransitionedEntryToDiskBeforeAttemptingSend() async throws {
        let box = Outbox(directory: dir)
        let localFile = FileManager.default.temporaryDirectory.appending(path: "rec-\(UUID().uuidString).m4a")
        try Data([0x01]).write(to: localFile)
        defer { try? FileManager.default.removeItem(at: localFile) }
        try await box.enqueue(.file, payload: [
            "local_file_path": localFile.path,
            "mime_type": "audio/mp4",
            "is_public": "false",
        ])

        let recorder = UploadRecorder()
        let snapshotPoster = SnapshotPoster(directory: dir)
        _ = await box.drain(api: CaptureAPI(poster: snapshotPoster), accessToken: "jwt", userId: UUID(),
                            upload: { fileURL, path, contentType in
                                try await recorder.upload(fileURL: fileURL, path: path, contentType: contentType)
                            })

        let snapshot = try XCTUnwrap(snapshotPoster.payloadAtCallTime, "the poster must have been invoked")
        XCTAssertNotNil(snapshot["file_path"],
                        "the transitioned entry must already be durably on disk by the time addFile is attempted")
        XCTAssertNil(snapshot["local_file_path"],
                     "local_file_path must already be cleared on disk before addFile is attempted — a crash " +
                     "during the network call must never leave the on-disk entry still pointing at the " +
                     "(by-then-deleted) local file")
    }

    // Beyond the brief's Step 1 enumeration, but deliberately added (disclosed in
    // task-4-report.md): dropping an entry is a permanent, data-destroying action, so the branch
    // that does it — file referenced by `local_file_path` no longer exists on disk — gets its own
    // test rather than shipping untested.
    func testDrainMissingLocalFileDropsEntryPermanentlyWithoutUploadingOrSending() async throws {
        let box = Outbox(directory: dir)
        let goneFile = FileManager.default.temporaryDirectory.appending(path: "gone-\(UUID().uuidString).m4a")
        // Deliberately never written to disk — simulates a local recording that vanished before
        // this drain ran (e.g. the app was force-quit and its tmp/App Support state got cleared).
        try await box.enqueue(.file, payload: [
            "local_file_path": goneFile.path,
            "mime_type": "audio/mp4",
            "is_public": "false",
        ])

        let recorder = UploadRecorder()
        let stub = StubPoster(); stub.response = itemJSON
        let sent = await box.drain(api: CaptureAPI(poster: stub), accessToken: "jwt", userId: UUID(),
                                   upload: { fileURL, path, contentType in
                                       try await recorder.upload(fileURL: fileURL, path: path, contentType: contentType)
                                   })

        XCTAssertEqual(sent, 0, "a dropped entry was never delivered, so it must not count as sent")
        XCTAssertTrue(recorder.calls.isEmpty, "there are no bytes anywhere left to upload")
        XCTAssertNil(stub.lastPath, "addFile must never be called for an entry that was dropped")
        let after = await box.pending()
        XCTAssertTrue(after.isEmpty, "retrying a permanently-failed entry can never succeed, so it must not be retained")
    }

    // MARK: - Task 3: cross-process drain claims
    //
    // Plan 5 Task 5+ puts the share extension and the app in the same App-Group-backed Outbox
    // directory (`AppGroup.userScopedURL`), so `drain` must coordinate across OS PROCESSES, not
    // just within one — `isDraining` above only guards reentrancy inside a single actor instance.
    // These tests use two separate `Outbox` instances over the SAME directory to stand in for
    // "two processes/instances," and inspect the raw `<id>.claim` sidecar file on disk directly
    // (rather than only asserting through `pending()`, which deliberately never surfaces `.claim`
    // files) to prove the claim's own lifecycle, not just its externally-visible effect.

    func testClaimedEntryIsSkippedByASecondOutbox() async throws {
        let boxA = Outbox(directory: dir)
        try await boxA.enqueue(.note, payload: ["content": "n1", "is_public": "false"])
        let pendingA = await boxA.pending()
        let entryId = try XCTUnwrap(pendingA.first).id
        let claimed = await boxA.claimEntry(id: entryId)
        XCTAssertTrue(claimed, "the first claim on a never-claimed entry must succeed")

        let boxB = Outbox(directory: dir)
        let stub = StubPoster(); stub.response = noteJSON
        let sent = await boxB.drain(api: CaptureAPI(poster: stub), accessToken: "jwt", userId: UUID(), upload: noOpUpload)

        XCTAssertEqual(sent, 0, "an entry already claimed by another process must be skipped, not sent")
        let pending = await boxB.pending()
        XCTAssertEqual(pending.count, 1, "the claimed entry itself must survive untouched")
        let claimURL = dir.appending(path: "\(entryId.uuidString).claim")
        XCTAssertTrue(FileManager.default.fileExists(atPath: claimURL.path),
                      "a second process's drain must never remove a live claim it doesn't own")
    }

    func testStaleClaimIsReclaimed() async throws {
        let stalePast = Date().addingTimeInterval(-700)   // > the 600s staleClaimInterval
        let crashedBox = Outbox(directory: dir, now: { stalePast })
        try await crashedBox.enqueue(.note, payload: ["content": "n1", "is_public": "false"])
        let pendingCrashed = await crashedBox.pending()
        let entryId = try XCTUnwrap(pendingCrashed.first).id
        let claimed = await crashedBox.claimEntry(id: entryId)
        XCTAssertTrue(claimed)

        let box = Outbox(directory: dir)   // real clock — reclaims the stale claim above
        let stub = StubPoster(); stub.response = noteJSON
        let sent = await box.drain(api: CaptureAPI(poster: stub), accessToken: "jwt", userId: UUID(), upload: noOpUpload)

        XCTAssertEqual(sent, 1, "a claim older than staleClaimInterval must be reclaimed and the entry sent")
        let pending = await box.pending()
        XCTAssertTrue(pending.isEmpty)
        let claimURL = dir.appending(path: "\(entryId.uuidString).claim")
        XCTAssertFalse(FileManager.default.fileExists(atPath: claimURL.path),
                       "the reclaimed-then-sent entry's claim must be removed along with the entry itself")
    }

    func testFailedSendReleasesClaim() async throws {
        let box = Outbox(directory: dir)
        try await box.enqueue(.note, payload: ["content": "n1", "is_public": "false"])
        let pendingBefore = await box.pending()
        let entryId = try XCTUnwrap(pendingBefore.first).id
        let failing = StubPoster(); failing.response = Data("{}".utf8)   // malformed → throw
        let sent = await box.drain(api: CaptureAPI(poster: failing), accessToken: "jwt", userId: UUID(), upload: noOpUpload)

        XCTAssertEqual(sent, 0)
        let after = await box.pending()
        XCTAssertEqual(after.count, 1)
        XCTAssertEqual(after[0].attempts, 1, "attempts must still increment on a failed send even though the claim is released")
        let claimURL = dir.appending(path: "\(entryId.uuidString).claim")
        XCTAssertFalse(FileManager.default.fileExists(atPath: claimURL.path),
                       "a failed send must release its claim so a retry — by this process or another — can pick the entry up")
    }
}
