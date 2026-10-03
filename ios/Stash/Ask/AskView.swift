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
/// Plan 16 (task 1c): the laid-out tail stays bounded. It's sized by height (the viewport and the
/// bubble text as set, `ChatThreadTail`), sheds when an answer completes with the reader at the end,
/// and only a send from above the whole tail sheds before its jump. Whatever changes size, what the
/// reader sees stays put (`AskThreadScrollObserver`): while they follow, the thread's end holds — the
/// lazy history re-measuring, a shed, the keyboard, a rotation, a text-size change — never under a
/// finger; while they read inside the tail, the tail holds still when the history above it
/// re-measures, finger or not.
///
/// Plan 16 (keyboard): the composer's focus is explicit (`inputFocused`). While it's focused the
/// header's right side is the shared keyboard "Cancel" (`StashCancelButton`, as on the Add tab)
/// instead of New chat / History, and the keyboard is put away before anything else is shown —
/// the Conversations list, a restored conversation, a citation's detail sheet. Why: on iOS 26 a
/// navigation push taken while the composer holds the keyboard hands the keyboard back to the
/// composer when the stack pops, and SwiftUI's keyboard avoidance misses that returning keyboard —
/// it sat up over a composer left at its resting position, hidden behind it, with nothing on
/// screen to put it away (reproduced on the iOS 26.5 simulator; iOS 17.5 restores nothing).
///
/// Plan 16 (task 2d, accessibility): text takes the type roles and scales with Dynamic Type (bubbles
/// and the composer at the 17 pt reading size), every control takes taps across at least 44 × 44 pt,
/// informational text meets AA contrast, and VoiceOver names every control. The header never jumps
/// when Cancel swaps in, at any text size (`AskHeader`), and VoiceOver goes to the end of the last
/// answer when Cancel goes. A scroll that isn't a drag — VoiceOver's, a status-bar tap — leaves the
/// thread's end like a drag does (`AskThreadScrollObserver`); a status-bar tap cuts to the thread's top
/// instead of animating there through the lazy history (fix round 1). Under Reduce Motion the thread's
/// eased jumps are cuts and the streaming cursor doesn't blink.
struct AskView: View {
    let userId: UUID

    @Environment(SubscriptionStore.self) private var subscription
    /// VoiceOver and Switch Control move through the thread element by element: while either runs,
    /// every row is laid out (`AskThreadTail.historyCount`, plan 16 task 2d).
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @Environment(\.accessibilitySwitchControlEnabled) private var switchControlEnabled

    @State private var store: ChatStore
    @State private var input = ""
    @State private var speech = SpeechReader()
    /// Thumbs given this session, by message id: they outlive a row's rebuild (task 1c, `ChatRatings`).
    @State private var ratings = ChatRatings()
    @State private var gateMessage: String?
    @State private var citationItem: Item?
    @State private var loadingSourceId: UUID?
    @State private var citationErrorMessage: String?
    @State private var showConversations = false
    /// The composer holds the keyboard. Drives the header's Cancel swap; cleared before the
    /// Conversations list, a restored conversation or a citation sheet is shown (plan 16).
    @FocusState private var inputFocused: Bool
    /// Where VoiceOver's focus goes when Cancel goes away with the keyboard (plan 16, task 2d).
    @AccessibilityFocusState private var accessibilityFocus: AskAccessibilityFocus?

    // Thread-follow state (M2, review fix).
    /// The thread's UIScrollView, so a follow-scroll never lands under a moving finger; and whether
    /// the reader follows (`isFollowing`).
    @State private var threadScroll = AskThreadScrollHandle()
    @State private var threadVisible = false
    /// The thread was replaced while off screen (e.g. a conversation opened from the pushed
    /// Conversations list) — land at its end when it's next shown. True for the first appearance.
    @State private var jumpToBottomOnAppear = true
    @State private var lastMessageCount = 0
    @State private var lastFirstMessageId: String?
    @State private var answerWasStreaming = false
    /// How the jump to the next new question goes, classified at the send from where the reader is
    /// (task 1c, `ChatThreadTail.sendJump`): a hop of up to a screen from up the thread eases, any
    /// other jump cuts, and only a reader above the whole tail sheds it first.
    @State private var nextSendJump = ChatThreadTail.SendJump.fromTheEnd
    /// Where the thread's lazy history ends and its laid-out tail begins (tasks 1b, 1c).
    @State private var tail = AskThreadTail()

    /// Pin the thread to its end as it grows, and hold the end through changes of size. Turned OFF
    /// only by the user dragging the thread away from the end (`AskThreadScrollObserver` —
    /// programmatic scrolls and content growth never count); back ON when they drag to the end
    /// again, send, retry, or the thread is replaced.
    ///
    /// Kept on the handle, unobserved (task 1c), and never read while `body` runs: turning following
    /// on or off must not re-render the thread. A re-render makes the lazy history re-estimate the
    /// rows it hasn't built: when following turned off under a drag, the history above the laid-out
    /// tail re-estimated by +1,036 pt (iOS 17.5) and +4,893 pt (18.5) in the frame after the flip —
    /// layout work for nothing, and a move of the whole tail under the reader's finger that only the
    /// observer's tail hold keeps off the screen.
    private var isFollowing: Bool {
        get { threadScroll.isFollowing }
        nonmutating set { threadScroll.isFollowing = newValue }
    }

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
    /// `--uitest-assistive-layout` (UI tests only): the thread lays out every row, as it does while
    /// VoiceOver or Switch Control runs — neither can run on the Simulator.
    private static let forcesAssistiveLayout = ProcessInfo.processInfo.arguments.contains("--uitest-assistive-layout")
    /// `--uitest-a11y-hooks` (UI tests only): two controls that scroll the thread the way VoiceOver
    /// does — a page up, as its three-finger swipe does, and to the end — which XCUITest can't do
    /// itself (`emulateVoiceOverScroll(toEnd:)`).
    private static let showsAccessibilityHooks = ProcessInfo.processInfo.arguments.contains("--uitest-a11y-hooks")
    #else
    private static let usesScriptedChat = false
    private static let forcesAssistiveLayout = false
    #endif

    init(userId: UUID) {
        self.userId = userId
        _store = State(initialValue: Self.makeStore(userId: userId))
        _citationStore = State(initialValue: ItemStore(userId: userId, fetcher: SupabaseItemsFetcher()))
    }

