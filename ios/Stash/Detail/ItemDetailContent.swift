import SwiftUI
import StashKit

/// Where the sheet's `page_body` read stands (plan 15, M5/L6).
enum DetailSourceLoad: Equatable {
    /// Not read by the sheet — the row arrived with `page_body`, or nothing has started yet.
    case idle
    case loading
    /// Read; whatever `item.pageBody` holds now is what the server has.
    case loaded
    case failed
}

/// The content section: DESIGN.md's panel-section grammar (uppercase micro-label — "NOTES &
/// SUMMARY" / "NOTES & TRANSCRIPT" / "NOTES" per `contentTabsConfig(for:).title` — over a
/// hairline rule) with `PillTabs` alongside it when the type has more than one tab, then the
/// active tab's body. `.summary`/`.original`/`.transcript` render through `MarkdownBlocksView`
/// when `MarkdownBlocks.looksLikeMarkdown` says the text is worth parsing as markdown, else plain
/// body text — port of the web's `EditItemContentSection.tsx` `ReadOnlyText`/`looksLikeMarkdown`
/// split. `.notes` (Plan 8 Task 5) hands off entirely to `NotesEditor`, which owns both the
/// read-only TipTap render (rich notes) and the inline autosaving field (plain notes fully, rich
/// notes as an append draft) — no separate composer alongside it anymore.
///
/// Legacy `Attachments` section (Task 8): `collection`-type items predate the single-object model
/// (Global Constraints: never created going forward) and carry no `content`/notes of their own
/// worth writing to — `contentTabsConfig(for: .collection)` still resolves to the generic
/// single-"Notes"-tab default, so this section renders directly below that tab's body, reusing
/// `CollectionStrip` (Task 7) read-only exactly as the card grid does. Gated strictly to
/// `.collection` — every other type has no `item_attachments` rows to show.
struct ItemDetailContent: View {
    let item: Item
    @Binding var selectedTab: ContentTabKey
    /// The sheet's `page_body` read (M5: only the source tabs wait on it — a summary is a list
    /// column and shows at once; L6: a failed read says so, with a retry).
    let sourceLoad: DetailSourceLoad
    var onRetryDetail: () -> Void
    let notesModel: NotesEditorModel
    var notesFocused: FocusState<DetailField?>.Binding
    var scheduleNotesFlush: () -> Void
    var flushNotesNow: () async -> Void
    /// Plan 14 Task 2 ("Transcribe with speakers") — all three owned/driven by `ItemDetailView`
    /// (same "the view that already talks to the network owns the state" split every other save
    /// site here follows): `isTranscribing` disables the button and swaps its label (also while
    /// the server's own job for the item runs — final wave B), `transcriptionErrorMessage` renders
    /// inline under this section's header on failure (the transcript shown is always the server's
    /// — this is purely a display concern), and `onTranscribeWithSpeakers` is the trigger
    /// `ItemDetailView.retranscribe()` hands down.
    let isTranscribing: Bool
    let transcriptionErrorMessage: String?
    var onTranscribeWithSpeakers: () -> Void
    /// "Generate summary" (plan 15) — owned by `ItemDetailView`, like the transcription trigger.
    let isGeneratingSummary: Bool
    let summaryErrorMessage: String?
    var onGenerateSummary: () -> Void

    #if DEBUG
    /// `--uitest-detail-busy-on-tap` (UI tests only, compiled out of Release): a tap on "Transcribe
    /// again" or "Generate summary" turns it busy (its progress label) and keeps it busy, with no job
    /// behind it. So a test can watch the idle → busy swap and sample the busy label's pixels (2b
    /// review M-2, recipe R-2). A real `summarize-content` call answers, or fails, within about a
    /// frame.
    private static let busyOnTap = ProcessInfo.processInfo.arguments.contains("--uitest-detail-busy-on-tap")
    @State private var uitestBusyActions: Set<String> = []
    #endif

    /// DEBUG: whether `--uitest-detail-busy-on-tap` has turned the inline action `identifier` busy.
    private func uitestShowsBusy(_ identifier: String) -> Bool {
        #if DEBUG
        return uitestBusyActions.contains(identifier)
        #else
        return false
        #endif
    }

