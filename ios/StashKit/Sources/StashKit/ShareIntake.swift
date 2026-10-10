import Foundation

/// One already-materialized shared object, ready for `ShareIntake.submit` — the share extension's
/// own `NSItemProvider` → `SharedObject` mapping (Task 7's `ProviderLoader`) happens entirely
/// OUTSIDE this file: that loading is callback/main-actor-ish (`loadFileRepresentation`'s
/// completion runs off an Apple-owned queue, and `NSItemProvider` itself isn't `Sendable`), which
/// would make this whole type impossible to exercise under plain `swift test` if it lived here
/// too. By the time anything in this file sees a `.file`, its bytes are ALREADY durably on local
/// disk — staged via `StagedFileStore.stage`/`stagePreparedImage` — so `ShareIntake` never touches
/// `NSItemProvider`, never loads a whole file into memory, and has no idea what UTI any of this
/// came from.
public enum SharedObject: Equatable, Sendable {
    case url(String)
    case text(String)
    case file(stagedURL: URL, mimeType: String, fileName: String?, durationS: Double?)
}

/// Tally of a foreground send — `ShareIntake.submit`, or the share sheet's bounded fallback
/// (`sendInForeground`) — without inspecting individual units. (Plan 15 Task 4: the share sheet
/// itself no longer waits on sends, so it always confirms "Saved to Stash" once every unit is
/// in the Outbox; these counts are for callers and logs.)
///
/// Unlike `CaptureViewModel.CaptureOutcome`, there is no `.rejected`/`dropped` case here: every
/// `SharedObject.file` already has its bytes durably on local disk by the time `submit` ever sees
/// it, so no failure in this type is ever unsafe to leave in the Outbox. `saved + queued + failed`
/// always equals the count of objects `submit` was called with; nothing is ever silently dropped,
/// which is why `failed` exists at all (the Outbox write itself can fail — an unwritable/full disk
/// — and that must still be counted, never just logged).
public struct ShareIntakeResult: Equatable, Sendable {
    public var saved: Int
    public var queued: Int
    public var failed: Int

    public init(saved: Int = 0, queued: Int = 0, failed: Int = 0) {
        self.saved = saved
        self.queued = queued
        self.failed = failed
    }
}

/// The share extension's orchestration layer — StashKit's counterpart to `CaptureViewModel.submit`,
/// built for objects the OS already handed the extension (`SharedObject`) rather than a composer's
/// own typed text/attachments. Behavior-parity with the composer (Global Constraints, ethos:
/// single-object capture, note-on-first) is the whole point: a multi-item OS share is N objects,
/// not a user grouping decision, and saves as N items exactly like N composer attachments would.
///
/// Plan 15 — outbox-first: every object is written to the Outbox FIRST (its entry id is the
/// idempotency key the `capture` endpoint dedupes on), then either sent right away in the
/// foreground (`submit`, `Outbox.sendNow`) or — what the share sheet does since Task 4 — handed
/// to the shared background `URLSession` (`enqueueForTransfer` → `BackgroundCaptureTransfers`,
/// with `sendInForeground` as its bounded fallback). A failed or skipped send never drops data
/// and never blocks the share sheet: the entry just stays queued for the app's next drain.
public struct ShareIntake: Sendable {
    private let userId: UUID
    private let capture: CaptureAPI
    private let outbox: Outbox
    private let staging: StagedFileStore
    private let directSendLimit: Int
    private let accessToken: @Sendable () async throws -> String
    private let upload: (@Sendable (URL, String, String) async throws -> Void)?

    /// - Parameters:
    ///   - directSendLimit: `submit` sends a staged file live only when it's at most this many
    ///     bytes; a bigger one is left queued for the app (it would hold the share sheet open for
    ///     the whole upload). Background transfers (`enqueueForTransfer`) have no such limit.
    ///   - upload: the Outbox's two-step Storage lane (`Outbox.sendNow`) — `nil` streams through
    ///     `capture.uploadFileToStorage` with the send's own token. `Optional`, not a closure with
    ///     a default expression, because Swift default-argument expressions can't reference a
    ///     sibling parameter (`accessToken`).
    public init(
        userId: UUID,
        capture: CaptureAPI = CaptureAPI(),
        outbox: Outbox? = nil,
        staging: StagedFileStore? = nil,
        directSendLimit: Int = 8 * 1024 * 1024,
        accessToken: @escaping @Sendable () async throws -> String,
        upload: (@Sendable (URL, String, String) async throws -> Void)? = nil
    ) {
        self.userId = userId
        self.capture = capture
        self.outbox = outbox ?? Outbox(directory: Outbox.defaultDirectory(userId: userId))
        self.staging = staging ?? StagedFileStore(userId: userId)
        self.directSendLimit = directSendLimit
        self.accessToken = accessToken
        self.upload = upload
    }

