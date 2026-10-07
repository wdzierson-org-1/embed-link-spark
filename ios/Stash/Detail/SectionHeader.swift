import SwiftUI

/// Detail sheet's shared layout constants — the "one place to tune" both the ONE horizontal
/// content inset and the vertical rhythm scale, from this fix round's audit (Plan 10 Task 3 — see
/// `task-3-report.md` for the full before/after value list behind Will's "margins being
/// inconsistent on the detail sheet" complaint).
enum DetailLayout {
    /// The ONE horizontal content inset — applied once, at the scroll content's outer `VStack`
    /// (`ItemDetailView.body`) and the pinned footer bar below it, so every section's left/right
    /// edge lines up with the title/description above it. Deliberately NOT applied to
    /// component-internal chrome the audit also turned up (`titleField`/`descriptionField`'s own
    /// text-hit-padding, the notes `TextEditor`'s own inset, the feed-link chip's capsule
    /// padding) — those size a control's own hit target or a pill's own label, not the page's
    /// content margin, and are left exactly as they were.
    static let inset: CGFloat = 20

    /// Tight, in-component rhythm (icon-to-label, a section's own micro-content grouping).
    static let tight: CGFloat = 8
    /// The flow surface's own item-to-item gap (title → description → media → URL bar).
    static let gap: CGFloat = 14
    /// The gap above a new section's `SectionHeader` — bigger than `gap` on purpose, so a new
    /// section always reads as a bigger beat than the prose above it.
    static let section: CGFloat = 24
}

/// What a `SectionHeader`'s `trailing` does when it doesn't fit beside the label.
enum SectionTrailingFit {
    /// It moves under the label, whole — an action ("Transcribe again") is never cut.
    case reflow
    /// It stays beside the label, its text shortened, at the standard sizes — the Details drawer's
    /// collapsed summary (a long domain), which the open drawer shows in full — and moves under the
    /// label at the accessibility sizes, where little fits beside it (2b review N-1: at Large a
    /// long domain took the chevron down under the label with it).
    case truncateUntilAccessibilitySizes
}

/// One shared section heading — DESIGN.md "Panel section grammar: uppercase micro-label over a
/// hairline rule — never a nested card/box." Before this fix round, `ItemDetailContent`,
/// `DetailsDrawer`, and `SharingSection` each hand-rolled this exact label-over-rule pattern
/// independently, and the label-to-rule gap had quietly drifted between them (7pt in the first
/// two, 10pt in the third — see `task-3-report.md`'s audit) — part of what read as "heading
/// underlines being inconsistently implemented." Now there's exactly one implementation, with the
/// rhythm fixed here: `DetailLayout.section` above the label, 10pt label-to-rule, `DetailLayout.gap`
/// below the rule.
///
/// `trailing` renders inline with the label, before the rule — `DetailsDrawer`'s collapsed
/// summary + chevron, where the whole header doubles as a tap target. `accessory` renders on its
/// own full-width line below the label, still above the rule — `ItemDetailContent`'s `PillTabs`
/// specifically needs this slot, not the inline one: three tabs squeezed onto the label's own row
/// wrapped mid-word at 393pt (confirmed live, pre-dating this fix round — see that view's own doc
/// comment). Both default to nothing, so the plain call site (`SharingSection`) is exactly
/// `SectionHeader(title:)`.
///
/// Plan 16: the label is `stashMicroLabel()` — Semibold 12 caps, `muted` (the old `faint` was
/// 2.79:1). When the label and `trailing` can't share a line (large text: "NOTES & TRANSCRIPT"
/// beside "Transcribe again"), `trailing` moves to its own line under the label instead of
/// squeezing either one — or, for a `trailing` that may be cut (`SectionTrailingFit`), only at
/// the accessibility sizes.
struct SectionHeader<Trailing: View, Accessory: View>: View {
    let title: String
    var trailingFit: SectionTrailingFit
    @ViewBuilder var trailing: () -> Trailing
    @ViewBuilder var accessory: () -> Accessory

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(title: String,
         trailingFit: SectionTrailingFit = .reflow,
         @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() },
         @ViewBuilder accessory: @escaping () -> Accessory = { EmptyView() }) {
        self.title = title
        self.trailingFit = trailingFit
        self.trailing = trailing
        self.accessory = accessory
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if trailingFit == .truncateUntilAccessibilitySizes, !dynamicTypeSize.isAccessibilitySize {
                // One line: the label keeps its word, `trailing`'s text gives way.
                HStack(spacing: 8) {
                    label
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .layoutPriority(1)
                    Spacer(minLength: 8)
                    trailing()
                }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        label
                        Spacer(minLength: 8)
                        trailing()
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        label
                        trailing()
                    }
                }
            }
            accessory()
            Rectangle().fill(StashColor.ink).frame(height: 1)
        }
        .padding(.top, DetailLayout.section)
        .padding(.bottom, DetailLayout.gap)
    }

    /// Callers pass the title in any case ("DETAILS", "Notes"); the caps are drawn, so VoiceOver
    /// reads the words — as a heading, so the rotor can jump between the sheet's sections.
    private var label: some View {
        Text(title.lowercased())
            .stashFont(.machine)
            .foregroundStyle(StashColor.ink)
            .accessibilityAddTraits(.isHeader)
    }
}
