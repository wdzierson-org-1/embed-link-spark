import Foundation
import Supabase

/// Port of the web's `items` PATCH / delete / tag flows (itemOperations.ts, useTags.ts,
/// useEditItemSheet.ts) — save-skip-when-unchanged, cascade delete, and the
/// share/unshare sticky-note rule.

// MARK: - ItemPatch

public struct ItemPatch: Equatable, Sendable {
    public var url: String?
    public var title: String?
    public var description: String?
    public var content: String?
    public var supplementalNote: String?
    public var isPublic: Bool?
    /// The FULL `items.attributes` blob to write (never a per-key merge — same whole-value-
    /// replace convention as every other field here), driven by the detail sheet's `LocationRow`
    /// (Task 8). `nil` means "don't touch this column" (key absent from `restBody`), same
    /// convention as every other `Optional` field on this type — NOT the same as sending `{}`,
    /// which would wipe every attribute the row already has. An empty-but-present
    /// `ItemAttributes` (e.g. the user just cleared their item's only attribute) is a real,
    /// intentional value and DOES get sent as `{}` — see `restBody`'s attributes branch below.
    public var attributes: ItemAttributes?

    public init(title: String? = nil, description: String? = nil, content: String? = nil,
                supplementalNote: String? = nil, isPublic: Bool? = nil, attributes: ItemAttributes? = nil,
                url: String? = nil) {
        self.url = url
        self.title = title
        self.description = description
        self.content = content
        self.supplementalNote = supplementalNote
        self.isPublic = isPublic
        self.attributes = attributes
    }

    public var isEmpty: Bool {
        title == nil && description == nil && content == nil && supplementalNote == nil
            && isPublic == nil && attributes == nil && url == nil
    }

    /// Any of the search-relevant text fields changed — mirrors web's
    /// `['title','description','content','supplemental_note'].some(field => field in updates)`,
    /// which gates whether a save schedules an embedding refresh. Deliberately excludes
    /// `attributes`: web parity, `itemOperations.ts:100-101` — an attributes-only PATCH (e.g.
    /// this task's location-row edit) changes nothing the server embeds (`generate-embeddings`
    /// builds the text from the saved row; a location isn't part of it), so it must never
    /// schedule a refresh either.
    public var touchesTextFields: Bool {
        title != nil || description != nil || content != nil || supplementalNote != nil
    }

    /// snake_case PATCH body, containing only the fields that were actually set on this patch.
    ///
    /// `supplementalNote == ""` is a deliberate SQL-null convention, not a real empty-string
    /// value: the web's un-share flow sends `supplemental_note: null` (see
    /// useEditItemSheet.ts:134) to delete a per-share sticky note, and Swift's `Optional<String>`
    /// has no way to distinguish "clear this field" from "leave it alone" other than reusing the
    /// empty string as the clear signal. So here `supplementalNote == ""` maps to a `null` entry
    /// in `restBody` (key present, value nil) while `supplementalNote == nil` means "don't touch
    /// the column" (key absent). `updateValue(_:forKey:)` is required for that null entry because
    /// `dict[key] = nil` on a `[String: Any?]` deletes the key instead of storing a null value.
    ///
    /// `attributes` uses `ItemAttributes.jsonObject()`'s own Optional contract (Task 3) instead:
    /// `nil` there means "can't encode, do not send" and never falls back to `{}` (which would
    /// silently wipe every attribute the row already has), so both `attributes == nil` (this
    /// patch doesn't touch the column) and a `jsonObject()` encode failure leave the `"attributes"`
    /// key out of `restBody` entirely — only a successfully-encoded object (which CAN legitimately
    /// be `[:]`) is written.
    public var restBody: [String: Any?] {
        var body: [String: Any?] = [:]
        if let url { body["url"] = url }
        if let title { body["title"] = title }
        if let description { body["description"] = description }
        if let content { body["content"] = content }
        if let supplementalNote {
            body.updateValue(supplementalNote.isEmpty ? nil : supplementalNote, forKey: "supplemental_note")
        }
        if let isPublic { body["is_public"] = isPublic }
        if let attributes, let object = attributes.jsonObject() {
            body["attributes"] = object
        }
        return body
    }
}

