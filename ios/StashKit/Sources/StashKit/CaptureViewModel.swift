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

    public init(id: UUID = UUID(), data: Data, fileExtension: String, mimeType: String, kind: Kind) {
        self.id = id
        self.data = data
        self.fileExtension = fileExtension
        self.mimeType = mimeType
        self.kind = kind
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
@MainActor
@Observable
public final class CaptureViewModel {
    public var text: String = ""
    public var attachments: [CaptureAttachment] = []
    public var isPublic: Bool = false
    public private(set) var pendingOutboxCount: Int = 0

    private let userId: UUID
    private let api: CaptureAPI
    private let outbox: Outbox
    private let upload: @Sendable (Data, String, String) async throws -> Void
    private let accessToken: @Sendable () async throws -> String
    private let downscale: @Sendable (Data) -> Data

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
        downscale: @escaping @Sendable (Data) -> Data = { $0 }
    ) {
        self.userId = userId
        self.api = api
        self.outbox = outbox ?? Outbox(directory: Outbox.defaultDirectory(userId: userId))
        self.upload = upload
        self.accessToken = accessToken
        self.downscale = downscale
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

        var savedCount = 0
        var queuedCount = 0
        var droppedCount = 0
        for unit in units {
            do {
                let ready = try await prepare(unit)
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

    public func drainOutbox() async {
        if let token = try? await accessToken() {
            _ = await outbox.drain(api: api, accessToken: token)
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

    /// text containing a URL -> add-url (content = text minus the URL); text only -> add-note;
    /// ONE file (+ optional text) -> upload + add-file with that text as content; MULTIPLE files
    /// -> one add-file per file with no content, plus a separate add-note for any leftover text.
    /// Attachments take priority: URL detection only runs when there are none (mirrors the
    /// web's "single link, no media items" gate — UnifiedInputPanel.tsx:802).
    private func route() -> [CaptureUnit] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if attachments.isEmpty {
            if let rawURL = detectFirstURL(in: trimmed) {
                let url = stripTrailingPunctuation(rawURL)
                var note = trimmed
                if let range = trimmed.range(of: rawURL) {
                    note = trimmed.replacingCharacters(in: range, with: "")
                }
                note = note.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespaces)
                return [.url(url: url, note: note)]
            }
            return trimmed.isEmpty ? [] : [.note(content: trimmed)]
        }

        if attachments.count == 1 {
            return [.file(attachments[0], content: trimmed.isEmpty ? nil : trimmed)]
        }

        var units: [CaptureUnit] = attachments.map { .file($0, content: nil) }
        if !trimmed.isEmpty { units.append(.note(content: trimmed)) }
        return units
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
        case note(content: String)
        case url(url: String, note: String)
        case file(path: String, mimeType: String, fileSize: Int, content: String?)
    }

    private func prepare(_ unit: CaptureUnit) async throws -> ReadyUnit {
        switch unit {
        case .note(let content):
            return .note(content: content)
        case .url(let url, let note):
            return .url(url: url, note: note)
        case .file(let attachment, let content):
            let data = try validatedUploadData(for: attachment)
            let path = makeUploadPath(userId: userId, fileExtension: attachment.fileExtension)
            do {
                try await upload(data, path, attachment.mimeType)
            } catch {
                throw UnqueueableFailure(reason: "upload failed before any bytes reached storage")
            }
            return .file(path: path, mimeType: attachment.mimeType, fileSize: data.count, content: content)
        }
    }

    private func send(_ ready: ReadyUnit, accessToken: String?) async throws -> Item {
        guard let accessToken else { throw CaptureError.badStatus(-1) }   // no session — queueable
        switch ready {
        case .note(let content):
            return try await api.addNote(content: content, title: nil, isPublic: isPublic, accessToken: accessToken)
        case .url(let url, let note):
            return try await api.addURL(url, note: note, isPublic: isPublic, accessToken: accessToken)
        case .file(let path, let mimeType, let fileSize, let content):
            return try await api.addFile(path: path, mimeType: mimeType, fileSize: fileSize,
                                         content: content, isPublic: isPublic, accessToken: accessToken)
        }
    }

    private func enqueue(_ ready: ReadyUnit) async {
        let publicFlag = isPublic ? "true" : "false"
        switch ready {
        case .note(let content):
            try? await outbox.enqueue(.note, payload: ["content": content, "is_public": publicFlag])
        case .url(let url, let note):
            try? await outbox.enqueue(.url, payload: ["url": url, "content": note, "is_public": publicFlag])
        case .file(let path, let mimeType, let fileSize, let content):
            var payload = ["file_path": path, "mime_type": mimeType,
                           "file_size": String(fileSize), "is_public": publicFlag]
            if let content { payload["content"] = content }
            try? await outbox.enqueue(.file, payload: payload)
        }
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