    private static func makeStore(userId: UUID) -> ChatStore {
        #if DEBUG
        if usesScriptedChat {
            let arguments = ProcessInfo.processInfo.arguments
            let longThread = arguments.contains("--uitest-scripted-long-thread")
            let prose = arguments.contains("--uitest-scripted-prose")
            // `--uitest-scripted-slow` (plan 16, task 2d): 500 ms chunks, an answer of about 23 s — room
            // for a test that does several slow things while one streams.
            let interval = arguments.contains("--uitest-scripted-slow") ? 500 : longThread ? 250 : 110
            return ChatStore(userId: userId,
                             streamer: ScriptedChatStreamer(chunkInterval: .milliseconds(interval), prose: prose),
                             history: ScriptedChatHistory(longThread: longThread, prose: prose),
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
                // Plan 16 (task 2d): when the column runs short — the keyboard up at the largest text
                // sizes — the thread gives way, never the header, the pill or the composer (the
                // header's title was cut from two lines to "Chat with your…" at AX5, and the header
                // seemed to jump).
                askHeader.layoutPriority(1)
                sessionTitlePill.layoutPriority(1)
                thread
                Divider()
                composerArea.layoutPriority(1)
            }
            .background(Color(.systemBackground))
            #if DEBUG
            .overlay(alignment: .topLeading) {
                if Self.showsAccessibilityHooks {
                    HStack(spacing: 4) {
                        Button("VO↑") { emulateVoiceOverScroll(toEnd: false) }
                            .accessibilityIdentifier("ask.debug.voiceOverScrollUp")
                        Button("VO⤓") { emulateVoiceOverScroll(toEnd: true) }
                            .accessibilityIdentifier("ask.debug.voiceOverScrollToEnd")
                    }
                    .font(.caption2)
                    .buttonStyle(.stashPlain)
                    .background(.yellow)
                }
            }
            #endif
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
            seedMarkdownAnswerFixtureIfRequested()
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
    /// Plan 16 (task 2d): the row's layout is `AskHeader`'s; Cancel sends VoiceOver to the thread.
    private var askHeader: some View {
        AskHeader(isComposing: inputFocused, isStreaming: store.isStreaming,
                  onNewChat: { store.startNewChat() },
                  onHistory: {
                      inputFocused = false
                      showConversations = true
                  },
                  onCancel: cancelComposing)
    }

    /// The header's Cancel: the keyboard goes, the draft stays. Cancel goes too (the circles come back
    /// in its place), so VoiceOver is sent somewhere it can read on (plan 16, task 2d): the last element
    /// of the last answer — what's on screen at the thread's end, in the laid-out tail rather than the
    /// lazy history — or, with nothing to read there yet or the reader away from the end, the composer.
    private func cancelComposing() {
        inputFocused = false
        let lastAnswer = isFollowing ? store.messages.last(where: { $0.role == .assistant }) : nil
        let target = lastAnswer.flatMap(AskAccessibilityFocus.lastElement(of:)) ?? .composer
        // On the next turn, once the circles have replaced Cancel.
        DispatchQueue.main.async { accessibilityFocus = target }
    }

    // MARK: - Session chrome (title pill + restore banner)

    /// Shown while an explicitly opened old conversation is on screen — the one visual cue
    /// that replies will continue that session (gap-exempt) rather than today's thread.
    @ViewBuilder private var sessionTitlePill: some View {
        if store.isExplicitSession, let title = store.sessionTitle {
            AskSessionPill(title: title)
        }
    }

    /// Web's "Load previous conversation — <title>" banner: appears only on an empty thread
    /// after an explicitly loaded conversation was let go (tab switch or Start new chat).
    /// Disabled while a send is in flight — it's still on screen while that send resolves its
    /// session, and the store refuses the switch then anyway (H4). Puts the keyboard away first
    /// (plan 16): the restored conversation is shown to be read.
    /// Plan 16 (task 2d): meta text and glyph scale together; the title stays violet-600 (4.64:1 on
    /// the banner's #f2f2f7); the banner takes taps across at least 44 pt of height (`.stashPlain`).
    @ViewBuilder private var restoreBanner: some View {
        if store.messages.isEmpty, let previous = store.lastLoaded {
            Button {
                inputFocused = false
                Task { await store.restorePrevious() }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "arrow.counterclockwise")
                        .accessibilityHidden(true)
                    (Text("Load previous conversation — ")
                        + Text(previous.title ?? "Untitled").foregroundStyle(StashColor.violet600))
                    Spacer(minLength: 0)
                }
                .stashFont(.meta)
                .foregroundStyle(StashColor.muted)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(StashColor.hairline, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            }
            .buttonStyle(.stashPlain)
            .disabled(store.isStreaming)
            .accessibilityIdentifier("ask.restoreBanner")
            .padding(.bottom, Self.rowGap)
        }
    }

    // MARK: - Thread

    /// Task 1b: the thread's history is a `LazyVStack`, and its end is a plain `VStack` (see
    /// `AskThreadTail`), so every scroll to the end lands on rows that are laid out.
    ///
    /// Task 1c: the content has no bottom padding, so a scroll to the last row (its gap included)
    /// rests exactly where a user's drag to the end does. The tail's height is measured for the
    /// scroll observer's holds and the send classification, the viewport's size and the bubble text's
    /// metrics for the tail's budget. The tail's reader writes to the unobserved handle, so a streamed
    /// update re-renders nothing; SwiftUI reports it before it hands the scroll view the content size
    /// that comes with it, in the same layout pass (measured on iOS 17.5, 18.5 and 26.5), which is
    /// what lets the observer tell the tail's own growth from a change above it.
    private var thread: some View {
        let messages = store.messages
        let questions = Self.precedingQuestions(in: messages)
        let lastIndex = messages.indices.last
        let historyCount = tail.historyCount(for: messages,
                                             laysOutEverything: voiceOverEnabled || switchControlEnabled || Self.forcesAssistiveLayout)
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
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { threadScroll.tailHeight = $0 }
                }
                .padding(.horizontal, ChatBubbleLayout.threadInset)
                .padding(.top, 12)
                // M2: the user's own drags decide whether the thread keeps following, and the
                // observer holds what the reader sees through changes of size. Must sit inside the
                // scrolled content (it walks up to the real UIScrollView).
                .background(AskThreadScrollObserver(handle: threadScroll))
                .id(Self.threadTopID)
            }
            // L10: drag the thread to put the keyboard away (the composer field has no other
            // dismiss path).
            .scrollDismissesKeyboard(.interactively)
            .accessibilityIdentifier("ask.thread")
            .onGeometryChange(for: CGSize.self) { $0.size } action: { tail.noteViewport($0) }
            .background { AskBubbleTextGauge(tail: tail) }
            .onChange(of: store.messages) { _, newMessages in
                followThread(newMessages, proxy: proxy)
            }
            .onAppear {
                threadVisible = true
                // The thread's one programmatic scroll besides `scrollToEnd` (plan 16, task 2d fix round 1):
                // a tap on the status bar cuts to the content's own top — laid out, whatever the lazy history
                // holds — without animation (`AskThreadScrollObserver.Coordinator.statusBarTapped`).
                threadScroll.scrollToTop = { proxy.scrollTo(Self.threadTopID, anchor: .top) }
            }
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
                settleAtTheEnd(proxy)
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
                ratings: ratings,
                accessibilityFocus: $accessibilityFocus,
                onCitationTap: openCitation,
                onRetry: { retryTapped(messageId: message.id) }
            )
            .equatable()
            .padding(.bottom, Self.rowGap)
            .id(message.id)
        }
    }

    /// Web's welcome bubble copy, verbatim (`ChatMole.tsx:494`). Shown for every new
    /// conversation (Will's call — kept even with the header chrome removed). Plan 16: at the
    /// bubbles' reading size; `muted` is 4.82:1 on its #f2f2f7.
    private var emptyState: some View {
        Text("Ask anything about what you've saved — answers cite the cards they came from.")
            .stashFont(.reading)
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
    /// restored, conversation opened, new chat) lands at its end, settles there (task 1c,
    /// `settleAtTheEnd`) and follows again.
    private func followThread(_ messages: [ChatMessage], proxy: ScrollViewProxy) {
        let firstId = messages.first?.id
        let threadReplaced = firstId != lastFirstMessageId
        lastFirstMessageId = firstId
        let rowsChanged = messages.count != lastMessageCount
        lastMessageCount = messages.count
        let answerStreaming = messages.last?.isStreaming ?? false
        let answerCompleted = answerWasStreaming && !answerStreaming
        answerWasStreaming = answerStreaming
        let jump = nextSendJump
        if rowsChanged { nextSendJump = .fromTheEnd }

        if threadReplaced {
            isFollowing = true
            if threadVisible {
                scrollToEnd(proxy)
                settleAtTheEnd(proxy)
            } else {
                jumpToBottomOnAppear = true
            }
            return
        }
        // Never pin under a finger: while one is on the thread (touch-down included) or the thread
        // is still gliding after it, the user's gesture decides — it either leaves the end
        // (following stops) or doesn't, and the next publish pins again.
        guard isFollowing, !threadScroll.userIsScrolling else { return }
        // A send from above the whole tail: every row the tail sheds is off screen below the reader,
        // and the jump below lands on the new rows (task 1c; see `ChatThreadTail.sendJump`). From
        // inside the tail nothing sheds: the rows above the reader stay as they are.
        if rowsChanged && jump.shedsTail {
            tail.shed(messages)
        }
        // A new question sent from up to a screen away eases in; from further, the jump cuts, and so
        // does a send from the end, where the held end has already brought the new rows into view.
        // Growth of the streaming answer pins without animation, so a scroll is never still in
        // flight when the user puts a finger on the thread — and not for a beat after a scroll that
        // isn't a drag has started away from the end (plan 16, task 2d; `pinsHeldOff`).
        // Nor while UIKit animates a scroll the thread didn't start (`foreignScrollIsAnimating`).
        if rowsChanged || !(threadScroll.pinsHeldOff || threadScroll.foreignScrollIsAnimating) {
            scrollToEnd(proxy, animated: rowsChanged && jump.animated)
        }
        if answerCompleted {
            // Task 1c: the reader followed the answer to its end, so the tail sheds back to its
            // budget — the last exchange and a screen and a half — and the next answer streams with
            // no more laid-out rows than this one did. The rows it sheds are above the viewport; the
            // observer holds the end through that layout pass (the reader follows, and no finger is
            // on the thread — checked above), so nothing on screen moves.
            tail.shed(messages)
            settleAtTheEnd(proxy)
        }
    }

    /// Pins the end a few more times over about 1.5 s, while the reader follows and no finger is on
    /// the thread: after an answer completes, and after a landing (a thread restored, opened or
    /// replaced). The observer's end hold keeps whatever distance from the end the viewport had, so
    /// it can't correct a landing that came to rest short; these pins do.
    ///
    /// - Final wave B: the finished answer re-renders (baked citations, actions row) and re-measures
    ///   for a few hundred ms more (on the iOS 17.0 simulator its height went 2401 → 1987 → 2182 pt
    ///   after one settle scroll).
    /// - Task 1c: once straight away, on the next turn, after that update's layout, and after a
    ///   landing too: a landing's scroll can run before the new thread has finished laying out, and
    ///   the hold keeps the distance it's given rather than seek the end (on iOS 18.5 under heavy load
    ///   a restored long thread once came to rest about 800 pt short of its end, and stayed).
    private func settleAtTheEnd(_ proxy: ScrollViewProxy) {
        Task { @MainActor in
            guard isFollowing, !threadScroll.userIsScrolling else { return }
            if !(threadScroll.pinsHeldOff || threadScroll.foreignScrollIsAnimating) { scrollToEnd(proxy) }
            try? await Task.sleep(for: .milliseconds(150))
            for _ in 0..<13 {
                guard isFollowing, !threadScroll.userIsScrolling else { return }
                if !(threadScroll.pinsHeldOff || threadScroll.foreignScrollIsAnimating) { scrollToEnd(proxy) }
                try? await Task.sleep(for: .milliseconds(100))
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
    ///
    /// Plan 16 (task 2d): under Reduce Motion the one eased jump — a send from up to a screen away —
    /// cuts too. (Read from UIKit at the call: no environment value to go stale in a view whose body
    /// never reads it.)
    private func scrollToEnd(_ proxy: ScrollViewProxy, animated: Bool = false) {
        let target = store.messages.last?.id ?? Self.threadTopID
        let anchor: UnitPoint = store.messages.isEmpty ? .top : .bottom
        if animated && !UIAccessibility.isReduceMotionEnabled {
            threadScroll.ownScrollAnimationAt = CACurrentMediaTime()
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
            ChatComposerBar(text: $input, isFocused: $inputFocused, accessibilityFocus: $accessibilityFocus,
                            isSending: store.isStreaming, onSend: sendTapped)
        }
        .padding(12)
    }

    /// L2: tap anywhere on a banner to dismiss it (same look at rest; the plain button style's
    /// press dim is the only feedback). Every banner also clears on the next send.
    ///
    /// Plan 16 (task 2d): white on DESIGN.md's `destructive` red, 5.06:1 (on the system red it was
    /// 3.55, below AA for 13 pt text); the whole message shows, wrapping at any size (it was cut at two
    /// lines); the glyph scales with the text; and the banner takes taps across at least 44 pt of
    /// height (`.stashPlain`).
    private func banner(_ text: String, identifier: String, dismiss: @escaping () -> Void) -> some View {
        Button(action: dismiss) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .accessibilityHidden(true)
                Text(text)
                Spacer(minLength: 0)
            }
            .stashFont(.meta)
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(StashColor.destructive, in: RoundedRectangle(cornerRadius: 10))
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.stashPlain)
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
        nextSendJump = classifySendJump()
        isFollowing = true
        Task { await store.send(text) }
    }

    private func retryTapped(messageId: String) {
        clearBanners()
        guard canAsk else {
            gateMessage = Self.gateCopy
            return
        }
        nextSendJump = classifySendJump()
        isFollowing = true
        Task { await store.retry(messageId: messageId) }
    }

    /// How the jump to the question about to be sent goes, from where the reader is now (task 1c,
    /// review finding I1). Read before `isFollowing` is set for the send.
    private func classifySendJump() -> ChatThreadTail.SendJump {
        let geometry = threadScroll.endGeometry
        return ChatThreadTail.sendJump(isFollowing: isFollowing,
                                       distanceFromEnd: geometry.map { Double($0.distanceFromEnd) },
                                       visibleHeight: geometry.map { Double($0.visibleHeight) },
                                       tailHeight: Double(threadScroll.tailHeight))
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
    ///
    /// Plan 16 (task 2d): `--uitest-seed-citation-ids=<linked>,<chip>` points the two sources at real
    /// items of the signed-in account (a UI test looks up permanent `UITEST-FIXTURE` items by REST),
    /// so a tap opens the real detail sheet instead of "Couldn't load that item". Without it, the ids
    /// are made up, as before.
    private func seedCitationScreenshotFixtureIfRequested() {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("--uitest-seed-citation-bubble") else { return }
        let realIds = arguments.first { $0.hasPrefix("--uitest-seed-citation-ids=") }
            .map { $0.dropFirst("--uitest-seed-citation-ids=".count).split(separator: ",").compactMap { UUID(uuidString: String($0)) } }
            ?? []
        let linkedSource = ChatSource(id: realIds.first ?? UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                                      title: "Persimmon Feeding Notes", type: "text", url: nil, n: 1)
        let extraSource = ChatSource(id: realIds.dropFirst().first ?? UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
                                     title: "Fruit Tree Almanac", type: "text", url: nil, n: nil)
        let question = ChatMessage(id: "fixture-u", role: .user,
                                   content: "What do my saved items say about persimmons?")
        let answer = ChatMessage(id: "fixture-a", role: .assistant,
                                 content: "Per [Feeding Log](#1), persimmons should be introduced gradually [1] to avoid stomach upset.",
                                 sources: [linkedSource, extraSource])
        store.seedForScreenshot([question, answer])
    }

    /// Plan 16 (task 2d): `--uitest-seed-markdown-answer` seeds a finished exchange whose answer has
    /// every block an answer can draw — a heading, a paragraph with strong and emphasised text and an
    /// inline citation, a bulleted list, a numbered list and a quote — plus one source it doesn't cite,
    /// shown as a chip: the accessibility pass's screenshots and audits look at all of them at once.
    /// The sources' ids match no item, so nothing is fetched unless one is tapped. Compiled out of
    /// Release.
    private func seedMarkdownAnswerFixtureIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("--uitest-seed-markdown-answer") else { return }
        let cited = ChatSource(id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
                               title: "Sourdough Starter Notes", type: "text", url: nil, n: 1)
        let extra = ChatSource(id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
                               title: "Bread Baking Basics", type: "link", url: nil, n: nil)
        let question = ChatMessage(id: "fixture-md-u", role: .user, content: "How do I look after my sourdough starter?")
        let answer = ChatMessage(id: "fixture-md-a", role: .assistant, content: """
            ## Feeding schedule
            Your [starter notes](#1) say to feed it **twice a day** while it lives on the counter, and *once a week* once it moves to the fridge.

            - Discard half before each feeding
            - Use equal weights of flour and water
            - A warm spot makes it rise faster

            1. Mix 50 g of flour with 50 g of water
            2. Wait four to six hours
            3. Bake with it at its peak

            > Bubbles all the way through means it's ready.
            """, sources: [cited, extra])
        store.seedForScreenshot([question, answer])
    }

    /// `--uitest-a11y-hooks` (plan 16, task 2d): scrolls the thread the way VoiceOver does — a page up,
    /// as its three-finger swipe does (UIKit's accessibility scroll on the thread's scroll view), or to
    /// the end, as moving its focus to the last answer does — neither of them a drag. For the UI tests of
    /// following after scrolls that aren't drags (task 1c review, M-6). Test scaffolding standing in for
    /// an assistive technology, never the app's own scrolling (that goes through `scrollToEnd` only).
    /// Compiled out of Release.
    private func emulateVoiceOverScroll(toEnd: Bool) {
        guard let scrollView = threadScroll.scrollView else {
            NSLog("A11YHOOK no scroll view")
            return
        }
        let insets = scrollView.adjustedContentInset
        if toEnd {
            // Not animated: an animation to an offset fixed at its start lands short when the lazy history
            // re-measures on the way (measured: 357 pt short of the end). And again until it's there, as
            // VoiceOver's scroll to the last element ends on that element: a jump to the end can make the
            // history re-measure under it (iOS 26.5: it came to rest short of the end, now and then).
            func jump(_ attempt: Int) {
                let end = max(-insets.top, scrollView.contentSize.height + insets.bottom - scrollView.bounds.height)
                guard abs(scrollView.contentOffset.y - end) > 1, attempt < 6 else { return }
                NSLog("A11YHOOK to the end (%d) from offset=%.0f end=%.0f", attempt, scrollView.contentOffset.y, end)
                scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: end), animated: false)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { jump(attempt + 1) }
            }
            jump(0)
            return
        }
        let handled = scrollView.accessibilityScroll(.up)
        NSLog("A11YHOOK accessibilityScroll(up) handled=%@ offset=%.0f", handled ? "true" : "false",
              scrollView.contentOffset.y)
        if !handled {
            // What UIKit's own accessibility scroll does (it isn't loaded while no assistive technology
            // runs): an animated page.
            let page = scrollView.bounds.height - insets.top - insets.bottom
            scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x,
                                                y: max(-insets.top, scrollView.contentOffset.y - page)),
                                        animated: true)
        }
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

