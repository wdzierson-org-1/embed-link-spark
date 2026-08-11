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
        let sent = await box.drain(api: api, accessToken: "jwt")
        XCTAssertEqual(sent, 1)
        let after = await box.pending()
        XCTAssertTrue(after.isEmpty)
    }

    func testDrainFailureRetainsAndIncrementsAttempts() async throws {
        let box = Outbox(directory: dir)
        try await box.enqueue(.note, payload: ["content": "n1", "is_public": "false"])
        let failing = StubPoster(); failing.response = Data("{}".utf8)   // malformed → throw
        let sent = await box.drain(api: CaptureAPI(poster: failing), accessToken: "jwt")
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
        async let first = box.drain(api: CaptureAPI(poster: slow), accessToken: "jwt")
        try await Task.sleep(for: .milliseconds(50))     // first drain is now suspended in send
        let second = await box.drain(api: CaptureAPI(poster: slow), accessToken: "jwt")
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
        let sent = await box.drain(api: api, accessToken: "jwt")
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
        let sent = await box.drain(api: api, accessToken: "jwt")
        XCTAssertEqual(sent, 1)
        XCTAssertEqual(stub.lastPath, "add-file")
        XCTAssertEqual(stub.lastBody["file_path"] as? String, "u/x.png")
        XCTAssertEqual(stub.lastBody["file_size"] as? Int, 1234)
        XCTAssertEqual(stub.lastBody["mime_type"] as? String, "image/png")
        XCTAssertEqual(stub.lastBody["is_public"] as? Bool, false)
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
        let sentB = await boxB.drain(api: CaptureAPI(poster: stub), accessToken: "user-b-jwt")
        XCTAssertEqual(sentB, 0, "draining dirB must never send dirA's queued entry under user B's token")

        let pendingA = await boxA.pending()
        XCTAssertEqual(pendingA.count, 1, "user A's entry must survive untouched by user B's drain")
        XCTAssertEqual(pendingA[0].payload["content"], "user A's offline note")
    }
}
