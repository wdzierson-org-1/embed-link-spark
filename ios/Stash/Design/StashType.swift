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
///   Book        → PPNeueMontreal-Book       (usWeightClass 350)
///   BookItalic  → PPNeueMontreal-BookItalic (350)
///   Medium      → PPNeueMontreal-Medium     (500)
///   Semibold    → PPNeueMontreal-Semibold   (600)
///
/// Plan 9 adds the one serif role DESIGN.md §Typography sanctions — the card title's "PP Editorial
/// New" — converted the same way (`/Users/will/.stash-fonttools/bin/python`, fontTools woff2→ttf,
/// see task-0-report.md):
///   Regular     → PPEditorialNew-Regular
/// Bundled in the **app target only** (`UIAppFonts` in `project.yml`'s `Stash` target) — the card
/// grid this face serves doesn't render inside the share extension, so unlike PP Neue Montreal it
/// isn't duplicated into `StashShareExtension`'s bundle.
///
/// ## Plan 16: roles, Dynamic Type, Bold Text
///
/// Text is set with a **role** — `.stashFont(.reading)` — never a raw size. Each role is a face at
/// a default (Large) size that scales with its iOS text style (`Font.custom(_:size:relativeTo:)`),
/// per DESIGN.md › Typography › iOS type roles. `stashFont` also honours Bold Text, live: SwiftUI
/// does NOT embolden bundled faces when Bold Text is on (measured on iOS 17.0 and 26.5 — identical
/// glyph widths and weight under `legibilityWeight == .bold`, while system fonts widen), so the
/// modifier reads `legibilityWeight` and draws the next heavier face (`Face.bolder`). Inside a
/// `Text` concatenation, where a view modifier can't reach one run, use
/// `Role.font(legibilityWeight)` with the view's own `@Environment(\.legibilityWeight)`.
///
/// Arbitrary sizes: `.stashFont(.custom(.medium, size: 24))` scales with the nearest text style
/// (or `relativeTo:`). The ONE non-scaling font is `StashType.decorative(_:size:)`, for
/// accessibility-hidden miniature art only. Text a person reads is never below 11 pt at the
/// default size (`.caption2`, the HIG floor): anything smaller is a picture of text —
/// `decorative` plus `accessibilityHidden(true)` — not a `.custom` role.
///
/// Markdown and TipTap text (plan 16 fix wave, measured on iOS 17.0 and 26.5): put the role on the
/// `Text` that renders the `AttributedString` — `Text(attributed).stashFont(.reading)` — and its
/// inline runs resolve against that face by themselves: `**strong**` (and TipTap bold, TipTap
/// headings) draws Semibold, `*emphasis*` (TipTap italic) Book Italic, `` `code` `` a monospaced
/// system face, both at regular weight and under Bold Text (where the rest goes Medium). No helper is
/// needed. The one trap: a role applied OUTSIDE a view whose `Text` already sets its own font is
/// dead — the inner font wins — so a markdown heading passes its role (`.readingSemibold`) into the
/// function that builds the `Text`. `***both***` draws Book Italic (no Semibold Italic is
/// bundled), and under Bold Text emphasis stays Book Italic inside Medium text (no Medium Italic).
///
/// Spacing that grows with the text: `.stashLeading(<em>, role:)` for line spacing and
/// `.stashTracking(<em>, role:)` for kerning; `Role.textStyle` / `Role.defaultSize` pair a role
/// with `@ScaledMetric(relativeTo:)` for anything else (a glyph beside a line of text).
///
/// The pre-plan-16 helpers (`body()`, `meta()`, `bodyMedium(_:)`, …) are deprecated — the build's
/// deprecation warnings are the surface passes' migration checklist. They still scale (with the
/// nearest text style) so nothing that slips through stays fixed, but they return a regular-weight
/// `Font` and can't follow Bold Text.
enum StashType {
    /// True once `PPNeueMontreal-Medium` resolves via `UIFont(name:size:)` — the cheapest single
    /// probe for "did the whole family register", since every weight ships together in the same
    /// `UIAppFonts` entry. Read by the DEBUG-only `design.fontStatus` / `share.fontStatus` labels.
    ///
    /// Cached (plan 15): every `StashType` font below consults this, and it used to run a
    /// `UIFont(name:size:)` lookup per call — i.e. per text view per render. `UIAppFonts` are
    /// registered before any app code runs, so the answer can't change for the process lifetime.
    static let isNeueMontrealAvailable: Bool = UIFont(name: "PPNeueMontreal-Medium", size: 12) != nil

