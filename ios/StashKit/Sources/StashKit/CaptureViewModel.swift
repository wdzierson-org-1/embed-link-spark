import Foundation
import Observation
import Supabase

/// One captured attachment (photo or arbitrary file) staged in the composer before `submit()`
/// saves it. `kind` drives display (thumbnail vs. doc icon) and which preparation/size-guard
/// branch applies — both eventually go through the same `capture` endpoint as `kind: "file"`.
public struct CaptureAttachment: Identifiable, Sendable {
    public enum Kind: Sendable { case photo, file }
    public let id: UUID
    public var data: Data
    public var fileExtension: String
    public var mimeType: String
    public var kind: Kind
    /// The original filename, captured at pick time (Task 5 — `attributes.media.file_name`):
    /// PhotosPicker's suggested name, the security-scoped URL's `lastPathComponent` for
    /// `fileImporter`, or `nil` for a camera capture (no source filename exists). Plan 15: a photo
    /// re-encoded by `ImagePreparation` records this name with its extension swapped to `.jpg`.
    public var fileName: String?
    /// Media duration in seconds, captured at pick time (`attributes.media.duration_s`): an
    /// `AVAsset` probe for a picked audio/video file, the recorder-elapsed time for a voice note,
    /// or `nil` for anything else (photos, documents).
    public var durationS: Double?

    public init(id: UUID = UUID(), data: Data, fileExtension: String, mimeType: String, kind: Kind,
                fileName: String? = nil, durationS: Double? = nil) {
        self.id = id
        self.data = data
        self.fileExtension = fileExtension
        self.mimeType = mimeType
        self.kind = kind
        self.fileName = fileName
        self.durationS = durationS
    }

    /// The largest attachment `CaptureViewModel.submit()` accepts, in bytes — `nil` = no limit.
    /// Photos have none (every photo is prepared down to ≤ 2560 px anyway); other files mirror
    /// the web's per-kind limits (MediaUploadTypes.ts:26-28): 100 MB for audio/video, 20 MB for
    /// everything else (docs). Public so the composer can refuse an oversized pick from its file
    /// size alone, before reading the bytes into memory (plan 15 6D); `submit()` enforces the
    /// same rule as its backstop.
    public static func byteLimit(kind: Kind, mimeType: String) -> Int? {
        guard kind == .file else { return nil }
        let isAudioOrVideo = mimeType.hasPrefix("video/") || mimeType.hasPrefix("audio/")
        return (isAudioOrVideo ? 100 : 20) * 1_048_576
    }
}

/// `dropped` on `.saved`/`.queued` and the dedicated `.rejected` case exist so data loss is
/// never silent (fix round, review Important finding): every unit that could not even be written
/// to the Outbox — an oversized reject, or bytes that couldn't be staged to disk — is counted and
/// must reach the user, not just a `print` log. Plan 15: a failed SEND is no longer a drop — the
/// unit is already in the Outbox and comes back as `.queued`. `.nothingToSave` is reserved for
/// the case where `submit()` had literally nothing to attempt (empty text, no attachments).
public enum CaptureOutcome: Equatable {
    case saved(count: Int, dropped: Int)
    case queued(count: Int, dropped: Int)
    case rejected(dropped: Int)
    case nothingToSave
}

