import SwiftUI
import Observation
import StashKit
import AVFoundation

/// The Ask tab: streaming Q&A over the user's stash (`ChatStore`), with citation links/chips that
/// open the existing read-only detail sheet, and read-aloud. Retrieval-only (plan 15, M11): every
/// message is a question — capture belongs to the Add tab and the share sheet, as on the web.
///
/// Plan 15 tune-up: while an answer streams the session can't be switched out from under it (new
/// chat, history and the restore banner are disabled; leaving the tab defers the let-go until the
/// answer lands — see `ChatStore`), the thread follows the stream until the user drags it away
/// (M2), drags dismiss the keyboard (L10), and error banners clear on the next send and on tap
/// (L2).
///
/// Plan 16 (task 1b): the thread's end is laid out in full (`AskThreadTail`) and every scroll to
/// the end lands on the last row (`scrollToEnd`), so a jump from far up can't land past it.
///
/// Plan 16 (keyboard): the composer's focus is explicit (`inputFocused`). While it's focused the
/// header's right side is the shared keyboard "Cancel" (`StashCancelButton`, as on the Add tab)
/// instead of New chat / History, and the keyboard is put away before anything else is shown —
/// the Conversations list, a restored conversation, a citation's detail sheet. Why: on iOS 26 a
/// navigation push taken while the composer holds the keyboard hands the keyboard back to the
/// composer when the stack pops, and SwiftUI's keyboard avoidance misses that returning keyboard —
/// it sat up over a composer left at its resting position, hidden behind it, with nothing on
/// screen to put it away (reproduced on the iOS 26.5 simulator; iOS 17.5 restores nothing).
struct AskView: View {
    let userId: UUID

    @Environment(SubscriptionStore.self) private var subscription

    @State private var store: ChatStore
    @State private var input = ""
    @State private var speech = SpeechReader()
    @State private var gateMessage: String?
    @State private var citationItem: Item?
    @State private var loadingSourceId: UUID?
    @State private var citationErrorMessage: String?
    @State private var showConversations = false
    /// The composer holds the keyboard. Drives the header's Cancel swap; cleared before the
    /// Conversations list, a restored conversation or a citation sheet is shown (plan 16).
    @FocusState private var inputFocused: Bool

    // Thread-follow state (M2, review fix).
    /// Pin the thread to its end as it grows. Turned OFF only by the user dragging the thread
    /// away from the end (`AskThreadScrollObserver` — programmatic scrolls and content growth
    /// never count); back ON when they drag to the end again, send, retry, or the thread is
    /// replaced.
    @State private var isFollowing = true
    /// The thread's UIScrollView, so a follow-scroll never lands under a moving finger.
    @State private var threadScroll = AskThreadScrollHandle()
    @State private var threadVisible = false
    /// The thread was replaced while off screen (e.g. a conversation opened from the pushed
    /// Conversations list) — land at its end when it's next shown. True for the first appearance.
    @State private var jumpToBottomOnAppear = true
    @State private var lastMessageCount = 0
    @State private var lastFirstMessageId: String?
    @State private var answerWasStreaming = false
    /// The next jump to a new question is from away from the end (the user had dragged off it), so
    /// it goes without animation: an eased scroll across screens of history reads as a blur.
    @State private var nextSendJumpIsFar = false
    /// Where the thread's lazy history ends and its laid-out tail begins (task 1b).
    @State private var tail = AskThreadTail()

    /// Exists purely to satisfy `ItemDetailView`'s init — citation sheets are read-only here (per
    /// the brief), so this store's own `items`/save plumbing is never read by anything else; it
    /// is intentionally not shared with the View tab's `ItemStore`.
    @State private var citationStore: ItemStore

    /// The thread's top: where an empty thread scrolls to.
    private static let threadTopID = "ask-thread-top"
    /// The gap below every row. It's in the row, not the stack's spacing, so the last row brings
    /// its own gap above the composer when a scroll bottom-aligns it.
    private static let rowGap: CGFloat = 14

    #if DEBUG
    /// `--uitest-scripted-chat` (UI tests only): answers come from `ScriptedChatStreamer` — a
    /// long, list-heavy answer streamed locally over ~6 s, status frames first — with in-memory
    /// history, so nothing reaches or is saved on the server and the subscription gate (a client
    /// check guarding a server call that never happens here) is bypassed. Compiled out of Release.
    private static let usesScriptedChat = ProcessInfo.processInfo.arguments.contains("--uitest-scripted-chat")
    #else
    private static let usesScriptedChat = false
    #endif

    init(userId: UUID) {
        self.userId = userId
        _store = State(initialValue: Self.makeStore(userId: userId))
        _citationStore = State(initialValue: ItemStore(userId: userId, fetcher: SupabaseItemsFetcher()))
    }