    /// True once `PPEditorialNew-Regular` resolves via `UIFont(name:size:)`. App-target-only (see
    /// the type doc comment above) — always `false` in the share extension, which is fine since
    /// nothing there calls `editorialTitle()`. Read by the DEBUG-only `design.fontStatus` label.
    /// Cached for the same reason as `isNeueMontrealAvailable`.
    static let isEditorialAvailable: Bool = UIFont(name: "PPEditorialNew-Regular", size: 12) != nil

    // MARK: - Faces

    /// The four bundled PP Neue Montreal faces.
    enum Face: CaseIterable {
        case book, bookItalic, medium, semibold

        var postScriptName: String {
            switch self {
            case .book: "PPNeueMontreal-Book"
            case .bookItalic: "PPNeueMontreal-BookItalic"
            case .medium: "PPNeueMontreal-Medium"
            case .semibold: "PPNeueMontreal-Semibold"
            }
        }

        /// The face Bold Text draws instead: the next heavier bundled face. Semibold is the
        /// heaviest bundled face and Book Italic has no heavier italic, so both stay.
        var bolder: Face {
            switch self {
            case .book: .medium
            case .medium: .semibold
            case .semibold, .bookItalic: self
            }
        }

        /// The system weight the SF Pro fallback uses.
        fileprivate var systemWeight: Font.Weight {
            switch self {
            case .book, .bookItalic: .regular
            case .medium: .medium
            case .semibold: .semibold
            }
        }
    }

    // MARK: - Roles

    /// A text role — DESIGN.md › Typography › iOS type roles. Apply with `.stashFont(_:)`.
    enum Role {
        /// Semibold 32 · `.largeTitle` — marketing, empty states. Track −0.022em.
        case display
        /// Medium 28 · `.title` — the detail panel's object title. Track −0.02em.
        case panelTitle
        /// Medium 22 · `.title2` — a screen's own title (Ask's "Chat with your Stash").
        case screenTitle
        /// Medium 20 · `.title3` — card titles. Track −0.014em.
        case cardTitle
        /// Book 17 · `.body` — reading text: detail description, notes, summary, transcript; chat
        /// bubbles and the Ask composer; the Add editor; the share-sheet note; search fields.
        case reading
        /// Medium 17 · `.body` — emphasis in reading text.
        case readingMedium
        /// Semibold 17 · `.body` — headings inside reading text (markdown `##`), sheet titles.
        case readingSemibold
        /// Book Italic 17 · `.body` — the user's own words in reading text.
        case readingItalic
        /// Book 15 · `.subheadline` — supporting text: card descriptions/previews/notes, settings
        /// secondary lines, conversation previews.
        case secondary
        /// Medium 15 · `.subheadline` — emphasis in supporting text; list-row titles; pill tabs.
        case secondaryMedium
        /// Book Italic 15 · `.subheadline` — the user's own words at the supporting size (card note).
        case secondaryItalic
        /// Book 13 · `.footnote` — dates, facts, footers, status lines.
        case meta
        /// Medium 13 · `.footnote` — emphasis in meta text (fact values, a status label).
        case metaMedium
        /// Medium 12 · `.caption` — chips and badges.
        case chip
        /// Semibold 12 · `.caption` — section micro-labels (caps, +0.11em). See `stashMicroLabel`.
        case microLabel
        /// Semibold 12 · `.caption` — kickers / eyebrows (caps, +0.10em). See `stashKicker`.
        case kicker
        /// Book 17 · `.body` — plain text buttons: the keyboard Cancel (`StashCancelButton`) and
        /// other secondary text actions in chrome.
        case textButton
        /// Medium 17 · `.body` — the one primary text action on a screen (the share sheet's Save,
        /// a Done) and the label of a filled primary button.
        case textButtonProminent
        /// Medium 15 · `.subheadline` — inline text actions inside content ("Retry", "Copy link",
        /// "Show all"). Never smaller than this.
        case inlineButton
        /// System monospace (DESIGN.md "ui-monospace") at `style`'s size — format/size chips,
        /// file names, URLs, timers. Map old point sizes to the nearest style: 10–11 →
        /// `.caption2`, 11.5–12 → `.caption`, 12.5–13 → `.footnote`, 15 → `.subheadline`,
        /// 28 → `.title`, 34 → `.largeTitle`. Bold Text is SwiftUI's own here (a system font).
        case mono(Font.TextStyle)
        /// `face` at an arbitrary default size, scaled like `relativeTo` — by default the nearest
        /// text style for `size` (`StashType.nearestTextStyle(for:)`). For the few places the
        /// named roles don't cover; prefer a named role. Readable text: `size` ≥ 11 — smaller is
        /// decorative art (`StashType.decorative`, accessibility-hidden).
        case custom(Face, size: CGFloat, relativeTo: Font.TextStyle? = nil)