/// Backs the Add-tab composer. UIKit-free by design, so the whole routing + Outbox contract is
/// unit-testable under `swift test` without the app target.
///
/// Plan 15 — outbox-first: every unit of a submission is written to the Outbox BEFORE any network
/// call (attachment bytes staged to disk via `StagedFileStore`, photos first through
/// `ImagePreparation` — ≤ 2560 px JPEG), then sent right away with `Outbox.sendNow`. The entry id
/// is the capture id the idempotent `capture` endpoint dedupes on, so a send whose response is lost
/// can be retried by any later drain without ever creating a second item. A failed send leaves the
/// unit queued (`.queued`) instead of dropping it; only size-limit and staging failures are
/// `.rejected`/`dropped`.
///
/// Reconciliation: a capture that reaches the server posts `Notification.Name.stashItemCaptured`
/// (from `Outbox`), which the app-scope item store prepends immediately; realtime still delivers
/// the enrichment upgrades.
///
/// Subscription-gate note (Task 7): this type deliberately does NOT check
/// `SubscriptionStore.canAddContent` — same UI-layer-only precedent `ChatStore`/`AskView`
/// established for the Ask tab's gates (Task 5). `CaptureComposerView` reads the gate from its
/// environment and disables Save + shows the inline copy before `submit()`/`submitVoiceNote`
/// are ever called. A stale gate that lets a save through still ends safely: the server's 403
/// parks the entry (Plan 14 T3).
@MainActor
@Observable
public final class CaptureViewModel {
    public var text: String = ""
    public var attachments: [CaptureAttachment] = []
    public var isPublic: Bool = false
    public private(set) var pendingOutboxCount: Int = 0
    /// A device location, ready to ride every unit of the NEXT `submit()`/`submitVoiceNote()` call
    /// (Global Constraints: "written to EVERY item in a batch"). `nil` (default) attaches nothing.
    /// Settable so Task 6's pin-toggle UI can assign it directly; `submit()`/`submitVoiceNote()`
    /// also assign it indirectly via `awaitPendingLocation(timeout:)` below, whenever the injected
    /// resolver hook has something newer to offer — once with no wait before the capture is
    /// written, and (for a pin still resolving) once more with the full budget right after.
    public var pendingLocation: CapturedLocation?

    private let userId: UUID
    private let api: CaptureAPI
    private let outbox: Outbox
    private let staging: StagedFileStore
    private let upload: (@Sendable (URL, String, String) async throws -> Void)?
    private let accessToken: @Sendable () async throws -> String
    private let awaitPendingLocationHook: (@Sendable (TimeInterval) async -> CapturedLocation?)?
    /// Keeps `pendingOutboxCount` honest when a capture lands outside this view model (see
    /// `refreshPendingCount`). Removed with the view model.
    @ObservationIgnored private var capturedObserver: NotificationObserver?

    /// Global Constraints / Task 6 brief: "submit() waits ≤2.5s on .resolving … then proceeds with
    /// whatever resolved." Single source of truth for that budget, referenced at every call site
    /// (`submit()`, `submitVoiceNote()`) so it can't drift between them. Plan 15 final wave: the
    /// wait happens AFTER the capture is in the Outbox (`captureLocationNow()` /
    /// `attachLateLocation(to:)`), never between Save and the Outbox write.
    private static let locationAwaitTimeout: TimeInterval = 2.5

    /// - Parameters:
    ///   - outbox: `nil` (every call site but tests) builds the per-user default directory from
    ///     `userId` — a shared, user-agnostic default let one account's offline-queued captures
    ///     drain into a different account's after a sign-out/sign-in (Critical final-review
    ///     finding; see `Outbox.defaultDirectory(userId:)`). Tests inject a scratch directory.
    ///   - staging: where attachment bytes are written before enqueueing — `nil` = the per-user
    ///     App Group staging directory (the same one `sweepOrphans` watches, so a crash between
    ///     staging and enqueue is still recovered on the next launch).
    ///   - upload: the Outbox's two-step Storage lane for files over the one-shot limit — `nil`
    ///     streams through `api.uploadFileToStorage` with the send's own token.
    ///   - accessToken: `nil` (every call site but tests) = `StashClient.accessToken(for: userId)`:
    ///     the signed-in session's token only while it is still `userId`'s — this view model's
    ///     Outbox is `userId`'s, and a send that reaches the token after a sign-out/sign-in must
    ///     leave the capture queued rather than deliver it into another account. `Optional`, not a
    ///     closure with a default expression, because a default argument can't reference `userId`.
    public init(
        userId: UUID,
        api: CaptureAPI = CaptureAPI(),
        outbox: Outbox? = nil,
        staging: StagedFileStore? = nil,
        upload: (@Sendable (URL, String, String) async throws -> Void)? = nil,
        accessToken: (@Sendable () async throws -> String)? = nil,
        // Bridges to the app's Task 6 `LocationCapture` (CLLocationManager/CLGeocoder plumbing —
        // deliberately kept out of StashKit, which has no CoreLocation dependency and never will).
        // `nil` (default: every StashKit test, and any future call site that never wires one up)
        // makes `awaitPendingLocation(timeout:)` a true no-op that leaves `pendingLocation` exactly
        // as it already was. This is an OPTIONAL closure, not a closure defaulted to "always
        // returns nil" — see that method's own doc comment for why the two are not
        // interchangeable here.
        awaitPendingLocation: (@Sendable (TimeInterval) async -> CapturedLocation?)? = nil
    ) {
        self.userId = userId
        self.api = api
        self.outbox = outbox ?? Outbox(directory: Outbox.defaultDirectory(userId: userId))
        self.staging = staging ?? StagedFileStore(userId: userId)
        self.upload = upload
        self.accessToken = accessToken ?? { try await StashClient.accessToken(for: userId) }
        self.awaitPendingLocationHook = awaitPendingLocation
        capturedObserver = NotificationObserver(name: .stashItemCaptured) { [weak self] in
            Task { @MainActor [weak self] in await self?.refreshPendingCount() }
        }
    }

