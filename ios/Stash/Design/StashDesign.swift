import SwiftUI

/// The iOS side of the cross-surface design system — DESIGN.md (repo root) is the single source
/// of truth for every token here; when this file and DESIGN.md disagree, DESIGN.md wins and both
/// get fixed in the same change (see DESIGN.md "Per-surface notes"). Components mirror the web's
/// conventions: 40/48px round iconographic buttons with hairline borders, a violet-filled
/// "weighted" submit, a compact wordmark header instead of per-screen titles, and the animated
/// gradient backdrop that gives every capture surface its ambience.
enum StashColor {
    // DESIGN.md §Color — neutrals (chrome).
    static let ink = Color(hex: 0x22262F)
    static let muted = Color(hex: 0x646B76)
    static let faint = Color(hex: 0x959BA6)
    static let hairline = Color.black.opacity(0.07)
    static let paper = Color.white
    /// Pill-tab track / quiet fills — DESIGN.md "chip bg" `rgba(20,22,30,.05)`.
    static let wash = Color(hex: 0x14161E).opacity(0.05)
    /// DESIGN.md "dotted rule" — facts-row separators only (Task 7's Details drawer).
    static let dottedRule = Color.black.opacity(0.18)

    // DESIGN.md §Color — intent colors.
    static let violet600 = Color(hex: 0x6D5BD0)
    static let violet300 = Color(hex: 0xB6A8EF)
    static let destructive = Color(hex: 0xC93A3A)

    /// `.animated-gradient`'s six stops, in order (web `src/index.css`; DESIGN.md §Color "Page
    /// wash gradient"). DESIGN.md sanctions the splash gradient only in page washes — this
    /// palette is intentionally untouched by the ink/violet token pass.
    static let gradientStops = [
        Color(hex: 0x667eea),
        Color(hex: 0x764ba2),
        Color(hex: 0x9d5fd8),
        Color(hex: 0xc2418f),
        Color(hex: 0x4facfe),
        Color(hex: 0x38bdf8),
    ]

    /// DESIGN.md §Color "Type spectrum" (lines ~101-114, plan 9) — the object-type identity used
    /// on cards, chips, and per-type fields. `.repo` is the odd row out (a dark plate, not an rgba
    /// tint) — see `typeField`/`typeText` below for how each case reads it.
    enum TypeTint { case voice, audio, document, screenshot, repo, social }

    /// The type's rgba field tint at its DESIGN.md alpha — the flat wash behind a hero/chip field.
    /// Table gives each row a range (e.g. voice `.11–.12`); this transcribes the range's midpoint.
    /// `.repo` has no rgba tint in the table (its field *is* the dark plate) — returns `repoPlate`.
    static func typeField(_ t: TypeTint) -> Color {
        switch t {
        case .voice: return Color(hex: 0x5458B2).opacity(0.115)
        case .audio: return Color(hex: 0x7E4A9E).opacity(0.105)
        case .document: return Color(hex: 0x9646BE).opacity(0.105)
        case .screenshot: return Color(hex: 0x3484C9).opacity(0.10)
        case .repo: return repoPlate
        case .social: return Color(hex: 0x4664B4).opacity(0.07)
        }
    }

    /// Text color per DESIGN.md's "Type spectrum" table's "Accent / text" column — `.repo` reads
    /// its mono `#e6edf3` (on the dark plate); `.social` reads "quote in ink" as `ink` itself.
    static func typeText(_ t: TypeTint) -> Color {
        switch t {
        case .voice: return Color(hex: 0x45408C)
        case .audio: return Color(hex: 0x703C77)
        case .document: return Color(hex: 0x7D3F9E)
        case .screenshot: return Color(hex: 0x22689C)
        case .repo: return Color(hex: 0xE6EDF3)
        case .social: return ink
        }
    }

    /// The saturated control accent where DESIGN.md's table gives one (voice's play/waveform,
    /// audio's player) — every other row falls back to `typeText`, since the table has no distinct
    /// accent column for document/screenshot/repo/social.
    static func typeAccent(_ t: TypeTint) -> Color {
        switch t {
        case .voice: return Color(hex: 0x544EBA)
        case .audio: return Color(hex: 0x8B4A9E)
        default: return typeText(t)
        }
    }

    static let repoPlate = Color(hex: 0x0D1117)
    static let repoOwner = Color(hex: 0x8B7BD8)

