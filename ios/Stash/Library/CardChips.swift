import SwiftUI
import StashKit

/// Shared pieces of the single-object card system (mirrors web `CardBits.tsx`). Anatomy on
/// every card: object zone → kicker → title (serif) → description → user's annotation (violet
/// bar) → metadata chips (leading tinted type chip, then neutral facts) → footer (date ·
/// location · type badge). The formatter functions (`formatFileSizeChip`/`formatDurationChip`/
/// `mimeExtensionLabel`) already live in StashKit's `CardMetadata.swift` (Task 4) — this file
/// holds only the SwiftUI-facing pieces.
enum CardHeroHeight {
    /// Landscape imagery, plates — every populated hero zone that isn't `.tall`.
    static let standard: CGFloat = 160
    /// Portrait media, contained link covers (video/book).
    static let tall: CGFloat = 224
}

/// Tailwind-matched accents used across the plates/annotation (no design-token asset for these
/// yet — see `docs/superpowers/specs/2026-08-16-single-object-items-design.md`).
extension Color {
    /// violet-300 — `CardAnnotation`'s leading bar.
    static let cardAnnotationBar = Color(red: 0.769, green: 0.710, blue: 0.992)
    /// violet-600 — favicon-plate letter + image file-plate icon.
    static let cardVioletAccent = Color(red: 0.486, green: 0.227, blue: 0.929)
    /// violet-100/50 — favicon/image-file-plate icon backgrounds.
    static let cardVioletTint = Color(red: 0.929, green: 0.914, blue: 0.996)
    /// red-500 — document file-plate icon.
    static let cardRedAccent = Color(red: 0.937, green: 0.267, blue: 0.267)
    /// red-50 — document file-plate icon background.
    static let cardRedTint = Color(red: 0.996, green: 0.949, blue: 0.949)
}

/// A small pill-shaped metadata chip. `mono` is for the raw-filename chip; everything else
/// (facts, duration) reads as plain text, matching `MetaChip.tsx`'s `mono?` prop.
struct MetaChip: View {
    var mono = false
    let text: String

    var body: some View {
        Text(text)
            .font(mono ? StashType.mono(10) : StashType.chip())
            .lineLimit(1)
            .truncationMode(.middle)
            .foregroundStyle(StashColor.muted)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.primary.opacity(0.04), in: Capsule())
    }
}

/// The user's own words — always visually distinct from extracted/AI text via a violet leading
/// bar, never confused with `description` (the object's own text) above it.
struct CardAnnotation: View {
    let text: String
    var lineLimit = 2

    var body: some View {
        // `.overlay`, not an `HStack` sibling: an unconstrained `Rectangle` has no intrinsic
        // height, so as an HStack child it's the one flexible view and soaks up any extra
        // height the row proposes (this card's grid row is equalized to its tallest sibling —
        // Task 6b's row-major note), stretching the bar far past the 1-2 lines of text beside
        // it. `.overlay` proposes the bar the base `Text`'s OWN already-resolved frame instead.
        Text(text)
            .font(StashType.body())
            .foregroundStyle(.primary.opacity(0.75))
            .lineLimit(lineLimit)
            .padding(.leading, 11)
            .overlay(alignment: .leading) {
                Rectangle().fill(Color.cardAnnotationBar).frame(width: 2)
            }
    }
}

/// `TYPE · SIZE` join shared by file plates and the metadata-chips row's facts chip — nil when
/// neither half has data, single-half when only one does (matches `ContentItemContent.tsx`'s
/// `[mimeExtensionLabel, formatFileSizeChip].filter(Boolean).join(' · ')`).
func factsLine(mime: String?, size: Int?) -> String? {
    let parts = [mimeExtensionLabel(mime), formatFileSizeChip(size)].compactMap { $0 }
    return parts.isEmpty ? nil : parts.joined(separator: " · ")
}

// MARK: - Type-spectrum chip (DESIGN.md §Components "Chips grammar" + §Color "Type spectrum")

