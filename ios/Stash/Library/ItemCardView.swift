import SwiftUI
import StashKit

/// A single object-first card in the library grid (Plan 4 rework — see
/// `docs/superpowers/specs/2026-08-16-single-object-items-design.md`; DESIGN.md §Components
/// "Card anatomy"/"Card note" for the plan-14 shell below). Anatomy, top to bottom: object zone
/// (`CardHero.swift`) → kicker (links only) → Montreal medium title (`.stashFont(.cardTitle)`,
/// plan 14 — was the plan-9 serif `editorialTitle()`; plan 15: `ItemDisplay.displayTitle`, so a
/// bare storage object name reads as its type) → description → the card's note (`CardNoteView`:
/// a violet-ruled 5-line preview of `content`, nothing when empty) → metadata chips (leading type
/// chip — tinted or neutral, always present, `CardChips.swift` — then facts) → footer (date ·
/// location pin; plan 9 final wave dropped the footer's own type badge). Legacy `collection` items
/// get a rich note + a leading "N items" chip + `CollectionStrip` instead of steps 2 (no kicker)
/// through 5 (no note preview — frozen design, never created going forward). Shows a shimmering
/// redacted overlay while a document is still processing, and a yellow sticky-note corner badge
/// when the item carries a public supplemental note — both unchanged from the pre-rework card.
///
/// Plan 15 (Task 3; Will: "We should just make the entirety of the cards tappable ... We don't need
/// multiple tap targets in the card on the mobile app for right now"): on iOS the whole card is ONE
/// tap target — `LibraryView`'s card `Button` — that opens the detail sheet. Nothing inside a card
/// claims a gesture any more (the plan-14 in-card note editor, its "Add a note" affordance and the
/// kicker's external-link icon are gone); notes are written and links opened from the detail
/// sheet. Web keeps its inline card-note editor (DESIGN.md "Card note").
///
/// Plan 16 (HIG + accessibility): the title is the `cardTitle` role, descriptions and the note
/// `secondary` (15), the kicker, date and location `meta`-scale in `muted` (dates were `.tertiary`,
/// which failed contrast), chips `chip` — all scale with Dynamic Type and follow Bold Text. At the
/// accessibility sizes the card gives the title every line it needs and the description and note
/// twice their lines, instead of truncating them to a few words; the footer stacks when its date,
/// type chip and place can't share a line.
struct ItemCardView: View {
    let item: Item

