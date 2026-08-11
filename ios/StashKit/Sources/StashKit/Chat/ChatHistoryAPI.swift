import Foundation
import Supabase

// MARK: - ChatMessage

public struct ChatMessage: Identifiable, Equatable, Sendable {
    public enum Role: String, Sendable { case user, assistant, saved }

    public var id: String
    public var role: Role
    public var content: String
    public var sources: [ChatSource]
    public var savedItemTitle: String?    // role == .saved chips
    public var savedKind: String?         // "link" | "note"
    public var isStreaming: Bool

    public init(id: String, role: Role, content: String, sources: [ChatSource] = [],
                savedItemTitle: String? = nil, savedKind: String? = nil, isStreaming: Bool = false) {
        self.id = id
        self.role = role
        self.content = content
        self.sources = sources
        self.savedItemTitle = savedItemTitle
        self.savedKind = savedKind
        self.isStreaming = isStreaming
    }
}

// MARK: - ChatHistoryStoring

/// Port of ChatMole.tsx's `conversations`/`messages` persistence (:70-132) — the Ask surface's
/// thread survives sessions in two tables instead of living only in view state.
public protocol ChatHistoryStoring: Sendable {
    func loadOrCreateConversation(userId: UUID) async throws -> UUID
    /// Oldest-first — mirrors the web's desc-ordered page, `.reverse()`d for display.
    func loadHistory(conversationId: UUID, limit: Int) async throws -> [ChatMessage]
    /// Fire-and-forget, matching ChatMole.tsx:121-131: a message that fails to save is logged,
    /// never thrown, so a persistence hiccup can't interrupt the conversation in progress.
    func persist(conversationId: UUID, role: String, content: String, sourceItemIds: [UUID]?) async
}

// MARK: - SupabaseChatHistory

public struct SupabaseChatHistory: ChatHistoryStoring {
    public init() {}

    /// ChatMole.tsx:76-92 — earliest conversation for the user; created on first use if none exists.
    public func loadOrCreateConversation(userId: UUID) async throws -> UUID {
        struct ConversationRow: Decodable { let id: UUID }
        let existing: ConversationRow? = try await StashClient.shared.from("conversations")
            .select("id")
            .eq("user_id", value: userId.uuidString)
            .order("created_at", ascending: true)
            .limit(1)
            .maybeSingle()
            .execute().value
        if let existing { return existing.id }

        let created: ConversationRow = try await StashClient.shared.from("conversations")
            .insert(["user_id": userId.uuidString, "title": "Ask Stash"])
            .select("id")
            .single()
            .execute().value
        return created.id
    }

    /// ChatMole.tsx:96-107 — last `limit` messages newest-first off the wire, reversed to
    /// oldest-first for display, keeping only user/assistant turns (a `saved` chip never
    /// round-trips through this table on the web either).
    public func loadHistory(conversationId: UUID, limit: Int) async throws -> [ChatMessage] {
        struct MessageRow: Decodable { let id: String; let role: String; let content: String }
        let rows: [MessageRow] = try await StashClient.shared.from("messages")
            .select("id, role, content, created_at")
            .eq("conversation_id", value: conversationId.uuidString)
            .order("created_at", ascending: false)
            .limit(limit)
            .execute().value
        return rows.reversed().compactMap { row in
            guard let role = ChatMessage.Role(rawValue: row.role), role == .user || role == .assistant else { return nil }
            return ChatMessage(id: row.id, role: role, content: row.content)
        }
    }

    /// ChatMole.tsx:118-132 — non-fatal insert: failures are printed, never surfaced to the
    /// caller, and an empty `source_items` array is normalized to `null` same as the web.
    ///
    /// Adaptation: `insert(_:)` takes `some Encodable` (PostgrestQueryBuilder.swift:139-144 in the
    /// supabase-swift checkout), so unlike `SupabaseItemPatcher`'s `[String: AnyJSON]` conversion
    /// — needed there because `ItemPatch.restBody` is `[String: Any?]`, not itself `Encodable` — a
    /// plain struct works directly here. One wrinkle: Foundation's synthesized `Encodable` uses
    /// `encodeIfPresent` for `Optional` properties, so `source_items: nil` *omits* the key rather
    /// than writing JSON `null`. That's fine: PostgREST treats a missing insert column the same as
    /// an explicit `null` when the column has no default, and `source_items UUID[]` (migration
    /// 20250622205827) has none — so the stored row matches the web's explicit `null` either way.
    public func persist(conversationId: UUID, role: String, content: String, sourceItemIds: [UUID]?) async {
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        struct MessageInsert: Encodable {
            let conversationId: String
            let role: String
            let content: String
            let sourceItems: [String]?

            enum CodingKeys: String, CodingKey {
                case conversationId = "conversation_id"
                case role, content
                case sourceItems = "source_items"
            }
        }
        let sourceItems = (sourceItemIds?.isEmpty == false) ? sourceItemIds?.map { $0.uuidString } : nil
        let payload = MessageInsert(conversationId: conversationId.uuidString, role: role,
                                    content: content, sourceItems: sourceItems)
        do {
            try await StashClient.shared.from("messages").insert(payload).execute()
        } catch {
            print("Failed to persist chat message (non-fatal): \(error)")
        }
    }
}
