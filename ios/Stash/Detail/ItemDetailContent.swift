import SwiftUI
import StashKit

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
    let isLoadingDetail: Bool
    let notesModel: NotesEditorModel
    var notesFocused: FocusState<Bool>.Binding
    var scheduleNotesFlush: () -> Void
    var flushNotesNow: () async -> Void

    private var config: ContentTabsConfig { contentTabsConfig(for: item.type) }
    private var tabs: [ContentTab] { config.tabs }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHead

            tabBody(for: selectedTab)

            if item.type == .collection {
                attachmentsSection
            }
        }
    }

    /// Micro-label on its own line, tabs (when there's more than one) on the line below — the
    /// web packs both onto one row (`SectionHead`'s `aside`), but its pills are a much narrower
    /// unstyled-track style; this task's brief calls for the sign-in-style wash-track pill
    /// (`PillTabs`), which needs more room than a phone-width row shared with the label leaves —
    /// confirmed live (three tabs wrapped mid-word at 393pt when squeezed onto the label's row).
    private var sectionHead: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(config.title.uppercased())
                .font(StashType.microLabel())
                .stashTracking(0.11, size: 11)
                .foregroundStyle(StashColor.faint)
            if tabs.count > 1 {
                let pillItems = tabs.map { PillTabs<ContentTabKey>.Item($0.key, label: $0.label) }
                PillTabs(items: pillItems, selection: $selectedTab)
                    .accessibilityIdentifier("detail.tabs")
            }
        }
        .padding(.bottom, 7)
        .overlay(alignment: .bottom) {
            Rectangle().fill(StashColor.hairline).frame(height: 1)
        }
    }

    private var attachmentsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Attachments".uppercased())
                .font(StashType.microLabel())
                .stashTracking(0.11, size: 11)
                .foregroundStyle(StashColor.faint)
            CollectionStrip(itemId: item.id)
        }
        .accessibilityIdentifier("detail.attachments")
    }

    @ViewBuilder private func tabBody(for tab: ContentTabKey) -> some View {
        if tab != .notes && isLoadingDetail {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 120)
                .accessibilityIdentifier("detail.loadingSource")
        } else {
            switch tab {
            case .summary:
                readOnlyBlock(item.summary, empty: "No summary yet — generate one on the web for now",
                              id: "detail.summaryText")
            case .original:
                readOnlyBlock(item.pageBody, empty: "Nothing captured yet", id: "detail.originalText")
            case .transcript:
                readOnlyBlock(item.pageBody, empty: "Transcription in progress…", id: "detail.transcriptText")
            case .notes:
                NotesEditor(item: item, model: notesModel, isFocused: notesFocused,
                            scheduleFlush: scheduleNotesFlush, flushNow: flushNotesNow)
            }
        }
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
