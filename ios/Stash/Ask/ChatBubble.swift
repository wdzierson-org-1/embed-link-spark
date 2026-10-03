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
///
/// Plan 16 (task 2d, accessibility):
/// - Bubble text is the `reading` role (17 pt at the default size, was 14), set only through
///   `chatBubbleText(_:)` — headings pass `.readingSemibold` INTO it — and the bubble's geometry is
///   `ChatBubbleLayout`'s, which the thread's tail budget reads too.
/// - Read-aloud and the thumbs take taps across 44 × 44 pt and sit 44 pt apart; each says what it
///   does and whether it's on (VoiceOver).
/// - An answer reads block by block in VoiceOver: a paragraph, a heading (a heading for the rotor
///   too), a list item. Each block is one element, so its links stay reachable and a long answer
///   can be moved through a block at a time.
/// - The streaming cursor blinks its opacity only — never its position — and holds still under
///   Reduce Motion.
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
    /// The thumbs given this session, kept outside the bubble (plan 16 task 1c) — see `ChatRatings`.
    let ratings: ChatRatings
    /// Where VoiceOver goes when the header's Cancel goes away (plan 16, task 2d): an answer binds each of
    /// its elements here (`AskAccessibilityFocus.answer`, `.answerStatus`). A binding to `AskView`'s
    /// state, the same every render — left out of `==` with the closures.
    let accessibilityFocus: AccessibilityFocusState<AskAccessibilityFocus?>.Binding
    let onCitationTap: (UUID) -> Void
    let onRetry: () -> Void

    /// Read only for the source chips' arrangement (plan 16) — an environment value, so a text-size
    /// change still reaches a bubble `==` skips.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    nonisolated static func == (lhs: ChatBubble, rhs: ChatBubble) -> Bool {
        lhs.message == rhs.message && lhs.index == rhs.index && lhs.question == rhs.question
            && lhs.userId == rhs.userId && lhs.loadingSourceId == rhs.loadingSourceId
            && lhs.showsRetry == rhs.showsRetry && lhs.speech === rhs.speech && lhs.ratings === rhs.ratings
    }

    private var rating: Int? { ratings.value(for: message.id) }

    #if DEBUG
    /// `--uitest-scripted-chat` (UI tests only): nothing reaches the server (see
    /// `AskView.usesScriptedChat`), so a thumb is recorded on screen but no `chat_feedback` row is
    /// written. Compiled out of Release.
    private static let keepsFeedbackLocal = ProcessInfo.processInfo.arguments.contains("--uitest-scripted-chat")
    #else
    private static let keepsFeedbackLocal = false
    #endif

    var body: some View {
        switch message.role {
        case .user: userBubble
        case .assistant: assistantBubble
        }
    }

    // MARK: - User bubble

    private var userBubble: some View {
        HStack(spacing: ChatBubbleLayout.spacing) {
            Spacer(minLength: ChatBubbleLayout.farSideGap)
            // Same face and rhythm as the assistant side (`ChatAnswerText`) — DESIGN.md's one UI
            // family. A bare `Text` here fell back to SF at the system size while replies rendered
            // Neue Montreal (Will, 2026-09-07).
            Text(message.content)
                .chatBubbleText()
                .accessibilityIdentifier("ask.bubble.\(index)")
                .foregroundStyle(.white)
                .padding(.horizontal, ChatBubbleLayout.questionHorizontalPadding)
                .padding(.vertical, ChatBubbleLayout.questionVerticalPadding)
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
        return HStack(alignment: .top, spacing: ChatBubbleLayout.spacing) {
            VStack(alignment: .leading, spacing: ChatBubbleLayout.answerSpacing) {
                HStack(alignment: .lastTextBaseline, spacing: 2) {
                    // Plan 15: what the server's agent loop is doing before the first token
                    // ("Searching your stash…"), in plain meta text inside the existing
                    // placeholder bubble. Its own identifier, so `ask.bubble.<n>` below keeps
                    // meaning "the answer text" for the UI tests that poll it.
                    if rendered.displayText.isEmpty, let status = message.streamStatus {
                        Text(status.label)
                            .stashFont(.meta)
                            .foregroundStyle(StashColor.muted)
                            .accessibilityFocused(accessibilityFocus, equals: .answerStatus(message.id))
                            .accessibilityIdentifier("ask.bubble.\(index).status")
                    }
                    // A wholly-blank answer (the instant between the placeholder's append and the
                    // first delta) would otherwise have no meaningful accessibility presence to
                    // find/poll — a single space keeps the identifier reliably resolvable.
                    Group {
                        if rendered.displayText.isEmpty {
                            Text(" ")
                        } else {
                            ChatAnswerText(blocks: rendered.blocks, messageId: message.id,
                                           accessibilityFocus: accessibilityFocus)
                        }
                    }
                    .accessibilityIdentifier("ask.bubble.\(index)")
                    if message.isStreaming {
                        StreamingCursor()
                    }
                }
                #if DEBUG
                .overlay(alignment: .topLeading) {
                    // Links can't carry their own per-run accessibility identifiers inside `Text` —
                    // this marker exists solely so a UI test can confirm a bubble rendered inline
                    // links without parsing rendered text. A REAL (non-zero) frame: a 0×0 view
                    // doesn't reliably participate in the accessibility tree at all. Plan 16: DEBUG
                    // only — an element with no label is nothing VoiceOver should ever stop on — and
                    // drawn over the text rather than laid out under it, so a test build's bubble is
                    // the size of the one that ships.
                    if !rendered.linkedSourceIDs.isEmpty {
                        Color.clear
                            .frame(width: 1, height: 1)
                            .allowsHitTesting(false)
                            .accessibilityIdentifier("ask.bubble.\(index).hasLinks")
                            .accessibilityHidden(false)
                    }
                }
                #endif
                if !rendered.extraSources.isEmpty {
                    sourcesRow(rendered.extraSources)
                        // 44 pt between a chip's centre and the actions row's below (plan 16).
                        .padding(.bottom, ChatBubbleLayout.chipsBottomGap)
                }
                actionsRow
            }
            .padding(ChatBubbleLayout.answerPadding)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
            Spacer(minLength: ChatBubbleLayout.farSideGap)
        }
    }

    // MARK: - Sources

    /// The chips sit in a horizontal scroll view, which clips anything past its own frame — a chip's
    /// 44 pt target included. So the row is laid out with room for the targets inside the scroll view
    /// (`chipTargetInset` above and below the chips), and that room is drawn, not laid out: the
    /// answer's spacing is unchanged. At accessibility sizes a chip is wider than the bubble, so they
    /// stack instead, each title wrapping (plan 16).
    @ViewBuilder private func sourcesRow(_ sources: [ChatSource]) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(sources.enumerated()), id: \.element.id) { chipIndex, source in
                    sourceChip(source, chipIndex: chipIndex)
                }
            }
            .accessibilityIdentifier("ask.sources.\(index)")
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(sources.enumerated()), id: \.element.id) { chipIndex, source in
                        sourceChip(source, chipIndex: chipIndex)
                    }
                }
                .padding(.vertical, ChatBubbleLayout.chipTargetInset)
            }
            // Its content's height, never more: a scroll view takes whatever height it's offered, and in
            // the bubble's VStack that took height from the answer's text (cut lines at larger sizes).
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, -ChatBubbleLayout.chipTargetInset)
            .accessibilityIdentifier("ask.sources.\(index)")
        }
    }

    private func sourceChip(_ source: ChatSource, chipIndex: Int) -> some View {
        let isLoading = loadingSourceId == source.id
        let stacked = dynamicTypeSize.isAccessibilitySize
        return Button {
            onCitationTap(source.id)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                if isLoading {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: icon(for: source.type))
                        .accessibilityHidden(true)
                }
                Text(displayTitle(source, chipIndex: chipIndex))
                    .lineLimit(stacked ? 3 : 1)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .stashFont(.chip)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: stacked ? 16 : 100))
        }
        .buttonStyle(.stashPlain)
        .disabled(isLoading)
        .accessibilityHint("Opens this source")
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

    /// Plan 16: each glyph takes taps across a 44 pt slot — the slots abut, so the glyphs' centres are
    /// 44 pt apart (they were 26–32) — and 44 pt down: the target overhangs the row above and below
    /// (`.stashPlain`, which also makes the 44 × 44 target the control's VoiceOver frame; Xcode's audit
    /// read the old ones as 44 × 14), and the row sits a little lower so the overhang stays clear of the
    /// answer's last line (a link there keeps its taps). Read-aloud's slot starts at its glyph, so the
    /// glyph stays flush with the text above it.
    @ViewBuilder private var actionsRow: some View {
        if !message.content.isEmpty {
            HStack(spacing: 0) {
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
                    thumbButton(1)
                    thumbButton(-1)
                }
            }
            .stashFont(.meta)
            .foregroundStyle(StashColor.muted)
            .padding(.top, ChatBubbleLayout.actionsExtraTop)
        }
    }

    private var speakerButton: some View {
        let isSpeaking = speech.speakingId == message.id
        let glyph = isSpeaking ? "stop.circle.fill" : "speaker.wave.2"
        return Button {
            speech.toggle(id: message.id, text: message.content)
        } label: {
            Image(systemName: glyph)
                .frame(minWidth: ChatBubbleLayout.actionSlot, alignment: .leading)
        }
        .buttonStyle(.stashPlain)
        // The web's names (ChatMole.tsx: "Read aloud" / "Stop reading").
        .stashIconControl(isSpeaking ? "Stop reading" : "Read aloud", systemImage: glyph)
        .accessibilityIdentifier("ask.bubble.\(index).speak")
    }

    /// Plan 15 (L1 / iOS spec "SSE drop mid-answer: keep partial text, show retry"): the answer
    /// stopped before the server finished; Retry asks the same question again. The row's muted
    /// treatment, at the inline-action size (plan 16: 15 pt, never smaller).
    private var retryButton: some View {
        Button(action: onRetry) {
            HStack(spacing: 4) {
                Image(systemName: "arrow.clockwise")
                Text("Retry")
            }
            .stashFont(.inlineButton)
        }
        .buttonStyle(.stashPlain)
        .accessibilityLabel("Answer interrupted. Retry")
        .accessibilityIdentifier("ask.bubble.\(index).retry")
    }

    /// Thumbs up (`value` 1) or down (−1). Once either is given both are disabled, and the given one
    /// is filled — and, for VoiceOver, selected.
    private func thumbButton(_ value: Int) -> some View {
        let up = value == 1
        let glyph = up ? "hand.thumbsup" : "hand.thumbsdown"
        let given = rating == value
        return Button {
            submitFeedback(value)
        } label: {
            Image(systemName: given ? glyph + ".fill" : glyph)
                .frame(minWidth: ChatBubbleLayout.actionSlot)
        }
        .buttonStyle(.stashPlain)
        .disabled(rating != nil)
        .stashIconControl(up ? "Helpful" : "Not helpful", systemImage: glyph)
        .accessibilityAddTraits(given ? .isSelected : [])
        .accessibilityIdentifier("ask.bubble.\(index).\(up ? "thumbsUp" : "thumbsDown")")
    }

    /// Fire-and-forget, matching `SupabaseChatHistory.persist`'s shape (ChatHistoryAPI.swift):
    /// failures are printed, never surfaced — a feedback row is a nice-to-have, not something that
    /// should interrupt the conversation. Columns per `chat_feedback` (src/integrations/supabase/
    /// types.ts, cross-checked against ChatMessageFeedback.tsx's insert): user_id, question,
    /// answer, source_item_ids (nullable), rating (1 up / -1 down).
    private func submitFeedback(_ value: Int) {
        guard rating == nil else { return }
        ratings.record(value, for: message.id)
        guard !Self.keepsFeedbackLocal else { return }
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

/// Where VoiceOver's focus is sent on the Ask tab (plan 16, task 2d) — `AskView`'s
/// `@AccessibilityFocusState`. Every element bound to it has a value of its own that never changes
/// while it's on screen: no two elements share one (which leaves it to SwiftUI which of them focus goes
/// to), and none moves to a new element as an answer streams (focus could follow it there).
enum AskAccessibilityFocus: Hashable {
    /// An element of the answer with this message id: its block `block`, and in a list, item `item`
    /// (0 for every other block).
    case answer(messageId: String, block: Int, item: Int)
    /// The status line of the answer with this message id, shown until its first words.
    case answerStatus(String)
    /// The composer's field.
    case composer

    /// `message`'s last VoiceOver element — its last block, the last item of a list, or before the first
    /// words its status line: what's on screen at the thread's end. Nil for a question, or for an answer
    /// with nothing to read yet.
    @MainActor
    static func lastElement(of message: ChatMessage) -> AskAccessibilityFocus? {
        guard message.role == .assistant else { return nil }
        let rendered = ChatRenderCache.shared.answer(for: message)
        guard !rendered.displayText.isEmpty, let last = rendered.blocks.last else {
            return message.streamStatus == nil ? nil : .answerStatus(message.id)
        }
        let item = switch last {
        case .bullets(let items), .numbered(let items): items.count - 1
        default: 0
        }
        return .answer(messageId: message.id, block: rendered.blocks.count - 1, item: item)
    }
}

/// The Ask thread's bubble geometry, in one place (plan 16, task 2d). The thread lays its rows out with
/// it, and its tail budget (`AskThreadTail.bubbleTextInset`) reads what a line of answer text is left
/// with — so a change here can't leave the budget measuring a different bubble.
enum ChatBubbleLayout {
    /// The thread's own horizontal padding, each side (`AskView`).
    static let threadInset: CGFloat = 16
    /// The least room a bubble leaves on its far side: its spacer's minimum length.
    static let farSideGap: CGFloat = 40
    /// Between a bubble and its spacer.
    static let spacing: CGFloat = 8
    /// An answer bubble's padding, every side.
    static let answerPadding: CGFloat = 12
    /// A question bubble's padding.
    static let questionHorizontalPadding: CGFloat = 14
    static let questionVerticalPadding: CGFloat = 10
    /// Between an answer's parts: its text, its source chips, its actions row.
    static let answerSpacing: CGFloat = 8
    /// A line of answer text is the thread's width less this: the thread's padding, the far-side gap
    /// and its spacing, and the answer bubble's own padding.
    static let answerTextInset = threadInset * 2 + farSideGap + spacing + answerPadding * 2

    /// An action's slot in the actions row: the width of its target, and so the distance between the
    /// centres of neighbouring actions (HIG: 44 pt).
    static let actionSlot: CGFloat = 44
    /// The actions row sits this much further below the answer (plan 16), so the targets' overhang —
    /// half of 44 less half the glyph's height, about 13.5 pt at the default size — stays clear of the
    /// answer's last line: `answerSpacing` plus this is 14.
    static let actionsExtraTop: CGFloat = 6
    /// Room above and below the source chips, inside their scroll view, for each chip's 44 pt target
    /// (a chip is about 25 pt tall at the default size). Drawn, not laid out.
    static let chipTargetInset: CGFloat = 10
    /// Extra room under the chips, so a chip's centre and an action's below are 44 pt apart.
    static let chipsBottomGap: CGFloat = 10
}

/// The blinking `▍` while an answer streams — the same look as ever (opacity 1 ↔ 0.15, ease-in-out
/// 0.6 s).
///
/// Plan 16 (task 2d): the repeating animation is scoped to the opacity ALONE (`animation(_:body:)`).
/// It used to be `.animation(_:value:)` on the cursor, which applies to every change in the cursor's
/// subtree in the update where the value flips — its position in the answer's row included. The flip
/// is in `onAppear`, and when that update also moved the cursor (the status line arriving beside it, or
/// the first words replacing it), the move took the repeating animation: the cursor slid back and
/// forth between where it had been and where it belonged for the rest of the answer, drawn over the
/// text ("Point 33: a▍short scripted line" on iOS 26.5). (Final wave B had already scoped it to the
/// cursor; before that, `withAnimation(.repeatForever)` in `onAppear` caught the whole row's layout.)
///
/// Reduce Motion: no blink — the cursor stays solid. It's decoration, so VoiceOver skips it.
private struct StreamingCursor: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dimmed = false

    var body: some View {
        Text("▍")
            .stashFont(.reading)
            .foregroundStyle(StashColor.muted)
            .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) { cursor in
                cursor.opacity(dimmed ? 0.15 : 1)
            }
            .onAppear { dimmed = !reduceMotion }
            // A rebuild, not an animated change, when Reduce Motion is switched: nothing is left
            // repeating.
            .id(reduceMotion)
            .accessibilityHidden(true)
    }
}