/// Changed-fields-only diff against `snapshot`, matching the web's `flushAndFinalSave`
/// (useEditItemSave.ts:95-118): compare the live draft to the value the item had when editing
/// began, treat a nil snapshot field as `""` for comparison purposes, and only put a field on the
/// patch when it actually differs. `content` isn't part of THIS diff — notes autosave (both
/// plain-text whole-field edits and rich-note TipTap paragraph appends) through their own separate
/// save call (`ItemDetailView.flushNotes`), on their own debounce, never through this field diff.
public func changedFields(from snapshot: Item, title: String, description: String,
                           supplementalNote: String) -> ItemPatch {
    var patch = ItemPatch()
    if title != (snapshot.title ?? "") { patch.title = title }
    if description != (snapshot.description ?? "") { patch.description = description }
    if supplementalNote != (snapshot.supplementalNote ?? "") { patch.supplementalNote = supplementalNote }
    return patch
}

// MARK: - ItemPatching

public protocol ItemPatching: Sendable {
    /// Throws `ItemEditorError.itemNotFound` when no row matched (deleted, or not this user's).
    func patch(itemId: UUID, patch: ItemPatch) async throws -> Item
    /// The row's current `attributes` blob, or `nil` when the row no longer exists. Used by
    /// `PendingEdits.flush` to apply a queued location onto whatever the server holds NOW instead
    /// of writing back a blob that may be hours old (plan 15, H5/M8).
    func currentAttributes(itemId: UUID) async throws -> ItemAttributes?
    func deleteItemCascade(itemId: UUID) async throws
    func itemTags(itemId: UUID) async throws -> [StashTag]
    func addTag(named: String, userId: UUID, itemId: UUID) async throws
    func removeTag(tagId: UUID, itemId: UUID) async throws
    func suggestTags(title: String, content: String, description: String, available: [String]) async throws -> [String]
}

// MARK: - SupabaseItemPatcher

public struct SupabaseItemPatcher: ItemPatching {
    public init() {}

    public func patch(itemId: UUID, patch: ItemPatch) async throws -> Item {
        do {
            let data = try await StashClient.shared.from("items")
                .update(Self.jsonBody(patch.restBody))
                .eq("id", value: itemId.uuidString)
                .select(Item.detailColumns)
                .single()
                .execute().data
            return try Item.decoder.decode(Item.self, from: data)
        } catch let error as PostgrestError where error.code == "PGRST116" {
            // `.single()` on zero matched rows: the item is gone (or RLS hides it). Distinct from a
            // transport failure so a queued edit for a deleted item is dropped, not retried forever.
            throw ItemEditorError.itemNotFound
        }
    }

    public func currentAttributes(itemId: UUID) async throws -> ItemAttributes? {
        struct Row: Decodable { let attributes: ItemAttributes? }
        let data = try await StashClient.shared.from("items")
            .select("attributes")
            .eq("id", value: itemId.uuidString)
            .limit(1)
            .execute().data
        guard let row = try JSONDecoder().decode([Row].self, from: data).first else { return nil }
        return row.attributes ?? ItemAttributes()
    }

