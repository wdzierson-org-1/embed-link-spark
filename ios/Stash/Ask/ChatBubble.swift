import SwiftUI
import StashKit
import Supabase

/// One row in the Ask thread: a right-aligned/tinted user bubble, or a left-aligned assistant
/// bubble (streaming cursor, source chips, read-aloud, thumbs). Assistant content renders as
/// markdown, with citation markers (`[3]` / `[Title](#3)`) baked by `ChatCitations.link` into
/// tappable `#item=<uuid>` links (Plan 8 Task 4 — Will: "replicate the web model where the user
/// clicks hyperlinks from the chat itself to open the detail sheet"); the
/// `.environment(\.openURL, …)` handler that routes those taps to `onCitationTap` lives at the
/// thread level in `AskView`, not per-bubble.
///
/// Plan 15 (M1): `Equatable` over exactly what it draws, and used with `.equatable()` in
/// `AskView`, so while an answer streams only the streaming bubble re-renders — finished bubbles
/// skip their body entirely. The two closures are deliberately left out of `==`: they're rebuilt
/// on every parent render, which is what used to defeat SwiftUI's diffing. The answer's citation
/// linking and markdown parse come memoized from `ChatRenderCache`.
///
/// Plan 15 (M11): the `.saved` capture-chip row is gone with chat-as-capture — Ask is
/// retrieval-only.
struct ChatBubble: View, Equatable {
    let message: ChatMessage
    let index: Int
    /// Nearest preceding `.user` message's text, for the `chat_feedback` row's `question` column.
    /// `ChatMessage` carries no `question` field of its own, so this is inferred at the view
    /// layer instead of on the model — empty when there's no earlier question in the thread,
    /// matching the web's own fallback for restored history (ChatMole.tsx's
    /// `message.question || ''`).
    let question: String
    let userId: UUID
    /// Which source is currently being fetched for the citation sheet — nil unless it's one of
    /// THIS message's sources (AskView filters it), so a citation tap re-renders only the bubble
    /// whose chip shows the spinner. Only one lookup is ever in flight.
    let loadingSourceId: UUID?
    /// An interrupted answer (`ChatMessage.isInterrupted`) offers Retry while it's the thread's
    /// last row and nothing is streaming.
    let showsRetry: Bool
    let speech: SpeechReader
    let onCitationTap: (UUID) -> Void
    let onRetry: () -> Void

    @State private var rating: Int?
    @State private var cursorVisible = true

    nonisolated static func == (lhs: ChatBubble, rhs: ChatBubble) -> Bool {
        lhs.message == rhs.message && lhs.index == rhs.index && lhs.question == rhs.question
            && lhs.userId == rhs.userId && lhs.loadingSourceId == rhs.loadingSourceId
            && lhs.showsRetry == rhs.showsRetry && lhs.speech === rhs.speech
    }

    var body: some View {
        switch message.role {
        case .user: userBubble
        case .assistant: assistantBubble
        }
    }

    // MARK: - User bubble

    private var userBubble: some View {
        HStack {
            Spacer(minLength: 40)
            // Same face and rhythm as the assistant side (`ChatAnswerText`, compact) —
            // DESIGN.md's one UI family. A bare `Text` here fell back to SF at the system size
            // while replies rendered Neue Montreal 14 (Will, 2026-09-07).
            Text(message.content)
                .font(StashType.body())
                .lineSpacing(14 * 0.35)
                .accessibilityIdentifier("ask.bubble.\(index)")
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(StashColor.violet600, in: RoundedRectangle(cornerRadius: 18))
        }
    }

    // MARK: - Assistant bubble

