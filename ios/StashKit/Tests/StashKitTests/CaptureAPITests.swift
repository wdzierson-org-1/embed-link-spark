import XCTest
@testable import StashKit

/// `captureErrorForFailedResponse` — the body-shape mapping every `capture` failure goes through.
/// (The legacy `add-*` client and its tests are gone: plan 15 Task 6A retired their last caller.)
final class CaptureAPITests: XCTestCase {

    // MARK: - Plan 14 T3: 403 subscription_required detection

    func testCaptureErrorForFailedResponseDetectsSubscriptionRequired() {
        let body = Data(#"{"error":"subscription_required"}"#.utf8)
        XCTAssertEqual(captureErrorForFailedResponse(status: 403, body: body), .subscriptionRequired)
    }

    func testCaptureErrorForFailedResponseOtherThreeOhThreeBodyIsOrdinaryBadStatus() {
        // A 403 with a DIFFERENT body (e.g. an unrelated auth failure) must not be mistaken for
        // the subscription gate — only the exact documented shape parks an Outbox entry.
        let body = Data(#"{"error":"forbidden"}"#.utf8)
        XCTAssertEqual(captureErrorForFailedResponse(status: 403, body: body), .badStatus(403))
    }

    func testCaptureErrorForFailedResponseNonThreeOhThreeStatusIsOrdinaryBadStatus() {
        let body = Data(#"{"error":"subscription_required"}"#.utf8)
        XCTAssertEqual(captureErrorForFailedResponse(status: 500, body: body), .badStatus(500))
    }

    func testCaptureErrorForFailedResponseUnparseableBodyIsOrdinaryBadStatus() {
        XCTAssertEqual(captureErrorForFailedResponse(status: 403, body: Data("not json".utf8)), .badStatus(403))
    }

    // MARK: - Plan 15: 409 / 413 mapping

    func testCaptureErrorForFailedResponseMapsCaptureInProgress() {
        XCTAssertEqual(captureErrorForFailedResponse(status: 409, body: Data(captureInProgressBody.utf8)), .inProgress)
        XCTAssertEqual(captureErrorForFailedResponse(status: 409, body: Data(#"{"error":"other"}"#.utf8)), .badStatus(409),
                       "only the documented 409 body means another attempt is in flight")
    }

    /// Only `file_too_large` means "send it two-step"; `meta_too_large` (a huge note) can't be
    /// fixed by switching lanes, so it's an ordinary failed attempt — as is a gateway's own 413.
    func testOnlyFileTooLargeRoutesToTheTwoStepLane() {
        XCTAssertEqual(captureErrorForFailedResponse(status: 413, body: Data(#"{"error":"file_too_large","max_bytes":47185920}"#.utf8)),
                       .fileTooLarge)
        XCTAssertEqual(captureErrorForFailedResponse(status: 413, body: Data(#"{"error":"meta_too_large","max_bytes":1048576}"#.utf8)),
                       .badStatus(413))
        XCTAssertEqual(captureErrorForFailedResponse(status: 413, body: Data("<html>gateway</html>".utf8)), .badStatus(413))
    }
}

/// Plan 15: `CaptureAPI.submit` + `CaptureTransport` — request shapes for the idempotent `capture`
/// endpoint, the streamed multipart body, the storage lane, and response mapping.
final class CaptureTransportTests: XCTestCase {
    var dir: URL!
    let userId = UUID(uuidString: "6B1E0A4E-9F6A-4D5E-8F2F-0E7C1B2D3A4B")!

    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appending(path: "capture-transport-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    private func entry(_ kind: OutboxEntry.Kind, _ payload: [String: String], attempts: Int = 0) -> OutboxEntry {
        OutboxEntry(id: UUID(), kind: kind, payload: payload, createdAt: Date(), attempts: attempts)
    }

    private func localFile(_ bytes: Data, ext: String = "bin") throws -> URL {
        let url = dir.appending(path: "local-\(UUID().uuidString).\(ext)")
        try bytes.write(to: url)
        return url
    }

    // MARK: JSON requests

    func testSubmitNoteSendsJSONMetaKeyedByLowercasedEntryId() async throws {
        let server = FakeCaptureServer()
        let api = CaptureAPI(transport: server)
        let note = entry(.note, ["content": "hello", "is_public": "false", "title": "T"])

        let result = try await api.submit(entry: note, userId: userId, accessToken: "jwt")

        XCTAssertEqual(server.calls.count, 1)
        let call = server.calls[0]
        XCTAssertEqual(call.request.httpMethod, "POST")
        XCTAssertEqual(call.url.absoluteString, "https://uqqsgmwkvslaomzxptnp.supabase.co/functions/v1/capture")
        XCTAssertEqual(call.header("Authorization"), "Bearer jwt")
        XCTAssertEqual(call.header("apikey"), StashConfig.supabaseAnonKey)
        XCTAssertEqual(call.header("Content-Type"), "application/json")
        XCTAssertEqual(call.captureId, note.id.uuidString.lowercased(), "the Outbox entry id IS the idempotency key")
        XCTAssertEqual(call.kind, "note")
        XCTAssertEqual(call.meta["content"] as? String, "hello")
        XCTAssertEqual(call.meta["title"] as? String, "T")
        XCTAssertEqual(call.meta["is_public"] as? Bool, false)
        XCTAssertNil(call.meta["attributes"], "no attributes_json → no attributes key (never `{}`)")
        XCTAssertEqual(result.item?.type, .text)
        XCTAssertFalse(result.duplicate)
    }

    func testSubmitURLForwardsContentAndAttributesVerbatim() async throws {
        let server = FakeCaptureServer()
        // A nested key no typed model knows must survive — the attributes string is forwarded as-is.
        let attributesJSON = #"{"location":{"label":"Testville","source":"manual","future_key":1},"custom":{"x":[1,2]}}"#
        let link = entry(.url, ["url": "https://example.com/a", "content": "", "is_public": "true",
                                "attributes_json": attributesJSON])

        _ = try await CaptureAPI(transport: server).submit(entry: link, userId: userId, accessToken: "jwt")

        let call = try XCTUnwrap(server.captures.first)
        XCTAssertEqual(call.kind, "url")
        XCTAssertEqual(call.meta["url"] as? String, "https://example.com/a")
        XCTAssertEqual(call.meta["content"] as? String, "", "links always carry content, even empty (add-url parity)")
        XCTAssertEqual(call.meta["is_public"] as? Bool, true)
        let location = try XCTUnwrap(call.attributes?["location"] as? [String: Any])
        XCTAssertEqual(location["future_key"] as? Int, 1)
        XCTAssertEqual((call.attributes?["custom"] as? [String: Any])?["x"] as? [Int], [1, 2])
    }

    func testSubmitAlreadyUploadedFileSendsJSONInFilePathMode() async throws {
        let server = FakeCaptureServer()
        let path = "\(userId.uuidString.lowercased())/abc.pdf"
        let file = entry(.file, ["file_path": path, "mime_type": "application/pdf", "file_size": "1234",
                                 "is_public": "false", "file_name": "Report.pdf", "content": ""])

        let result = try await CaptureAPI(transport: server).submit(entry: file, userId: userId, accessToken: "jwt")

        let call = try XCTUnwrap(server.captures.first)
        XCTAssertFalse(call.isMultipart)
        XCTAssertEqual(call.kind, "file")
        XCTAssertEqual(call.meta["file_path"] as? String, path)
        XCTAssertEqual(call.meta["mime_type"] as? String, "application/pdf")
        XCTAssertEqual(call.meta["file_size"] as? Int, 1234)
        XCTAssertEqual(call.meta["file_name"] as? String, "Report.pdf")
        XCTAssertNil(call.meta["content"], "files only carry a non-empty content (add-file parity)")
        XCTAssertEqual(result.item?.type, .document)
    }

    func testSubmitRejectsAFilePathOutsideTheUsersFolderWithoutANetworkCall() async {
        let server = FakeCaptureServer()
        let file = entry(.file, ["file_path": "someone-else/abc.png", "mime_type": "image/png", "is_public": "false"])
        do {
            _ = try await CaptureAPI(transport: server).submit(entry: file, userId: userId, accessToken: "jwt")
            XCTFail("expected invalidEntry")
        } catch {
            guard case CaptureError.invalidEntry = error else { return XCTFail("unexpected \(error)") }
        }
        XCTAssertTrue(server.calls.isEmpty)
    }

    // MARK: Multipart (one-shot)

    /// The multipart body, byte for byte — including file bytes that contain CR/LF and a fake
    /// boundary-looking run, which must pass through untouched.
    func testOneShotMultipartBodyIsExactlyFramed() async throws {
        let server = FakeCaptureServer()
        let fileBytes = Data([0x00, 0x01, 0xFF, 0x0D, 0x0A]) + Data("--not-a-boundary\r\n".utf8) + Data([0xFE])
        let local = try localFile(fileBytes, ext: "m4a")
        let recording = entry(.file, ["local_file_path": local.path, "mime_type": "audio/mp4", "is_public": "false"])

        _ = try await CaptureAPI(transport: server).submit(entry: recording, userId: userId, accessToken: "jwt")

        let call = try XCTUnwrap(server.captures.first)
        let boundary = try XCTUnwrap(call.boundary)
        XCTAssertEqual(call.header("Content-Type"), "multipart/form-data; boundary=\(boundary)")
        let captureId = recording.id.uuidString.lowercased()
        let meta = try CaptureTransport.metaJSONData(for: recording, fileSize: fileBytes.count)
        var expected = Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"meta\"\r\n\r\n".utf8)
        expected += meta
        expected += Data(("\r\n--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; "
            + "filename=\"\(captureId).m4a\"\r\nContent-Type: audio/mp4\r\n\r\n").utf8)
        expected += fileBytes
        expected += Data("\r\n--\(boundary)--\r\n".utf8)
        XCTAssertEqual(call.body, expected, "multipart framing must match byte for byte")

        XCTAssertEqual(call.meta["file_size"] as? Int, fileBytes.count, "file_size comes from the local file when the payload has none")
        XCTAssertEqual(call.filePart?.data, fileBytes)
        XCTAssertEqual(call.filePart?.contentType, "audio/mp4")
    }

    /// The body is assembled by chunked copy: a tiny chunk size must still reproduce the file exactly.
    func testMultipartBodyStreamsTheFileInChunks() throws {
        var bytes = Data(count: 10_007)
        for index in bytes.indices { bytes[index] = UInt8(truncatingIfNeeded: index &* 31) }
        let local = try localFile(bytes)
        let file = entry(.file, ["local_file_path": local.path, "mime_type": "application/octet-stream", "is_public": "false"])

        let prepared = try CaptureTransport.captureRequest(for: file, accessToken: "jwt", bodyDirectory: dir, chunkSize: 7)

        XCTAssertEqual(prepared.bodyKind, .multipart)
        let body = try Data(contentsOf: prepared.bodyFile)
        let boundary = try XCTUnwrap(TransportCall(request: prepared.urlRequest, body: body).boundary)
        let filePart = try XCTUnwrap(parseMultipart(body, boundary: boundary).first { $0.name == "file" })
        XCTAssertEqual(filePart.data, bytes)
        XCTAssertEqual(prepared.urlRequest.timeoutInterval, 60)
    }

    func testSubmitDeletesItsScratchBodyFile() async throws {
        let server = FakeCaptureServer()
        let note = entry(.note, ["content": "x", "is_public": "false"])
        _ = try await CaptureAPI(transport: server).submit(entry: note, userId: userId, accessToken: "jwt")

        let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: CaptureAPI.foregroundBodyDirectory.path)) ?? []
        XCTAssertFalse(leftovers.contains { $0.hasPrefix(note.id.uuidString.lowercased()) },
                       "a foreground request's body file must be removed once the request finishes")
    }

    func testFileEntryWithNeitherPathIsInvalid() {
        let broken = entry(.file, ["mime_type": "image/png", "is_public": "false"])
        XCTAssertThrowsError(try CaptureTransport.captureRequest(for: broken, accessToken: "jwt", bodyDirectory: dir)) { error in
            guard case CaptureError.invalidEntry = error else { return XCTFail("unexpected \(error)") }
        }
    }

    // MARK: Routing

    func testRequiresTwoStepRouting() throws {
        let small = try localFile(Data(count: 10))
        let smallFile = entry(.file, ["local_file_path": small.path, "mime_type": "image/jpeg"])
        XCTAssertFalse(CaptureTransport.requiresTwoStep(smallFile), "≤ 10 MiB → one multipart request")
        XCTAssertTrue(CaptureTransport.requiresTwoStep(smallFile, oneShotLimit: 9), "over the limit → two-step")
        XCTAssertFalse(CaptureTransport.requiresTwoStep(smallFile, oneShotLimit: 10), "the limit is inclusive")
        XCTAssertTrue(CaptureTransport.requiresTwoStep(entry(.file, smallFile.payload, attempts: CaptureAPI.oneShotMaxAttempts)),
                      "repeated one-shot failures fall back to the storage lane")
        XCTAssertFalse(CaptureTransport.requiresTwoStep(entry(.file, ["file_path": "u/x.png", "mime_type": "image/png"])),
                       "already in Storage → nothing to upload")
        XCTAssertFalse(CaptureTransport.requiresTwoStep(entry(.note, ["content": "x"])))
    }

    /// The production limit (coordinator decision): 10 MiB, well under the endpoint's own 45 MiB —
    /// checked at the real boundary with sparse files (no 10 MiB of actual writes).
    func testDefaultOneShotLimitIsTenMiB() throws {
        XCTAssertEqual(CaptureAPI.oneShotFileLimit, 10 * 1024 * 1024)
        XCTAssertEqual(CaptureAPI().oneShotLimit, CaptureAPI.oneShotFileLimit)
        func sparseFile(size: UInt64) throws -> URL {
            let url = dir.appending(path: "sparse-\(UUID().uuidString).mov")
            FileManager.default.createFile(atPath: url.path, contents: nil)
            let handle = try FileHandle(forWritingTo: url)
            try handle.truncate(atOffset: size)
            try handle.close()
            return url
        }
        let limit = UInt64(CaptureAPI.oneShotFileLimit)
        let atLimit = entry(.file, ["local_file_path": try sparseFile(size: limit).path, "mime_type": "video/quicktime"])
        let overLimit = entry(.file, ["local_file_path": try sparseFile(size: limit + 1).path, "mime_type": "video/quicktime"])
        XCTAssertFalse(CaptureTransport.requiresTwoStep(atLimit), "exactly 10 MiB still goes one-shot")
        XCTAssertTrue(CaptureTransport.requiresTwoStep(overLimit), "one byte over goes two-step")
    }

    // MARK: Storage lane

    func testStorageUploadIsDeterministicAndUpserts() throws {
        let local = try localFile(Data([0x01]), ext: "MOV")
        let movie = entry(.file, ["local_file_path": local.path, "mime_type": "video/quicktime"])

        let upload = try CaptureTransport.storageUpload(for: movie, userId: userId, accessToken: "jwt")

        let expectedPath = "\(userId.uuidString.lowercased())/\(movie.id.uuidString.lowercased()).mov"
        XCTAssertEqual(upload.path, expectedPath, "<uid>/<entryId>.<ext>, all lowercase")
        XCTAssertEqual(upload.fileURL, local, "the body is the local file itself — never a copy in memory")
        XCTAssertEqual(upload.request.url?.absoluteString,
                       "https://uqqsgmwkvslaomzxptnp.supabase.co/storage/v1/object/stash-media/\(expectedPath)")
        XCTAssertEqual(upload.request.httpMethod, "POST")
        XCTAssertEqual(upload.request.value(forHTTPHeaderField: "x-upsert"), "true")
        XCTAssertEqual(upload.request.value(forHTTPHeaderField: "Content-Type"), "video/quicktime")
        XCTAssertEqual(upload.request.value(forHTTPHeaderField: "Authorization"), "Bearer jwt")
        XCTAssertEqual(upload.request.value(forHTTPHeaderField: "apikey"), StashConfig.supabaseAnonKey)
        XCTAssertEqual(try CaptureTransport.storageUpload(for: movie, userId: userId, accessToken: "jwt").path, expectedPath,
                       "the same entry always maps to the same object")
    }

    /// Parity with the server's `fileExtensionFor` — these are its vitest cases
    /// (supabase/functions/_shared/capture.test.ts), verbatim — so an entry's object has ONE name
    /// whichever lane stored it.
    func testFileExtensionMatchesTheServersFileExtensionFor() {
        let ext = CaptureTransport.fileExtension(fileName:mimeType:)
        // prefers a sane extension from the file name, lowercased
        XCTAssertEqual(ext("Photo.JPG", "image/png"), "jpg")
        XCTAssertEqual(ext("IMG_0001.HEIC", nil), "heic")
        XCTAssertEqual(ext("archive.tar.gz", "application/gzip"), "gz")
        XCTAssertEqual(ext("folder/sub/report.pdf", nil), "pdf")
        // falls back to the MIME map when the name has no usable extension
        XCTAssertEqual(ext("noext", "image/png"), "png")
        XCTAssertEqual(ext(".hidden", "image/png"), "png")
        XCTAssertEqual(ext("trailingdot.", "application/pdf"), "pdf")
        XCTAssertEqual(ext("weird.ex-t", "audio/x-m4a"), "m4a")
        XCTAssertEqual(ext("long.abcdefghijk", "video/quicktime"), "mov")
        XCTAssertEqual(ext(nil, "IMAGE/JPEG; q=1"), "jpg")
        XCTAssertEqual(ext(nil, "application/vnd.openxmlformats-officedocument.wordprocessingml.document"), "docx")
        // ends at bin when nothing is known
        XCTAssertEqual(ext(nil, nil), "bin")
        XCTAssertEqual(ext("", "application/x-unknown"), "bin")
    }

    /// The entry-level wrapper uses `file_name` + `mime_type` only — never the local file's own
    /// extension, which the server can't see (any extra tier could only make the lanes disagree).
    func testStorageExtensionIgnoresTheLocalFilesOwnExtension() {
        let named = entry(.file, ["local_file_path": "/tmp/staged.jpg", "file_name": "IMG_0042.JPEG", "mime_type": "image/jpeg"])
        XCTAssertEqual(CaptureTransport.storageFileExtension(for: named), "jpeg")
        let recording = entry(.file, ["local_file_path": "/tmp/rec.caf", "mime_type": "audio/mp4"])
        XCTAssertEqual(CaptureTransport.storageFileExtension(for: recording), "m4a")
        let unmapped = entry(.file, ["local_file_path": "/tmp/design.sketch", "mime_type": "application/x-sketch"])
        XCTAssertEqual(CaptureTransport.storageFileExtension(for: unmapped), "bin", "exactly what the server would name it")
    }

    func testAnEmptyAttributesObjectIsNeverSent() {
        let note = entry(.note, ["content": "x", "attributes_json": "{}"])
        XCTAssertNil(CaptureTransport.meta(for: note, fileSize: nil)["attributes"], "never send `{}`")
    }

    func testUploadFileToStorageMapsNon2xxToBadStatus() async throws {
        let server = FakeCaptureServer()
        server.storageBehaviors = [.respond(400, #"{"error":"Duplicate"}"#)]
        let local = try localFile(Data([0x01]))
        do {
            try await CaptureAPI(transport: server).uploadFileToStorage(local, path: "u/x.bin", contentType: "a/b", accessToken: "jwt")
            XCTFail("expected badStatus")
        } catch {
            XCTAssertEqual(error as? CaptureError, .badStatus(400))
        }
    }

    // MARK: Responses

    func testResultMapping() throws {
        let row = FakeCaptureServer.row(kind: "note", meta: ["content": "x"])
        let fresh = try JSONSerialization.data(withJSONObject: ["item": row, "duplicate": false])
        XCTAssertNotNil(try CaptureTransport.result(status: 200, body: fresh).item)

        let deleted = Data(#"{"item":null,"duplicate":true}"#.utf8)
        XCTAssertEqual(try CaptureTransport.result(status: 200, body: deleted), CaptureResult(item: nil, duplicate: true),
                       "a replay of a capture whose row the user since deleted is still a success")

        let odd = Data(#"{"item":{"id":"not-a-uuid"},"duplicate":false}"#.utf8)
        XCTAssertEqual(try CaptureTransport.result(status: 200, body: odd), CaptureResult(item: nil, duplicate: false),
                       "an undecodable row must not turn a landed capture into an endless retry")

        XCTAssertThrowsError(try CaptureTransport.result(status: 200, body: Data("<html>".utf8))) {
            XCTAssertEqual($0 as? CaptureError, .malformedResponse)
        }
        XCTAssertThrowsError(try CaptureTransport.result(status: 403, body: Data(subscriptionRequiredBody.utf8))) {
            XCTAssertEqual($0 as? CaptureError, .subscriptionRequired)
        }
        XCTAssertThrowsError(try CaptureTransport.result(status: 409, body: Data(captureInProgressBody.utf8))) {
            XCTAssertEqual($0 as? CaptureError, .inProgress)
        }
        XCTAssertThrowsError(try CaptureTransport.result(status: 502, body: Data())) {
            XCTAssertEqual($0 as? CaptureError, .badStatus(502))
        }
    }
}