    private static func makeStore(userId: UUID) -> ChatStore {
        #if DEBUG
        if usesScriptedChat {
            let longThread = ProcessInfo.processInfo.arguments.contains("--uitest-scripted-long-thread")
            return ChatStore(userId: userId,
                             streamer: ScriptedChatStreamer(chunkInterval: .milliseconds(longThread ? 250 : 110)),
                             history: ScriptedChatHistory(longThread: longThread),
                             accessToken: { "scripted" })
        }
        #endif
        return ChatStore(
            userId: userId,
            streamer: LiveChatStreamer(),
            history: SupabaseChatHistory(),
            accessToken: { try await StashClient.shared.auth.session.accessToken }
        )
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                askHeader
                sessionTitlePill
                thread
                Divider()
                composerArea
            }
            .background(Color(.systemBackground))
            // Registered-but-hidden: no visible title anywhere on this tab (Will's call — no
            // wordmark on View/Ask/Settings), but the nav title still feeds the pushed
            // Conversations screen's back button ("‹ Ask").
            .navigationTitle("Ask")
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $showConversations) {
                ConversationsListView(store: store)
            }
        }
        // Fire on tab switches only (pushing Conversations keeps this NavigationStack on
        // screen): the iOS analog of collapsing the web mole — an explicitly loaded old
        // conversation is let go, restorable via the banner. Mid-answer the store defers the
        // let-go until the answer lands; coming back first cancels it. Read-aloud stops with the
        // tab, so it can never be left holding the audio session a voice memo needs.
        .onAppear { store.cancelPendingLetGo() }
        .onDisappear {
            store.letGoIfExplicit()
            speech.stop()
        }
        .task {
            await store.loadHistoryOnce()
            #if DEBUG
            seedCitationScreenshotFixtureIfRequested()
            #endif
        }
        .onChange(of: store.errorRestoredInput) { _, restored in
            if let restored { input = restored }
        }
        // The server's own paywall refused the question (`403 subscription_required`, final wave
        // B): the same gate copy as the client-side check, and a forced re-check so the local
        // gate — which let the send through (out of date, or still failing open) — catches up.
        .onChange(of: store.subscriptionRefusals) { _, _ in
            gateMessage = Self.gateCopy
            Task { await subscription.refresh(force: true) }
        }
        .sheet(item: $citationItem) { item in
            ItemDetailView(item: item, store: citationStore)
        }
    }

    // MARK: - Header

    /// The pre-plan-7 header affordance, restored (Will's reversal, 2026-09-03: "the previous
    /// implementation of 'start a new chat' and 'earlier conversations' … was the better
    /// approach — go back to this"), PLUS plan 12's "Chat with your Stash" title (Will: "add a
    /// title back to the 'Ask' tab") — left-aligned in the same row, same two round icon buttons
    /// right-aligned, same accessibility identifiers as before (`ask.newChat`/`ask.history`) so
    /// `testConversationsSmoke`'s navigation and `testAskHeaderButtonsOpenConversations`'s
    /// above-the-bubble assertion both keep working unchanged.
    ///
    /// Plan 15 (H4): both are disabled while an answer streams, so the answer can never be
    /// dropped or filed into another conversation by a mid-stream session switch.
    ///
    /// Plan 16 (Will: "when keyboard is shown and input is active while composing on Ask view,
    /// upper right should become 'cancel' (same as when composing on the home screen)"): while the
    /// composer is focused the two circles give way to `StashCancelButton` (`ask.dismissKeyboard`)
    /// — keyboard away, draft kept. It also means History can't be opened while the composer holds
    /// the keyboard (the stuck-keyboard path; see the type doc), though it clears focus anyway.
    private var askHeader: some View {
        HStack(spacing: 8) {
            Text("Chat with your Stash")
                .font(StashType.medium(size: 22))
                .foregroundStyle(StashColor.ink)
            Spacer()
            if inputFocused {
                StashCancelButton(identifier: "ask.dismissKeyboard") {
                    inputFocused = false
                }
            } else {
                Button {
                    store.startNewChat()
                } label: {
                    CircleIcon(systemImage: "square.and.pencil", size: 36)
                }
                .buttonStyle(.plain)
                .disabled(store.isStreaming)
                .accessibilityLabel("Start new chat")
                .accessibilityIdentifier("ask.newChat")

                Button {
                    inputFocused = false
                    showConversations = true
                } label: {
                    CircleIcon(systemImage: "clock", size: 36)
                }
                .buttonStyle(.plain)
                .disabled(store.isStreaming)
                .accessibilityLabel("Earlier conversations")
                .accessibilityIdentifier("ask.history")
            }
        }
        // A 44 pt row so the Cancel's hit area fits without the header changing height when it
        // swaps in; with the insets below the 36 pt circles and the title sit exactly where they
        // did before (top 8 + 36 + bottom 4 = 48 = top 4 + 44).
        .frame(minHeight: 44)
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }

    // MARK: - Session chrome (title pill + restore banner)

    /// Shown while an explicitly opened old conversation is on screen — the one visual cue
    /// that replies will continue that session (gap-exempt) rather than today's thread.
    @ViewBuilder private var sessionTitlePill: some View {
        if store.isExplicitSession, let title = store.sessionTitle {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "clock").font(.system(size: 11))
                    Text(title).lineLimit(1).truncationMode(.tail)
                }
                .font(StashType.meta())
                .foregroundStyle(StashColor.violet600)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(StashColor.violet600.opacity(0.12), in: Capsule())
                .overlay(Capsule().strokeBorder(StashColor.violet300.opacity(0.6), lineWidth: 1))
                .accessibilityIdentifier("ask.sessionPill")
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 2)
        }
    }

    /// Web's "Load previous conversation — <title>" banner: appears only on an empty thread
    /// after an explicitly loaded conversation was let go (tab switch or Start new chat).
    /// Disabled while a send is in flight — it's still on screen while that send resolves its
    /// session, and the store refuses the switch then anyway (H4). Puts the keyboard away first
    /// (plan 16): the restored conversation is shown to be read.
    @ViewBuilder private var restoreBanner: some View {
        if store.messages.isEmpty, let previous = store.lastLoaded {
            Button {
                inputFocused = false
                Task { await store.restorePrevious() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 12))
                        .foregroundStyle(StashColor.muted)
                    (Text("Load previous conversation — ")
                        + Text(previous.title ?? "Untitled").foregroundStyle(StashColor.violet600))
                        .font(StashType.meta())
                        .foregroundStyle(StashColor.muted)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(StashColor.hairline, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            }
            .buttonStyle(.plain)
            .disabled(store.isStreaming)
            .accessibilityIdentifier("ask.restoreBanner")
            .padding(.bottom, Self.rowGap)
        }
    }

    // MARK: - Thread

    /// Task 1b: the thread's history is a `LazyVStack`, and its end is a plain `VStack` (see
    /// `AskThreadTail`), so every scroll to the end lands on rows that are laid out.
    private var thread: some View {
        let messages = store.messages
        let questions = Self.precedingQuestions(in: messages)
        let lastIndex = messages.indices.last
        let historyCount = tail.historyCount(for: messages)
        return ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    restoreBanner
                    if messages.isEmpty {
                        emptyState
                    }
                    LazyVStack(alignment: .leading, spacing: 0) {
                        rows(messages, 0..<historyCount, questions: questions, lastIndex: lastIndex)
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        rows(messages, historyCount..<messages.count, questions: questions, lastIndex: lastIndex)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 12)
                .padding(.bottom, 4)
                // M2: the user's own drags decide whether the thread keeps following. Must sit
                // inside the scrolled content (it walks up to the real UIScrollView).
                .background(
                    AskThreadScrollObserver(handle: threadScroll) { atEnd in
                        if isFollowing != atEnd { isFollowing = atEnd }
                    }
                )
                .id(Self.threadTopID)
            }
            // L10: drag the thread to put the keyboard away (the composer field has no other
            // dismiss path).
            .scrollDismissesKeyboard(.interactively)
            .accessibilityIdentifier("ask.thread")
            .onChange(of: store.messages) { _, newMessages in
                followThread(newMessages, proxy: proxy)
            }
            .onAppear { threadVisible = true }
            .onDisappear { threadVisible = false }
            .task {
                // Lands at the end on first appearance and after the thread was replaced while
                // hidden — never on a plain tab re-appear, which keeps the reader's position (M2).
                // The short wait lets a just-replaced thread lay out first: an immediate scrollTo
                // on a still-measuring scroll view is a no-op.
                guard jumpToBottomOnAppear else { return }
                try? await Task.sleep(for: .milliseconds(50))
                guard !Task.isCancelled else { return }
                jumpToBottomOnAppear = false
                scrollToEnd(proxy)
            }
            // Every assistant bubble's inline citation links (`ChatCitations.link`, baked as
            // `#item=<uuid>` — or the legacy `stash://item/<uuid>` form some rows may still carry
            // from round 1 of plan 8's task 4) route through this one handler rather than each
            // `ChatBubble` wiring its own — set once at the thread level, same as the web's single
            // `onSourceClick` prop threaded through `ChatMole`'s markdown renderer.
            // `ChatCitations.itemID(from:)` is the single source of truth for both forms, so this
            // handler and what `ChatCitations` renders as a link never drift apart. Anything else
            // (a real http(s) link inside an AI answer, or an unresolved `#3` fragment — though
            // `stripUnresolvedMarkers` should mean none of those reach here as a link at all)
            // falls through to the system.
            .environment(\.openURL, OpenURLAction { url in
                guard let id = ChatCitations.itemID(from: url) else { return .systemAction }
                openCitation(id)
                return .handled
            })
        }
    }

    /// The rows at `range` (indices into `messages`), each carrying the thread's gap below it.
    @ViewBuilder
    private func rows(_ messages: [ChatMessage], _ range: Range<Int>, questions: [String], lastIndex: Int?) -> some View {
        ForEach(Array(messages[range].enumerated()), id: \.element.id) { offset, message in
            let index = range.lowerBound + offset
            // `.equatable()` (plan 15, M1): SwiftUI compares bubbles with `ChatBubble.==`, so a
            // streaming delta re-renders only the answer it changed. `loadingSourceId` is passed
            // only to the bubble that owns that source, for the same reason.
            let ownsLoadingSource = message.sources.contains { $0.id == loadingSourceId }
            let showsRetry = message.isInterrupted && index == lastIndex && !store.isStreaming
            ChatBubble(
                message: message,
                index: index,
                question: questions[index],
                userId: userId,
                loadingSourceId: ownsLoadingSource ? loadingSourceId : nil,
                showsRetry: showsRetry,
                speech: speech,
                onCitationTap: openCitation,
                onRetry: { retryTapped(messageId: message.id) }
            )
            .equatable()
            .padding(.bottom, Self.rowGap)
            .id(message.id)
        }
    }

    /// Web's welcome bubble copy, verbatim (`ChatMole.tsx:494`). Shown for every new
    /// conversation (Will's call — kept even with the header chrome removed).
    private var emptyState: some View {
        Text("Ask anything about what you've saved — answers cite the cards they came from.")
            .font(StashType.body())
            .foregroundStyle(StashColor.muted)
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
            .accessibilityIdentifier("ask.emptyState")
    }

    /// M2 (review fix): while `isFollowing`, every change pins the thread to its end — each
    /// streamed publish (`ChatStore` already caps those at ~10 Hz), with no throttle, so a burst
    /// of lines can never outrun the view — plus settle scrolls once the answer completes (its
    /// thumbs/source-chips row lays out after that change). Nothing here ever turns following
    /// OFF: only a user drag does (`AskThreadScrollObserver`). A replaced thread (history
    /// restored, conversation opened, new chat) lands at its end and follows again.
    private func followThread(_ messages: [ChatMessage], proxy: ScrollViewProxy) {
        let firstId = messages.first?.id
        let threadReplaced = firstId != lastFirstMessageId
        lastFirstMessageId = firstId
        let rowsChanged = messages.count != lastMessageCount
        lastMessageCount = messages.count
        let answerStreaming = messages.last?.isStreaming ?? false
        let answerCompleted = answerWasStreaming && !answerStreaming
        answerWasStreaming = answerStreaming
        let jumpIsFar = nextSendJumpIsFar
        if rowsChanged { nextSendJumpIsFar = false }

        if threadReplaced {
            isFollowing = true
            if threadVisible {
                scrollToEnd(proxy)
            } else {
                jumpToBottomOnAppear = true
            }
            return
        }
        // Never pin under a finger: while one is on the thread (touch-down included) or the thread
        // is still gliding after it, the user's gesture decides — it either leaves the end
        // (following stops) or doesn't, and the next publish pins again.
        guard isFollowing, !threadScroll.userIsScrolling else { return }
        // On a jump from far up, the tail sheds the rows it no longer needs (see `AskThreadTail`):
        // they're off screen below the reader, and the jump below lands on the new rows.
        if rowsChanged && jumpIsFar {
            tail.shed(messages)
        }
        // A new question eases in when the thread was at its end. Growth of the streaming answer
        // pins without animation, so a scroll is never still in flight when the user puts a finger
        // on the thread.
        scrollToEnd(proxy, animated: rowsChanged && !jumpIsFar)
        if answerCompleted {
            Task { @MainActor in
                // Final wave B: the finished answer re-renders (baked citations, actions row) and
                // re-measures for a few hundred ms more (on the iOS 17.0 simulator its height went
                // 2401 → 1987 → 2182 pt after one settle scroll). So hold the end while it settles:
                // bounded, and never under a finger or once the user has scrolled away.
                try? await Task.sleep(for: .milliseconds(150))
                for _ in 0..<13 {
                    guard isFollowing, !threadScroll.userIsScrolling else { return }
                    scrollToEnd(proxy)
                    try? await Task.sleep(for: .milliseconds(100))
                }
            }
        }
    }

    /// Scrolls to the thread's end: the last row's bottom (its gap included) at the bottom of the
    /// viewport; an empty thread goes to its top.
    ///
    /// Task 1b: the target is always a row in the laid-out tail (`AskThreadTail`), never a
    /// position the lazy stack has to estimate. It used to be a 1 pt anchor view after the last
    /// row, and in the completion settle the scroll view's absolute content end. From far up a long
    /// thread neither was built, so both were estimates: the lazy stack sizes rows it hasn't built
    /// at the average height of the ones it has, several hundred points with list answers. The jump
    /// then landed past the last real row, and the thread stayed blank until the user dragged back
    /// up (iOS 17.5, 18.5 and 26.5). On 26.5 a long thread could instead send the lazy stack's
    /// placement into a loop at full CPU, and on 18.5 a restored thread could stop short of its end.
    private func scrollToEnd(_ proxy: ScrollViewProxy, animated: Bool = false) {
        let target = store.messages.last?.id ?? Self.threadTopID
        let anchor: UnitPoint = store.messages.isEmpty ? .top : .bottom
        if animated {
            withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(target, anchor: anchor) }
        } else {
            proxy.scrollTo(target, anchor: anchor)
        }
    }

    /// For each row, the nearest preceding `.user` message's text (see `ChatBubble.question`) —
    /// one pass over the thread instead of a backwards scan per bubble.
    private static func precedingQuestions(in messages: [ChatMessage]) -> [String] {
        var questions: [String] = []
        questions.reserveCapacity(messages.count)
        var lastQuestion = ""
        for message in messages {
            questions.append(lastQuestion)
            if message.role == .user { lastQuestion = message.content }
        }
        return questions
    }

    // MARK: - Composer

    private var composerArea: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let errorMessage = store.errorMessage {
                banner(errorMessage, identifier: "ask.error") { store.errorMessage = nil }
            }
            if let gateMessage {
                banner(gateMessage, identifier: "ask.gateError") { self.gateMessage = nil }
            }
            if let citationErrorMessage {
                banner(citationErrorMessage, identifier: "ask.citationError") { self.citationErrorMessage = nil }
            }
            ChatComposerBar(text: $input, isFocused: $inputFocused, isSending: store.isStreaming, onSend: sendTapped)
        }
        .padding(12)
    }

    /// L2: tap anywhere on a banner to dismiss it (same look at rest; the plain button style's
    /// press dim is the only feedback). Every banner also clears on the next send.
    private func banner(_ text: String, identifier: String, dismiss: @escaping () -> Void) -> some View {
        Button(action: dismiss) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill").imageScale(.small)
                Text(text).font(StashType.meta()).lineLimit(2)
                Spacer(minLength: 0)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.red, in: RoundedRectangle(cornerRadius: 10))
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Dismisses this message")
        .accessibilityIdentifier(identifier)
    }

    /// Web toast copy, verbatim (ChatMole.tsx `ask()`'s gate branch) — shown for the client-side
    /// gate and for the server's `403 subscription_required` alike.
    private static let gateCopy = "AI chat needs an active trial or subscription."

    private func sendTapped() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        clearBanners()
        guard canAsk else {
            gateMessage = Self.gateCopy
            return
        }
        input = ""
        nextSendJumpIsFar = !isFollowing
        isFollowing = true
        Task { await store.send(text) }
    }

    private func retryTapped(messageId: String) {
        clearBanners()
        guard canAsk else {
            gateMessage = Self.gateCopy
            return
        }
        nextSendJumpIsFar = !isFollowing
        isFollowing = true
        Task { await store.retry(messageId: messageId) }
    }

    private var canAsk: Bool { subscription.canUseAI || Self.usesScriptedChat }

    private func clearBanners() {
        gateMessage = nil
        citationErrorMessage = nil
        store.errorMessage = nil
    }

    #if DEBUG
    /// Plan 8 Task 4 proof-of-rendering: the standing test account is subscription-gate-blocked
    /// for real Ask answers, so citation-link rendering (`ChatCitations.link` → tappable
    /// `#item=<uuid>` links in `ChatBubble`) has no live-answer path to screenshot. Launching with
    /// `--uitest-seed-citation-bubble` (paired with `--uitest-tab-ask`) seeds a fixture exchange
    /// through the exact same `ChatBubble` rendering path a real answer would use — a linked
    /// title (`[Feeding Log](#1)`) and a bare marker (`[1]`) both citing the same source, PLUS a
    /// second source that's never cited by number (the `fetchedInFull` fallback case from
    /// `chat-with-all-content/index.ts`), so the per-source chip filter renders too: one inline
    /// link plus exactly one leftover chip, not all-or-nothing. Never reachable without this exact
    /// launch argument; compiled out of Release.
    private func seedCitationScreenshotFixtureIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("--uitest-seed-citation-bubble") else { return }
        let linkedSource = ChatSource(id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                                      title: "Persimmon Feeding Notes", type: "text", url: nil, n: 1)
        let extraSource = ChatSource(id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
                                     title: "Fruit Tree Almanac", type: "text", url: nil, n: nil)
        let question = ChatMessage(id: "fixture-u", role: .user,
                                   content: "What do my saved items say about persimmons?")
        let answer = ChatMessage(id: "fixture-a", role: .assistant,
                                 content: "Per [Feeding Log](#1), persimmons should be introduced gradually [1] to avoid stomach upset.",
                                 sources: [linkedSource, extraSource])
        store.seedForScreenshot([question, answer])
    }
    #endif

    // MARK: - Citations

    /// Puts the keyboard away (plan 16), as for an earlier conversation: the source opens to be
    /// read, and the composer mustn't hold the keyboard while the sheet is up. A sheet presented over
    /// a focused composer is the same kind of transition as the Conversations push, which handed the
    /// keyboard back when it went away on iOS 26 (see the type doc). Focus is cleared twice, because
    /// the fetch leaves a window:
    /// - at the tap, ahead of the one-load-at-a-time guard, so a second tap while a source loads
    ///   still puts the keyboard away;
    /// - again in the same transaction that presents the sheet, in case the composer was tapped
    ///   while the fetch was in flight.
    private func openCitation(_ id: UUID) {
        inputFocused = false
        guard loadingSourceId == nil else { return }
        loadingSourceId = id
        citationErrorMessage = nil
        Task {
            defer { loadingSourceId = nil }
            do {
                let item = try await SupabaseItemsFetcher().fetchDetail(id: id)
                inputFocused = false
                citationItem = item
            } catch {
                citationErrorMessage = "Couldn't load that item — try again."
            }
        }
    }
}