/// The Ask header (plan 16, task 2d): "Chat with your Stash" and, on the right, New chat and History —
/// or, while the composer holds the keyboard, the keyboard Cancel in their place.
///
/// It never jumps when Cancel swaps in, at any text size: the right side is always as big as the
/// bigger of its two states (both sizes are reserved; only the live one is drawn), so the title beside
/// it wraps the same way whichever shows, and the row keeps its height. Cancel's 44 pt target, like the
/// circles', overhangs instead of growing the row (`StashCancelButton`), so nothing needs reserving for
/// it. At the default size the row is exactly as before: 8 + 36 + 4 pt, circles 16 pt from the edge
/// and 44 pt apart centre to centre.
///
/// At accessibility sizes the title would wrap to two or three lines in what's left beside the
/// controls, so the controls take a row of their own above it — a large-title navigation bar's
/// arrangement — and the title wraps across the whole width.
private struct AskHeader: View {
    let isComposing: Bool
    let isStreaming: Bool
    let onNewChat: () -> Void
    let onHistory: () -> Void
    let onCancel: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private static let circleSize: CGFloat = 36
    private static let circleSpacing: CGFloat = 8

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 0) {
                        Spacer(minLength: 0)
                        controls
                    }
                    title
                }
            } else {
                HStack(spacing: 8) {
                    title
                    Spacer(minLength: 0)
                    controls
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private var title: some View {
        Text("Chat with your Stash")
            .stashFont(.screenTitle)
            .foregroundStyle(StashColor.ink)
            .accessibilityAddTraits(.isHeader)
    }

    /// The circles, or Cancel, over the size of both.
    private var controls: some View {
        ZStack(alignment: .trailing) {
            // Sizing only, never drawn: the circles' row, and Cancel's word in its role
            // (`StashCancelButton`'s layout is the word alone). A ZStack takes its size from its
            // highest-priority children, and `StashCancelButton` carries `layoutPriority(1)` (for the
            // title beside it to give way first) — so these outrank it, or the stack would be just
            // Cancel's word while it shows, and the row 9 pt shorter.
            Color.clear
                .frame(width: Self.circleSize * 2 + Self.circleSpacing, height: Self.circleSize)
                .layoutPriority(2)
            Text("Cancel")
                .stashFont(.textButton)
                .lineLimit(1)
                .fixedSize()
                .hidden()
                .layoutPriority(2)
            if isComposing {
                StashCancelButton(identifier: "ask.dismissKeyboard", action: onCancel)
            } else {
                HStack(spacing: Self.circleSpacing) {
                    Button(action: onNewChat) {
                        CircleIcon(systemImage: "square.and.pencil", size: Self.circleSize)
                    }
                    .buttonStyle(.plain)
                    .disabled(isStreaming)
                    .stashIconControl("Start new chat", systemImage: "square.and.pencil")
                    .accessibilityIdentifier("ask.newChat")

                    Button(action: onHistory) {
                        CircleIcon(systemImage: "clock", size: Self.circleSize)
                    }
                    .buttonStyle(.plain)
                    .disabled(isStreaming)
                    .stashIconControl("Earlier conversations", systemImage: "clock")
                    .accessibilityIdentifier("ask.history")
                }
            }
        }
        .fixedSize()
    }
}

/// Shown while an explicitly opened old conversation is on screen (see `AskView.sessionTitlePill`).
/// Plan 16 (task 2d): violet-700 text on its violet tint (5.46:1; violet-600 was 4.41), the clock in the
/// text's role so it grows with it, and at accessibility sizes the title wraps to a second line rather
/// than being cut.
private struct AskSessionPill: View {
    let title: String

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "clock")
                    .accessibilityHidden(true)
                Text(title)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                    .truncationMode(.tail)
            }
            .stashFont(.meta)
            .foregroundStyle(StashColor.violet700)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(StashColor.violet600.opacity(0.12), in: Capsule())
            .overlay(Capsule().strokeBorder(StashColor.violet300.opacity(0.6), lineWidth: 1))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("ask.sessionPill")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 2)
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
/// Reports land on a later main-queue turn (`Coordinator.userScrolled`): the KVO callback also fires
/// when SwiftUI's OWN layout moves the content while a drag or glide is in progress — inside a view
/// update — and a report then would read a mid-layout snapshot. (Plan 15 wrote `@State` here, which
/// was the "Modifying state during view update" runtime issue; task 1c keeps following on the
/// unobserved handle, `AskThreadScrollHandle.isFollowing`.)
///
/// Plan 16 (task 1c): it also holds what the reader sees through every change of size, on every OS
/// (`Coordinator.Hold`). Why: the rows above the laid-out tail are the lazy history's estimates, and
/// whenever it builds or re-estimates one — after a landing, when the keyboard comes up, after a
/// jump, at a completion shed — everything below moves by the difference. The lazy stack keeps its
/// own visible rows still through that, but not the tail, which is outside it; and nothing kept the
/// end through the keyboard, a rotation or a text-size change. With the content's top holding still,
/// as a scroll view's does, every re-estimate moved the reader. On iOS 18.5, task 1b's restored long
/// thread came to rest 816 pt short of its end half a second after it landed; and without the tail
/// hold, a reader a little way up its last answer saw the line they were reading drop 816 pt down
/// the screen when they tapped the composer.
///
/// SwiftUI's own size-change anchor (`defaultScrollAnchor(_:for: .sizeChanges)`, iOS 18 and later)
/// can't do this job: it holds a fixed point of the viewport, so it can't keep a reader's place on
/// the tail while an answer streams below them, and switching it on and off with following means
/// reading `isFollowing` in `body` — whose re-render at the flip is itself what made the history
/// re-estimate under a drag (see `AskView.isFollowing`).
private struct AskThreadScrollObserver: UIViewRepresentable {
    /// Receives the thread's UIScrollView once found, and the reader's following.
    let handle: AskThreadScrollHandle