/// An assistant answer's markdown, drawn from `ChatRenderCache`'s memoized blocks (plan 15, M1)
/// instead of re-parsing the whole answer on every render. The layout is `MarkdownBlocksView`'s
/// (Detail/MarkdownBlocksView.swift) at the chat's tighter rhythm.
///
/// Plan 16 (task 2d): a block's role and colour go INTO `inlineText`, which builds the `Text` —
/// applied outside it they're dead (the inner `Text`'s own font and colour win), which is why `##`
/// headings rendered in the Book face and quotes in `ink`. Headings are VoiceOver headings too. List
/// markers are `muted` (a number carries the order; `faint` was 2.5:1 on the bubble). The gaps grow
/// with the text, like its leading.
private struct ChatAnswerText: View {
    let blocks: [ChatRenderedBlock]
    let messageId: String
    let accessibilityFocus: AccessibilityFocusState<AskAccessibilityFocus?>.Binding

    @ScaledMetric(relativeTo: .body) private var gap: CGFloat = 6

    var body: some View {
        VStack(alignment: .leading, spacing: gap) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { offset, block in
                view(for: block, at: offset)
            }
        }
        // Always as tall as its text needs at the width it's given. Placed at its measured height, a
        // VStack shares that height out by its children's flexibility, and a text can give height up by
        // cutting lines — so anything flexible nearby could take it (plan 16: the quote's bar, the chip
        // row's scroll view; "3. Bake with it at its p…" at AX3 on plan 15's code too).
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private func view(for block: ChatRenderedBlock, at index: Int) -> some View {
        switch block {
        case .paragraph(let text):
            inlineText(text)
                .accessibilityFocused(accessibilityFocus, equals: focusValue(index))

        case .heading(let text):
            inlineText(text, role: .readingSemibold)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused(accessibilityFocus, equals: focusValue(index))

        case .bullets(let items):
            list(items, block: index) { _ in "•" }

        case .numbered(let items):
            list(items, block: index) { "\($0 + 1)." }

        case .quote(let text):
            // The bar is drawn beside the text, not laid out with it (plan 16): as a `Rectangle` in an
            // HStack it was a block that could take any height, so when the answer was placed at its
            // measured height the VStack shared that height out by flexibility — every other block got
            // less than it needed and was cut ("3. Bake with it at its p…" at AX3, on plan 15's code
            // too), and the quote took the rest as blank lines.
            inlineText(text, color: StashColor.muted)
                .accessibilityFocused(accessibilityFocus, equals: focusValue(index))
                .padding(.leading, 12)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(StashColor.violet600)
                        .frame(width: 2)
                        .accessibilityHidden(true)
                }

        case .code(let text):
            Text(text)
                .stashFont(.mono(.subheadline))
                .foregroundStyle(StashColor.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(StashColor.wash, in: RoundedRectangle(cornerRadius: StashRadius.input))
                .accessibilityFocused(accessibilityFocus, equals: focusValue(index))
        }
    }

