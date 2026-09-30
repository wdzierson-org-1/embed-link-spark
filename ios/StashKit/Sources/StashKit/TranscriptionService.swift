import Foundation
import Observation
import Supabase

/// "Transcribe with speakers" (plan 14 Task 2) runs as the SERVER's transcription job (final wave
/// B). Deployed `transcribe-audio` v28 (verified against its source) has two modes:
///
/// - **Preview** `{ audioUrl, fileName }` — synchronous, what this used to call. It now answers
///   `200 { transcription: "", deferred: true }` for any file over 24 MiB (the client showed an
///   endless "try again"), and the client then PATCHed `page_body`/`description` with the user's
///   token, which the `protect_enrichment_edits` trigger records as USER edits
///   (`attributes.enrichment.protected_fields`), shutting later enrichment out of both fields.
/// - **Job** `{ itemId, rebuild: true }` — `202 { accepted: true }` at once (after resetting
///   `attributes.media.transcript` to `pending`); the job then owns every write with the service
///   role: the transcript into `page_body` (chunk by chunk — files of any size are split
///   server-side), `description`, `summary`, an AI title when the title is still a file name,
///   `media.kind`, embeddings, and `media.transcript` (`processing` → `done` / `failed`).
///
/// iOS uses the job for every file. The client starts it, watches `media.transcript.status`
/// (`TranscriptJobState`, kept loss-lessly in `MediaAttributes.extra`) until the job settles, then
/// reads the finished row. It never writes the item itself.

/// Where the server's transcription job for an audio/video item stands: `attributes.media.transcript`
/// (spec 2026-09-09 "long audio transcription"), written only by `transcribe-audio` and `add-file`.
public struct TranscriptJobState: Equatable, Sendable {
    public enum Status: String, Sendable {
        case pending, processing, done, failed
    }

    public let status: Status
    public let chunksDone: Int?
    public let chunksTotal: Int?
    /// Only when failed: `download_failed`, `no_audio_track`, `unsupported_container`,
    /// `transcription_failed`, `no_speech`.
    public let error: String?
    /// When the job last touched the status (server clock).
    public let updatedAt: Date?

    /// A running job touches its status at least once per chunk; the server's own sweep resumes a
    /// stalled one after 15 minutes. A pending/processing status older than this is treated as
    /// stalled — no longer shown as running, so a new run can be started.
    public static let staleAfter: TimeInterval = 20 * 60

    public init(status: Status, chunksDone: Int? = nil, chunksTotal: Int? = nil, error: String? = nil,
                updatedAt: Date? = nil) {
        self.status = status
        self.chunksDone = chunksDone
        self.chunksTotal = chunksTotal
        self.error = error
        self.updatedAt = updatedAt
    }

    /// `nil` when the item has no transcript status (anything but audio/video, or legacy rows).
    public init?(attributes: ItemAttributes) {
        guard case .object(let transcript)? = attributes.media?.extra["transcript"],
              case .string(let raw)? = transcript["status"], let status = Status(rawValue: raw)
        else { return nil }
        func int(_ key: String) -> Int? {
            if case .number(let value)? = transcript[key] { return Int(value) }
            return nil
        }
        var error: String?
        if case .string(let code)? = transcript["error"] { error = code }
        var updatedAt: Date?
        if case .string(let stamp)? = transcript["updated_at"] { updatedAt = Self.parseTimestamp(stamp) }
        self.init(status: status, chunksDone: int("chunks_done"), chunksTotal: int("chunks_total"),
                  error: error, updatedAt: updatedAt)
    }

    /// Pending or processing, and touched within `staleAfter` of `now`.
    public func isRunning(at now: Date) -> Bool {
        guard status == .pending || status == .processing, let updatedAt else { return false }
        return now.timeIntervalSince(updatedAt) < Self.staleAfter
    }

    /// The job writes `new Date().toISOString()` (fractional seconds); plain seconds also accepted.
    static func parseTimestamp(_ stamp: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: stamp) { return date }
        return ISO8601DateFormatter().date(from: stamp)
    }
}

/// How a watched job ended.
public enum TranscriptionOutcome: Equatable, Sendable {
    /// `done` — the finished row (`page_body` included), read after the job's last write.
    case finished(Item)
    /// `failed` — the row as it stands (whatever the job wrote before failing; `nil` if it couldn't
    /// be read) and the job's error code.
    case failed(Item?, reason: String?)
}

