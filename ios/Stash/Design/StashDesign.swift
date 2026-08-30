import SwiftUI

/// The iOS side of the web design system (`src/index.css` + `UnifiedInputPanel.tsx` are the
/// source of truth). Colors are the web's exact hex values (Tailwind violet/gray scales and the
/// `.animated-gradient` stops); components mirror the web's conventions: 48px round iconographic
/// buttons with hairline borders and soft shadows, a violet-filled "weighted" submit, a compact
/// wordmark header instead of per-screen titles, and the animated gradient backdrop that gives
/// every capture surface its pink-hued ambience.
enum StashColor {
    static let violet = Color(red: 139/255, green: 92/255, blue: 246/255)      // #8B5CF6
    static let violet50 = Color(red: 245/255, green: 243/255, blue: 255/255)   // #F5F3FF
    static let violet300 = Color(red: 196/255, green: 181/255, blue: 253/255)  // #C4B5FD
    static let violet600 = Color(red: 124/255, green: 58/255, blue: 237/255)   // #7C3AED
    static let gray300 = Color(red: 209/255, green: 213/255, blue: 219/255)    // #D1D5DB
    static let gray400 = Color(red: 156/255, green: 163/255, blue: 175/255)    // #9CA3AF
    static let gray500 = Color(red: 107/255, green: 114/255, blue: 128/255)    // #6B7280

    /// `.animated-gradient`'s six stops, in order (index.css:195).
    static let gradientStops = [
        Color(red: 102/255, green: 126/255, blue: 234/255),  // #667eea
        Color(red: 118/255, green: 75/255, blue: 162/255),   // #764ba2
        Color(red: 240/255, green: 147/255, blue: 251/255),  // #f093fb
        Color(red: 245/255, green: 87/255, blue: 108/255),   // #f5576c
        Color(red: 79/255, green: 172/255, blue: 254/255),   // #4facfe
        Color(red: 0/255, green: 242/255, blue: 254/255),    // #00f2fe
    ]
}

// MARK: - Round icon buttons (web: h-12 w-12 rounded-full border shadow-sm)

/// The visual for one round icon control — used as a `Button`/`PhotosPicker` label so both get
/// the identical treatment. `active` is the web's violet toggled state (location pin on, public
/// globe on); default is the white/gray resting state.
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
        .foregroundStyle(active ? StashColor.violet600 : StashColor.gray500)
        .background(active ? StashColor.violet50 : Color(.systemBackground), in: Circle())
        .overlay(Circle().strokeBorder(active ? StashColor.violet300 : StashColor.gray300, lineWidth: 1))
        .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
    }
}

/// The weighted submit circle (web's Send button): violet-filled with a white paper plane while
/// submittable, the resting white/gray circle otherwise — never dimmed (`disabled:opacity-100`).
struct CircleSubmitIcon: View {
    var size: CGFloat = 48
    var hot: Bool
    var busy = false
    var systemImage = "paperplane.fill"

    var body: some View {
        ZStack {
            if busy {
                ProgressView().tint(hot ? .white : StashColor.gray400)
            } else {
                Image(systemName: systemImage)
                    .font(.system(size: size * 0.38, weight: .semibold))
            }
        }
        .frame(width: size, height: size)
        .foregroundStyle(hot ? .white : StashColor.gray400)
        .background(hot ? StashColor.violet : Color(.systemBackground), in: Circle())
        .overlay(Circle().strokeBorder(hot ? StashColor.violet : StashColor.gray300, lineWidth: 1))
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
                .foregroundStyle(.primary)
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