    /// Waits (bounded by `timeout` seconds) on an in-flight pin resolution before this batch's
    /// location is snapshotted — the injected `awaitPendingLocationHook` (Task 6's app-side
    /// `LocationCapture`) supplies the actual wait/poll logic; StashKit itself has no idea what
    /// ".resolving" means, only how long it may take.
    ///
    /// No hook at all (`nil` — every StashKit test, any call site that never wires one up) is a
    /// true no-op: `pendingLocation` stays exactly as it already was, including whatever a test
    /// set it to directly. Once a hook IS wired (every real app launch), its result UNCONDITIONALLY
    /// replaces `pendingLocation` — nil included. That's deliberate, not "nil means don't touch":
    /// nil is exactly what `LocationCapture.awaitResolution` returns for an `.off`/`.failed` pin,
    /// and a pin the user has explicitly turned off (or that failed) must be able to CLEAR a
    /// location a previous toggle-on cycle left behind, not just skip setting a new one. A pin
    /// still `.resolving` past `timeout` resolves to whatever `currentLocation` reads at that
    /// point (Global Constraints: "then proceeds with whatever resolved") — never blocks past that
    /// budget either way.
    public func awaitPendingLocation(timeout: TimeInterval) async {
        guard let hook = awaitPendingLocationHook else { return }
        pendingLocation = await hook(timeout)
    }

    /// The location a capture made RIGHT NOW carries: whatever the pin has already resolved
    /// (`awaitPendingLocation(timeout: 0)` — no wait; `nil` while a pin is still resolving, or off).
    private func captureLocationNow() async -> CapturedLocation? {
        await awaitPendingLocation(timeout: 0)
        return pendingLocation
    }

    /// Plan 15 final wave (mirrors the share sheet): a pin that was still resolving when the
    /// capture was saved gets its `locationAwaitTimeout` now — with every unit ALREADY in the
    /// Outbox, so a kill during the wait loses nothing — and a location that arrives in time is
    /// merged into each still-queued entry (`Outbox.attachLocation`) before anything is sent.
    /// Returns at once for a pin that is off, failed, or already resolved (nothing to wait for).
    /// An entry a concurrent drain sent during the wait keeps its item location-less (rare; the
    /// same accepted window as the share sheet's).
    private func attachLateLocation(to entryIds: [UUID]) async {
        guard !entryIds.isEmpty else { return }
        await awaitPendingLocation(timeout: Self.locationAwaitTimeout)
        guard let location = pendingLocation else { return }
        for id in entryIds {
            await outbox.attachLocation(location, to: id)
        }
    }

    // MARK: - Submit / drain

