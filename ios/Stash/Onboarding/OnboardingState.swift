import Foundation

/// Gating for the post-sign-in "How to easily stash" panel — plan 12, task 4 (Will's device
/// note 10): shown ONCE per app install, immediately after a successful sign-in/sign-up, and
/// re-openable any time from Settings → "How to stash". `UserDefaults.standard` (not the
/// Keychain-backed session) is the right store here — this is a pure "have we shown this piece
/// of UI before" flag scoped to the install, not to the signed-in account, so it deliberately
/// does NOT reset when `SessionStore` signs a user out/in again (that's `--uitest-reset-auth`'s
/// job, a separate concern — see `SessionStore.start()`'s DEBUG block).
enum OnboardingState {
    static let howToStashSeenKey = "onboarding.howToStash.seen"

    /// `false` until "Got it" is tapped once. "Show me later" deliberately leaves this `false` —
    /// the panel is meant to reappear next sign-in in that case (spec: "Show me later" does NOT
    /// set the seen flag).
    static var hasSeenHowToStash: Bool {
        UserDefaults.standard.bool(forKey: howToStashSeenKey)
    }

    /// "Got it" — the only action that permanently retires the panel for this install.
    static func markHowToStashSeen() {
        UserDefaults.standard.set(true, forKey: howToStashSeenKey)
    }

    #if DEBUG
    /// UI-test repeatability, same family as `SessionStore`'s `--uitest-reset-auth` handling:
    /// clears the flag so `testOnboardingPanelShowsOnceAfterSignIn` can force the panel to show
    /// again on its next sign-in regardless of what a prior run left behind on this simulator.
    /// Wired from the `--uitest-reset-onboarding` launch argument in `SessionStore.start()`.
    static func resetHowToStashSeenForTests() {
        UserDefaults.standard.removeObject(forKey: howToStashSeenKey)
    }
    #endif
}