/// The always-visible leading type chip — "tinted type chip (always visible — replaces any
/// hover-only type badge)", DESIGN.md's first chips-grammar element. Reads its tint/text color
/// from Task 0's `StashColor.typeField`/`typeText` (the same pair every type-tinted plate below
/// reads), so a chip and its plate (where one exists) always agree. Distinct from `MetaChip`
/// (neutral, untinted facts) — this one carries the object's *type* identity, matching web
/// `CardBits.tsx`'s `TypeChip`.
struct TypeChip: View {
    let tint: StashColor.TypeTint
    let systemImage: String
    let text: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .labelStyle(.titleAndIcon)
            .font(StashType.chip())
            // Same squeeze-proofing as the footer's `typeBadge` (ItemCardView) — a chip row that
            // exceeds the card's content width must not degrade this into vertical text.
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(StashColor.typeText(tint))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(StashColor.typeField(tint), in: Capsule())
            // Same HStack-identifier-collision fix as `ItemCardView.locationBadge`/`CaptureComposerView
            // .pinPreview` (Task 6/9 findings): a bare `Label`'s icon and text independently inherit
            // `card.typeChip` without this, and an XCUITest query for it returns "multiple matching
            // elements" instead of the one element the anatomy smoke expects.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(text)
            .accessibilityIdentifier("card.typeChip")
    }
}

/// Voice note vs. long recording — mirrors web `audioSubtype` (`CardBits.tsx`). Web reads
/// `attributes.media.kind` first and only falls back to a duration threshold when that's absent;
/// StashKit's `MediaAttributes` (`Models/ItemAttributes.swift`) has no `kind` field yet — an
/// unrecognized key nested inside a known `attributes` sub-object is dropped, not preserved (that
/// file's own doc comment) — so this build always takes web's fallback branch: under ten minutes
/// reads as a voice note, at or over ten minutes as a recording.
func audioSubtype(_ item: Item) -> StashColor.TypeTint {
    let duration = item.attributes.media?.durationS ?? 0
    return duration >= 600 ? .audio : .voice
}

/// Screenshot vs. plain photo — mirrors web `isScreenshotItem` (`CardBits.tsx`). Same
/// `attributes.media.kind` gap as `audioSubtype` above (the enrichment-written `kind` never
/// survives StashKit's decode), so this always takes web's other signal: the vision-written
/// title's own words.
func isScreenshotItem(_ item: Item) -> Bool {
    item.title?.hasPrefix("Screenshot of") ?? false
}

/// `document`'s spreadsheet-vs-generic split — mirrors web `isSpreadsheetExt` (`CardBits.tsx`).
func isSpreadsheetExt(_ ext: String?) -> Bool {
    ext == "XLSX" || ext == "XLS" || ext == "CSV"
}

/// The leading type chip for one item, or `nil` when its type doesn't earn one. Mirrors web
/// `ContentItemContent.tsx`'s `typeChipFor` for the rows DESIGN.md's type-spectrum table tints
/// (voice/recording, document/spreadsheet, screenshot) — copy kept verbatim, lowercase, matching
/// web's own JSX literals (`TypeChip`'s `text-[11px] font-medium` carries no uppercase transform).
/// `.image` (non-screenshot), `.video`, and `.link` get no chip here: DESIGN.md "Photos, videos,
/// and link covers use real imagery — no field, no tint" — web's own `typeChipFor` renders those
/// three as an untinted `MetaChip` (or nothing), never a tinted `TypeChip`; same for a `.link`
/// item whose flavor happens to be `social` — the type-spectrum table's "social post" row has no
/// live call site on web yet either (`CHIP_TINTS.social` is declared, never read), so this doesn't
/// invent one.
func typeChip(for item: Item) -> AnyView? {
    switch item.type {
    case .audio:
        let subtype = audioSubtype(item)
        return AnyView(TypeChip(tint: subtype,
                                 systemImage: subtype == .voice ? "mic.fill" : "waveform",
                                 text: subtype == .voice ? "voice note" : "recording"))
    case .document:
        let ext = mimeExtensionLabel(item.mimeType)
        if isSpreadsheetExt(ext) {
            return AnyView(TypeChip(tint: .document, systemImage: "tablecells", text: "spreadsheet"))
        }
        return AnyView(TypeChip(tint: .document, systemImage: "doc.fill", text: ext?.lowercased() ?? "document"))
    case .image:
        guard isScreenshotItem(item) else { return nil }
        return AnyView(TypeChip(tint: .screenshot, systemImage: "viewfinder", text: "screenshot"))
    case .text, .link, .video, .collection, .unknown:
        return nil
    }
}