    @State private var shimmerPhase: CGFloat = -1
    @State private var collectionCount: Int?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Line caps: the designed clamps at the standard sizes; at the accessibility sizes (where a
    /// line holds a word or two) the title isn't clamped and the previews get twice the lines.
    private var titleLineLimit: Int? { dynamicTypeSize.isAccessibilitySize ? nil : 2 }
    private func previewLineLimit(_ standard: Int) -> Int {
        dynamicTypeSize.isAccessibilitySize ? standard * 2 : standard
    }

    private static let footerDateFormatter: DateFormatter = {
        // Fixed pattern + POSIX locale, not a localized style: the anatomy pins the literal
        // "MMM d, yyyy" shape (matches web's `format(date, 'MMM d, yyyy')`, itself locale-fixed),
        // not "whatever the device region prefers".
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    /// Plan 14 fix wave B (#10, perf): every card used to pay for a `TimelineView(.periodic
    /// (by: 30))` — a perpetual 30s re-render tick, live for as long as the card is on screen —
    /// even for an item with no `attributes.enrichment` key at all, which can NEVER dim or show a
    /// status pill (`enrichmentStatus(at:)` returns `nil` unconditionally whenever that key is
    /// missing; it only depends on wall-clock time once a "pending" status with a timestamp is
    /// actually present). A library screen full of such items — most of them, once enrichment has
    /// long since finished or never applied — was ticking a timer none of them could ever act on.
    /// `nil`-ness itself never depends on `now`, so probing it once outside the timer (with any
    /// `Date`) is enough to decide, per card, whether the timer is worth paying for at all; a card
    /// whose enrichment key DOES exist still gets the exact same periodic re-evaluation as before,
    /// so the pending→partial 10-minute timeout in `enrichmentStatus(at:)` is unaffected.
    var body: some View {
        if item.attributes.enrichmentStatus(at: .now) == nil {
            cardBody
        } else {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                let status = item.attributes.enrichmentStatus(at: context.date)
                cardBody
                    .opacity(status == "pending" ? 0.5 : 1)
                    .overlay(alignment: .topLeading) {
                        if status == "pending" || status == "partial" {
                            Text(status == "pending" ? "Gathering more information…" : "Some information unavailable")
                                .stashFont(.meta)
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(Color(.systemBackground), in: Capsule())
                                .padding(8)
                                .accessibilityIdentifier("card.enrichmentStatus")
                        }
                    }
            }
        }
    }

    private var cardBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            heroZone
            VStack(alignment: .leading, spacing: 8) {
                kicker
                // DESIGN.md's current card heading (2026-09-13 housekeeping mirror, plan 14):
                // Montreal medium 20/tight · −0.014em tracking (`.stashFont(.cardTitle)`),
                // superseding the plan-9 serif `editorialTitle()`. The negative leading keeps the
                // "tight" leading the old serif treatment also needed — Montreal at 20pt across a
                // 2-line clamp reads loose under SwiftUI's default line spacing too. −0.1 em: the
                // old fixed −2 pt at Large, scaling with the title (2b review N-5).
                Text(title).stashFont(.cardTitle).stashTracking(-0.014, role: .cardTitle)
                    .stashLeading(-0.1, role: .cardTitle).lineLimit(titleLineLimit)
                    // Plan 15 fix: with the negative line spacing, a title that needs both lines
                    // was sometimes handed a one-line height at layout time — rendered as
                    // "…" after one line while the grid row still reserved the second (a ~24pt
                    // phantom gap under the card). Taking its full ideal height keeps the
                    // designed 2-line clamp.
                    .fixedSize(horizontal: false, vertical: true)
                contentSection
                footer
            }
            // DESIGN.md §Space: body side padding 24px; `--card-gap: 18px` between hero bottom
            // and body top for every hero type; 22px top padding on hero-less cards (`.text`/
            // `.audio` — no player hero shipped yet — /`.collection`/`.unknown`).
            .padding(.horizontal, 24)
            .padding(.top, hasHero ? 18 : 22)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        // One outer clip (rather than porting the web's per-plate `rounded-t-2xl`) crops
        // whatever's in the hero zone to the card's own top corners — the hero sits flush
        // against the top/sides with no gap, so this alone produces the same silhouette.
        .clipShape(RoundedRectangle(cornerRadius: StashRadius.card))
        // Web card treatment: a white surface lifted off the gradient backdrop by a hairline
        // border + soft shadow, instead of the flat gray-fill look.
        .overlay(RoundedRectangle(cornerRadius: StashRadius.card).strokeBorder(.black.opacity(0.06), lineWidth: 1))
        // DESIGN.md's two-layer card shadow (Task 0's `.stashCardShadow()`), replacing the ad hoc
        // single `.shadow`.
        .stashCardShadow()
        .overlay(alignment: .topTrailing) { stickyBadge }
        .redacted(reason: item.isProcessingDocument ? .placeholder : [])
        .overlay { if item.isProcessingDocument { shimmer } }
    }

    /// Mirrors `heroZone`'s own switch — true for the four types that currently render a
    /// non-empty object zone. `.audio` reads `false` today (no player hero yet, `heroZone`'s
    /// `EmptyView()` branch) even though DESIGN.md's per-type hero table eventually wants one; the
    /// no-hero 22pt top padding is the visually-correct choice while that gap is still empty, and
    /// whoever ships the audio player hero should widen this switch alongside it.
    private var hasHero: Bool {
        switch item.type {
        case .link, .image, .video, .document: true
        case .text, .audio, .collection, .unknown: false
        }
    }

    /// Plan 15: a UUID/timestamp object name ("ce47f779-….m4a") reads as its type ("Voice note") —
    /// display only; the detail sheet still shows and edits the stored title.
    private var title: String { ItemDisplay.displayTitle(for: item) }

    // MARK: - Object zone (anatomy step 1)

