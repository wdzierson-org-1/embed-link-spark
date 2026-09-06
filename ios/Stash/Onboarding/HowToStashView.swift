import SwiftUI

/// The post-sign-in "How to easily stash" screen — plan 13, v2 of the plan-12 single-panel
/// version: a three-panel swipe carousel (`TabView(selection:)`, `.page` style, no system dots)
/// instead of a three-column strip in one static card. Spec is
/// `docs/superpowers/prototypes/2026-09-07-ios-share-tutorial-swipe.html`'s top comment block
/// (Will's Sep 7 2026 review, chosen outright over the three-column comparison that prototype
/// used to carry) plus plan 13's Global Constraints, which is the authoritative source for any
/// number transcribed below (radii, sizes, timings) that isn't already a named `StashDesign`
/// token.
///
/// Presented as a `.fullScreenCover` — see `StashApp.swift`'s `onChange(of: session.state)` for
/// the once-per-install gate (`OnboardingState`) and `SettingsView`'s "How to stash" row for the
/// any-time re-entry point. Visually mirrors `SignInView`'s own "one paper card floating on the
/// ambient gradient wash" shape (`GradientBackdrop` + `StashRadius.sheet` card + `stashCardShadow`)
/// rather than inventing new chrome — same tokens, same recipe, different content.
///
/// Self-contained: every dismissing action uses `\.dismiss` (SwiftUI supplies that environment
/// action automatically for anything presented via `.fullScreenCover`/`.sheet`), so neither
/// `StashApp` nor `SettingsView` needs to pass a completion closure down.
///
/// ## Skip vs. Got it (plan 13 semantics — a deliberate change from plan 12's "Show me later")
///
/// Both the primary button's last-panel state ("Got it") AND the "Skip" link call
/// `OnboardingState.markHowToStashSeen()` before dismissing. Skip is NOT "later" here — the panel
/// is always reachable again from Settings → "How to stash" regardless of the seen flag, so there
/// is no need for a separate "ask me again next sign-in" state for a user who dismisses early.
/// `OnboardingState.markHowToStashDeferred()`/`clearHowToStashDeferred()` and `StashApp`'s
/// `isHowToStashDeferred` check are deliberately left in place (nothing in this file or
/// `StashApp.swift` was touched to remove them) even though no button in this revision calls
/// `markHowToStashDeferred()` any more — the plan calls this out explicitly as the "deferred path
/// stays in code" carry-over; removing the dead call site's plumbing is out of scope for this
/// task and it costs nothing to leave live (a future button could still wire it up).
struct HowToStashView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var pageIndex = 0

    private static let panelCount = 3
    /// Fixed height for the `TabView` — SwiftUI's paged `TabView` doesn't self-size to its
    /// tallest page, and the three panels have different content heights (only panel 2 carries a
    /// hint line under its caption). A fixed height matching the tallest panel, with each panel's
    /// own content top-aligned inside it (`OnboardingPanelChrome`'s `.frame(maxHeight: .infinity,
    /// alignment: .top)`), reproduces the prototype's CSS behavior exactly: `.ob-carousel-viewport`
    /// has no explicit height, so the flexbox default (`align-items: stretch`) stretches every
    /// panel to the height of the tallest one (panel 2), and each panel's own column layout
    /// (`justify-content` unset → `flex-start`) leaves the extra space at the bottom rather than
    /// centering or distributing it — panels 1 and 3 have quiet empty space below their caption,
    /// panel 2 fills the box exactly. An earlier, taller card (508pt `panelHeight` plus more
    /// generous outer/card padding) pushed `skipButton`, at the very bottom, to only ~25pt above
    /// the screen edge (measured `y=819` on an 852pt-tall iPhone 15 Pro) — inside the zone iOS
    /// reserves for the home-indicator swipe gesture. XCUITest's synthesized tap still reported
    /// the button `hittable`, but the OS silently ate the touch before SwiftUI's `Button` ever
    /// saw it, so `Skip`'s action never ran — no crash, no error, just a tap that did nothing
    /// (see `testOnboardingPanelShowsOnceAfterSignIn`'s own note on this). 490 here, plus the
    /// tightened outer/card padding just below, together shrink the whole card enough to clear
    /// that zone with margin (measured `y=750`, ~93pt of clearance) while still leaving panel 2's
    /// two-line hint (the tallest panel content) room to wrap without truncating.
    private static let panelHeight: CGFloat = 490

    var body: some View {
        ZStack {
            StashColor.paper.ignoresSafeArea()
            GradientBackdrop(opacity: 0.3).ignoresSafeArea()

            GeometryReader { geo in
                ScrollView {
                    card
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity, minHeight: geo.size.height)
                }
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .accessibilityIdentifier("onboarding.panel")
    }

    private var card: some View {
        VStack(spacing: 14) {
            VStack(spacing: 8) {
                Text("How to easily stash")
                    .font(StashType.medium(size: 24))
                    .foregroundStyle(StashColor.ink)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("onboarding.title")

                Text("Save from any app: tap Share, then Stash.")
                    .font(StashType.body())
                    .foregroundStyle(StashColor.muted)
                    .multilineTextAlignment(.center)
            }

            TabView(selection: $pageIndex) {
                SharePanel()
                    .tag(0)
                    .accessibilityIdentifier("onboarding.panel.1")
                PickStashPanel()
                    .tag(1)
                    .accessibilityIdentifier("onboarding.panel.2")
                SavePanel()
                    .tag(2)
                    .accessibilityIdentifier("onboarding.panel.3")
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: Self.panelHeight)
            // Matches the "Next" button's own animation so a swipe and a tap read identically —
            // plan 13 Global Constraints: "Swipe + Next both animate
            // withAnimation(.easeInOut(duration: 0.25))."
            .animation(.easeInOut(duration: 0.25), value: pageIndex)

            dots

            VStack(spacing: 10) {
                primaryButton
                skipButton
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .frame(maxWidth: 400)
        .background(StashColor.paper, in: RoundedRectangle(cornerRadius: StashRadius.sheet, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StashRadius.sheet, style: .continuous)
                .strokeBorder(StashColor.hairline, lineWidth: 1)
        )
        .stashCardShadow()
    }

    // MARK: - Dots

    /// Custom dots (not the system page-index dots `.page` would otherwise draw): active = a
    /// 24×6 violet600 capsule, inactive = a plain 6pt circle — plan 13 Global Constraints.
    private var dots: some View {
        HStack(spacing: 7) {
            ForEach(0..<Self.panelCount, id: \.self) { i in
                Capsule()
                    .fill(i == pageIndex ? StashColor.violet600 : StashColor.ink.opacity(0.15))
                    .frame(width: i == pageIndex ? 24 : 6, height: 6)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: pageIndex)
        .accessibilityIdentifier("onboarding.dots")
    }

    // MARK: - Actions

    /// "Next" on panels 1-2, "Got it" on panel 3 — same identifier (`onboarding.gotIt`) in every
    /// state so callers/tests never need to know which label is currently showing, only that the
    /// primary button exists.
    private var primaryButton: some View {
        Button {
            if pageIndex < Self.panelCount - 1 {
                withAnimation(.easeInOut(duration: 0.25)) {
                    pageIndex += 1
                }
            } else {
                OnboardingState.markHowToStashSeen()
                dismiss()
            }
        } label: {
            Text(pageIndex == Self.panelCount - 1 ? "Got it" : "Next")
                .font(StashType.bodyMedium())
                .frame(maxWidth: .infinity, minHeight: 52)
        }
        .foregroundStyle(.white)
        .background(StashColor.violet600, in: RoundedRectangle(cornerRadius: StashRadius.input, style: .continuous))
        .accessibilityIdentifier("onboarding.gotIt")
    }

    /// Marks the panel seen (see this type's own doc comment for why Skip is not "later") and
    /// dismisses immediately regardless of which panel is showing.
    private var skipButton: some View {
        Button {
            OnboardingState.markHowToStashSeen()
            dismiss()
        } label: {
            Text("Skip")
                .font(StashType.body())
                .foregroundStyle(StashColor.muted)
        }
        .accessibilityIdentifier("onboarding.skip")
    }
}

// MARK: - Panel chrome (shared layout: kicker, title, art, caption, optional hint)

/// The column every panel shares: `STEP N` kicker, panel title, an art slot sized by the caller
/// (each concrete panel's own art already reports the shared 172×344 footprint — see
/// `HowToStashView.panelHeight`'s doc comment), caption, and an optional hint line (panel 2 only).
private struct OnboardingPanelChrome<Art: View>: View {
    let step: Int
    let title: String
    let caption: String
    var hint: String?
    @ViewBuilder var art: Art

    var body: some View {
        VStack(spacing: 14) {
            Text("STEP \(step)")
                .font(StashType.microLabel())
                .stashTracking(0.11, size: 11)
                .foregroundStyle(StashColor.violet600)

            Text(title)
                .font(StashType.semibold(size: 18))
                .foregroundStyle(StashColor.ink)
                .multilineTextAlignment(.center)

            art

            Text(caption)
                .font(StashType.regular(size: 13.5))
                .foregroundStyle(StashColor.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 240)

            if let hint {
                Text(hint)
                    .font(StashType.meta())
                    .foregroundStyle(StashColor.faint)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 230)
            }
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

// MARK: - Panel 1 — "Look for the share button"

private struct SharePanel: View {
    var body: some View {
        OnboardingPanelChrome(
            step: 1,
            title: "Look for the share button",
            caption: "In Safari, Photos, or any app, tap Share."
        ) {
            ShareGlyphArt()
        }
    }
}

/// Not a screenshot — a large SF Symbol quoting the OS's own Share icon, on a white tile with the
/// standard card shadow. Centered inside the shared 172×344 art footprint (see
/// `HowToStashView.panelHeight`'s doc comment) the same way the prototype's `.shot--glyph`
/// variant centers it inside its own invisible, same-size box.
private struct ShareGlyphArt: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(StashColor.paper)
            .frame(width: 160, height: 160)
            .overlay(
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 60, weight: .regular))
                    // The ONE non-token color on this screen, and deliberately so: this glyph
                    // quotes iOS's own Share icon — the exact button the user is hunting for in
                    // Safari/Photos/any other app — so it needs to read as "the real system
                    // button," not a Stash-branded illustration recolored in violet600. Plan 13
                    // Global Constraints calls this out explicitly as the sanctioned exception.
                    .foregroundStyle(Color(uiColor: .systemBlue))
            )
            .stashCardShadow()
            .frame(width: 172, height: 344)
    }
}

// MARK: - Panel 2 — "Pick Stash"

private struct PickStashPanel: View {
    var body: some View {
        OnboardingPanelChrome(
            step: 2,
            title: "Pick Stash",
            caption: "Choose Stash in the share sheet.",
            hint: "Don't see Stash? Tap More, then add Stash to your favorites."
        ) {
            MockShareSheet()
        }
    }
}

/// A native mock of the iOS share sheet's top portion — not a device screenshot (the real
/// `onboarding.step2` capture was too tight a crop to show the app-icon row at all). Grabber,
/// three app tiles (a neutral "Reminders" stand-in, the real Stash icon glowing, and "More"),
/// then a grouped white action list (Copy Photo / Add to Album / AirPlay) matching a real share
/// sheet's structure below it. Fills the shared 172×344 art footprint with a wash background,
/// content top-aligned with padding — the box reads as a peek of a taller sheet, cut off, same as
/// the prototype's `.shot--sheet`.
private struct MockShareSheet: View {
    // 44pt — the prototype's own `.share-tile` size. A 60pt tile (the "standard Home Screen
    // icon size" `onboarding.stashTile`'s 1024px source was cropped to describe, per plan 13's
    // Global Constraints) does not fit three tiles across the shared 172pt-wide art footprint at
    // any legible label size — measured against the rendered prototype PNG, all three tiles
    // (including Stash) sit at this same 44pt, not enlarged for emphasis; the glow ring is what
    // draws the eye instead.
    private let tileSize: CGFloat = 44
    private let tileRadius: CGFloat = 11
    private let sheetRadius: CGFloat = 14

    var body: some View {
        VStack(spacing: 16) {
            Capsule()
                .fill(Color.black.opacity(0.18))
                .frame(width: 34, height: 4)

            HStack(spacing: 10) {
                neutralTile(systemImage: "checklist", label: "Reminders")
                stashTile
                neutralTile(systemImage: "ellipsis", label: "More")
            }

            actionList
        }
        .padding(.top, 14)
        .padding(.horizontal, 10)
        .padding(.bottom, 12)
        .frame(width: 172, height: 344, alignment: .top)
        .background(StashColor.wash, in: RoundedRectangle(cornerRadius: sheetRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: sheetRadius, style: .continuous)
                .strokeBorder(StashColor.hairline, lineWidth: 1)
        )
    }

    private func neutralTile(systemImage: String, label: String) -> some View {
        VStack(spacing: 5) {
            RoundedRectangle(cornerRadius: tileRadius, style: .continuous)
                .fill(StashColor.paper)
                .frame(width: tileSize, height: tileSize)
                .overlay(
                    RoundedRectangle(cornerRadius: tileRadius, style: .continuous)
                        .strokeBorder(StashColor.hairline, lineWidth: 1)
                )
                .overlay(
                    Image(systemName: systemImage)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(StashColor.muted)
                )
            Text(label)
                .font(StashType.regular(size: 9))
                .foregroundStyle(StashColor.ink)
                .fixedSize()
        }
    }

    /// The tile the whole panel is pointing at — real app icon (`onboarding.stashTile`, cropped
    /// from `AppIcon-1024.png`) plus the glowing ring/halo from `StashTileGlow`.
    private var stashTile: some View {
        VStack(spacing: 5) {
            Image("onboarding.stashTile")
                .resizable()
                .scaledToFill()
                .frame(width: tileSize, height: tileSize)
                .clipShape(RoundedRectangle(cornerRadius: tileRadius, style: .continuous))
                .modifier(StashTileGlow(cornerRadius: tileRadius))
            Text("Stash")
                .font(StashType.regular(size: 9))
                .foregroundStyle(StashColor.ink)
                .fixedSize()
        }
    }

    private var actionList: some View {
        VStack(spacing: 0) {
            actionRow(systemImage: "doc.on.doc", label: "Copy Photo")
            hairlineDivider
            actionRow(systemImage: "rectangle.stack.badge.plus", label: "Add to Album")
            hairlineDivider
            actionRow(systemImage: "airplayvideo", label: "AirPlay")
        }
        .background(StashColor.paper, in: RoundedRectangle(cornerRadius: tileRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: tileRadius, style: .continuous)
                .strokeBorder(StashColor.hairline, lineWidth: 1)
        )
    }

    private var hairlineDivider: some View {
        Rectangle().fill(StashColor.hairline).frame(height: 1)
    }

    private func actionRow(systemImage: String, label: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(StashColor.muted)
                .frame(width: 13)
            Text(label)
                .font(StashType.regular(size: 10))
                .foregroundStyle(StashColor.ink)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }
}

/// The Stash tile's glowing ring — plan 13 Global Constraints: "a 1px violet600 ring + violet
/// glow (shadow color violet300 @0.45, radius pulsing 6→14pt, 1.6s autoreverse; honors
/// `accessibilityReduceMotion` → static)." The ring itself never moves or scales — only the
/// shadow's blur radius animates — so reduced motion only needs to freeze that one number instead
/// of tearing out a whole animation graph; it lands on 10 (the pulse's midpoint) so the glow reads
/// at roughly its average intensity rather than snapping to either extreme.
private struct StashTileGlow: ViewModifier {
    let cornerRadius: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsedOut = false

    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(StashColor.violet600, lineWidth: 1)
            )
            .shadow(
                color: StashColor.violet300.opacity(0.45),
                radius: reduceMotion ? 10 : (pulsedOut ? 14 : 6)
            )
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                    pulsedOut = true
                }
            }
    }
}

// MARK: - Panel 3 — "Add a note, save"

private struct SavePanel: View {
    var body: some View {
        OnboardingPanelChrome(
            step: 3,
            title: "Add a note, save",
            caption: "Add an optional note, then Save. Stash does the rest."
        ) {
            Image("onboarding.step3")
                .resizable()
                .scaledToFill()
                .frame(width: 172, height: 344)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(StashColor.hairline, lineWidth: 1)
                )
                .shadow(color: Color(hex: 0x1E212C).opacity(0.10), radius: 10, y: 6)
        }
    }
}

#Preview {
    HowToStashView()
}
