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

/// Port of ChatMole.tsx's `conversations`/`messages` persistence — the Ask surface's thread
/// survives sessions in two tables instead of living only in view state. Sessions rework
/// (2026-08-29, mirroring the web's 2026-08-27/28 model): conversations are 3h-gap sessions
/// (`ChatSessions`), rows are created lazily on first send with a null title, auto-titled via
/// `generate-title`, and browsable through the `list_conversations` RPC.
public protocol ChatHistoryStoring: Sendable {
    /// The user's most recent conversation by `last_message_at` (ChatMole.tsx's open-time
    /// resolution query), or nil for a first-ever chat.
    func latestConversation(userId: UUID) async throws -> ChatSessions.Candidate?
    /// A fresh session row — title null, auto-titled after the first exchange.
    func createConversation(userId: UUID) async throws -> UUID
    /// Oldest-first — mirrors the web's desc-ordered page, `.reverse()`d for display.
    func loadHistory(conversationId: UUID, limit: Int) async throws -> [ChatMessage]
    /// Fire-and-forget, matching ChatMole.tsx:121-131: a message that fails to save is logged,
    /// never thrown, so a persistence hiccup can't interrupt the conversation in progress.
    func persist(conversationId: UUID, role: String, content: String, sourceItemIds: [UUID]?) async
    /// `generate-title` edge function; nil on any failure (the caller falls back to the question).
    func generateTitle(for question: String) async -> String?
    /// Fire-and-forget title write, same non-fatal contract as `persist`.
    func setTitle(conversationId: UUID, title: String) async
    /// `list_conversations(search_text, page_limit, page_offset)` — newest-first.
    func listConversations(searchText: String?, pageLimit: Int, pageOffset: Int) async throws -> [ConversationListRow]
}

// MARK: - SupabaseChatHistory

public struct SupabaseChatHistory: ChatHistoryStoring {
    public init() {}

    public func latestConversation(userId: UUID) async throws -> ChatSessions.Candidate? {
        struct Row: Decodable {
            let id: UUID
            let title: String?
            let last_message_at: String?
        }
        let row: Row? = try await StashClient.shared.from("conversations")
            .select("id, title, last_message_at")
            .eq("user_id", value: userId.uuidString)
            .order("last_message_at", ascending: false, nullsFirst: false)
            .limit(1)
            .maybeSingle()
            .execute().value
        guard let row else { return nil }
        return ChatSessions.Candidate(id: row.id, title: row.title,
                                       lastMessageAt: ChatSessions.parseTimestamp(row.last_message_at))
    }

    public func createConversation(userId: UUID) async throws -> UUID {
        struct Row: Decodable { let id: UUID }
        // `title` omitted → SQL null; the auto-title lands after the first exchange.
        let created: Row = try await StashClient.shared.from("conversations")
            .insert(["user_id": userId.uuidString])
            .select("id")
            .single()
            .execute().value
        return created.id
    }

    /// ChatMole.tsx:96-107 — last `limit` messages newest-first off the wire, reversed to
    /// oldest-first for display, keeping only user/assistant turns (a `saved` chip never
    /// round-trips through this table on the web either).
    ///
    /// Fix round 1: also selects `source_items` (`messages.source_items UUID[]`, migration
    /// 20250622205827) and reconstructs bare-id `ChatSource` stand-ins from it — same shape the
    /// web restores (`m.source_items` → `sourceItemIds`, ChatMole.tsx:114), just adapted into this
    /// type's single `sources` array since iOS has no separate `sourceItemIds` field. These carry
    /// no `title`/`type`/`n` (the column only stores ids), so `ChatCitations.link` can't use them
    /// to bake anything new — but `ChatBubble`'s per-source chip filter still uses them correctly:
    /// a reloaded answer's content is already baked (see `ChatStore`'s `.done` handling), so
    /// whichever of these ids ISN'T found inline-linked in that baked text is a genuine
    /// never-cited-by-number fallback source and surfaces as a chip (title falls back to "Item N",
    /// `ChatBubble.displayTitle`), matching the web's own `extraSources` behavior on reload.
    public func loadHistory(conversationId: UUID, limit: Int) async throws -> [ChatMessage] {
        struct MessageRow: Decodable { let id: String; let role: String; let content: String; let source_items: [String]? }
        let rows: [MessageRow] = try await StashClient.shared.from("messages")
            .select("id, role, content, source_items, created_at")
            .eq("conversation_id", value: conversationId.uuidString)
            .order("created_at", ascending: false)
            .limit(limit)
            .execute().value
        return rows.reversed().compactMap { row in
            guard let role = ChatMessage.Role(rawValue: row.role), role == .user || role == .assistant else { return nil }
            let sources = (row.source_items ?? []).compactMap(UUID.init(uuidString:))
                .map { ChatSource(id: $0, title: nil, type: nil, url: nil, n: nil) }
            return ChatMessage(id: row.id, role: role, content: row.content, sources: sources)
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

    /// ChatMole.tsx's auto-title branch: `generate-title` returns `{ title }` (with its own
    /// "Untitled Note" fallback body even on server error); any transport failure here just
    /// yields nil and the caller falls back to the question text.
    public func generateTitle(for question: String) async -> String? {
        struct Response: Decodable { let title: String? }
        do {
            let response: Response = try await StashClient.shared.functions
                .invoke("generate-title", options: .init(body: ["content": question]))
            let title = response.title?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (title?.isEmpty == false) ? title : nil
        } catch {
            print("Title generation failed (non-fatal): \(error)")
            return nil
        }
    }

    public func setTitle(conversationId: UUID, title: String) async {
        do {
            try await StashClient.shared.from("conversations")
                .update(["title": title])
                .eq("id", value: conversationId.uuidString)
                .execute()
        } catch {
            print("Failed to set conversation title (non-fatal): \(error)")
        }
    }

    public func listConversations(searchText: String?, pageLimit: Int, pageOffset: Int) async throws -> [ConversationListRow] {
        struct Params: Encodable {
            let search_text: String?
            let page_limit: Int
            let page_offset: Int
        }
        struct Row: Decodable {
            let id: UUID
            let title: String?
            let last_message_at: String
            let message_count: Int
            let preview: String?
            let total_count: Int
        }
        let rows: [Row] = try await StashClient.shared
            .rpc("list_conversations", params: Params(search_text: searchText,
                                                       page_limit: pageLimit,
                                                       page_offset: pageOffset))
            .execute().value
        return rows.compactMap { row in
            guard let lastMessageAt = ChatSessions.parseTimestamp(row.last_message_at) else { return nil }
            return ConversationListRow(id: row.id, title: row.title, lastMessageAt: lastMessageAt,
                                        messageCount: row.message_count, preview: row.preview,
                                        totalCount: row.total_count)
        }
    }
}