    /// Web order (itemOperations.ts:135-155): embeddings rows first, then the item row. The
    /// embeddings delete is best-effort, not load-bearing — `embeddings.item_id` carries an
    /// `ON DELETE CASCADE` FK to `items`, so the row is removed regardless once the item delete
    /// below succeeds; the manual delete here only saves a moment of dangling rows in between.
    ///
    /// Plan 12 feedback round 3, Task 1 root cause — confirmed live against production: a
    /// PostgREST DELETE whose target row doesn't satisfy the table's RLS policy (or simply
    /// doesn't exist) still returns an HTTP SUCCESS status with an empty representation body —
    /// `curl -X DELETE .../items?id=eq.<nonexistent-or-not-mine> -H "Prefer:
    /// return=representation"` → `200 []`, no error at any layer. supabase-swift's `.delete()`
    /// already defaults to `Prefer: return=representation` (see `PostgrestQueryBuilder.delete`),
    /// so that `[]` body was ALWAYS coming back — this method just never read it, so a 0-row
    /// no-op delete was indistinguishable from a real one and `try await ... .execute()` never
    /// threw. The caller (`ItemDetailView.performDelete`) then treated that as success:
    /// `isDeleted = true`, sheet dismissed, and the row — never actually removed server-side —
    /// was still there on the very next list fetch (Will's on-device report: "deleted it...
    /// still showing in the list, pull-refresh didn't help"; pull-to-refresh re-fetches the
    /// TRUE server state, which genuinely still had the row). `.select("id")` narrows the
    /// representation payload to just the column this check needs; decoding it into a non-empty
    /// array is now the actual proof of deletion, not just the absence of a thrown error.
    public func deleteItemCascade(itemId: UUID) async throws {
        do {
            try await StashClient.shared.from("embeddings").delete()
                .eq("item_id", value: itemId.uuidString).execute()
        } catch {
            // Web parity (itemOperations.ts:141-144): never fail the delete over this — the
            // DB's ON DELETE CASCADE on embeddings.item_id covers it regardless.
            print("Embeddings delete failed (non-fatal): \(error)")
        }
        struct DeletedRow: Decodable { let id: UUID }
        let data = try await StashClient.shared.from("items").delete()
            .eq("id", value: itemId.uuidString)
            .select("id")
            .execute().data
        // Final wave (F6): a decode FAILURE (malformed/unexpected body — a real server-side
        // anomaly) used to fold into the exact same "matched no rows" bucket as a genuinely
        // empty `[]` array (the expected, well-understood RLS/stale-id shape this whole method's
        // doc comment above is about). Distinguished now so the two get their own error cases —
        // `deleteResponseUnreadable` can't reuse `deleteMatchedNoRows`'s "it may not exist
        // anymore or you may not have permission" copy, which would be actively misleading for a
        // response the client couldn't even parse.
        guard let deletedRows = try? JSONDecoder().decode([DeletedRow].self, from: data) else {
            throw ItemEditorError.deleteResponseUnreadable
        }
        guard !deletedRows.isEmpty else {
            throw ItemEditorError.deleteMatchedNoRows
        }
    }

    public func itemTags(itemId: UUID) async throws -> [StashTag] {
        struct Row: Decodable { let tags: StashTag }
        let rows: [Row] = try await StashClient.shared.from("item_tags")
            .select("tags(id,name,usage_count)")
            .eq("item_id", value: itemId.uuidString)
            .execute().value
        return rows.map(\.tags)
    }

    public func addTag(named: String, userId: UUID, itemId: UUID) async throws {
        let tagId: UUID = try await StashClient.shared
            .rpc("increment_tag_usage", params: ["tag_name": named.lowercased(), "user_uuid": userId.uuidString])
            .execute().value

        struct ExistingRow: Decodable { let id: UUID }
        let existing: ExistingRow? = try await StashClient.shared.from("item_tags")
            .select("id")
            .eq("item_id", value: itemId.uuidString)
            .eq("tag_id", value: tagId.uuidString)
            .maybeSingle()
            .execute().value
        guard existing == nil else { return }

        try await StashClient.shared.from("item_tags")
            .insert(["item_id": itemId.uuidString, "tag_id": tagId.uuidString])
            .execute()
    }

    public func removeTag(tagId: UUID, itemId: UUID) async throws {
        try await StashClient.shared.from("item_tags").delete()
            .eq("item_id", value: itemId.uuidString)
            .eq("tag_id", value: tagId.uuidString)
            .execute()
    }

    public func suggestTags(title: String, content: String, description: String, available: [String]) async throws -> [String] {
        struct SuggestResponse: Decodable { let relevantTags: [String] }
        let body: [String: AnyJSON] = [
            "title": .string(title),
            "content": .string(content),
            "description": .string(description),
            "availableTags": .array(available.map(AnyJSON.string)),
        ]
        let response: SuggestResponse = try await StashClient.shared.functions
            .invoke("get-relevant-tags", options: FunctionInvokeOptions(body: body))
        return response.relevantTags
    }

    /// `.update()` requires an `Encodable` body; `ItemPatch.restBody`'s `[String: Any?]` isn't
    /// one, so this converts field-by-field into `[String: AnyJSON]` (`AnyJSON: Codable`, hence
    /// the dictionary is `Encodable`). Every restBody value is a `String`, `Bool`, the
    /// `[String: Any]` attributes blob (Task 8's `ItemAttributes.jsonObject()`), or the null
    /// convention described on `restBody` — the switch's `default` is unreachable in practice.
    private static func jsonBody(_ body: [String: Any?]) -> [String: AnyJSON] {
        var result: [String: AnyJSON] = [:]
        for (key, value) in body {
            switch value {
            case .none: result[key] = .null
            case let string as String: result[key] = .string(string)
            case let bool as Bool: result[key] = .bool(bool)
            case let object as [String: Any]:
                // Drop the key entirely on a (practically unreachable — see doc comment below)
                // conversion failure rather than falling back to `.null`/`.object([:])`, which
                // would silently wipe every attribute the row already has.
                if let json = anyJSON(fromJSONObject: object) { result[key] = json }
            default: result[key] = .null
            }
        }
        return result
    }