    /// What an inline action's tap runs: its own action, or (DEBUG, `--uitest-detail-busy-on-tap`)
    /// a stand-in that only marks it busy.
    private func uitestAction(_ identifier: String, _ action: @escaping () -> Void) -> () -> Void {
        #if DEBUG
        if Self.busyOnTap { return { _ = uitestBusyActions.insert(identifier) } }
        #endif
        return action
    }

    private var config: ContentTabsConfig { contentTabsConfig(for: item.type) }
    private var tabs: [ContentTab] { config.tabs.filter { $0.key != .notes } }
    /// Audio/video items with a stored media file only (web parity: `EditItemContentSection.tsx`
    /// passes `item.file_path` straight through to `TranscriptContent`, which itself gates its
    /// button on that prop being present) — a `.link`/`.text`/etc. item, or an audio/video row
    /// that somehow has no `file_path` (shouldn't happen in practice, but nothing to rebuild from
    /// either way), never shows this affordance.
    private var showsTranscribeButton: Bool {
        (item.type == .audio || item.type == .video) && !(item.filePath ?? "").isEmpty
    }

    var body: some View {
        // Outer spacing 0 — `sectionHead` is a `SectionHeader`, which already carries its own
        // top/bottom rhythm (`DetailLayout.section`/`.gap`); a nonzero outer spacing here would
        // double-count on top of that. `DetailLayout.gap` moves down onto the inner group instead,
        // unchanged in value from this VStack's own spacing before this fix round.
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "Notes")
                .accessibilityIdentifier("detail.notes.heading")
            NotesEditor(item: item, model: notesModel, isFocused: notesFocused,
                        scheduleFlush: scheduleNotesFlush, flushNow: flushNotesNow)
            if !tabs.isEmpty { sectionHead }
            if showsTranscribeButton, let transcriptionErrorMessage, !transcriptionErrorMessage.isEmpty {
                Text(transcriptionErrorMessage)
                    .stashFont(.meta)
                    .foregroundStyle(StashColor.destructive)
                    .padding(.bottom, DetailLayout.gap)
                    .accessibilityIdentifier("detail.transcribeSpeakers.error")
            }

