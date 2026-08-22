import Foundation
import Observation
import Supabase

/// One captured attachment (photo or arbitrary file) staged in the composer before `submit()`
/// uploads it. `kind` only drives display (thumbnail vs. doc icon) and which size-guard branch
/// applies in `validatedUploadData` — both eventually go through the same `add-file` endpoint.
public struct CaptureAttachment: Identifiable {
    public enum Kind { case photo, file }
    public let id: UUID
    public var data: Data
    public var fileExtension: String
    public var mimeType: String
    public var kind: Kind
    /// The original filename, captured at pick time (Task 5 — `attributes.media.file_name`):
    /// PhotosPicker's suggested name, the security-scoped URL's `lastPathComponent` for
    /// `fileImporter`, or `nil` for a camera capture (no source filename exists).
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
}

/// `dropped` on `.saved`/`.queued` and the dedicated `.rejected` case exist so data loss is
/// never silent (fix round, review Important finding): every `UnqueueableFailure` — an oversized
/// reject or an upload that never landed in storage — is counted and must reach the user, not
/// just a `print` log. `.nothingToSave` is reserved for the case where `submit()` had literally
/// nothing to attempt (empty text, no attachments); it is never returned once anything was
/// attempted, even if everything attempted was dropped (`.rejected` covers that).
public enum CaptureOutcome: Equatable {
    case saved(count: Int, dropped: Int)
    case queued(count: Int, dropped: Int)
    case rejected(dropped: Int)
    case nothingToSave
}