    public func submit() async -> CaptureOutcome {
        let units = route()
        guard !units.isEmpty else { return .nothingToSave }
        let publicFlag = isPublic

        // Clear immediately (web parity, UnifiedInputPanel.tsx:778-782 "clear the form
        // immediately for better UX") — everything below works off the captured `units`.
        text = ""
        attachments = []

        // Snapshotted once, without waiting: every unit in THIS batch gets the same location
        // (Global Constraints: "written to EVERY item in a batch"). A pin still resolving is
        // given its time only once the batch is durable (step 2).
        let location = await captureLocationNow()

        // 1. Persist the WHOLE batch before any wait or network call (plan 15 review + final
        //    wave): the form is already cleared, so from here on the Outbox is the only copy — a
        //    kill during the pin wait, or while unit 1 uploads, must not lose anything (links/notes
        //    would be gone for good; files would only come back via `sweepOrphans`, without their
        //    note, location, or visibility).
        var entryIds: [UUID] = []
        var droppedCount = 0
        for unit in units {
            let ready: ReadyUnit
            do {
                ready = try await prepare(unit, location: location, isPublic: publicFlag)
            } catch {
                // Never queueable — see `UnqueueableFailure`. Still counted (never just logged).
                droppedCount += 1
                print("Capture: dropped an attachment — \(error)")
                continue
            }
            do {
                entryIds.append(try await outbox.enqueue(ready.kind, payload: ready.payload).id)
            } catch {
                // Couldn't persist the unit at all (e.g. a full disk). Its staged copy is removed
                // so a later `sweepOrphans` can't quietly save something the user was told failed.
                if let staged = ready.stagedFile { staging.discard(staged) }
                droppedCount += 1
                print("Capture: couldn't write a capture to the Outbox — \(error)")
            }
        }

        // 2. A pin still resolving at Save: its ≤ 2.5 s, now that the batch is durable.
        if location == nil {
            await attachLateLocation(to: entryIds)
        }

        // 3. Only now the token — fetching it may itself refresh the session over the network.
        //    Once per batch: every unit sends under the same session snapshot. `try?` turns "no
        //    session" (or another account's) into a nil token: the units stay queued for a later
        //    drain.
        let token = entryIds.isEmpty ? nil : try? await accessToken()

        // 4. Send each (the capture id is the entry id, so any of these can be retried later).
        var savedCount = 0
        var queuedCount = 0
        for id in entryIds {
            guard let token else {
                queuedCount += 1
                continue
            }
            switch await outbox.sendNow(id: id, api: api, userId: userId, accessToken: token, upload: upload) {
            case .sent, .notFound:
                // `.notFound`: a concurrent drain already delivered it between enqueue and send.
                savedCount += 1
            case .dropped:
                droppedCount += 1
            case .parked, .pending, .inFlight:
                // Plan 14 fix wave B (#8): a 403 subscription_required parks the entry (inside
                // `sendNow`) instead of leaving it pending; either way it's safely queued.
                queuedCount += 1
            }
        }

        await refreshPendingCount()
        if queuedCount > 0 { return .queued(count: queuedCount, dropped: droppedCount) }
        if savedCount > 0 { return .saved(count: savedCount, dropped: droppedCount) }
        // `units` was non-empty (guarded above) and neither saved nor queued anything, so
        // every unit in this submission was dropped.
        return .rejected(dropped: droppedCount)
    }