    /// Enqueues every object (Outbox first), then sends each one right away in the foreground.
    ///
    /// - Parameters:
    ///   - objects: Already-materialized shared objects. No reordering happens HERE (unlike
    ///     `CaptureViewModel.route()`, which always moves a detected URL to the front) —
    ///     `objects[0]` is unconditionally "the first object" for note-attachment purposes. Task 7:
    ///     that URL-first ordering decision does still apply to a share, just one layer up — see
    ///     `reorderURLFirst` below, which `ProviderLoader` calls before objects ever reach here.
    ///   - note: The compose card's own optional typed note — attaches to `objects[0]` ONLY, same
    ///     "note on the first unit" rule the composer uses (Global Constraints/plan-4 parity).
    ///     Blank/whitespace-only collapses to "no note", same as the composer's own trimming.
    ///   - location: Threads into EVERY unit's `attributes.location`, unconditionally — this is a
    ///     plain value here (unlike `CaptureViewModel.pendingLocation`), since resolving an
    ///     in-flight pin is the extension's (T7) job, before this is ever called.
    public func submit(_ objects: [SharedObject], note: String?, location: CapturedLocation?, isPublic: Bool = false) async -> ShareIntakeResult {
        var result = ShareIntakeResult()

        // 1. Persist EVERY object before any network call (plan 15 review) — the share sheet can be
        //    killed at any moment once Save is tapped, and an object still only in memory while
        //    an earlier one uploads would be lost (or, for a file, only come back through
        //    `sweepOrphans` without its note or location).
        var queued: [(id: UUID, stagedFile: URL?)] = []
        for unit in units(for: objects, note: note, location: location, isPublic: isPublic) {
            guard let entry = try? await outbox.enqueue(unit.kind, payload: unit.payload) else {
                // The Outbox write itself failed. Counted, never silent. A staged file is left in
                // place: `sweepOrphans` is the recovery net on the app's next launch.
                result.failed += 1
                continue
            }
            queued.append((entry.id, unit.stagedFile))
        }

        // 2. Only now the token (fetching it may refresh the session over the network) — once per
        //    batch, so every unit sends under the same session snapshot. No session → everything
        //    stays queued for the app to drain later.
        let token = queued.isEmpty ? nil : try? await accessToken()

        // 3. Send what fits the foreground budget; the rest waits for the app.
        for (id, stagedFile) in queued {
            let fileSize = stagedFile.flatMap { staging.fileSize(of: $0) } ?? 0
            guard let token, fileSize <= directSendLimit else {
                result.queued += 1
                continue
            }
            switch await outbox.sendNow(id: id, api: capture, userId: userId, accessToken: token, upload: upload) {
            case .sent, .notFound: result.saved += 1
            case .parked, .pending, .inFlight: result.queued += 1
            case .dropped: result.failed += 1
            }
        }
        return result
    }

    /// Plan 15 (for Task 4's background transfers): writes every object to the Outbox as
    /// `.transferring` (stamped now) and returns the entries, in object order, WITHOUT sending
    /// anything — the caller hands them to the shared background session and dismisses. Same
    /// payload rules as `submit` (note on the first object, `.text` + note merge, location on
    /// every unit). An object whose Outbox write fails is left out of the result (its staged file,
    /// if any, stays for `sweepOrphans`).
    ///
    /// Plan 15 review: `status: .pending` persists the share for the app to send as is — the share
    /// sheet does that when it can't hand off at once (a location pin still resolving, a token to
    /// refresh), then `attachLocation`s it if needed and hands the entries to the background
    /// session (`start` re-stamps them `.transferring`). Should the hand-off never happen, the app's
    /// drain sends them.
    public func enqueueForTransfer(_ objects: [SharedObject], note: String?, location: CapturedLocation?,
                                   status: OutboxEntry.Status = .transferring, isPublic: Bool = false) async -> [OutboxEntry] {
        var entries: [OutboxEntry] = []
        for unit in units(for: objects, note: note, location: location, isPublic: isPublic) {
            if let entry = try? await outbox.enqueue(unit.kind, payload: unit.payload, status: status) {
                entries.append(entry)
            }
        }
        return entries
    }

