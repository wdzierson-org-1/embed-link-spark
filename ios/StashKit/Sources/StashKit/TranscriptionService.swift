import Foundation
import Observation
import Supabase

/// Plan 14 Task 2 ("Transcribe with speakers"): mirrors the web's `TranscriptContent.tsx`
/// `retranscribe` exactly — resolve the item's stored media URL the same way `Item.thumbnailURL`
/// already does (`ItemRules.swift`; that computed property is generic over `file_path`, not
/// actually thumbnail-specific, so reusing it here is the "same URL resolution" the brief calls
/// for rather than a second hand-rolled copy of the http-vs-storage-path branch), invoke
/// `transcribe-audio` with `{audioUrl, fileName}`, then PATCH ONLY `page_body` + `description` —
/// never `content`, which is the user's own notes and this flow must never touch. Web parity:
/// `supabase.from('items').update({ page_body, description })`.
///
/// Decoded success body of `transcribe-audio` (deployed v27: `gpt-4o-transcribe-diarize`,
/// diarized Markdown in `transcription`). Both fields are optional on the wire — a malformed or
/// empty response is a legitimate failure mode this type has to detect itself, not something the
/// JSON decoder can reject up front.
public struct TranscriptionOutcome: Sendable, Decodable {
    public let transcription: String?
    public let description: String?

    public init(transcription: String?, description: String?) {
        self.transcription = transcription
        self.description = description
    }
}

/// Typed failures for `TranscriptionService.retranscribe` — every case leaves the item's existing
/// `page_body` untouched server-side; this type never mutates anything before a PATCH actually
/// succeeds, so a caller catching any of these is guaranteed the previous transcript is intact.
public enum TranscriptionServiceError: Error, Equatable, Sendable {
    /// No `file_path` on the item — nothing to rebuild from (mirrors the web's `if (!filePath)
    /// return` guard; the UI is expected to hide the button entirely in this case, same as web).
    case noStoredMedia
    /// The `transcribe-audio` invoke itself failed (network, function error, non-2xx).
    case invokeFailed(String)
    /// The function returned a 2xx with no usable transcript text — web parity: `if
    /// (transcriptionError || !data?.transcription?.trim()) throw`.
    case emptyTranscript
    /// The transcript came back fine but the `items` PATCH failed — the OLD transcript is still
    /// the one live on the server; nothing was overwritten.
    case patchFailed(String)
    /// A run for this item is already in progress (possibly started from a sheet that has since
    /// been closed) — nothing new was started.
    case alreadyRunning
}

/// Injection point for the `transcribe-audio` call — mirrors `AccountDeletionTransport`'s "stubbed
/// transport" shape (StashKitTests hits this with a canned/throwing stub, never the network).
public protocol TranscriptionInvoking: Sendable {
    func invoke(audioUrl: String, fileName: String) async throws -> TranscriptionOutcome
}

/// Real network transport. Plan 15 (M9): its OWN request and session, not
/// `StashClient.shared.functions.invoke` — that goes through `URLSession.shared` with the default
/// 60 s request timeout, but `transcribe-audio` is fully synchronous (download → diarized
/// transcription → summary → respond), so the first response byte of a long memo can take minutes.
/// At 60 s the client gave up with "Couldn't update the transcript" while the server finished and
/// its (paid-for) result was thrown away.
///
/// The client now allows 300 s, so it is never the one to give up first — but the Supabase
/// gateway itself answers 504 after ~150 s with no response byte, so a memo whose diarization takes
/// longer than that still fails (and its result is still lost). Fixing that needs the server's
/// async transcription job (the server PATCHes, the client observes) — a follow-up, not built here.
public struct FunctionsTranscriptionInvoker: TranscriptionInvoking {
    /// How long the client waits for `transcribe-audio`'s response (it sends nothing until it's
    /// done). The gateway's own ~150 s limit is the effective ceiling today.
    public static let requestTimeout: TimeInterval = 300

    /// One session for every run, with the request and resource timeouts both covering a full
    /// `requestTimeout` wait (the per-request `timeoutInterval` is set too, so neither the session
    /// default nor the request default can cut it short).
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = requestTimeout
        configuration.timeoutIntervalForResource = requestTimeout + 60
        return URLSession(configuration: configuration)
    }()

    public init() {}

    /// `POST <supabase>/functions/v1/transcribe-audio` with the platform's two auth headers and
    /// `{audioUrl, fileName}` — the same body the web sends. Pure, for tests.
    public static func request(audioUrl: String, fileName: String, accessToken: String) throws -> URLRequest {
        var request = URLRequest(url: StashConfig.supabaseURL.appending(path: "/functions/v1/transcribe-audio"))
        request.httpMethod = "POST"
        request.timeoutInterval = requestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(StashConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["audioUrl": audioUrl, "fileName": fileName])
        return request
    }

    public func invoke(audioUrl: String, fileName: String) async throws -> TranscriptionOutcome {
        let accessToken = try await StashClient.shared.auth.session.accessToken
        let request = try Self.request(audioUrl: audioUrl, fileName: fileName, accessToken: accessToken)
        let (data, response) = try await Self.session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard (200..<300).contains(status) else {
            throw TranscriptionServiceError.invokeFailed("transcribe-audio answered HTTP \(status)")
        }
        return try JSONDecoder().decode(TranscriptionOutcome.self, from: data)
    }
}

