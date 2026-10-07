import SwiftUI
import UIKit

/// DESIGN-v2.md is the cross-surface reference. Paper and white hold the person's
/// objects; black and Departure Mono belong to the machine. Lime marks its active work.
enum StashColor {
    static let paper = Color(hex: 0xF3F4F1)
    static let white = Color(hex: 0xFFFFFF)
    static let surface = white
    static let ink = Color(hex: 0x000000)
    static let inkSoft = Color(hex: 0x262626)
    static let muted = Color(hex: 0x5C6159)
    static let hairline = Color(hex: 0xD5D8D1)
    static let line = hairline
    static let lineSoft = Color(hex: 0xE5E7E2)
    static let fill = Color(hex: 0xECEDE9)
    static let wash = fill
    static let dot = ink.opacity(0.13)
    static let dottedRule = dot
    /// Decorative/disabled only. Readable secondary text always uses `muted`.
    static let faint = Color(hex: 0x959B91)

    static let spot = Color(hex: 0xA3F53B)
    static let onSpot = ink
    static let spotInk = Color(hex: 0x1F4A38)
    static let spotOnInk = spot
    static let ok = Color(hex: 0x2E9E52)
    static let error = Color(hex: 0xA1281C)
    static let success = ok
    static let destructive = error
    static let linkUnderline = ink

    // Compatibility names for existing screens. Lime is never text on light surfaces:
    // legacy interactive violet therefore maps to ink, retaining readable contrast.
    static let violet600 = ink
    static let violet700 = ink
    static let violet300 = hairline
    static let gradientStops = [paper, paper]

    enum TypeTint { case voice, audio, document, screenshot, repo, social }

    static func typeField(_ type: TypeTint) -> Color {
        type == .repo ? repoPlate : fill
    }

    static func typeText(_ type: TypeTint) -> Color {
        type == .repo ? white : ink
    }

    static func typeAccent(_ type: TypeTint) -> Color { typeText(type) }

    static let repoPlate = ink
    static let repoOwner = white
    static let gateBackground = spot
    static let gateBorder = ink
    static let gateText = ink
}

extension Color {
    /// `0xRRGGBB`, matching the design reference's literal colour tokens.
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

extension Text.LineStyle {
    /// Links in reading text always have a cue beyond colour.
    static let stashLinkUnderline = Text.LineStyle(pattern: .solid, color: StashColor.linkUnderline)
}

enum StashRadius {
    static let object: CGFloat = 2
    static let machine: CGFloat = 0
    static let control: CGFloat = machine
    static let card = object
    static let composer = object
    static let sheet = machine
    static let input = machine
}

/// Objects rest quietly on paper. Floating windows and active composers use a hard
/// print shadow. Touch cards do not lift: their press state is an ink edge.
struct StashShadow: ViewModifier {
    var hard = false

    func body(content: Content) -> some View {
        content.compositingGroup()
            .shadow(color: StashColor.ink.opacity(hard ? 1 : 0.08),
                       radius: 0, x: hard ? 4 : 0, y: hard ? 4 : 1)
    }

    static func card() -> StashShadow { StashShadow() }
    static var object: StashShadow { StashShadow() }
    static var print: StashShadow { StashShadow(hard: true) }
}

extension View {
    func stashCardShadow() -> some View { modifier(StashShadow.card()) }
    func stashPrintShadow() -> some View { modifier(StashShadow.print) }
}

private struct StashComposerRing: ViewModifier {
    let active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay {
                RoundedRectangle(cornerRadius: StashRadius.composer)
                    .strokeBorder(active ? StashColor.ink : StashColor.line, lineWidth: 1)
            }
            .overlay {
                if active {
                    RoundedRectangle(cornerRadius: StashRadius.composer + 3)
                        .stroke(StashColor.spot, lineWidth: 3)
                        .padding(-2)
                        .allowsHitTesting(false)
                }
            }
            .compositingGroup()
            .shadow(color: StashColor.ink.opacity(active ? 1 : 0.08),
                    radius: 0, x: active ? 4 : 0, y: active ? 4 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: active)
    }
}

extension View {
    /// Focus is an ink edge plus a lime ring: the ink carries contrast on paper.
    func stashComposerRing(active: Bool) -> some View {
        modifier(StashComposerRing(active: active))
    }
}

