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

    // DESIGN.md §Color — intent colors.
    static let violet600 = Color(hex: 0x6D5BD0)
    static let violet300 = Color(hex: 0xB6A8EF)
    static let destructive = Color(hex: 0xC93A3A)

    /// `.animated-gradient`'s six stops, in order (web `src/index.css`). DESIGN.md sanctions the
    /// splash gradient only in page washes — this palette is intentionally untouched by the
    /// ink/violet token pass.
    static let gradientStops = [
        Color(red: 102/255, green: 126/255, blue: 234/255),  // #667eea
        Color(red: 118/255, green: 75/255, blue: 162/255),   // #764ba2
        Color(red: 240/255, green: 147/255, blue: 251/255),  // #f093fb
        Color(red: 245/255, green: 87/255, blue: 108/255),   // #f5576c
        Color(red: 79/255, green: 172/255, blue: 254/255),   // #4facfe
        Color(red: 0/255, green: 242/255, blue: 254/255),    // #00f2fe
    ]
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

// MARK: - Wordmark header (one titling convention across all four tabs)

/// Every tab is one level deep, so per-screen large titles are redundant next to the tab bar.
/// Instead, each tab carries this identical compact header: the Stash wordmark leading (same as
/// the web's header) and an optional per-tab accessory trailing. Detail flows stay sheets; if a
/// tab ever grows push navigation, the system inline back bar slots under this without clashing.
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

/// The web's `gradientShift` reinterpreted for SwiftUI: a triple-width diagonal gradient sliding
/// back and forth over 15s. Always paired with a fade-to-background overlay by `GradientBackdrop`.
/// Palette unchanged by the DESIGN.md token pass — the page wash is a sanctioned exception.
struct AnimatedGradient: View {
    @State private var slide = false

    var body: some View {
        GeometryReader { geo in
            LinearGradient(colors: StashColor.gradientStops,
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .frame(width: geo.size.width * 3)
                .offset(x: slide ? -geo.size.width * 2 : 0)
                .animation(.easeInOut(duration: 15).repeatForever(autoreverses: true), value: slide)
                .onAppear { slide = true }
        }
        .clipped()
        .allowsHitTesting(false)
    }
}

/// Page-level ambience (web Index.tsx:149-150): the animated gradient at low opacity, washed
/// down to the system background so content lower on the screen sits on a clean surface.
struct GradientBackdrop: View {
    var opacity: Double = 0.3

    var body: some View {
        AnimatedGradient()
            .opacity(opacity)
            .overlay(
                LinearGradient(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: Color(.systemBackground).opacity(0.5), location: 0.55),
                    .init(color: Color(.systemBackground), location: 1),
                ], startPoint: .top, endPoint: .bottom)
            )
            .allowsHitTesting(false)
    }
}
