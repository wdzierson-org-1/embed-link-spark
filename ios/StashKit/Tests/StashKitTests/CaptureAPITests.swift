import XCTest
@testable import StashKit

/// Stub for testing JSON posting without network access. Reused by Task 3 tests.
internal final class StubPoster: JSONPosting, @unchecked Sendable {
    var lastPath: String?
    var lastBody: [String: Any] = [:]
    var response: Data = Data()
    func post(path: String, body: [String: Any], accessToken: String) async throws -> Data {
        lastPath = path; lastBody = body; return response
    }
}

/// Shared test fixtures for capture endpoints. Reused by Task 3 tests.
internal let itemJSON = """
{"success":true,"item":{"id":"6b1e0a4e-9f6a-4d5e-8f2f-0e7c1b2d3a4b","type":"image",
 "title":"t","content":null,"url":null,"file_path":"u/x.png","description":null,
 "summary":null,"created_at":"2026-08-11T10:00:00+00:00","mime_type":"image/png",
 "is_public":false,"supplemental_note":null}}
""".data(using: .utf8)!
internal let noteJSON = """
{"success":true,"note":{"id":"6b1e0a4e-9f6a-4d5e-8f2f-0e7c1b2d3a4c","type":"text",
 "title":"hello","content":"hello world","url":null,"file_path":null,"description":null,
 "summary":null,"created_at":"2026-08-11T10:00:00+00:00","mime_type":null,
 "is_public":false,"supplemental_note":null}}
""".data(using: .utf8)!

final class CaptureAPITests: XCTestCase {

    func testAddNoteEnvelopeAndPayload() async throws {
        let stub = StubPoster(); stub.response = noteJSON
        let api = CaptureAPI(poster: stub)
        let item = try await api.addNote(content: "hello world", title: nil, isPublic: false, accessToken: "jwt")
        XCTAssertEqual(stub.lastPath, "add-note")
        XCTAssertEqual(stub.lastBody["content"] as? String, "hello world")
        XCTAssertNil(stub.lastBody["title"])
        XCTAssertEqual(item.type, .text)
        XCTAssertEqual(item.title, "hello")
    }

    func testAddURLPayload() async throws {
        let stub = StubPoster(); stub.response = itemJSON
        let api = CaptureAPI(poster: stub)
        _ = try await api.addURL("https://example.com", note: "ctx", isPublic: true, accessToken: "jwt")
        XCTAssertEqual(stub.lastPath, "add-url")
        XCTAssertEqual(stub.lastBody["url"] as? String, "https://example.com")
        XCTAssertEqual(stub.lastBody["content"] as? String, "ctx")
        XCTAssertEqual(stub.lastBody["is_public"] as? Bool, true)
    }

    func testAddFilePayloadAndDecode() async throws {
        let stub = StubPoster(); stub.response = itemJSON
        let api = CaptureAPI(poster: stub)
        let item = try await api.addFile(path: "u/x.png", mimeType: "image/png", fileSize: 12,
                                         content: nil, isPublic: false, accessToken: "jwt")
        XCTAssertEqual(stub.lastPath, "add-file")
        XCTAssertEqual(stub.lastBody["file_path"] as? String, "u/x.png")
        XCTAssertEqual(item.type, .image)
    }

    // Task 5: `attributes` threading — `body["attributes"]` must appear ONLY when there's a
    // non-empty blob to send, never as an empty object (Task 3's whole-blob-PATCH-replace
    // contract: an empty object would wipe attributes the row already has).
    func testAddFileEncodesAttributes() async throws {
        let stub = StubPoster(); stub.response = itemJSON
        let api = CaptureAPI(poster: stub)

        _ = try await api.addFile(path: "u/x.png", mimeType: "image/png", fileSize: 12,
                                  content: nil, isPublic: false, accessToken: "jwt")
        XCTAssertNil(stub.lastBody["attributes"], "no attributes argument -> body must not carry the key")

        _ = try await api.addFile(path: "u/x.png", mimeType: "image/png", fileSize: 12,
                                  content: nil, isPublic: false, attributes: ItemAttributes(),
                                  accessToken: "jwt")
        XCTAssertNil(stub.lastBody["attributes"], "an .isEmpty ItemAttributes must not attach an empty object")

        let attrs = ItemAttributes(location: CapturedLocation(label: "Testville", source: "manual"),
                                   media: MediaAttributes(durationS: 12, fileName: "clip.mp4"))
        _ = try await api.addFile(path: "u/x.png", mimeType: "image/png", fileSize: 12,
                                  content: nil, isPublic: false, attributes: attrs, accessToken: "jwt")
        let body = try XCTUnwrap(stub.lastBody["attributes"] as? [String: Any])
        let location = try XCTUnwrap(body["location"] as? [String: Any])
        XCTAssertEqual(location["label"] as? String, "Testville")
        let media = try XCTUnwrap(body["media"] as? [String: Any])
        XCTAssertEqual(media["file_name"] as? String, "clip.mp4")
        XCTAssertEqual(media["duration_s"] as? Double, 12)
    }

    func testMalformedResponseThrows() async {
        let stub = StubPoster(); stub.response = Data("{}".utf8)
        let api = CaptureAPI(poster: stub)
        do { _ = try await api.addNote(content: "x", title: nil, isPublic: false, accessToken: "jwt"); XCTFail() }
        catch { XCTAssertEqual(error as? CaptureError, .malformedResponse) }
    }

    func testUploadPathShape() {
        let uid = UUID(uuidString: "6B1E0A4E-9F6A-4D5E-8F2F-0E7C1B2D3A4B")!
        let path = makeUploadPath(userId: uid, fileExtension: "PNG")
        XCTAssertTrue(path.hasPrefix("6b1e0a4e-9f6a-4d5e-8f2f-0e7c1b2d3a4b/"))
        XCTAssertTrue(path.hasSuffix(".png"))
        XCTAssertEqual(path.split(separator: "/").count, 2)
        XCTAssertNil(path.rangeOfCharacter(from: CharacterSet.uppercaseLetters))
    }

    func testInnerItemDecodeFailureMapsToMalformedResponse() async {
        let stub = StubPoster()
        stub.response = Data(#"{"success":true,"item":{"id":"not-a-uuid"}}"#.utf8)
        let api = CaptureAPI(poster: stub)
        do { _ = try await api.addFile(path: "u/x.png", mimeType: "image/png", fileSize: nil, content: nil, isPublic: false, accessToken: "jwt"); XCTFail() }
        catch { XCTAssertEqual(error as? CaptureError, .malformedResponse) }
    }
}
