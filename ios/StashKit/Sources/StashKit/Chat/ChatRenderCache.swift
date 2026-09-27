import Foundation

/// One markdown block of an assistant answer, with its inline markdown (`**bold**`, `*italic*`,
/// citation links) already parsed into an `AttributedString` — the expensive step
/// (`AttributedString(markdown:)`) done once instead of on every SwiftUI body evaluation.
/// Mirrors `MarkdownBlock` case for case (a heading's level is dropped: nothing renders it).
public enum ChatRenderedBlock: Equatable, Sendable {
    case paragraph(AttributedString)
    case heading(AttributedString)
    case bullets([AttributedString])
    case numbered([AttributedString])
    case quote(AttributedString)
    case code(String)

    init(_ block: MarkdownBlock) {
        switch block {
        case .paragraph(let text): self = .paragraph(Self.inline(text))
        case .heading(_, let text): self = .heading(Self.inline(text))
        case .bullets(let items): self = .bullets(items.map(Self.inline))
        case .numbered(let items): self = .numbered(items.map(Self.inline))
        case .quote(let text): self = .quote(Self.inline(text))
        case .code(let text): self = .code(text)
        }
    }

    /// Exactly `MarkdownBlocksView.inlineText`'s parse: inline-only syntax, whitespace preserved,
    /// and the raw text as a plain string if the markdown doesn't parse.
    static func inline(_ raw: String) -> AttributedString {
        (try? AttributedString(markdown: raw, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(raw)
    }
}

/// Everything an assistant bubble needs to draw its answer, derived from one `ChatMessage`.
public struct ChatRenderedAnswer: Equatable, Sendable {
    /// `content` with citation markers baked into item links (`ChatCitations.link`) and any
    /// never-resolved `[Title](#N)` stripped to plain text.
    public let displayText: String
    /// Items reachable through an inline link in `displayText`.
    public let linkedSourceIDs: Set<UUID>
    /// Web parity (`extraSources`): sources NOT already linked inline — the fallback chip row.
    public let extraSources: [ChatSource]
    public let blocks: [ChatRenderedBlock]

    public init(message: ChatMessage) {
        let baked = ChatCitations.link(answer: message.content, sources: message.sources)
        displayText = ChatCitations.stripUnresolvedMarkers(baked.text)
        linkedSourceIDs = baked.linkedSourceIDs
        extraSources = message.sources.filter { !baked.linkedSourceIDs.contains($0.id) }
        blocks = MarkdownBlocks.parse(displayText).map(ChatRenderedBlock.init)
    }
}

/// Plan 15 (M1): memoizes `ChatRenderedAnswer` per (message id, content, sources). A finished
/// answer is linked, parsed, and attributed once; the streaming answer re-derives only when its
/// (coalesced, ≤10 Hz) content actually changes; a bubble LazyVStack rebuilds while scrolling is
/// a dictionary hit. Bounded, oldest-first eviction — a thread is at most a few hundred rows.
@MainActor
public final class ChatRenderCache {
    public static let shared = ChatRenderCache()

    private struct Entry {
        let content: String
        let sources: [ChatSource]
        let answer: ChatRenderedAnswer
    }

    private let capacity: Int
    private var entries: [String: Entry] = [:]
    private var insertionOrder: [String] = []
    /// Test hook: how many lookups had to derive (miss) rather than reuse.
    private(set) var derivations = 0

    public init(capacity: Int = 300) {
        self.capacity = max(1, capacity)
    }

    public func answer(for message: ChatMessage) -> ChatRenderedAnswer {
        if let entry = entries[message.id], entry.content == message.content, entry.sources == message.sources {
            return entry.answer
        }
        derivations += 1
        let answer = ChatRenderedAnswer(message: message)
        if entries.updateValue(Entry(content: message.content, sources: message.sources, answer: answer),
                               forKey: message.id) == nil {
            insertionOrder.append(message.id)
            if insertionOrder.count > capacity {
                entries.removeValue(forKey: insertionOrder.removeFirst())
            }
        }
        return answer
    }
}
