import SwiftUI
import StashKit

/// The content section: a segmented `Picker` over `contentTabsConfig(for:).tabs`, with each
/// tab's body (or its empty-state copy) driven straight off the current `Item`. `.summary`
/// and `.notes` read fields the grid already loaded; `.original`/`.transcript` read
/// `pageBody`, which only arrives after `ItemDetailView`'s on-appear detail fetch — while
/// that's in flight, those two tabs show a spinner instead of a premature empty state.
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

    private var tabs: [ContentTab] { contentTabsConfig(for: item.type).tabs }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Content", selection: $selectedTab) {
                ForEach(tabs, id: \.key) { tab in
                    Text(tab.label).tag(tab.key)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("detail.tabPicker")

            tabBody(for: selectedTab)

            if item.type == .collection {
                attachmentsSection
            }
        }
    }

    private var attachmentsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Attachments")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
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
                textBlock(item.summary, empty: "No summary yet — generate one on the web for now",
                          id: "detail.summaryText")
            case .original:
                originalBlock
            case .transcript:
                textBlock(item.pageBody, empty: "Transcription in progress…", id: "detail.transcriptText")
            case .notes:
                notesBlock
            }
        }
    }

    private func textBlock(_ text: String?, empty: String, id: String) -> some View {
        Group {
            if let text, !text.isEmpty {
                Text(text)
            } else {
                Text(empty).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier(id)
    }

    /// Scrollable + monospaced-ish, independent of the sheet's own outer scroll — captured
    /// source pages can run tens of KB, so this tab gets its own bounded, scrolling frame.
    private var originalBlock: some View {
        Group {
            if let body = item.pageBody, !body.isEmpty {
                ScrollView {
                    Text(body)
                        .font(.system(.footnote, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 320)
            } else {
                Text("Nothing captured yet")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityIdentifier("detail.originalText")
    }

    private var notesBlock: some View {
        Group {
            if let content = item.content, !content.isEmpty {
                Text(renderTipTap(content))
            } else {
                Text("No notes yet").foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("detail.notesText")
    }
}