/// Which items have a "Transcribe with speakers" run in flight, app-wide (plan 15, M9). A run can
/// take minutes and keeps going after its sheet is closed, so the busy state lives here rather than
/// in the sheet: reopening the item still shows "Transcribing…", and a second (duplicate, paid)
/// run for the same item can't be started.
@MainActor @Observable
public final class TranscriptionActivity {
    public static let shared = TranscriptionActivity()

    public private(set) var itemIds: Set<UUID> = []

    public init() {}

    public func isRunning(_ itemId: UUID) -> Bool { itemIds.contains(itemId) }

    /// `false` when a run for `itemId` is already in progress.
    func begin(_ itemId: UUID) -> Bool { itemIds.insert(itemId).inserted }

    func end(_ itemId: UUID) { itemIds.remove(itemId) }
}

/// Injection point for the `page_body`/`description`-only PATCH — deliberately its OWN protocol,
/// not a reuse of `ItemPatching`/`ItemPatch`: `ItemPatch` has no `pageBody` field at all (notes
/// autosave and the title/description/content fields never touch that column — see its own doc
/// comment), and giving it one just for this one call site would let every other `ItemPatch` user
/// accidentally start writing `page_body` too. A narrow, purpose-built protocol keeps the
/// "never touches `content`" guarantee enforced by the type signature itself, not just convention.
public protocol TranscriptPatching: Sendable {
    func patchTranscript(itemId: UUID, pageBody: String, description: String?) async throws -> Item
}

public struct SupabaseTranscriptPatcher: TranscriptPatching {
    public init() {}

    public func patchTranscript(itemId: UUID, pageBody: String, description: String?) async throws -> Item {
        var body: [String: AnyJSON] = ["page_body": .string(pageBody)]
        // `description` is genuinely optional on the wire (`TranscriptionOutcome.description`) —
        // web parity sends whatever `data.description` is, including `null`/absent, rather than
        // inventing a fallback; a present-but-nil value here is a deliberate "clear it" write,
        // not "leave the column alone" (unlike `ItemPatch.attributes`'s different convention).
        body["description"] = description.map(AnyJSON.string) ?? .null
        let data = try await StashClient.shared.from("items")
            .update(body)
            .eq("id", value: itemId.uuidString)
            .select(Item.detailColumns)
            .single()
            .execute().data
        return try Item.decoder.decode(Item.self, from: data)
    }
}

/// Orchestrates one "Transcribe with speakers" run: resolve media URL → invoke → guard non-empty
/// → PATCH `page_body`/`description` → schedule an embedding refresh from the merged row (same
/// decoupled, never-awaited shape `ItemEditor.save` already uses via the shared
/// `EmbeddingRefresher`) → return the updated item for the caller to adopt into its own state and
/// the item store. Any thrown error means nothing was written — the caller's existing `item.pageBody`
/// is still correct to display.
@MainActor
public final class TranscriptionService {
    private let invoker: TranscriptionInvoking
    private let patcher: TranscriptPatching
    private let refresher: EmbeddingRefresher
    private let activity: TranscriptionActivity
    private let writeQueue: ItemWriteQueue

    /// `activity`/`writeQueue` default to the app-wide shared instances (tests pass their own).
    public init(invoker: TranscriptionInvoking = FunctionsTranscriptionInvoker(),
                patcher: TranscriptPatching = SupabaseTranscriptPatcher(),
                refresher: EmbeddingRefresher,
                activity: TranscriptionActivity? = nil,
                writeQueue: ItemWriteQueue? = nil) {
        self.invoker = invoker
        self.patcher = patcher
        self.refresher = refresher
        self.activity = activity ?? .shared
        self.writeQueue = writeQueue ?? .shared
    }

    public func retranscribe(item: Item) async throws -> Item {
        // `item.thumbnailURL` (ItemRules.swift) is the one place this codebase already resolves
        // `file_path` into a playable/fetchable URL — "an http-prefixed external URL or storage
        // path either way" per that property's own doc comment — so reusing it here is genuinely
        // the SAME resolution, not a parallel copy that could drift from it.
        guard let filePath = item.filePath, !filePath.isEmpty, let audioURL = item.thumbnailURL else {
            throw TranscriptionServiceError.noStoredMedia
        }
        guard activity.begin(item.id) else { throw TranscriptionServiceError.alreadyRunning }
        defer { activity.end(item.id) }
        let fileName = filePath.split(separator: "/").last.map(String.init) ?? filePath

        let outcome: TranscriptionOutcome
        do {
            outcome = try await invoker.invoke(audioUrl: audioURL.absoluteString, fileName: fileName)
        } catch let error as TranscriptionServiceError {
            throw error
        } catch {
            throw TranscriptionServiceError.invokeFailed(error.localizedDescription)
        }

        guard let transcription = outcome.transcription?.trimmingCharacters(in: .whitespacesAndNewlines),
              !transcription.isEmpty else {
            throw TranscriptionServiceError.emptyTranscript
        }

        let updated: Item
        do {
            // Same per-item write order as every detail-sheet save (`ItemWriteQueue`): this PATCH
            // also writes `description`, so it must not overtake (or be overtaken by) a queued edit.
            updated = try await writeQueue.enqueue(itemId: item.id) { [patcher] in
                try await patcher.patchTranscript(itemId: item.id, pageBody: transcription,
                                                  description: outcome.description)
            }
        } catch {
            throw TranscriptionServiceError.patchFailed(error.localizedDescription)
        }

        await refresher.schedule(updated)
        return updated
    }
}