/// One shared `AVSpeechSynthesizer` for every assistant bubble's read-aloud button — starting a
/// new utterance always stops whatever's currently speaking first, so only one bubble is ever
/// "active" at a time.
///
/// Plan 15 (M3):
/// - Speaks `ChatSpeech.speakableText(from:)` — the web's `stripForSpeech` — so citation links,
///   markdown markers and item UUIDs are never read aloud.
/// - Puts the shared audio session in `.playback` / `.spokenAudio` before speaking, so read-aloud
///   is audible with the silent switch on and after a voice memo left the session in `.record`;
///   once nothing is speaking it deactivates (letting other audio resume) and restores whatever
///   category was set before — but only while the session is still read-aloud's own: if anything
///   else (a voice memo) has re-categorized it since, it's theirs and is left untouched (review
///   fix — deactivating it would cut their recording off).
/// - Stops with the Ask tab (`stop()` from `AskView.onDisappear`).
/// - Delegate callbacks act only for the utterance that's current, so a late `didFinish` for
///   bubble A can't clear bubble B's speaking state after the user switched.
@MainActor
@Observable
final class SpeechReader: NSObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private(set) var speakingId: String?

    @ObservationIgnored private var currentUtterance: AVSpeechUtterance?
    @ObservationIgnored private var savedSessionConfiguration: (category: AVAudioSession.Category,
                                                                mode: AVAudioSession.Mode,
                                                                options: AVAudioSession.CategoryOptions)?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// Stops any read-aloud in progress (the audio session is handed back from `didCancel`).
    func stop() {
        guard speakingId != nil || synthesizer.isSpeaking else { return }
        currentUtterance = nil
        speakingId = nil
        synthesizer.stopSpeaking(at: .immediate)
    }

    func toggle(id: String, text: String) {
        if speakingId == id {
            currentUtterance = nil
            speakingId = nil
            synthesizer.stopSpeaking(at: .immediate)   // didCancel → session released
            return
        }
        synthesizer.stopSpeaking(at: .immediate)
        let spoken = ChatSpeech.speakableText(from: text)
        guard !spoken.isEmpty else {
            currentUtterance = nil
            speakingId = nil
            return
        }
        activateAudioSession()
        let utterance = AVSpeechUtterance(string: spoken)
        currentUtterance = utterance
        speakingId = id
        synthesizer.speak(utterance)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let ended = ObjectIdentifier(utterance)
        Task { @MainActor in self.utteranceEnded(ended) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let ended = ObjectIdentifier(utterance)
        Task { @MainActor in self.utteranceEnded(ended) }
    }

    private func utteranceEnded(_ ended: ObjectIdentifier) {
        if let current = currentUtterance, ObjectIdentifier(current) == ended {
            currentUtterance = nil
            speakingId = nil
        }
        if currentUtterance == nil, !synthesizer.isSpeaking {
            releaseAudioSession()
        }
    }

    private func activateAudioSession() {
        let session = AVAudioSession.sharedInstance()
        if savedSessionConfiguration == nil {
            savedSessionConfiguration = (session.category, session.mode, session.categoryOptions)
        }
        do {
            try session.setCategory(.playback, mode: .spokenAudio)
            try session.setActive(true)
        } catch {
            print("Read-aloud audio session setup failed (non-fatal): \(error)")
        }
    }

    private func releaseAudioSession() {
        guard let saved = savedSessionConfiguration else { return }
        savedSessionConfiguration = nil
        let session = AVAudioSession.sharedInstance()
        // Someone else took the session since read-aloud set it up (e.g. the Add tab's voice
        // recorder switched it to `.record`): it's theirs now — deactivating or re-categorizing
        // it would cut them off.
        guard session.category == .playback, session.mode == .spokenAudio else { return }
        do {
            try session.setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            print("Read-aloud audio session deactivation failed (non-fatal): \(error)")
        }
        do {
            try session.setCategory(saved.category, mode: saved.mode, options: saved.options)
        } catch {
            print("Read-aloud audio session restore failed (non-fatal): \(error)")
        }
    }
}

