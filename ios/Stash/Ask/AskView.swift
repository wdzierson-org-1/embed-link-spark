import SwiftUI
import Observation
import StashKit
import AVFoundation

/// The Ask tab: streaming Q&A over the user's stash (`ChatStore`), with citation links/chips that
/// open the existing read-only detail sheet, and read-aloud. Retrieval-only (plan 15, M11): every
/// message is a question — capture belongs to the Add tab and the share sheet, as on the web.
///
/// Plan 15 tune-up: while an answer streams the session can't be switched out from under it (new
/// chat / history are disabled; leaving the tab defers the let-go until the answer lands — see
/// `ChatStore`), the thread only follows the stream while the reader is at the bottom or just
/// sent (M2), drags dismiss the keyboard (L10), and error banners clear on the next send and on
/// tap (L2).
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

    // Thread-follow state (M2).
    /// The visible rect's bottom edge is within a short distance of the content's end.
    @State private var isNearBottom = true
    /// The user just sent (or retried): follow the next appended rows even if scrolled up.
    @State private var followOnNextChange = false
    @State private var threadVisible = false
    /// The thread was replaced while off screen (e.g. a conversation opened from the pushed
    /// Conversations list) — land at its end when it's next shown. True for the first appearance.
    @State private var jumpToBottomOnAppear = true
    @State private var lastMessageCount = 0
    @State private var lastFirstMessageId: String?
    @State private var lastScrollTime = Date.distantPast

    /// Exists purely to satisfy `ItemDetailView`'s init — citation sheets are read-only here (per
    /// the brief), so this store's own `items`/save plumbing is never read by anything else; it
    /// is intentionally not shared with the View tab's `ItemStore`.
    @State private var citationStore: ItemStore

    private static let bottomAnchorID = "ask-bottom"

    init(userId: UUID) {
        self.userId = userId
        _store = State(initialValue: ChatStore(
            userId: userId,
            streamer: LiveChatStreamer(),
            history: SupabaseChatHistory(),
            accessToken: { try await StashClient.shared.auth.session.accessToken }
        ))
        _citationStore = State(initialValue: ItemStore(userId: userId, fetcher: SupabaseItemsFetcher()))
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
        // let-go until the answer lands; coming back first cancels it.
        .onAppear { store.cancelPendingLetGo() }
        .onDisappear { store.letGoIfExplicit() }
        .task {
            await store.loadHistoryOnce()
            #if DEBUG
            seedCitationScreenshotFixtureIfRequested()
            #endif
        }
        .onChange(of: store.errorRestoredInput) { _, restored in
            if let restored { input = restored }
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
    private var askHeader: some View {
        HStack(spacing: 8) {
            Text("Chat with your Stash")
                .font(StashType.medium(size: 22))
                .foregroundStyle(StashColor.ink)
            Spacer()
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
                showConversations = true
            } label: {
                CircleIcon(systemImage: "clock", size: 36)
            }
            .buttonStyle(.plain)
            .disabled(store.isStreaming)
            .accessibilityLabel("Earlier conversations")
            .accessibilityIdentifier("ask.history")
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 4)
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
    @ViewBuilder private var restoreBanner: some View {
        if store.messages.isEmpty, let previous = store.lastLoaded {
            Button {
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
            .accessibilityIdentifier("ask.restoreBanner")
        }
    }

    // MARK: - Thread

    private var thread: some View {
        let messages = store.messages
        let questions = Self.precedingQuestions(in: messages)
        let lastIndex = messages.indices.last
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    restoreBanner
                    if messages.isEmpty {
                        emptyState
                    }
                    ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                        // `.equatable()` (plan 15, M1): SwiftUI compares bubbles with
                        // `ChatBubble.==`, so a streaming delta re-renders only the answer it
                        // changed. `loadingSourceId` is passed only to the bubble that owns that
                        // source, for the same reason.
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
                        .id(message.id)
                    }
                    Color.clear.frame(height: 1).id(Self.bottomAnchorID)
                }
                .padding(.horizontal)
                .padding(.top, 12)
                .padding(.bottom, 4)
                // M2: track "is the reader at the bottom?" — only flips are delivered, so this
                // costs nothing while scrolling within the middle of a long thread.
                .onGeometryChange(for: Bool.self) { geometry in
                    guard let visible = geometry.bounds(of: .scrollView) else { return true }
                    // Within 80pt of the end still counts as "reading the latest".
                    return geometry.size.height - visible.maxY < 80
                } action: { nearBottom in
                    isNearBottom = nearBottom
                }
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
                proxy.scrollTo(Self.bottomAnchorID, anchor: .bottom)
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

    /// M2: follow the conversation only when the reader is already at the bottom, or just sent.
    /// A replaced thread (history restored, conversation opened, new chat) lands at its end.
    /// Content-only changes (the streaming answer growing, ≤10 Hz after `ChatStore`'s
    /// coalescing) scroll at most every ~0.3s.
    private func followThread(_ messages: [ChatMessage], proxy: ScrollViewProxy) {
        let firstId = messages.first?.id
        let threadReplaced = firstId != lastFirstMessageId
        lastFirstMessageId = firstId
        let countChanged = messages.count != lastMessageCount
        lastMessageCount = messages.count

        if threadReplaced {
            followOnNextChange = false
            if threadVisible {
                proxy.scrollTo(Self.bottomAnchorID, anchor: .bottom)
                lastScrollTime = Date()
            } else {
                jumpToBottomOnAppear = true
            }
            return
        }
        let justSent = followOnNextChange && countChanged
        if justSent { followOnNextChange = false }
        guard justSent || isNearBottom else { return }
        let now = Date()
        guard countChanged || now.timeIntervalSince(lastScrollTime) > 0.3 else { return }
        lastScrollTime = now
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo(Self.bottomAnchorID, anchor: .bottom)
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
            ChatComposerBar(text: $input, isSending: store.isStreaming, onSend: sendTapped)
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

    /// Web toast copy, verbatim (ChatMole.tsx `ask()`'s gate branch).
    private func sendTapped() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        clearBanners()
        guard subscription.canUseAI else {
            gateMessage = "AI chat needs an active trial or subscription."
            return
        }
        input = ""
        followOnNextChange = true
        Task { await store.send(text) }
    }

    private func retryTapped(messageId: String) {
        clearBanners()
        guard subscription.canUseAI else {
            gateMessage = "AI chat needs an active trial or subscription."
            return
        }
        followOnNextChange = true
        Task { await store.retry(messageId: messageId) }
    }

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

    private func openCitation(_ id: UUID) {
        guard loadingSourceId == nil else { return }
        loadingSourceId = id
        citationErrorMessage = nil
        Task {
            defer { loadingSourceId = nil }
            do {
                citationItem = try await SupabaseItemsFetcher().fetchDetail(id: id)
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
///   category was set before.
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