    // DESIGN.md §Color "Gate strip" (2026-09-03, plan 9) — lapsed-account capture lock, Add tab +
    // share sheet.
    static let gateBackground = Color(hex: 0xFFF7E6)
    static let gateBorder = Color(hex: 0xF3D9A4)
    static let gateText = Color(hex: 0x7A4B00)
}

extension Color {
    /// `0xRRGGBB` — the literal form every DESIGN.md hex token is transcribed in.
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

/// DESIGN.md §Space, radius, elevation.
enum StashRadius {
    static let card: CGFloat = 16
    static let sheet: CGFloat = 20
    static let input: CGFloat = 12
    /// DESIGN.md §Space "Composer card" (2026-09-03, plan 9) — the Add-tab capture panel's own
    /// (smaller, web-parity) radius; deliberately not `card` (16px).
    static let composer: CGFloat = 6
}

/// DESIGN.md card/sheet shadow recipes (each a two-layer shadow; SwiftUI has no multi-shadow
/// modifier, so `card()` is applied as two stacked `.shadow` calls via this `ViewModifier`).
struct StashShadow: ViewModifier {
    func body(content: Content) -> some View {
        content
            .shadow(color: Color(hex: 0x14161E).opacity(0.05), radius: 1, y: 1)
            .shadow(color: Color(hex: 0x1E212C).opacity(0.08), radius: 12, y: 8)
    }

    /// `0 1 2 rgba(20,22,30,.05) + 0 8 24 rgba(30,33,44,.08)` — DESIGN.md card shadow.
    static func card() -> StashShadow { StashShadow() }
}

extension View {
    func stashCardShadow() -> some View { modifier(StashShadow.card()) }
}

/// DESIGN.md §Space "Composer card" (2026-09-03, plan 9) — the Add-tab capture panel's idle vs.
/// composing treatment (web parity: `UnifiedInputPanel.tsx`'s `shell` motion.div). SwiftUI has no
/// spread-only "ring" shadow, so the 1.5pt stroke is a `strokeBorder` overlay and the halo/deep
/// shadow are two stacked `.shadow` calls; all three layers exist in both states (opacity/size
/// animate between idle and active values) so the spring below always has something to interpolate
/// instead of layers popping in/out. `active`'s spring uses the same physical model (mass,
/// stiffness, damping) as the web's Framer Motion spring, numbers transcribed 1:1.
private struct StashComposerRing: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: StashRadius.composer, style: .continuous)
                    .strokeBorder(StashColor.violet600.opacity(active ? 0.5 : 0), lineWidth: 1.5)
            )
            // Halo — DESIGN.md's 6pt violet600@.08 ring (active only).
            .shadow(color: StashColor.violet600.opacity(active ? 0.08 : 0), radius: 6)
            // Neutral card shadow's near layer while idle; quiets to nothing once the halo/deep
            // shadow above carry the active state's visual weight.
            .shadow(color: Color(hex: 0x14161E).opacity(active ? 0 : 0.05), radius: 1, y: 1)
            // Deep shadow: neutral card ambient while idle, violet drop (DESIGN.md's
            // "0 24 48 violet600@.35") once composing.
            .shadow(color: active ? StashColor.violet600.opacity(0.35) : Color(hex: 0x1E212C).opacity(0.08),
                    radius: active ? 24 : 12, y: active ? 24 : 8)
            .scaleEffect(active ? 1.006 : 1)
            .offset(y: active ? -2 : 0)
            .animation(.interpolatingSpring(mass: 0.7, stiffness: 320, damping: 28), value: active)
    }
}

extension View {
    /// Idle = neutral card shadow; composing (`active`) = the three-layer violet ring (1.5pt
    /// stroke, 6pt halo, deep drop) with a 2px lift and 1.006 scale, spring-animated. Nothing else
    /// is exposed — callers can't reach the individual layers.
    func stashComposerRing(active: Bool) -> some View {
        modifier(StashComposerRing(active: active))
    }
}

// MARK: - Round icon buttons (web: h-12 w-12 rounded-full border shadow-sm)

/// The visual for one round icon control — used as a `Button`/`PhotosPicker` label so both get
/// the identical treatment. `active` is the web's violet toggled state (location pin on, public
/// globe on); default is the hairline-bordered ink-on-paper resting state.
struct CircleIcon: View {
    let systemImage: String
    var size: CGFloat = 40
    var active = false
    var busy = false