/// Plan 15 review fix (M2): tells the Ask thread whether the USER has left or returned to the end
/// of the conversation. Reports only for user-driven motion — a finger drag or the momentum after
/// one (`isDragging || isDecelerating`) — never for programmatic scrolls, keyboard insets or the
/// content growing under a still viewport, so a burst of streamed lines can't switch following
/// off by itself.
///
/// UIScrollView KVO rather than SwiftUI geometry, for the reason `LibraryView` documents (verified
/// there): on the iOS 17 floor, geometry/preference tracking fires at layout but not during an
/// interactive scroll. Invisible and zero-size; must sit inside the `ScrollView`'s own content so
/// walking `superview` reaches the real `UIScrollView`.
///
/// Reports are never delivered synchronously (the same fix as `LibraryScrollOffsetObserver`): the
/// KVO callback also fires when SwiftUI's OWN layout moves the content while a drag or glide is in
/// progress — i.e. inside a view update — and writing `@State` (`isFollowing`) there is undefined
/// behavior. That was the "Modifying state during view update" runtime issue the follow-scroll UI
/// test logged now and then (unified-log backtrace: `isFollowing.setter` ← this KVO handler,
/// inside SwiftUI's update). See `Coordinator.userScrolled`.
private struct AskThreadScrollObserver: UIViewRepresentable {
    /// Receives the thread's UIScrollView once found.
    let handle: AskThreadScrollHandle
    /// "Is the viewport at the end of the thread (within 80 pt)?" — called after user-driven offset
    /// changes, on a main-queue turn of its own (a burst of changes yields one call).
    var onUserScroll: (_ atEnd: Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(handle: handle) }