    func makeCoordinator() -> Coordinator { Coordinator(handle: handle) }

    func makeUIView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        // `didMoveToWindow` is when this view's full ancestor chain (up through the UIScrollView)
        // exists — see `LibraryScrollOffsetObserver` for the verification.
        view.onWindowAttach = { [weak view, weak coordinator = context.coordinator] in
            guard let view, let coordinator else { return }
            coordinator.attach(from: view)
        }
        return view
    }

    func updateUIView(_ uiView: ProbeView, context: Context) {
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
        /// What a change of size holds still for the reader. Decided from the geometry just BEFORE
        /// the change (the KVO "prior" notification), applied just after it, inside the same
        /// setter — so in the layout pass that made the change, and no frame is drawn displaced.
        /// (Deciding afterwards would read a geometry UIKit has already touched: when the content
        /// shrinks, it clamps the offset inside `setContentSize:` before the change is reported —
        /// by 316 pt in one measured pass on iOS 18.5.)
        enum Hold: Equatable {
            /// The reader follows, with no finger on the thread and the viewport at the end (within
            /// `AskThreadScrollHandle.endSlack`): the viewport keeps this distance from the content's
            /// end. A streamed update, a completion shed, the lazy history re-measuring above, the
            /// keyboard, a rotation, a text-size change: the end stays where it was on screen.
            case end(distance: CGFloat)
            /// Every row on screen is a laid-out tail row (the reader reads inside the tail, following
            /// or not, finger on the thread or not): the viewport keeps its place on the tail. It keeps
            /// this distance from the content's end, plus whatever the tail itself grew by below it, so
            /// a change above the tail (the lazy history re-measuring) moves it with the tail, and an
            /// answer streaming below the reader moves nothing.
            ///
            /// Relative to the end, never to the lazy history's own reported height: SwiftUI reports
            /// that from passes it lays out and drops in the same frame, and holding by those moved
            /// the viewport into rows that then re-estimated it back — on iOS 18.5, an oscillation of
            /// 6,000 pt every frame. The end is laid out, so the viewport's place relative to it is
            /// the same in every pass, and so is what the lazy stack builds near it.
            case tail(distance: CGFloat)
        }

        private let handle: AskThreadScrollHandle
        private var observations: [NSKeyValueObservation] = []
        /// Decided at the prior notification of a content-size or viewport-size change.
        private var contentHold: Hold?
        private var viewportHold: Hold?
        /// The tail's height as of the last content-size change (nil until the first). SwiftUI
        /// reports the tail's new height to the handle before it sets the content size that comes
        /// with it, in the same layout pass (measured on iOS 17.5, 18.5 and 26.5).
        private var tailHeight: CGFloat?
        /// Where the last hold put the viewport, and whether the reader followed then (an end hold) or
        /// not (a tail hold) — kept until this run-loop turn is over — and how many times it has been
        /// put back since (see `offsetChanged`).
        private var held: (offset: CGFloat, following: Bool)?
        private var heldRestores = 0
        private var heldExpiryScheduled = false
        /// True while the coordinator itself is setting the offset.
        private var settingOffset = false
        /// True while a report is scheduled on the main queue (see `userScrolled`).
        private var reportScheduled = false
        /// When the viewport last changed size (the keyboard, a rotation) — see `movedWithoutADrag`.
        private var viewportChangedAt: CFTimeInterval = 0
        /// Where the last tail hold aimed, unrounded (plan 16, task 2d) — see `tailDistance`.
        private var tailHoldTarget: CGFloat?
        /// Stands in for the scroll view's own delegate (SwiftUI's), to take taps on the status bar
        /// (`statusBarTapped`).
        private var statusBarDelegate: AskThreadStatusBarDelegate?
        /// Until when a status-bar cut's top is put back, and how many times it has been (`keepCutTop`).
        private var cutHeldUntil: CFTimeInterval = 0
        private var cutRestores = 0
        #if DEBUG
        private let scrollLog = AskThreadScrollLog.isEnabled ? AskThreadScrollLog() : nil
        #endif

        init(handle: AskThreadScrollHandle) {
            self.handle = handle
        }

        func attach(from view: UIView) {
            if observations.isEmpty { observe(from: view) }
            if let scrollView = handle.scrollView { takeStatusBarTaps(scrollView) }
        }

        /// Puts `AskThreadStatusBarDelegate` between the scroll view and its own delegate, once, and again if
        /// SwiftUI has since given the scroll view a delegate of its own.
        private func takeStatusBarTaps(_ scrollView: UIScrollView) {
            guard let current = scrollView.delegate, current !== statusBarDelegate,
                  !(current is AskThreadStatusBarDelegate) else { return }
            let delegate = AskThreadStatusBarDelegate(swiftUIDelegate: current, coordinator: self)
            statusBarDelegate = delegate
            scrollView.delegate = delegate
        }

        private func observe(from view: UIView) {
            var ancestor = view.superview
            while let candidate = ancestor {
                if let scrollView = candidate as? UIScrollView {
                    handle.scrollView = scrollView
                    #if DEBUG
                    scrollLog?.attach(to: scrollView.window)
                    #endif
                    observations = [
                        scrollView.observe(\.contentOffset, options: [.old]) { [weak self] scrollView, change in
                            self?.offsetChanged(scrollView, from: change.oldValue?.y)
                        },
                        scrollView.observe(\.contentSize, options: [.prior]) { [weak self] scrollView, change in
                            guard let self else { return }
                            if change.isPrior {
                                self.contentHold = self.hold(scrollView)
                            } else {
                                self.contentSizeChanged(scrollView)
                            }
                        },
                        // The viewport's size: the keyboard, a rotation. (`bounds` also changes with
                        // every scroll, as its origin; only a change of size is held.)
                        scrollView.layer.observe(\.bounds, options: [.prior, .old, .new]) { [weak self, weak scrollView] _, change in
                            guard let self, let scrollView else { return }
                            if change.isPrior {
                                self.viewportHold = self.hold(scrollView, followingOnly: true)
                            } else if change.oldValue?.size != change.newValue?.size {
                                self.viewportSizeChanged(scrollView)
                            }
                        },
                    ]
                    return
                }
                ancestor = candidate.superview
            }
        }

        /// What to hold through a change about to land, from the geometry as it stands. The end, while
        /// the reader follows at it with no finger on the thread; otherwise — for content changes only —
        /// the tail, while every row on screen is in it. A viewport that shows any lazy history row is
        /// left alone: the lazy stack keeps its own visible rows still, and a hold on top of that would
        /// move them twice. A viewport-size change is only held at the end: a reader who has scrolled
        /// away keeps their place from the top when the keyboard comes or goes, as before.
        ///
        /// Plan 16 (task 2d): nothing is held while UIKit animates a scroll the thread didn't start
        /// (`AskThreadScrollHandle.foreignScrollIsAnimating`) — a write would retarget it.
        private func hold(_ scrollView: UIScrollView, followingOnly: Bool = false) -> Hold? {
            if handle.foreignScrollIsAnimating { return nil }
            let distance = Self.distanceFromEnd(scrollView)
            if handle.isFollowing, !handle.userIsScrolling, distance < AskThreadScrollHandle.endSlack {
                return .end(distance: max(0, distance))
            }
            guard !followingOnly, let tailHeight,
                  distance + Self.visibleHeight(scrollView) <= tailHeight + 0.5 else { return nil }
            return .tail(distance: tailDistance(scrollView, measured: distance))
        }

        /// A tail hold's distance from the end, measured from where the last tail hold aimed rather than
        /// from where the viewport is, while nothing else has moved it (plan 16, task 2d). A hold's
        /// offset isn't always set exactly — UIKit puts it on the pixel grid, and `setOffset` skips a move
        /// of half a point or less — and measuring the next hold from the viewport kept what was lost.
        /// Over the history's animated re-estimate as the composer takes focus (a small growth every
        /// frame for half a second) that added up to a drop of 1–3 pt in the line being read (iOS 17.5:
        /// 4 runs of 4 with plan 16's taller answers, 1 of 5 with task 1c's).
        private func tailDistance(_ scrollView: UIScrollView, measured: CGFloat) -> CGFloat {
            guard let target = tailHoldTarget, !handle.userIsScrolling,
                  abs(scrollView.contentOffset.y - target) <= 0.5 else { return measured }
            return Self.endOffset(scrollView) - target
        }

        private func contentSizeChanged(_ scrollView: UIScrollView) {
            let newTailHeight = handle.tailHeight
            switch contentHold {
            case .end(let distance)?:
                tailHoldTarget = nil
                keepHeld(setOffset(scrollView, Self.endOffset(scrollView) - distance), following: true)
            case .tail(let distance)?:
                let tailGrowth = newTailHeight - (tailHeight ?? newTailHeight)
                let target = setOffset(scrollView, Self.endOffset(scrollView) - (distance + tailGrowth))
                tailHoldTarget = target
                keepHeld(target, following: false)
            case nil:
                tailHoldTarget = nil
                held = nil
            }
            contentHold = nil
            tailHeight = newTailHeight
        }

        private func viewportSizeChanged(_ scrollView: UIScrollView) {
            viewportChangedAt = CACurrentMediaTime()
            if case .end(let distance)? = viewportHold {
                keepHeld(setOffset(scrollView, Self.endOffset(scrollView) - distance), following: true)
            }
            viewportHold = nil
        }

        /// Every move of the offset: the user's drags and glides decide following (`userScrolled`),
        /// and a hold made this run-loop turn is put back if SwiftUI undoes it.
        ///
        /// Why put back: in an update that lays the thread out more than once (the lazy history
        /// re-estimating as the keyboard comes up, say), SwiftUI can set the offset itself after a
        /// hold, discarding it. On iOS 18.5, after UIKit had clamped the offset inside
        /// `setContentSize:` as the content shrank, SwiftUI wrote back the offset the update began
        /// with: tail holds that had kept a reader's line still through +2,990, −544 and +2,534 pt
        /// were wiped, and the line dropped 1,990 pt (1 run in 3). On iOS 26.5, right after an end hold
        /// it set an offset of its own: a restored long thread at rest at its end was left 2,637 pt
        /// short of it when the keyboard came up, every time.
        ///
        /// Put back only what a hold of the same kind would still keep, and never under a finger. A
        /// tail hold (the reader doesn't follow): any move, since then nothing else moves the offset
        /// programmatically. An end hold (the reader follows): a move up, away from the end, or past
        /// it — a follower's own jumps and pins only ever go to the end, and those stand.
        private func offsetChanged(_ scrollView: UIScrollView, from oldOffset: CGFloat?) {
            #if DEBUG
            if handle.foreignScrollIsAnimating { scrollLog?.noteAnimatedFrame() }
            #endif
            if keepCutTop(scrollView) { return }
            var putBack = false
            if !settingOffset, let held, heldRestores < 4, !handle.userIsScrolling,
               handle.isFollowing == held.following, !handle.foreignScrollIsAnimating {
                let offset = scrollView.contentOffset.y
                let lastOffset = max(-scrollView.adjustedContentInset.top, Self.endOffset(scrollView))
                let undone = held.following
                    ? offset < held.offset - 0.5 || offset > lastOffset + 0.5
                    : abs(offset - held.offset) > 0.5
                // Where the put-back would land: UIKit may have put the offset there already — as the content
                // shrinks it clamps the offset to the new end, where an end hold aimed — and then nothing was
                // undone, and nothing moved away (task 2d fix round 1, M-2: in the status-bar test's traces on
                // iOS 26.5, 51 of 52 put-backs were such no-ops, each holding the next pin off for a beat).
                let target = Self.clampedOffset(scrollView, held.offset)
                if undone, abs(offset - target) > 0.5 {
                    heldRestores += 1
                    // A move up undone under an end hold may be the first frame of a scroll that isn't
                    // a drag: the next pin waits a beat, so it can go on (see `movedWithoutADrag`).
                    if held.following, offset < target { handle.movedAwayWithoutADragAt = CACurrentMediaTime() }
                    setOffset(scrollView, held.offset)
                    putBack = true
                }
            }
            // A drag or the glide after one turns following on or off on the next turn
            // (`userScrolled`) — never a touch-down that hasn't moved, content growth or a hold. Two
            // flag reads are safe inside a layout pass.
            if scrollView.isDragging || scrollView.isDecelerating {
                userScrolled(scrollView)
            } else if !settingOffset, !putBack, let oldOffset {
                movedWithoutADrag(scrollView, from: oldOffset)
            }
        }

        /// Plan 16 (task 2d; task 1c review, M-6): a scroll that isn't a drag leaves the thread's end, or
        /// comes back to it, as a drag does. VoiceOver scrolls what it moves its focus to into view, and
        /// scrolls a page at a three-finger swipe; Switch Control, Voice Control and Full Keyboard Access
        /// scroll too — none of them a drag, so none turned following off, and the follow pins and the
        /// settle after each answer pulled the reader straight back to the end. (A tap on the status bar is
        /// the thread's own cut, which decides following itself: `statusBarTapped`.)
        ///
        /// Only two kinds of move count (task 2d fix round 1, M-3): a scroll UIKit animates that the thread
        /// didn't start (`AskThreadScrollHandle.foreignScrollIsAnimating`), and, while an assistive
        /// technology runs (`assistiveTechnologyRuns`), any move — VoiceOver's scroll to the element it
        /// moves to isn't animated. Every other move without a finger is the system's own and is never a
        /// reader's: SwiftUI setting offsets of its own after a change of size (2,681 and 3,149 pt up as the
        /// keyboard comes or goes, iOS 26.5) or landing a scroll request late, UIKit clamping the offset as
        /// the content shrinks. (Before, only a 0.4 s window after a change of the viewport's size kept those
        /// out, and one landing later would have turned following off, or on.) While an assistive technology
        /// runs, that window still guards the moves it makes without animation.
        ///
        /// Leaving is any such move AWAY from the end that starts at it (within `endSlack`) — the first
        /// frame of an animated scroll is enough, and it has to be: VoiceOver's page scroll moves a point
        /// or two in its first frames, and a pin landing before it had gone further cancelled it. Small
        /// moves count too: a VoiceOver reader moving up to the paragraph before the one streaming keeps
        /// it where it is. Of the moves that count, none of the thread's own can be taken for one:
        /// - the thread's own scrolls (`AskView.scrollToEnd`) only ever go to the end, and only while the
        ///   reader follows;
        /// - the holds are this coordinator's own writes (`settingOffset`), and SwiftUI undoing one is put
        ///   back above, first; in a turn that has made a hold (`held`), no move is taken as a reader's —
        ///   SwiftUI's own writes come in those turns (task 1c), and VoiceOver's scroll in one is put back
        ///   anyway;
        /// - a scroll that starts away from the end — the thread's first layout before its landing —
        ///   isn't leaving it.
        /// Coming back is any such move toward the end that ends within its reach. (Not just the move
        /// that crosses into it: an animated scroll's frame that lands in a turn with a tail hold is put
        /// back, and if that was the frame that crossed, the frames after it are already inside.)
        /// It's decided at once, not on the next turn as a drag is: the next streamed update would pin the
        /// reader back first. And any move away from the end while the reader follows — even one put back,
        /// or in a held turn — holds the pins off for a beat (`AskThreadScrollHandle.pinsHeldOff`): the
        /// first frame of an animated scroll can land in a held turn, and a pin before the next frame would
        /// cancel the scroll.
        private func movedWithoutADrag(_ scrollView: UIScrollView, from oldOffset: CGFloat) {
            guard !scrollView.isTracking else { return }   // a finger is down: its drag decides
            let foreign = handle.foreignScrollIsAnimating
            guard foreign || (handle.assistiveTechnologyRuns && CACurrentMediaTime() - viewportChangedAt > 0.4)
            else { return }
            let slack = AskThreadScrollHandle.endSlack
            let before = Self.endOffset(scrollView) - oldOffset
            let after = Self.distanceFromEnd(scrollView)
            // While UIKit animates a scroll the thread didn't start, nothing holds the end, so a streamed
            // update can grow the content past the end's reach before its first frame: a follower is
            // still leaving the end (iOS 17.5: 266 pt below at a status-bar tap's first frame, before the
            // thread took those taps itself).
            let fromTheEnd = before < slack || foreign
            if handle.isFollowing, fromTheEnd, after > max(before, 0) + 0.5 {
                handle.movedAwayWithoutADragAt = CACurrentMediaTime()
                if held == nil { handle.isFollowing = false }
            } else if !handle.isFollowing, after < slack, after < before {
                handle.isFollowing = true
            }
        }

        /// A tap on the status bar (plan 16, task 2d fix round 1, C-1; from `AskThreadStatusBarDelegate`): the
        /// thread cuts to its top — the content's own top, a laid-out target whatever the lazy history holds,
        /// without animation — and UIKit's animated scroll to the top never runs. That animation crosses the
        /// whole lazy history, rows it can only estimate, and on iOS 26.5, while an answer grew below it and
        /// nothing held (a foreign animation), it now and then stopped the app's main thread for minutes at its
        /// first frame, a jump of 1,700 pt into the history.
        ///
        /// The reader leaves the end as with a drag: following is decided first, from where the cut lands —
        /// off, unless the whole thread is within the end's reach — so no pin or settle pulls them back. Then:
        /// - this coordinator's own write to the top, at once (with `setContentOffset`, so a glide stops, as
        ///   UIKit's own scroll to the top stops it). Every hold this turn then decides from the top. Leaving
        ///   the jump to SwiftUI alone, the content-size change of its own layout pass found the viewport still
        ///   at the end, all tail rows, made a tail hold there, and put SwiftUI's jump back — every time, in a
        ///   stress run of 48 (SwiftUI's next pass jumped again);
        /// - SwiftUI's own scroll to the same top (`AskThreadScrollHandle.scrollToTop`), so its idea of where
        ///   the thread is agrees with the scroll view's;
        /// - and the top is held for a moment (`cutHeldUntil`): a scroll SwiftUI had in hand before the tap — a
        ///   follow pin requested just before it — lands a pass after the cut, at the old end (iOS 26.5: 1 ms and
        ///   3 ms after it, 10–11 ms after the pin; a held turn had already ended), and is put back. Not past
        ///   that moment, not under a finger, not while UIKit animates a scroll the thread didn't start, and not
        ///   once the reader follows again.
        ///
        /// Never under a finger. Returns whether the thread took the tap — not before `AskView` has handed over
        /// its scroll to the top, when UIKit's own scroll runs.
        func statusBarTapped(_ scrollView: UIScrollView) -> Bool {
            guard let scrollToTop = handle.scrollToTop else { return false }
            guard !scrollView.isTracking, !scrollView.isDragging else { return true }
            let top = -scrollView.adjustedContentInset.top
            handle.isFollowing = scrollView.contentSize.height <= Self.visibleHeight(scrollView)
                || Self.endOffset(scrollView) - top < AskThreadScrollHandle.endSlack
            held = nil
            heldRestores = 0
            tailHoldTarget = nil
            settingOffset = true
            scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: top), animated: false)
            settingOffset = false
            cutHeldUntil = CACurrentMediaTime() + Self.cutHold
            cutRestores = 0
            scrollToTop()
            #if DEBUG
            scrollLog?.noteCut()
            #endif
            return true
        }

        /// How long after a status-bar cut the top is put back if something else moves the viewport off it.
        private static let cutHold: CFTimeInterval = 0.25

        /// A status-bar cut's top, put back (see `statusBarTapped`): true when this move was undone.
        private func keepCutTop(_ scrollView: UIScrollView) -> Bool {
            guard !settingOffset, cutRestores < 4, CACurrentMediaTime() < cutHeldUntil, !handle.isFollowing,
                  !handle.userIsScrolling, !handle.foreignScrollIsAnimating else { return false }
            let top = -scrollView.adjustedContentInset.top
            guard scrollView.contentOffset.y > top + 0.5 else { return false }
            cutRestores += 1
            setOffset(scrollView, top)
            return true
        }

        /// Keeps a hold's offset for the rest of this run-loop turn (the update it was made in, and
        /// the frame it draws), then lets it go.
        private func keepHeld(_ offset: CGFloat, following: Bool) {
            held = (offset, following)
            guard !heldExpiryScheduled else { return }
            heldExpiryScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.held = nil
                self.heldRestores = 0
                self.heldExpiryScheduled = false
            }
        }

        /// Sets the offset — never above the content's top or past its end — and returns where it put
        /// it.
        @discardableResult
        private func setOffset(_ scrollView: UIScrollView, _ y: CGFloat) -> CGFloat {
            let target = Self.clampedOffset(scrollView, y)
            if abs(scrollView.contentOffset.y - target) > 0.5 {
                settingOffset = true
                scrollView.contentOffset.y = target
                settingOffset = false
            }
            return target
        }

        /// `y`, kept between the content's top and its end, as `setOffset` writes it.
        static func clampedOffset(_ scrollView: UIScrollView, _ y: CGFloat) -> CGFloat {
            let top = -scrollView.adjustedContentInset.top
            return max(top, min(y, max(top, endOffset(scrollView))))
        }

        /// The offset at which the viewport's bottom meets the content's end.
        static func endOffset(_ scrollView: UIScrollView) -> CGFloat {
            scrollView.contentSize.height + scrollView.adjustedContentInset.bottom - scrollView.bounds.height
        }

        /// How far the content's end is below the viewport's bottom (negative when the content is
        /// shorter than the viewport).
        static func distanceFromEnd(_ scrollView: UIScrollView) -> CGFloat {
            endOffset(scrollView) - scrollView.contentOffset.y
        }

        static func visibleHeight(_ scrollView: UIScrollView) -> CGFloat {
            let insets = scrollView.adjustedContentInset
            return scrollView.bounds.height - insets.top - insets.bottom
        }

        /// Records whether the thread now rests at its end, on the next main-queue turn — outside
        /// whatever layout pass may be running now. A burst of offset changes coalesces into one
        /// report, which reads the layout as it stands then rather than a mid-layout snapshot. The lag
        /// is harmless: a follow-scroll can't pin in between, because it holds off while
        /// `AskThreadScrollHandle.userIsScrolling`.
        private func userScrolled(_ scrollView: UIScrollView) {
            guard !reportScheduled else { return }
            reportScheduled = true
            DispatchQueue.main.async { [weak self, weak scrollView] in
                guard let self else { return }
                self.reportScheduled = false
                guard let scrollView else { return }
                self.handle.isFollowing = Self.isAtEnd(scrollView)
            }
        }

        /// A thread shorter than the viewport is always "at the end" (so a rubber-band pull on a
        /// short thread doesn't stop following); otherwise within `endSlack` of the last row counts.
        static func isAtEnd(_ scrollView: UIScrollView) -> Bool {
            guard scrollView.contentSize.height > visibleHeight(scrollView) else { return true }
            return distanceFromEnd(scrollView) < AskThreadScrollHandle.endSlack
        }
    }
}