    /// Plan 15 review: adds a location that resolved after the share was saved to each entry's
    /// `attributes_json` (merged — a file's `media` and any other key stay as they are) and
    /// returns the entries as now persisted, in order. An entry that no longer exists (already
    /// sent by the app) is left out; its item simply has no location.
    public func attachLocation(_ location: CapturedLocation, to entries: [OutboxEntry]) async -> [OutboxEntry] {
        var updated: [OutboxEntry] = []
        for entry in entries {
            if let rewritten = await outbox.attachLocation(location, to: entry.id) { updated.append(rewritten) }
        }
        return updated
    }

    // MARK: - Background hand-off (plan 15, Task 4)
    //
    // The share sheet's Save: `enqueueForTransfer` (every unit on disk first) → a token →
    // `BackgroundCaptureTransfers.start` → the confirmation → ~0.8 s later `completeRequest`. The
    // helpers below are the pieces of that flow that decide something; each is bounded so the
    // sheet never waits on the network for longer than its confirmation window allows.

    /// A token that expires sooner than this is refreshed before transfers start: a background
    /// transfer can take a while to reach the server on a slow network, and the server checks
    /// the token when the request arrives.
    public static let transferTokenMinimumValidity: TimeInterval = 5 * 60
    /// Upper bound on that refresh; on timeout the entries (saved `.pending`) wait in the Outbox
    /// for the app.
    public static let transferTokenRefreshTimeout: TimeInterval = 2.5
    /// Upper bound on the foreground fallback when the background session can't take the share.
    public static let foregroundFallbackTimeout: TimeInterval = 6

    /// `accessToken` when it stays valid for at least `minimumValidity` from `now`, else `nil`
    /// (the caller refreshes — `refreshedTransferToken`).
    public static func usableTransferToken(_ accessToken: String, expiresAt: Date, now: Date = Date(),
                                           minimumValidity: TimeInterval = transferTokenMinimumValidity) -> String? {
        expiresAt.timeIntervalSince(now) >= minimumValidity ? accessToken : nil
    }

    /// Runs `refresh` for at most `timeout` seconds: its token, or `nil` if it failed or didn't
    /// answer in time (the refresh is cancelled and left to finish on its own — the caller never
    /// waits for it).
    public static func refreshedTransferToken(timeout: TimeInterval = transferTokenRefreshTimeout,
                                              refresh: @escaping @Sendable () async throws -> String) async -> String? {
        await withDeadline(.seconds(timeout), fallback: nil) { try? await refresh() }
    }

    /// The bounded foreground fallback: sends `ids` one by one (`Outbox.sendNow`, the same
    /// idempotent path as `submit`) for at most `timeout` seconds, then stops — an in-flight
    /// request is cancelled (that entry stays pending with its attempt counted, its claim
    /// released) and the rest are left untouched for the app. Files over `directSendLimit` are
    /// left for the app too, as in `submit`.
    public func sendInForeground(_ ids: [UUID], accessToken: String,
                                 timeout: TimeInterval = foregroundFallbackTimeout) async -> ShareIntakeResult {
        guard !ids.isEmpty else { return ShareIntakeResult() }
        let work = Task { () -> ShareIntakeResult in
            var result = ShareIntakeResult()
            for id in ids {
                guard !Task.isCancelled else {
                    result.queued += 1
                    continue
                }
                if let entry = await outbox.entry(id: id), entry.payload["file_path"] == nil,
                   let size = CaptureTransport.localFileSize(of: entry), size > directSendLimit {
                    result.queued += 1
                    continue
                }
                switch await outbox.sendNow(id: id, api: capture, userId: userId, accessToken: accessToken, upload: upload) {
                case .sent, .notFound: result.saved += 1
                case .parked, .pending, .inFlight: result.queued += 1
                case .dropped: result.failed += 1
                }
            }
            return result
        }
        let deadline = Task {
            try? await Task.sleep(for: .seconds(timeout))
            work.cancel()
        }
        let result = await work.value
        deadline.cancel()
        return result
    }

    // MARK: - Ordering (Task 7, T6-review carry: adopted ordering decision)

