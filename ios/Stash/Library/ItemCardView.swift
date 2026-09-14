import SwiftUI
import StashKit

/// A single object-first card in the library grid (Plan 4 rework — see
/// `docs/superpowers/specs/2026-08-16-single-object-items-design.md`; DESIGN.md §Components
/// "Card anatomy"/"Card note" for the plan-14 shell below). Anatomy, top to bottom: object zone
/// (`CardHero.swift`) → kicker (links only) → Montreal medium title (`StashType.cardTitle()`,
/// plan 14 — was the plan-9 serif `editorialTitle()`) → description → the card's editable note
/// (`CardNoteView`, plan 14 — was a read-only `CardAnnotation`; "Add a note" when empty, a
/// tappable violet-ruled preview otherwise, opening `CardNoteEditorSheet`) → metadata chips
/// (leading type chip — tinted or neutral, always present, `CardChips.swift` — then facts) →
/// footer (date · location pin; plan 9 final wave dropped the footer's own type badge). Legacy
/// `collection` items get a rich note + a leading "N items" chip + `CollectionStrip` instead of
/// steps 2 (no kicker) through 5 (no editable note — frozen design, never created going forward).
/// Shows a shimmering redacted overlay while a document is still processing, and a yellow
/// sticky-note corner badge when the item carries a public supplemental note — both unchanged
/// from the pre-rework card.
struct ItemCardView: View {
    let item: Item
    /// Plan 14: the card note editor patches through the same `ItemStore` the detail sheet does
    /// (`store.applyDetail(merged)`), so a save here is reflected in the grid immediately without
    /// waiting on the next realtime broadcast — see `CardNoteView`'s own doc comment.
    let store: ItemStore

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
                                .font(StashType.meta())
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
                // Montreal medium 20/tight · −0.014em tracking (`StashType.cardTitle()`),
                // superseding the plan-9 serif `editorialTitle()`. The negative `.lineSpacing`
                // keeps the "tight" leading the old serif treatment also needed — Montreal at
                // 20pt across a 2-line clamp reads loose under SwiftUI's default line spacing too.
                Text(title).font(StashType.cardTitle()).stashTracking(-0.014, size: 20)
                    .lineSpacing(-2).lineLimit(2)
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
                // Plan 12 feedback round 3 (Will, on-device: "clicking anywhere on the note
                // should bring up the detail sheet [on iOS] (unlike the web)"): the domain LABEL
                // itself used to carry the `.highPriorityGesture` below, claiming every tap
                // across its own (fairly wide) text run — confirmed live in `testDetailSheets`'
                // own doc comment: a card compact enough that its vertical center lands on this
                // exact row backgrounds the whole app into Safari instead of presenting the
                // sheet, for ANY tap in that band, not just one deliberately aimed at the label.
                // The external-open affordance itself is real product value (web parity —
                // DESIGN.md's kicker is "domain or author handle", but a quick jump to the
                // source is a reasonable iOS-only addition) so this doesn't remove it — per this
                // fix round's own brief, "keep an explicit external-link affordance if one
                // exists (keep it, smaller)": narrowed to just a small trailing icon (same
                // "small icon, not the whole label, carries the tap" shape `DetailURLBar` already
                // uses for its own open-link affordance), so the domain TEXT is now a plain,
                // non-interactive label that participates in the outer card's whole-card tap
                // like every other inch of the card.
                HStack(spacing: 4) {
                    Text(domain.uppercased())
                        .font(StashType.microLabel())
                        .kerning(0.6)
                        .foregroundStyle(StashColor.muted)
                    // `.accessibilityAddTraits`/`.accessibilityAction` restore what a `Link`/
                    // `Button` would have given for free — VoiceOver's double-tap activation
                    // calls a raw `.highPriorityGesture` closure not at all, since that's a touch
                    // gesture, not an accessibility action.
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(StashColor.faint)
                        .highPriorityGesture(TapGesture().onEnded { openURL(url) })
                        .accessibilityAddTraits(.isButton)
                        .accessibilityLabel("Open link")
                        .accessibilityAction { openURL(url) }
                }
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