/// Why no outcome came back from `TranscriptionService`.
public enum TranscriptionServiceError: Error, Equatable, Sendable {
    /// No `file_path` on the item — nothing to rebuild from (the UI hides the button then).
    case noStoredMedia
    /// The job couldn't be started (network, auth, non-2xx) — nothing changed on the server.
    case startFailed(String)
    /// The client stopped watching (`TranscriptionService.maxWait`) before it could deliver an
    /// outcome — the job outlasted the wait (it carries on server-side, and the item's
    /// `media.transcript` still says so), or it finished but the row couldn't be read back. Nothing
    /// to report to the user; the list picks the result up like any server change.
    case stoppedWatching
    /// This app is already watching a job for the item (possibly started from a sheet since
    /// closed) — nothing new was started.
    case alreadyRunning
}

/// The transcription job's network surface — stubbed in `StashKitTests`.
public protocol TranscriptionJobClient: Sendable {
    /// `POST transcribe-audio { itemId, rebuild: true }` — succeeds on the `202`.
    func startRebuild(itemId: UUID) async throws
    /// The row's current `attributes`, or `nil` when it can't be read.
    func currentAttributes(itemId: UUID) async throws -> ItemAttributes?
    /// The full detail row, `page_body` included.
    func fetchDetail(itemId: UUID) async throws -> Item
}

public struct SupabaseTranscriptionJobClient: TranscriptionJobClient {
    public init() {}

    /// The job answers `202` as soon as it has reset the status; no long wait.
    public static let startTimeout: TimeInterval = 30

    /// `POST <supabase>/functions/v1/transcribe-audio` with the platform's two auth headers and
    /// `{ itemId, rebuild: true }` (the function checks the caller owns the item). Pure, for tests.
    public static func startRequest(itemId: UUID, accessToken: String) throws -> URLRequest {
        var request = URLRequest(url: StashConfig.supabaseURL.appending(path: "/functions/v1/transcribe-audio"))
        request.httpMethod = "POST"
        request.timeoutInterval = startTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(StashConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["itemId": itemId.uuidString.lowercased(),
                                                                      "rebuild": true])
        return request
    }

    public func startRebuild(itemId: UUID) async throws {
        let accessToken = try await StashClient.shared.auth.session.accessToken
        let (_, response) = try await URLSession.shared.data(for: Self.startRequest(itemId: itemId, accessToken: accessToken))
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard (200..<300).contains(status) else {
            throw TranscriptionServiceError.startFailed("transcribe-audio answered HTTP \(status)")
        }
    }

    public func currentAttributes(itemId: UUID) async throws -> ItemAttributes? {
        try await SupabaseItemPatcher().currentAttributes(itemId: itemId)
    }

    public func fetchDetail(itemId: UUID) async throws -> Item {
        try await SupabaseItemsFetcher().fetchDetail(id: itemId)
    }
}

/// Which items this app is watching a transcription job for, app-wide (plan 15, M9). A job can
/// take minutes and keeps going after its sheet is closed, so the busy state lives here rather
/// than in the sheet: reopening the item still shows "Transcribing…", and a second (duplicate,
/// paid) run for the same item can't be started meanwhile.
@MainActor @Observable
public final class TranscriptionActivity {
    public static let shared = TranscriptionActivity()

    public private(set) var itemIds: Set<UUID> = []

    public init() {}

    public func isRunning(_ itemId: UUID) -> Bool { itemIds.contains(itemId) }

    /// `false` when `itemId` is already being watched.
    func begin(_ itemId: UUID) -> Bool { itemIds.insert(itemId).inserted }

    func end(_ itemId: UUID) { itemIds.remove(itemId) }
}

/// Starts and watches the server's transcription job for an item (see the top of this file).
@MainActor
public final class TranscriptionService {
    /// How long the client keeps watching one job. A 45-minute recording (three chunks) takes a
    /// few minutes; past this the job still finishes server-side and the item says so.
    public static let maxWait: TimeInterval = 30 * 60

    /// Every 3 s for the first minute (a voice memo is usually done by then), every 8 s after.
    public static func pollInterval(afterWaiting elapsed: TimeInterval) -> TimeInterval {
        elapsed < 60 ? 3 : 8
    }

