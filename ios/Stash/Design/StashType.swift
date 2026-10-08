import SwiftUI
import UIKit

/// V2's three voices, bundled in the app and share extension: Montreal for human
/// words, Departure Mono for short machine labels, JetBrains Mono for literal strings.
/// Every readable role scales with Dynamic Type. Native reading and action sizes remain
/// 17/15 pt; the web's compact 15/14 pt reading scale is not imposed on the phone.
enum StashType {
    static let isNeueMontrealAvailable = UIFont(name: "PPNeueMontreal-Medium", size: 12) != nil
    static let isDepartureMonoAvailable = UIFont(name: "DepartureMono-Regular", size: 11) != nil
    static let isJetBrainsMonoAvailable = UIFont(name: "JetBrainsMono-Regular", size: 13) != nil
    /// Legacy registration probe only. No v2 role renders this retired face.
    static let isEditorialAvailable = UIFont(name: "PPEditorialNew-Regular", size: 12) != nil

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

        /// Bold Text uses a heavier bundled face. Italic and Semibold have no heavier face.
        var bolder: Face {
            switch self {
            case .book: .medium
            case .medium: .semibold
            case .semibold, .bookItalic: self
            }
        }

        fileprivate var systemWeight: Font.Weight {
            switch self {
            case .book, .bookItalic: .regular
            case .medium: .medium
            case .semibold: .semibold
            }
        }
    }

    enum Role {
        case display
        case panelTitle
        case screenTitle
        case cardTitle
        case reading, readingMedium, readingSemibold, readingItalic
        case secondary, secondaryMedium, secondaryItalic
        /// Short machine strings: metadata, facts, dates, chips, section labels and status.
        case meta, metaMedium, chip, microLabel, kicker
        case textButton, textButtonProminent, inlineButton
        /// Departure Mono's native 11 pt grid, scaled with accessibility settings.
        case machine, machineLarge, machineDisplay
        /// Literal strings such as URLs, commands, handles and file names. `mono` is kept
        /// source-compatible and resolves to the same JetBrains regular/medium code voice.
        case mono(Font.TextStyle)
        case code(Font.TextStyle)
        case codeMedium(Font.TextStyle)
        case custom(Face, size: CGFloat, relativeTo: Font.TextStyle? = nil)

        func font(_ legibilityWeight: LegibilityWeight?) -> Font {
            if isMachine {
                guard StashType.isDepartureMonoAvailable else {
                    return .system(textStyle, design: .monospaced)
                }
                // The machine family has one weight; like Montreal's heaviest face it
                // stays itself under Bold Text instead of swapping to an unrelated face.
                return .custom("DepartureMono-Regular", size: defaultSize, relativeTo: textStyle)
            }
            switch self {
            case .mono(let style), .code(let style):
                return StashType.codeFont(style: style, medium: legibilityWeight == .bold)
            case .codeMedium(let style):
                return StashType.codeFont(style: style, medium: true)
            default:
                let (face, size, style) = metrics
                return StashType.scaled(legibilityWeight == .bold ? face.bolder : face,
                                        size: size, relativeTo: style)
            }
        }

        var textStyle: Font.TextStyle { metrics.2 }
        var defaultSize: CGFloat { metrics.1 }

        var isMachine: Bool {
            switch self {
            case .machine, .machineLarge, .machineDisplay, .meta, .metaMedium, .chip, .microLabel, .kicker: true
            default: false
            }
        }

        private var metrics: (Face, CGFloat, Font.TextStyle) {
            switch self {
            case .display: (.medium, 36, .largeTitle)
            case .panelTitle, .screenTitle: (.medium, 28, .largeTitle)
            case .cardTitle: (.medium, 18, .headline)
            case .reading: (.book, 17, .body)
            case .readingMedium: (.medium, 17, .body)
            case .readingSemibold: (.semibold, 17, .body)
            case .readingItalic: (.bookItalic, 17, .body)
            case .secondary: (.book, 15, .subheadline)
            case .secondaryMedium: (.medium, 15, .subheadline)
            case .secondaryItalic: (.bookItalic, 15, .subheadline)
            case .meta, .metaMedium, .chip, .microLabel, .kicker, .machine: (.book, 11, .caption2)
            case .machineLarge: (.book, 16.5, .callout)
            case .machineDisplay: (.book, 22, .title2)
            case .textButton: (.book, 17, .body)
            case .textButtonProminent: (.medium, 17, .body)
            case .inlineButton: (.medium, 15, .subheadline)
            case .mono(let style), .code(let style), .codeMedium(let style):
                (.book, StashType.defaultSize(of: style), style)
            case let .custom(face, size, relativeTo):
                (face, size, relativeTo ?? StashType.nearestTextStyle(for: size))
            }
        }
    }

    private static func scaled(_ face: Face, size: CGFloat, relativeTo style: Font.TextStyle) -> Font {
        guard isNeueMontrealAvailable else {
            let fallback = Font.system(style, weight: face.systemWeight)
            return face == .bookItalic ? fallback.italic() : fallback
        }
        return .custom(face.postScriptName, size: size, relativeTo: style)
    }

    private static func codeFont(style: Font.TextStyle, medium: Bool) -> Font {
        guard isJetBrainsMonoAvailable else {
            return .system(style, design: .monospaced).weight(medium ? .medium : .regular)
        }
        return .custom(medium ? "JetBrainsMono-Medium" : "JetBrainsMono-Regular",
                       size: defaultSize(of: style), relativeTo: style)
    }

    static func nearestTextStyle(for size: CGFloat) -> Font.TextStyle {
        switch size {
        case 31...: .largeTitle
        case 25..<31: .title
        case 21..<25: .title2
        case 18.5..<21: .title3
        case 16.5..<18.5: .body
        case 15.5..<16.5: .callout
        case 14..<15.5: .subheadline
        case 12.5..<14: .footnote
        case 11.5..<12.5: .caption
        default: .caption2
        }
    }

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

    /// Fixed-size miniature artwork only. The containing drawing must be accessibility-hidden.
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

    @available(*, deprecated, message: "plan 16: use .stashFont(.machine) (11 pt dates, facts and short status)")
    static func meta() -> Font { Role.meta.font(nil) }

    @available(*, deprecated, message: "plan 16: use .stashFont(.chip) — follows Bold Text")
    static func chip() -> Font { Role.chip.font(nil) }

    @available(*, deprecated, message: "plan 16: use .stashMicroLabel() (font + caps + tracking + colour) or .stashFont(.microLabel)")
    static func microLabel() -> Font { Role.microLabel.font(nil) }

    @available(*, deprecated, message: "plan 16: use .stashKicker() (font + caps + tracking + colour) or .stashFont(.kicker)")
    static func kicker() -> Font { Role.kicker.font(nil) }

    @available(*, deprecated, message: "plan 16: use .stashFont(.reading) (17 pt reading text) or .stashFont(.secondary) (15 pt supporting text)")
    static func body() -> Font { legacy(.book, size: 14) }

    @available(*, deprecated, message: "plan 16: use .stashFont(.readingMedium) 17 / .secondaryMedium 15 / .metaMedium 11 / .chip 11 / .textButtonProminent, or .custom(.medium, size:)")
    static func bodyMedium(_ size: CGFloat = 14) -> Font { legacy(.medium, size: size) }

    @available(*, deprecated, message: "plan 16: use .stashFont(.readingSemibold) 17, or .custom(.semibold, size:)")
    static func bodySemibold(_ size: CGFloat = 14) -> Font { legacy(.semibold, size: size) }

    @available(*, deprecated, message: "plan 16: use .stashFont(.readingItalic) 17 or .stashFont(.secondaryItalic) 15")
    static func bodyItalic() -> Font { legacy(.bookItalic, size: 14) }

    @available(*, deprecated, message: "plan 16: use .stashFont(.mono(<text style>)) — 10–11 → .caption2, 11.5–12 → .caption, 12.5–13 → .footnote, 15 → .subheadline, 28 → .title, 34 → .largeTitle")
    static func mono(_ size: CGFloat = 11) -> Font { Role.code(nearestTextStyle(for: size)).font(nil) }

    @available(*, deprecated, message: "plan 16: use .stashFont(.screenTitle) for 28 pt, else .stashFont(.custom(.medium, size:)) — or StashType.decorative(.medium, size:) for accessibility-hidden art")
    static func medium(size: CGFloat) -> Font { legacy(.medium, size: size) }

    @available(*, deprecated, message: "plan 16: use .stashFont(.custom(.semibold, size:)) — or StashType.decorative(.semibold, size:) for accessibility-hidden art")
    static func semibold(size: CGFloat) -> Font { legacy(.semibold, size: size) }

    @available(*, deprecated, message: "plan 16: use a role (.stashFont(.meta) 11, .secondary 15, .reading 17) or .stashFont(.custom(.book, size:)) — or StashType.decorative(.book, size:) for accessibility-hidden art")
    static func regular(size: CGFloat) -> Font { legacy(.book, size: size) }

    /// Source-compatible legacy role. V2 has no serif: this is the Montreal object title.
    @available(*, deprecated, message: "Use .stashFont(.cardTitle); v2 titles use Montreal")
    static func editorialTitle() -> Font { Role.cardTitle.font(nil) }
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
    /// Sets a StashType role (DESIGN-v2.md › Typography and native Dynamic Type roles): its face at its Dynamic
    /// Type–scaled size, and the next heavier face while Bold Text is on — live. Like `.font`, it
    /// applies to every text view inside.
    func stashFont(_ role: StashType.Role) -> some View {
        modifier(StashRoleFont(role: role))
    }

    /// A machine micro-label: Departure Mono 11 (`.caption2`), no tracking, `muted` unless
    /// told otherwise — the whole recipe in one call. Pass the text in its natural case.
    /// `.textCase(.uppercase)` draws the caps and reaches the accessibility label too: the
    /// onboarding kicker "Step 1" is labelled "STEP 1", as the all-caps literal it replaced was.
    /// VoiceOver reads a word like that as a word, so nothing is lost; a label that has to read
    /// differently needs its own `.accessibilityLabel`. The colour is set here, so a later
    /// `.foregroundStyle` can't change it — pass it instead.
    func stashMicroLabel(_ color: Color = StashColor.muted) -> some View {
        stashFont(.microLabel)
            .textCase(.uppercase)
            .stashTracking(0, role: .microLabel)
            .foregroundStyle(color)
    }

    /// A machine eyebrow: Departure Mono 11 (`.caption2`), caps, no tracking, `muted` unless told
    /// otherwise. Same rules as `stashMicroLabel`.
    func stashKicker(_ color: Color = StashColor.muted) -> some View {
        stashFont(.kicker)
            .textCase(.uppercase)
            .stashTracking(0, role: .kicker)
            .foregroundStyle(color)
    }

    /// Kerning for text set in `role`, as an em fraction of the role's default (Large) size —
    /// DESIGN.md's letter-spacing tokens as written: `.stashTracking(-0.014, role: .cardTitle)`,
    /// `.stashTracking(0, role: .microLabel)`. The kerning is that many points at every text
    /// size, so it tightens in em terms as the text grows, as Apple's own tracking does.
    func stashTracking(_ em: CGFloat, role: StashType.Role) -> some View {
        kerning(role.isMachine ? 0 : em * role.defaultSize)
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
