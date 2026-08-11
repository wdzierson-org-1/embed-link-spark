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
}
