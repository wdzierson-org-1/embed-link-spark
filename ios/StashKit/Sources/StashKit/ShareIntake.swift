import Foundation

/// One already-materialized shared object, ready for `ShareIntake.submit` — the share extension's
/// own `NSItemProvider` → `SharedObject` mapping (Task 7's `ProviderLoader`) happens entirely
/// OUTSIDE this file: that loading is callback/main-actor-ish (`loadFileRepresentation`'s
/// completion runs off an Apple-owned queue, and `NSItemProvider` itself isn't `Sendable`), which
/// would make this whole type impossible to exercise under plain `swift test` if it lived here
/// too. By the time anything in this file sees a `.file`, its bytes are ALREADY durably on local
/// disk — staged via `StagedFileStore.stage`/`stageDownscaledImage` (Task 4) — so `ShareIntake`
/// never touches `NSItemProvider`, never loads a whole file into memory, and has no idea what UTI
/// any of this came from.
public enum SharedObject: Equatable, Sendable {
    case url(String)
    case text(String)
    case file(stagedURL: URL, mimeType: String, fileName: String?, durationS: Double?)
}

/// Tally `ShareIntake.submit` hands back so the extension's compose card can pick the right
/// outcome line ("Saved to Stash" vs "Saved — will sync") without inspecting individual units.
///
/// Unlike `CaptureViewModel.CaptureOutcome`, there is no `.rejected`/`dropped` case here: every
/// `SharedObject.file` already has its bytes durably on local disk by the time `submit` ever sees
/// it (Task 4's `StagedFileStore`), so — exactly like `CaptureViewModel.submitVoiceNote`'s own
/// reasoning — no failure in this type is ever unsafe to hand to the Outbox. `saved + queued +
/// failed` always equals the count of objects `submit` was called with; nothing is ever silently
/// dropped, which is why `failed` exists at all (an Outbox enqueue call can itself fail — an
/// unwritable/full disk — and that must still be counted, never just logged).
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
/// Direct-send-with-durable-Outbox-fallback (plan's "Direct-vs-queue rule"): every unit tries a
/// live send first; ANY failure — network, no session, an oversized file skipping the attempt
/// entirely — falls back to the Outbox, never drops data and never blocks the share sheet waiting
/// on a retry.
public struct ShareIntake: Sendable {
    private let userId: UUID
    private let capture: CaptureAPI
    private let outbox: Outbox
    private let staging: StagedFileStore
    private let directSendLimit: Int
    private let accessToken: @Sendable () async throws -> String
    private let upload: (@Sendable (URL, String, String) async throws -> Void)?

    /// - Parameter upload: `Optional`, not a plain closure with a default expression — Swift
    ///   default-argument expressions can't reference a sibling parameter (`accessToken` isn't in
    ///   scope in a default-argument expression here), the exact constraint `Outbox.drain`'s own
    ///   `upload` parameter (Task 4) already works around the same way, and the same fix applies:
    ///   `nil` (every real call site) is resolved inside `submit()` itself, reusing THAT call's own
    ///   already-fetched token — never an independent second token fetch buried in a default
    ///   closure. This is a deliberate departure from the brief's literal sketch (`=
    ///   uploadToStorageFromFile persisted-shape`), which isn't valid Swift as written.
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

    /// How one unit's attempt resolved — internal bookkeeping only; `submit` folds a whole batch of
    /// these into the public `ShareIntakeResult` tally.
    private enum UnitOutcome { case saved, queued, failed }

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
    public func submit(_ objects: [SharedObject], note: String?, location: CapturedLocation?) async -> ShareIntakeResult {
        let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveNote = (trimmed?.isEmpty ?? true) ? nil : trimmed

        // Fetched once per submit, same reasoning as `CaptureViewModel.submit()`'s own `token`:
        // every unit in this batch resolves against the SAME session snapshot, not whichever
        // session happens to be current partway through an await-laced loop. A `nil` token isn't
        // special-cased further here — every live send below already treats it as an ordinary
        // queueable failure (`CaptureError.badStatus(-1)`), exactly like `CaptureViewModel.send`,
        // so "no session" degrades to "queue the whole batch" rather than blocking the share sheet.
        let token = try? await accessToken()
        let performUpload: @Sendable (URL, String, String) async throws -> Void = upload ?? { fileURL, path, contentType in
            guard let token else { throw CaptureError.badStatus(-1) }
            try await uploadToStorageFromFile(fileURL: fileURL, path: path, contentType: contentType, accessToken: token)
        }

        var saved = 0, queued = 0, failed = 0
        for (index, object) in objects.enumerated() {
            let noteForThisUnit = index == 0 ? effectiveNote : nil
            let outcome: UnitOutcome
            switch object {
            case .url(let url):
                outcome = await handleURL(url, note: noteForThisUnit ?? "", location: location, token: token)
            case .text(let text):
                outcome = await handleText(text, note: noteForThisUnit, location: location, token: token)
            case .file(let stagedURL, let mimeType, let fileName, let durationS):
                outcome = await handleFile(stagedURL: stagedURL, mimeType: mimeType, fileName: fileName,
                                           durationS: durationS, content: noteForThisUnit, location: location,
                                           token: token, performUpload: performUpload)
            }
            switch outcome {
            case .saved: saved += 1
            case .queued: queued += 1
            case .failed: failed += 1
            }
        }
        return ShareIntakeResult(saved: saved, queued: queued, failed: failed)
    }

