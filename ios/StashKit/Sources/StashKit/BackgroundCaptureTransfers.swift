import Foundation
import os
import Supabase

// Plan 15, Task 4 — the share sheet hands its captures to a background `URLSession` and quits.
//
// Apple DTS, "Networking in a Short-Lived Extension" (developer.apple.com/forums/thread/76659):
// - The app and the extension use the SAME background session identifier, in the App Group
//   (`sharedContainerIdentifier`), so the system can hand the extension's transfers to the app.
// - Only one process may be connected to that session at a time; a second one is invalidated at
//   once with `NSURLErrorBackgroundSessionInUseByAnotherProcess`.
// - The extension starts its tasks and calls `completeRequest` right away — it never waits.
// - Whether the extension or the app receives a task's completion is non-deterministic (a fast
//   task often completes while the extension is still alive), so the completion handling lives
//   HERE, in shared code, and runs in whichever process gets the events.
// - When the system wakes the app for the session's events, the app stores the completion
//   handler, reconnects, handles the events, and on `urlSessionDidFinishEvents` invalidates
//   (`finishTasksAndInvalidate`) and calls the handler, so it never stays connected.
//
// Every transfer is an Outbox entry first (its id is the server-side idempotency key), so any
// transfer that dies quietly is simply resent later by the app's drain — never duplicated.

// MARK: - Task description

/// Which half of a capture one background task carries: `capture` — the `capture` endpoint
/// request (JSON, or one multipart body for a small file); `storage` — the two-step lane's
/// Storage upsert of a big file (a JSON `capture` task follows it). The same enum the Outbox
/// records on a `.transferring` entry.
public typealias BackgroundTransferPhase = OutboxEntry.TransferPhase

/// A background task's `taskDescription`: `"<userId>|<entryId>|<phase>"`, ids lowercased, plus an
/// optional fourth component `refreshed` once the task was restarted with a freshly refreshed
/// token. It is the only state that reaches whichever process the system wakes with the task's
/// events, so it names everything the completion needs: whose Outbox, which entry, which half of
/// the capture, and whether the one token-refresh retry was already spent.
public struct BackgroundTransferDescriptor: Hashable, Sendable {
    public let userId: UUID
    public let entryId: UUID
    public let phase: BackgroundTransferPhase
    /// `true` for a task restarted after a 401 with a refreshed token (it gets no second retry).
    public let refreshed: Bool

    public init(userId: UUID, entryId: UUID, phase: BackgroundTransferPhase, refreshed: Bool = false) {
        self.userId = userId
        self.entryId = entryId
        self.phase = phase
        self.refreshed = refreshed
    }

    public var taskDescription: String {
        "\(userId.uuidString.lowercased())|\(entryId.uuidString.lowercased())|\(phase.rawValue)"
            + (refreshed ? "|refreshed" : "")
    }

    /// `nil` for anything that isn't exactly this format (a task this code didn't create).
    public init?(taskDescription: String?) {
        guard let parts = taskDescription?.split(separator: "|", omittingEmptySubsequences: false),
              parts.count == 3 || (parts.count == 4 && parts[3] == "refreshed"),
              let userId = UUID(uuidString: String(parts[0])),
              let entryId = UUID(uuidString: String(parts[1])),
              let phase = BackgroundTransferPhase(rawValue: String(parts[2])) else { return nil }
        self.init(userId: userId, entryId: entryId, phase: phase, refreshed: parts.count == 4)
    }
}

// MARK: - Completion decision (pure)

/// What a finished background task means for its Outbox entry.
public enum BackgroundTransferDecision: Equatable, Sendable {
    /// 2xx from `capture`: the server has it (new, or a `duplicate` replay). Complete the entry
    /// (entry, claim and staged file deleted) and, in the app, post `.stashItemCaptured`.
    case complete(CaptureResult)
    /// 2xx from Storage: the bytes are at the entry's deterministic path. Checkpoint `file_path`,
    /// then send the JSON capture in the same session.
    case checkpointThenCapture
    /// 403 `subscription_required`: park until the account can add content again.
    case park
    /// Back to `.pending` for a later send. `countsAsAttempt` is false when the attempt wasn't a
    /// failure of this capture: 409 `capture_in_progress` (another attempt with the same id is
    /// running server-side), or the session was in use by another process (nothing was sent).
    case retry(countsAsAttempt: Bool)
    /// 413 `file_too_large`: back to `.pending` (attempt counted) with the next send forced
    /// through the two-step Storage lane.
    case retryTwoStep
    /// The token was rejected (401, or Storage's "jwt expired"): a background task can sit in the
    /// system's queue — no signal — longer than a token lives. Restart the SAME phase in the
    /// session once with a freshly refreshed token, without counting an attempt.
    case refreshTokenAndRetry

