import SwiftUI
import StashKit
import Supabase

/// One row in the Ask thread: a `.saved` capture chip, a right-aligned/tinted user bubble, or a
/// left-aligned assistant bubble (streaming cursor, source chips, read-aloud, thumbs). Assistant
/// content renders through `MarkdownBlocksView`, with citation markers (`[3]` / `[Title](#3)`)
/// baked by `ChatCitations.link` into tappable `#item=<uuid>` links (Plan 8 Task 4 — Will:
/// "replicate the web model where the user clicks hyperlinks from the chat itself to open the
/// detail sheet"); the `.environment(\.openURL, …)` handler that routes those taps to
/// `onCitationTap` lives at the thread level in `AskView`, not per-bubble.
struct ChatBubble: View {
    let message: ChatMessage
    let index: Int
    /// Nearest preceding `.user` message's text, for the `chat_feedback` row's `question` column.
    /// `ChatMessage` (Task 2, already shipped/tested) carries no `question` field of its own, so
    /// this is inferred at the view layer instead of on the model — empty when there's no earlier
    /// question in the thread, matching the web's own fallback for restored history (which never
    /// carries a `question` either: ChatMole.tsx's `message.question || ''`).
    let question: String
    let userId: UUID
    /// Which source is currently being fetched for the citation sheet (nil = none) — drives the
    /// spinner on the matching chip across every bubble, so only one lookup is ever in flight.
    let loadingSourceId: UUID?
    var speech: SpeechReader
    /// True while `DictationController` is actively listening — the mic session holds the audio
    /// category at `.record`, which does not support simultaneous playback, so starting read-aloud
    /// during dictation is a silent no-op. Disabling the speaker button surfaces that as a visible
    /// affordance instead of a tap that appears to do nothing.
    let isDictating: Bool
    let onCitationTap: (UUID) -> Void

    @State private var rating: Int?
    @State private var cursorVisible = true
    @State private var shimmerPhase: CGFloat = -1

    var body: some View {
        switch message.role {
        case .saved: savedCard
        case .user: userBubble
        case .assistant: assistantBubble
        }
    }

    // MARK: - Saved chip (chat-as-capture)

    private var isSaving: Bool { message.savedItemTitle == nil || message.savedItemTitle == "Saving…" }

