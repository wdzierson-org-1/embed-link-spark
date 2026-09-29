import Foundation

/// One persisted capture. Plan 15: EVERY iOS capture (composer, voice note, share extension) is
/// written here FIRST and then sent with `capture_id = id` (lowercased) — the entry id is the
/// server-side idempotency key, so any retry of this entry, from any process, at any time, resolves
/// to the same single item.
///
/// `payload` keys (all strings — the file format predates typed payloads): `content`, `title`,
/// `url`, `is_public` ("true"/"false"), `attributes_json` (the attributes object as a JSON string),
/// `remind_at`; for `.file`: `mime_type`, `file_size`, `file_name` (the user-facing original name,
/// plan 15), `local_file_path` (bytes on this device — staged share, staged composer attachment, or
/// a voice recording) and/or `file_path` (bytes already in Storage). When both are present (a
/// two-step checkpoint keeps the local reference until the local copy is deleted), `file_path`
/// wins everywhere.
public struct OutboxEntry: Codable, Identifiable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable { case note, url, file }
    /// - `pending`: `drain` sends it.
    /// - `parked` (Plan 14 T3): `drain` already got HTTP 403 `{"error":"subscription_required"}`
    ///   for it — the account can't add content right now, which no retry can fix, so it's skipped
    ///   until `unparkAll` flips it back (see that method for who calls it and when).
    /// - `transferring` (plan 15): a background `URLSession` transfer owns it (share extension,
    ///   Task 4) since `transferStartedAt`. `drain` leaves it alone until that is older than
    ///   `Outbox.staleTransferInterval` (or missing), then resends it — safe, because the server
    ///   dedupes by capture id if the transfer actually landed.
    public enum Status: String, Codable, Sendable { case pending, parked, transferring }
    /// Which half of a capture a background transfer is carrying (plan 15 Task 4): the `capture`
    /// request itself, or the two-step lane's Storage upload of a big file.
    public enum TransferPhase: String, Codable, Sendable, CaseIterable { case capture, storage }
    public var id: UUID
    public var kind: Kind
    public var payload: [String: String]
    public var createdAt: Date
    public var attempts: Int
    public var status: Status
    public var transferStartedAt: Date?
    /// The phase of the background transfer that owns a `.transferring` entry (`nil` when not
    /// known — e.g. between enqueue and the transfer's start). A Storage upload gets a longer
    /// stale bound (`Outbox.staleInterval(for:)`).
    public var transferPhase: TransferPhase?

    public init(id: UUID, kind: Kind, payload: [String: String], createdAt: Date, attempts: Int,
                status: Status = .pending, transferStartedAt: Date? = nil, transferPhase: TransferPhase? = nil) {
        self.id = id
        self.kind = kind
        self.payload = payload
        self.createdAt = createdAt
        self.attempts = attempts
        self.status = status
        self.transferStartedAt = transferStartedAt
        self.transferPhase = transferPhase
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, payload, createdAt, attempts, status, transferStartedAt, transferPhase
    }

    /// Custom `Decodable` so an entry written to disk by an OLDER build still decodes: no `status`
    /// key (pre-plan-14) → `.pending`; no `transferStartedAt`/`transferPhase` (pre-plan-15) →
    /// `nil`. Entry ids were always UUIDs, so every old entry already carries a valid idempotency
    /// key — no migration. `encode(to:)` stays compiler-synthesized, so a re-persisted entry always
    /// carries an explicit `status` (and `transferStartedAt`/`transferPhase` whenever set).
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        kind = try container.decode(Kind.self, forKey: .kind)
        payload = try container.decode([String: String].self, forKey: .payload)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        attempts = try container.decode(Int.self, forKey: .attempts)
        status = try container.decodeIfPresent(Status.self, forKey: .status) ?? .pending
        transferStartedAt = try container.decodeIfPresent(Date.self, forKey: .transferStartedAt)
        transferPhase = try container.decodeIfPresent(TransferPhase.self, forKey: .transferPhase)
    }
}

/// How one `Outbox.sendNow` (or one entry of a `drain` pass) ended.
public enum OutboxSendResult: Sendable, Equatable {
    /// The server has the capture (new, or `duplicate: true` for an earlier attempt that landed);
    /// the entry, its claim, and its local file are gone.
    case sent(CaptureResult)
    /// HTTP 403 `subscription_required` — parked until `unparkAll`.
    case parked
    /// Still queued for a later pass: the send failed (`attempts` += 1), or the server reported the
    /// same capture id already in progress (409, `attempts` unchanged).
    case pending
    /// Not attempted: another process/pass holds its claim, or a background transfer owns it.
    case inFlight
    /// No such entry any more (already sent by someone else, or cleared).
    case notFound
    /// Permanently dropped: its `local_file_path` no longer exists, so there are no bytes left to
    /// send anywhere.
    case dropped
}

