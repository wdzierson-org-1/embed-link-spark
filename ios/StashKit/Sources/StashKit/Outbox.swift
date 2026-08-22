import Foundation

public struct OutboxEntry: Codable, Identifiable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable { case note, url, file }
    public var id: UUID
    public var kind: Kind
    public var payload: [String: String]
    public var createdAt: Date
    public var attempts: Int
}

/// Cross-process claim sidecar (Plan 5 Task 3): `<entryId>.claim`, written and read next to the
/// entry it guards. Existence alone is the mutex — `Outbox.claimEntry` creates it with
/// `Data.write(options: [.withoutOverwriting])`, which maps to POSIX `O_EXCL` on APFS, so at most
/// one of any number of concurrent creators targeting the same `id` ever succeeds. The fields
/// inside are diagnostic-only: nothing ever reads `owner` or `claimedAt` back to arbitrate
/// ownership, only to decide whether a claim has gone stale (see `Outbox.staleClaimInterval`).
private struct OutboxClaim: Codable, Sendable {
    let owner: String
    let claimedAt: Date
}

/// One JSON file per pending capture. Survives crashes and offline periods. See
/// `defaultDirectory` below for how the directory itself is resolved (per-user, App-Group-backed
/// since Plan 5 Task 2) and `drain` for the claim protocol (Plan 5 Task 3) that lets the app and
/// the share extension (Task 5+) safely share one such directory without double-sending an entry.
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

    /// How long a claim sidecar with NO matching entry is left alone before `sweepOrphanClaims`
    /// (Task 4) treats it as inert clutter rather than a claim mid-cleanup by its own owning
    /// process. Unrelated to `staleClaimInterval` above (that one governs claims whose entry is
    /// still PENDING and eligible for `drain` to reclaim and retry); this one only ever applies to
    /// a claim whose entry is already gone entirely, so it only needs to outlast the ordinary,
    /// microseconds-wide gap between `drain` deleting an entry and releasing its claim — 60s is
    /// ample margin without waiting anywhere near as long as a genuine stale-drain reclaim does.
    /// Deliberately the same NUMBER `sweepOrphans`'s own young-file skip uses, per the task brief —
    /// not because the two share a mechanism, just because both are "give an in-flight local
    /// operation a full minute before treating its leftovers as abandoned."
    private static let orphanClaimGracePeriod: TimeInterval = 60

    /// Diagnostic value stamped into a claim's `owner` field — never read back to decide
    /// ownership (the O_EXCL create is the actual mutex), but distinguishes which process holds a
    /// claim if one is ever inspected by hand. Bundle id (falls back to the bare process name
    /// when there's no bundle, e.g. the `swift test`/XCTest host) plus pid, so the app and the
    /// share extension — two separate processes/bundles that legitimately point at the same App
    /// Group directory — are always distinguishable from each other.
    private static let processOwner: String = {
        let name = Bundle.main.bundleIdentifier ?? ProcessInfo.processInfo.processName
        return "\(name)#\(ProcessInfo.processInfo.processIdentifier)"
    }()

    /// - Parameter now: Injectable for tests (`testStaleClaimIsReclaimed` backdates a claim by
    ///   constructing an `Outbox` whose `now` returns a past instant). Defaults to the current
    ///   time so no existing call site needs to change.
    public init(directory: URL,
                // A bare `Date.init` reference triggers "converting non-Sendable function value
                // to '@Sendable () -> Date' may introduce data races" on this toolchain — the
                // same quirk `drain`'s `upload` parameter default already works around by wrapping
                // in a closure literal instead of passing the function value directly.
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.directory = directory
        self.now = now
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
    /// (Task 5+) can enqueue into the same Outbox the app drains. This preserves the per-user
    /// segment described above; collapsing back to one shared directory across accounts would
    /// reopen the leak. A one-time `AppGroup.migrateLegacyDirectory` call relocates any entries
    /// already queued at the pre-Task-2 location (dev-stage: no real users yet, but a
    /// not-yet-drained entry from a developer's own test run would otherwise go silently
    /// invisible on the first App-Group-entitled launch) — a no-op once moved, and a no-op
    /// (guaranteed, since the two paths are then identical) wherever the App Group entitlement
    /// isn't active.
    public static func defaultDirectory(userId: UUID) -> URL {
        let destination = AppGroup.userScopedURL("StashOutbox", userId: userId)
        AppGroup.migrateLegacyDirectory(from: AppGroup.legacyUserScopedURL("StashOutbox", userId: userId),
                                        to: destination)
        return destination
    }

    public func enqueue(_ kind: OutboxEntry.Kind, payload: [String: String]) throws {
        let entry = OutboxEntry(id: UUID(), kind: kind, payload: payload, createdAt: Date(), attempts: 0)
        let data = try JSONEncoder().encode(entry)
        try data.write(to: fileURL(for: entry.id), options: .atomic)
    }

    public func pending() -> [OutboxEntry] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.pathExtension == "json" }   // exclude `.claim` sidecars (Task 3)
            .compactMap { try? JSONDecoder().decode(OutboxEntry.self, from: Data(contentsOf: $0)) }
            .sorted { $0.createdAt < $1.createdAt }
    }

    /// - Parameters:
    ///   - userId: Needed to build the fresh `makeUploadPath` a `local_file_path` entry uploads
    ///     to — see the `local_file_path` handling below.
    ///   - upload: Injectable for tests; `nil` (every real call site) resolves to the real
    ///     `uploadToStorageFromFile` using THIS call's own `accessToken`. Only ever called for a
    ///     `.file` entry whose payload contains `local_file_path` (a locally-staged/recorded file
    ///     not yet uploaded) — a `.file` entry with an already-uploaded `file_path` (Task 3) never
    ///     touches this closure. Task 4: takes the local file's `URL` directly, not a loaded
    ///     `Data` blob — `drain` streams straight from disk, never materializing a recording's or
    ///     staged share's full bytes in this process's memory.
    ///
    ///     `Optional`, not a plain closure with a default expression, because Swift default
    ///     argument expressions can't reference a sibling parameter (verified: `accessToken` isn't
    ///     in scope there) — the same constraint `CaptureViewModel`'s own `accessToken`-consuming
    ///     defaults sidestep by fetching independently instead. Resolving the real default inside
    ///     the function body (below) is what lets it reuse the CALLER's own `accessToken` — one
    ///     token fetch per `drain`, not a second independent one buried in a default closure.
    public func drain(api: CaptureAPI, accessToken: String, userId: UUID,
                      upload: (@Sendable (URL, String, String) async throws -> Void)? = nil) async -> Int {
        guard !isDraining else { return 0 }
        isDraining = true
        defer { isDraining = false }
        let performUpload: @Sendable (URL, String, String) async throws -> Void = upload ?? { fileURL, path, contentType in
            try await uploadToStorageFromFile(fileURL: fileURL, path: path, contentType: contentType,
                                              accessToken: accessToken)
        }
        var sent = 0
        for var entry in pending() {
            // Cross-process claim (Task 3): acquired BEFORE any processing of this entry —
            // including the missing-local-file drop check and the local-file upload lane below —
            // so the claim spans the entry's entire lifecycle for this pass, not just the final
            // `send`. `false` means some other in-flight drain (this process's own reentrant call
            // can't reach here at all, thanks to `isDraining` above, so in practice this is
            // another PROCESS — the share extension, Task 5+ — or a previous crashed run that
            // hasn't gone stale yet) already owns this entry; skip it and move on to the next one.
            guard acquireClaim(for: entry.id) else { continue }

            // Recording durability (Task 4): a `.file` entry can carry `local_file_path` instead
            // of (as well as, briefly) `file_path` — the app's recorder (Task 6) writes audio
            // straight to local disk via `RecordingStore` and enqueues before any network call
            // ever happens, so (unlike every other attachment, which is already uploaded by the
            // time `CaptureViewModel.prepare` enqueues it — Task 3) the upload itself has to
            // happen here, inside drain.
            let localPath = entry.kind == .file ? entry.payload["local_file_path"] : nil

            if let localPath, !FileManager.default.fileExists(atPath: localPath) {
                // Permanent failure: the local recording is gone (e.g. the app was force-quit and
                // its on-disk state got cleared before this entry was ever drained). There are no
                // bytes left anywhere to upload, so — unlike every other failure below, which is
                // retried (attempts += 1, entry rewritten to disk) — this entry is dropped
                // outright. Retrying can never succeed; keeping it around would just retry forever
                // for nothing.
                print("Outbox: dropping entry \(entry.id) — its local recording file is missing, upload can never succeed")
                try? FileManager.default.removeItem(at: fileURL(for: entry.id))
                releaseClaim(for: entry.id)
                continue
            }

            do {
                if let localPath {
                    let localURL = URL(fileURLWithPath: localPath)
                    let path = makeUploadPath(userId: userId, fileExtension: localURL.pathExtension)
                    try await performUpload(localURL, path, entry.payload["mime_type"] ?? "application/octet-stream")
                    entry.payload["file_path"] = path
                    entry.payload.removeValue(forKey: "local_file_path")
                    // Persist the transitioned entry to disk BEFORE deleting the local file or
                    // attempting `send` (Critical, task review fix round). `send` below is a
                    // network `await` — if the process is killed while it's suspended, no `catch`
                    // ever runs, so the ONLY record of "this upload already succeeded" that
                    // survives a relaunch is whatever's on disk at this exact point. Persisting
                    // here first — synchronously, before either of the next two operations —
                    // guarantees a relaunch's `pending()` sees an entry with `file_path` set and
                    // no `local_file_path`, i.e. an ordinary already-uploaded `.file` entry that
                    // just retries `addFile` (never re-uploads, and is never mistaken for the
                    // missing-local-file permanent-failure case above once the line below deletes
                    // the local copy).
                    if let checkpoint = try? JSONEncoder().encode(entry) {
                        try? checkpoint.write(to: fileURL(for: entry.id), options: .atomic)
                    }
                    // Only now is it safe to delete the local copy: a crash between the persist
                    // above and here just leaves a harmless, sweepable local file; a crash after
                    // here (including mid-`send`) is fully covered by the checkpoint already on
                    // disk.
                    try? FileManager.default.removeItem(at: localURL)
                }
                _ = try await send(entry, api: api, accessToken: accessToken)
                try? FileManager.default.removeItem(at: fileURL(for: entry.id))
                releaseClaim(for: entry.id)
                sent += 1
            } catch {
                entry.attempts += 1
                if let data = try? JSONEncoder().encode(entry) {
                    try? data.write(to: fileURL(for: entry.id), options: .atomic)
                }
                // Release even on failure (attempts still increments above) so the entry is
                // re-eligible immediately on the very next drain — by this process or another —
                // rather than waiting out `staleClaimInterval` for no reason.
                releaseClaim(for: entry.id)
            }
        }
        return sent
    }

    /// Attempts to acquire ownership of `id` for this `drain` pass. Returns `true` if this call
    /// now owns the entry — either there was no existing claim, or there was a stale one this
    /// call just replaced — and `false` if a live claim exists (owned by this process's own
    /// earlier, still-in-flight attempt or, cross-process, by another one entirely), meaning the
    /// entry must be skipped this pass.
    private func acquireClaim(for id: UUID) -> Bool {
        if claimEntry(id: id) { return true }
        // Creation failed: a claim sidecar already exists. Read it to decide whether it's stale;
        // an unreadable/corrupt sidecar is treated the same as a live one (conservative — never
        // double-process an entry just because its claim file looks odd).
        let url = claimFileURL(for: id)
        guard let data = try? Data(contentsOf: url),
              let claim = try? JSONDecoder().decode(OutboxClaim.self, from: data),
              now().timeIntervalSince(claim.claimedAt) > Self.staleClaimInterval else {
            return false
        }
        // Stale: the owning process almost certainly crashed or was force-quit mid-entry. Delete
        // the stale sidecar, then recreate it with the SAME `.withoutOverwriting` atomicity as a
        // fresh claim (`claimEntry` again) rather than assuming this call now owns it outright.
        // There's a tiny race window right here, between `removeItem` and that recreate, where a
        // second process independently polling the same stale claim could slip in — that's fine
        // and intentional, not a bug to close: exactly one of the two `claimEntry` calls wins the
        // O_EXCL create, and the loser's `false` return means it skips the entry this pass, same
        // as any ordinary live-claim contention. The delete itself isn't atomic with the recreate,
        // but the recreate is the step that actually decides ownership, and that one is.
        try? FileManager.default.removeItem(at: url)
        return claimEntry(id: id)
    }

    /// Removes the claim sidecar for `id`, if any. Called once an entry reaches a terminal state
    /// for this pass — sent, permanently dropped, or retried-after-failure — so the entry is
    /// immediately re-eligible rather than waiting out `staleClaimInterval`.
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
        let claim = OutboxClaim(owner: Self.processOwner, claimedAt: now())
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

    private func send(_ entry: OutboxEntry, api: CaptureAPI, accessToken: String) async throws -> Item {
        let isPublic = entry.payload["is_public"] == "true"
        let attributes = decodedAttributes(from: entry)
        switch entry.kind {
        case .note:
            return try await api.addNote(content: entry.payload["content"] ?? "",
                                         title: entry.payload["title"], isPublic: isPublic,
                                         attributes: attributes, accessToken: accessToken)
        case .url:
            return try await api.addURL(entry.payload["url"] ?? "",
                                        note: entry.payload["content"] ?? "", isPublic: isPublic,
                                        attributes: attributes, accessToken: accessToken)
        case .file:
            return try await api.addFile(path: entry.payload["file_path"] ?? "",
                                         mimeType: entry.payload["mime_type"] ?? "application/octet-stream",
                                         fileSize: entry.payload["file_size"].flatMap(Int.init),
                                         content: entry.payload["content"], isPublic: isPublic,
                                         attributes: attributes, accessToken: accessToken)
        }
    }

    /// Task 5: the counterpart to `CaptureViewModel.attributesPayloadString` — decodes the
    /// `attributes_json` string an entry was enqueued with (if any) back into a real
    /// `ItemAttributes`, so a drained entry sends the identical `attributes` object a live send
    /// would have. `nil` for an entry with no `attributes_json` key (the ordinary case: nothing
    /// was pinned/no media facts) or one that fails to decode (defensive — never crashes a drain
    /// over a malformed persisted string; the entry still sends, just without its attributes).
    private func decodedAttributes(from entry: OutboxEntry) -> ItemAttributes? {
        guard let json = entry.payload["attributes_json"], let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ItemAttributes.self, from: data)
    }

    private func fileURL(for id: UUID) -> URL {
        directory.appending(path: "\(id.uuidString).json")
    }
}