/// The Ask thread's scroll state, shared by `AskView` and `AskThreadScrollObserver` and held in
/// `@State`: a weak reference to the thread's UIScrollView, so follow-scrolls can check whether the
/// user's finger — or the glide after it — is on the thread right now; whether the reader follows;
/// and the measured heights the observer's holds and a send's classification need. Unobserved:
/// writing to it never re-renders anything.
final class AskThreadScrollHandle {
    /// Within this distance of the content's end the viewport is at the end: a drag that comes to
    /// rest there keeps following, and the end hold applies.
    static let endSlack: CGFloat = 80

    weak var scrollView: UIScrollView?
    /// The reader follows the thread (see `AskView.isFollowing`).
    var isFollowing = true
    /// When a scroll that isn't a drag last moved the viewport away from the end while the reader
    /// followed (plan 16, task 2d) — VoiceOver's, say. See `pinsHeldOff`.
    var movedAwayWithoutADragAt: CFTimeInterval = 0

    /// A streamed update doesn't pin the end for a beat after such a move: the scroll is animated, and a
    /// pin cancels it. Its first frames can land in a turn whose hold puts them back, so it may not have
    /// left the end yet; a frame or two later it has, and following is off. (Sends and retries still
    /// jump.)
    var pinsHeldOff: Bool { CACurrentMediaTime() - movedAwayWithoutADragAt < 0.12 }
    /// When the thread's own eased jump last started (`AskView.scrollToEnd(_:animated: true)`).
    var ownScrollAnimationAt: CFTimeInterval = 0

