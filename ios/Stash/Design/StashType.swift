import SwiftUI
import UIKit

/// Typography per DESIGN.md §Typography: PP Neue Montreal (Book/BookItalic/Medium/Semibold),
/// bundled as TTFs in both the app and share-extension targets (an appex can't read the host
/// bundle — each target lists `UIAppFonts` and carries its own copy of `Design/Fonts`). Falls
/// back to SF Pro only if the face fails to register, so the UI never crashes or blanks out on a
/// bad `Info.plist` font entry — it just looks like SF Pro until the bundling is fixed.
///
/// Font weight → PostScript name (recorded from each TTF's `name` table ID 6 after the lossless
/// woff2 → ttf conversion — see docs/superpowers/sdd/2026-09-03-ios-plan-7-design-consolidation/
/// task-2-report.md):
///   Book        → PPNeueMontreal-Book
///   BookItalic  → PPNeueMontreal-BookItalic
///   Medium      → PPNeueMontreal-Medium
///   Semibold    → PPNeueMontreal-Semibold
///
/// Plan 9 adds the one serif role DESIGN.md §Typography sanctions — the card title's "PP Editorial
/// New" — converted the same way (`/Users/will/.stash-fonttools/bin/python`, fontTools woff2→ttf,
/// see task-0-report.md):
///   Regular     → PPEditorialNew-Regular
/// Bundled in the **app target only** (`UIAppFonts` in `project.yml`'s `Stash` target) — the card
/// grid this face serves doesn't render inside the share extension, so unlike PP Neue Montreal it
/// isn't duplicated into `StashShareExtension`'s bundle.
enum StashType {
    /// True once `PPNeueMontreal-Medium` resolves via `UIFont(name:size:)` — the cheapest single
    /// probe for "did the whole family register", since every weight ships together in the same
    /// `UIAppFonts` entry. Read by the DEBUG-only `design.fontStatus` / `share.fontStatus` labels.
    static var isNeueMontrealAvailable: Bool {
        UIFont(name: "PPNeueMontreal-Medium", size: 12) != nil
    }

    /// True once `PPEditorialNew-Regular` resolves via `UIFont(name:size:)`. App-target-only (see
    /// the type doc comment above) — always `false` in the share extension, which is fine since
    /// nothing there calls `editorialTitle()`. Read by the DEBUG-only `design.fontStatus` label.
    static var isEditorialAvailable: Bool {
        UIFont(name: "PPEditorialNew-Regular", size: 12) != nil
    }

    private static func custom(_ psName: String, size: CGFloat, weight: Font.Weight) -> Font {
        isNeueMontrealAvailable ? .custom(psName, size: size) : .system(size: size, weight: weight)
    }

    /// Object title (panel): 500 · 28 / 1.2 · −0.02em (tracking applied via `.stashTracking`).
    static func panelTitle() -> Font { custom("PPNeueMontreal-Medium", size: 28, weight: .medium) }

    /// Display header (marketing, empty states): 600 · 32 · −0.022em (DESIGN.md tracking token;
    /// applied by callers via `.stashTracking(-0.022, size: 32)`, same pattern as `panelTitle()`).
    static func display() -> Font { custom("PPNeueMontreal-Semibold", size: 32, weight: .semibold) }

    /// Body / description: 400 · 14.
    static func body() -> Font { custom("PPNeueMontreal-Book", size: 14, weight: .regular) }

    /// Body at Medium weight (500) — for callers that need a bolder body-sized face than
    /// `.fontWeight(.semibold)` over the Book face can reliably synthesize (a fixed-weight custom
    /// font may not bolden). Default size matches `body()`; callers may override.
    static func bodyMedium(_ size: CGFloat = 14) -> Font { custom("PPNeueMontreal-Medium", size: size, weight: .medium) }