    /// Block `block`'s VoiceOver element — item `item` of a list — as `AskView` names it to send focus
    /// there (`AskAccessibilityFocus.answer`). Each element's own value, the same for as long as it's on
    /// screen.
    private func focusValue(_ block: Int, item: Int = 0) -> AskAccessibilityFocus {
        .answer(messageId: messageId, block: block, item: item)
    }

    /// A bulleted or numbered list: one VoiceOver element per item (marker and text together).
    private func list(_ items: [AttributedString], block: Int, marker: @escaping (Int) -> String) -> some View {
        VStack(alignment: .leading, spacing: gap) {
            ForEach(Array(items.enumerated()), id: \.offset) { offset, item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    // The system body face, as before (a round bullet; Neue Montreal's is square) — a
                    // text style, so it scales with the item and follows Bold Text by itself.
                    Text(marker(offset))
                        .font(.body)
                        .foregroundStyle(StashColor.muted)
                    inlineText(item)
                }
                .padding(.leading, 16)
                .accessibilityElement(children: .combine)
                .accessibilityFocused(accessibilityFocus, equals: focusValue(block, item: offset))
            }
        }
    }

    /// One markdown run as a `Text` in `role` and `color` — both passed in, never applied outside (see
    /// the type's doc). Links — the answer's inline citations — in DESIGN.md violet600 (4.64:1 on the
    /// bubble), underlined with the shared link underline, `Text.LineStyle.stashLinkUnderline` (violet-600 at
    /// 80 %, ≈ #8879d8 on the bubble's #f2f2f7, 3.26:1; plan 16, WCAG 1.4.1: colour alone can't mark a link —
    /// violet-600 against ink body text is 2.93:1, against a quote's `muted` 1.04:1). The same style as
    /// the detail sheet's `MarkdownBlocksView`.
    private func inlineText(_ parsed: AttributedString, role: StashType.Role = .reading,
                            color: Color = StashColor.ink) -> some View {
        var attributed = parsed
        let linkRanges = attributed.runs.filter { $0.link != nil }.map(\.range)
        for range in linkRanges {
            attributed[range].foregroundColor = StashColor.violet600
            attributed[range].underlineStyle = Text.LineStyle.stashLinkUnderline
        }
        return Text(attributed)
            .chatBubbleText(role)
            .foregroundStyle(color)
            .frame(maxWidth: nil, alignment: .leading)
    }
}