    /// `ChatRenderCache` derives, once per (message id, content, sources): the citation-baked
    /// display text (`ChatCitations.link`, then `stripUnresolvedMarkers` so a never-resolved
    /// `[Title](#N)` — an older reloaded row, or an unknown citation number — renders as plain
    /// text rather than a dead violet link), which sources are linked inline, the fallback chips
    /// (web parity, `extraSources`: only sources NOT already reachable via an inline link), and
    /// the parsed markdown blocks.
    private var assistantBubble: some View {
        let rendered = ChatRenderCache.shared.answer(for: message)
        return HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .lastTextBaseline, spacing: 2) {
                    // Plan 15: what the server's agent loop is doing before the first token
                    // ("Searching your stash…"), in plain meta text inside the existing
                    // placeholder bubble. Its own identifier, so `ask.bubble.<n>` below keeps
                    // meaning "the answer text" for the UI tests that poll it.
                    if rendered.displayText.isEmpty, let status = message.streamStatus {
                        Text(status.label)
                            .font(StashType.meta())
                            .foregroundStyle(StashColor.muted)
                            .accessibilityIdentifier("ask.bubble.\(index).status")
                    }
                    // A wholly-blank answer (the instant between the placeholder's append and the
                    // first delta) would otherwise have no meaningful accessibility presence to
                    // find/poll — a single space keeps the identifier reliably resolvable.
                    Group {
                        if rendered.displayText.isEmpty {
                            Text(" ")
                        } else {
                            ChatAnswerText(blocks: rendered.blocks)
                        }
                    }
                    .accessibilityIdentifier("ask.bubble.\(index)")
                    if message.isStreaming {
                        streamingCursor
                    }
                }
                // Links can't carry their own per-run accessibility identifiers inside `Text` —
                // this marker exists solely so a UI test can confirm a bubble rendered inline
                // links without parsing rendered text. A REAL (non-zero) frame: a 0×0 view
                // doesn't reliably participate in the accessibility tree at all.
                if !rendered.linkedSourceIDs.isEmpty {
                    Color.clear
                        .frame(width: 1, height: 1)
                        .accessibilityIdentifier("ask.bubble.\(index).hasLinks")
                        .accessibilityHidden(false)
                }
                if !rendered.extraSources.isEmpty {
                    sourcesRow(rendered.extraSources)
                }
                actionsRow
            }
            .padding(12)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
            Spacer(minLength: 40)
        }
    }

    private var streamingCursor: some View {
        Text("▍")
            .foregroundStyle(StashColor.muted)
            .opacity(cursorVisible ? 1 : 0.15)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                    cursorVisible.toggle()
                }
            }
    }

    // MARK: - Sources

    private func sourcesRow(_ sources: [ChatSource]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Array(sources.enumerated()), id: \.element.id) { chipIndex, source in
                    sourceChip(source, chipIndex: chipIndex)
                }
            }
        }
        .accessibilityIdentifier("ask.sources.\(index)")
    }

    private func sourceChip(_ source: ChatSource, chipIndex: Int) -> some View {
        let isLoading = loadingSourceId == source.id
        return Button {
            onCitationTap(source.id)
        } label: {
            HStack(spacing: 4) {
                if isLoading {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: icon(for: source.type))
                }
                Text(displayTitle(source, chipIndex: chipIndex)).lineLimit(1)
            }
            .font(StashType.chip())
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color(.tertiarySystemFill), in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .accessibilityIdentifier("ask.sources.\(index).chip.\(chipIndex)")
    }

    private func displayTitle(_ source: ChatSource, chipIndex: Int) -> String {
        let trimmed = source.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Item \(chipIndex + 1)" : trimmed
    }

    private func icon(for type: String?) -> String {
        switch ItemType(rawValue: type ?? "") {
        case .text: "note.text"
        case .link: "link"
        case .image: "photo"
        case .audio: "waveform"
        case .video: "video"
        case .document: "doc.richtext"
        case .collection: "folder"
        case .unknown, nil: "doc.text"
        }
    }

    // MARK: - Actions row (read-aloud + retry / thumbs)

    @ViewBuilder private var actionsRow: some View {
        if !message.content.isEmpty {
            HStack(spacing: 14) {
                speakerButton
                if showsRetry {
                    retryButton
                }
                // DISCLOSED adaptation: the web only shows thumbs once a message's `sources` key
                // has been set at all (even to `[]`) — a byproduct of `sources` staying
                // `undefined` until the `.done` SSE event, which incidentally also hides thumbs on
                // messages restored from history. `ChatMessage.sources` here is a plain
                // non-optional array, so that distinction isn't representable — thumbs show on
                // any bubble that finished streaming instead, restored history included. Never on
                // a partial (interrupted) answer: there's no complete answer to rate.
                if !message.isStreaming && !message.isInterrupted {
                    thumbsRow
                }
            }
            .font(StashType.meta())
            .foregroundStyle(StashColor.muted)
        }
    }

    private var speakerButton: some View {
        let isSpeaking = speech.speakingId == message.id
        return Button {
            speech.toggle(id: message.id, text: message.content)
        } label: {
            Image(systemName: isSpeaking ? "stop.circle.fill" : "speaker.wave.2")
        }
        .accessibilityIdentifier("ask.bubble.\(index).speak")
    }

    /// Plan 15 (L1 / iOS spec "SSE drop mid-answer: keep partial text, show retry"): the answer
    /// stopped before the server finished; Retry asks the same question again. Same meta/muted
    /// treatment as its neighbours in this row.
    private var retryButton: some View {
        Button(action: onRetry) {
            HStack(spacing: 4) {
                Image(systemName: "arrow.clockwise")
                Text("Retry")
            }
        }
        .accessibilityLabel("Answer interrupted. Retry")
        .accessibilityIdentifier("ask.bubble.\(index).retry")
    }

    private var thumbsRow: some View {
        HStack(spacing: 10) {
            Button {
                submitFeedback(1)
            } label: {
                Image(systemName: rating == 1 ? "hand.thumbsup.fill" : "hand.thumbsup")
            }
            .disabled(rating != nil)
            .accessibilityIdentifier("ask.bubble.\(index).thumbsUp")

            Button {
                submitFeedback(-1)
            } label: {
                Image(systemName: rating == -1 ? "hand.thumbsdown.fill" : "hand.thumbsdown")
            }
            .disabled(rating != nil)
            .accessibilityIdentifier("ask.bubble.\(index).thumbsDown")
        }
    }

    /// Fire-and-forget, matching `SupabaseChatHistory.persist`'s shape (ChatHistoryAPI.swift):
    /// failures are printed, never surfaced — a feedback row is a nice-to-have, not something that
    /// should interrupt the conversation. Columns per `chat_feedback` (src/integrations/supabase/
    /// types.ts, cross-checked against ChatMessageFeedback.tsx's insert): user_id, question,
    /// answer, source_item_ids (nullable), rating (1 up / -1 down).
    private func submitFeedback(_ value: Int) {
        guard rating == nil else { return }
        rating = value
        let feedback = ChatFeedbackInsert(
            userId: userId.uuidString,
            question: question,
            answer: message.content,
            sourceItemIds: message.sources.isEmpty ? nil : message.sources.map { $0.id.uuidString },
            rating: value
        )
        Task {
            do {
                try await StashClient.shared.from("chat_feedback").insert(feedback).execute()
            } catch {
                print("Failed to submit chat feedback (non-fatal): \(error)")
            }
        }
    }
}

