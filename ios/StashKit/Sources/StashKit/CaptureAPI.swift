import Foundation
import Supabase

public enum CaptureError: Error, Equatable {
    case badStatus(Int)
    case malformedResponse
    /// Plan 14 T3 (Outbox park-on-403): the server refused with HTTP 403 and body
    /// `{"error": "subscription_required"}` — the account's subscription/trial has lapsed, not a
    /// transient send failure. `Outbox.drain` special-cases this to PARK the entry instead of
    /// incrementing `attempts` and retrying (see that method's catch clause). Distinct from the
    /// generic `.badStatus(403)` an agent-token 403 (a different endpoint's shape entirely) or any
    /// other 403 body would still map to — see `captureErrorForFailedResponse` below.
    case subscriptionRequired
    /// Plan 15: the `capture` endpoint answered `409 {"error":"capture_in_progress"}` — another
    /// attempt with the same capture id (the Outbox entry id) is in flight server-side right now.
    /// Not a failure of this send: the Outbox leaves the entry `.pending` with `attempts`
    /// unchanged, and a later pass finds the server's finished receipt (`duplicate: true`).
    case inProgress
    /// Plan 15: HTTP 413 — the one-shot multipart body was too big for the endpoint (its own
    /// 45 MiB guard, or any gateway limit in front of it; the client's own 10 MiB routing limit
    /// normally keeps it from ever happening). The Outbox immediately retries the same entry
    /// through the two-step storage lane instead.
    case fileTooLarge
    /// Plan 15: an Outbox entry that can't be expressed as a capture request (a `.file` entry with
    /// neither `file_path` nor `local_file_path`, or a `file_path` outside the user's own folder).
    /// Rejected client-side, before any network call; the Outbox still keeps the entry (it never
    /// auto-deletes user data) and counts it as an ordinary failed attempt.
    case invalidEntry(String)
}

public protocol JSONPosting: Sendable {
    func post(path: String, body: [String: Any], accessToken: String) async throws -> Data
}

/// Maps a non-2xx `FunctionsPoster`/`capture` response to the specific `CaptureError` case it
/// represents. Pulled out as its own pure function so the body-shape detection is unit-testable
/// without a real network round trip (`CaptureAPITests`). Only the exact documented bodies map to
/// the special cases (a 403 with any other body — e.g. an agent-token refusal — stays
/// `.badStatus(403)`); 413 maps regardless of body, because a gateway in front of the function can
/// send it too.
func captureErrorForFailedResponse(status: Int, body: Data) -> CaptureError {
    let error = ((try? JSONSerialization.jsonObject(with: body)) as? [String: Any])?["error"] as? String
    switch status {
    case 403 where error == "subscription_required": return .subscriptionRequired
    case 409 where error == "capture_in_progress": return .inProgress
    case 413: return .fileTooLarge
    default: return .badStatus(status)
    }
}