    /// The voice-note counterpart to `submit()` — a single already-on-disk recording (written by
    /// the app's `AudioRecorderController` via `RecordingStore`, before this is ever called) is
    /// written to the Outbox as a `.file` entry pointing at the recording (`local_file_path`),
    /// then sent right away with `Outbox.sendNow`. The recording's bytes are already durably on
    /// local disk, so any send failure just leaves the entry queued — retried later from exactly
    /// this file, under the same capture id (never a second item). On success the entry AND the
    /// local recording are removed.
    ///
    /// `content: nil` is deliberate, not an oversight — voice notes never consume the composer's
    /// `text` field (the sheet that calls this is a self-contained flow with its own Save button,
    /// independent of whatever's typed in the composer's editor at the time).
    /// - Parameter durationS: Recorder-elapsed seconds (`AudioRecorderController.elapsed` at Stop),
    ///   threaded into `attributes.media.duration_s` exactly like a picked file's `CaptureAttachment
    ///   .durationS` — `nil` (default) omits the media fact entirely. `pendingLocation` rides along
    ///   too, the same way as in `submit()`: already resolved → straight into the entry; still
    ///   resolving → its wait happens after the entry is written (`attachLateLocation(to:)`).
    public func submitVoiceNote(fileURL: URL, durationS: Double? = nil) async -> CaptureOutcome {
        let location = await captureLocationNow()
        let attributes = buildAttributes(location: location, media: buildMedia(fileName: nil, durationS: durationS))
        var payload = [
            "local_file_path": fileURL.path,
            "mime_type": "audio/mp4",
            "is_public": isPublic ? "true" : "false",
        ]
        if let size = staging.fileSize(of: fileURL) { payload["file_size"] = String(size) }
        if let json = attributesPayloadString(attributes) { payload["attributes_json"] = json }

        guard let entry = try? await outbox.enqueue(.file, payload: payload) else {
            // The recording itself is still safe in `RecordingStore` — the next launch's
            // `sweepOrphans` re-enqueues it — so this is "will sync", not a loss.
            await refreshPendingCount()
            return .queued(count: 1, dropped: 0)
        }
        if location == nil {
            await attachLateLocation(to: [entry.id])
        }
        guard let token = try? await accessToken() else {
            await refreshPendingCount()
            return .queued(count: 1, dropped: 0)
        }
        let result = await outbox.sendNow(id: entry.id, api: api, userId: userId, accessToken: token, upload: upload)
        await refreshPendingCount()
        switch result {
        case .sent, .notFound: return .saved(count: 1, dropped: 0)
        case .dropped: return .rejected(dropped: 1)
        case .parked, .pending, .inFlight: return .queued(count: 1, dropped: 0)
        }
    }

    public func drainOutbox() async {
        if let token = try? await accessToken() {
            _ = await outbox.drain(api: api, accessToken: token, userId: userId, upload: upload)
        }
        await refreshPendingCount()
    }

    /// Only `.pending` entries count — the ones waiting on THIS app to send them.
    ///
    /// Plan 14 fix wave B (#9): a parked entry is explained by the composer's gate strip, not by
    /// "still trying" — counting it here would show e.g. "1 pending" for an entry that will never
    /// send again until the user resubscribes. Plan 15 review: a `.transferring` entry belongs to a
    /// background transfer and completes on its own, so it isn't the composer's backlog either.
    /// Re-read whenever a capture lands anywhere in the app (`.stashItemCaptured` — e.g. the
    /// launch drain or a background-transfer completion), not just after this view model's own sends.
    private func refreshPendingCount() async {
        pendingOutboxCount = await outbox.pending().filter { $0.status == .pending }.count
    }

    // MARK: - Routing (Global Constraints: port of web UnifiedInputPanel submit, collections cut)

    private enum CaptureUnit {
        case note(content: String)
        case url(url: String, note: String)
        case file(CaptureAttachment, content: String?)
    }

    /// Single-object model (Global Constraints, plan 4 `ui-changes.md`): a capture with N objects
    /// (files and/or a detected URL) always saves N items — never a collection, never a bundled
    /// extra "note" item — and the typed note, if any, rides `content` on the FIRST unit ONLY.
    /// That rule is universal across every branch below, not a special case of any one of them:
    ///
    /// - A URL detected anywhere in the typed text is always its own unit (a `url` capture,
    ///   content = the text with the URL substring removed) and always comes FIRST when present,
    ///   whether or not files are attached too. Any attachments then follow as individual file
    ///   units with no content — the note already rode the URL.
    /// - No URL, no attachments: a single note (or nothing, if the text is empty too).
    /// - No URL, exactly one attachment: one file, the typed text as its content.
    /// - No URL, multiple attachments: one file per attachment; the FIRST carries the typed
    ///   text as its content, the rest carry none. There is no more separate note item for
    ///   "leftover" text once attachments are involved — plan 2's note-as-its-own-item behavior is
    ///   retired.
    private func route() -> [CaptureUnit] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if let rawURL = detectFirstURL(in: trimmed) {
            let url = stripTrailingPunctuation(rawURL)
            let note = noteText(strippingURLFrom: trimmed, rawURL: rawURL)
            return [.url(url: url, note: note)] + attachments.map { .file($0, content: nil) }
        }