// MARK: - Hit targets and icon-only controls (plan 16)

extension View {
    /// HIG: every tappable element takes touches across at least 44×44 pt. Grows this view's hit
    /// area to `minimum` × `minimum`, centred, WITHOUT changing its layout size or its look — a
    /// clear, hit-testable background that may overhang the view (SwiftUI doesn't clip hit testing
    /// to a view's frame). Views already that big are unchanged.
    ///
    /// **It goes on the control's LABEL** (inside `label:`, after the label's own visuals), never
    /// on the `Button`: there the clear background belongs to no gesture — a 44 pt dead zone that
    /// swallows taps meant for whatever is beside or beneath it, and activates nothing. For a plain
    /// custom control, `.buttonStyle(.stashPlain)` puts it in the right place for you.
    ///
    /// Why it matters even though SwiftUI hit-tests a touch with a radius (a lone control takes a
    /// tap ~16 pt past its edge): over anything else tappable — a card, a row, a sheet's surface —
    /// the exact hit on that surface wins, so a small control only gets the taps its own shape
    /// covers. Proven by `A11yFoundationUITests.testSharedControlsTakeEveryTapInsideA44PointTarget`.
    ///
    /// Limits: two targets closer than 44 pt (centre to centre) overlap, and the later sibling wins
    /// the overlap; and an overhang is lost wherever an ancestor clips — past a `ScrollView`'s edge
    /// (a horizontal scroll row's top and bottom, a list's first and last row) or inside
    /// `.clipped()` / `.clipShape` — so keep a small control's centre ≥ 22 pt inside such an edge,
    /// or give it a real 44 pt layout there.
    func stashMinimumHitTarget(_ minimum: CGFloat = 44) -> some View {
        background {
            Color.clear
                .frame(minWidth: minimum, minHeight: minimum)
                .contentShape(Rectangle())
        }
    }

    /// Names an icon-only control (a `CircleIcon` button, a glyph-only button) — VoiceOver's label,
    /// and the Large Content Viewer: icon chrome keeps a fixed glyph size at every text size, like
    /// the system's bar buttons, so at accessibility sizes a long press shows `label` and the glyph
    /// large. Use it in place of `.accessibilityLabel` on the control itself (the `Button`), with
    /// the same symbol the control draws.
    ///
    /// `isOn`: pass it for a control that toggles a state — the Add tab / share sheet's location
    /// pin, the detail sheet's public globe (`CircleIcon(active:)`) — and VoiceOver hears a toggle
    /// button that is "On" or "Off" (`.isToggle` trait + value), not a plain button whose state is
    /// only a colour. Leave it nil for an action.
    func stashIconControl(_ label: String, systemImage: String, isOn: Bool? = nil) -> some View {
        accessibilityLabel(label)
            .accessibilityShowsLargeContentViewer {
                Label(label, systemImage: systemImage)
            }
            .modifier(StashToggleState(isOn: isOn))
    }
}

/// `stashIconControl`'s on/off state for VoiceOver (WCAG 4.1.2 name, role, value).
private struct StashToggleState: ViewModifier {
    let isOn: Bool?

    func body(content: Content) -> some View {
        if let isOn {
            content
                .accessibilityAddTraits(.isToggle)
                .accessibilityValue(isOn ? "On" : "Off")
        } else {
            content
        }
    }
}

/// `.buttonStyle(.stashPlain)` — exactly `.plain` (no chrome; the system's pressed dimming), with
/// the 44×44 pt target built in: `stashMinimumHitTarget()` lands on the button's label, the one
/// place it works, so it can't be misplaced. For small custom controls — a glyph-only button (a
/// search clear ×, a reminder ×, a sheet's close ×), a thumbs/speak glyph, a short inline text
/// action ("Open link", "Delete item"). A label already 44 pt both ways is unchanged; the shared
/// controls (`CircleIcon`, `CircleSubmitIcon`, `PillTabs`, `StashCancelButton`) carry their own.
struct StashPlainButtonStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button(role: configuration.role, action: configuration.trigger) {
            configuration.label.stashMinimumHitTarget()
        }
        .buttonStyle(.plain)
    }
}