        /// This role's font: the scaled face, or the next heavier face when `legibilityWeight` is
        /// `.bold` (the Bold Text setting). For a run inside a `Text` concatenation; everywhere
        /// else use `.stashFont(_:)`, which reads `legibilityWeight` for you and stays live.
        func font(_ legibilityWeight: LegibilityWeight?) -> Font {
            if case .mono(let style) = self {
                return .system(style, design: .monospaced)
            }
            let (face, size, style) = metrics
            return StashType.scaled(legibilityWeight == .bold ? face.bolder : face, size: size, relativeTo: style)
        }

        /// The text style this role scales with — for `@ScaledMetric(relativeTo:)` sizes that
        /// should grow with this text (a glyph or a gap beside it).
        var textStyle: Font.TextStyle { metrics.2 }

        /// This role's size at the default (Large) text size, in points — the size DESIGN.md's
        /// table gives it, and the base `stashLeading` / `stashTracking` scale from. `mono(style)`
        /// is the style's own default size.
        var defaultSize: CGFloat {
            if case .mono(let style) = self { return StashType.defaultSize(of: style) }
            return metrics.1
        }

        /// Face, default (Large) size and scaling text style. `mono` never reaches here.
        private var metrics: (Face, CGFloat, Font.TextStyle) {
            switch self {
            case .display: (.semibold, 32, .largeTitle)
            case .panelTitle: (.medium, 28, .title)
            case .screenTitle: (.medium, 22, .title2)
            case .cardTitle: (.medium, 20, .title3)
            case .reading: (.book, 17, .body)
            case .readingMedium: (.medium, 17, .body)
            case .readingSemibold: (.semibold, 17, .body)
            case .readingItalic: (.bookItalic, 17, .body)
            case .secondary: (.book, 15, .subheadline)
            case .secondaryMedium: (.medium, 15, .subheadline)
            case .secondaryItalic: (.bookItalic, 15, .subheadline)
            case .meta: (.book, 13, .footnote)
            case .metaMedium: (.medium, 13, .footnote)
            case .chip: (.medium, 12, .caption)
            case .microLabel, .kicker: (.semibold, 12, .caption)
            case .textButton: (.book, 17, .body)
            case .textButtonProminent: (.medium, 17, .body)
            case .inlineButton: (.medium, 15, .subheadline)
            case .mono(let style): (.book, 17, style)
            case let .custom(face, size, relativeTo): (face, size, relativeTo ?? StashType.nearestTextStyle(for: size))
            }
        }
    }

    /// `face` at `size` (Large), scaled like `style`. When the bundled family didn't register, the
    /// fallback is SF Pro at `style` itself — it scales and follows Bold Text on its own, at the
    /// style's default size rather than `size` (a registration failure is a bug to fix, not a look).
    private static func scaled(_ face: Face, size: CGFloat, relativeTo style: Font.TextStyle) -> Font {
        guard isNeueMontrealAvailable else {
            let fallback = Font.system(style, weight: face.systemWeight)
            return face == .bookItalic ? fallback.italic() : fallback
        }
        return .custom(face.postScriptName, size: size, relativeTo: style)
    }

