import Foundation
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
}

/// Injection point for the `transcribe-audio` call — mirrors `AccountDeletionTransport`'s "stubbed
/// transport" shape (StashKitTests hits this with a canned/throwing stub, never the network).
public protocol TranscriptionInvoking: Sendable {
    func invoke(audioUrl: String, fileName: String) async throws -> TranscriptionOutcome
}

/// Real network transport: `StashClient.shared.functions.invoke`, same call shape
/// `SupabaseItemPatcher.suggestTags` and `SupabaseEmbeddingSyncer.replaceEmbeddings` already use
/// elsewhere in StashKit for other edge functions.
public struct FunctionsTranscriptionInvoker: TranscriptionInvoking {
    public init() {}

    public func invoke(audioUrl: String, fileName: String) async throws -> TranscriptionOutcome {
        let body: [String: AnyJSON] = ["audioUrl": .string(audioUrl), "fileName": .string(fileName)]
        return try await StashClient.shared.functions
            .invoke("transcribe-audio", options: FunctionInvokeOptions(body: body))
    }
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

    public init(invoker: TranscriptionInvoking = FunctionsTranscriptionInvoker(),
                patcher: TranscriptPatching = SupabaseTranscriptPatcher(),
                refresher: EmbeddingRefresher) {
        self.invoker = invoker
        self.patcher = patcher
        self.refresher = refresher
    }

    public func retranscribe(item: Item) async throws -> Item {
        // `item.thumbnailURL` (ItemRules.swift) is the one place this codebase already resolves
        // `file_path` into a playable/fetchable URL — "an http-prefixed external URL or storage
        // path either way" per that property's own doc comment — so reusing it here is genuinely
        // the SAME resolution, not a parallel copy that could drift from it.
        guard let filePath = item.filePath, !filePath.isEmpty, let audioURL = item.thumbnailURL else {
            throw TranscriptionServiceError.noStoredMedia
        }
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
            updated = try await patcher.patchTranscript(itemId: item.id, pageBody: transcription,
                                                          description: outcome.description)
        } catch {
            throw TranscriptionServiceError.patchFailed(error.localizedDescription)
        }

        await refresher.schedule(updated)
        return updated
    }
}