    /// Maps one finished task. `error` is the task's transport error (a transport error always
    /// wins over a partial response — the body may be cut off); `statusCode` its HTTP status.
    /// `bodyTruncated`: the response body went over the accumulation cap (a 2xx capture then
    /// still completes — the server has it; only its row can't be read back).
    /// `afterTokenRefresh`: the task already was the one token-refresh retry.
    public static func decide(phase: BackgroundTransferPhase, statusCode: Int?, body: Data,
                              error: Error?, bodyTruncated: Bool = false,
                              afterTokenRefresh: Bool = false) -> BackgroundTransferDecision {
        if let error {
            if (error as? URLError)?.code == .backgroundSessionInUseByAnotherProcess {
                return .retry(countsAsAttempt: false)
            }
            return .retry(countsAsAttempt: true)
        }
        guard let statusCode else { return .retry(countsAsAttempt: true) }
        if (200..<300).contains(statusCode) {
            switch phase {
            case .storage:
                return .checkpointThenCapture
            case .capture:
                if bodyTruncated { return .complete(CaptureResult(item: nil, duplicate: false)) }
                // A 2xx that isn't the endpoint's JSON (a proxy page, a cut-off body) is treated
                // like the foreground lane treats it: a failed attempt. The resend is harmless —
                // if the capture did land, the server answers `duplicate: true`.
                guard let result = try? CaptureTransport.result(status: statusCode, body: body) else {
                    return .retry(countsAsAttempt: true)
                }
                return .complete(result)
            }
        }
        if isRejectedToken(phase: phase, statusCode: statusCode, body: body) {
            return afterTokenRefresh ? .retry(countsAsAttempt: true) : .refreshTokenAndRetry
        }
        switch captureErrorForFailedResponse(status: statusCode, body: body) {
        case .subscriptionRequired: return .park
        case .inProgress: return .retry(countsAsAttempt: false)
        case .fileTooLarge: return .retryTwoStep
        default: return .retry(countsAsAttempt: true)
        }
    }

    /// A token rejection: any 401 (the gateway's "Invalid JWT", the endpoint's own auth check),
    /// or — Storage only — a 400/403 whose body names the JWT (Storage answers an expired token
    /// with e.g. `{"statusCode":"403","error":"Unauthorized","message":"jwt expired"}`).
    static func isRejectedToken(phase: BackgroundTransferPhase, statusCode: Int, body: Data) -> Bool {
        if statusCode == 401 { return true }
        guard phase == .storage, statusCode == 400 || statusCode == 403 else { return false }
        return String(decoding: body.prefix(4096), as: UTF8.self).lowercased().contains("jwt")
    }

    /// A log-safe summary (never the item itself — that's user content).
    var logLabel: String {
        switch self {
        case .complete(let result): "complete (duplicate: \(result.duplicate), item: \(result.item == nil ? "none" : "yes"))"
        case .checkpointThenCapture: "checkpoint, then capture"
        case .park: "park"
        case .retry(let countsAsAttempt): "retry (attempt counted: \(countsAsAttempt))"
        case .retryTwoStep: "retry two-step"
        case .refreshTokenAndRetry: "refresh the token and retry once"
        }
    }
}

// MARK: - Session seam

/// The two things this file needs from a background `URLSession` — a protocol so tests can drive
/// `start` and the events flow without the system's transfer daemon.
protocol BackgroundUploadSession: AnyObject, Sendable {
    func startUpload(_ request: URLRequest, fromFile file: URL, taskDescription: String)
    func finishTasksAndInvalidate()
}

extension URLSession: BackgroundUploadSession {
    func startUpload(_ request: URLRequest, fromFile file: URL, taskDescription: String) {
        let task = uploadTask(with: request, fromFile: file)
        task.taskDescription = taskDescription
        task.resume()
    }
}

/// What `start` did with one share's entries.
public struct BackgroundTransferBatch: Equatable, Sendable {
    public let userId: UUID
    /// Which connection of this process's session carried the batch (`nil` when none could).
    let generation: Int?
    /// Entries whose background task was started.
    public let started: [UUID]
    /// Entries that couldn't be handed over (already put back to `.pending`).
    public let notStarted: [UUID]
}