            VStack(alignment: .leading, spacing: DetailLayout.gap) {
                if let first = tabs.first {
                    tabBody(for: selectedTab == .notes ? first.key : selectedTab)
                }

                if item.type == .collection {
                    attachmentsSection
                }
            }
        }
    }

    /// `SectionHeader`'s `accessory` slot (own full-width line below the label, above the rule) —
    /// not `trailing` (inline with the label) — is what `PillTabs` needs here; see that type's own
    /// doc comment for why (three tabs wrapped mid-word at 393pt when squeezed onto the label's
    /// row, confirmed live pre-dating this fix round).
    ///
    /// `trailing` used to carry this section's own hide-keyboard control (plan 12 feedback round
    /// 3, Task 1). Final wave (F7, whole-branch review): moved to `ItemDetailView.footerBar`
    /// instead — the notes header sits roughly 400pt below the title/description fields on a
    /// typical item, so a control there was a long reach back down to it when the FIELD being
    /// dismissed was the title/description, not notes. The footer is pinned and always on
    /// screen regardless of scroll position, so it's reachable no matter which of the three
    /// fields is focused. `trailing` is empty now — kept as a named slot (not deleted) in case a
    /// future section-local control needs it.
    private var sectionHead: some View {
        SectionHeader(title: config.title, trailing: {
            // Plan 14 Task 2: this used to be an always-empty named slot (see the doc comment
            // above on why it was retired, not deleted, in an earlier round) — "Transcribe with
            // speakers" is the first control to actually need it. Audio/video's `contentTabsConfig`
            // never has more than one tab, so this and `accessory`'s `PillTabs` never compete for
            // the same header.
            if showsTranscribeButton {
                transcribeButton
            }
        }, accessory: {
            if tabs.count > 1 {
                let pillItems = tabs.map { PillTabs<ContentTabKey>.Item($0.key, label: $0.label) }
                PillTabs(items: pillItems, selection: $selectedTab)
                    .accessibilityIdentifier("detail.tabs")
            }
        })
    }

    /// Text button (DESIGN.md's "muted text + glyph" affordance family, same spirit as the card's
    /// "Add a note") — mirrors the web's `TranscriptContent.tsx` outline button 1:1 in behavior,
    /// just native's own plain-text-button chrome rather than a bordered pill: busy disables the
    /// button and swaps the label to "Transcribing…" with a small spinner alongside it. The copy
    /// never claimed real speaker identities and no longer mentions speakers at all: as of
    /// 2026-09-29 the server does not diarize, so the button only promises a rebuild.
    ///
    /// Plan 16: an inline action — `inlineButton` (Medium 15) with a 44 pt target (`InlineActionStyle`).
    /// Busy, its label is the progress ("Transcribing…"), which people read: `busyInlineAction`.
    private var transcribeButton: some View {
        // Identifier deliberately unchanged: stable UI-test contract. A mild misnomer
        // since the server no longer diarizes — renaming churns StashUITests for no user benefit.
        busyInlineAction("Transcribe again", busy: "Transcribing…", isBusy: isTranscribing,
                         identifier: "detail.transcribeSpeakers", action: onTranscribeWithSpeakers)
    }

    /// An inline action that turns into its own progress while it runs: "Transcribe again" →
    /// "Transcribing…", "Generate summary" → "Generating summary…" with a small spinner.
    /// - Idle: violet-600 `inlineButton` text with a 44 pt target.
    /// - Busy: the same button, disabled, so VoiceOver hears "…, dimmed, button". It is drawn as
    ///   is, in `muted` (5.38:1). `.plain` would dim a disabled label to half (#b1b5ba, 2.06:1;
    ///   2b review M-2), and this label is the progress people need to read.
    /// - ONE `Button` in one style for both states; only its label changes. Two buttons in an
    ///   `if` were two views, so turning busy replaced the control VoiceOver's cursor was on (2bf
    ///   review m1). It keeps its place and identifier.
    private func busyInlineAction(_ title: String, busy busyTitle: String, isBusy: Bool, identifier: String,
                                  action: @escaping () -> Void) -> some View {
        let busy = isBusy || uitestShowsBusy(identifier)
        return Button(action: uitestAction(identifier, action)) {
            HStack(spacing: 6) {
                if busy {
                    ProgressView()
                        .controlSize(.mini)
                }
                Text(busy ? busyTitle : title)
                    .stashFont(.inlineButton)
            }
        }
        .buttonStyle(InlineActionStyle())
        .foregroundStyle(busy ? StashColor.muted : StashColor.violet600)
        .disabled(busy)
        .accessibilityIdentifier(identifier)
    }

    private var attachmentsSection: some View {
        VStack(alignment: .leading, spacing: DetailLayout.tight) {
            Text("Attachments")
                .stashMicroLabel()
                .accessibilityAddTraits(.isHeader)
            CollectionStrip(itemId: item.id)
        }
        .accessibilityIdentifier("detail.attachments")
    }

    @ViewBuilder private func tabBody(for tab: ContentTabKey) -> some View {
        switch tab {
        case .summary:
            summaryBody
        case .original:
            sourceBody(empty: "Nothing captured yet", id: "detail.originalText")
        case .transcript:
            // A job that ended `failed` (incl. `no_speech`) says so — the header's "Transcribe with
            // speakers" is the retry — instead of "Transcription in progress…" forever.
            sourceBody(empty: ItemDisplay.emptyTranscriptText(for: item), id: "detail.transcriptText")
        case .notes:
            NotesEditor(item: item, model: notesModel, isFocused: notesFocused,
                        scheduleFlush: scheduleNotesFlush, flushNow: flushNotesNow)
        }
    }

    /// Original/Transcript — the tabs that actually wait on `page_body`.
    @ViewBuilder private func sourceBody(empty: String, id: String) -> some View {
        if let text = item.pageBody, !text.isEmpty {
            readOnlyBlock(text, empty: empty, id: id)
        } else if sourceLoad == .loading {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 120)
                .accessibilityIdentifier("detail.loadingSource")
        } else if sourceLoad == .failed {
            loadFailedState(id: id)
        } else {
            readOnlyBlock(nil, empty: empty, id: id)
        }
    }

    private var isDocument: Bool { item.type == .document }
    private var noSummaryYet: String { "No summary yet for this \(isDocument ? "document" : "link")." }

    /// M5: a summary is a list column, so it's on screen the moment the sheet opens — never behind
    /// the `page_body` spinner. An empty one offers "Generate summary" (web parity,
    /// `EditItemContentSection.tsx`, same copy) once the item's captured text is known to exist.
    @ViewBuilder private var summaryBody: some View {
        if let summary = item.summary, !summary.isEmpty {
            readOnlyBlock(summary, empty: "", id: "detail.summaryText")
        } else if let pageBody = item.pageBody, !pageBody.isEmpty {
            VStack(alignment: .leading, spacing: DetailLayout.tight) {
                emptyText(noSummaryYet, id: "detail.summaryText")
                generateSummaryButton
                if let summaryErrorMessage {
                    Text(summaryErrorMessage)
                        .stashFont(.meta)
                        .foregroundStyle(StashColor.destructive)
                        .accessibilityIdentifier("detail.generateSummary.error")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            switch sourceLoad {
            case .failed:
                loadFailedState(id: "detail.summaryText")
            case .loaded:
                emptyText(isDocument ? "Content is still being extracted from this document."
                                     : "We haven't been able to read this page's content yet.",
                          id: "detail.summaryText")
            case .idle, .loading:
                emptyText(noSummaryYet, id: "detail.summaryText")
            }
        }
    }

    /// Same text-button treatment as "Transcribe with speakers": busy disables it and swaps the
    /// label (an action keeps its name through the flow — DESIGN.md §Voice). Plan 16:
    /// `busyInlineAction` — busy, its progress label stays readable.
    private var generateSummaryButton: some View {
        busyInlineAction("Generate summary", busy: "Generating summary…", isBusy: isGeneratingSummary,
                         identifier: "detail.generateSummary", action: onGenerateSummary)
    }

    /// L6: the `page_body` fetch failed — say so, with a retry, instead of empty-state copy that
    /// reads as "there's nothing here". Existing empty-state text styles; the retry is the same
    /// text-button treatment as the section's other actions.
    private func loadFailedState(id: String) -> some View {
        VStack(alignment: .leading, spacing: DetailLayout.tight) {
            emptyText("Couldn't load this content.", id: id)
            Button {
                onRetryDetail()
            } label: {
                Text("Try again")
                    .stashFont(.inlineButton)
            }
            .buttonStyle(.stashPlain)
            .foregroundStyle(StashColor.violet600)
            .accessibilityIdentifier("detail.loadFailed.retry")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Plan 16: reading text (17) in `muted` — it says something ("No summary yet…"), so not
    /// `faint`.
    private func emptyText(_ text: String, id: String) -> some View {
        Text(text)
            .stashFont(.reading)
            .foregroundStyle(StashColor.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier(id)
    }

    /// Shared by Summary/Original/Transcript: renders through `MarkdownBlocksView` when the text
    /// looks like markdown, else as plain body text — never literal `- `/`**` syntax. Plan 16: the
    /// `reading` role (17, was 14) with leading that grows with it (`stashLeading`).
    private func readOnlyBlock(_ text: String?, empty: String, id: String) -> some View {
        Group {
            if let text, !text.isEmpty {
                if MarkdownBlocks.looksLikeMarkdown(text) {
                    MarkdownBlocksView(text: text)
                } else {
                    Text(text)
                        .stashFont(.reading)
                        .foregroundStyle(StashColor.ink)
                        .stashLeading(0.55, role: .reading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                Text(empty)
                    .stashFont(.reading)
                    .foregroundStyle(StashColor.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier(id)
    }
}

/// An inline action's button style, idle and busy alike (`busyInlineAction`): the label as drawn,
/// with `.stashPlain`'s 44 pt target. While enabled, a press dims it, as `.plain`'s does. Disabled
/// (busy), it isn't dimmed at all: a custom `ButtonStyle` gets no automatic disabled look, whereas
/// `.plain` halves a disabled label's opacity, and a busy label is the progress people read. The
/// button itself is still `.disabled`, so VoiceOver hears it dimmed.
private struct InlineActionStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(isEnabled && configuration.isPressed ? 0.4 : 1)
            .stashMinimumHitTarget()
    }
}