extension View {
    /// Sets bubble text the one way `ChatBubble` lays it out: the role's face and size (`.reading`,
    /// or `.readingSemibold` for a heading — passed IN, never applied outside) and the space between
    /// lines, which grows with the text (`stashLeading`, 0.35 em: CSS line-height 1.35). Every line of
    /// a question or an answer goes through here, and so does the Ask thread's text gauge
    /// (`AskBubbleTextGauge`, on the default role), which measures a sample set this way to size the
    /// thread's laid-out tail by height (`ChatThreadTail`, plan 16 task 1c). So a change of type here
    /// moves the tail's budget with it: set bubble text through this modifier, never with its own
    /// `.font` or `.lineSpacing`.
    func chatBubbleText(_ role: StashType.Role = .reading) -> some View {
        stashFont(role)
            .stashLeading(0.35, role: role)
    }
}

/// The thumbs the user gave each answer this session, by message id (plan 16 task 1c, review nit
/// N5). A bubble used to hold its rating in its own `@State`, which starts over whenever the row is
/// rebuilt — and the Ask thread rebuilds a row whenever it moves from the laid-out tail into the lazy
/// history (`AskThreadTail`), which since task 1c happens at every answer the reader follows to its
/// end. The given thumb then showed unset again, and a second tap could insert a second
/// `chat_feedback` row. Kept by `AskView`, so it lasts as long as the Ask tab does.
@MainActor
@Observable
final class ChatRatings {
    private var values: [String: Int] = [:]

    func value(for messageId: String) -> Int? { values[messageId] }

    func record(_ rating: Int, for messageId: String) { values[messageId] = rating }
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
    @Previewable @AccessibilityFocusState var focus: AskAccessibilityFocus?
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
        ratings: ChatRatings(),
        accessibilityFocus: $focus,
        onCitationTap: { _ in },
        onRetry: {}
    )
    .padding()
}