    /// Promotes whole web URLs delivered as plain text, then moves the first `.url` case to
    /// index 0, preserving the relative order of
    /// everything else — a no-op when there's no `.url` object, or it's already first. Lives here
    /// (a pure StashKit function `swift test` can exercise directly) rather than inside `T7`'s
    /// `ProviderLoader`, which is NOT `swift test`-able at all (an Xcode extension target, not part
    /// of this package) — `ProviderLoader.load` calls this after assembling its raw
    /// `[SharedObject]` list, before ever handing it to `submit`.
    ///
    /// Why this exists: `submit`'s own doc comment above says `objects[0]` is unconditionally "the
    /// first object" for note-attachment purposes and trusts caller-supplied order as-is (T6
    /// disclosure #6) — correct for `ShareIntake` itself, but it pushes the actual ordering
    /// decision onto whoever builds the array. `NSExtensionContext.inputItems`/`.attachments` order
    /// is the OS's/sending-app's choice, not guaranteed to put a shared URL first (e.g. a URL
    /// shared alongside inline text). The composer's own `CaptureViewModel.route()` has a
    /// deterministic rule for the equivalent situation — "a URL detected anywhere ... always comes
    /// FIRST when present" — so a share with a URL object anywhere in it should land its note on
    /// that URL too, matching iOS-wide capture behavior with no second, extension-only ordering
    /// variant.
    public static func reorderURLFirst(_ objects: [SharedObject]) -> [SharedObject] {
        let objects = objects.map(normalizeSharedObject)
        guard let urlIndex = objects.firstIndex(where: {
            if case .url = $0 { return true }
            return false
        }), urlIndex != 0 else { return objects }
        var reordered = objects
        let url = reordered.remove(at: urlIndex)
        reordered.insert(url, at: 0)
        return reordered
    }

    private static func normalizeSharedObject(_ object: SharedObject) -> SharedObject {
        if case .text(let text) = object, let url = detectWholeWebURL(in: text) { return .url(url) }
        return object
    }

    // MARK: - Objects → Outbox units

    private struct Unit {
        let kind: OutboxEntry.Kind
        let payload: [String: String]
        let stagedFile: URL?
    }

    private func units(for objects: [SharedObject], note: String?, location: CapturedLocation?, isPublic: Bool) -> [Unit] {
        let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveNote = (trimmed?.isEmpty ?? true) ? nil : trimmed
        return objects.enumerated().map { index, object in
            unit(for: object, note: index == 0 ? effectiveNote : nil, location: location, isPublic: isPublic)
        }
    }

    /// A shared `.text` object's own string already IS its content — unlike `.url`/`.file`, which
    /// have no free text of their own, so an attached note simply BECOMES their whole content
    /// (there's nothing else it could overwrite). A note attaching to a `.text` object instead
    /// AUGMENTS it: `appendNoteParagraph` (TipTapAppend.swift — written for the since-retired
    /// "append to an existing item" composer) treats the shared text as the existing body and the
    /// typed note as a new paragraph appended after it, so neither is ever silently dropped.
    private func unit(for object: SharedObject, note: String?, location: CapturedLocation?, isPublic: Bool) -> Unit {
        // Also normalize at the durable boundary: direct callers and both transfer lanes must
        // send the same URL payload, even if they did not use ProviderLoader's ordering helper.
        switch Self.normalizeSharedObject(object) {
        case .url(let url):
            var payload = ["url": url, "content": note ?? "", "is_public": isPublic ? "true" : "false"]
            if let json = attributesJSONString(buildAttributes(location: location)) { payload["attributes_json"] = json }
            return Unit(kind: .url, payload: payload, stagedFile: nil)
        case .text(let text):
            let content = note.map { appendNoteParagraph(to: text, note: $0) } ?? text
            var payload = ["content": content, "is_public": isPublic ? "true" : "false"]
            if let json = attributesJSONString(buildAttributes(location: location)) { payload["attributes_json"] = json }
            return Unit(kind: .note, payload: payload, stagedFile: nil)
        case .file(let stagedURL, let mimeType, let fileName, let durationS):
            var payload = ["local_file_path": stagedURL.path, "mime_type": mimeType, "is_public": isPublic ? "true" : "false"]
            // Attributes only (`StagedFileStore.fileSize`), never `Data(contentsOf:)`.
            if let size = staging.fileSize(of: stagedURL) { payload["file_size"] = String(size) }
            if let fileName, !fileName.isEmpty { payload["file_name"] = fileName }
            if let note { payload["content"] = note }
            let media = buildMedia(fileName: fileName, durationS: durationS)
            if let json = attributesJSONString(buildAttributes(location: location, media: media)) {
                payload["attributes_json"] = json
            }
            return Unit(kind: .file, payload: payload, stagedFile: stagedURL)
        }
    }

