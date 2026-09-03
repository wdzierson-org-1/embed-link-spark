import StashKit
import SwiftUI

/// Renders `MarkdownBlocks.parse(text)` block-by-block — the fix for AI summaries showing up as
/// literal `- ` bullets and `**bold**` in the detail sheet. Each block gets its own layout
/// treatment; inline emphasis inside paragraphs/bullets/etc. is handed to
/// `AttributedString(markdown:)` so `**bold**`, `*italic*`, and `[text](url)` links render
/// properly instead of showing their raw markdown syntax.
struct MarkdownBlocksView: View {
    let text: String

    private var blocks: [MarkdownBlock] { MarkdownBlocks.parse(text) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                view(for: block)
            }
        }
    }

    @ViewBuilder private func view(for block: MarkdownBlock) -> some View {
        switch block {
        case .paragraph(let text):
            inlineText(text)

        case .heading(_, let text):
            inlineText(text)
                .font(StashType.bodySemibold())

        case .bullets(let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•").foregroundStyle(StashColor.faint)
                        inlineText(item)
                    }
                    .padding(.leading, 16)
                    .accessibilityElement(children: .combine)
                }
            }

        case .numbered(let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(index + 1).").foregroundStyle(StashColor.faint)
                        inlineText(item)
                    }
                    .padding(.leading, 16)
                    .accessibilityElement(children: .combine)
                }
            }

        case .quote(let text):
            HStack(spacing: 10) {
                Rectangle()
                    .fill(StashColor.violet600)
                    .frame(width: 2)
                inlineText(text)
                    .foregroundStyle(StashColor.muted)
            }

        case .code(let text):
            Text(text)
                .font(StashType.mono())
                .foregroundStyle(StashColor.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(StashColor.wash, in: RoundedRectangle(cornerRadius: StashRadius.input))
        }
    }

    /// Body line-height per DESIGN.md (~1.55 at 14pt): `.lineSpacing` adds the delta on top of
    /// the font's own single-line spacing, so `14 * 0.55`.
    private func inlineText(_ raw: String) -> some View {
        var attributed = (try? AttributedString(markdown: raw, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(raw)
        styleLinks(&attributed)
        return Text(attributed)
            .font(StashType.body())
            .foregroundStyle(StashColor.ink)
            .lineSpacing(14 * 0.55)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// DISCLOSED tweak (Plan 8 Task 4): any markdown link rendered through this view — including
    /// `ChatCitations`' `stash://item/<uuid>` citation links in Ask answers — uses DESIGN.md's
    /// violet600 token with no underline, rather than `Text`'s default (system tint, which the Ask
    /// tab happens to already set to violet600 via `MainTabView`'s `.tint`, but this view is also
    /// used standalone in `#Preview` and elsewhere outside that hierarchy) plus an underline that
    /// default markdown-link styling can add.
    private func styleLinks(_ attributed: inout AttributedString) {
        let linkRanges = attributed.runs.filter { $0.link != nil }.map(\.range)
        for range in linkRanges {
            attributed[range].foregroundColor = StashColor.violet600
            attributed[range].underlineStyle = nil
        }
    }
}

#Preview {
    ScrollView {
        MarkdownBlocksView(text: """
        Key features include:

        - Brown tortoiseshell effect
        - Brand logo detailing
        - Round frame
        - Tinted lenses
        - Comes with a protective case

        These sunglasses pair well with **casual** and **smart-casual** outfits alike, and the \
        [product page](https://www.farfetch.com) has full sizing details.
        """)
        .padding(20)
    }
}