    /// UIKit is animating a scroll the thread didn't start: VoiceOver's page or scroll-to-visible, Voice
    /// Control's or Full Keyboard Access's (plan 16, task 2d) — not a status-bar tap's, which the thread
    /// takes itself as a cut (`AskThreadScrollObserver.Coordinator.statusBarTapped`). While it runs, nothing
    /// holds, puts back or pins — it's let run, and where it goes decides following (`movedWithoutADrag`).
    /// A write to the offset before its first frame retargets it to that offset, and the scroll is lost: on
    /// iOS 17.5 a streamed update's end hold landed between a status-bar tap and its first frame in 4 runs
    /// of 8, and UIKit then animated to the held end for 200 ms. iOS 17.4 and later (`isScrollAnimating`);
    /// before that nothing tells, and a scroll can still be lost that way.
    var foreignScrollIsAnimating: Bool {
        guard #available(iOS 17.4, *) else { return false }
        guard let scrollView, scrollView.isScrollAnimating else { return false }
        return CACurrentMediaTime() - ownScrollAnimationAt > 0.4
    }

    /// An assistive technology that scrolls the thread without a drag runs: VoiceOver or Switch Control
    /// (plan 16, task 2d fix round 1, M-3; see `AskThreadScrollObserver.Coordinator.movedWithoutADrag`). In
    /// DEBUG, `--uitest-a11y-hooks` stands in for one, as its controls stand in for VoiceOver's scrolls.
    var assistiveTechnologyRuns: Bool {
        if UIAccessibility.isVoiceOverRunning || UIAccessibility.isSwitchControlRunning { return true }
        #if DEBUG
        return Self.standsInForAssistiveTechnology
        #else
        return false
        #endif
    }
    #if DEBUG
    private static let standsInForAssistiveTechnology = ProcessInfo.processInfo.arguments.contains("--uitest-a11y-hooks")
    #endif