/// Cross-process claim sidecar (Plan 5 Task 3): `<entryId>.claim`, written and read next to the
/// entry it guards. Existence alone is the mutex — `Outbox.claimEntry` creates it with
/// `Data.write(options: [.withoutOverwriting])`, which maps to POSIX `O_EXCL` on APFS, so at most
/// one of any number of concurrent creators targeting the same `id` ever succeeds. The fields
/// inside never arbitrate ownership; they only decide whether a claim has gone stale (see
/// `Outbox.acquireClaim`: too old, or — plan 15 — left by a previous process of the app itself).
private struct OutboxClaim: Codable, Sendable {
    let owner: String
    let claimedAt: Date
}

/// Who stamps a claim: `"<bundle id or process name>#<pid>"` (the on-disk format every build has
/// written). `isSingleProcessApp` is true only in the main app — ONE process at a time, so a claim
/// carrying the app's own name but another pid can only have been left by a previous app process
/// that died mid-send (force-quit, crash, jetsam), and is reclaimed at once instead of blocking
/// that entry for `staleClaimInterval`. Claims by any OTHER owner (the share extension, whose
/// processes can overlap the app's) keep the plain age rule.
struct ClaimOwner: Sendable, Equatable {
    let name: String
    let pid: Int32
    let isSingleProcessApp: Bool

    var stamp: String { "\(name)#\(pid)" }

    static let current = ClaimOwner(
        name: Bundle.main.bundleIdentifier ?? ProcessInfo.processInfo.processName,
        pid: ProcessInfo.processInfo.processIdentifier,
        isSingleProcessApp: Bundle.main.bundleURL.pathExtension == "app")

    /// Whether `stamp` names this same app in a different (therefore dead) process.
    func isDeadPredecessor(ofStamp stamp: String) -> Bool {
        guard isSingleProcessApp, let hash = stamp.lastIndex(of: "#"),
              let pid = Int32(stamp[stamp.index(after: hash)...]) else { return false }
        return stamp[..<hash] == name && pid != self.pid
    }
}

