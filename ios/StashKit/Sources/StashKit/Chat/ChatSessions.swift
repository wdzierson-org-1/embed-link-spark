import Foundation

/// Port of the web's `src/utils/chatSessions.ts` (spec:
/// `docs/superpowers/specs/2026-08-27-chat-sessions-design.md`): a conversation is a burst of
/// activity — 3+ hours of silence starts a new one. Pure logic only; the DB side (the
/// `last_message_at` trigger and `list_conversations` RPC) is already deployed and shared with
/// the web client.
public enum ChatSessions {
    /// `SESSION_GAP_MS`, in seconds.
    public static let sessionGap: TimeInterval = 3 * 60 * 60

    public struct Candidate: Equatable, Sendable {
        public let id: UUID
        public let title: String?
        public let lastMessageAt: Date?

        public init(id: UUID, title: String?, lastMessageAt: Date?) {
            self.id = id
            self.title = title
            self.lastMessageAt = lastMessageAt
        }
    }

    public enum Target: Equatable, Sendable {
        case continueSession(id: UUID, title: String?)
        case new
    }

    /// `resolveSessionTarget` — continue the latest conversation iff its last message is under
    /// the gap old; anything else (no conversation, no timestamp, stale) starts fresh.
    public static func resolveTarget(latest: Candidate?, now: Date) -> Target {
        guard let latest, let lastMessageAt = latest.lastMessageAt else { return .new }
        return now.timeIntervalSince(lastMessageAt) < sessionGap
            ? .continueSession(id: latest.id, title: latest.title)
            : .new
    }

    /// `bucketConversations`' label rule, for one row: Today / Yesterday / This week (Monday
    /// start, matching date-fns `weekStartsOn: 1`) / month name (year appended when not the
    /// current year). Rows arrive newest-first from the RPC, so emitting labels in row order
    /// groups correctly with one pass.
    public static func bucketLabel(for date: Date, now: Date, calendar base: Calendar = .current) -> String {
        var calendar = base
        calendar.firstWeekday = 2
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date),
                                            to: calendar.startOfDay(for: now)).day ?? 0
        if days <= 0 { return "Today" }
        if days == 1 { return "Yesterday" }
        if calendar.isDate(date, equalTo: now, toGranularity: .weekOfYear) { return "This week" }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let sameYear = calendar.isDate(date, equalTo: now, toGranularity: .year)
        formatter.dateFormat = sameYear ? "MMMM" : "MMMM yyyy"
        return formatter.string(from: date)
    }

    /// PostgREST renders `timestamptz` as ISO8601, with fractional seconds for most rows but
    /// without them for values that landed on an exact second — accept both.
    public static func parseTimestamp(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: raw) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: raw)
    }
}

/// One row of `list_conversations(search_text, page_limit, page_offset)` (migration
/// `20260828100000`): search matches title OR any message content, pages clamp 1–100 server-side,
/// every row carries the filtered `total_count`.
public struct ConversationListRow: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let title: String?
    public let lastMessageAt: Date
    public let messageCount: Int
    public let preview: String?
    public let totalCount: Int

    public init(id: UUID, title: String?, lastMessageAt: Date, messageCount: Int,
                preview: String?, totalCount: Int) {
        self.id = id
        self.title = title
        self.lastMessageAt = lastMessageAt
        self.messageCount = messageCount
        self.preview = preview
        self.totalCount = totalCount
    }
}