    private let client: TranscriptionJobClient
    private let activity: TranscriptionActivity
    private let writeQueue: ItemWriteQueue
    private let now: () -> Date
    private let sleep: @Sendable (TimeInterval) async throws -> Void

    /// `activity`/`writeQueue` default to the app-wide shared instances; tests pass their own, and
    /// their own clock and sleep.
    public init(client: TranscriptionJobClient = SupabaseTranscriptionJobClient(),
                activity: TranscriptionActivity? = nil,
                writeQueue: ItemWriteQueue? = nil,
                now: @escaping () -> Date = Date.init,
                sleep: @escaping @Sendable (TimeInterval) async throws -> Void = { seconds in
                    try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                }) {
        self.client = client
        self.activity = activity ?? .shared
        self.writeQueue = writeQueue ?? .shared
        self.now = now
        self.sleep = sleep
    }

    /// "Transcribe with speakers": rebuilds the item's transcript from its recording on the server
    /// and waits for the result. Throws before anything starts for `.noStoredMedia`/
    /// `.alreadyRunning`/`.startFailed`; `.stoppedWatching` when no outcome came by `maxWait`.
    public func retranscribe(item: Item) async throws -> TranscriptionOutcome {
        guard let filePath = item.filePath, !filePath.isEmpty else { throw TranscriptionServiceError.noStoredMedia }
        guard activity.begin(item.id) else { throw TranscriptionServiceError.alreadyRunning }
        defer { activity.end(item.id) }
        do {
            try await client.startRebuild(itemId: item.id)
        } catch let error as TranscriptionServiceError {
            throw error
        } catch {
            throw TranscriptionServiceError.startFailed(error.localizedDescription)
        }
        return try await watch(itemId: item.id)
    }

    /// Follows a job that is already running server-side — the sheet opened while one ran (a fresh
    /// recording's first transcription, or a rebuild started from a sheet since closed) — until it
    /// settles. `nil` when this app already watches the item (that watcher delivers the result).
    public func follow(itemId: UUID) async throws -> TranscriptionOutcome? {
        guard activity.begin(itemId) else { return nil }
        defer { activity.end(itemId) }
        return try await watch(itemId: itemId)
    }

    /// Polls `media.transcript.status` until `done`/`failed`, then reads the row. A read that fails
    /// (offline for a moment) is just retried: the job doesn't depend on this client.
    private func watch(itemId: UUID) async throws -> TranscriptionOutcome {
        let startedAt = now()
        func elapsed() -> TimeInterval { now().timeIntervalSince(startedAt) }
        var settled: TranscriptJobState?
        while settled == nil {
            if elapsed() >= Self.maxWait { throw TranscriptionServiceError.stoppedWatching }
            try await sleep(Self.pollInterval(afterWaiting: elapsed()))
            let attributes: ItemAttributes?
            do {
                attributes = try await client.currentAttributes(itemId: itemId)
            } catch {
                if error is CancellationError { throw error }
                continue
            }
            guard let attributes else { return .failed(nil, reason: nil) }   // deleted, or not readable
            if let job = TranscriptJobState(attributes: attributes), job.status == .done || job.status == .failed {
                settled = job
            }
        }
        let row = try await settledRow(itemId: itemId, startedAt: startedAt)
        if settled?.status == .done {
            guard let row else { throw TranscriptionServiceError.stoppedWatching }
            return .finished(row)
        }
        return .failed(row, reason: settled?.error)
    }

    /// The settled row, read in the item's write slot — after every write to it the sheet already
    /// started — so adopting it can never roll back a newer save. Retried like the polls; `nil` if
    /// it still can't be read by `maxWait`.
    private func settledRow(itemId: UUID, startedAt: Date) async throws -> Item? {
        while true {
            do {
                return try await writeQueue.enqueue(itemId: itemId) { [client] in
                    try await client.fetchDetail(itemId: itemId)
                }
            } catch {
                if error is CancellationError { throw error }
                let elapsed = now().timeIntervalSince(startedAt)
                if elapsed >= Self.maxWait { return nil }
                try await sleep(Self.pollInterval(afterWaiting: elapsed))
            }
        }
    }
}
