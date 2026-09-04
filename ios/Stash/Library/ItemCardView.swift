import SwiftUI
import StashKit

/// A single object-first card in the library grid (Plan 4 rework — see
/// `docs/superpowers/specs/2026-08-16-single-object-items-design.md`; DESIGN.md §Components
/// "Card anatomy" for the plan-9 token shell below). Anatomy, top to bottom: object zone
/// (`CardHero.swift`) → kicker (links only) → serif title → description → the user's own
/// annotation (violet bar, always visually distinct from description) → metadata chips (leading
/// tinted type chip, `CardChips.swift`) → footer (date · location pin · type badge). Legacy
/// `collection` items get a rich note + `CollectionStrip` instead of steps 2 (no kicker) through 6
/// (no chips). Shows a shimmering redacted overlay while a document is still processing, and a
/// yellow sticky-note corner badge when the item carries a public supplemental note — both
/// unchanged from the pre-rework card.
struct ItemCardView: View {
    let item: Item

    @Environment(\.openURL) private var openURL
    @State private var shimmerPhase: CGFloat = -1
    @State private var collectionCount: Int?

    private static let footerDateFormatter: DateFormatter = {
        // Fixed pattern + POSIX locale, not a localized style: the anatomy pins the literal
        // "MMM d, yyyy" shape (matches web's `format(date, 'MMM d, yyyy')`, itself locale-fixed),
        // not "whatever the device region prefers".
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            heroZone
            VStack(alignment: .leading, spacing: 8) {
                kicker
                // DESIGN.md's one serif role: "Object title (card) … PP Editorial New 400 · 20 /
                // tight · 2-line clamp" (plan 9's `StashType.editorialTitle()`, Task 0). The
                // negative `.lineSpacing` is the "tight" leading the font helper's own doc comment
                // asks callers to apply — SwiftUI's default line spacing for a 20pt serif reads
                // loose across a 2-line clamp otherwise.
                Text(title).font(StashType.editorialTitle()).lineSpacing(-2).lineLimit(2)
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

    private var title: String {
        let trimmed = item.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Untitled" : trimmed
    }

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

    // MARK: - Kicker (step 2: links only, tappable → opens URL)

    @ViewBuilder private var kicker: some View {
        if item.type == .link, let urlString = item.url, let url = URL(string: urlString) {
            let domain = domainOf(urlString)
            if !domain.isEmpty {
                // A `Link`/`Button` here (a nested semantic control) rather than a bare gesture
                // fought the outer card's own selection `Button` (LibraryView wraps the whole
                // card in one) for the tap: for a compact-hero card like the `example.com`
                // fixture, XCUITest's center-tap on `card.0` lands on this kicker, and the
                // nested control wins the WHOLE gesture — backgrounding the app into Safari
                // instead of presenting the detail sheet (`testDetailSheets` caught this live).
                // `.highPriorityGesture` is the documented way to claim taps within just this
                // view's own bounds without that nested-control ambiguity.
                // `.accessibilityAddTraits`/`.accessibilityAction` restore what a `Link`/`Button`
                // would have given for free — VoiceOver's double-tap activation calls a raw
                // `.highPriorityGesture` closure not at all, since that's a touch gesture, not
                // an accessibility action.
                Text(domain.uppercased())
                    .font(StashType.microLabel())
                    .kerning(0.6)
                    .foregroundStyle(StashColor.muted)
                    .highPriorityGesture(TapGesture().onEnded { openURL(url) })
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { openURL(url) }
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

    /// Text-type inversion (step 5): `content` IS the body (4-line clamp, no annotation
    /// treatment); `description` (the AI summary) shows only when there's no user content.
    @ViewBuilder private var textBody: some View {
        if !contentPlain.isEmpty {
            Text(contentPlain).font(StashType.body()).foregroundStyle(.primary.opacity(0.85)).lineLimit(4)
        } else if !descriptionPlain.isEmpty {
            Text(descriptionPlain).font(StashType.body()).foregroundStyle(StashColor.muted).lineLimit(3)
        }
    }

    private var standardBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !descriptionPlain.isEmpty {
                Text(descriptionPlain).font(StashType.body()).foregroundStyle(StashColor.muted).lineLimit(3)
            }
            if !contentPlain.isEmpty {
                CardAnnotation(text: contentPlain)
            }
            chipsRow
        }
    }

    /// Legacy `collection`: rich note (`renderTipTap` of `content`, else plain-texted
    /// `description`) + the read-only attachment strip. Frozen design — never created going
    /// forward (Global Constraints); no fixture exercises this in this task's verification pass.
    private var collectionBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !contentPlain.isEmpty {
                Text(renderTipTap(item.content)).font(StashType.body()).lineLimit(6)
            } else if !descriptionPlain.isEmpty {
                Text(descriptionPlain).font(StashType.body()).foregroundStyle(StashColor.muted).lineLimit(2)
            }
            CollectionStrip(itemId: item.id) { collectionCount = $0 }
        }
    }

    @ViewBuilder private var chipsRow: some View {
        let chips = metadataChips
        if !chips.isEmpty {
            HStack(spacing: 6) { ForEach(chips.indices, id: \.self) { chips[$0] } }
        }
    }

    /// Order matches DESIGN.md's chips grammar / web `ContentItemContent.tsx`'s chip build:
    /// leading tinted type chip, then fileName, then facts, then duration.
    private var metadataChips: [AnyView] {
        var chips: [AnyView] = []
        if let typeChip = typeChip(for: item) {
            chips.append(typeChip)
        }
        if [.image, .audio, .video].contains(item.type), let fileName = item.attributes.media?.fileName {
            chips.append(AnyView(MetaChip(mono: true, text: fileName)))
        }
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

    private var footer: some View {
        HStack(spacing: 8) {
            Text(Self.footerDateFormatter.string(from: item.createdAt))
                .font(StashType.meta())
                .foregroundStyle(.tertiary)
            if let label = item.attributes.location?.label, !label.isEmpty {
                locationBadge(label)
            }
            Spacer(minLength: 4)
            typeBadge
        }
    }

    private func locationBadge(_ label: String) -> some View {
        HStack(spacing: 2) {
            Image(systemName: "mappin.and.ellipse").font(.system(size: 9))
            Text(label).lineLimit(1).truncationMode(.tail)
        }
        .font(StashType.meta())
        .foregroundStyle(.tertiary)
        .frame(maxWidth: 140, alignment: .leading)
        // Same HStack-identifier-collision fix as `CaptureComposerView.pinPreview` (Task 6
        // finding): without `.ignore` + an explicit label, the icon and text independently
        // inherit `card.location`, and an XCUITest query for it returns "multiple matching
        // elements" instead of the one element Task 9's smoke expects.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("posted from \(label)")
        .accessibilityIdentifier("card.location")
    }

    private var typeBadge: some View {
        Label(typeBadgeLabel, systemImage: typeIcon)
            .font(StashType.chip())
            .labelStyle(.titleAndIcon)
            // Bug found live via Task 9's located-note fixture (first permanent fixture pairing
            // a long `card.location` label with this badge in the same footer row): with neither
            // `.lineLimit`/`.fixedSize` here, an HStack width squeeze (date + long location text
            // + this badge exceeding the card's content width) fell entirely on this Label — the
            // one sibling with no stated size preference — degrading to one-character-per-line
            // vertical text ("t/e/x/t") instead of the intended horizontal pill. `locationBadge`
            // already opts into graceful shrink-by-truncation (`.lineLimit(1)` + `maxWidth: 140`)
            // for exactly this squeeze; this badge should instead hold its single-line size and
            // never wrap, matching every other type name ("link"/"image"/"audio"/"video"/
            // "document"/"collection"/"N items") which are equally short and equally unsuited to
            // vertical wrapping.
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color(.tertiarySystemFill), in: Capsule())
            .foregroundStyle(StashColor.muted)
    }

    /// "N items" for collections (once the strip's own fetch reports a count — "items" bare
    /// until then), else the plain type name. Always visible on iOS (no hover state to gate it).
    private var typeBadgeLabel: String {
        guard item.type == .collection else { return item.type.rawValue }
        guard let collectionCount else { return "items" }
        return "\(collectionCount) item\(collectionCount == 1 ? "" : "s")"
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

    private var typeIcon: String {
        switch item.type {
        case .text: "note.text"
        case .link: "link"
        case .image: "photo"
        case .audio: "waveform"
        case .video: "video"
        case .document: "doc.richtext"
        case .collection: "folder"
        case .unknown: "questionmark.square"
        }
    }
}