    /// Text-type inversion (step 5): `content` IS the body — editable via `CardNoteView`, same as
    /// every other type's note (web parity, `ContentItemContent.tsx`'s `.text` branch: "the words
    /// ARE the object — show them, not the AI summary"); `description` (the AI summary) shows only
    /// when there's no user content yet. Plan 9 final wave: gained `chipsRow` too (web parity —
    /// `ContentItemContent.tsx`'s text branch renders `typeChipFor(item)` unconditionally) now
    /// that `.text` earns a neutral "note" chip; previously this branch (unlike `standardBody`)
    /// never called `chipsRow` at all, which is why text cards showed no type identity until this
    /// wave.
    @ViewBuilder private var textBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            if contentPlain.isEmpty, !descriptionPlain.isEmpty {
                Text(descriptionPlain).font(StashType.body()).foregroundStyle(StashColor.muted).lineLimit(3)
            }
            CardNoteView(item: item, store: store)
            chipsRow
        }
    }

    private var standardBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !descriptionPlain.isEmpty {
                Text(descriptionPlain).font(StashType.body()).foregroundStyle(StashColor.muted).lineLimit(3)
            }
            CardNoteView(item: item, store: store)
            chipsRow
        }
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
                Text(renderTipTap(item.content)).font(StashType.body()).lineLimit(6)
            } else if !descriptionPlain.isEmpty {
                Text(descriptionPlain).font(StashType.body()).foregroundStyle(StashColor.muted).lineLimit(2)
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
    private var footer: some View {
        HStack(spacing: 8) {
            Text(Self.footerDateFormatter.string(from: item.createdAt))
                .font(StashType.meta())
                .foregroundStyle(.tertiary)
            if let chip = typeChip(for: item) { chip }
            if let label = item.attributes.location?.label, !label.isEmpty {
                locationBadge(label)
            }
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
}

// MARK: - Card note (DESIGN.md §Components "Card note", plan 14)

/// The card's own editable `content` field — an "Add a note" affordance when empty, a tappable
/// violet-ruled 5-line preview otherwise. Web reference: `src/components/cards/CardInlineNote.tsx`
/// (full inline rich editor); this is the touch adaptation the handoff doc sanctions — "a compact
/// editor sheet is a sensible touch adaptation" — opening `CardNoteEditorSheet` on tap instead of
/// expanding in place. That sheet reuses `NotesEditorModel` (`ios/Stash/Detail/NotesEditor.swift`)
/// so a rich TipTap document is only ever appended to, never flattened to plain text — exactly the
/// detail sheet's own Notes-tab contract.
///
/// Claims its own tap via `.highPriorityGesture`, not a nested `Button`: `ItemCardView` sits
/// inside `LibraryView.grid`'s own whole-card `Button` (opens the detail sheet), and this
/// codebase already established (`ItemCardView.kicker`'s external-link icon, see its own doc
/// comment) that `.highPriorityGesture` reliably wins the tap away from that ancestor `Button`
/// while a plain nested `Button` is not guaranteed to — so every interactive piece inside a card
/// uses the same technique for the same reason.
struct CardNoteView: View {
    let item: Item
    let store: ItemStore

    @State private var isEditing = false
    @State private var washOpacity: Double = 0
    @State private var showSavedBadge = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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

    var body: some View {
        Group {
            if preview.isEmpty { addNoteAffordance } else { notePreview }
        }
        .sheet(isPresented: $isEditing) {
            CardNoteEditorSheet(item: item, store: store) { saved in
                if saved { acknowledgeSave() }
            }
        }
    }

    private var addNoteAffordance: some View {
        HStack(spacing: 4) {
            Image(systemName: "plus").font(.system(size: 10, weight: .semibold))
            Text("Add a note")
        }
        .font(StashType.chip())
        .foregroundStyle(StashColor.muted)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.primary.opacity(0.04), in: Capsule())
        .contentShape(Rectangle())
        .highPriorityGesture(TapGesture().onEnded { isEditing = true })
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Add a note")
        .accessibilityAction { isEditing = true }
        .accessibilityIdentifier("card.addNote")
    }

    private var notePreview: some View {
        Text(preview)
            .font(StashType.body())
            .foregroundStyle(.primary.opacity(0.75))
            .lineLimit(5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 11)
            .padding(.vertical, 5)
            .padding(.trailing, 8)
            .background(Color.primary.opacity(0.04), in: rightRoundedShape)
            // The violet-600 fill bar (DESIGN.md: "a fill, not a stroke") — `.overlay`, not an
            // `HStack` sibling, same reasoning the retired `CardAnnotation` documented: an
            // unconstrained `Rectangle` has no intrinsic height, so it'd soak up any extra height
            // an equalized grid row proposes; `.overlay` proposes the bar the `Text`'s own already-
            // resolved frame instead.
            .overlay(alignment: .leading) {
                Rectangle().fill(StashColor.violet600).frame(width: 2)
            }
            // Save acknowledgment: violet-300 @ 0.25 fading to 0 over 450ms (static under Reduce
            // Motion — no animated fade either direction).
            .overlay {
                StashColor.violet300.opacity(washOpacity)
                    .clipShape(rightRoundedShape)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .topTrailing) { if showSavedBadge { savedBadge } }
            .contentShape(Rectangle())
            .highPriorityGesture(TapGesture().onEnded { isEditing = true })
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("Edit note")
            .accessibilityAction { isEditing = true }
            .accessibilityIdentifier("card.note")
    }

    private var savedBadge: some View {
        Label("Saved", systemImage: "checkmark")
            .labelStyle(.titleAndIcon)
            .font(StashType.chip())
            .foregroundStyle(StashColor.violet600)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color(.systemBackground), in: Capsule())
            .offset(x: 4, y: -14)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Saved")
            .accessibilityIdentifier("card.note.saved")
    }

    /// A confirmed save washes the note and shows a brief checkmark/"Saved" caption (~2s) — DESIGN.md
    /// "Card note". Reduced-motion users get the same two states with no animated transition between
    /// them (the wash appears/disappears as a hard cut instead of fading).
    @MainActor
    private func acknowledgeSave() {
        showSavedBadge = true
        washOpacity = 0.25
        if !reduceMotion {
            withAnimation(.easeOut(duration: 0.45)) { washOpacity = 0 }
        }
        Task {
            try? await Task.sleep(for: .seconds(2))
            showSavedBadge = false
            washOpacity = 0
        }
    }
}
