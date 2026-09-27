import Foundation

public enum CaptureError: Error, Equatable {
    case badStatus(Int)
    case malformedResponse
    /// Plan 14 T3 (Outbox park-on-403): the server refused with HTTP 403 and body
    /// `{"error": "subscription_required"}` — the account's subscription/trial has lapsed, not a
    /// transient send failure. `Outbox` special-cases this to PARK the entry instead of
    /// incrementing `attempts` and retrying. Distinct from the generic `.badStatus(403)` an
    /// agent-token 403 or any other 403 body still maps to — see `captureErrorForFailedResponse`.
    case subscriptionRequired
    /// Plan 15: the `capture` endpoint answered `409 {"error":"capture_in_progress"}` — another
    /// attempt with the same capture id (the Outbox entry id) is in flight server-side right now,
    /// or this attempt was superseded by a newer one (the endpoint answers both the same way).
    /// Not a failure of this send: the Outbox leaves the entry `.pending` with `attempts`
    /// unchanged, and a later pass finds the server's finished receipt (`duplicate: true`).
    case inProgress
    /// Plan 15: HTTP 413 `{"error":"file_too_large"}` — the one-shot multipart body was over the
    /// endpoint's own guard (the client's 10 MiB routing limit normally keeps this from happening).
    /// The Outbox immediately retries the same entry through the two-step storage lane instead.
    /// Any OTHER 413 (`meta_too_large` — e.g. a huge pasted note — or a gateway's own) is a plain
    /// `.badStatus(413)`: the two-step lane couldn't help, so it counts as an ordinary failed
    /// attempt rather than looping.
    case fileTooLarge
    /// Plan 15: an Outbox entry that can't be expressed as a capture request (a `.file` entry with
    /// neither `file_path` nor `local_file_path`, or a `file_path` outside the user's own folder).
    /// Rejected client-side, before any network call; the Outbox still keeps the entry (it never
    /// auto-deletes user data) and counts it as an ordinary failed attempt.
    case invalidEntry(String)
}

/// Maps a non-2xx `capture` response to the specific `CaptureError` case it represents. Pulled out
/// as its own pure function so the body-shape detection is unit-testable without a real network
/// round trip (`CaptureAPITests`). Only the exact documented bodies map to the special cases: a
/// 403 with any other body (e.g. an agent-token refusal) stays `.badStatus(403)`, a 409 with any
/// other body stays `.badStatus(409)`, and only `413 file_too_large` routes to the two-step lane.
func captureErrorForFailedResponse(status: Int, body: Data) -> CaptureError {
    let error = ((try? JSONSerialization.jsonObject(with: body)) as? [String: Any])?["error"] as? String
    switch status {
    case 403 where error == "subscription_required": return .subscriptionRequired
    case 409 where error == "capture_in_progress": return .inProgress
    case 413 where error == "file_too_large": return .fileTooLarge
    default: return .badStatus(status)
    }
}

/// Plan 15: the client for the idempotent `capture` endpoint (docs/PLATFORM_API.md) — the ONE
/// capture entry point on iOS. (The legacy direct `add-note`/`add-url`/`add-file` calls are gone:
/// their last caller, Ask's chat-as-capture, was retired in plan 15 Task 6A.)
public struct CaptureAPI: Sendable {
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
    ///   - transport: the network seam for `submit` and the storage lane (tests inject a stub).
    ///   - oneShotLimit: see the property.
    public init(transport: CaptureTransporting = URLSessionCaptureTransport(),
                oneShotLimit: Int = CaptureAPI.oneShotFileLimit) {
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
}

/// Streams a local file to the `stash-media` object endpoint
/// (`/storage/v1/object/stash-media/<path>`, `x-upsert: true` — see
/// `CaptureTransport.storageRequest`) via `URLSession.upload(for:fromFile:)`, so the file's bytes
/// are never materialized in memory. `StashApp`'s launch/unpark drains pass this as `Outbox.drain`'s
/// two-step `upload` lane; it is the same request `CaptureAPI.uploadFileToStorage` sends through
/// the injectable transport. No fixed `timeoutInterval`: a large file over a slow connection can
/// legitimately take a while, so `URLRequest`'s ordinary (idle) default stays in place.
public func uploadToStorageFromFile(fileURL: URL, path: String, contentType: String, accessToken: String) async throws {
    let request = CaptureTransport.storageRequest(path: path, contentType: contentType, accessToken: accessToken)
    let (_, response) = try await URLSession.shared.upload(for: request, fromFile: fileURL)
    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
        throw CaptureError.badStatus((response as? HTTPURLResponse)?.statusCode ?? -1)
    }
}