    func makeUIView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        context.coordinator.onUserScroll = onUserScroll
        // `didMoveToWindow` is when this view's full ancestor chain (up through the UIScrollView)
        // exists — see `LibraryScrollOffsetObserver` for the verification.
        view.onWindowAttach = { [weak view, weak coordinator = context.coordinator] in
            guard let view, let coordinator else { return }
            coordinator.attach(from: view)
        }
        return view
    }

    func updateUIView(_ uiView: ProbeView, context: Context) {
        context.coordinator.onUserScroll = onUserScroll
        if uiView.window != nil { context.coordinator.attach(from: uiView) }
    }

    final class ProbeView: UIView {
        var onWindowAttach: (() -> Void)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window != nil { onWindowAttach?() }
        }
    }

    final class Coordinator {
        var onUserScroll: ((Bool) -> Void)?
        private let handle: AskThreadScrollHandle
        private var observation: NSKeyValueObservation?
        /// True while a report to SwiftUI is scheduled on the main queue (see `userScrolled`).
        private var reportScheduled = false

        init(handle: AskThreadScrollHandle) {
            self.handle = handle
        }

        func attach(from view: UIView) {
            guard observation == nil else { return }
            var ancestor = view.superview
            while let candidate = ancestor {
                if let scrollView = candidate as? UIScrollView {
                    handle.scrollView = scrollView
                    observation = scrollView.observe(\.contentOffset, options: [.new]) { [weak self] scrollView, _ in
                        // Only a drag or the glide after one may turn following on or off — never a
                        // touch-down that hasn't moved, a programmatic scroll or content growth. Two
                        // flag reads are safe inside a layout pass; telling SwiftUI is not (see
                        // `userScrolled`).
                        guard scrollView.isDragging || scrollView.isDecelerating else { return }
                        self?.userScrolled(scrollView)
                    }
                    return
                }
                ancestor = candidate.superview
            }
        }

        /// Tells SwiftUI whether the thread now rests at its end, on the next main-queue turn —
        /// outside whatever view update may be running now. A burst of offset changes coalesces
        /// into one report, which reads the layout as it stands then rather than a mid-layout
        /// snapshot. The lag is harmless: a follow-scroll can't pin in between, because it holds
        /// off while `AskThreadScrollHandle.userIsScrolling`.
        ///
        /// Not de-duplicated against the last report on purpose: `isFollowing` has other writers
        /// (send, retry, a replaced thread), so only the receiver may compare with its live value.
        private func userScrolled(_ scrollView: UIScrollView) {
            guard !reportScheduled else { return }
            reportScheduled = true
            DispatchQueue.main.async { [weak self, weak scrollView] in
                guard let self else { return }
                self.reportScheduled = false
                guard let scrollView else { return }
                self.onUserScroll?(Self.isAtEnd(scrollView))
            }
        }

        /// A thread shorter than the viewport is always "at the end" (so a rubber-band pull on a
        /// short thread doesn't stop following); otherwise within 80 pt of the last row counts.
        static func isAtEnd(_ scrollView: UIScrollView) -> Bool {
            let insets = scrollView.adjustedContentInset
            let visibleHeight = scrollView.bounds.height - insets.top - insets.bottom
            guard scrollView.contentSize.height > visibleHeight else { return true }
            let endOffset = scrollView.contentSize.height + insets.bottom - scrollView.bounds.height
            return endOffset - scrollView.contentOffset.y < 80
        }
    }
}