    /// Round-trips a `JSONSerialization`-ready `[String: Any]` (only ever `ItemAttributes.
    /// jsonObject()`'s output in practice) into `AnyJSON.object` via `Data`, since `AnyJSON` has
    /// no direct `[String: Any]` initializer — only one for a `Codable` VALUE
    /// (`AnyJSON.init(_: some Codable)`), which a heterogeneous `[String: Any]` doesn't conform
    /// to. Returns `nil` on failure, which should be unreachable in practice: `object` already
    /// passed `JSONSerialization` once, inside `jsonObject()` itself, to get here.
    private static func anyJSON(fromJSONObject object: [String: Any]) -> AnyJSON? {
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let json = try? JSONDecoder().decode(AnyJSON.self, from: data)
        else { return nil }
        return json
    }
}

// MARK: - ItemEditor

public enum ItemEditorError: Error, Equatable {
    /// `save` was called with a no-op patch; web's `flushAndFinalSave` just returns early
    /// instead — but a Swift `-> Item` return can't produce "nothing happened" without either an
    /// optional return or a thrown signal, so callers that don't care use `try?`.
    case emptyPatch
    /// Plan 12 feedback round 3, Task 1 (Will, on-device: "deleted [a note] from the detail
    /// sheet, and the item is still showing in the list. pull-refresh didn't help"): the items
    /// DELETE request completed with an HTTP success status but matched zero rows server-side —
    /// see `SupabaseItemPatcher.deleteItemCascade`'s doc comment for the confirmed root cause
    /// (RLS silently filters the row out of the DELETE's candidate set rather than erroring).
    /// UI copy: "Couldn't delete this item — it may not exist anymore or you may not have
    /// permission."
    case deleteMatchedNoRows
    /// Final wave (F6): the DELETE's representation body came back but couldn't be decoded as
    /// `[{id: UUID}]` at all — a genuinely unexpected server response, NOT the well-understood
    /// "matched zero rows" shape `deleteMatchedNoRows` covers (which decodes cleanly to `[]`).
    /// Kept distinct so the two never share misleading UI copy.
    case deleteResponseUnreadable
    /// A PATCH matched no row: the item was deleted (here or on another device) or isn't visible
    /// to this user. Plan 15: lets `PendingEdits` drop a queued edit for a deleted item instead of
    /// retrying it on every refresh forever.
    case itemNotFound
}

// MARK: - ItemWriteQueue

/// Runs every write to one item strictly in call order, one at a time (plan 15, H5).
///
/// The detail sheet now closes without waiting on the network and hands anything unconfirmed to
/// `PendingEdits`, whose flush can start while one of the sheet's own PATCHes for the same item is
/// still in flight. Two concurrent PATCHes can land out of order, and the older value would then
/// win on the server. With every writer (`ItemEditor` instances, `TranscriptionService`) going
/// through the one shared queue, a later write is only sent once the earlier one has finished, so
/// the server always ends with the newest value. Different items never wait on each other.
///
/// Work runs in unstructured tasks: a caller that goes away (a dismissed sheet) never cancels a
/// write already queued.
@MainActor
public final class ItemWriteQueue {
    public static let shared = ItemWriteQueue()

    private var tails: [UUID: Task<Void, Never>] = [:]

    public init() {}

    /// Runs `operation` after every write to `itemId` enqueued before it has finished (whether it
    /// succeeded or not), and returns its result.
    public func enqueue<T: Sendable>(itemId: UUID, _ operation: @escaping @MainActor () async throws -> T) async throws -> T {
        let previous = tails[itemId]
        let work = Task<T, Error> { @MainActor in
            _ = await previous?.value
            return try await operation()
        }
        let tail = Task<Void, Never> { @MainActor in _ = await work.result }
        tails[itemId] = tail
        let result = await work.result
        if tails[itemId] == tail { tails[itemId] = nil }
        return try result.get()
    }