    private var savedCard: some View {
        HStack(spacing: 10) {
            Image(systemName: message.savedKind == "link" ? "link" : "note.text")
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(StashColor.violet600, in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(message.savedItemTitle ?? "Saving…")
                    .font(StashType.bodySemibold())
                    .lineLimit(1)
                    .accessibilityIdentifier("ask.bubble.\(index)")
                if !isSaving {
                    Text("Saved to your stash").font(StashType.meta()).foregroundStyle(StashColor.success)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: 320, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
        .redacted(reason: isSaving ? .placeholder : [])
        .overlay { if isSaving { shimmer } }
    }

    // MARK: - User bubble

    private var userBubble: some View {
        HStack {
            Spacer(minLength: 40)
            Text(message.content)
                .accessibilityIdentifier("ask.bubble.\(index)")
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(StashColor.violet600, in: RoundedRectangle(cornerRadius: 18))
        }
    }

    // MARK: - Assistant bubble

    /// Citation markers in `message.content` baked into item links against `message.sources` —
    /// see `ChatCitations.link`. Recomputed per render rather than cached on `ChatMessage`: cheap
    /// (a couple of linear scans), and it must track `message.content` as it grows token-by-token
    /// while streaming. `displayText` additionally runs `stripUnresolvedMarkers` (fix round 1):
    /// once baked, `message.content` itself already IS the baked text (`ChatStore` bakes before
    /// ever setting it — see that type's `.done` handling), so this is normally a no-op re-bake,
    /// but it's what keeps a leftover, never-resolved `[Title](#N)` — an older row reloaded from
    /// before this fix, or a genuinely unknown citation number — from rendering as a dead violet
    /// link: `AttributedString(markdown:)` accepts any `#`-fragment href as a real, tappable link,
    /// so the raw marker has to be stripped down to plain text rather than left for
    /// `MarkdownBlocksView` to style.
    private var linkedAnswer: (displayText: String, linkedSourceIDs: Set<UUID>) {
        let baked = ChatCitations.link(answer: message.content, sources: message.sources)
        return (ChatCitations.stripUnresolvedMarkers(baked.text), baked.linkedSourceIDs)
    }

    /// Web parity (`ChatMole.tsx`'s `extraSources`): only sources that ISN'T already reachable via
    /// an inline link render as a fallback chip — not all-or-nothing. `linkedSourceIDs` already
    /// accounts for links baked just now AND links that arrived pre-baked (reloaded history), so
    /// this filter is correct in both cases without needing to know which.
    private func extraSources(linkedSourceIDs: Set<UUID>) -> [ChatSource] {
        message.sources.filter { !linkedSourceIDs.contains($0.id) }
    }

    private var assistantBubble: some View {
        let linked = linkedAnswer
        let extras = extraSources(linkedSourceIDs: linked.linkedSourceIDs)
        return HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .lastTextBaseline, spacing: 2) {
                    // A wholly-blank answer (the instant between the placeholder's append and the
                    // first delta) would otherwise have no meaningful accessibility presence to
                    // find/poll — a single space keeps the identifier reliably resolvable, same as
                    // the plain-Text era this replaced.
                    Group {
                        if linked.displayText.isEmpty {
                            Text(" ")
                        } else {
                            // `compact: true` (final wave, item E/8): the bubble hugs its own
                            // text width instead of stretching to `.padding(12)`'s full available
                            // width, with tighter line/paragraph spacing appropriate to a chat
                            // bubble rather than the detail sheet's reading column.
                            MarkdownBlocksView(text: linked.displayText, compact: true)
                        }
                    }
                    .accessibilityIdentifier("ask.bubble.\(index)")
                    if message.isStreaming {
                        streamingCursor
                    }
                }
                // Links can't carry their own per-run accessibility identifiers inside `Text` —
                // this marker exists solely so a future UI test can confirm a bubble rendered
                // inline links without parsing rendered text. A REAL (non-zero) frame: a 0×0 view
                // doesn't reliably participate in the accessibility tree at all, so `exists` would
                // silently and permanently return false regardless of whether links are present.
                if !linked.linkedSourceIDs.isEmpty {
                    Color.clear
                        .frame(width: 1, height: 1)
                        .accessibilityIdentifier("ask.bubble.\(index).hasLinks")
                        .accessibilityHidden(false)
                }
                if !extras.isEmpty {
                    sourcesRow(extras)
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

    // MARK: - Actions row (read-aloud + thumbs)

    @ViewBuilder private var actionsRow: some View {
        if !message.content.isEmpty {
            HStack(spacing: 14) {
                speakerButton
                // DISCLOSED adaptation: the web only shows thumbs once a message's `sources` key
                // has been set at all (even to `[]`) — a byproduct of `sources` staying
                // `undefined` until the `.done` SSE event, which incidentally also hides thumbs on
                // messages restored from history. `ChatMessage.sources` here is a plain
                // non-optional array (always `[]` by default), so that distinction isn't
                // representable — thumbs show on any bubble that's finished streaming instead,
                // restored history included.
                if !message.isStreaming {
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
        .disabled(isDictating)
        .accessibilityIdentifier("ask.bubble.\(index).speak")
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

    /// Mirrors `ItemCardView`'s processing shimmer (same gradient/opacity/duration recipe,
    /// duplicated rather than shared — `ItemTagsSection`'s own copy already established that
    /// precedent for a small loading treatment with no other consumer).
    private var shimmer: some View {
        GeometryReader { geo in
            LinearGradient(colors: [.clear, .white.opacity(0.55), .clear],
                            startPoint: .leading, endPoint: .trailing)
                .frame(width: geo.size.width * 0.6)
                .offset(x: shimmerPhase * geo.size.width)
        }
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) {
                shimmerPhase = 1.6
            }
        }
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
/// running app (used for `task-4-links.png`, since the standing test account is gate-blocked for
/// a live answer).
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
        speech: SpeechReader(),
        isDictating: false,
        onCitationTap: { _ in }
    )
    .padding()
}
