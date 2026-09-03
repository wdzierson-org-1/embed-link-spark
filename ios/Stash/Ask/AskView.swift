import SwiftUI
import Observation
import StashKit
import Supabase
import AVFoundation

/// The Ask tab: streaming Q&A over the user's stash (`ChatStore`, Task 2), with citation chips
/// that open the existing read-only detail sheet, capture-as-chat (`.saved` chips), dictation,
/// and read-aloud. Prose-specified per plan-1/2 precedent — the state machine underneath is
/// already tested (`ChatStoreTests`); this view is what renders it.
struct AskView: View {
    let userId: UUID

    @Environment(SubscriptionStore.self) private var subscription

    @State private var store: ChatStore
    @State private var input = ""
    @State private var dictation = DictationController()
    /// The composer's content at the instant dictation last started — captured once per
    /// start/restart so every interim update re-merges against the SAME unchanging prefix (see
    /// `mergeDictation`). Without this, restarting dictation (redo) or dictating after already
    /// typing something loses that text the moment `DictationController.start()` resets
    /// `transcript` to "" (task review finding: the field went blank instantly on a second tap).
    @State private var dictationPrefix = ""
    @State private var speech = SpeechReader()
    @State private var gateMessage: String?
    @State private var citationItem: Item?
    @State private var loadingSourceId: UUID?
    @State private var citationErrorMessage: String?
    @State private var lastMessageCount = 0
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
            capture: CaptureAPI(),
            accessToken: { try await StashClient.shared.auth.session.accessToken }
        ))
        _citationStore = State(initialValue: ItemStore(userId: userId, fetcher: SupabaseItemsFetcher()))
    }

    @State private var showConversations = false
    @State private var itemCount: Int?

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
            // Registered-but-hidden: `askHeader` is this tab's real header (per DESIGN.md parity
            // with ChatMole.tsx it carries its own "Ask Stash" title, not the shared wordmark),
            // but the nav title still feeds the pushed Conversations screen's back button ("‹ Ask").
            .navigationTitle("Ask")
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $showConversations) {
                ConversationsListView(store: store)
            }
        }
        // Fires on tab switch only (pushing Conversations keeps this NavigationStack on
        // screen): the iOS analog of collapsing the web mole — an explicitly loaded old
        // conversation is let go, restorable via the banner.
        .onDisappear { store.letGoIfExplicit() }
        .task { await store.loadHistoryOnce() }
        .task { await loadItemCountOnce() }
        .onChange(of: store.errorRestoredInput) { _, restored in
            if let restored { input = restored }
        }
        // Ordered before the transcript mirror below: both fire from the same transaction when
        // `start()` resets `transcript` to "" and flips `isListening` true together, and the
        // prefix must already be captured by the time the transcript handler re-merges.
        .onChange(of: dictation.isListening) { _, isListening in
            if isListening { dictationPrefix = input }
        }
        .onChange(of: dictation.transcript) { _, newValue in
            guard dictation.isListening else { return }
            input = mergeDictation(prefix: dictationPrefix, interim: newValue)
        }
        .onDisappear { dictation.stop() }
        .sheet(item: $citationItem) { item in
            ItemDetailView(item: item, store: citationStore)
        }
    }

    // MARK: - Header

    /// Web's Ask panel header (`ChatMole.tsx`'s "Ask Stash" / "Answers from your N items") — this
    /// tab drops the shared wordmark (`StashHeader`) for its own panel title, matching that
    /// layout. The two former header circle-icon actions (new chat / history) now live in
    /// `footerLinks`, under the composer — Will couldn't find the history affordance up here.
    private var askHeader: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Ask Stash")
                .font(askTitleFont)
                .stashTracking(-0.02, size: 22)
                .foregroundStyle(StashColor.ink)
            if let itemCount {
                Text("Answers from your \(itemCount) item\(itemCount == 1 ? "" : "s")")
                    .font(StashType.meta())
                    .foregroundStyle(StashColor.muted)
                    .accessibilityIdentifier("ask.itemCount")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    /// `StashType.panelTitle()` is fixed at DESIGN.md's 28pt "Object title (panel)" size; this
    /// header wants the same PP Neue Montreal Medium face at the brief's smaller 22pt, so this
    /// mirrors `panelTitle()`'s availability check at that one different size rather than adding
    /// a size parameter to the shared token (out of this task's file scope).
    private var askTitleFont: Font {
        StashType.isNeueMontrealAvailable
            ? .custom("PPNeueMontreal-Medium", size: 22)
            : .system(size: 22, weight: .medium)
    }

    /// Cheapest correct source for the header subtitle's item count: a HEAD request with
    /// `count: .exact` on `items` (no rows fetched, just the count) — cached for this view's
    /// lifetime (kept alive for the whole app session by `MainTabView`'s `TabView`, so this only
    /// ever runs once per launch). Left `nil` (subtitle omitted) on any failure — this is
    /// decoration, never worth surfacing an error banner over.
    private func loadItemCountOnce() async {
        guard itemCount == nil else { return }
        do {
            let response = try await StashClient.shared.from("items")
                .select("id", head: true, count: .exact)
                .eq("user_id", value: userId.uuidString)
                .execute()
            itemCount = response.count
        } catch {
            // Left nil — see doc comment.
        }
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
                .font(.caption)
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
                        .font(.footnote)
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
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    restoreBanner
                    if store.messages.isEmpty {
                        emptyState
                    }
                    ForEach(Array(store.messages.enumerated()), id: \.element.id) { index, message in
                        ChatBubble(
                            message: message,
                            index: index,
                            question: precedingQuestion(before: index),
                            userId: userId,
                            loadingSourceId: loadingSourceId,
                            speech: speech,
                            isDictating: dictation.isListening,
                            onCitationTap: openCitation
                        )
                        .id(message.id)
                    }
                    Color.clear.frame(height: 1).id(Self.bottomAnchorID)
                }
                .padding(.horizontal)
                .padding(.top, 12)
                .padding(.bottom, 4)
            }
            .accessibilityIdentifier("ask.thread")
            .onChange(of: store.messages) { _, _ in handleMessagesChanged(proxy) }
            .task {
                // Lets the initial history restore (if any) actually lay out before jumping —
                // an immediate scrollTo on a still-empty/measuring scroll view is a no-op.
                try? await Task.sleep(for: .milliseconds(50))
                proxy.scrollTo(Self.bottomAnchorID, anchor: .bottom)
            }
        }
    }

    /// Web's welcome bubble copy, verbatim (`ChatMole.tsx:494`). The iOS-only capture hint
    /// ("paste a link… / 'remember:' to save") lives solely on the composer's placeholder now —
    /// this bubble no longer duplicates it.
    private var emptyState: some View {
        Text("Ask anything about what you've saved — answers cite the cards they came from.")
            .font(.subheadline)
            .foregroundStyle(StashColor.muted)
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    /// Always scrolls on a message-COUNT change (a new bubble appended — user turn, assistant
    /// placeholder, saved chip); throttled to at most once per ~0.3s otherwise (a content-only
    /// mutation, i.e. streaming deltas landing on the same bubble), so a fast token stream doesn't
    /// fire a `scrollTo` on every delta.
    private func handleMessagesChanged(_ proxy: ScrollViewProxy) {
        let now = Date()
        let countChanged = store.messages.count != lastMessageCount
        lastMessageCount = store.messages.count
        guard countChanged || now.timeIntervalSince(lastScrollTime) > 0.3 else { return }
        lastScrollTime = now
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo(Self.bottomAnchorID, anchor: .bottom)
        }
    }

    /// The nearest preceding `.user` message's text — see `ChatBubble.question`'s doc comment.
    private func precedingQuestion(before index: Int) -> String {
        guard index > 0 else { return "" }
        for i in stride(from: index - 1, through: 0, by: -1) where store.messages[i].role == .user {
            return store.messages[i].content
        }
        return ""
    }

    // MARK: - Composer

    private var composerArea: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let errorMessage = store.errorMessage {
                banner(errorMessage, identifier: "ask.error")
            }
            if let gateMessage {
                banner(gateMessage, identifier: "ask.gateError")
            }
            if let citationErrorMessage {
                banner(citationErrorMessage, identifier: "ask.citationError")
            }
            if dictation.isListening {
                Text("Listening…")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            ChatComposerBar(text: $input, isSending: store.isStreaming, dictation: dictation, onSend: sendTapped)
            footerLinks
        }
        .padding(12)
    }

    /// Web's footer links (`ChatMole.tsx:655-673`, "Start new chat · Earlier conversations") —
    /// replaces the two header circle icons (Will couldn't find the history affordance up there).
    /// Same accessibility identifiers as before (`ask.newChat`/`ask.history`), so
    /// `testConversationsSmoke`'s navigation keeps working unchanged.
    private var footerLinks: some View {
        HStack(spacing: 6) {
            Button("Start new chat") { store.startNewChat() }
                .accessibilityIdentifier("ask.newChat")
            Text("·")
            Button("Earlier conversations") { showConversations = true }
                .accessibilityIdentifier("ask.history")
        }
        .buttonStyle(.plain)
        .font(StashType.meta())
        .foregroundStyle(StashColor.muted)
        .padding(.top, 2)
    }

    private func banner(_ text: String, identifier: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").imageScale(.small)
            Text(text).font(.footnote).lineLimit(2)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.red, in: RoundedRectangle(cornerRadius: 10))
        .accessibilityIdentifier(identifier)
    }

    /// Web toast copy, verbatim (ChatMole.tsx's `ask`/`saveUrl`/`saveNote` gate branches).
    private func sendTapped() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        switch classifyMessage(text) {
        case .ask:
            guard subscription.canUseAI else {
                gateMessage = "AI chat needs an active trial or subscription."
                return
            }
        case .saveURL, .saveNote:
            guard subscription.canAddContent else {
                gateMessage = "Subscribe to add new items."
                return
            }
        }
        gateMessage = nil
        input = ""
        Task { await store.send(text) }
    }

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
/// "active" at a time. `didFinish` clears `speakingId` for natural completion; a user-initiated
/// stop (the same bubble tapped again, or a different bubble started) clears/reassigns it
/// synchronously inside `toggle` itself, so the two paths never race — see the note on
/// `didCancel` below.
@MainActor
@Observable
final class SpeechReader: NSObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private(set) var speakingId: String?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func toggle(id: String, text: String) {
        if speakingId == id {
            synthesizer.stopSpeaking(at: .immediate)
            speakingId = nil
            return
        }
        synthesizer.stopSpeaking(at: .immediate)
        speakingId = id
        synthesizer.speak(AVSpeechUtterance(string: text))
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.speakingId = nil }
    }

    // No-op: `toggle()` already updates `speakingId` synchronously for every user-initiated stop
    // (same-bubble re-tap, or switching to a different bubble) before this can ever fire —
    // clearing it here too would risk an async callback for utterance A racing a synchronous
    // reassignment to bubble B's id that already happened.
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {}
}