    /// True while a write to `itemId` is queued or running.
    public func isBusy(_ itemId: UUID) -> Bool { tails[itemId] != nil }
}

/// What `ItemEditor.saveLatest` did: `item` is the saved row, or `nil` when the patch built at the
/// write's turn turned out to be empty (nothing left to send). `context` is whatever the builder
/// returned alongside the patch.
public struct QueuedSave<Context: Sendable>: Sendable {
    public let item: Item?
    public let patch: ItemPatch
    public let context: Context
}

/// Backs the item detail view: save/delete/public-toggle/tag operations, all delegating network
/// work to an injected `ItemPatching` so the pure diff/patch-building logic (this type + the
/// free functions above) can be tested without touching Supabase.
@MainActor
public final class ItemEditor {
    private let patcher: ItemPatching
    private let refresher: EmbeddingRefresher
    private let writeQueue: ItemWriteQueue

    /// `writeQueue` defaults to the app-wide `ItemWriteQueue.shared` (tests pass their own).
    public init(patcher: ItemPatching, refresher: EmbeddingRefresher, writeQueue: ItemWriteQueue? = nil) {
        self.patcher = patcher
        self.refresher = refresher
        self.writeQueue = writeQueue ?? .shared
    }

    /// Saves resolve on the PATCH alone; embedding regeneration is scheduled separately (from the
    /// full merged row so a partial patch can't wipe the rest of the item's searchable content)
    /// and never awaited here — see EmbeddingRefresher. Plan 15: sent through `ItemWriteQueue`, so
    /// it goes out only after every earlier write to the same item has finished.
    public func save(itemId: UUID, patch: ItemPatch) async throws -> Item {
        guard !patch.isEmpty else { throw ItemEditorError.emptyPatch }
        return try await writeQueue.enqueue(itemId: itemId) { [patcher, refresher] in
            let addressPatch = try await Self.preparingAddress(patch, itemId: itemId, patcher: patcher)
            let merged = try await patcher.patch(itemId: itemId, patch: addressPatch)
            if patch.touchesTextFields {
                await refresher.schedule(merged)
            }
            return merged
        }
    }

    /// Like `save`, but the patch is built by `prepare` when this write's turn comes — after every
    /// earlier write to the item has finished — so a queued flush always sends the newest values
    /// rather than whatever was pending when it was scheduled. `prepare` returning `nil` means
    /// "nothing to do" (the method returns `nil`); an empty patch is reported back without a
    /// request (`QueuedSave.item == nil`).
    public func saveLatest<Context: Sendable>(
        itemId: UUID,
        prepare: @escaping @MainActor () async throws -> (ItemPatch, Context)?
    ) async throws -> QueuedSave<Context>? {
        try await saveLatest(itemId: itemId, prepare: prepare, landed: { _ in })
    }

    /// `saveLatest`, telling `landed` about a PATCH that succeeded while the write still holds the
    /// item's slot — before any later write to the item builds its patch (`PendingEdits` notes
    /// what reached the server there; plan 16 review P-3).
    func saveLatest<Context: Sendable>(
        itemId: UUID,
        prepare: @escaping @MainActor () async throws -> (ItemPatch, Context)?,
        landed: @escaping @MainActor (QueuedSave<Context>) -> Void
    ) async throws -> QueuedSave<Context>? {
        try await writeQueue.enqueue(itemId: itemId) { [patcher, refresher] in
            guard let prepared = try await prepare() else { return nil }
            let (patch, context) = prepared
            guard !patch.isEmpty else { return QueuedSave(item: nil, patch: patch, context: context) }
            let addressPatch = try await Self.preparingAddress(patch, itemId: itemId, patcher: patcher)
            let merged = try await patcher.patch(itemId: itemId, patch: addressPatch)
            let saved = QueuedSave(item: merged, patch: patch, context: context)
            landed(saved)
            if patch.touchesTextFields {
                await refresher.schedule(merged)
            }
            return saved
        }
    }

    /// Read fresh metadata in the item's write slot, including after an offline replay. The
    /// durable queue stores URL intent only; it never carries an old link/enrichment snapshot.
    private static func preparingAddress(_ patch: ItemPatch, itemId: UUID,
                                         patcher: ItemPatching) async throws -> ItemPatch {
        guard patch.url != nil else { return patch }
        guard let current = try await patcher.currentAttributes(itemId: itemId) else {
            throw ItemEditorError.itemNotFound
        }
        return LinkAddressEdit.preparing(patch, currentAttributes: current)
    }