    /// SwiftUI's scroll to the thread's top, set by `AskView` from inside its `ScrollViewReader`: the
    /// thread's cut when the status bar is tapped (`AskThreadScrollObserver.Coordinator.statusBarTapped`).
    var scrollToTop: (() -> Void)?
    /// The laid-out tail's height (task 1c), measured as it changes — how far above the end the
    /// tail's first row is, for the observer's tail hold and a send's classification
    /// (`ChatThreadTail.sendJump`).
    var tailHeight: CGFloat = 0

    /// A finger is on the thread or its momentum is still moving it: touch-down (`isTracking` —
    /// true a beat before `isDragging`, so a pin can't land under a finger that has only just
    /// touched), a drag, or the glide after a lift. Follow-scrolls hold off while this is true.
    /// Broader than what may turn following OFF — that is a drag or glide only
    /// (`AskThreadScrollObserver`), since a bare touch-down moves nothing.
    var userIsScrolling: Bool {
        guard let scrollView else { return false }
        return scrollView.isTracking || scrollView.isDragging || scrollView.isDecelerating
    }

    /// Where the viewport is: its bottom's distance from the content's end (never negative), and its
    /// visible height. Inside the laid-out tail the distance is exact; above it, it includes the lazy
    /// history's estimate of the rows in between, which only ever adds to it.
    var endGeometry: (distanceFromEnd: CGFloat, visibleHeight: CGFloat)? {
        guard let scrollView else { return nil }
        return (max(0, AskThreadScrollObserver.Coordinator.distanceFromEnd(scrollView)),
                AskThreadScrollObserver.Coordinator.visibleHeight(scrollView))
    }
}

/// Stands between the Ask thread's scroll view and its own delegate — SwiftUI's — and passes every message
/// on to it, except a tap on the status bar (plan 16, task 2d fix round 1, C-1): the thread takes that itself
/// (`AskThreadScrollObserver.Coordinator.statusBarTapped`), so UIKit's animated scroll to the top never runs
/// across the lazy history. SwiftUI's delegate is kept here, strongly: the scroll view only holds this one
/// weakly, and a message forwarded to a delegate that had gone would crash.
private final class AskThreadStatusBarDelegate: NSObject, UIScrollViewDelegate {
    let swiftUIDelegate: any UIScrollViewDelegate
    private weak var coordinator: AskThreadScrollObserver.Coordinator?

    init(swiftUIDelegate: any UIScrollViewDelegate, coordinator: AskThreadScrollObserver.Coordinator) {
        self.swiftUIDelegate = swiftUIDelegate
        self.coordinator = coordinator
    }

    override func responds(to aSelector: Selector!) -> Bool {
        super.responds(to: aSelector) || swiftUIDelegate.responds(to: aSelector)
    }

    override func forwardingTarget(for aSelector: Selector!) -> Any? {
        swiftUIDelegate.responds(to: aSelector) ? swiftUIDelegate : super.forwardingTarget(for: aSelector)
    }

    func scrollViewShouldScrollToTop(_ scrollView: UIScrollView) -> Bool {
        // SwiftUI's own answer first: what it won't scroll to the top isn't scrolled at all.
        if swiftUIDelegate.scrollViewShouldScrollToTop?(scrollView) == false { return false }
        guard let coordinator, coordinator.statusBarTapped(scrollView) else { return true }
        return false
    }
}

#if DEBUG
/// `--uitest-scroll-log` (UI tests only; plan 16, task 2d fix round 1): what moved the thread without a drag —
/// the frames of scrolls UIKit animated that the thread didn't start, and the status-bar taps it cut to the
/// top — as the label of an invisible element on the thread's window, `ask.debug.scrollLog`: "animated N ·
/// cut M". A UIKit view, so updating it re-renders nothing. Compiled out of Release.
private final class AskThreadScrollLog {
    static let isEnabled = ProcessInfo.processInfo.arguments.contains("--uitest-scroll-log")

    private let element: UIView = {
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = true
        view.accessibilityIdentifier = "ask.debug.scrollLog"
        return view
    }()
    private var animatedFrames = 0
    private var cuts = 0

    func attach(to window: UIWindow?) {
        guard let window, element.window !== window else { return }
        window.addSubview(element)
        update()
    }

    func noteAnimatedFrame() {
        animatedFrames += 1
        update()
    }

    func noteCut() {
        cuts += 1
        update()
    }

    private func update() {
        element.accessibilityLabel = "animated \(animatedFrames) · cut \(cuts)"
    }
}
#endif