/// An assistant answer's markdown, drawn from `ChatRenderCache`'s memoized blocks (plan 15, M1)
/// instead of re-parsing the whole answer on every render. The layout is exactly
/// `MarkdownBlocksView(text:compact: true)`'s (Detail/MarkdownBlocksView.swift) — the compact
/// mode that existed only for this bubble — modifier for modifier, so nothing looks different.
private struct ChatAnswerText: View {
    let blocks: [ChatRenderedBlock]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                view(for: block)
            }
        }
    }

    @ViewBuilder private func view(for block: ChatRenderedBlock) -> some View {
        switch block {
        case .paragraph(let text):
            inlineText(text)

        case .heading(let text):
            inlineText(text)
                .font(StashType.bodySemibold())

        case .bullets(let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•").foregroundStyle(StashColor.faint)
                        inlineText(item)
                    }
                    .padding(.leading, 16)
                    .accessibilityElement(children: .combine)
                }
            }

        case .numbered(let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(index + 1).").foregroundStyle(StashColor.faint)
                        inlineText(item)
                    }
                    .padding(.leading, 16)
                    .accessibilityElement(children: .combine)
                }
            }

        case .quote(let text):
            HStack(spacing: 10) {
                Rectangle()
                    .fill(StashColor.violet600)
                    .frame(width: 2)
                inlineText(text)
                    .foregroundStyle(StashColor.muted)
            }

        case .code(let text):
            Text(text)
                .font(StashType.mono())
                .foregroundStyle(StashColor.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(StashColor.wash, in: RoundedRectangle(cornerRadius: StashRadius.input))
        }
    }

    /// `MarkdownBlocksView.inlineText` in compact mode, minus the parse (already done): links in
    /// DESIGN.md violet600 with no underline, body face, ~1.35 line height, hugging its content.
    private func inlineText(_ parsed: AttributedString) -> some View {
        var attributed = parsed
        let linkRanges = attributed.runs.filter { $0.link != nil }.map(\.range)
        for range in linkRanges {
            attributed[range].foregroundColor = StashColor.violet600
            attributed[range].underlineStyle = nil
        }
        return Text(attributed)
            .font(StashType.body())
            .foregroundStyle(StashColor.ink)
            .lineSpacing(14 * 0.35)
            .frame(maxWidth: nil, alignment: .leading)
    }
}

private struct ChatFeedbackInsert: Encodable {
    let userId: String
    let question: String
    let answer: String
    let sourceItemIds: [String]?
    let rating: Int

    enum CodingKeys: String, CodingKey {
        case userId = "user_id", question, answer
        case sourceItemIds = "source_item_ids"
        case rating
    }
}

/// Plan 8 Task 4 proof-of-rendering (fix round 1): a linked title (`[Title](#1)`) plus a bare
/// marker (`[1]`) citing the same source, PLUS a second, never-cited-by-number source — so both
/// `ChatCitations.link` forms render inline AND the per-source chip row fallback (exactly the
/// leftover source, not all-or-nothing) render at once. See
/// `AskView.seedCitationScreenshotFixtureIfRequested` for the equivalent seeded through the real
/// running app.
#Preview {
    ChatBubble(
        message: ChatMessage(
            id: "preview-a", role: .assistant,
            content: "Per [Feeding Log](#1), persimmons should be introduced gradually [1] to avoid stomach upset.",
            sources: [ChatSource(id: UUID(), title: "Persimmon Feeding Notes", type: "text", url: nil, n: 1),
                      ChatSource(id: UUID(), title: "Fruit Tree Almanac", type: "text", url: nil, n: nil)]),
        index: 0,
        question: "What do my saved items say about persimmons?",
        userId: UUID(),
        loadingSourceId: nil,
        showsRetry: false,
        speech: SpeechReader(),
        onCitationTap: { _ in },
        onRetry: {}
    )
    .padding()
}
