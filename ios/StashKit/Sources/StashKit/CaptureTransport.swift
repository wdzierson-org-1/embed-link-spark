import Foundation

public extension Notification.Name {
    /// Plan 15: posted (on the main actor) every time a capture reaches the server — a composer
    /// save, a voice note, an Outbox drain, or a background transfer completion handled in-app.
    /// `userInfo["item"]` is the created (or, for an idempotent replay, the already-existing)
    /// `Item`; `userInfo["duplicate"]` is a `Bool` (`true` when the server recognized the capture id
    /// from an earlier attempt and created nothing new). Observers upsert by `item.id`.
    static let stashItemCaptured = Notification.Name("it.gostash.stash.itemCaptured")
}

/// Posts `.stashItemCaptured` on the main actor (observers are UI state). Public so the
/// background-transfer completion handler (plan 15 Task 4) posts exactly the same shape.
public func postStashItemCaptured(_ item: Item, duplicate: Bool) async {
    await MainActor.run {
        NotificationCenter.default.post(name: .stashItemCaptured, object: nil,
                                        userInfo: ["item": item, "duplicate": duplicate])
    }
}

/// What the `capture` endpoint answered for one accepted capture: `200 { item, duplicate }`.
/// `item` is `nil` when the server recognized the capture id (`duplicate: true`) but the user has
/// since deleted the row, or when a 2xx row didn't decode — either way the capture itself is done
/// server-side and must never be resent.
public struct CaptureResult: Sendable, Equatable {
    public var item: Item?
    public var duplicate: Bool

    public init(item: Item?, duplicate: Bool) {
        self.item = item
        self.duplicate = duplicate
    }
}

/// The one network seam every capture request goes through (plan 15): executes a request whose
/// body is already on disk and hands back the raw status + body. Upload-from-file is the only
/// shape a background `URLSession` supports, so foreground sends use it too — one request shape
/// for both. Tests inject a stub; production uses `URLSessionCaptureTransport`.
public protocol CaptureTransporting: Sendable {
    func upload(_ request: URLRequest, fromFile bodyFile: URL) async throws -> (status: Int, body: Data)
}

/// Production transport: `URLSession.upload(for:fromFile:)` streams the body straight off disk.
public struct URLSessionCaptureTransport: CaptureTransporting {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func upload(_ request: URLRequest, fromFile bodyFile: URL) async throws -> (status: Int, body: Data) {
        let (data, response) = try await session.upload(for: request, fromFile: bodyFile)
        guard let http = response as? HTTPURLResponse else { throw CaptureError.badStatus(-1) }
        return (http.statusCode, data)
    }
}

/// Plan 15: builds every request the idempotent `capture` endpoint (and the two-step storage lane)
/// needs for one `OutboxEntry`, and interprets the answers. Pure request/response logic — no
/// Outbox state, no network — so the SAME builders serve the foreground send
/// (`CaptureAPI.submit`) and the share extension's background `URLSession` tasks (Task 4).
///
/// Wire contract (docs/PLATFORM_API.md `capture`): `POST /functions/v1/capture` with the user JWT
/// + anon key. The body is either the JSON `meta` object, or `multipart/form-data` with a `meta`
/// part (the JSON string) and a `file` part (the bytes). `meta.capture_id` is the Outbox entry id,
/// lowercased — the idempotency key: every retry of the same entry, from any process, at any time,
/// resolves to the same server-side item.
public enum CaptureTransport {
    /// Multipart bodies are assembled by copying the source file in chunks of this size — never
    /// a whole-file `Data` load (the share extension runs under a ~120 MB ceiling).
    public static let multipartCopyChunkSize = 1 << 20

    static let jsonTimeout: TimeInterval = 30
    static let multipartTimeout: TimeInterval = 60

    public static var captureURL: URL {
        StashConfig.supabaseURL.appending(path: "/functions/v1/capture")
    }