/// Task 1c: measures bubble text as `ChatBubble` sets it (`chatBubbleText()`), for the tail's height
/// budget (`ChatThreadTail.Metrics`): the step from one line to the next, leading included, and the
/// average width of a character of prose. Hidden behind the thread; it re-measures whenever the
/// bubbles would re-lay out (text size, Bold Text). Writes to `AskThreadTail`'s unobserved fields, so
/// measuring never re-renders anything.
private struct AskBubbleTextGauge: View {
    let tail: AskThreadTail

    /// A line of plain prose, for the average character width.
    static let sample = "Here is what your saved notes and links say about it, and where they differ."

    var body: some View {
        ZStack(alignment: .topLeading) {
            Text(Self.sample)
                .chatBubbleText()
                .fixedSize()
                .onGeometryChange(for: CGSize.self) { $0.size } action: { tail.gaugeSample = $0 }
            Text("Ag\nAg\nAg")
                .chatBubbleText()
                .fixedSize()
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { tail.gaugeThreeLines = $0 }
        }
        .hidden()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Where the Ask thread's lazily built history ends and its fully laid-out tail begins (plan 16,
/// tasks 1b and 1c). The rule itself — why a tail, how big — is `ChatThreadTail` in StashKit; this
/// holds the split for the thread on screen and the measurements the rule needs.
///
/// The split is read during `body`, and set there for a new thread (keyed by its first row), so a
/// thread's first render already has it. Rows only ever move from the tail into the history, at two
/// moments, both when the rows that move are off screen:
/// - a send from above the whole tail (`ChatThreadTail.sendJump`): they're below the reader, and the
///   jump lands on the new rows;
/// - an answer completing with the reader following at its end: they're above the reader, and the
///   scroll observer holds the end through that layout pass (`AskThreadScrollObserver`). Task 1b
///   measured a one-frame flash of 1,070–1,517 pt when it shed there without the hold, so it didn't:
///   new exchanges piled up in the tail while the reader followed, and each one kept laid out added
///   about ten dropped frames to every later streamed answer.
///
/// A moved row is rebuilt and loses its own state, as a lazy row scrolled far away sometimes does
/// anyway; a given rating lives in `ChatRatings`, so it stays.
///
/// Plan 16 (task 2d): while VoiceOver or Switch Control runs, there is no lazy history — every row is
/// in the laid-out tail (`laysOutEverything`). Both move through the thread one element at a time, in
/// the order of the accessibility tree, and a lazy stack's tree holds only the rows it has built near
/// the screen, while the tail is always in it, after them. So from the last element of the last row the
/// history had built, the next was the tail's first — every row in between skipped. Measured on iOS
/// 26.5 (`A11yAskUITests`, long prose thread): with an answer's last element at the thread's bottom
/// edge, the least VoiceOver scrolls to show it, the next question wasn't built in 1 of 4 places. The
/// cost is the one the tail was bounded to avoid — every row redrawn as an answer streams — paid only
/// while one of them runs.
@Observable
final class AskThreadTail {
    /// What a line of bubble text is left with of the thread's width (`ChatBubbleLayout`): the
    /// thread's padding, an answer bubble's far-side gap and spacing, and its own padding.
    static let bubbleTextInset: CGFloat = ChatBubbleLayout.answerTextInset

    @ObservationIgnored private var threadKey: String?
    @ObservationIgnored private var historyEnd = 0
    @ObservationIgnored private var laysOutEverything = false
    /// `AskBubbleTextGauge`'s measurements: one line of sample prose, and three short lines.
    @ObservationIgnored var gaugeSample: CGSize = .zero
    @ObservationIgnored var gaugeThreeLines: CGFloat = 0
    /// The thread's size now, and the tallest it has been (so the budget isn't cut while the
    /// keyboard is up).
    @ObservationIgnored private var viewport: CGSize = .zero
    @ObservationIgnored private var tallestViewport: CGFloat = 0
    /// Bumped by `shed`, so the thread re-renders with the new split.
    private var sheds = 0

    func noteViewport(_ size: CGSize) {
        viewport = size
        tallestViewport = max(tallestViewport, size.height)
    }

    /// The budget's inputs, once the thread and the gauge have both been measured.
    var metrics: ChatThreadTail.Metrics? {
        let characters = CGFloat(AskBubbleTextGauge.sample.count)
        guard gaugeSample.width > 0, gaugeThreeLines > gaugeSample.height,
              viewport.width > Self.bubbleTextInset, tallestViewport > 0 else { return nil }
        return ChatThreadTail.Metrics(viewportHeight: Double(tallestViewport),
                                      textWidth: Double(viewport.width - Self.bubbleTextInset),
                                      lineHeight: Double((gaugeThreeLines - gaugeSample.height) / 2),
                                      characterWidth: Double(gaugeSample.width / characters))
    }

    /// How many leading rows of `messages` are lazy history. The rest are the tail, which always
    /// holds at least the last row — and every row, while `laysOutEverything` (VoiceOver or Switch
    /// Control runs; see the type doc).
    func historyCount(for messages: [ChatMessage], laysOutEverything: Bool) -> Int {
        _ = sheds
        let key = messages.first?.id
        if key != threadKey || laysOutEverything != self.laysOutEverything {
            threadKey = key
            self.laysOutEverything = laysOutEverything
            historyEnd = laysOutEverything ? 0 : ChatThreadTail.tailStart(in: messages, metrics: metrics)
        }
        // A rollback (a question that failed before its first token) can leave the split past the
        // last row. Stored back, so the next rows appended stay in the tail rather than moving
        // finished rows out of it while the reader follows (review nit N1).
        historyEnd = min(historyEnd, max(0, messages.count - 1))
        return historyEnd
    }

    /// Moves the rows the tail no longer needs into the history — only at the two moments above, and
    /// never while every row is laid out.
    func shed(_ messages: [ChatMessage]) {
        guard !laysOutEverything else { return }
        let start = ChatThreadTail.tailStart(in: messages, metrics: metrics)
        guard messages.first?.id == threadKey, start > historyEnd else { return }
        historyEnd = start
        sheds += 1
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
///
/// With `--uitest-scripted-prose` (task 1c) every answer is prose instead: three wrapping paragraphs
/// (about 550 characters) and the same closing line. A list answer is tall at any text size; prose
/// takes a height that depends on the text size and the width, as a real answer's does, which is what
/// the tail's height budget has to follow.
private struct ScriptedChatStreamer: ChatStreaming {
    var chunkInterval: Duration = .milliseconds(110)
    var prose = false

    func stream(message: String, history: [[String: String]], accessToken: String) -> AsyncThrowingStream<SSEEvent, Error> {
        if message.hasPrefix("gate:") {
            return AsyncThrowingStream { $0.finish(throwing: ChatStreamError.subscriptionRequired) }
        }
        let chunkInterval = chunkInterval
        let chunks = prose ? Self.proseChunks(for: message) : Self.answerChunks(for: message)
        return AsyncThrowingStream { continuation in
            let task = Task {
                continuation.yield(.status(.searching))
                try? await Task.sleep(for: .milliseconds(400))
                continuation.yield(.status(.reading))
                try? await Task.sleep(for: .milliseconds(400))
                for chunk in chunks {
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

    private static let proseParagraphs = [
        "Here is what your stash says about it. The notes you saved over the last few months come back to the same idea again and again, and the clearest version of it is in the longest one.",
        "Most of the links you saved agree on the basics, although two of them disagree about the details, and one of your voice memos adds a caveat that the others leave out entirely.",
        "If you want to read further, the article you saved in the spring covers the background in more depth, and the photo of the whiteboard has the outline you sketched at the time.",
    ]

    /// The prose answer, streamed a few words at a time.
    static func proseChunks(for question: String) -> [String] {
        var chunks: [String] = []
        for paragraph in proseParagraphs {
            let words = paragraph.split(separator: " ")
            stride(from: 0, to: words.count, by: 5).forEach { start in
                let end = min(start + 5, words.count)
                chunks.append(words[start..<end].joined(separator: " ") + (end < words.count ? " " : ""))
            }
            chunks.append("\n\n")
        }
        chunks.append("End of the scripted answer to: \(question)")
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
/// loaded. With `--uitest-scripted-prose` too (task 1c), their answers are the prose answer.
private struct ScriptedChatHistory: ChatHistoryStoring {
    let longThread: Bool
    var prose = false

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

    /// Questions "Long question <tag>1" … "<tag>8", each answered with the scripted list (or prose).
    private static func longMessages(tag: String, prose: Bool) -> [ChatMessage] {
        (1...8).flatMap { n -> [ChatMessage] in
            let question = "Long question \(tag)\(n)"
            let answer = prose ? ScriptedChatStreamer.proseChunks(for: question) : ScriptedChatStreamer.answerChunks(for: question)
            return [ChatMessage(id: "scripted-long-\(tag)\(n)-q", role: .user, content: question),
                    ChatMessage(id: "scripted-long-\(tag)\(n)-a", role: .assistant, content: answer.joined())]
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
        case Self.latestLongId where longThread: Self.longMessages(tag: "", prose: prose)
        case Self.listedLongId where longThread: Self.longMessages(tag: "B", prose: prose)
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