    /// The text style whose default (Large) size is nearest `size` — how arbitrary sizes and the
    /// deprecated helpers pick their scaling curve. Headline is skipped (same size and curve as
    /// body); a tie goes to the larger style.
    static func nearestTextStyle(for size: CGFloat) -> Font.TextStyle {
        switch size {
        case 31...: .largeTitle       // 34
        case 25..<31: .title          // 28
        case 21..<25: .title2         // 22
        case 18.5..<21: .title3       // 20
        case 16.5..<18.5: .body       // 17
        case 15.5..<16.5: .callout    // 16
        case 14..<15.5: .subheadline  // 15
        case 12.5..<14: .footnote     // 13
        case 11.5..<12.5: .caption    // 12
        default: .caption2            // 11
        }
    }

    /// Apple's default (Large) point size for `style` — SF's own sizes, which the roles follow.
    static func defaultSize(of style: Font.TextStyle) -> CGFloat {
        switch style {
        case .largeTitle: 34
        case .title: 28
        case .title2: 22
        case .title3: 20
        case .headline, .body: 17
        case .callout: 16
        case .subheadline: 15
        case .footnote: 13
        case .caption: 12
        case .caption2: 11
        default: 17
        }
    }

    // MARK: - Decorative (the one fixed size)

    /// A FIXED-size font for decorative art only — the miniature illustrations and plates that
    /// draw text or glyphs at a set scale (onboarding step art, card-plate miniatures, the share
    /// sheet's file tile). It never scales and never follows Bold Text, so the view that uses it
    /// must be `accessibilityHidden(true)` (or sit inside a container that is): it's a picture of
    /// text, not text. Anything a person reads to use the app takes a role instead. Works for SF
    /// Symbol glyph art too — the symbol takes the face's size and weight.
    static func decorative(_ face: Face, size: CGFloat) -> Font {
        guard isNeueMontrealAvailable else {
            let fallback = Font.system(size: size, weight: face.systemWeight)
            return face == .bookItalic ? fallback.italic() : fallback
        }
        return .custom(face.postScriptName, fixedSize: size)
    }

    // MARK: - Deprecated (plan 16) — Task 5 deletes these

    /// Pre-plan-16 helpers at their old sizes, scaled with the nearest text style.
    private static func legacy(_ face: Face, size: CGFloat) -> Font {
        scaled(face, size: size, relativeTo: nearestTextStyle(for: size))
    }

    @available(*, deprecated, message: "plan 16: use .stashFont(.panelTitle) — follows Bold Text")
    static func panelTitle() -> Font { Role.panelTitle.font(nil) }

    @available(*, deprecated, message: "plan 16: use .stashFont(.display) — follows Bold Text")
    static func display() -> Font { Role.display.font(nil) }

    @available(*, deprecated, message: "plan 16: use .stashFont(.cardTitle) — follows Bold Text")
    static func cardTitle() -> Font { Role.cardTitle.font(nil) }

    @available(*, deprecated, message: "plan 16: use .stashFont(.meta) (13 pt dates, facts, footers) — follows Bold Text")
    static func meta() -> Font { Role.meta.font(nil) }

    @available(*, deprecated, message: "plan 16: use .stashFont(.chip) — follows Bold Text")
    static func chip() -> Font { Role.chip.font(nil) }

    @available(*, deprecated, message: "plan 16: use .stashMicroLabel() (font + caps + tracking + colour) or .stashFont(.microLabel)")
    static func microLabel() -> Font { Role.microLabel.font(nil) }

    @available(*, deprecated, message: "plan 16: use .stashKicker() (font + caps + tracking + colour) or .stashFont(.kicker)")
    static func kicker() -> Font { Role.kicker.font(nil) }

