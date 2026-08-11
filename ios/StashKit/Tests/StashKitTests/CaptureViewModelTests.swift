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

        XCTAssertEqual(outcome, .saved(count: 1))
        XCTAssertEqual(poster.calls.map(\.path), ["add-url"])
        XCTAssertEqual(poster.calls[0].body["url"] as? String, "https://example.com")
        XCTAssertEqual(poster.calls[0].body["content"] as? String, "check this out cool")
    }

    func testPlainTextRoutesToAddNote() async {
        let poster = RecordingPoster()
        let vm = makeViewModel(poster: poster)
        vm.text = "buy milk"

        let outcome = await vm.submit()

        XCTAssertEqual(outcome, .saved(count: 1))
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

        XCTAssertEqual(outcome, .saved(count: 1))
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

        XCTAssertEqual(outcome, .saved(count: 4))
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

        XCTAssertEqual(outcome, .queued(count: 1))
        let box = Outbox(directory: dir)
        let pending = await box.pending()
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending[0].payload["content"], "offline note")
    }
}
