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

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                thread
                Divider()
                composerArea
            }
            .navigationTitle("Ask Stash")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task { await store.loadHistoryOnce() }
        .onChange(of: store.errorRestoredInput) { _, restored in
            if let restored { input = restored }
        }
        .onChange(of: dictation.transcript) { _, newValue in input = newValue }
        .onDisappear { dictation.stop() }
        .sheet(item: $citationItem) { item in
            ItemDetailView(item: item, store: citationStore)
        }
    }

    // MARK: - Thread

    private var thread: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
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

    private var emptyState: some View {
        Text("Ask anything about what you've saved — or paste a link here and I'll stash it. Start a message with \u{201c}remember:\u{201d} to save a quick note.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
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
        }
        .padding(12)
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