    /// The idempotency key for `entry`.
    public static func captureId(for entry: OutboxEntry) -> String {
        entry.id.uuidString.lowercased()
    }

    // MARK: - Routing

    /// Local file size for a `.file` entry that still carries `local_file_path` (nil otherwise, or
    /// when the file is gone). Filesystem attributes only — never reads the bytes.
    public static func localFileSize(of entry: OutboxEntry) -> Int? {
        guard entry.kind == .file, let path = entry.payload["local_file_path"] else { return nil }
        return (try? URL(fileURLWithPath: path).resourceValues(forKeys: [.fileSizeKey]))?.fileSize
    }

    /// Whether `entry`'s bytes must go to Storage first (two-step: deterministic path + a JSON
    /// capture carrying `file_path`) rather than riding one multipart capture request: a local
    /// file over `oneShotLimit` (`CaptureAPI.oneShotFileLimit`, 10 MiB), or a file entry that has
    /// already failed `CaptureAPI.oneShotMaxAttempts` times (a safety valve — if the endpoint
    /// can't take this body for any reason, e.g. a gateway size or function resource limit, the
    /// storage lane always can, and the capture id keeps the switch idempotent). Entries without
    /// a local file (notes, links, already-uploaded files) never need it.
    public static func requiresTwoStep(_ entry: OutboxEntry, oneShotLimit: Int = CaptureAPI.oneShotFileLimit) -> Bool {
        guard entry.kind == .file, entry.payload["file_path"] == nil,
              entry.payload["local_file_path"] != nil else { return false }
        if entry.attempts >= CaptureAPI.oneShotMaxAttempts { return true }
        return (localFileSize(of: entry) ?? 0) > oneShotLimit
    }

    // MARK: - Capture request

    public enum BodyKind: Sendable, Equatable { case json, multipart }

    /// A capture request plus its body file (always on disk — see `CaptureTransporting`). The
    /// caller owns `bodyFile` and deletes it once the request has finished (foreground) or once
    /// the background task completes (Task 4).
    public struct PreparedRequest: Sendable {
        public let urlRequest: URLRequest
        public let bodyFile: URL
        public let bodyKind: BodyKind
    }