        if attachments.isEmpty {
            return trimmed.isEmpty ? [] : [.note(content: trimmed)]
        }

        if attachments.count == 1 {
            return [.file(attachments[0], content: trimmed.isEmpty ? nil : trimmed)]
        }

        return attachments.enumerated().map { index, attachment in
            .file(attachment, content: index == 0 && !trimmed.isEmpty ? trimmed : nil)
        }
    }

    /// `trimmed` with its first detected URL substring removed and whitespace collapsed — the
    /// note text `route()`'s URL branch attaches to its `.url` unit. Factored out so
    /// `pendingNoteHasContent` (below) can predict the same value BEFORE `submit()` clears `text`,
    /// without duplicating the stripping logic.
    private func noteText(strippingURLFrom trimmed: String, rawURL: String) -> String {
        var note = trimmed
        if let range = trimmed.range(of: rawURL) {
            note = trimmed.replacingCharacters(in: range, with: "")
        }
        return note.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    /// Whether the CURRENTLY typed `text` would attach non-empty note content to this batch's
    /// first unit — i.e. `route()`'s own note computation, minus the routing decision itself.
    /// `CaptureComposerView` reads this BEFORE calling `submit()` (which clears `text`
    /// immediately) to pick the right multi-save notice copy (Global Constraints: "your note went
    /// with the first one" vs. "so each got its own"). Correct across every `route()` branch
    /// without re-deriving them: URL-stripping only ever happens in the URL branch, and every
    /// other branch's note is simply the trimmed text verbatim, so "is there a URL to strip"
    /// followed by "is what's left non-empty" is the one check that already agrees with all of them.
    public var pendingNoteHasContent: Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let rawURL = detectFirstURL(in: trimmed) else { return !trimmed.isEmpty }
        return !noteText(strippingURLFrom: trimmed, rawURL: rawURL).isEmpty
    }

    // MARK: - Prepare (unit → Outbox payload)

    /// Thrown by `prepare` for the only failures that never reach the Outbox: an oversized
    /// attachment (retrying can never succeed) and bytes that couldn't be staged to disk (there's
    /// nothing durable for an entry to point at). Both are counted into `submit()`'s `dropped` and
    /// surfaced via `CaptureOutcome` — never silent.
    private struct UnqueueableFailure: Error { let reason: String }

    /// One unit, ready to enqueue: its Outbox kind + payload, and (for files) the staged copy the
    /// payload's `local_file_path` points at.
    private struct ReadyUnit: Sendable {
        let kind: OutboxEntry.Kind
        let payload: [String: String]
        let stagedFile: URL?
    }

    private func prepare(_ unit: CaptureUnit, location: CapturedLocation?, isPublic: Bool) async throws -> ReadyUnit {
        let publicFlag = isPublic ? "true" : "false"
        switch unit {
        case .note(let content):
            var payload = ["content": content, "is_public": publicFlag]
            if let json = attributesPayloadString(buildAttributes(location: location)) { payload["attributes_json"] = json }
            return ReadyUnit(kind: .note, payload: payload, stagedFile: nil)
        case .url(let url, let note):
            var payload = ["url": url, "content": note, "is_public": publicFlag]
            if let json = attributesPayloadString(buildAttributes(location: location)) { payload["attributes_json"] = json }
            return ReadyUnit(kind: .url, payload: payload, stagedFile: nil)
        case .file(let attachment, let content):
            try validateSize(of: attachment)
            let staged: StagedAttachment
            do {
                staged = try await Self.stage(attachment, into: staging)
            } catch {
                throw UnqueueableFailure(reason: "couldn't stage the attachment to disk: \(error)")
            }
            var payload = [
                "local_file_path": staged.url.path,
                "mime_type": staged.mimeType,
                "file_size": String(staged.byteCount),
                "is_public": publicFlag,
            ]
            if let content { payload["content"] = content }
            if let fileName = staged.fileName { payload["file_name"] = fileName }
            let media = buildMedia(fileName: staged.fileName, durationS: attachment.durationS)
            if let json = attributesPayloadString(buildAttributes(location: location, media: media)) {
                payload["attributes_json"] = json
            }
            return ReadyUnit(kind: .file, payload: payload, stagedFile: staged.url)
        }
    }

    private struct StagedAttachment: Sendable {
        let url: URL
        let mimeType: String
        let byteCount: Int
        let fileName: String?
    }

    /// Photos go through `ImagePreparation` (≤ 2560 px JPEG, orientation applied, metadata
    /// dropped; GIF and small JPEGs kept as-is); a photo ImageIO can't read is staged as its
    /// original bytes rather than dropped. Runs off the main actor — decoding/encoding a 12 MP
    /// photo takes long enough to hitch the UI.
    nonisolated private static func stage(_ attachment: CaptureAttachment,
                                          into staging: StagedFileStore) async throws -> StagedAttachment {
        try await Task.detached(priority: .userInitiated) {
            if attachment.kind == .photo, let prepared = ImagePreparation.prepare(attachment.data) {
                let url = try staging.stage(data: prepared.data, fileExtension: prepared.fileExtension)
                return StagedAttachment(url: url, mimeType: prepared.mimeType, byteCount: prepared.data.count,
                                        fileName: ImagePreparation.fileName(attachment.fileName,
                                                                            reencoded: prepared.wasReencoded))
            }
            let url = try staging.stage(data: attachment.data, fileExtension: attachment.fileExtension)
            return StagedAttachment(url: url, mimeType: attachment.mimeType, byteCount: attachment.data.count,
                                    fileName: attachment.fileName)
        }.value
    }

    /// `CaptureAttachment.byteLimit(kind:mimeType:)` — the one definition the composer also checks
    /// at pick time.
    private func validateSize(of attachment: CaptureAttachment) throws {
        guard let limit = CaptureAttachment.byteLimit(kind: attachment.kind, mimeType: attachment.mimeType),
              attachment.data.count > limit else { return }
        throw UnqueueableFailure(reason: "\(attachment.mimeType) attachment exceeds \(limit / 1_048_576) MB limit")
    }

    /// `nil` whenever there's nothing to attach (no location pinned, no media facts) — kept as an
    /// `ItemAttributes?`, not an always-present `ItemAttributes()`, so the never-send-`{}` gate has
    /// nothing to do for the common case of an unpinned, non-media unit.
    private func buildAttributes(location: CapturedLocation?, media: MediaAttributes? = nil) -> ItemAttributes? {
        guard location != nil || media != nil else { return nil }
        return ItemAttributes(location: location, media: media)
    }

    private func buildMedia(fileName: String?, durationS: Double?) -> MediaAttributes? {
        guard fileName != nil || durationS != nil else { return nil }
        return MediaAttributes(durationS: durationS, fileName: fileName)
    }

    /// `attributes` serialized to a JSON string for the Outbox's text-only `[String: String]`
    /// payload (Task 5) — `nil` whenever there's nothing worth persisting (the
    /// `nonEmptyJSONObject` gate: never send `{}`), so the capture request carries exactly the
    /// attributes the user's capture has.
    private func attributesPayloadString(_ attributes: ItemAttributes?) -> String? {
        guard let object = attributes?.nonEmptyJSONObject,
              let data = try? JSONSerialization.data(withJSONObject: object)
        else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

/// A block-based `NotificationCenter` registration that unregisters itself when released — lets a
/// `@MainActor` type observe notifications without a `deinit` (which can't touch its isolated state).
final class NotificationObserver: @unchecked Sendable {
    private let token: NSObjectProtocol

    init(name: Notification.Name, handler: @escaping @Sendable () -> Void) {
        token = NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil) { _ in handler() }
    }

    deinit { NotificationCenter.default.removeObserver(token) }
}