    @ViewBuilder private var heroZone: some View {
        switch item.type {
        case .link: LinkHeroZone(item: item)
        case .image: ImageHeroZone(item: item)
        case .video: VideoHeroZone(item: item)
        case .document:
            FilePlate(kind: .document, fileName: item.attributes.media?.fileName,
                      factsLine: factsLine(mime: item.mimeType, size: item.fileSize))
        case .text, .audio, .collection, .unknown: EmptyView()
        }
    }

    // MARK: - Kicker (step 2: links only)

    /// The link's domain as a plain micro-label. Plan 15: the trailing external-link icon (plan 12's
    /// narrowed `.highPriorityGesture` affordance) is gone — the card is one tap target on iOS and
    /// the detail sheet's URL bar (`DetailURLBar`) already opens the link.
    @ViewBuilder private var kicker: some View {
        if item.type == .link, let urlString = item.url {
            let domain = domainOf(urlString)
            if !domain.isEmpty {
                // The kicker role (Semibold 12, caps drawn — VoiceOver reads the domain, not
                // letters), keeping the card's own 0.6 pt tracking.
                Text(domain)
                    .stashFont(.kicker)
                    .textCase(.uppercase)
                    .stashTracking(0.05, role: .kicker)
                    .foregroundStyle(StashColor.muted)
            }
        }
    }

    // MARK: - Description / annotation / chips (steps 4-6), collection note+strip

    @ViewBuilder private var contentSection: some View {
        switch item.type {
        case .collection: collectionBody
        case .text: textBody
        default: standardBody
        }
    }

    /// Text-type inversion (step 5): `content` IS the body — previewed via `CardNoteView`, same as
    /// every other type's note (web parity, `ContentItemContent.tsx`'s `.text` branch: "the words
    /// ARE the object — show them, not the AI summary"); `description` (the AI summary) shows only
    /// when there's no user content yet. Plan 9 final wave: gained `chipsRow` too (web parity —
    /// `ContentItemContent.tsx`'s text branch renders `typeChipFor(item)` unconditionally) now
    /// that `.text` earns a neutral "note" chip; previously this branch (unlike `standardBody`)
    /// never called `chipsRow` at all, which is why text cards showed no type identity until this
    /// wave.
    ///
    /// Plan 15: a `Group` (not a nested `VStack`) — its rows join the card body's own 8pt-spaced
    /// stack, so a card with no description/note/chips (possible now that the "Add a note" row is
    /// gone) doesn't pick up a double 16pt gap around an empty section.
    @ViewBuilder private var textBody: some View {
        Group {
            if contentPlain.isEmpty, !descriptionPlain.isEmpty {
                description
            }
            CardNoteView(item: item)
            chipsRow
        }
    }

    private var standardBody: some View {
        Group {
            if !descriptionPlain.isEmpty {
                description
            }
            CardNoteView(item: item)
            chipsRow
        }
    }

    /// Supporting text: the `secondary` role (15, was 14) in `muted`, 3 lines (6 at the
    /// accessibility sizes). Takes its full ideal height, like the title: the grid could hand it
    /// one line at layout time — "Voice memo abou…" over a two-line gap (seen in plan 16's search
    /// results).
    private var description: some View {
        Text(descriptionPlain)
            .stashFont(.secondary)
            .foregroundStyle(StashColor.muted)
            .lineLimit(previewLineLimit(3))
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Legacy `collection`: rich note (`renderTipTap` of `content`, else plain-texted
    /// `description`) + the read-only attachment strip. Frozen design — never created going
    /// forward (Global Constraints); no fixture exercises this in this task's verification pass.
    /// Plan 9 final wave: gained its own leading neutral chip ("N items") now that the footer's
    /// `typeBadge` — the count's only home before this — is gone; built inline rather than
    /// through `typeChip(for:)` since that free function has no access to this view's own
    /// `collectionCount` state (populated asynchronously by `CollectionStrip`'s fetch below).
    private var collectionBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !contentPlain.isEmpty {
                Text(renderTipTap(item.content)).stashFont(.secondary).lineLimit(previewLineLimit(6))
                    .fixedSize(horizontal: false, vertical: true)
            } else if !descriptionPlain.isEmpty {
                Text(descriptionPlain).stashFont(.secondary).foregroundStyle(StashColor.muted)
                    .lineLimit(previewLineLimit(2))
                    .fixedSize(horizontal: false, vertical: true)
            }
            MetaChip(text: collectionChipText).accessibilityIdentifier("card.typeChip")
            CollectionStrip(itemId: item.id) { collectionCount = $0 }
        }
    }

