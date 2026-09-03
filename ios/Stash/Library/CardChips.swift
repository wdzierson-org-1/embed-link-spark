import SwiftUI
import StashKit

/// Shared pieces of the single-object card system (mirrors web `CardBits.tsx`). Anatomy on
/// every card: object zone → kicker → title (serif) → description → user's annotation (violet
/// bar) → metadata chips → footer (date · location · type badge). The formatter functions
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
