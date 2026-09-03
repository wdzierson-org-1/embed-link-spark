import Foundation
import Supabase

/// Port of the web's `items` PATCH / delete / tag flows (itemOperations.ts, useTags.ts,
/// useEditItemSheet.ts) — save-skip-when-unchanged, cascade delete, and the
/// share/unshare sticky-note rule.

// MARK: - ItemPatch

public struct ItemPatch: Equatable, Sendable {
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
                supplementalNote: String? = nil, isPublic: Bool? = nil, attributes: ItemAttributes? = nil) {
        self.title = title
        self.description = description
        self.content = content
        self.supplementalNote = supplementalNote
        self.isPublic = isPublic
        self.attributes = attributes
    }

    public var isEmpty: Bool {
        title == nil && description == nil && content == nil && supplementalNote == nil
            && isPublic == nil && attributes == nil
    }

    /// Any of the search-relevant text fields changed — mirrors web's
    /// `['title','description','content','supplemental_note'].some(field => field in updates)`,
    /// which gates whether a save schedules an embedding refresh. Deliberately excludes
    /// `attributes`: web parity, `itemOperations.ts:100-101` — an attributes-only PATCH (e.g.
    /// this task's location-row edit) never touches any of the four fields
    /// `buildEmbeddingText` actually reads, so it must never schedule a refresh either.
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
    func patch(itemId: UUID, patch: ItemPatch) async throws -> Item
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
        let data = try await StashClient.shared.from("items")
            .update(Self.jsonBody(patch.restBody))
            .eq("id", value: itemId.uuidString)
            .select(Item.detailColumns)
            .single()
            .execute().data
        return try Item.decoder.decode(Item.self, from: data)
    }

    /// Web order (itemOperations.ts:135-155): embeddings rows first, then the item row. The
    /// embeddings delete is best-effort, not load-bearing — `embeddings.item_id` carries an
    /// `ON DELETE CASCADE` FK to `items`, so the row is removed regardless once the item delete
    /// below succeeds; the manual delete here only saves a moment of dangling rows in between.
    public func deleteItemCascade(itemId: UUID) async throws {
        do {
            try await StashClient.shared.from("embeddings").delete()
                .eq("item_id", value: itemId.uuidString).execute()
        } catch {
            // Web parity (itemOperations.ts:141-144): never fail the delete over this — the
            // DB's ON DELETE CASCADE on embeddings.item_id covers it regardless.
            print("Embeddings delete failed (non-fatal): \(error)")
        }
        try await StashClient.shared.from("items").delete()
            .eq("id", value: itemId.uuidString).execute()
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
}

/// Backs the item detail view: save/delete/public-toggle/tag operations, all delegating network
/// work to an injected `ItemPatching` so the pure diff/patch-building logic (this type + the
/// free functions above) can be tested without touching Supabase.
@MainActor
public final class ItemEditor {
    private let patcher: ItemPatching
    private let refresher: EmbeddingRefresher

    public init(patcher: ItemPatching, refresher: EmbeddingRefresher) {
        self.patcher = patcher
        self.refresher = refresher
    }

    /// Saves resolve on the PATCH alone; embedding regeneration is scheduled separately (from the
    /// full merged row so a partial patch can't wipe the rest of the item's searchable content)
    /// and never awaited here — see EmbeddingRefresher.
    public func save(itemId: UUID, patch: ItemPatch) async throws -> Item {
        guard !patch.isEmpty else { throw ItemEditorError.emptyPatch }
        let merged = try await patcher.patch(itemId: itemId, patch: patch)
        if patch.touchesTextFields {
            await refresher.schedule(merged)
        }
        return merged
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