    @available(*, deprecated, message: "plan 16: use .stashFont(.reading) (17 pt reading text) or .stashFont(.secondary) (15 pt supporting text)")
    static func body() -> Font { legacy(.book, size: 14) }

    @available(*, deprecated, message: "plan 16: use .stashFont(.readingMedium) 17 / .secondaryMedium 15 / .metaMedium 13 / .chip 12 / .textButtonProminent, or .custom(.medium, size:)")
    static func bodyMedium(_ size: CGFloat = 14) -> Font { legacy(.medium, size: size) }

    @available(*, deprecated, message: "plan 16: use .stashFont(.readingSemibold) 17, or .custom(.semibold, size:)")
    static func bodySemibold(_ size: CGFloat = 14) -> Font { legacy(.semibold, size: size) }

    @available(*, deprecated, message: "plan 16: use .stashFont(.readingItalic) 17 or .stashFont(.secondaryItalic) 15")
    static func bodyItalic() -> Font { legacy(.bookItalic, size: 14) }

    @available(*, deprecated, message: "plan 16: use .stashFont(.mono(<text style>)) — 10–11 → .caption2, 11.5–12 → .caption, 12.5–13 → .footnote, 15 → .subheadline, 28 → .title, 34 → .largeTitle")
    static func mono(_ size: CGFloat = 11) -> Font { .system(nearestTextStyle(for: size), design: .monospaced) }

    @available(*, deprecated, message: "plan 16: use .stashFont(.screenTitle) for 22 pt, else .stashFont(.custom(.medium, size:)) — or StashType.decorative(.medium, size:) for accessibility-hidden art")
    static func medium(size: CGFloat) -> Font { legacy(.medium, size: size) }

    @available(*, deprecated, message: "plan 16: use .stashFont(.custom(.semibold, size:)) — or StashType.decorative(.semibold, size:) for accessibility-hidden art")
    static func semibold(size: CGFloat) -> Font { legacy(.semibold, size: size) }

    @available(*, deprecated, message: "plan 16: use a role (.stashFont(.meta) 13, .secondary 15, .reading 17) or .stashFont(.custom(.book, size:)) — or StashType.decorative(.book, size:) for accessibility-hidden art")
    static func regular(size: CGFloat) -> Font { legacy(.book, size: size) }

    /// Plan 9's serif card title ("PP Editorial New" 400 · 20), unused since plan 14 moved card
    /// titles to Montreal medium (`Role.cardTitle`). The face stays bundled in the app target; a
    /// future serif moment gets a proper role then. Scales with `.title3` meanwhile.
    @available(*, deprecated, message: "plan 16: unused since plan 14 — card titles are .stashFont(.cardTitle); a future serif use gets its own role")
    static func editorialTitle() -> Font {
        isEditorialAvailable ? .custom("PPEditorialNew-Regular", size: 20, relativeTo: .title3) : .system(.title3, design: .serif)
    }
}

// MARK: - Applying roles

/// Reads `legibilityWeight` (the Bold Text setting) so a toggle redraws the text in the right face
/// at once — no rebuild of the view tree, no lost drafts or navigation.
private struct StashRoleFont: ViewModifier {
    let role: StashType.Role
    @Environment(\.legibilityWeight) private var legibilityWeight

    func body(content: Content) -> some View {
        content.font(role.font(legibilityWeight))
    }
}

extension View {
    /// Sets a StashType role (DESIGN.md › Typography › iOS type roles): its face at its Dynamic
    /// Type–scaled size, and the next heavier face while Bold Text is on — live. Like `.font`, it
    /// applies to every text view inside.
    func stashFont(_ role: StashType.Role) -> some View {
        modifier(StashRoleFont(role: role))
    }