/// Backs the Add-tab composer. UIKit-free by design (the only touch point for image bytes is
/// the `downscale` hook, itself a plain `Data -> Data` closure), so the whole routing +
/// Outbox-fallback contract is unit-testable under `swift test` without the app target.
/// StashKit's own default `downscale` is the identity closure; the app supplies a real
/// UIImage-based re-encoder at construction (see task-7-report.md for why this type lives here
/// rather than in the app target, where the brief originally placed it).
///
/// Reconciliation note (brief's "Correction for implementability"): this type deliberately does
/// NOT call `ItemStore.applyNew` — `LibraryView` owns its store privately, and there is no clean
/// seam to reach it from here. Realtime is the single reconciliation path: on a successful
/// capture the View tab's own `RealtimeObserver` subscription (already live, ~1s) picks up the
/// new row once the user switches tabs. Wiring `applyNew` too would race a second reconciliation
/// path against realtime for the same event, which Task 4's review flagged as unnecessary.
///
/// Subscription-gate note (Task 7): this type deliberately does NOT check
/// `SubscriptionStore.canAddContent` — same UI-layer-only precedent `ChatStore`/`AskView`
/// established for the Ask tab's gates (Task 5). `CaptureComposerView` reads the gate from its
/// environment and disables Save + shows the inline copy before `submit()`/`submitVoiceNote`
/// are ever called; nothing here needs new test coverage as a result (the gate boolean itself is
/// already fully covered by `SubscriptionStoreTests`, Task 3).
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
    /// resolver hook has something newer to offer.
    public var pendingLocation: CapturedLocation?

    private let userId: UUID
    private let api: CaptureAPI
    private let outbox: Outbox
    private let upload: @Sendable (Data, String, String) async throws -> Void
    private let accessToken: @Sendable () async throws -> String
    private let downscale: @Sendable (Data) -> Data
    private let awaitPendingLocationHook: (@Sendable (TimeInterval) async -> CapturedLocation?)?

    /// Global Constraints / Task 6 brief: "submit() waits ≤2.5s on .resolving … then proceeds with
    /// whatever resolved." Single source of truth for that budget, referenced at every call site
    /// (`submit()`, `submitVoiceNote()`) so it can't drift between them.
    private static let locationAwaitTimeout: TimeInterval = 2.5

    public init(
        userId: UUID,
        api: CaptureAPI = CaptureAPI(),
        // nil (every call site but tests) builds the per-user default directory from `userId`
        // below — can't be a plain default-argument expression since it needs `userId`, which
        // isn't available until the initializer body runs. Fix for a Critical final-review
        // finding: a shared, user-agnostic default here let one account's offline-queued
        // captures drain into a different account's after a sign-out/sign-in — see
        // `Outbox.defaultDirectory(userId:)`'s doc comment. Tests inject an explicit `Outbox`
        // over a scratch tmp directory.
        outbox: Outbox? = nil,
        upload: @escaping @Sendable (Data, String, String) async throws -> Void = { data, path, contentType in
            try await uploadToStorage(data: data, path: path, contentType: contentType)
        },
        accessToken: @escaping @Sendable () async throws -> String = {
            try await StashClient.shared.auth.session.accessToken
        },
        downscale: @escaping @Sendable (Data) -> Data = { $0 },
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
        self.upload = upload
        self.accessToken = accessToken
        self.downscale = downscale
        self.awaitPendingLocationHook = awaitPendingLocation
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

    // MARK: - Submit / drain

    public func submit() async -> CaptureOutcome {
        let units = route()
        guard !units.isEmpty else { return .nothingToSave }

        // Clear immediately (web parity, UnifiedInputPanel.tsx:778-782 "clear the form
        // immediately for better UX") — everything below works off the captured `units`.
        text = ""
        attachments = []

        // Fetched once per submit, not stored on `self` — mirrors `Outbox.drain`'s own
        // one-token-per-batch shape (Task 3). `try?` turns "no session" into a nil token,
        // which `send` below treats as an ordinary queueable failure.
        let token = try? await accessToken()

        // Task 6: give an in-flight pin resolution up to `locationAwaitTimeout` to finish before
        // snapshotting — placed AFTER the immediate text/attachments clear above, so the "clear
        // the form immediately" UX (web parity, noted above) isn't itself delayed by the wait.
        await awaitPendingLocation(timeout: Self.locationAwaitTimeout)

        // Snapshotted once, same reasoning as `token` above: every unit in THIS batch gets the
        // same location (Global Constraints: "written to EVERY item in a batch"), not whatever
        // `pendingLocation` happens to read partway through an `await`-laced loop.
        let location = pendingLocation

        var savedCount = 0
        var queuedCount = 0
        var droppedCount = 0
        for unit in units {
            do {
                let ready = try await prepare(unit, location: location)
                do {
                    _ = try await send(ready, accessToken: token)
                    savedCount += 1
                } catch {
                    // `prepare` already succeeded — any upload it needed has landed in
                    // storage — so this is a CaptureAPI/network throw, exactly what the
                    // Outbox exists to retry.
                    await enqueue(ready)
                    queuedCount += 1
                }
            } catch {
                // Never safe to queue — see `UnqueueableFailure`'s doc comment. Still counted
                // (never just logged): silently losing an attachment is exactly the bug this
                // fix round closes.
                droppedCount += 1
                print("Capture: dropped an attachment — \(error)")
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
    /// read, uploaded, and registered via `addFile`. Unlike `submit()`'s attachment path, there is
    /// no unqueueable-failure distinction: the recording's bytes are already durably on local disk
    /// (that's the entire point of recording straight into `RecordingStore` instead of holding the
    /// bytes in memory), so ANY failure here — reading the file, the upload, or `addFile` itself —
    /// is always safe, and always correct, to hand to the Outbox: it retries with the exact same
    /// local file, never invents a `file_path` nothing was ever written to.
    ///
    /// `content: nil` is deliberate, not an oversight — voice notes never consume the composer's
    /// `text` field (the sheet that calls this is a self-contained flow with its own Save button,
    /// independent of whatever's typed in the composer's editor at the time).
    /// - Parameter durationS: Recorder-elapsed seconds (`AudioRecorderController.elapsed` at Stop),
    ///   threaded into `attributes.media.duration_s` exactly like a picked file's `CaptureAttachment
    ///   .durationS` — `nil` (default) omits the media fact entirely, same as a picked file whose
    ///   own probe came back empty. `pendingLocation` rides along too, same as every `submit()`
    ///   unit — including the same Task 6 `awaitPendingLocation` wait, in case the pin is still
    ///   `.resolving` when a voice note is saved (e.g. the user toggled it on immediately before
    ///   opening the recorder sheet).
    public func submitVoiceNote(fileURL: URL, durationS: Double? = nil) async -> CaptureOutcome {
        await awaitPendingLocation(timeout: Self.locationAwaitTimeout)
        let attributes = buildAttributes(location: pendingLocation, media: buildMedia(fileName: nil, durationS: durationS))
        do {
            let data = try Data(contentsOf: fileURL)
            let path = makeUploadPath(userId: userId, fileExtension: "m4a")
            try await upload(data, path, "audio/mp4")
            let token = try await accessToken()
            _ = try await api.addFile(path: path, mimeType: "audio/mp4", fileSize: data.count,
                                      content: nil, isPublic: isPublic, attributes: attributes, accessToken: token)
            try? FileManager.default.removeItem(at: fileURL)
            await refreshPendingCount()
            return .saved(count: 1, dropped: 0)
        } catch {
            // Keep the file — this entry's local_file_path is the only reference to it, and the
            // Outbox drain (Task 4) uploads it from exactly this path on retry.
            var payload = [
                "local_file_path": fileURL.path,
                "mime_type": "audio/mp4",
                "is_public": isPublic ? "true" : "false",
            ]
            if let json = attributesPayloadString(attributes) { payload["attributes_json"] = json }
            try? await outbox.enqueue(.file, payload: payload)
            await refreshPendingCount()
            return .queued(count: 1, dropped: 0)
        }
    }

    public func drainOutbox() async {
        if let token = try? await accessToken() {
            // Reuses this view model's own injected `upload` closure so a test that stubs it out
            // (or the app's real `uploadToStorage`) also governs any queued recording's upload,
            // not just the attachments `submit()` uploads directly.
            _ = await outbox.drain(api: api, accessToken: token, userId: userId, upload: upload)
        }
        await refreshPendingCount()
    }

    private func refreshPendingCount() async {
        pendingOutboxCount = await outbox.pending().count
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
    /// - A URL detected anywhere in the typed text is always its own unit (add-url, content = the
    ///   text with the URL substring removed) and always comes FIRST when present, whether or not
    ///   files are attached too. Any attachments then follow as individual add-file units with no
    ///   content — the note already rode the URL.
    /// - No URL, no attachments: a single add-note (or nothing, if the text is empty too).
    /// - No URL, exactly one attachment: one add-file, the typed text as its content.
    /// - No URL, multiple attachments: one add-file per attachment; the FIRST carries the typed
    ///   text as its content, the rest carry none. There is no more separate add-note call for
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

    // MARK: - Upload + send + Outbox fallback

    /// Thrown by `prepare` for failures the Outbox must never see: `Outbox`'s `file` payload
    /// only stores an already-uploaded `file_path` (Task 3's schema assumes the bytes are
    /// already in storage and only the `add-file` registration call may need a retry), so
    /// queuing a path nothing was ever written to would let a later drain register an item
    /// pointing at nothing. An oversized reject is the same story: retrying, live or queued,
    /// can never succeed. Neither is safe to queue — but both are still counted into `submit()`'s
    /// `droppedCount` and surfaced via `CaptureOutcome`'s `dropped`/`.rejected` (fix round: this
    /// used to be logged-and-dropped with no way for the caller to know data was lost — see
    /// task-7-report.md's fix-round addendum).
    private struct UnqueueableFailure: Error { let reason: String }

    private enum ReadyUnit {
        case note(content: String, attributes: ItemAttributes?)
        case url(url: String, note: String, attributes: ItemAttributes?)
        case file(path: String, mimeType: String, fileSize: Int, content: String?, attributes: ItemAttributes?)
    }

    private func prepare(_ unit: CaptureUnit, location: CapturedLocation?) async throws -> ReadyUnit {
        switch unit {
        case .note(let content):
            return .note(content: content, attributes: buildAttributes(location: location))
        case .url(let url, let note):
            return .url(url: url, note: note, attributes: buildAttributes(location: location))
        case .file(let attachment, let content):
            let data = try validatedUploadData(for: attachment)
            let path = makeUploadPath(userId: userId, fileExtension: attachment.fileExtension)
            do {
                try await upload(data, path, attachment.mimeType)
            } catch {
                throw UnqueueableFailure(reason: "upload failed before any bytes reached storage")
            }
            let media = buildMedia(fileName: attachment.fileName, durationS: attachment.durationS)
            let attributes = buildAttributes(location: location, media: media)
            return .file(path: path, mimeType: attachment.mimeType, fileSize: data.count,
                        content: content, attributes: attributes)
        }
    }

    /// `nil` whenever there's nothing to attach (no location pinned, no media facts) — kept as an
    /// `ItemAttributes?`, not an always-present `ItemAttributes()`, so `CaptureAPI`'s own
    /// non-empty check (never send `{}`) has nothing to do for the common case of an unpinned,
    /// non-media unit.
    private func buildAttributes(location: CapturedLocation?, media: MediaAttributes? = nil) -> ItemAttributes? {
        guard location != nil || media != nil else { return nil }
        return ItemAttributes(location: location, media: media)
    }

    private func buildMedia(fileName: String?, durationS: Double?) -> MediaAttributes? {
        guard fileName != nil || durationS != nil else { return nil }
        return MediaAttributes(durationS: durationS, fileName: fileName)
    }

    private func send(_ ready: ReadyUnit, accessToken: String?) async throws -> Item {
        guard let accessToken else { throw CaptureError.badStatus(-1) }   // no session — queueable
        switch ready {
        case .note(let content, let attributes):
            return try await api.addNote(content: content, title: nil, isPublic: isPublic,
                                         attributes: attributes, accessToken: accessToken)
        case .url(let url, let note, let attributes):
            return try await api.addURL(url, note: note, isPublic: isPublic,
                                        attributes: attributes, accessToken: accessToken)
        case .file(let path, let mimeType, let fileSize, let content, let attributes):
            return try await api.addFile(path: path, mimeType: mimeType, fileSize: fileSize, content: content,
                                         isPublic: isPublic, attributes: attributes, accessToken: accessToken)
        }
    }

    private func enqueue(_ ready: ReadyUnit) async {
        let publicFlag = isPublic ? "true" : "false"
        switch ready {
        case .note(let content, let attributes):
            var payload = ["content": content, "is_public": publicFlag]
            if let json = attributesPayloadString(attributes) { payload["attributes_json"] = json }
            try? await outbox.enqueue(.note, payload: payload)
        case .url(let url, let note, let attributes):
            var payload = ["url": url, "content": note, "is_public": publicFlag]
            if let json = attributesPayloadString(attributes) { payload["attributes_json"] = json }
            try? await outbox.enqueue(.url, payload: payload)
        case .file(let path, let mimeType, let fileSize, let content, let attributes):
            var payload = ["file_path": path, "mime_type": mimeType,
                           "file_size": String(fileSize), "is_public": publicFlag]
            if let content { payload["content"] = content }
            if let json = attributesPayloadString(attributes) { payload["attributes_json"] = json }
            try? await outbox.enqueue(.file, payload: payload)
        }
    }

    /// `attributes` serialized to a JSON string for the Outbox's text-only `[String: String]`
    /// payload (Task 5) — `nil` whenever there's nothing worth persisting, same
    /// `nonEmptyJSONObject` gate `CaptureAPI.addAttributes` uses, so a queued entry's eventual
    /// `drain` sends exactly what a live send would have.
    private func attributesPayloadString(_ attributes: ItemAttributes?) -> String? {
        guard let object = attributes?.nonEmptyJSONObject,
              let data = try? JSONSerialization.data(withJSONObject: object)
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Images > 20MB downscale (never rejected); other files mirror the web's per-kind limits
    /// (MediaUploadTypes.ts:26-28): 100MB for audio/video, 20MB for everything else (docs).
    private func validatedUploadData(for attachment: CaptureAttachment) throws -> Data {
        let mb = 1_048_576
        switch attachment.kind {
        case .photo:
            return attachment.data.count > 20 * mb ? downscale(attachment.data) : attachment.data
        case .file:
            let isAudioOrVideo = attachment.mimeType.hasPrefix("video/") || attachment.mimeType.hasPrefix("audio/")
            let limit = (isAudioOrVideo ? 100 : 20) * mb
            guard attachment.data.count <= limit else {
                throw UnqueueableFailure(reason: "\(attachment.mimeType) attachment exceeds \(limit / mb) MB limit")
            }
            return attachment.data
        }
    }
}