/// POSTs to <supabase>/functions/v1/<path> with the platform's two auth headers.
public struct FunctionsPoster: JSONPosting {
    public init() {}
    public func post(path: String, body: [String: Any], accessToken: String) async throws -> Data {
        var request = URLRequest(url: StashConfig.supabaseURL.appending(path: "/functions/v1/\(path)"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(StashConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw captureErrorForFailedResponse(status: status, body: data)
        }
        return data
    }
}

public struct CaptureAPI: Sendable {
    let poster: JSONPosting
    let transport: CaptureTransporting

    /// Plan 15: a `.file` entry whose local file is at most this many bytes rides ONE multipart
    /// request to `capture`; anything bigger goes two-step (Storage upload to the deterministic
    /// path, then a JSON capture carrying `file_path`). Deliberately well under the endpoint's own
    /// 45 MiB one-shot guard (coordinator decision, 2026-09-27): the gateway buffers the whole
    /// request before the function runs and caps it at 150 s, so a big one-shot body is fragile on
    /// a slow uplink, while the direct Storage upload has no such cap. Prepared photos
    /// (~0.3–1.5 MB) stay one-shot; videos and long recordings go two-step.
    public static let oneShotFileLimit = 10 * 1024 * 1024
    /// Plan 15: after this many failed attempts a file entry stops trying the one-shot request and
    /// switches to the two-step lane — see `CaptureTransport.requiresTwoStep`.
    public static let oneShotMaxAttempts = 3

    /// The one-shot limit this instance routes by — `oneShotFileLimit` unless a test injects a
    /// tiny one to exercise the two-step lane without multi-megabyte fixtures.
    public let oneShotLimit: Int

    /// - Parameters:
    ///   - transport: plan 15's network seam for `submit` and the storage lane. The legacy `add-*`
    ///     methods below keep using `poster` (the Ask tab's chat-as-capture still calls them).
    ///   - oneShotLimit: see the property.
    public init(poster: JSONPosting = FunctionsPoster(), transport: CaptureTransporting = URLSessionCaptureTransport(),
                oneShotLimit: Int = CaptureAPI.oneShotFileLimit) {
        self.poster = poster
        self.transport = transport
        self.oneShotLimit = oneShotLimit
    }

    /// Plan 15: sends ONE capture request for `entry` as it stands (see
    /// `CaptureTransport.captureRequest`) to the idempotent `capture` endpoint, keyed by
    /// `capture_id = entry.id` (lowercased). Retrying the same entry can never create a second
    /// item: the server answers a repeat with `duplicate: true` and the original item. The
    /// one-shot vs two-step split (and its checkpoint) is `Outbox`'s job — this is one request.
    ///
    /// `userId` guards an already-uploaded `file_path` (the two-step lane's second half): it must
    /// sit inside that user's own folder, as the server requires — checked here so a malformed
    /// entry fails fast with `.invalidEntry` instead of costing a round trip.
    public func submit(entry: OutboxEntry, userId: UUID, accessToken: String) async throws -> CaptureResult {
        if entry.kind == .file, let filePath = entry.payload["file_path"],
           !filePath.hasPrefix("\(userId.uuidString.lowercased())/") {
            throw CaptureError.invalidEntry("file_path is outside the user's storage folder")
        }
        let prepared = try CaptureTransport.captureRequest(for: entry, accessToken: accessToken,
                                                           bodyDirectory: Self.foregroundBodyDirectory)
        defer { try? FileManager.default.removeItem(at: prepared.bodyFile) }
        let (status, body) = try await transport.upload(prepared.urlRequest, fromFile: prepared.bodyFile)
        return try CaptureTransport.result(status: status, body: body)
    }

    /// Plan 15: the two-step lane's Storage upload — streams `fileURL` to `stash-media/<path>` with
    /// `x-upsert: true`, through the same transport as `submit` (so tests stub both with one seam).
    public func uploadFileToStorage(_ fileURL: URL, path: String, contentType: String, accessToken: String) async throws {
        let request = CaptureTransport.storageRequest(path: path, contentType: contentType, accessToken: accessToken)
        let (status, _) = try await transport.upload(request, fromFile: fileURL)
        guard (200..<300).contains(status) else { throw CaptureError.badStatus(status) }
    }

    /// Scratch space for foreground request bodies (each deleted right after its request).
    /// Background transfers keep theirs in the App Group instead — the system daemon that runs a
    /// background `URLSession` must be able to read them after this process is gone.
    static var foregroundBodyDirectory: URL {
        FileManager.default.temporaryDirectory.appending(path: "StashCaptureBodies")
    }

    public func addNote(content: String, title: String?, isPublic: Bool,
                        attributes: ItemAttributes? = nil, accessToken: String) async throws -> Item {
        var body: [String: Any] = ["content": content, "is_public": isPublic]
        if let title { body["title"] = title }
        addAttributes(attributes, to: &body)
        return try await send(path: "add-note", body: body, envelopeKey: "note", accessToken: accessToken)
    }

    public func addURL(_ url: String, note: String, isPublic: Bool,
                       attributes: ItemAttributes? = nil, accessToken: String) async throws -> Item {
        var body: [String: Any] = ["url": url, "content": note, "is_public": isPublic]
        addAttributes(attributes, to: &body)
        return try await send(path: "add-url", body: body, envelopeKey: "item", accessToken: accessToken)
    }

    public func addFile(path: String, mimeType: String, fileSize: Int?, content: String?, isPublic: Bool,
                        attributes: ItemAttributes? = nil, accessToken: String) async throws -> Item {
        var body: [String: Any] = ["file_path": path, "mime_type": mimeType, "is_public": isPublic]
        if let fileSize { body["file_size"] = fileSize }
        if let content, !content.isEmpty { body["content"] = content }
        addAttributes(attributes, to: &body)
        return try await send(path: "add-file", body: body, envelopeKey: "item", accessToken: accessToken)
    }

    /// Sets `body["attributes"]` only when there's actually something to send — `nil` attributes,
    /// an `.isEmpty` blob, and an encode failure (Task 3's `jsonObject()` contract: "do not send",
    /// never `[:]`, or a caller would silently wipe every attribute the row already has on the
    /// next whole-blob PATCH-replace) all collapse to the same skip via `nonEmptyJSONObject`.
    private func addAttributes(_ attributes: ItemAttributes?, to body: inout [String: Any]) {
        guard let object = attributes?.nonEmptyJSONObject else { return }
        body["attributes"] = object
    }

    private func send(path: String, body: [String: Any], envelopeKey: String, accessToken: String) async throws -> Item {
        let data = try await poster.post(path: path, body: body, accessToken: accessToken)
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let itemObject = root[envelopeKey],
              let itemData = try? JSONSerialization.data(withJSONObject: itemObject)
        else { throw CaptureError.malformedResponse }
        do {
            return try Item.decoder.decode(Item.self, from: itemData)
        } catch {
            throw CaptureError.malformedResponse
        }
    }
}

public func makeUploadPath(userId: UUID, fileExtension: String) -> String {
    "\(userId.uuidString.lowercased())/\(UUID().uuidString.lowercased()).\(fileExtension.lowercased())"
}

public func uploadToStorage(data: Data, path: String, contentType: String) async throws {
    try await StashClient.shared.storage.from("stash-media")
        .upload(path, data: data, options: FileOptions(contentType: contentType))
}

/// Task 4 (Plan 5): the streaming counterpart to `uploadToStorage` above — same bucket, same
/// eventual bytes-on-the-wire, but reached via `URLSession.upload(for:fromFile:)` (the async/await
/// form of `uploadTask(with:fromFile:)`) instead of the Supabase Storage SDK client. That SDK call
/// needs the caller to already hold the file's bytes as `Data`; this one streams straight off
/// disk, which is the entire point — `Outbox.drain`'s `local_file_path` lane (a recording that may
/// be many MB) and, from Task 6, the share extension's own uploads (under a ~120 MB process
/// ceiling) can never afford to materialize a whole shared/recorded file in memory first.
///
/// Hand-builds the request against the object endpoint
/// (`/storage/v1/object/stash-media/<path>`) rather than going through the SDK — deliberately NOT
/// `StashConfig.publicStorageURL`, which builds the separate `/object/public/...` READ path used
/// to fetch an already-uploaded file back, not to write one. Headers and the non-2xx →
/// `CaptureError.badStatus` mapping mirror `FunctionsPoster.post` exactly (same two auth headers,
/// same status-code check) — the one deliberate difference is no fixed `timeoutInterval`: that
/// poster's 20s budget suits a small JSON POST, but a large file upload over a slow connection
/// can legitimately take longer, so this leaves `URLRequest`'s ordinary default in place.
///
/// Plan 15: the request now comes from `CaptureTransport.storageRequest`, which adds
/// `x-upsert: true` — the Outbox's two-step lane uploads to a DETERMINISTIC path per entry
/// (`CaptureTransport.storagePath`), so re-uploading after a lost response or a relaunch must
/// overwrite the object it already wrote rather than fail as a duplicate. Harmless for the random
/// `makeUploadPath` names older call sites pass. (`CaptureAPI.uploadFileToStorage` is the same
/// request through the injectable transport.)
public func uploadToStorageFromFile(fileURL: URL, path: String, contentType: String, accessToken: String) async throws {
    let request = CaptureTransport.storageRequest(path: path, contentType: contentType, accessToken: accessToken)
    let (_, response) = try await URLSession.shared.upload(for: request, fromFile: fileURL)
    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
        throw CaptureError.badStatus((response as? HTTPURLResponse)?.statusCode ?? -1)
    }
}