    /// A section micro-label (DESIGN.md): Semibold 12 (`.caption`), caps, +0.11em, `muted` unless
    /// told otherwise — the whole recipe in one call. Pass the text in its natural case.
    /// `.textCase(.uppercase)` draws the caps and reaches the accessibility label too: the
    /// onboarding kicker "Step 1" is labelled "STEP 1", as the all-caps literal it replaced was.
    /// VoiceOver reads a word like that as a word, so nothing is lost; a label that has to read
    /// differently needs its own `.accessibilityLabel`. The colour is set here, so a later
    /// `.foregroundStyle` can't change it — pass it instead.
    func stashMicroLabel(_ color: Color = StashColor.muted) -> some View {
        stashFont(.microLabel)
            .textCase(.uppercase)
            .stashTracking(0.11, role: .microLabel)
            .foregroundStyle(color)
    }

    /// A kicker / eyebrow (DESIGN.md): Semibold 12 (`.caption`), caps, +0.10em, `muted` unless told
    /// otherwise. Same rules as `stashMicroLabel`.
    func stashKicker(_ color: Color = StashColor.muted) -> some View {
        stashFont(.kicker)
            .textCase(.uppercase)
            .stashTracking(0.10, role: .kicker)
            .foregroundStyle(color)
    }

    /// Kerning for text set in `role`, as an em fraction of the role's default (Large) size —
    /// DESIGN.md's letter-spacing tokens as written: `.stashTracking(-0.014, role: .cardTitle)`,
    /// `.stashTracking(0.11, role: .microLabel)`. The kerning is that many points at every text
    /// size, so it tightens in em terms as the text grows, as Apple's own tracking does.
    func stashTracking(_ em: CGFloat, role: StashType.Role) -> some View {
        kerning(em * role.defaultSize)
    }

    /// `stashTracking(_:role:)` with the size by hand — prefer the role overload, which can't be
    /// handed a stale size (the pre-plan-16 call sites pass 11 for what is now a 12 pt role).
    func stashTracking(_ em: CGFloat, size: CGFloat) -> some View {
        kerning(em * size)
    }

    /// Line spacing for text set in `role`: `em` × the role's size, scaled with the role's text
    /// style like the text itself, so paragraphs keep their proportions as text grows (a fixed
    /// `lineSpacing` shrinks to nothing). `em` is the gap on top of the face's own line, and Neue
    /// Montreal's line is 1.2 em, so CSS `line-height` ≈ 1.2 + `em`: the detail sheet's reading
    /// text, `.stashLeading(0.55, role: .reading)`, is ≈ 1.75 — 9.35 pt at Large, 12.1 at xxxLarge —
    /// and Ask's 0.35 is ≈ 1.55. It replaces every `lineSpacing(14 * …)`.
    ///
    /// At the accessibility sizes the gap tapers: it's capped at 0.35 em — 12.95 pt for reading text
    /// at AX3, where 0.55 em was 20.35, so a line's pitch goes from 1.75 to 1.55 em (measured on the
    /// detail sheet). A line there holds two to four words, so the eye's return sweep is short and
    /// extra leading mostly costs scrolling; Apple's own text styles taper the same way (body
    /// leading ÷ size 1.29 at Large, 1.175 at AX3). Large to xxxLarge are unchanged, and a gap of
    /// 0.35 em or less (Ask's bubbles) never changes.
    func stashLeading(_ em: CGFloat, role: StashType.Role) -> some View {
        modifier(StashLeading(em: em, role: role))
    }
}

/// `stashLeading`: two `@ScaledMetric`s built from the role's own size and text style — the gap,
/// and the gap capped at `accessibilityCap` for the accessibility sizes.
private struct StashLeading: ViewModifier {
    /// The largest gap at the accessibility sizes, in em (see `stashLeading`).
    static let accessibilityCap: CGFloat = 0.35

    @ScaledMetric private var spacing: CGFloat
    @ScaledMetric private var accessibilitySpacing: CGFloat
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(em: CGFloat, role: StashType.Role) {
        _spacing = ScaledMetric(wrappedValue: em * role.defaultSize, relativeTo: role.textStyle)
        _accessibilitySpacing = ScaledMetric(wrappedValue: min(em, Self.accessibilityCap) * role.defaultSize,
                                             relativeTo: role.textStyle)
    }

    func body(content: Content) -> some View {
        content.lineSpacing(dynamicTypeSize.isAccessibilitySize ? accessibilitySpacing : spacing)
    }
}
