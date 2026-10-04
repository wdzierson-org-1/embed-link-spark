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
///
/// Plan 16 (task 1d): the laid-out tail stays bounded for a reader who drags away while answers stream — it
/// sheds when they send from the end, or once a send from inside the tail has landed there — and, for one who
/// follows, sheds the exchange before a streaming answer once that answer's own exchange covers the budget. Rows
/// move a whole exchange at a time, and every shed above the reader waits until the thread has seen its holds
/// work (`ChatThreadTail.canShedAtTheEnd`). A long
/// scroll UIKit would animate across the lazy history (a keyboard's Home or End, Voice Control's "scroll to
/// top") is a cut, as the status-bar tap is. The thread's scroll machinery is `AskThreadScrolling.swift`.
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
    /// other jump cuts; a reader above the whole tail, or at the end, sheds it first, and one inside it
    /// sheds once the jump has landed (task 1d).
    @State private var nextSendJump = ChatThreadTail.SendJump.cut
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
                        Button("KB⤒") { emulateKeyboardScroll(toEnd: false) }
                            .accessibilityIdentifier("ask.debug.keyboardScrollToTop")
                        Button("KB⤓") { emulateKeyboardScroll(toEnd: true) }
                            .accessibilityIdentifier("ask.debug.keyboardScrollToEnd")
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
        #if DEBUG
        // The split, for the UI tests (task 1c review, nit N-d): a UIKit label, so this re-renders nothing.
        threadScroll.scrollLog?.noteSplit(history: historyCount, total: messages.count)
        #endif
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
                // And a long scroll UIKit would animate to the end is the thread's own jump there (task 1d).
                threadScroll.scrollToEnd = { scrollToEnd(proxy) }
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
        if rowsChanged {
            nextSendJump = .cut
            // A send that sheds nothing before its jump sheds once the jump has landed (below; task 1d).
            tail.shedOnLandingPending = jump.shedsOnLanding
        }

        if threadReplaced {
            tail.shedOnLandingPending = false
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
        // and the jump below lands on the new rows (task 1c; see `ChatThreadTail.sendJump`). A send
        // from the end (task 1d, review finding M-1): every row it sheds is above the reader, and the
        // observer holds the end through the layout pass. From inside the tail nothing sheds before
        // the jump: the rows above the reader stay as they are.
        if rowsChanged && jump.shedsTail {
            tail.shed(messages)
        }
        // Task 1d (coordinator ruling): a send that shed nothing before its jump sheds once the jump
        // has landed at the end — a streamed update or two later, the reader following there, the end
        // hold covering the layout pass, and no scroll animating (the send's own ease included) — as
        // an answer completing there does. Never on the update that adds the rows, while the reader is
        // still where they sent from.
        if !rowsChanged, tail.shedOnLandingPending, canShedAtTheEnd(landed: true) {
            tail.shedOnLandingPending = false
            tail.shed(messages)
        }
        // Task 1d (the I-1 ruling): while the answer streams with the reader following at the end, once its
        // exchange alone covers the tail's budget (`ChatThreadTail.lastExchangeCoversTheBudget`), the exchanges
        // before it shed, as they would when it completes, and the rest of it streams with only its own exchange
        // laid out and redrawn. Rows move a whole exchange at a time, so without this the exchange before stayed
        // laid out to the answer's end: 8.5 and 13.5 more dropped frames an answer than before task 1b's tail
        // (follow5, answers 3–5, iOS 18.5 and 26.5), past the ruling's 10. Once per answer: after it, the tail
        // already starts at the last question, and `AskThreadTail.shed` only ever moves the split on.
        if !rowsChanged, answerStreaming, let metrics = tail.metrics,
           ChatThreadTail.lastExchangeCoversTheBudget(in: messages, metrics: metrics), canShedAtTheEnd(landed: true) {
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
            // observer holds the end through that layout pass, so nothing on screen moves. Task 1d
            // (review finding M-2): only while that hold covers it (`canShedAtTheEnd`) — the reader at
            // the end, nothing else scrolling, and the holds seen working; without them the tail grows,
            // as task 1b's did, rather than flash.
            tail.shedOnLandingPending = false
            if canShedAtTheEnd(landed: false) { tail.shed(messages) }
            settleAtTheEnd(proxy)
        }
    }

    /// The tail may shed rows above the reader now: the end hold covers this layout pass (task 1d,
    /// `ChatThreadTail.canShedAtTheEnd`). `landed`: also no scroll of the thread animating, its own
    /// eased jump included — a send's jump that hasn't finished landing.
    private func canShedAtTheEnd(landed: Bool) -> Bool {
        ChatThreadTail.canShedAtTheEnd(
            isFollowing: isFollowing,
            isBeingScrolled: threadScroll.isBeingScrolled || (landed && threadScroll.scrollIsAnimating),
            distanceFromEnd: threadScroll.endGeometry.map { Double($0.distanceFromEnd) },
            holdsSeen: threadScroll.holdsSeen)
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
    ///
    /// Task 1d (task 2d re-review, N-2): SwiftUI lands the scroll a layout pass later, so the request is
    /// noted (`pinRequestedAt`): a status-bar cut made just after it holds its top against it.
    private func scrollToEnd(_ proxy: ScrollViewProxy, animated: Bool = false) {
        threadScroll.pinRequestedAt = CACurrentMediaTime()
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
    /// review finding I1; task 1d, M-1 and M-2). Read before `isFollowing` is set for the send.
    private func classifySendJump() -> ChatThreadTail.SendJump {
        let geometry = threadScroll.endGeometry
        return ChatThreadTail.sendJump(isFollowing: isFollowing,
                                       isBeingScrolled: threadScroll.isBeingScrolled,
                                       distanceFromEnd: geometry.map { Double($0.distanceFromEnd) },
                                       visibleHeight: geometry.map { Double($0.visibleHeight) },
                                       tailHeight: Double(threadScroll.tailHeight),
                                       holdsSeen: threadScroll.holdsSeen)
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

    /// `--uitest-a11y-hooks` (task 1d; task 2d re-review, "the unheld animated paths"): scrolls the thread the
    /// way UIKit's own keyboard scrolling does for Home or End (a hardware keyboard, or Full Keyboard Access),
    /// and Voice Control's "scroll to top" and "scroll to bottom": one animated scroll, the thread's not, all
    /// the way to its top or end — the scroll the thread cuts short (`cutLongForeignScroll`). XCUITest can
    /// drive none of those, and a scroll view takes keyboard scrolling only once it has focus. Test
    /// scaffolding, never the app's own scrolling. Compiled out of Release.
    private func emulateKeyboardScroll(toEnd: Bool) {
        guard let scrollView = threadScroll.scrollView else {
            NSLog("A11YHOOK no scroll view")
            return
        }
        let insets = scrollView.adjustedContentInset
        let y = toEnd ? max(-insets.top, scrollView.contentSize.height + insets.bottom - scrollView.bounds.height) : -insets.top
        NSLog("A11YHOOK animated scroll to the %@ from offset=%.0f to %.0f", toEnd ? "end" : "top", scrollView.contentOffset.y, y)
        scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: y), animated: true)
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