/// A weak reference to the Ask thread's UIScrollView (filled in by `AskThreadScrollObserver`),
/// held in `@State` so follow-scrolls can check whether the user's finger — or the glide after
/// it — is on the thread right now.
final class AskThreadScrollHandle {
    weak var scrollView: UIScrollView?

    /// A finger is on the thread or its momentum is still moving it: touch-down (`isTracking` —
    /// true a beat before `isDragging`, so a pin can't land under a finger that has only just
    /// touched), a drag, or the glide after a lift. Follow-scrolls hold off while this is true.
    /// Broader than what may turn following OFF — that is a drag or glide only
    /// (`AskThreadScrollObserver`), since a bare touch-down moves nothing.
    var userIsScrolling: Bool {
        guard let scrollView else { return false }
        return scrollView.isTracking || scrollView.isDragging || scrollView.isDecelerating
    }
}

/// Task 1b: where the Ask thread's lazily built history ends and its fully laid-out tail begins.
///
/// Why a tail: a `LazyVStack` builds only the rows near the screen and sizes the rest at the
/// average height of the rows it has built. A jump far down is aimed with that estimate, and with
/// answers several screens long it can land past the last real row, with nothing on screen and
/// nothing re-measured (see `AskView.scrollToEnd`). Rows in the tail are always built, so a scroll
/// to the thread's last row lands on it exactly, and so does everything on screen with it: the tail
/// is the last exchange plus earlier rows until it holds `minimumTailCharacters` of text, about a
/// screen and a half or more.
///
/// Why only a tail: built rows cost memory, and each streamed update redraws them all. Laid out in
/// full, a 200-message thread (the History load limit) took about 600 MB in a replica on the
/// simulator, against about 45 MB lazy. And every finished long answer kept in the tail added
/// about ten dropped frames per streamed answer in the app. So a thread starts with just that tail,
/// and on a jump from far up the thread the tail sheds the rows it no longer needs (`shed`).
///
/// Only there, because a shed row is re-estimated by the lazy history, which moves everything below
/// it until the next scroll lands: from far up, that's all off screen. Shedding when an answer
/// completes at the end was measured to flash other content for one frame, before the re-pin
/// landed. So while the reader follows the thread, new exchanges pile up in the tail.
///
/// The split is read during `body`, and set there for a new thread (keyed by its first row), so a
/// thread's first render already has it. Rows only ever move from the tail into the history. A moved
/// row is rebuilt, so it loses its state (a given rating), as a lazy row scrolled far away sometimes
/// does anyway.
@Observable
final class AskThreadTail {
    static let minimumTailCharacters = 2_000