/// One JSON file per queued capture. Survives crashes and offline periods. See
/// `defaultDirectory` below for how the directory itself is resolved (per-user, App-Group-backed
/// since Plan 5 Task 2) and `drain` for the claim protocol (Plan 5 Task 3) that lets the app and
/// the share extension safely share one such directory without double-sending an entry.
///
/// Plan 15: every send goes through the idempotent `capture` endpoint (`CaptureAPI.submit`) keyed
/// by the entry id. A `.file` entry still holding its bytes locally rides ONE multipart request
/// when the file is ≤ `CaptureAPI.oneShotFileLimit`; a bigger one goes two-step — upload to the
/// deterministic `<uid>/<entryId>.<ext>` Storage path (upsert), checkpoint `file_path` to disk,
/// then a JSON capture. `sendNow` is the single-entry path the composer and share sheet use right
/// after enqueueing; `drain` is the batch path; the `mark…`/`park`/`complete`/`checkpoint`
/// helpers are for the background-transfer delegate (Task 4).
public actor Outbox {
    private let directory: URL
    private var isDraining = false
    private let now: @Sendable () -> Date

    /// How long a claim sidecar is honored before `drain` treats its owner as dead (crashed,
    /// force-quit, or killed by the OS mid-upload) and reclaims the entry for itself. There's no
    /// liveness signal beyond the sidecar's age — a process holding a claim never renews it — so
    /// this is a blunt timeout, not a lease with heartbeats: comfortably longer than any single
    /// entry's processing should ever legitimately take (including the local-file lane's upload
    /// step), while short enough that a genuinely abandoned claim doesn't block an entry forever.
    private static let staleClaimInterval: TimeInterval = 600

    /// Plan 15: how long a `.transferring` entry is left to its background transfer before `drain`
    /// resends it itself. A resend is always safe — the server dedupes by capture id — this only
    /// bounds how long a transfer that silently died (or never started) can delay a capture.
    public static let staleTransferInterval: TimeInterval = 600

    /// Plan 15 review: the bound for a background Storage upload of a big file that hasn't been
    /// checkpointed yet. Such an upload can legitimately run for the background session's whole
    /// resource timeout (3600 s) on a slow network; resending it after 10 minutes would upload the
    /// same file twice. Once its bytes are checkpointed (`file_path`), only the short JSON capture
    /// is left and `staleTransferInterval` applies again.
    public static let staleStorageTransferInterval: TimeInterval = 3600 + 300

    /// The stale bound for `entry`'s background transfer (see the two intervals above).
    public static func staleInterval(for entry: OutboxEntry) -> TimeInterval {
        entry.transferPhase == .storage && entry.payload["file_path"] == nil
            ? staleStorageTransferInterval : staleTransferInterval
    }

    /// Whether `drain`/`sendNow` would send `entry` at `now`: `.pending` always; `.transferring`
    /// once its transfer is stale (or was never stamped); `.parked` never. Public so the app can
    /// decide whether a drain is worth starting at all.
    public static func isEligibleForSend(_ entry: OutboxEntry, now: Date) -> Bool {
        switch entry.status {
        case .pending: return true
        case .parked: return false
        case .transferring:
            guard let started = entry.transferStartedAt else { return true }
            return now.timeIntervalSince(started) > staleInterval(for: entry)
        }
    }

    /// How long a claim sidecar with NO matching entry is left alone before `sweepOrphanClaims`
    /// (Task 4) treats it as inert clutter rather than a claim mid-cleanup by its own owning
    /// process. Unrelated to `staleClaimInterval` above (that one governs claims whose entry is
    /// still PENDING and eligible for `drain` to reclaim and retry); this one only ever applies to
    /// a claim whose entry is already gone entirely, so it only needs to outlast the ordinary,
    /// microseconds-wide gap between `drain` deleting an entry and releasing its claim — 60s is
    /// ample margin without waiting anywhere near as long as a genuine stale-drain reclaim does.
    /// Deliberately the same NUMBER `sweepOrphans`'s young-RECORDING skip uses
    /// (`recordingSweepGracePeriod`), per the task brief — not because the two share a mechanism,
    /// just because both are "give an in-flight local operation a full minute before treating its
    /// leftovers as abandoned." (Staged files get far longer — `stagedFileSweepGracePeriod`.)
    private static let orphanClaimGracePeriod: TimeInterval = 60

    /// Who this instance stamps its claims as (bundle id or process name, plus pid) — see
    /// `ClaimOwner`. The app and the share extension are separate processes/bundles over the same
    /// App Group directory, so their claims are always distinguishable.
    private let claimOwner: ClaimOwner

    /// - Parameter now: Injectable for tests (`testStaleClaimIsReclaimed` backdates a claim, and
    ///   the plan-15 transfer tests backdate `transferStartedAt`, by constructing an `Outbox` whose
    ///   `now` returns a past instant). Defaults to the current time.
    public init(directory: URL,
                // A bare `Date.init` reference triggers "converting non-Sendable function value
                // to '@Sendable () -> Date' may introduce data races" on this toolchain — the
                // same quirk `drain`'s `upload` parameter default already works around by wrapping
                // in a closure literal instead of passing the function value directly.
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.init(directory: directory, now: now, claimOwner: .current)
    }

    /// Test seam: `claimOwner` stands in for "a claim stamped by another process" (a previous app
    /// process, or the share extension) without real OS processes.
    init(directory: URL, now: @escaping @Sendable () -> Date = { Date() }, claimOwner: ClaimOwner) {
        self.directory = directory
        self.now = now
        self.claimOwner = claimOwner
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Per-user Outbox root: `.../Application Support/StashOutbox/<uid-lowercased>`.
    ///
    /// Fix for a Critical final-review finding: this used to be a single directory shared by
    /// every account that ever signed into the device (`.../StashOutbox`, no user segment). The
    /// composer drains the Outbox with whatever session's JWT is CURRENT at drain time — not
    /// whichever user's session was current when an entry was queued — so a note or URL captured
    /// offline under user A survived a sign-out/sign-in as user B and was silently created in B's
    /// account on the next drain. Scoping the directory by user id closes that: user B's `Outbox`
    /// resolves to a directory user A's queued entries were never written into, so a drain can
    /// never cross the account boundary no matter whose session happens to be active.
    ///
    /// Plan 5 Task 2: now resolves through `AppGroup.userScopedURL`, which moves this directory
    /// into the shared App Group container when the app is entitled (falling back to the exact
    /// old Application Support formula otherwise, e.g. `swift test`) — so the share extension
    /// can enqueue into the same Outbox the app drains. This preserves the per-user segment
    /// described above; collapsing back to one shared directory across accounts would reopen the
    /// leak. A one-time `AppGroup.migrateLegacyDirectory` call relocates any entries already
    /// queued at the pre-Task-2 location — a no-op once moved, and a no-op (guaranteed, since the
    /// two paths are then identical) wherever the App Group entitlement isn't active.
    public static func defaultDirectory(userId: UUID) -> URL {
        let destination = AppGroup.userScopedURL("StashOutbox", userId: userId)
        AppGroup.migrateLegacyDirectory(from: AppGroup.legacyUserScopedURL("StashOutbox", userId: userId),
                                        to: destination)
        return destination
    }

    // MARK: - Enqueue / read

    /// Persists a new entry and returns it (its `id` is the capture id every send of it will use).
    ///
    /// `status` (Plan 14 fix wave B, #8) lets a caller enqueue an entry that's already known to be
    /// gated (`.parked`); plan 15's share extension enqueues `.transferring` entries it is about to
    /// hand to a background session (`transferStartedAt` is stamped here). Defaults to `.pending`.
    @discardableResult
    public func enqueue(_ kind: OutboxEntry.Kind, payload: [String: String],
                        status: OutboxEntry.Status = .pending) throws -> OutboxEntry {
        let entry = OutboxEntry(id: UUID(), kind: kind, payload: payload, createdAt: Date(), attempts: 0,
                                status: status, transferStartedAt: status == .transferring ? now() : nil)
        let data = try JSONEncoder().encode(entry)
        try data.write(to: fileURL(for: entry.id), options: .atomic)
        return entry
    }

    /// Every entry on disk regardless of status (pending, parked, transferring), oldest first.
    public func pending() -> [OutboxEntry] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.pathExtension == "json" }   // exclude `.claim` sidecars (Task 3)
            .compactMap { try? JSONDecoder().decode(OutboxEntry.self, from: Data(contentsOf: $0)) }
            .sorted { $0.createdAt < $1.createdAt }
    }

    /// The entry with `id`, read fresh from disk (another process may have changed it).
    public func entry(id: UUID) -> OutboxEntry? {
        guard let data = try? Data(contentsOf: fileURL(for: id)) else { return nil }
        return try? JSONDecoder().decode(OutboxEntry.self, from: data)
    }

    // MARK: - Send

    /// Plan 15: sends ONE entry right now — the composer/share-sheet path immediately after
    /// `enqueue`. Takes the same cross-process claim `drain` does, so a concurrent drain (this
    /// process or another) can never send it twice at once; the capture id makes even a later
    /// resend harmless. Never sends a `.parked` entry or one a live background transfer owns.
    ///
    /// - Parameter upload: the two-step Storage lane, exactly as `drain`'s — `nil` streams through
    ///   `api.uploadFileToStorage` with this call's own `accessToken`.
    public func sendNow(id: UUID, api: CaptureAPI, userId: UUID, accessToken: String,
                        upload: (@Sendable (URL, String, String) async throws -> Void)? = nil) async -> OutboxSendResult {
        guard let snapshot = entry(id: id) else { return .notFound }
        if snapshot.status == .parked { return .parked }
        guard isEligibleForSend(snapshot) else { return .inFlight }
        guard acquireClaim(for: id) else { return .inFlight }
        guard let current = entry(id: id) else {
            releaseClaim(for: id)
            return .notFound
        }
        guard isEligibleForSend(current) else {
            releaseClaim(for: id)
            return current.status == .parked ? .parked : .inFlight
        }
        return await process(current, api: api, userId: userId, accessToken: accessToken,
                             upload: resolvedUpload(upload, api: api, accessToken: accessToken))
    }

    /// Sends every eligible entry (`.pending`, plus `.transferring` ones whose transfer went
    /// stale), oldest first; never `.parked`. Returns how many reached the server (including
    /// idempotent `duplicate` replays of captures an earlier, unanswered attempt already created).
    ///
    /// - Parameters:
    ///   - userId: builds the deterministic two-step Storage path (`<uid>/<entryId>.<ext>`).
    ///   - upload: the two-step lane's Storage upload (`fileURL`, `path`, `contentType`) — only ever
    ///     called for a `.file` entry whose local file needs two-step (`CaptureTransport
    ///     .requiresTwoStep`, or after a 413). `nil` (the default) streams through
    ///     `api.uploadFileToStorage` with THIS call's own `accessToken`; `StashApp` passes a
    ///     closure over `uploadToStorageFromFile` (same request, `x-upsert` included). Never given
    ///     loaded `Data` — the lane streams straight from disk.
    ///
    ///     `Optional`, not a plain closure with a default expression, because Swift default
    ///     argument expressions can't reference a sibling parameter (`accessToken`/`api` aren't
    ///     in scope there); resolving the default in the body lets it reuse the caller's token.
    public func drain(api: CaptureAPI, accessToken: String, userId: UUID,
                      upload: (@Sendable (URL, String, String) async throws -> Void)? = nil) async -> Int {
        guard !isDraining else { return 0 }
        isDraining = true
        defer { isDraining = false }
        let performUpload = resolvedUpload(upload, api: api, accessToken: accessToken)
        var sent = 0
        for snapshot in pending() where isEligibleForSend(snapshot) {
            // Cross-process claim (Task 3): acquired BEFORE any processing of this entry —
            // including the missing-local-file drop check and the upload lane below — so the
            // claim spans the entry's entire lifecycle for this pass. `false` means some other
            // in-flight send (another PROCESS — the share extension — a concurrent `sendNow`, or a
            // crashed run that hasn't gone stale yet) owns this entry; skip it this pass.
            guard acquireClaim(for: snapshot.id) else { continue }
            // Re-read under the claim: the snapshot may be stale (another process completed,
            // parked, or re-marked it between `pending()` and the claim).
            guard let current = entry(id: snapshot.id), isEligibleForSend(current) else {
                releaseClaim(for: snapshot.id)
                continue
            }
            if case .sent = await process(current, api: api, userId: userId, accessToken: accessToken,
                                          upload: performUpload) {
                sent += 1
            }
        }
        return sent
    }

    /// `.pending` always; `.transferring` once its background transfer is stale (or was never
    /// stamped); `.parked` never — see `Outbox.isEligibleForSend(_:now:)`.
    private func isEligibleForSend(_ entry: OutboxEntry) -> Bool {
        Self.isEligibleForSend(entry, now: now())
    }

    private func resolvedUpload(_ upload: (@Sendable (URL, String, String) async throws -> Void)?, api: CaptureAPI,
                                accessToken: String) -> @Sendable (URL, String, String) async throws -> Void {
        upload ?? { fileURL, path, contentType in
            try await api.uploadFileToStorage(fileURL, path: path, contentType: contentType, accessToken: accessToken)
        }
    }

    /// One claimed entry, start to finish. The caller holds the entry's claim; every path out of
    /// here releases it (or deletes it along with the entry).
    private func process(_ claimed: OutboxEntry, api: CaptureAPI, userId: UUID, accessToken: String,
                         upload: @Sendable (URL, String, String) async throws -> Void) async -> OutboxSendResult {
        var entry = claimed
        if entry.kind == .file, entry.payload["file_path"] == nil, let localPath = entry.payload["local_file_path"],
           !FileManager.default.fileExists(atPath: localPath) {
            // Plan 15 review: re-read before dropping — a background Storage upload may have
            // checkpointed this entry (`file_path`) and deleted the local copy since the snapshot;
            // such an entry only needs its JSON capture.
            if let fresh = self.entry(id: entry.id), fresh.payload["file_path"] != nil {
                entry = fresh
            } else {
                // Permanent failure: the local bytes are gone (e.g. the app's on-disk state was
                // cleared before this entry was ever sent). Unlike every other failure below — each
                // retried, never dropped — retrying can never succeed here, so the entry is dropped.
                print("Outbox: dropping entry \(entry.id) — its local file is missing, it can never be sent")
                try? FileManager.default.removeItem(at: fileURL(for: entry.id))
                releaseClaim(for: entry.id)
                return .dropped
            }
        }
        do {
            if CaptureTransport.requiresTwoStep(entry, oneShotLimit: api.oneShotLimit) {
                entry = try await uploadAndCheckpoint(entry, userId: userId, upload: upload)
            }
            let result: CaptureResult
            do {
                result = try await api.submit(entry: entry, userId: userId, accessToken: accessToken)
            } catch CaptureError.fileTooLarge where entry.payload["file_path"] == nil && entry.payload["local_file_path"] != nil {
                // The one-shot body was refused as too large (the endpoint's own guard, or a
                // gateway limit): same entry, same capture id, straight through the two-step lane.
                entry = try await uploadAndCheckpoint(entry, userId: userId, upload: upload)
                result = try await api.submit(entry: entry, userId: userId, accessToken: accessToken)
            }
            removeEntryAndLocalFile(entry)
            if let item = result.item {
                await postStashItemCaptured(item, duplicate: result.duplicate, userId: userId)
            }
            return .sent(result)
        } catch CaptureError.subscriptionRequired {
            // Plan 14 T3: the account can't add content right now, which no retry of this send can
            // fix — park it (attempts untouched: not a failure of the send itself).
            updateStatusIfPresent(entry.id, to: .parked, countingAttempt: false)
            releaseClaim(for: entry.id)
            return .parked
        } catch CaptureError.inProgress {
            // Plan 15: another attempt with this capture id is mid-flight server-side (e.g. a
            // background transfer). Not a failure: stays pending, attempts unchanged; the next
            // pass gets the finished receipt back as `duplicate: true`.
            updateStatusIfPresent(entry.id, to: .pending, countingAttempt: false)
            releaseClaim(for: entry.id)
            return .pending
        } catch {
            updateStatusIfPresent(entry.id, to: .pending, countingAttempt: true)
            // Release even on failure (attempts still increments above) so the entry is
            // re-eligible immediately on the very next pass — by this process or another —
            // rather than waiting out `staleClaimInterval` for no reason.
            releaseClaim(for: entry.id)
            return .pending
        }
    }

    /// Plan 15 review: a failed or deferred send updates only the entry's status fields, on the
    /// entry as it is on disk NOW — never by writing back this send's older copy, which could
    /// undo a checkpoint a background Storage upload wrote meanwhile (the local copy is then gone,
    /// and the next pass would drop an entry whose bytes are safely in Storage).
    private func updateStatusIfPresent(_ id: UUID, to status: OutboxEntry.Status, countingAttempt: Bool) {
        guard var current = entry(id: id) else { return }
        current.status = status
        current.transferStartedAt = nil
        current.transferPhase = nil
        if countingAttempt { current.attempts += 1 }
        persistIfPresent(current)
    }

    /// The two-step lane's first half: streams the local file to the entry's deterministic Storage
    /// path (`x-upsert`, so a repeat after a lost response overwrites the same object), then
    /// checkpoints (`checkpointUploaded`) — returns the checkpointed entry.
    private func uploadAndCheckpoint(_ entry: OutboxEntry, userId: UUID,
                                     upload: @Sendable (URL, String, String) async throws -> Void) async throws -> OutboxEntry {
        guard let localPath = entry.payload["local_file_path"] else { return entry }
        let path = CaptureTransport.storagePath(userId: userId, entryId: entry.id,
                                                fileExtension: CaptureTransport.storageFileExtension(for: entry))
        try await upload(URL(fileURLWithPath: localPath), path, CaptureTransport.mimeType(for: entry))
        return checkpointUploaded(entry, filePath: path)
    }

    /// Records "these bytes are in Storage at `filePath`" DURABLY before anything else happens
    /// (Critical, Plan 5 task review): `file_path` set, `file_size` captured if missing, written
    /// to disk — and only then is the local copy deleted. `file_path` takes precedence over
    /// `local_file_path` everywhere (the missing-file drop check, two-step routing, the request
    /// shape), so a process killed mid-`submit` relaunches to an already-uploaded entry that just
    /// retries the JSON capture — never re-uploads, never mistaken for a missing local file.
    ///
    /// Plan 15 review: `local_file_path` is KEPT alongside `file_path`, so the local copy stays
    /// referenced by its entry until it's actually gone — a process killed between the checkpoint
    /// and the delete can't leave an unreferenced file for `sweepOrphans` to re-enqueue under a
    /// second capture id. If the checkpoint can't be written (or the entry vanished), the local
    /// copy is left alone here; the returned entry still names it, so the success path
    /// (`removeEntryAndLocalFile`) deletes it.
    private func checkpointUploaded(_ entry: OutboxEntry, filePath: String) -> OutboxEntry {
        var checkpointed = entry
        if checkpointed.payload["file_size"] == nil, let size = CaptureTransport.localFileSize(of: entry) {
            checkpointed.payload["file_size"] = String(size)
        }
        checkpointed.payload["file_path"] = filePath
        if persistIfPresent(checkpointed), let localPath = checkpointed.payload["local_file_path"] {
            try? FileManager.default.removeItem(atPath: localPath)
        }
        return checkpointed
    }

    // MARK: - Transitions for the background-transfer delegate (plan 15, Task 4)

    /// Marks existing, non-parked entries `.transferring` from now (`transferStartedAt = now`) —
    /// e.g. when a follow-up task is started for them — recording the transfer's `phase` (it
    /// picks the stale bound, `staleInterval(for:)`). Returns the entries as persisted.
    @discardableResult
    public func markTransferring(ids: [UUID], phase: OutboxEntry.TransferPhase? = nil) -> [OutboxEntry] {
        var marked: [OutboxEntry] = []
        for id in ids {
            guard var entry = entry(id: id), entry.status != .parked else { continue }
            entry.status = .transferring
            entry.transferStartedAt = now()
            entry.transferPhase = phase
            persistIfPresent(entry)
            marked.append(entry)
        }
        return marked
    }

    /// Back to `.pending` (a transfer that couldn't start, failed, or got 409), optionally
    /// counting a failed attempt. No-op for an unknown id.
    public func markPending(id: UUID, incrementAttempts: Bool) {
        guard var entry = entry(id: id) else { return }
        entry.status = .pending
        entry.transferStartedAt = nil
        entry.transferPhase = nil
        if incrementAttempts { entry.attempts += 1 }
        persistIfPresent(entry)
    }

    /// Parks an entry (403 `subscription_required`). No-op for an unknown id.
    public func park(id: UUID) {
        guard var entry = entry(id: id) else { return }
        entry.status = .parked
        entry.transferStartedAt = nil
        entry.transferPhase = nil
        persistIfPresent(entry)
    }

    /// Plan 15 review: rewrites an entry's payload in place (read fresh from disk, `transform`
    /// applied, persisted only if the entry still exists) — the share sheet adds a location that
    /// resolved after the entry was saved. Returns the updated entry, or `nil` for an unknown id.
    @discardableResult
    public func updatePayload(id: UUID, _ transform: ([String: String]) -> [String: String]) -> OutboxEntry? {
        guard var entry = entry(id: id) else { return nil }
        entry.payload = transform(entry.payload)
        return persistIfPresent(entry) ? entry : nil
    }

    /// Adds a location that resolved AFTER the capture was saved (the pin was still resolving at
    /// Save — share sheet and composer alike) to the entry's `attributes_json`, merged: a file's
    /// `media` and every other key stay as they are. Returns the updated entry, or `nil` when it no
    /// longer exists (already sent — its item simply has no location).
    @discardableResult
    public func attachLocation(_ location: CapturedLocation, to id: UUID) -> OutboxEntry? {
        guard let locationJSON = ItemAttributes(location: location).nonEmptyJSONObject?["location"] else {
            return entry(id: id)
        }
        return updatePayload(id: id) { payload in
            var payload = payload
            var attributes = CaptureTransport.attributesObject(from: payload["attributes_json"]) ?? [:]
            attributes["location"] = locationJSON
            if let data = try? JSONSerialization.data(withJSONObject: attributes),
               let json = String(data: data, encoding: .utf8) {
                payload["attributes_json"] = json
            }
            return payload
        }
    }

    /// The capture reached the server: deletes the entry, its claim sidecar, and its local file
    /// (staged share/attachment or recording), if any. Returns the removed entry (`nil` if it was
    /// already gone — e.g. `drain` finished it first; that's fine, the server deduped).
    @discardableResult
    public func complete(id: UUID) -> OutboxEntry? {
        guard let entry = entry(id: id) else {
            releaseClaim(for: id)
            return nil
        }
        removeEntryAndLocalFile(entry)
        return entry
    }

    /// The two-step lane's Storage upload for `id` landed at `filePath`: checkpoints it (see
    /// `checkpointUploaded`) so the follow-up JSON capture — and any later resend — never
    /// re-uploads. Returns the checkpointed entry (`nil` for an unknown id).
    @discardableResult
    public func checkpoint(id: UUID, filePath: String) -> OutboxEntry? {
        guard let entry = entry(id: id) else { return nil }
        return checkpointUploaded(entry, filePath: filePath)
    }

    // MARK: - Park / clear

    /// Flips every `.parked` entry back to `.pending` — called once `SubscriptionStore.refresh()`
    /// reports `canAddContent == true` again (see `CaptureComposerView`'s
    /// `.onChange(of: subscription.canAddContent)`, which constructs a fresh `Outbox` over this
    /// same directory and calls this before its own next `drainOutbox()`). Idempotent and cheap
    /// when nothing is parked — safe to call on every entitlement-restored signal, not just the
    /// first one after a park. Doesn't itself send anything; the very next `drain` picks up the
    /// now-`.pending` entries normally.
    ///
    /// - Returns: the number of entries unparked, for callers/tests that want to confirm work
    ///   actually happened.
    @discardableResult
    public func unparkAll() -> Int {
        var count = 0
        for var entry in pending() where entry.status == .parked {
            entry.status = .pending
            if let data = try? JSONEncoder().encode(entry) {
                try? data.write(to: fileURL(for: entry.id), options: .atomic)
                count += 1
            }
        }
        return count
    }

    /// Deletes every entry (and any claim sidecar) in this Outbox's directory outright, ignoring
    /// `status`/`attempts` entirely — used by account deletion
    /// (`SessionStore.completeAccountDeletion`) once the server has confirmed the account itself
    /// is gone: there is nothing left anywhere to ever send these to. Unlike `drain`, this never
    /// attempts a claim or a send first.
    public func clearAll() {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.pathExtension == "json" || file.pathExtension == "claim" {
            try? FileManager.default.removeItem(at: file)
        }
    }

    // MARK: - Persistence helpers

    /// Rewrites `entry` only if its file still exists — a status/attempts update must never
    /// resurrect an entry another process (or the background-transfer delegate) completed while
    /// this send was in flight. Returns whether the write happened.
    @discardableResult
    private func persistIfPresent(_ entry: OutboxEntry) -> Bool {
        let url = fileURL(for: entry.id)
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? JSONEncoder().encode(entry) else { return false }
        return (try? data.write(to: url, options: .atomic)) != nil
    }

    /// The capture reached the server: removes the local bytes FIRST, then the entry and its claim
    /// (plan 15 review). A process killed between the two leaves an entry whose local file is gone
    /// — the next pass drops it, or (checkpointed) replays it as a `duplicate` — never a local file
    /// with no entry, which `sweepOrphans` would re-enqueue under a NEW capture id (a second item).
    /// For the same reason, if the local file can't be deleted the entry is kept (still naming the
    /// file); its next send is an idempotent replay.
    private func removeEntryAndLocalFile(_ entry: OutboxEntry) {
        if let localPath = entry.payload["local_file_path"] {
            try? FileManager.default.removeItem(atPath: localPath)
            guard !FileManager.default.fileExists(atPath: localPath) else {
                print("Outbox: couldn't delete the local file of captured entry \(entry.id); keeping the entry")
                releaseClaim(for: entry.id)
                return
            }
        }
        try? FileManager.default.removeItem(at: fileURL(for: entry.id))
        releaseClaim(for: entry.id)
    }

    // MARK: - Claims

    /// Attempts to acquire ownership of `id` for this pass. Returns `true` if this call now owns
    /// the entry — either there was no existing claim, or there was a stale one this call just
    /// replaced — and `false` if a live claim exists (owned by this process's own earlier,
    /// still-in-flight attempt or, cross-process, by another one entirely), meaning the entry must
    /// be skipped this pass.
    ///
    /// Stale means older than `staleClaimInterval`, OR (plan 15 review) — in the app only — stamped
    /// by a previous process of the app itself (same name, different pid; see `ClaimOwner`): the
    /// app runs as one process at a time, so that owner is certainly dead, and a relaunch after a
    /// kill mid-send resends immediately instead of 10 minutes later.
    private func acquireClaim(for id: UUID) -> Bool {
        if claimEntry(id: id) { return true }
        // Creation failed: a claim sidecar already exists. Read it to decide whether it's stale;
        // an unreadable/corrupt sidecar is treated the same as a live one (conservative — never
        // double-process an entry just because its claim file looks odd).
        let url = claimFileURL(for: id)
        guard let data = try? Data(contentsOf: url),
              let claim = try? JSONDecoder().decode(OutboxClaim.self, from: data) else {
            return false
        }
        let expired = now().timeIntervalSince(claim.claimedAt) > Self.staleClaimInterval
        guard expired || claimOwner.isDeadPredecessor(ofStamp: claim.owner) else { return false }
        // Stale: the owning process almost certainly crashed or was force-quit mid-entry. Delete
        // the stale sidecar, then recreate it with the SAME `.withoutOverwriting` atomicity as a
        // fresh claim (`claimEntry` again) rather than assuming this call now owns it outright.
        // There's a tiny race window right here, between `removeItem` and that recreate, where a
        // second process independently polling the same stale claim could slip in — that's fine
        // and intentional, not a bug to close: exactly one of the two `claimEntry` calls wins the
        // O_EXCL create, and the loser's `false` return means it skips the entry this pass, same
        // as any ordinary live-claim contention.
        try? FileManager.default.removeItem(at: url)
        return claimEntry(id: id)
    }

    /// Removes the claim sidecar for `id`, if any. Called once an entry reaches a terminal state
    /// for this pass — sent, permanently dropped, parked, or retried-after-failure — so the entry
    /// is immediately re-eligible rather than waiting out `staleClaimInterval`.
    private func releaseClaim(for id: UUID) {
        try? FileManager.default.removeItem(at: claimFileURL(for: id))
    }

    /// Attempts to atomically create the claim sidecar for `id` (see `OutboxClaim`'s doc comment
    /// for why existence alone is the mutex). Returns `true` if this call created it — the entry
    /// is now owned by this process/instance for the remainder of this pass — or `false` if a
    /// claim already existed and this call therefore did nothing.
    ///
    /// `internal` (no `public`/`private`) rather than folded entirely into `drain`/`acquireClaim`:
    /// exposed so `OutboxTests` can simulate a second process's live claim by calling this
    /// directly from a separate `Outbox` instance over the same directory, without needing two
    /// real OS processes.
    ///
    /// Local-only note: `.withoutOverwriting`'s O_EXCL atomicity is a guarantee of the local
    /// filesystem (APFS) the App Group container lives on. It would not hold over iCloud Drive or
    /// a network filesystem — neither of which applies here (`AppGroup.containerURL()` is always a
    /// local App Group / Application Support directory, never an iCloud-backed one).
    ///
    /// Deliberately not `@discardableResult`: ignoring the outcome would be a bug at any call
    /// site (processing an entry without knowing whether this call actually owns it), so every
    /// caller — internal or in `OutboxTests` — is required to look at it.
    func claimEntry(id: UUID) -> Bool {
        let claim = OutboxClaim(owner: claimOwner.stamp, claimedAt: now())
        guard let data = try? JSONEncoder().encode(claim) else { return false }
        return (try? data.write(to: claimFileURL(for: id), options: .withoutOverwriting)) != nil
    }

    private func claimFileURL(for id: UUID) -> URL {
        directory.appending(path: "\(id.uuidString).claim")
    }

    /// Deletes stray `.claim` sidecars that have no matching `<id>.json` entry — the crash window
    /// this closes (Task 3 review carry, folded into Task 4's `sweepOrphans`): `drain` deletes a
    /// sent/permanently-dropped entry's `.json` a few lines before it releases that entry's claim,
    /// so a process killed in that narrow gap leaves an inert `.claim` file nothing will otherwise
    /// ever remove. A claim WITH a matching entry is left alone no matter its age — that's either
    /// a live claim or a stale-but-still-pending one `drain`'s own `acquireClaim` already knows how
    /// to reclaim; only a claim whose entry is entirely gone is this method's business. `internal`
    /// (no access modifier), same visibility rationale as `claimEntry`: called from `sweepOrphans`
    /// (same module) and exercised directly by tests via `@testable import`.
    ///
    /// - Parameter now: mirrors `drain`'s own injectable clock — see `orphanClaimGracePeriod`.
    /// - Returns: the count deleted. `sweepOrphans` deliberately does NOT fold this into its own
    ///   "entries created" return value (disclosed in task-4-report.md) — deleting an inert claim
    ///   file creates nothing.
    func sweepOrphanClaims(now: @Sendable () -> Date = { Date() }) -> Int {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        var deleted = 0
        for file in files where file.pathExtension == "claim" {
            let entryURL = file.deletingPathExtension().appendingPathExtension("json")
            guard !FileManager.default.fileExists(atPath: entryURL.path) else { continue }
            guard let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
                  now().timeIntervalSince(modified) >= Self.orphanClaimGracePeriod else { continue }
            try? FileManager.default.removeItem(at: file)
            deleted += 1
        }
        return deleted
    }

    private func fileURL(for id: UUID) -> URL {
        directory.appending(path: "\(id.uuidString).json")
    }
}
