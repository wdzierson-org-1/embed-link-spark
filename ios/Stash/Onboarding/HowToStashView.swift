import SwiftUI

/// The one-panel post-sign-in "How to easily stash" screen — plan 12, task 4 (Will's device note
/// 10, verbatim): "a single panel 'How to easily stash' screen post-sign-in that reminds the user
/// they can use the Sharing intent from any app... basic screenshots that spell through how to
/// use the standard iOS share sheet, then choose the Stash icon."
///
/// Presented as a `.fullScreenCover` — see `StashApp.swift`'s `onChange(of: session.state)` for
/// the once-per-install gate (`OnboardingState`) and `SettingsView`'s "How to stash" row for the
/// any-time re-entry point. Visually mirrors `SignInView`'s own "one paper card floating on the
/// ambient gradient wash" shape (`GradientBackdrop` + `StashRadius.sheet` card + `stashCardShadow`)
/// rather than inventing a new panel chrome — same tokens, same recipe, different content.
///
/// Self-contained: both buttons dismiss via `\.dismiss` (works because SwiftUI supplies that
/// environment action automatically for anything presented via `.fullScreenCover`/`.sheet`), so
/// neither `StashApp` nor `SettingsView` needs to pass a completion closure down — they only ever
/// need a `Bool` binding to trigger presentation.
struct HowToStashView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            StashColor.paper.ignoresSafeArea()
            GradientBackdrop(opacity: 0.3).ignoresSafeArea()

            GeometryReader { geo in
                ScrollView {
                    card
                        .padding(.horizontal, 20)
                        .padding(.vertical, 40)
                        .frame(maxWidth: .infinity, minHeight: geo.size.height)
                }
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .accessibilityIdentifier("onboarding.panel")
    }

    private var card: some View {
        VStack(spacing: 24) {
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

            stepsStrip

            VStack(spacing: 12) {
                gotItButton
                showLaterButton
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 28)
        .frame(maxWidth: 400)
        .background(StashColor.paper, in: RoundedRectangle(cornerRadius: StashRadius.sheet, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StashRadius.sheet, style: .continuous)
                .strokeBorder(StashColor.hairline, lineWidth: 1)
        )
        .stashCardShadow()
    }

    // MARK: - Three-step strip

    private var stepsStrip: some View {
        HStack(alignment: .top, spacing: 12) {
            stepColumn(number: 1, caption: "Tap Share in Safari (or any app)", imageName: "onboarding.step1")
            stepColumn(number: 2, caption: "Pick Stash in the share sheet", imageName: "onboarding.step2")
            stepColumn(number: 3, caption: "Add an optional note and Save", imageName: "onboarding.step3")
        }
    }

    /// One step = a numbered micro-label, its caption, then a phone-frame-free portrait capture
    /// (real simulator screenshot, cropped to ~1:2 — see `task-4-report.md` for provenance per
    /// step). Fixed width/height rather than a `GeometryReader`-derived one: three of these need
    /// to sit comfortably inside the narrowest supported card width (iPhone SE, 375pt screen)
    /// with room to spare, which a hand-picked 78×156 (exactly 1:2) already covers.
    private func stepColumn(number: Int, caption: String, imageName: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("STEP \(number)")
                .font(StashType.microLabel())
                .stashTracking(0.11, size: 11)
                .foregroundStyle(StashColor.violet600)

            Text(caption)
                .font(StashType.meta())
                .foregroundStyle(StashColor.muted)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: 32, alignment: .top)

            Image(imageName)
                .resizable()
                .scaledToFill()
                .frame(width: 78, height: 156)
                .clipShape(RoundedRectangle(cornerRadius: StashRadius.input, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: StashRadius.input, style: .continuous)
                        .strokeBorder(StashColor.hairline, lineWidth: 1)
                )
                .accessibilityIdentifier("onboarding.step\(number).image")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Actions

    private var gotItButton: some View {
        Button {
            OnboardingState.markHowToStashSeen()
            dismiss()
        } label: {
            Text("Got it")
                .font(StashType.bodyMedium())
                .frame(maxWidth: .infinity, minHeight: 52)
        }
        .foregroundStyle(.white)
        .background(StashColor.violet600, in: RoundedRectangle(cornerRadius: StashRadius.input, style: .continuous))
        .accessibilityIdentifier("onboarding.gotIt")
    }

    /// Deliberately does NOT call `OnboardingState.markHowToStashSeen()` — spec: "'Show me
    /// later' does NOT [set the seen flag] (it reappears next sign-in)". Final wave (F4): DOES
    /// call `markHowToStashDeferred()` — the first version of this button left the panel eligible
    /// to re-show on the very next COLD LAUNCH, not just "next sign-in" as the copy promises; see
    /// `OnboardingState`'s own doc comment for the full rule this fixes.
    private var showLaterButton: some View {
        Button {
            OnboardingState.markHowToStashDeferred()
            dismiss()
        } label: {
            Text("Show me later")
                .font(StashType.body())
                .foregroundStyle(StashColor.muted)
        }
        .accessibilityIdentifier("onboarding.showLater")
    }
}

#Preview {
    HowToStashView()
}
