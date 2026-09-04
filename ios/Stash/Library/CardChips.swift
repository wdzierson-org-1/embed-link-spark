import SwiftUI
import StashKit

/// Shared pieces of the single-object card system (mirrors web `CardBits.tsx`). Anatomy on
/// every card: object zone → kicker → title (serif) → description → user's annotation (violet
/// bar) → metadata chips (leading type chip — tinted or neutral, always present — then facts) →
/// footer (date · location; plan 9 final wave dropped the footer's own type badge, now that
/// every card carries its type up in the chips row instead). The formatter functions
/// (`formatFileSizeChip`/`formatDurationChip`/`mimeExtensionLabel`) already live in StashKit's
/// `CardMetadata.swift` (Task 4) — this file holds only the SwiftUI-facing pieces.
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
            // A chip row that exceeds the card's content width must not degrade this into
            // vertical text (the same squeeze-proofing the now-deleted footer `typeBadge`
            // (ItemCardView) used to need) — the chips row's own `FlowLayout` (plan 9 final wave)
            // handles the actual overflow by wrapping instead, but each individual chip still
            // needs to hold its own single-line size within its row.
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

/// Web `LINK_FLAVOR_LABELS` (`ContentItemContent.tsx`), transcribed verbatim — `social` reads
/// "post" (the label, not the raw flavor string), everything else round-trips its own name, and
/// an unrecognized/missing flavor falls back to "link" (web's own `?? 'link'` default).
private let linkFlavorLabels: [String: String] = [
    "article": "article",
    "video": "video",
    "repo": "repo",
    "book": "book",
    "social": "post",
    "generic": "link",
]

private func linkFlavorLabel(for item: Item) -> String {
    linkFlavorLabels[item.attributes.link?.flavor ?? "generic"] ?? "link"
}

/// Plan 9 final wave: the untinted types now carry a neutral `MetaChip` in this same slot instead
/// of `nil` (DESIGN.md/web parity — `typeChipFor`'s `MetaChip` branches for `photo`/`video`/
/// `note`/link-flavor) — so the identifier that makes a chip queryable as THE card's leading type
/// chip (`card.typeChip`) is applied HERE, at the one call site that fills that grammar slot, and
/// NOT on `MetaChip` itself (reused elsewhere in the chips row — facts, duration — where that
/// identifier must not appear).
private func neutralTypeChip(_ text: String) -> some View {
    MetaChip(text: text).accessibilityIdentifier("card.typeChip")
}

/// The leading type chip for one item. Mirrors web `ContentItemContent.tsx`'s `typeChipFor` for
/// the rows DESIGN.md's type-spectrum table tints (voice/recording, document/spreadsheet,
/// screenshot) — copy kept verbatim, lowercase, matching web's own JSX literals (`TypeChip`'s
/// `text-[11px] font-medium` carries no uppercase transform) — plus, per DESIGN.md's chips
/// grammar ("always-visible type chip first ... neutral for photo / note / video / link
/// flavors"), a neutral `MetaChip` for the types that don't earn a tint: `.image` (non-
/// screenshot) reads "photo", `.video` reads "video", `.text` reads "note", `.link` reads its
/// flavor label. `.collection` (legacy, frozen design) and `.unknown` still return `nil` — the
/// collection card builds its own "N items" chip inline (`ItemCardView.collectionBody`, needs
/// `collectionCount` state this free function has no access to).
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
        if isScreenshotItem(item) {
            return AnyView(TypeChip(tint: .screenshot, systemImage: "viewfinder", text: "screenshot"))
        }
        return AnyView(neutralTypeChip("photo"))
    case .video:
        return AnyView(neutralTypeChip("video"))
    case .text:
        return AnyView(neutralTypeChip("note"))
    case .link:
        return AnyView(neutralTypeChip(linkFlavorLabel(for: item)))
    case .collection, .unknown:
        return nil
    }
}
