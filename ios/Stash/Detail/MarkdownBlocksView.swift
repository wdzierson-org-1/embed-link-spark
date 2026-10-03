import StashKit
import SwiftUI

/// Renders `MarkdownBlocks.parse(text)` block-by-block — the fix for AI summaries showing up as
/// literal `- ` bullets and `**bold**` in the detail sheet. Each block gets its own layout
/// treatment; inline emphasis inside paragraphs/bullets/etc. is handed to
/// `AttributedString(markdown:)` so `**bold**`, `*italic*`, and `[text](url)` links render
/// properly instead of showing their raw markdown syntax.
///
/// Plan 16: reading text is the `reading` role (17, was 14) with leading that grows with it
/// (`stashLeading`), and `**strong**` / `*emphasis*` resolve to the role's Semibold / Book Italic
/// faces by themselves. A block's role and colour go INTO `inlineText`, which builds the `Text`:
/// one applied outside it is dead (the inner `Text`'s own font and colour win) — which is why
/// `##` headings used to render in the Book face and quotes in `ink`. Links are violet-600 with
/// the shared link underline (`styleLinks`, `Text.LineStyle.stashLinkUnderline`).
struct MarkdownBlocksView: View {
    let text: String
    // (Plan 15: the `compact` chat-bubble mode is gone — the Ask tab renders its own cached blocks
    // through `ChatAnswerText` since 6A, so this view only ever draws the detail sheet's
    // full-width Summary/Original/Transcript tabs.)

    /// The gaps between blocks and list items grow with the text, like its leading.
    @ScaledMetric(relativeTo: .body) private var blockGap: CGFloat = 12
    @ScaledMetric(relativeTo: .body) private var itemGap: CGFloat = 6

    private var blocks: [MarkdownBlock] { MarkdownBlocks.parse(text) }

    var body: some View {
        VStack(alignment: .leading, spacing: blockGap) {
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
            inlineText(text, role: .readingSemibold)
                .accessibilityAddTraits(.isHeader)

        case .bullets(let items):
            VStack(alignment: .leading, spacing: itemGap) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        marker("•")
                        inlineText(item)
                    }
                    .padding(.leading, 16)
                    .accessibilityElement(children: .combine)
                }
            }

        case .numbered(let items):
            VStack(alignment: .leading, spacing: itemGap) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        marker("\(index + 1).")
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
                inlineText(text, color: StashColor.muted)
            }

        case .code(let text):
            Text(text)
                .stashFont(.mono(.subheadline))
                .foregroundStyle(StashColor.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(StashColor.wash, in: RoundedRectangle(cornerRadius: StashRadius.input))
        }
    }

    /// A list marker, `muted`: a number carries the order, so it has to be readable (`faint` was
    /// 2.79:1). Its face is the system body style, as before (a round bullet; Neue Montreal's is
    /// square) — a text style, so it scales with the item and follows Bold Text by itself.
    private func marker(_ text: String) -> some View {
        Text(text)
            .font(.body)
            .foregroundStyle(StashColor.muted)
    }

    /// One markdown run as a `Text` in `role` and `color` — both passed in, never applied outside
    /// (see the type's doc). The detail sheet's reading leading, `stashLeading(0.55)`: 0.55 em on
    /// top of the face's own 1.2 em line (CSS line-height ≈ 1.75; ≈ 1.55 at the accessibility
    /// sizes, where `stashLeading` caps the gap at 0.35 em), scaled with the role's text style.
    private func inlineText(_ raw: String, role: StashType.Role = .reading,
                            color: Color = StashColor.ink) -> some View {
        var attributed = (try? AttributedString(markdown: raw, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(raw)
        styleLinks(&attributed)
        return Text(attributed)
            .stashFont(role)
            .foregroundStyle(color)
            .stashLeading(0.55, role: role)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Every markdown link here is DESIGN.md's violet-600 text WITH an underline (plan 16, WCAG
    /// 2.2 SC 1.4.1 Use of Color, Level A). Colour alone can't mark a link inside reading text:
    /// violet-600 is 2.93:1 against `ink` body text and 1.04:1 against a quote's `muted` (3:1 is the
    /// floor for a colour-only link), and no violet clears 3:1 against `ink` while staying 4.5:1 on
    /// white. The underline is the shared Design style, `Text.LineStyle.stashLinkUnderline`
    /// (violet-600 at 80 %, 3.52:1 on white), the same one Ask's answers take. This supersedes
    /// plan 8 Task 4's disclosed tweak, which took the underline off.
    private func styleLinks(_ attributed: inout AttributedString) {
        let linkRanges = attributed.runs.filter { $0.link != nil }.map(\.range)
        for range in linkRanges {
            attributed[range].foregroundColor = StashColor.violet600
            attributed[range].underlineStyle = Text.LineStyle.stashLinkUnderline
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