// MARK: - Transfers

/// The shared background session for capture transfers (see the header comment for the Apple
/// DTS pattern it implements): `start` hands Outbox entries to it (share extension); the
/// delegate applies each finished task to its entry in whichever process receives it; the app
/// reconnects only when the system asks it to (`handleEvents`), never at an ordinary launch —
/// stale `transferring` entries are resent by the app's ordinary drain instead.
public final class BackgroundCaptureTransfers: NSObject, @unchecked Sendable {
    public static let sessionIdentifier = "it.gostash.stash.capture-transfers"

    /// The process-wide instance: one session object per identifier per process is a hard rule.
    public static let shared = BackgroundCaptureTransfers()

    public static func makeConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.background(withIdentifier: sessionIdentifier)
        configuration.sharedContainerIdentifier = AppGroup.identifier
        configuration.isDiscretionary = false
        configuration.sessionSendsLaunchEvents = true
        configuration.timeoutIntervalForResource = 3600
        return configuration
    }

    /// `<App Group>/StashTransfers/` — request bodies must outlive the process that wrote them
    /// (the system's transfer daemon reads them after the extension is gone).
    public static var defaultBodyDirectory: URL {
        AppGroup.containerURL().appending(path: "StashTransfers")
    }

    /// Body files older than this can't belong to a live task (`timeoutIntervalForResource` is
    /// an hour); `sweepStaleBodyFiles` removes them.
    public static let staleBodyFileAge: TimeInterval = 3 * 3600

    /// At most this much of one response is kept: a `duplicate: true` answer carries the whole
    /// item row (page text included), and nothing past the capture's own JSON is ever needed.
    static let maxResponseBodyBytes = 2 * 1024 * 1024

    /// Upper bound on the token fetch while applying completions (final wave, T4 review carry):
    /// the fetch may refresh the session over the network, and a background wake has only seconds
    /// for ALL its events — completions are applied one after another, and the system's completion
    /// handler waits behind them. So there is ONE bounded fetch per user per wake
    /// (`completionToken(for:)`), whatever the number of completions. On timeout the entries stay
    /// `.pending` for the app's next drain.
    public static let completionTokenTimeout: TimeInterval = 10

    /// How long one completion-token answer is reused (final wave review) — a whole wake's events
    /// arrive well within it. A wake's end (`finishEvents`) forgets it sooner; this bound covers the
    /// share extension, whose process can stay alive (and be reused) without an end-of-events call.
    static let completionTokenReuseInterval: TimeInterval = 60

    // Dependencies (injectable for tests).
    private let bodyDirectory: URL
    private let outboxForUser: @Sendable (UUID) -> Outbox
    private let accessTokenForUser: @Sendable (UUID) async -> String?
    private let postsCaptureNotifications: Bool
    private let oneShotLimit: Int
    private let sessionFactory: (BackgroundCaptureTransfers) -> BackgroundUploadSession
    private let foregroundSend: @Sendable (Outbox, UUID, UUID, String) async -> Void

    private let delegateQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.name = "it.gostash.stash.capture-transfers"
        return queue
    }()
    private let log = Logger(subsystem: "it.gostash.stash", category: "capture-transfers")

    // State, guarded by `lock`.
    private let lock = NSLock()
    /// The connected session (created lazily; `nil` before the first use and after invalidation).
    private var session: BackgroundUploadSession?
    private var sessionGeneration = 0
    /// A session this process invalidated with `finishTasksAndInvalidate` whose tasks are still
    /// running: it stays connected until they finish, and a second session object with the same
    /// identifier must not be created meanwhile.
    private var windingDownSession: BackgroundUploadSession?
    /// Connections that were lost (invalidated without this process asking, e.g. because another
    /// process was connected) — their tasks will never report back here.
    private var lostGenerations: Set<Int> = []
    private var responseBodies: [Int: Data] = [:]
    /// Tasks whose response went over `maxResponseBodyBytes` (the rest was dropped).
    private var truncatedResponses: Set<Int> = []
    private var eventsCompletionHandlers: [() -> Void] = []
    private var workTail: Task<Void, Never>?
    /// This wake's token fetch per user (see `completionToken(for:)`), with when it started.
    private var completionTokens: [UUID: (fetch: Task<String?, Never>, startedAt: Date)] = [:]

    public override convenience init() {
        self.init(
            bodyDirectory: Self.defaultBodyDirectory,
            outboxForUser: { Outbox(directory: Outbox.defaultDirectory(userId: $0)) },
            accessTokenForUser: { userId in
                // Never another account's token (a transfer finishing after a sign-out/sign-in must
                // not be sent — or re-sent — as someone else), and never an unbounded wait.
                await ShareIntake.refreshedTransferToken(timeout: BackgroundCaptureTransfers.completionTokenTimeout) {
                    try await StashClient.accessToken(for: userId)
                }
            },
            // The app observes `.stashItemCaptured`; the extension has nothing to update.
            postsCaptureNotifications: Bundle.main.bundleURL.pathExtension == "app",
            oneShotLimit: CaptureAPI.oneShotFileLimit,
            sessionFactory: { owner in
                URLSession(configuration: BackgroundCaptureTransfers.makeConfiguration(), delegate: owner,
                           delegateQueue: owner.delegateQueue)
            },
            foregroundSend: { outbox, entryId, userId, token in
                _ = await outbox.sendNow(id: entryId, api: CaptureAPI(), userId: userId, accessToken: token)
            })
    }

    init(bodyDirectory: URL,
         outboxForUser: @escaping @Sendable (UUID) -> Outbox,
         accessTokenForUser: @escaping @Sendable (UUID) async -> String?,
         postsCaptureNotifications: Bool,
         oneShotLimit: Int = CaptureAPI.oneShotFileLimit,
         sessionFactory: @escaping (BackgroundCaptureTransfers) -> BackgroundUploadSession,
         foregroundSend: @escaping @Sendable (Outbox, UUID, UUID, String) async -> Void) {
        self.bodyDirectory = bodyDirectory
        self.outboxForUser = outboxForUser
        self.accessTokenForUser = accessTokenForUser
        self.postsCaptureNotifications = postsCaptureNotifications
        self.oneShotLimit = oneShotLimit
        self.sessionFactory = sessionFactory
        self.foregroundSend = foregroundSend
        super.init()
    }

    // MARK: Start (share extension)

    /// Hands `entries` (already on disk — `ShareIntake.enqueueForTransfer`) to the background
    /// session: each request body is written to `StashTransfers/` (`CaptureTransport`), each
    /// entry re-stamped `.transferring`, then its upload task started — the stamp comes first,
    /// so even an instant completion is always applied after it. A file entry over the one-shot
    /// limit starts with its Storage upsert. An entry whose request can't be built goes back to
    /// `.pending` and is reported in `notStarted`; if the session can't take tasks at all, every
    /// entry is. Never waits for a transfer.
    public func start(entries: [OutboxEntry], userId: UUID, accessToken: String) async -> BackgroundTransferBatch {
        let outbox = outboxForUser(userId)
        guard !entries.isEmpty else {
            return BackgroundTransferBatch(userId: userId, generation: nil, started: [], notStarted: [])
        }
        guard let connection = connect() else {
            log.notice("start: this process's session is still winding down — \(entries.count) entries left pending")
            for entry in entries { await outbox.markPending(id: entry.id, incrementAttempts: false) }
            return BackgroundTransferBatch(userId: userId, generation: nil, started: [], notStarted: entries.map(\.id))
        }
        let (session, generation) = connection
        var started: [UUID] = []
        var notStarted: [UUID] = []
        for entry in entries {
            let upload: PreparedUpload
            do {
                upload = try prepareUpload(for: entry, userId: userId, accessToken: accessToken)
            } catch {
                log.error("start: couldn't build the request for entry \(entry.id.uuidString, privacy: .public): \(String(describing: error))")
                await outbox.markPending(id: entry.id, incrementAttempts: false)
                notStarted.append(entry.id)
                continue
            }
            guard !(await outbox.markTransferring(ids: [entry.id], phase: upload.phase)).isEmpty else {
                // Parked or gone in the meantime — nothing to send.
                upload.discardBody()
                continue
            }
            let descriptor = BackgroundTransferDescriptor(userId: userId, entryId: entry.id, phase: upload.phase)
            session.startUpload(upload.request, fromFile: upload.file, taskDescription: descriptor.taskDescription)
            started.append(entry.id)
            log.notice("start: entry \(entry.id.uuidString, privacy: .public) phase \(upload.phase.rawValue, privacy: .public)")
        }
        return BackgroundTransferBatch(userId: userId, generation: generation, started: started, notStarted: notStarted)
    }

    /// For the extension, once its confirmation has shown: which of `batch`'s entries the
    /// background session is NOT going to deliver — every entry that couldn't start, every entry
    /// a finished task already put back to `.pending` (a fast failure, or the session was in use
    /// by another process), and, if this process's connection was lost, every entry of the
    /// batch still marked transferring (flipped to `.pending` here). The caller sends those in
    /// the foreground (bounded) before it dismisses; the app's drain covers anything left.
    public func entriesNeedingForegroundSend(in batch: BackgroundTransferBatch) async -> [UUID] {
        await waitForIdle()
        let outbox = outboxForUser(batch.userId)
        let connectionLost = batch.generation.map { generation in lock.withLock { lostGenerations.contains(generation) } } ?? false
        var ids = batch.notStarted
        for id in batch.started {
            guard let entry = await outbox.entry(id: id) else { continue }
            switch entry.status {
            case .pending:
                ids.append(id)
            case .transferring where connectionLost:
                await outbox.markPending(id: id, incrementAttempts: false)
                discardBodyFiles(for: id)
                ids.append(id)
            case .transferring, .parked:
                break
            }
        }
        return ids
    }

    // MARK: Events (app)

    /// `application(_:handleEventsForBackgroundURLSession:completionHandler:)`: returns `false`
    /// for any other session identifier. Stores the handler and reconnects (creating the session
    /// object if this process has none) so the system can deliver the events; the handler is
    /// called on the main queue once they're all handled (`urlSessionDidFinishEvents`), right
    /// after the session is invalidated so this process doesn't stay connected.
    @discardableResult
    public func handleEvents(forBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) -> Bool {
        guard identifier == Self.sessionIdentifier else { return false }
        lock.withLock { eventsCompletionHandlers.append(completionHandler) }
        log.notice("handleEvents: reconnecting to deliver background transfer events")
        _ = connect()
        return true
    }

    // MARK: Maintenance

    /// Deletes request bodies in `directory` older than `age` — leftovers of a process killed
    /// between writing a body and its task's completion (the completion always deletes its own).
    @discardableResult
    public static func sweepStaleBodyFiles(in directory: URL = defaultBodyDirectory,
                                           olderThan age: TimeInterval = staleBodyFileAge,
                                           now: Date = Date()) -> Int {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        var removed = 0
        for file in files {
            guard let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
                  now.timeIntervalSince(modified) > age else { continue }
            if (try? FileManager.default.removeItem(at: file)) != nil { removed += 1 }
        }
        return removed
    }

    /// Puts `.transferring` entries whose transfer started more than `interval` ago back to
    /// `.pending`, so the next drain resends them — the server dedupes by capture id if the
    /// transfer did land. `drain` already does this on its own after
    /// `Outbox.staleTransferInterval`; this exists so UI tests can shorten that wait (a DEBUG
    /// launch argument in the app).
    @discardableResult
    public static func releaseStaleTransfers(in outbox: Outbox, olderThan interval: TimeInterval,
                                             now: Date = Date()) async -> Int {
        var released = 0
        for entry in await outbox.pending() where entry.status == .transferring {
            guard let started = entry.transferStartedAt, now.timeIntervalSince(started) > interval else { continue }
            await outbox.markPending(id: entry.id, incrementAttempts: false)
            released += 1
        }
        return released
    }

    // MARK: - Internals

    private struct PreparedUpload {
        let request: URLRequest
        let file: URL
        let phase: BackgroundTransferPhase
        /// A body written for this upload (`nil` for a Storage upsert, which streams the staged
        /// file itself).
        let bodyFile: URL?

        func discardBody() {
            if let bodyFile { try? FileManager.default.removeItem(at: bodyFile) }
        }
    }

    private func prepareUpload(for entry: OutboxEntry, userId: UUID, accessToken: String) throws -> PreparedUpload {
        let phase: BackgroundTransferPhase = CaptureTransport.requiresTwoStep(entry, oneShotLimit: oneShotLimit) ? .storage : .capture
        return try prepareUpload(for: entry, phase: phase, userId: userId, accessToken: accessToken)
    }

    private func prepareUpload(for entry: OutboxEntry, phase: BackgroundTransferPhase, userId: UUID,
                               accessToken: String) throws -> PreparedUpload {
        if phase == .storage {
            let storage = try CaptureTransport.storageUpload(for: entry, userId: userId, accessToken: accessToken)
            guard FileManager.default.fileExists(atPath: storage.fileURL.path) else {
                throw CaptureError.invalidEntry("the staged file is missing")
            }
            return PreparedUpload(request: storage.request, file: storage.fileURL, phase: .storage, bodyFile: nil)
        }
        // Same guard as `CaptureAPI.submit`: an uploaded file must sit in the user's own folder.
        if entry.kind == .file, let filePath = entry.payload["file_path"],
           !filePath.hasPrefix("\(userId.uuidString.lowercased())/") {
            throw CaptureError.invalidEntry("file_path is outside the user's storage folder")
        }
        let prepared = try CaptureTransport.captureRequest(for: entry, accessToken: accessToken, bodyDirectory: bodyDirectory)
        return PreparedUpload(request: prepared.urlRequest, file: prepared.bodyFile, phase: .capture,
                              bodyFile: prepared.bodyFile)
    }

    /// The connected session, created on first use. `nil` while a session this process
    /// invalidated is still finishing its tasks (a second object for the identifier would be
    /// undefined behavior).
    private func connect() -> (BackgroundUploadSession, Int)? {
        lock.withLock {
            if let session { return (session, sessionGeneration) }
            guard windingDownSession == nil else { return nil }
            sessionGeneration += 1
            let created = sessionFactory(self)
            session = created
            return (created, sessionGeneration)
        }
    }

    /// Applies one finished task to its entry. Request bodies for the entry are always deleted
    /// first (a follow-up task writes a fresh one); an entry that no longer exists is left alone
    /// (another lane finished it, or the Outbox was cleared). A `.parked` entry only ever moves
    /// forward: a success still completes/checkpoints it, a failure leaves it parked.
    func handleCompletion(taskDescription: String?, decision: BackgroundTransferDecision) async {
        guard let descriptor = BackgroundTransferDescriptor(taskDescription: taskDescription) else {
            log.error("completion for a task this code didn't create")
            return
        }
        discardBodyFiles(for: descriptor.entryId)
        let outbox = outboxForUser(descriptor.userId)
        guard let entry = await outbox.entry(id: descriptor.entryId) else {
            log.notice("completion for entry \(descriptor.entryId.uuidString, privacy: .public) (\(descriptor.phase.rawValue, privacy: .public)): already gone")
            return
        }
        log.notice("completion for entry \(descriptor.entryId.uuidString, privacy: .public) (\(descriptor.phase.rawValue, privacy: .public)): \(decision.logLabel, privacy: .public)")
        let parked = entry.status == .parked
        switch decision {
        case .complete(let result):
            await outbox.complete(id: entry.id)
            if postsCaptureNotifications, let item = result.item {
                await postStashItemCaptured(item, duplicate: result.duplicate, userId: descriptor.userId)
            }
        case .checkpointThenCapture:
            let path = CaptureTransport.storagePath(userId: descriptor.userId, entryId: entry.id,
                                                    fileExtension: CaptureTransport.storageFileExtension(for: entry))
            guard let checkpointed = await outbox.checkpoint(id: entry.id, filePath: path), !parked else { return }
            // Pending first: if this process dies before the follow-up starts, the next drain
            // sends the (small) JSON capture right away instead of waiting out a stale bound.
            await outbox.markPending(id: entry.id, incrementAttempts: false)
            guard let token = await completionToken(for: descriptor.userId) else { return }
            await restartTransfer(checkpointed, phase: .capture, userId: descriptor.userId, token: token,
                                  refreshed: false, outbox: outbox)
        case .refreshTokenAndRetry:
            guard !parked else { return }
            guard let token = await completionToken(for: descriptor.userId) else {
                // No session for that user any more (signed out) — the app sends it when it has one.
                await outbox.markPending(id: entry.id, incrementAttempts: false)
                return
            }
            await restartTransfer(entry, phase: descriptor.phase, userId: descriptor.userId, token: token,
                                  refreshed: true, outbox: outbox)
        case .park:
            await outbox.park(id: entry.id)
        case .retry(let countsAsAttempt):
            guard !parked else { return }
            await outbox.markPending(id: entry.id, incrementAttempts: countsAsAttempt)
        case .retryTwoStep:
            guard !parked else { return }
            await flagForTwoStep(entry.id, in: outbox)
        }
    }

    /// The token completions of this wake use for `userId`: fetched once (`accessTokenForUser`,
    /// bounded by `completionTokenTimeout` in the app/extension) by the first completion that
    /// needs one, then reused by every later one — `nil` included, so a fetch that came up empty
    /// isn't waited on again for each entry (they stay `.pending` for the app's drain). Final wave
    /// review: one deadline per wake, not one per completion.
    private func completionToken(for userId: UUID) async -> String? {
        let now = Date()
        let fetch = lock.withLock { () -> Task<String?, Never> in
            if let cached = completionTokens[userId],
               now.timeIntervalSince(cached.startedAt) < Self.completionTokenReuseInterval {
                return cached.fetch
            }
            let fetchToken = self.accessTokenForUser
            let fetch = Task { await fetchToken(userId) }
            completionTokens[userId] = (fetch, now)
            return fetch
        }
        return await fetch.value
    }

    /// Starts `phase` for `entry` as a new task in this process's session, with `token`: the
    /// two-step lane's second half (a JSON capture carrying `file_path`, after the Storage upsert
    /// landed) or the one retry of a phase whose token was rejected (`refreshed`). When this
    /// process's session is already winding down (the app handles events, then invalidates), the
    /// entry is sent in the foreground instead. Nothing here counts an attempt.
    private func restartTransfer(_ entry: OutboxEntry, phase: BackgroundTransferPhase, userId: UUID, token: String,
                                 refreshed: Bool, outbox: Outbox) async {
        guard let session = lock.withLock({ self.session }) else {
            await outbox.markPending(id: entry.id, incrementAttempts: false)
            await foregroundSend(outbox, entry.id, userId, token)
            return
        }
        do {
            let upload = try prepareUpload(for: entry, phase: phase, userId: userId, accessToken: token)
            guard !(await outbox.markTransferring(ids: [entry.id], phase: phase)).isEmpty else {
                upload.discardBody()
                return
            }
            let descriptor = BackgroundTransferDescriptor(userId: userId, entryId: entry.id, phase: phase,
                                                          refreshed: refreshed)
            session.startUpload(upload.request, fromFile: upload.file, taskDescription: descriptor.taskDescription)
            log.notice("restart: entry \(entry.id.uuidString, privacy: .public) phase \(phase.rawValue, privacy: .public) (token refreshed: \(refreshed))")
        } catch {
            await outbox.markPending(id: entry.id, incrementAttempts: false)
        }
    }

    /// `.pending` with an attempt counted, and at least `CaptureAPI.oneShotMaxAttempts` attempts
    /// in all — exactly the condition under which `CaptureTransport.requiresTwoStep` routes a
    /// file entry's next send (drain, `sendNow`, or a later background start) through Storage.
    private func flagForTwoStep(_ id: UUID, in outbox: Outbox) async {
        await outbox.markPending(id: id, incrementAttempts: true)
        for _ in 0..<CaptureAPI.oneShotMaxAttempts {
            guard let entry = await outbox.entry(id: id), entry.status == .pending,
                  entry.attempts < CaptureAPI.oneShotMaxAttempts else { return }
            await outbox.markPending(id: id, incrementAttempts: true)
        }
    }

    /// Deletes every request body written for `entryId` (`CaptureTransport` names them
    /// `<capture_id>-<uuid>.<ext>`, and the capture id is the lowercased entry id).
    private func discardBodyFiles(for entryId: UUID) {
        let prefix = entryId.uuidString.lowercased() + "-"
        let files = (try? FileManager.default.contentsOfDirectory(at: bodyDirectory, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.lastPathComponent.hasPrefix(prefix) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    /// `urlSessionDidFinishEvents`, after every completion delivered before it has been applied:
    /// if the system is waiting on a handler (the app was woken for these events), invalidate the
    /// session — `finishTasksAndInvalidate`, so tasks still running (e.g. a follow-up capture)
    /// finish in the daemon — and call the handler on the main queue. With no handler waiting
    /// (the extension), stay connected: invalidating there could strand a `start` in progress.
    func finishEvents(for finished: BackgroundUploadSession) async {
        let (handlers, invalidate) = lock.withLock { () -> ([() -> Void], Bool) in
            // The wake is over: its token answer isn't reused by the next one.
            completionTokens = [:]
            let handlers = eventsCompletionHandlers
            eventsCompletionHandlers = []
            guard !handlers.isEmpty, let session, session === finished else { return (handlers, false) }
            self.session = nil
            windingDownSession = finished
            return (handlers, true)
        }
        if invalidate {
            log.notice("finishEvents: invalidating (finishTasksAndInvalidate) and calling \(handlers.count) handler(s)")
            finished.finishTasksAndInvalidate()
        }
        callOnMain(handlers)
    }

    /// `urlSession(_:didBecomeInvalidWithError:)`. A session this process invalidated is simply
    /// forgotten. A connected session lost unexpectedly (typically
    /// `NSURLErrorBackgroundSessionInUseByAnotherProcess`) marks its generation lost — its tasks
    /// won't report here — and releases any events handler waiting on it: those events go to the
    /// process that is connected, or wake the app again later.
    func sessionDidBecomeInvalid(_ invalid: BackgroundUploadSession, error: Error?) {
        let orphanedHandlers = lock.withLock { () -> [() -> Void] in
            // One session at a time, so every body still kept belonged to this one.
            responseBodies = [:]
            truncatedResponses = []
            if windingDownSession === invalid { windingDownSession = nil }
            guard session === invalid else { return [] }
            session = nil
            lostGenerations.insert(sessionGeneration)
            let handlers = eventsCompletionHandlers
            eventsCompletionHandlers = []
            return handlers
        }
        if let error {
            log.error("session invalidated: \((error as NSError).domain, privacy: .public) \((error as NSError).code)")
        }
        callOnMain(orphanedHandlers)
    }

    private func callOnMain(_ handlers: [() -> Void]) {
        guard !handlers.isEmpty else { return }
        let box = HandlerBox(handlers: handlers)
        DispatchQueue.main.async { box.handlers.forEach { $0() } }
    }

    /// Serializes completion work in delivery order (the delegate callbacks are synchronous; the
    /// Outbox is an actor), so `urlSessionDidFinishEvents` — enqueued after every completion it
    /// follows — only runs once they're all applied.
    @discardableResult
    func enqueue(_ work: @escaping @Sendable () async -> Void) -> Task<Void, Never> {
        lock.withLock {
            let previous = workTail
            let task = Task {
                await previous?.value
                await work()
            }
            workTail = task
            return task
        }
    }

    /// Returns once every completion enqueued so far (and any enqueued while waiting) is applied.
    func waitForIdle() async {
        while true {
            let tail = lock.withLock { workTail }
            await tail?.value
            if lock.withLock({ workTail }) == tail { return }
        }
    }

    // MARK: Delegate bridging (testable without a real task)

    func didReceive(_ data: Data, forTask taskIdentifier: Int) {
        lock.withLock {
            var body = responseBodies[taskIdentifier, default: Data()]
            let room = Self.maxResponseBodyBytes - body.count
            if data.count > room {
                body.append(data.prefix(max(0, room)))
                truncatedResponses.insert(taskIdentifier)
            } else {
                body.append(data)
            }
            responseBodies[taskIdentifier] = body
        }
    }

    func didComplete(taskIdentifier: Int, taskDescription: String?, statusCode: Int?, error: Error?) {
        let (body, truncated) = lock.withLock {
            (responseBodies.removeValue(forKey: taskIdentifier) ?? Data(),
             truncatedResponses.remove(taskIdentifier) != nil)
        }
        let descriptor = BackgroundTransferDescriptor(taskDescription: taskDescription)
        let decision = BackgroundTransferDecision.decide(phase: descriptor?.phase ?? .capture, statusCode: statusCode,
                                                         body: body, error: error, bodyTruncated: truncated,
                                                         afterTokenRefresh: descriptor?.refreshed ?? false)
        enqueue { [weak self] in
            await self?.handleCompletion(taskDescription: taskDescription, decision: decision)
        }
    }

    func didFinishEvents(for session: BackgroundUploadSession) {
        enqueue { [weak self] in await self?.finishEvents(for: session) }
    }
}

extension BackgroundCaptureTransfers: URLSessionDataDelegate {
    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        didReceive(data, forTask: dataTask.taskIdentifier)
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        didComplete(taskIdentifier: task.taskIdentifier, taskDescription: task.taskDescription,
                    statusCode: (task.response as? HTTPURLResponse)?.statusCode, error: error)
    }

    public func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        didFinishEvents(for: session)
    }

    public func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) {
        sessionDidBecomeInvalid(session, error: error)
    }
}

/// Carries the system's (non-`Sendable`) completion handlers to the main queue.
private struct HandlerBox: @unchecked Sendable {
    let handlers: [() -> Void]
}