    @ObservationIgnored private var threadKey: String?
    @ObservationIgnored private var historyEnd = 0
    /// Bumped by `shed`, so the thread re-renders with the new split.
    private var sheds = 0

    /// How many leading rows of `messages` are lazy history. The rest are the tail, which always
    /// holds at least the last row.
    func historyCount(for messages: [ChatMessage]) -> Int {
        _ = sheds
        let key = messages.first?.id
        if key != threadKey {
            threadKey = key
            historyEnd = Self.tailStart(in: messages)
        }
        return min(historyEnd, max(0, messages.count - 1))
    }

    /// Moves the rows the tail no longer needs into the history. Call only when nothing below the
    /// reader is on screen and the next scroll lands on the tail (a jump from far up).
    func shed(_ messages: [ChatMessage]) {
        let start = Self.tailStart(in: messages)
        guard messages.first?.id == threadKey, start > historyEnd else { return }
        historyEnd = start
        sheds += 1
    }

    /// Where the tail starts: at the last question, or earlier until the tail holds
    /// `minimumTailCharacters` of text.
    static func tailStart(in messages: [ChatMessage]) -> Int {
        guard !messages.isEmpty else { return 0 }
        var start = messages.lastIndex { $0.role == .user } ?? messages.count - 1
        var characters = messages[start...].reduce(0) { $0 + $1.content.count }
        while start > 0, characters < minimumTailCharacters {
            start -= 1
            characters += messages[start].content.count
        }
        return start
    }
}

#if DEBUG
/// `--uitest-scripted-chat` answers (UI tests only — see `AskView.usesScriptedChat`): status
/// frames first, then a long, list-heavy answer over ~6 s, including two bursts of ten bullets in
/// a single delta (the case that once outran the throttled follow-scroll), ending in a paragraph
/// that names the question — "End of the scripted answer to: <question>" — so a UI test can find
/// each answer's last line. A question starting with "gate:" is refused the way the server's
/// paywall refuses it (`ChatStreamError.subscriptionRequired`, final wave B), before any frame.
///
/// With `--uitest-scripted-long-thread` (task 1b) the chunks come slower, so an answer takes about
/// 12 s: that test's checks on a big thread all land while the answer is still streaming.
private struct ScriptedChatStreamer: ChatStreaming {
    var chunkInterval: Duration = .milliseconds(110)

