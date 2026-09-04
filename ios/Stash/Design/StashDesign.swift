import SwiftUI
import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins

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
/// spread-only "ring" shadow, so the hairline/violet stroke is a `strokeBorder` overlay and the
/// halo/deep shadow are two stacked `.shadow` calls; both layers exist in both states
/// (opacity/size animate between idle and active values) so the spring below always has something
/// to interpolate instead of layers popping in/out. `active`'s spring uses the same physical model
/// (mass, stiffness, damping) as the web's Framer Motion spring, numbers transcribed 1:1.
///
/// Fix round 1 (task-0 review): idle now implements DESIGN.md's own idle recipe — `0 0 0 1px
/// rgba(0,0,0,.05), 0 10px 30px -18px rgba(0,0,0,.3)` — instead of reusing `StashShadow.card()`.
/// The 1px hairline maps 1:1 to the stroke overlay. The soft shadow doesn't: CSS's `-18px` spread
/// pulls the shadow's silhouette in tighter than its 30px blur alone would, so the visible shadow
/// is a fairly tight, close-in soft edge, not a wide diffuse one — SwiftUI's `.shadow` has no
/// spread parameter, only blur `radius` and offset. Tempered by eye against the web reference
/// (`task-0-ring-idle.png` vs. a browser screenshot of the same panel at rest): `radius: 12, y: 8`
/// reproduces the same close, soft-edged falloff; the alpha is lowered from the CSS value's `.3` to
/// `.14` because a blur-only shadow (no negative spread pulling it back in) spreads that opacity
/// over a visibly larger silhouette than the spread-narrowed CSS shadow does — left at `.3` it read
/// noticeably heavier/darker than the web at matching card sizes.
private struct StashComposerRing: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: StashRadius.composer, style: .continuous)
                    .strokeBorder(
                        active ? StashColor.violet600.opacity(0.5) : Color.black.opacity(0.05),
                        lineWidth: active ? 1.5 : 1
                    )
            )
            // Halo — DESIGN.md's 6pt violet600@.08 ring (active only; invisible at rest).
            .shadow(color: StashColor.violet600.opacity(active ? 0.08 : 0), radius: 6)
            // Deep/soft shadow: idle = the tempered `radius 12, y 8, .14` recipe above; active =
            // DESIGN.md's "0 24 48 violet600@.35" (both engines just do blur+offset there, no
            // tempering needed).
            .shadow(color: active ? StashColor.violet600.opacity(0.35) : Color.black.opacity(0.14),
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
///
/// Plan-10 task 1 ("animated white box" bug): this used to be a live `LinearGradient` with
/// `.blur(radius: 40)` then `.drawingGroup()` to cache the blur's cost across the 15s
/// `repeatForever` drift. Reproduced on iOS 17.0 and 17.4 simulators (not on 17.2/17.5/18.5/26.5
/// in the same pass — genuinely environment-dependent): a hard-edged rectangle of raw background
/// white sat where blurred gradient should be, moving with the drift. Root-cause probe (isolating
/// each modifier alone) showed NEITHER `.blur` alone NOR `.drawingGroup()` alone reproduced it —
/// only the combination did. `.drawingGroup()` rasterizes into an offscreen Metal texture sized
/// from the view's pre-effect layout bounds; `.blur`'s visual bleed extends past those bounds, and
/// on some simulator GPU/driver paths the offscreen buffer doesn't grow to cover that bleed, so
/// the un-rasterized remainder reads as transparent → background white. Rather than ship a fix
/// that depends on which GPU/OS renders it, the blur is now precomputed entirely off SwiftUI's
/// rasterizer: `UIGraphicsImageRenderer` draws the 2×-canvas linear gradient with `CGGradient`,
/// `CIGaussianBlur` blurs it once into a plain `UIImage` (rendered at 1x — it's a blur, so pixel
/// density doesn't matter, and `.resizable().interpolation(.high)` upscales it losslessly-enough
/// for a soft wash), and the drift animation only ever translates that static bitmap. No live
/// `.blur`, no `.drawingGroup()` — nothing left in the pipeline whose rasterization bounds could
/// disagree with its visual bounds.
///
/// The image is looked up (and, the first time for a given size, rendered) directly in `body` —
/// deliberately NOT behind `.onAppear`/`.onChange(of:)`. An early version gated the render behind
/// those lifecycle hooks and turned out to be its own new source of nondeterminism: on a cold
/// launch straight into a screen using this view (e.g. the Add tab immediately after sign-in),
/// `onAppear` sometimes silently never fired for this `GeometryReader`-nested view, leaving
/// `image` `nil` forever with no error — the same "white box" symptom the drawingGroup/blur bug
/// produced, from an unrelated cause. `body` is a pure, cheap function of `geo.size` once the
/// per-size cache is warm (`cachedGradientImage` returns immediately on a hit), so computing it
/// inline removes that whole class of "did the hook fire" question — every `body` evaluation
/// (rare: SwiftUI interpolates the `.offset` animation itself, it does not replay `body` per
/// frame) recomputes the answer from scratch rather than trusting stale `@State`.
struct AnimatedGradient: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drift = false
    @State private var startedAnimating = false

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            Group {
                if let img = Self.cachedGradientImage(forViewSize: geo.size) {
                    Image(uiImage: img)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: w * 2, height: h * 2)
                        // The 2× canvas always overhangs the viewport, so this diagonal drift
                        // never exposes a blurred edge — see the offset-bounds note above
                        // `drift`'s range.
                        .offset(x: drift ? -w * 0.25 : -w * 0.75,
                                y: drift ? -h * 0.75 : -h * 0.25)
                }
            }
            .onAppear {
                // Only responsible for starting the drift animation — NOT for rendering (see the
                // doc comment above on why that used to live here and why it moved into `body`).
                guard !startedAnimating, !reduceMotion else { return }
                startedAnimating = true
                withAnimation(.easeInOut(duration: 15).repeatForever(autoreverses: true)) {
                    drift = true
                }
            }
        }
        .clipped()
        .allowsHitTesting(false)
    }

    /// `CGSize` itself only picks up `Hashable` on iOS 18+, so the cache key is this plain
    /// width/height pair instead — deployment target here is iOS 17.
    private struct CacheKey: Hashable {
        let width: CGFloat
        let height: CGFloat
        init(_ size: CGSize) { width = size.width; height = size.height }
    }

    /// Per-size cache (keyed by the *view's* size, not the 2× canvas) — every `AnimatedGradient`
    /// call site (SignInView, CaptureComposerView, SplashView, LibraryView, ShareComposeView) at
    /// the same device size shares one rendered bitmap instead of each paying its own blur cost,
    /// and repeat `body` evaluations at an already-seen size are a plain dictionary lookup.
    @MainActor private static var cache: [CacheKey: UIImage] = [:]

    @MainActor
    private static func cachedGradientImage(forViewSize size: CGSize) -> UIImage? {
        guard size.width > 0, size.height > 0 else { return nil }
        let key = CacheKey(size)
        if let cached = cache[key] { return cached }
        let canvasSize = CGSize(width: size.width * 2, height: size.height * 2)
        guard let rendered = renderBlurredGradient(canvasSize: canvasSize) else { return nil }
        cache[key] = rendered
        return rendered
    }

    /// Draws the six-stop sweep (bottom-leading → top-trailing, matching the old `LinearGradient`
    /// direction) into a plain `CGContext` at 1x scale, then blurs it once with Core Image's
    /// `CIGaussianBlur` (radius 40, matching the old `.blur(radius: 40)`). The gradient is drawn
    /// into a canvas padded by `blurRadius * 3` on every side — comfortably more than the ~0.25×
    /// margin the drift animation already guarantees stays off-screen — and `drawsBeforeStart`/
    /// `drawsAfterEnd` extend the end-stop colors flat into that padding, so `CIGaussianBlur`
    /// always has real (non-transparent) content to sample from and the crop back to `canvasSize`
    /// never exposes a blur-edge seam.
    private static func renderBlurredGradient(canvasSize: CGSize) -> UIImage? {
        let blurRadius: CGFloat = 40
        let pad = blurRadius * 3
        let paddedSize = CGSize(width: canvasSize.width + pad * 2, height: canvasSize.height + pad * 2)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: paddedSize, format: format)

        let cgColors = StashColor.gradientStops.map { UIColor($0).cgColor }
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let gradient = CGGradient(colorsSpace: colorSpace, colors: cgColors as CFArray, locations: nil)
        else { return nil }

        let paddedImage = renderer.image { ctx in
            let cg = ctx.cgContext
            UIColor.white.setFill()
            cg.fill(CGRect(origin: .zero, size: paddedSize))
            // bottomLeading → topTrailing in the unpadded canvas, offset into the padded canvas.
            let start = CGPoint(x: pad, y: pad + canvasSize.height)
            let end = CGPoint(x: pad + canvasSize.width, y: pad)
            cg.drawLinearGradient(gradient, start: start, end: end,
                                   options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        }

        let blur = CIFilter.gaussianBlur()
        blur.inputImage = CIImage(image: paddedImage)
        blur.radius = Float(blurRadius)
        guard let blurred = blur.outputImage else { return nil }
        let cropRect = CGRect(x: pad, y: pad, width: canvasSize.width, height: canvasSize.height)
        guard let cgImage = sharedCIContext.createCGImage(blurred, from: cropRect) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    /// One `CIContext` reused across every size render (Metal device setup is the expensive part
    /// of creating one — not worth repeating per call site/size).
    private static let sharedCIContext = CIContext()
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