    var body: some View {
        ZStack {
            if busy {
                ProgressView()
            } else {
                Image(systemName: systemImage)
                    .font(.system(size: size * 0.42, weight: .medium))
            }
        }
        .frame(width: size, height: size)
        .foregroundStyle(active ? StashColor.violet600 : StashColor.ink)
        .background(active ? StashColor.violet600.opacity(0.12) : StashColor.paper, in: Circle())
        .overlay(Circle().strokeBorder(active ? StashColor.violet300 : StashColor.hairline, lineWidth: 1))
        .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
    }
}

/// The weighted submit circle (web's Send button): violet-filled with a white paper plane while
/// submittable, the resting paper/hairline circle otherwise — never dimmed (`disabled:opacity-100`).
struct CircleSubmitIcon: View {
    var size: CGFloat = 48
    var hot: Bool
    var busy = false
    var systemImage = "paperplane.fill"

    var body: some View {
        ZStack {
            if busy {
                ProgressView().tint(hot ? .white : StashColor.faint)
            } else {
                Image(systemName: systemImage)
                    .font(.system(size: size * 0.38, weight: .semibold))
            }
        }
        .frame(width: size, height: size)
        .foregroundStyle(hot ? .white : StashColor.faint)
        .background(hot ? StashColor.violet600 : StashColor.paper, in: Circle())
        .overlay(Circle().strokeBorder(hot ? StashColor.violet600 : StashColor.hairline, lineWidth: 1))
        .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
    }
}

// MARK: - Wordmark header (Add tab + share sheet only — final wave, item E/11)

/// Add tab + share sheet only (final wave, item E/11 — doc corrected; Will's call, plan 8: View/
/// Ask/Settings all dropped this header in favor of no title chrome at all, `SettingsView`'s own
/// doc comment has the detail). The Stash wordmark leading (same as the web's header) and an
/// optional per-tab accessory trailing. Detail flows stay sheets; if a tab ever grows push
/// navigation, the system inline back bar slots under this without clashing.
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

// MARK: - Animated gradient backdrop (web: .animated-gradient at opacity-30, faded to background)

/// The web's `gradientShift` reinterpreted for SwiftUI: a −45°-equivalent sweep (bottom-leading →
/// top-trailing) over a 2× canvas, blurred 40pt so the six stops read as a smooth wash with no
/// banding, drifting slowly back and forth over 15s. Always paired with a fade-to-background
/// overlay by `GradientBackdrop`. Palette unchanged by the DESIGN.md token pass — the page wash
/// is a sanctioned exception.
struct AnimatedGradient: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drift = false

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            LinearGradient(colors: StashColor.gradientStops,
                           startPoint: .bottomLeading, endPoint: .topTrailing)
                .frame(width: w * 2, height: h * 2)
                .blur(radius: 40)
                // `.drawingGroup()` (final wave, item E/10): rasterizes the blurred gradient into
                // a single flattened layer ONCE, right after the blur — the drift animation below
                // then just translates that cached bitmap every frame instead of re-running the
                // (expensive) blur filter over the full 2×-canvas gradient on every frame of a
                // 15s-long `repeatForever` animation. Visually identical; purely a render-cost fix.
                .drawingGroup()
                // The 2× canvas always overhangs the viewport, so this diagonal drift never
                // exposes a blurred edge — see the offset-bounds note above `drift`'s range.
                .offset(x: drift ? -w * 0.25 : -w * 0.75,
                        y: drift ? -h * 0.75 : -h * 0.25)
                .onAppear {
                    guard !reduceMotion else { return }
                    withAnimation(.easeInOut(duration: 15).repeatForever(autoreverses: true)) {
                        drift = true
                    }
                }
        }
        .clipped()
        .allowsHitTesting(false)
    }
}

/// Page-level ambience (web Index.tsx:149-150): the animated gradient at low opacity, washed
/// down to `StashColor.paper` so content lower on the screen sits on a clean surface.
struct GradientBackdrop: View {
    var opacity: Double = 0.3

    var body: some View {
        AnimatedGradient()
            .opacity(opacity)
            .overlay(
                LinearGradient(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: StashColor.paper.opacity(0.5), location: 0.55),
                    .init(color: StashColor.paper, location: 1),
                ], startPoint: .top, endPoint: .bottom)
            )
            .allowsHitTesting(false)
    }
}