    /// Builds the capture request for `entry` AS IT STANDS: a `.file` entry that still has only
    /// `local_file_path` → one multipart request (meta + file bytes, streamed into a body file
    /// under `bodyDirectory`); everything else — notes, links, and files already in Storage
    /// (`file_path`, the two-step lane's second half) → a JSON request. Throws
    /// `CaptureError.invalidEntry` for an entry that can't be expressed (a `.file` with neither
    /// path), or the file error if the local file can't be read.
    public static func captureRequest(for entry: OutboxEntry, accessToken: String, bodyDirectory: URL,
                                      chunkSize: Int = multipartCopyChunkSize) throws -> PreparedRequest {
        try FileManager.default.createDirectory(at: bodyDirectory, withIntermediateDirectories: true)
        let captureId = captureId(for: entry)
        var request = URLRequest(url: captureURL)
        request.httpMethod = "POST"
        request.setValue(StashConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        if entry.kind == .file, entry.payload["file_path"] == nil {
            guard let localPath = entry.payload["local_file_path"] else {
                throw CaptureError.invalidEntry("file entry has neither file_path nor local_file_path")
            }
            let localURL = URL(fileURLWithPath: localPath)
            let meta = try metaJSONData(for: entry, fileSize: localFileSize(of: entry))
            let boundary = "StashCapture-\(UUID().uuidString)"
            let bodyFile = bodyDirectory.appending(path: "\(captureId)-\(UUID().uuidString).multipart")
            do {
                try writeMultipartBody(meta: meta, file: localURL,
                                       fileName: "\(captureId).\(storageFileExtension(for: entry))",
                                       contentType: mimeType(for: entry), boundary: boundary,
                                       to: bodyFile, chunkSize: chunkSize)
            } catch {
                try? FileManager.default.removeItem(at: bodyFile)
                throw error
            }
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = multipartTimeout
            return PreparedRequest(urlRequest: request, bodyFile: bodyFile, bodyKind: .multipart)
        }

        let bodyFile = bodyDirectory.appending(path: "\(captureId)-\(UUID().uuidString).json")
        try metaJSONData(for: entry, fileSize: nil).write(to: bodyFile, options: .atomic)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = jsonTimeout
        return PreparedRequest(urlRequest: request, bodyFile: bodyFile, bodyKind: .json)
    }

    /// The `meta` object for `entry` (JSON-ready), mapped from the Outbox's `[String: String]`
    /// payload, in the shape the endpoint forwards to `add-note`/`add-url`/`add-file`:
    /// notes/links always carry `content` (links may send `""`), files only a non-empty one;
    /// `attributes` is the `attributes_json` string parsed verbatim — never round-tripped through
    /// a typed model that could drop keys it doesn't know — and omitted when empty.
    public static func meta(for entry: OutboxEntry, fileSize: Int?) -> [String: Any] {
        let payload = entry.payload
        var meta: [String: Any] = [
            "capture_id": captureId(for: entry),
            "kind": entry.kind.rawValue,
            "is_public": payload["is_public"] == "true",
        ]
        if let title = payload["title"], !title.isEmpty { meta["title"] = title }
        if let remindAt = payload["remind_at"], !remindAt.isEmpty { meta["remind_at"] = remindAt }
        if let attributes = attributesObject(from: payload["attributes_json"]) { meta["attributes"] = attributes }
        switch entry.kind {
        case .note:
            meta["content"] = payload["content"] ?? ""
        case .url:
            meta["url"] = payload["url"] ?? ""
            meta["content"] = payload["content"] ?? ""
        case .file:
            if let content = payload["content"], !content.isEmpty { meta["content"] = content }
            meta["mime_type"] = mimeType(for: entry)
            if let filePath = payload["file_path"] { meta["file_path"] = filePath }
            if let fileName = payload["file_name"], !fileName.isEmpty { meta["file_name"] = fileName }
            if let size = payload["file_size"].flatMap(Int.init) ?? fileSize { meta["file_size"] = size }
        }
        return meta
    }

    /// `meta(for:fileSize:)` serialized with sorted keys (deterministic bytes — the multipart
    /// byte test relies on it).
    public static func metaJSONData(for entry: OutboxEntry, fileSize: Int?) throws -> Data {
        try JSONSerialization.data(withJSONObject: meta(for: entry, fileSize: fileSize),
                                   options: [.sortedKeys, .withoutEscapingSlashes])
    }

    /// Streams `file` into a `multipart/form-data` body at `destination`:
    ///
    ///     --<boundary>\r\n
    ///     Content-Disposition: form-data; name="meta"\r\n\r\n
    ///     <meta JSON>\r\n
    ///     --<boundary>\r\n
    ///     Content-Disposition: form-data; name="file"; filename="<name>"\r\n
    ///     Content-Type: <mime>\r\n\r\n
    ///     <file bytes>\r\n
    ///     --<boundary>--\r\n
    ///
    /// The `meta` part carries no `Content-Type` (a filename-less part is a plain string field to
    /// the WHATWG form-data parser Deno uses). `fileName` must be header-safe ASCII — callers pass
    /// `<capture_id>.<ext>`; the user-facing original name travels in `meta.file_name` instead.
    static func writeMultipartBody(meta: Data, file: URL, fileName: String, contentType: String,
                                   boundary: String, to destination: URL, chunkSize: Int) throws {
        let input = try FileHandle(forReadingFrom: file)
        defer { try? input.close() }
        guard FileManager.default.createFile(atPath: destination.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let output = try FileHandle(forWritingTo: destination)
        defer { try? output.close() }

        try output.write(contentsOf: Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"meta\"\r\n\r\n".utf8))
        try output.write(contentsOf: meta)
        try output.write(contentsOf: Data(("\r\n--\(boundary)\r\n"
            + "Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n"
            + "Content-Type: \(contentType)\r\n\r\n").utf8))
        while true {
            let chunk: Data? = try autoreleasepool { try input.read(upToCount: max(1, chunkSize)) }
            guard let chunk, !chunk.isEmpty else { break }
            try output.write(contentsOf: chunk)
        }
        try output.write(contentsOf: Data("\r\n--\(boundary)--\r\n".utf8))
    }

    // MARK: - Two-step storage lane

    /// `stash-media/<uid>/<entryId>.<ext>` — deterministic per entry, so re-uploading the same
    /// entry (a retry after a lost response, a relaunch mid-upload, the app finishing what the
    /// extension started) overwrites one object (`x-upsert: true`) instead of minting orphans.
    public static func storagePath(userId: UUID, entryId: UUID, fileExtension: String) -> String {
        let ext = fileExtension.isEmpty ? "bin" : fileExtension.lowercased()
        return "\(userId.uuidString.lowercased())/\(entryId.uuidString.lowercased()).\(ext)"
    }

    /// Extension for `entry`'s object name — exactly what the server picks for a one-shot upload
    /// (`fileExtension(fileName:mimeType:)`, a port of `_shared/capture.ts` `fileExtensionFor`), so
    /// an entry's object has ONE name whichever lane stored it (the two-step upsert then overwrites
    /// a one-shot object instead of orphaning it). The local file's own extension is deliberately
    /// NOT consulted: the server never sees it, and any tier the server lacks could only diverge.
    public static func storageFileExtension(for entry: OutboxEntry) -> String {
        fileExtension(fileName: entry.payload["file_name"], mimeType: entry.payload["mime_type"])
    }

    /// Port of the server's `fileExtensionFor` (supabase/functions/_shared/capture.ts; its vitest
    /// cases are mirrored in `CaptureTransportTests`): the file name's extension when it has a
    /// sane one (lowercased, `[a-z0-9]{1,10}`, not a leading/trailing dot), else the MIME map
    /// (the server's table, verbatim), else `bin`.
    public static func fileExtension(fileName: String?, mimeType: String?) -> String {
        if let fileName, !fileName.isEmpty {
            let base = fileName.split(whereSeparator: { $0 == "/" || $0 == "\\" }).last.map(String.init) ?? ""
            if let dot = base.lastIndex(of: "."), dot > base.startIndex, base.index(after: dot) < base.endIndex {
                let ext = base[base.index(after: dot)...].lowercased()
                if (1...10).contains(ext.count), ext.allSatisfy({ ("a"..."z").contains($0) || ("0"..."9").contains($0) }) {
                    return ext
                }
            }
        }
        if let mimeType {
            let essence = (mimeType.split(separator: ";").first.map(String.init) ?? "")
                .trimmingCharacters(in: .whitespaces).lowercased()
            if let mapped = serverMimeExtensions[essence] { return mapped }
        }
        return "bin"
    }

    /// The server's `MIME_EXTENSIONS` table (capture.ts), verbatim — keep the two in sync.
    static let serverMimeExtensions: [String: String] = [
        "image/jpeg": "jpg", "image/jpg": "jpg", "image/pjpeg": "jpg", "image/png": "png", "image/gif": "gif",
        "image/webp": "webp", "image/heic": "heic", "image/heif": "heif", "image/avif": "avif", "image/tiff": "tiff",
        "image/bmp": "bmp", "image/svg+xml": "svg",
        "video/mp4": "mp4", "video/quicktime": "mov", "video/x-m4v": "m4v", "video/webm": "webm", "video/mpeg": "mpeg",
        "video/3gpp": "3gp",
        "audio/mp4": "m4a", "audio/m4a": "m4a", "audio/x-m4a": "m4a", "audio/aac": "aac", "audio/mpeg": "mp3",
        "audio/mp3": "mp3", "audio/wav": "wav", "audio/x-wav": "wav", "audio/wave": "wav", "audio/webm": "webm",
        "audio/ogg": "ogg", "audio/flac": "flac", "audio/x-caf": "caf", "audio/amr": "amr",
        "application/pdf": "pdf", "application/msword": "doc",
        "application/vnd.openxmlformats-officedocument.wordprocessingml.document": "docx",
        "application/vnd.ms-excel": "xls",
        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet": "xlsx",
        "application/vnd.ms-powerpoint": "ppt",
        "application/vnd.openxmlformats-officedocument.presentationml.presentation": "pptx",
        "application/rtf": "rtf", "application/epub+zip": "epub", "application/zip": "zip", "application/json": "json",
        "text/plain": "txt", "text/markdown": "md", "text/csv": "csv", "text/html": "html", "text/rtf": "rtf",
    ]

    /// The Storage object-endpoint request (`POST /storage/v1/object/stash-media/<path>`) with
    /// `x-upsert: true`; the body is the local file itself (`upload(_:fromFile:)`).
    public static func storageRequest(path: String, contentType: String, accessToken: String) -> URLRequest {
        var request = URLRequest(url: StashConfig.supabaseURL.appending(path: "/storage/v1/object/stash-media/\(path)"))
        request.httpMethod = "POST"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue(StashConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("true", forHTTPHeaderField: "x-upsert")
        return request
    }

    /// Everything the two-step lane's first half needs for `entry`: the upsert request, the local
    /// file to stream as its body, and the deterministic `path` to checkpoint once it lands
    /// (`Outbox.checkpoint(id:filePath:)`). Throws `.invalidEntry` for an entry with no local file.
    public static func storageUpload(for entry: OutboxEntry, userId: UUID,
                                     accessToken: String) throws -> (request: URLRequest, fileURL: URL, path: String) {
        guard entry.kind == .file, let localPath = entry.payload["local_file_path"] else {
            throw CaptureError.invalidEntry("storage upload needs a file entry with local_file_path")
        }
        let path = storagePath(userId: userId, entryId: entry.id, fileExtension: storageFileExtension(for: entry))
        return (storageRequest(path: path, contentType: mimeType(for: entry), accessToken: accessToken),
                URL(fileURLWithPath: localPath), path)
    }

    // MARK: - Responses

    /// Maps a `capture` response: 2xx → `CaptureResult`; non-2xx → the matching `CaptureError`
    /// (`captureErrorForFailedResponse`: 403 `subscription_required` → `.subscriptionRequired`,
    /// 409 `capture_in_progress` → `.inProgress`, 413 `file_too_large` → `.fileTooLarge`, else
    /// `.badStatus` — including 413 `meta_too_large`, which no lane switch could fix).
    /// A 2xx whose `item` doesn't decode still counts as success (`item: nil`): the server has
    /// the capture, and throwing would only make the Outbox resend it forever.
    public static func result(status: Int, body: Data) throws -> CaptureResult {
        guard (200..<300).contains(status) else { throw captureErrorForFailedResponse(status: status, body: body) }
        guard let root = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] else {
            throw CaptureError.malformedResponse
        }
        var item: Item?
        if let object = root["item"] as? [String: Any],
           let data = try? JSONSerialization.data(withJSONObject: object) {
            item = try? Item.decoder.decode(Item.self, from: data)
        }
        return CaptureResult(item: item, duplicate: root["duplicate"] as? Bool ?? false)
    }

    // MARK: - Helpers

    static func mimeType(for entry: OutboxEntry) -> String {
        let mime = entry.payload["mime_type"] ?? ""
        return mime.isEmpty ? "application/octet-stream" : mime
    }

    /// Parses the Outbox's `attributes_json` string verbatim; `nil` when absent, unparseable, not
    /// an object, or empty (never send `{}` — the whole-blob write convention).
    static func attributesObject(from json: String?) -> [String: Any]? {
        guard let data = json?.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              !object.isEmpty else { return nil }
        return object
    }
}