    // MARK: - Attributes helpers (private duplicates of CaptureViewModel's own — see disclosure)

    /// Deliberately duplicated rather than shared with `CaptureViewModel`'s identical-shaped
    /// private helpers of the same name: both are tiny, and extracting a shared free function would
    /// be new public(ish) surface neither the brief nor `CaptureViewModel` asked for, for two call
    /// sites. Same `nil`-collapsing contract either way — never an always-present `ItemAttributes()`.
    private func buildAttributes(location: CapturedLocation?, media: MediaAttributes? = nil) -> ItemAttributes? {
        guard location != nil || media != nil else { return nil }
        return ItemAttributes(location: location, media: media)
    }

    private func buildMedia(fileName: String?, durationS: Double?) -> MediaAttributes? {
        guard fileName != nil || durationS != nil else { return nil }
        return MediaAttributes(durationS: durationS, fileName: fileName)
    }

    /// `attributes` serialized to a JSON string for the Outbox's text-only `[String: String]`
    /// payload — mirrors `CaptureViewModel.attributesPayloadString` exactly, so every capture
    /// request sends the attributes a direct call would have.
    private func attributesJSONString(_ attributes: ItemAttributes?) -> String? {
        guard let object = attributes?.nonEmptyJSONObject,
              let data = try? JSONSerialization.data(withJSONObject: object)
        else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

/// Runs `work` and returns its result — or `fallback` as soon as `timeout` passes first. Never
/// waits on `work` past that: it is cancelled and left to end on its own, and whatever it returns
/// later is dropped (unlike a task group, which would wait for a child that ignores cancellation).
/// Whichever side answers first cancels the other, so the timer doesn't outlive a quick answer.
/// For waits nobody can afford to have held open by a stalled request: a token fetch during a
/// background wake or the share sheet's confirmation window, a composer pick whose iCloud/Photos
/// transfer never finishes.
public func withDeadline<Value: Sendable>(_ timeout: Duration, fallback: Value,
                                          _ work: @escaping @Sendable () async -> Value) async -> Value {
    await withDeadline(fallback: fallback, deadline: { try? await Task.sleep(for: timeout) }, work)
}

/// `withDeadline(_:fallback:_:)` with the timer injectable (tests): `deadline` returns when time is
/// up — or early, once it is cancelled because `work` answered first.
func withDeadline<Value: Sendable>(fallback: Value, deadline: @escaping @Sendable () async -> Void,
                                   _ work: @escaping @Sendable () async -> Value) async -> Value {
    await withCheckedContinuation { continuation in
        let gate = FirstResult(continuation)
        let worker = Task<Void, Never> { gate.resume(returning: await work()) }
        let timer = Task<Void, Never> {
            await deadline()
            gate.resume(returning: fallback)   // a no-op once the work has answered
        }
        gate.cancelOnResult([worker, timer])
    }
}

/// Resumes a continuation with whichever result arrives first; later ones are ignored. Racing
/// tasks registered with `cancelOnResult` are cancelled the moment a result is in.
private final class FirstResult<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Never>?
    private var racers: [Task<Void, Never>] = []

    init(_ continuation: CheckedContinuation<Value, Never>) {
        self.continuation = continuation
    }

    /// Cancels `tasks` once a result is in — at once, if one already is (a racer that answered
    /// before this registration couldn't reach the others).
    func cancelOnResult(_ tasks: [Task<Void, Never>]) {
        let resolved = lock.withLock { () -> Bool in
            guard continuation != nil else { return true }
            racers += tasks
            return false
        }
        if resolved { tasks.forEach { $0.cancel() } }
    }

    /// `true` if this call delivered the result.
    @discardableResult
    func resume(returning value: Value) -> Bool {
        let (first, racers) = lock.withLock { () -> (CheckedContinuation<Value, Never>?, [Task<Void, Never>]) in
            defer {
                continuation = nil
                self.racers = []
            }
            return (continuation, continuation == nil ? [] : self.racers)
        }
        first?.resume(returning: value)
        racers.forEach { $0.cancel() }
        return first != nil
    }
}