    /// "N items" once the strip's own fetch reports a count — "items" bare until then. Same
    /// copy the deleted footer `typeBadge` used to show (`typeBadgeLabel`'s old `.collection`
    /// branch).
    private var collectionChipText: String {
        guard let collectionCount else { return "items" }
        return "\(collectionCount) item\(collectionCount == 1 ? "" : "s")"
    }

    /// `FlowLayout` (Design/StashDesign.swift), not a plain `HStack`: a card can carry several
    /// chips (leading type chip + facts + a salient fact) that must never squeeze the leading
    /// type chip into truncation — this wraps to a second line under width pressure instead.
    @ViewBuilder private var chipsRow: some View {
        let chips = metadataChips
        if !chips.isEmpty {
            FlowLayout(spacing: 6) { ForEach(chips.indices, id: \.self) { chips[$0] } }
        }
    }

    /// Order matches DESIGN.md's chips grammar / web `ContentItemContent.tsx`'s chip build:
    /// leading type chip (tinted or neutral, always present for the types this row renders for),
    /// then facts, then duration. The raw-filename mono chip (plan 9 final wave: dropped from
    /// cards — DESIGN.md §Components "Chips grammar" "nothing else"; web removed it first) no
    /// longer has a call site here — the filename still lives in the detail sheet's Details
    /// drawer.
    private var metadataChips: [AnyView] {
        var chips: [AnyView] = []
        if item.type != .document, item.type != .link,
           let facts = factsLine(mime: item.mimeType, size: item.fileSize) {
            chips.append(AnyView(MetaChip(text: facts)))
        }
        if item.type == .audio, let duration = formatDurationChip(item.attributes.media?.durationS) {
            chips.append(AnyView(MetaChip(text: duration)))
        }
        return chips
    }

    // MARK: - Footer (step 7)

    /// Plan 9 final wave: dropped its own trailing `typeBadge` — the card's type now surfaces up
    /// in the chips row (`CardChips.swift`'s `typeChip(for:)`, tinted or neutral, on every card)
    /// instead of down here, so the footer keeps only date + location, matching web's own footer
    /// contents minus the desktop-only hover overflow control.
    ///
    /// Plan 16: the date never wraps inside the row (it and the type chip keep their one line; the
    /// place gives way first, as before). At the accessibility sizes, where the three can't share a
    /// line, they stack — date, chip, then the place in full.
    @ViewBuilder private var footer: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                footerContents
            }
        } else {
            HStack(spacing: 8) {
                footerContents
            }
        }
    }

    @ViewBuilder private var footerContents: some View {
        // `meta` in `muted` (it was `.tertiary`, which failed contrast).
        Text(Self.footerDateFormatter.string(from: item.createdAt))
            .stashFont(.meta)
            .foregroundStyle(StashColor.muted)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
        if let chip = typeChip(for: item) {
            chip.fixedSize(horizontal: true, vertical: false)
        }
        if let label = item.attributes.location?.label, !label.isEmpty {
            locationBadge(label)
        }
    }

    /// The pin takes the line's own role, a size down (`imageScale(.small)`, as the 9 pt glyph
    /// sat beside 12 pt text), so it grows with the text.
    private func locationBadge(_ label: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Image(systemName: "mappin.and.ellipse").imageScale(.small)
            Text(label)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
                .truncationMode(.tail)
        }
        .stashFont(.meta)
        .foregroundStyle(StashColor.muted)
        .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : 140, alignment: .leading)
        // Same HStack-identifier-collision fix as `CaptureComposerView.pinPreview` (Task 6
        // finding): without `.ignore` + an explicit label, the icon and text independently
        // inherit `card.location`, and an XCUITest query for it returns "multiple matching
        // elements" instead of the one element Task 9's smoke expects.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("posted from \(label)")
        .accessibilityIdentifier("card.location")
    }

    // MARK: - Plain-texted content/description (steps 4-5: never raw TipTap JSON on a card)

    private var descriptionPlain: String { plainText(item.description) }
    private var contentPlain: String { plainText(item.content) }

    /// `renderTipTap` already passes plain (non-JSON) text through unchanged; taking just the
    /// `.characters` of its `AttributedString` result strips any bold/italic marks it applied,
    /// matching the anatomy's "plain-texted" wording (as opposed to the rich `Text(renderTipTap
    /// (...))` the legacy-collection note and the detail sheet's Notes tab use).
    private func plainText(_ raw: String?) -> String {
        String(renderTipTap(raw).characters).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Sticky badge / processing shimmer (unchanged)

    @ViewBuilder private var stickyBadge: some View {
        if let note = item.supplementalNote, !note.isEmpty, item.isPublic {
            Image(systemName: "note.text")
                .font(.caption2)
                .foregroundStyle(.black.opacity(0.7))
                .padding(5)
                .background(Color.yellow, in: RoundedRectangle(cornerRadius: 4))
                .rotationEffect(.degrees(6))
                .padding(6)
                // Plan 16: a corner badge is chrome, capped at its Large size — it stays inside the
                // card's 24 pt side padding; grown with the text it covered the title's first line
                // (seen at xxxLarge and AX3). VoiceOver reads what it means, not the glyph's name.
                .dynamicTypeSize(...DynamicTypeSize.large)
                .accessibilityLabel("Sticky note on your public feed")
        }
    }

    private var shimmer: some View {
        GeometryReader { geo in
            LinearGradient(colors: [.clear, .white.opacity(0.55), .clear],
                            startPoint: .leading, endPoint: .trailing)
                .frame(width: geo.size.width * 0.6)
                .offset(x: shimmerPhase * geo.size.width)
        }
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) {
                shimmerPhase = 1.6
            }
        }
    }
}