    // MARK: - Ordering (Task 7, T6-review carry: adopted ordering decision)

    /// Moves the first `.url` case (if any) to index 0, preserving the relative order of
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
        guard let urlIndex = objects.firstIndex(where: {
            if case .url = $0 { return true }
            return false
        }), urlIndex != 0 else { return objects }
        var reordered = objects
        let url = reordered.remove(at: urlIndex)
        reordered.insert(url, at: 0)
        return reordered
    }

    // MARK: - Per-type handling

    private func handleURL(_ url: String, note: String, location: CapturedLocation?, token: String?) async -> UnitOutcome {
        let attributes = buildAttributes(location: location)
        do {
            guard let token else { throw CaptureError.badStatus(-1) }
            _ = try await capture.addURL(url, note: note, isPublic: false, attributes: attributes, accessToken: token)
            return .saved
        } catch {
            var payload = ["url": url, "content": note, "is_public": "false"]
            if let json = attributesJSONString(attributes) { payload["attributes_json"] = json }
            return await enqueueOrFail(.url, payload: payload)
        }
    }

    /// A shared `.text` object's own string already IS its content — unlike `.url`/`.file`, which
    /// have no free text of their own, so an attached note simply BECOMES their whole content
    /// (there's nothing else it could overwrite). A note attaching to a `.text` object instead
    /// AUGMENTS it: `appendNoteParagraph` — the same helper `NotesAppendComposer`'s "append to an
    /// existing item" flow uses — treats the shared text as the existing body and the typed note as
    /// a new paragraph appended after it, so neither is ever silently dropped. This merge behavior
    /// isn't in the brief's Step 1 test list (which never combines a `.text` object with a note);
    /// disclosed as a deliberate, tested addition rather than leaving the combination unspecified.
    private func handleText(_ text: String, note: String?, location: CapturedLocation?, token: String?) async -> UnitOutcome {
        let content = (note.map { $0.isEmpty } ?? true) ? text : appendNoteParagraph(to: text, note: note!)
        let attributes = buildAttributes(location: location)
        do {
            guard let token else { throw CaptureError.badStatus(-1) }
            _ = try await capture.addNote(content: content, title: nil, isPublic: false, attributes: attributes, accessToken: token)
            return .saved
        } catch {
            var payload = ["content": content, "is_public": "false"]
            if let json = attributesJSONString(attributes) { payload["attributes_json"] = json }
            return await enqueueOrFail(.note, payload: payload)
        }
    }

    /// No `UnqueueableFailure`-style split between "upload failed" and "send failed" the way
    /// `CaptureViewModel.prepare`/`send` splits for in-memory `CaptureAttachment` bytes: every
    /// `SharedObject.file` is already durable on local disk (staged before this is ever called), so
    /// — exactly like `CaptureViewModel.submitVoiceNote` — ANY failure anywhere in this method is
    /// always safe, and always correct, to hand to the Outbox via the STAGED path.
    private func handleFile(stagedURL: URL, mimeType: String, fileName: String?, durationS: Double?, content: String?,
                            location: CapturedLocation?, token: String?,
                            performUpload: @Sendable (URL, String, String) async throws -> Void) async -> UnitOutcome {
        let media = buildMedia(fileName: fileName, durationS: durationS)
        let attributes = buildAttributes(location: location, media: media)
        // Attributes only (`StagedFileStore.fileSize`), never `Data(contentsOf:)` — this file may
        // be up to the extension's own multi-item ceiling; the whole point of staging is to never
        // require its bytes in memory just to make a routing decision.
        let fileSize = staging.fileSize(of: stagedURL)

        guard (fileSize ?? 0) <= directSendLimit else {
            // Global Constraints "Direct-vs-queue rule": a file over the limit is NEVER even
            // attempted live — straight to a durable Outbox entry. The staged file is RETAINED
            // (not `discard`ed): `Outbox.drain`'s local-file lane uploads it later from this exact
            // path, and Task 4's `sweepOrphans` recovers it if this process dies before that.
            return await enqueueFile(stagedURL: stagedURL, mimeType: mimeType, content: content, attributes: attributes)
        }

        do {
            guard let token else { throw CaptureError.badStatus(-1) }
            let uploadPath = makeUploadPath(userId: userId, fileExtension: stagedURL.pathExtension)
            try await performUpload(stagedURL, uploadPath, mimeType)
            _ = try await capture.addFile(path: uploadPath, mimeType: mimeType, fileSize: fileSize, content: content,
                                          isPublic: false, attributes: attributes, accessToken: token)
            // Bytes are durably uploaded AND registered — the staged copy is now redundant, and
            // discarding it is NOT optional cleanup: an un-discarded staged file with no Outbox
            // entry pointing at it would look exactly like a crash orphan to `sweepOrphans` once it
            // ages past the 60s grace period, minting a DUPLICATE `.file` entry — and eventually a
            // duplicate item — for bytes that already landed.
            staging.discard(stagedURL)
            return .saved
        } catch {
            // ANY failure here — the upload or `addFile` itself — falls back via the STAGED path,
            // never a maybe-registered `file_path`: mirrors `CaptureViewModel.submitVoiceNote`
            // exactly. A retry re-uploads from the local file to a FRESH path rather than trusting
            // that an upload which may or may not have actually landed is still good.
            return await enqueueFile(stagedURL: stagedURL, mimeType: mimeType, content: content, attributes: attributes)
        }
    }

    private func enqueueFile(stagedURL: URL, mimeType: String, content: String?, attributes: ItemAttributes?) async -> UnitOutcome {
        var payload = ["local_file_path": stagedURL.path, "mime_type": mimeType, "is_public": "false"]
        if let content { payload["content"] = content }
        if let json = attributesJSONString(attributes) { payload["attributes_json"] = json }
        return await enqueueOrFail(.file, payload: payload)
    }

    /// Shared tail of every fallback path: enqueue, and if THAT fails too, count it as `failed` —
    /// never silent (brief: "Outbox enqueue failure → failed+1"), and never a thrown error the
    /// caller has to catch — `submit()` has no `throws` surface at all; its whole contract is to
    /// always finish the batch and hand back a tally, never abort partway through.
    private func enqueueOrFail(_ kind: OutboxEntry.Kind, payload: [String: String]) async -> UnitOutcome {
        do {
            try await outbox.enqueue(kind, payload: payload)
            return .queued
        } catch {
            return .failed
        }
    }

    // MARK: - Attributes helpers (private duplicates of CaptureViewModel's own — see disclosure)

    /// Deliberately duplicated rather than shared with `CaptureViewModel`'s identical-shaped
    /// private helpers of the same name: both are tiny, and extracting a shared free function would
    /// be new public(ish) surface neither the brief nor `CaptureViewModel` asked for, for two call
    /// sites. Same `nil`-collapsing contract either way — never an always-present `ItemAttributes()`
    /// (`CaptureAPI`'s own non-empty check has nothing to do for the common unpinned/non-media unit).
    private func buildAttributes(location: CapturedLocation?, media: MediaAttributes? = nil) -> ItemAttributes? {
        guard location != nil || media != nil else { return nil }
        return ItemAttributes(location: location, media: media)
    }

    private func buildMedia(fileName: String?, durationS: Double?) -> MediaAttributes? {
        guard fileName != nil || durationS != nil else { return nil }
        return MediaAttributes(durationS: durationS, fileName: fileName)
    }

    /// `attributes` serialized to a JSON string for the Outbox's text-only `[String: String]`
    /// payload — mirrors `CaptureViewModel.attributesPayloadString` exactly, so a queued entry's
    /// eventual `drain` sends exactly what a live send would have.
    private func attributesJSONString(_ attributes: ItemAttributes?) -> String? {
        guard let object = attributes?.nonEmptyJSONObject,
              let data = try? JSONSerialization.data(withJSONObject: object)
        else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