    /// Body at Semibold weight (600) — same reasoning as `bodyMedium`, for heading-weight body
    /// text (e.g. `MarkdownBlocksView`'s `##` headings, the panel title's field label).
    static func bodySemibold(_ size: CGFloat = 14) -> Font { custom("PPNeueMontreal-Semibold", size: size, weight: .semibold) }

    /// User annotation: 400 italic · 14.
    static func bodyItalic() -> Font {
        isNeueMontrealAvailable ? .custom("PPNeueMontreal-BookItalic", size: 14) : .system(size: 14, weight: .regular).italic()
    }

    /// Micro-label (section headers): 600 · 11 — caller uppercases the text and applies
    /// `.stashTracking(0.11, size: 11)`.
    static func microLabel() -> Font { custom("PPNeueMontreal-Semibold", size: 11, weight: .semibold) }

    /// Kicker / eyebrow: 600 · 11 caps · +0.10em — same face as `microLabel`, distinct tracking.
    static func kicker() -> Font { custom("PPNeueMontreal-Semibold", size: 11, weight: .semibold) }

    /// Chip: 500 · 11.
    static func chip() -> Font { custom("PPNeueMontreal-Medium", size: 11, weight: .medium) }

    /// Date / meta: 400 · 12.
    static func meta() -> Font { custom("PPNeueMontreal-Book", size: 12, weight: .regular) }

    /// Mono chip variant (DESIGN.md: "ui-monospace 10–11.5") — system monospace, no bundled face.
    static func mono(_ size: CGFloat = 11) -> Font { .system(size: size, weight: .regular, design: .monospaced) }

    /// Medium weight (500) at an arbitrary size — for callers that need the Medium face at a size
    /// none of the fixed-size helpers above cover (e.g. `AskView`'s 22pt panel-style title). Same
    /// `isNeueMontrealAvailable` gate as every other helper here.
    static func medium(size: CGFloat) -> Font { custom("PPNeueMontreal-Medium", size: size, weight: .medium) }

    /// Semibold weight (600) at an arbitrary size — the `medium(size:)` counterpart for callers
    /// that need the Semibold face at a size none of the fixed-size helpers above cover.
    static func semibold(size: CGFloat) -> Font { custom("PPNeueMontreal-Semibold", size: size, weight: .semibold) }

    /// Book weight (400) at an arbitrary size — the `medium(size:)`/`semibold(size:)` counterpart
    /// for callers that need the plain Book face at a size none of the fixed-size helpers above
    /// (`body()`, `meta()`, `chip()`) cover exactly (final wave's typography sweep: card-plate
    /// micro-copy, chip labels, etc. that were previously bare `.system(size:)`).
    static func regular(size: CGFloat) -> Font { custom("PPNeueMontreal-Book", size: size, weight: .regular) }

    /// Object title (card) — DESIGN.md's single serif role: "PP Editorial New" 400 · 20 / tight ·
    /// 2-line clamp. Gated on `isEditorialAvailable` (not `isNeueMontrealAvailable` — a separate
    /// TTF, registered or not independently of the Neue Montreal family), falling back to
    /// `.system(size: 20, design: .serif)` so a card title never blanks or crashes if the face
    /// fails to load. Callers apply DESIGN.md's "tight" line spacing themselves, e.g.
    /// `.lineSpacing(-1)` / a small negative `.kerning` per their own multi-line clamp treatment —
    /// this helper only returns the `Font`, not layout modifiers.
    static func editorialTitle() -> Font {
        isEditorialAvailable ? .custom("PPEditorialNew-Regular", size: 20) : .system(size: 20, design: .serif)
    }
}

extension View {
    /// Kerning expressed as an em fraction of `size`, matching the web's letter-spacing tokens
    /// (e.g. DESIGN.md's `+0.11em` micro-label tracking becomes `stashTracking(0.11, size: 11)`).
    func stashTracking(_ em: CGFloat, size: CGFloat) -> some View {
        kerning(em * size)
    }
}