    func stream(message: String, history: [[String: String]], accessToken: String) -> AsyncThrowingStream<SSEEvent, Error> {
        if message.hasPrefix("gate:") {
            return AsyncThrowingStream { $0.finish(throwing: ChatStreamError.subscriptionRequired) }
        }
        let chunkInterval = chunkInterval
        return AsyncThrowingStream { continuation in
            let task = Task {
                continuation.yield(.status(.searching))
                try? await Task.sleep(for: .milliseconds(400))
                continuation.yield(.status(.reading))
                try? await Task.sleep(for: .milliseconds(400))
                for chunk in Self.answerChunks(for: message) {
                    guard !Task.isCancelled else { break }
                    continuation.yield(.delta(chunk))
                    try? await Task.sleep(for: chunkInterval)
                }
                continuation.yield(.done(sources: []))
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    static func answerChunks(for question: String) -> [String] {
        func bullet(_ n: Int) -> String { "- Point \(n): a short scripted line\n" }
        var chunks = ["Here is everything that matched:\n\n"]
        chunks += (1...20).map(bullet)
        chunks.append((21...30).map(bullet).joined())
        chunks += (31...50).map(bullet)
        chunks.append((51...60).map(bullet).joined())
        chunks.append("\nEnd of the scripted answer to: \(question)")
        return chunks
    }
}

/// In-memory history for `--uitest-scripted-chat`: a fresh thread every launch, nothing persisted —
/// plus one fixed earlier conversation (plan 16), so the Conversations list has a row to open
/// (and search to match) without the server.
///
/// With `--uitest-scripted-long-thread` as well (task 1b), two long conversations join it, each 8
/// exchanges whose answers are the scripted 60-line list (several screens tall): one continues as
/// the latest conversation, so it's restored at launch, and one is listed in History ("Scripted long
/// conversation"). Every far jump the thread makes then runs against rows the lazy stack hasn't
/// loaded.
private struct ScriptedChatHistory: ChatHistoryStoring {
    let longThread: Bool

    private static let earlierId = UUID(uuidString: "5C21B7ED-A5C0-4E16-9D16-000000000016")!
    private static let earlierTitle = "Scripted earlier conversation"
    private static let earlierMessages = [
        ChatMessage(id: "scripted-earlier-q", role: .user, content: "What did I save about sourdough?"),
        ChatMessage(id: "scripted-earlier-a", role: .assistant,
                    content: "A scripted earlier answer about sourdough starters."),
    ]
    private static let latestLongId = UUID(uuidString: "5C21B7ED-A5C0-4E16-9D16-0000000001B1")!
    private static let listedLongId = UUID(uuidString: "5C21B7ED-A5C0-4E16-9D16-0000000001B2")!
    private static let listedLongTitle = "Scripted long conversation"

    /// Questions "Long question <tag>1" … "<tag>8", each answered with the scripted list.
    private static func longMessages(tag: String) -> [ChatMessage] {
        (1...8).flatMap { n -> [ChatMessage] in
            let question = "Long question \(tag)\(n)"
            return [ChatMessage(id: "scripted-long-\(tag)\(n)-q", role: .user, content: question),
                    ChatMessage(id: "scripted-long-\(tag)\(n)-a", role: .assistant,
                                content: ScriptedChatStreamer.answerChunks(for: question).joined())]
        }
    }

    func latestConversation(userId: UUID) async throws -> ChatSessions.Candidate? {
        guard longThread else { return nil }
        return ChatSessions.Candidate(id: Self.latestLongId, title: nil, lastMessageAt: Date().addingTimeInterval(-60))
    }
    func createConversation(userId: UUID) async throws -> UUID { UUID() }
    func loadHistory(conversationId: UUID, limit: Int) async throws -> [ChatMessage] {
        switch conversationId {
        case Self.earlierId: Self.earlierMessages
        case Self.latestLongId where longThread: Self.longMessages(tag: "")
        case Self.listedLongId where longThread: Self.longMessages(tag: "B")
        default: []
        }
    }
    func persist(conversationId: UUID, role: String, content: String, sourceItemIds: [UUID]?) async {}
    func generateTitle(for question: String) async -> String? { nil }
    func setTitle(conversationId: UUID, title: String) async {}
    func listConversations(searchText: String?, pageLimit: Int, pageOffset: Int) async throws -> [ConversationListRow] {
        let query = (searchText ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard pageOffset == 0 else { return [] }
        var rows: [ConversationListRow] = []
        if longThread {
            rows.append(ConversationListRow(id: Self.listedLongId, title: Self.listedLongTitle,
                                            lastMessageAt: Date().addingTimeInterval(-1800), messageCount: 16,
                                            preview: "A scripted long conversation.", totalCount: 0))
        }
        rows.append(ConversationListRow(id: Self.earlierId, title: Self.earlierTitle,
                                        lastMessageAt: Date().addingTimeInterval(-3600), messageCount: 2,
                                        preview: Self.earlierMessages[1].content, totalCount: 0))
        let matching = rows.filter { query.isEmpty || ($0.title ?? "").lowercased().contains(query) }
        return matching.map {
            ConversationListRow(id: $0.id, title: $0.title, lastMessageAt: $0.lastMessageAt,
                                messageCount: $0.messageCount, preview: $0.preview, totalCount: matching.count)
        }
    }
}
#endif