extension PrimitiveButtonStyle where Self == StashPlainButtonStyle {
    /// `.plain` with a 44×44 pt target on the label — see `StashPlainButtonStyle`.
    static var stashPlain: StashPlainButtonStyle { StashPlainButtonStyle() }
}

// MARK: - Square machine controls

/// Existing name retained at call sites; the v2 visual is square machine chrome.
/// Its glyph stays fixed like native bar-button chrome, with a 44 pt hit target.
struct CircleIcon: View {
    let systemImage: String
    var size: CGFloat = 40
    var active = false
    var busy = false
    var bordered = true

    var body: some View {
        ZStack {
            if busy {
                StashCursor(size: .machineLarge)
            } else {
                Image(systemName: systemImage)
                    .font(.system(size: size * 0.42, weight: .medium))
            }
        }
        .frame(width: size, height: size)
        .foregroundStyle(active ? StashColor.spotOnInk : StashColor.ink)
        .background(active ? StashColor.ink : StashColor.white)
        .overlay {
            if bordered {
                Rectangle().strokeBorder(active ? StashColor.ink : StashColor.line, lineWidth: 1)
            }
        }
        .stashMinimumHitTarget()
    }
}

/// Primary action: white on ink when available, a quiet square at rest.
struct CircleSubmitIcon: View {
    var size: CGFloat = 48
    var hot: Bool
    var busy = false
    var systemImage = "paperplane.fill"

    var body: some View {
        ZStack {
            if busy {
                StashCursor(size: .machineLarge)
            } else {
                Image(systemName: systemImage)
                    .font(.system(size: size * 0.38, weight: .semibold))
            }
        }
        .frame(width: size, height: size)
        .foregroundStyle(hot ? StashColor.white : StashColor.faint)
        .background(hot ? StashColor.ink : StashColor.white)
        .overlay(Rectangle().strokeBorder(hot ? StashColor.ink : StashColor.line, lineWidth: 1))
        .stashMinimumHitTarget()
    }
}

/// A native Toggle's label and state in v2 square chrome. The whole row is the
/// 44 pt target, and the native label remains the VoiceOver name.
struct StashSwitchStyle: ToggleStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: 12) {
                configuration.label
                Spacer(minLength: 8)
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(configuration.isOn ? StashColor.ink : StashColor.fill)
                    Rectangle()
                        .fill(configuration.isOn ? StashColor.spotOnInk : StashColor.white)
                        .frame(width: 16, height: 16)
                        .overlay {
                            if configuration.isOn {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(StashColor.onSpot)
                            }
                        }
                        .offset(x: configuration.isOn ? 21 : 3)
                }
                .frame(width: 40, height: 22)
                .overlay(Rectangle().strokeBorder(StashColor.ink, lineWidth: 1))
                .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: configuration.isOn)
                .accessibilityHidden(true)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            .opacity(isEnabled ? 1 : 0.45)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(configuration.isOn ? "On" : "Off")
    }
}

// MARK: - Shared wordmark header and keyboard Cancel

struct StashHeader<Accessory: View>: View {
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(alignment: .center) {
            Image("StashWordmark")
                .resizable()
                .scaledToFit()
                .frame(height: 20)
                .foregroundStyle(StashColor.ink)
                .accessibilityLabel("Stash")
            Spacer()
            accessory
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }
}

extension StashHeader where Accessory == EmptyView {
    init() { self.init(accessory: { EmptyView() }) }
}

// MARK: - Keyboard "Cancel" (plan 16)

/// Shared keyboard Cancel. The word keeps its Dynamic Type size, one unbroken line,
/// a 44 pt hit target and the native cancel keyboard shortcut. `onWash` adds a square
/// white backing without changing the row's layout; retained for source compatibility.
struct StashCancelButton: View {
    /// The caller's accessibility identifier (e.g. `ask.dismissKeyboard`) — tests find it by this.
    let identifier: String
    /// Draws an opaque backing when placed over a textured stage.
    var onWash = false
    /// VoiceOver's hint: what THIS Cancel does. The default fits a Cancel that only puts the
    /// keyboard away (Ask, the Add tab); one that also clears something says so (the View-tab
    /// search: "Clears the search and hides the keyboard").
    var hint = "Hides the keyboard"
    let action: () -> Void

