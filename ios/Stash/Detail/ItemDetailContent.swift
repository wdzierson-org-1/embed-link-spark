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
    /// site here follows): `isTranscribing` disables the button and swaps its label,
    /// `transcriptionErrorMessage` renders inline under this section's header on failure (the
    /// previous transcript stays exactly as it was — this is purely a display concern), and
    /// `onTranscribeWithSpeakers` is the trigger `ItemDetailView.retranscribe()` hands down.
    let isTranscribing: Bool
    let transcriptionErrorMessage: String?
    var onTranscribeWithSpeakers: () -> Void
    /// "Generate summary" (plan 15) — owned by `ItemDetailView`, like the transcription trigger.
    let isGeneratingSummary: Bool
    let summaryErrorMessage: String?
    var onGenerateSummary: () -> Void

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
                    .font(StashType.meta())
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
    /// button and swaps the label to "Transcribing…" with a small spinner alongside it; copy never
    /// claims real speaker identities ("Speaker 1/2…" is the server's own labeling, this button
    /// just triggers the rebuild).
    private var transcribeButton: some View {
        Button {
            onTranscribeWithSpeakers()
        } label: {
            HStack(spacing: 6) {
                if isTranscribing {
                    ProgressView()
                        .controlSize(.mini)
                }
                Text(isTranscribing ? "Transcribing…" : "Transcribe with speakers")
                    .font(StashType.meta())
            }
        }
        .foregroundStyle(isTranscribing ? StashColor.faint : StashColor.violet600)
        .disabled(isTranscribing)
        .accessibilityIdentifier("detail.transcribeSpeakers")
    }

    private var attachmentsSection: some View {
        VStack(alignment: .leading, spacing: DetailLayout.tight) {
            Text("Attachments".uppercased())
                .font(StashType.microLabel())
                .stashTracking(0.11, size: 11)
                .foregroundStyle(StashColor.faint)
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
            sourceBody(empty: "Transcription in progress…", id: "detail.transcriptText")
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
                        .font(StashType.meta())
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
    /// label (an action keeps its name through the flow — DESIGN.md §Voice).
    private var generateSummaryButton: some View {
        Button {
            onGenerateSummary()
        } label: {
            HStack(spacing: 6) {
                if isGeneratingSummary {
                    ProgressView()
                        .controlSize(.mini)
                }
                Text(isGeneratingSummary ? "Generating summary…" : "Generate summary")
                    .font(StashType.meta())
            }
        }
        .foregroundStyle(isGeneratingSummary ? StashColor.faint : StashColor.violet600)
        .disabled(isGeneratingSummary)
        .accessibilityIdentifier("detail.generateSummary")
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
                    .font(StashType.meta())
            }
            .foregroundStyle(StashColor.violet600)
            .accessibilityIdentifier("detail.loadFailed.retry")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func emptyText(_ text: String, id: String) -> some View {
        Text(text)
            .font(StashType.body())
            .foregroundStyle(StashColor.faint)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier(id)
    }

    /// Shared by Summary/Original/Transcript: renders through `MarkdownBlocksView` when the text
    /// looks like markdown, else as plain body text — never literal `- `/`**` syntax.
    private func readOnlyBlock(_ text: String?, empty: String, id: String) -> some View {
        Group {
            if let text, !text.isEmpty {
                if MarkdownBlocks.looksLikeMarkdown(text) {
                    MarkdownBlocksView(text: text)
                } else {
                    Text(text)
                        .font(StashType.body())
                        .foregroundStyle(StashColor.ink)
                        .lineSpacing(14 * 0.55)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                Text(empty)
                    .font(StashType.body())
                    .foregroundStyle(StashColor.faint)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier(id)
    }
}