    /// The row's current `attributes`, or `nil` when it no longer exists.
    public func currentAttributes(itemId: UUID) async throws -> ItemAttributes? {
        try await patcher.currentAttributes(itemId: itemId)
    }

    /// Pure patch builder for the public/private toggle (useEditItemSheet.ts:128-141): sharing
    /// never touches the supplemental note, but un-sharing an item that carries one clears it in
    /// the same PATCH (the UI is expected to confirm with the user before calling this).
    public func togglePublic(item: Item, to isPublic: Bool) -> ItemPatch {
        var patch = ItemPatch(isPublic: isPublic)
        if !isPublic, let note = item.supplementalNote, !note.isEmpty {
            patch.supplementalNote = ""
        }
        return patch
    }

    public func delete(itemId: UUID) async throws {
        try await patcher.deleteItemCascade(itemId: itemId)
    }

    // MARK: - Tag pass-throughs (Task 9)
    //
    // Thin forwards to the private `patcher` so the detail sheet's tag UI can talk to
    // `ItemEditor` alone, never holding a reference to `ItemPatching`/`SupabaseItemPatcher`
    // itself — same reasoning as `save`/`delete` above.

    public func itemTags(itemId: UUID) async throws -> [StashTag] {
        try await patcher.itemTags(itemId: itemId)
    }

    public func addTag(named: String, userId: UUID, itemId: UUID) async throws {
        try await patcher.addTag(named: named, userId: userId, itemId: itemId)
    }

    public func removeTag(tagId: UUID, itemId: UUID) async throws {
        try await patcher.removeTag(tagId: tagId, itemId: itemId)
    }

    public func suggestTags(title: String, content: String, description: String, available: [String]) async throws -> [String] {
        try await patcher.suggestTags(title: title, content: content, description: description, available: available)
    }
}

// MARK: - Generate summary (plan 15)

/// Why "Generate summary" produced no summary.
public enum SummaryGenerationError: Error, Equatable, Sendable {
    /// The item has no captured page text to summarize (`reason: "no_source_content"`).
    case noSourceContent
    /// Anything else: transport failure, non-2xx, `success: false`, or an empty summary.
    case failed
}

/// The `summarize-content` response: `{ success: true, summary }` or `{ success: false, reason }`
/// (soft failures come back as 200 — see the function).
public struct SummarizeContentResponse: Decodable, Equatable, Sendable {
    public let success: Bool?
    public let summary: String?
    public let reason: String?

    public init(success: Bool?, summary: String?, reason: String?) {
        self.success = success
        self.summary = summary
        self.reason = reason
    }

    /// The summary to show, or the typed reason there isn't one.
    public func summaryOrThrow() throws -> String {
        if success == true, let summary,
           !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return summary
        }
        if reason == "no_source_content" { throw SummaryGenerationError.noSourceContent }
        throw SummaryGenerationError.failed
    }
}

public protocol SummaryInvoking: Sendable {
    func summarize(itemId: UUID) async throws -> SummarizeContentResponse
}

public struct FunctionsSummaryInvoker: SummaryInvoking {
    public init() {}

    public func summarize(itemId: UUID) async throws -> SummarizeContentResponse {
        try await StashClient.shared.functions.invoke(
            "summarize-content",
            options: FunctionInvokeOptions(body: ["itemId": itemId.uuidString.lowercased()]))
    }
}

/// "Generate summary" in an empty Summary tab (plan 15 — the iOS spec's promised action, web parity
/// with `useItemSourceContent.generateSummary`). `summarize-content` (deployed v7, identical to the
/// repo) does everything server-side: it checks the caller owns the item, summarizes the item's own
/// `page_body` (links and documents only), writes `items.summary`, and refreshes the embeddings
/// itself. The client only shows the returned text.
public struct SummaryGenerator: Sendable {
    private let invoker: SummaryInvoking

    public init(invoker: SummaryInvoking = FunctionsSummaryInvoker()) {
        self.invoker = invoker
    }

    public func generate(itemId: UUID) async throws -> String {
        let response: SummarizeContentResponse
        do {
            response = try await invoker.summarize(itemId: itemId)
        } catch {
            throw SummaryGenerationError.failed
        }
        return try response.summaryOrThrow()
    }
}