    /// The optional backing grows visually without changing the row's layout.
    private static let backingVerticalPadding: CGFloat = 5

    var body: some View {
        Button(action: action) {
            Text("Cancel")
                .stashFont(.textButton)
                .foregroundStyle(StashColor.ink)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, onWash ? 12 : 0)
                .background {
                    if onWash {
                        Rectangle()
                            .fill(StashColor.white)
                            .overlay(Rectangle().strokeBorder(StashColor.hairline, lineWidth: 1))
                            .padding(.vertical, -Self.backingVerticalPadding)
                    }
                }
                .stashMinimumHitTarget()
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.cancelAction)
        .accessibilityLabel("Cancel")
        .accessibilityHint(hint)
        .accessibilityIdentifier(identifier)
        .layoutPriority(1)
    }
}

// MARK: - Paper and machine activity

/// Decorative dot texture. Canvas draws one static path; it has no timer or bitmap cache.
struct StashDotGrid: View {
    var spacing: CGFloat = 16
    var opacity: Double = 0.13

    var body: some View {
        Canvas { context, size in
            var dots = Path()
            let step = max(spacing, 4)
            for y in stride(from: CGFloat(0), through: size.height, by: step) {
                for x in stride(from: CGFloat(0), through: size.width, by: step) {
                    dots.addRect(CGRect(x: x, y: y, width: 1, height: 1))
                }
            }
            context.fill(dots, with: .color(StashColor.ink.opacity(opacity)))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The quiet sheet behind objects. Settings and forms can use plain paper; library,
/// loading and sign-in use the fine 4 pt cutting-mat dots from DESIGN-v2.md §7.
struct StashPaperBackdrop: View {
    var showDots = false

    var body: some View {
        ZStack {
            StashColor.paper
            if showDots { StashDotGrid(spacing: 4, opacity: 0.055) }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Source-compatible replacement for the old animated gradient. No ambient animation.
struct AnimatedGradient: View {
    var body: some View { StashPaperBackdrop(showDots: true) }
}

/// Source-compatible page backdrop; `opacity` now controls only the paper's subtle dots.
struct GradientBackdrop: View {
    var opacity: Double = 0.3

    var body: some View {
        ZStack {
            StashColor.paper
            StashDotGrid(spacing: 4, opacity: 0.055 * min(max(opacity / 0.3, 0), 1))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Every visible cursor shares the same date-based phase. Reduced Motion keeps `|`.
/// Cursor glyphs are decoration; the caller supplies the stable state to VoiceOver.
struct StashCursor: View {
    var size: StashType.Role = .machine
    var active = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private static let frames = ["|", "/", "-", "\\"]

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.13, paused: reduceMotion || !active)) { context in
            let phase = reduceMotion || !active ? 0 : Int(context.date.timeIntervalSinceReferenceDate / 0.13) % Self.frames.count
            Text(Self.frames[phase])
                .stashFont(size)
        }
        .accessibilityHidden(true)
    }
}

struct StashStatusLine: View {
    let text: String
    var busy = true
    var color: Color = StashColor.muted

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if busy { StashCursor() }
            Text(text)
                .stashFont(.machine)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(color)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }
}

// MARK: - Flow layout (plan 9 final wave, item B/4 — card chip row wrapping)

/// A minimal left-aligned, top-to-bottom wrapping row — SwiftUI ships no built-in flow layout.
/// The card chips row (`ItemCardView.chipsRow`) uses this instead of a plain `HStack` so a card
/// carrying several chips (leading type chip + facts + a salient fact) wraps to a second line
/// under width pressure rather than truncating/squeezing the leading type chip the way a fixed
/// `HStack` would. Deliberately minimal (no alignment options, no per-row justification) — the
/// chips row is this struct's only call site; grow it if a second one needs more.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var totalHeight: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth > 0, rowWidth + spacing + size.width > maxWidth {
                totalHeight += rowHeight + spacing
                rowWidth = 0
                rowHeight = 0
            }
            rowWidth += (rowWidth > 0 ? spacing : 0) + size.width
            rowHeight = max(rowHeight, size.height)
        }
        totalHeight += rowHeight
        return CGSize(width: maxWidth.isFinite ? maxWidth : rowWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