// MARK: - Card note (DESIGN.md §Components "Card note", plan 14; static on iOS since plan 15)

/// The card's own `content` field as a read-only, violet-ruled 5-line preview; renders nothing
/// when the note is empty. Web reference: `src/components/cards/CardInlineNote.tsx` (web still
/// edits inline). Plan 15: on iOS this no longer claims a tap — no "Add a note" affordance, no
/// editor sheet — so a tap anywhere on the card, the note included, opens the detail sheet, whose
/// Notes editor is the one place a note is written on iOS.
struct CardNoteView: View {
    let item: Item

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Plain-texted preview — same "never raw TipTap JSON on a card" rule `ItemCardView.plainText`
    /// follows, computed independently here since this view doesn't have access to that private
    /// helper.
    private var preview: String {
        String(renderTipTap(item.content).characters).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var rightRoundedShape: UnevenRoundedRectangle {
        // "only the right corners of the hover surface are rounded" (DESIGN.md "Card note") — the
        // left edge is squared off, flush with the violet fill bar overlaid on it.
        UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 0,
                                bottomTrailingRadius: 8, topTrailingRadius: 8, style: .continuous)
    }

    /// Plan 16: the `secondary` role (15, was 14); 5 lines, 10 at the accessibility sizes.
    var body: some View {
        if !preview.isEmpty {
            Text(preview)
                .stashFont(.secondary)
                .foregroundStyle(.primary.opacity(0.75))
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 10 : 5)
                // Its full ideal height (see `ItemCardView.description`).
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 11)
                .padding(.vertical, 5)
                .padding(.trailing, 8)
                .background(Color.primary.opacity(0.04), in: rightRoundedShape)
                // The violet-600 fill bar (DESIGN.md: "a fill, not a stroke") — `.overlay`, not an
                // `HStack` sibling, same reasoning the retired `CardAnnotation` documented: an
                // unconstrained `Rectangle` has no intrinsic height, so it'd soak up any extra
                // height an equalized grid row proposes; `.overlay` proposes the bar the `Text`'s
                // own already-resolved frame instead.
                .overlay(alignment: .leading) {
                    Rectangle().fill(StashColor.violet600).frame(width: 2)
                }
                .accessibilityIdentifier("card.note")
        }
    }
}
