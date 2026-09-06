import Foundation

/// Gating for the post-sign-in "How to easily stash" panel — plan 12, task 4 (Will's device
/// note 10): shown ONCE per app install, immediately after a successful sign-in/sign-up, and
/// re-openable any time from Settings → "How to stash". `UserDefaults.standard` (not the
/// Keychain-backed session) is the right store here — this is a pure "have we shown this piece
/// of UI before" flag scoped to the install, not to the signed-in account, so it deliberately
/// does NOT reset when `SessionStore` signs a user out/in again (that's `--uitest-reset-auth`'s
/// job, a separate concern — see `SessionStore.start()`'s DEBUG block).
///
/// ## The showing rule (final wave, F4 — whole-branch review)
///
/// The panel is presented by `StashApp`'s `onChange(of: session.state)` on a transition INTO
/// `.signedIn` (cold-launch Keychain restore counts as much as a fresh sign-in — see that
/// callsite's own doc comment) exactly when:
///
///     !hasSeenHowToStash && !isHowToStashDeferred
///
/// `hasSeenHowToStash` is permanent (only "Got it" sets it — see `markHowToStashSeen()`).
/// `isHowToStashDeferred` is temporary and exists ONLY to fix a bug the first version of this
/// panel had: "Show me later" left `hasSeenHowToStash` false so the NEXT COLD LAUNCH — not just
/// the next real sign-in — re-showed the panel, which on a simulator/device left running for a
/// while reads as "this thing won't stop nagging me every time I reopen the app." The fix
/// distinguishes the two: `markHowToStashDeferred()` (wired to "Show me later") sets a SEPARATE
/// flag that suppresses the panel across cold launches, and `clearHowToStashDeferred()` — wired
/// to `StashApp`'s own `.signedOut → .signedIn` transition, i.e. an EXPLICIT user sign-in, never
/// a Keychain restore — clears it again, so deferring the panel once doesn't suppress it forever
/// (a sign-out/sign-in round trip, or a different account entirely, gets a fresh chance to show
/// it). Net effect: "Show me later" means "not now, but ask me again next time I actually sign
/// in" — not "never" and not "again in five seconds when I relaunch the app." A brand-new
/// install, or an existing session's first launch after upgrading to a build that HAS this flag
/// at all, still shows the panel once — neither flag has ever been set, so both default `false`.
enum OnboardingState {
    static let howToStashSeenKey = "onboarding.howToStash.seen"
    static let howToStashDeferredKey = "onboarding.howToStash.deferred"

    /// `false` until "Got it" is tapped once. "Show me later" deliberately leaves this `false` —
    /// the panel is meant to reappear on a future real sign-in in that case (see this type's own
    /// doc comment for the full showing rule) — `markHowToStashDeferred()` below is what actually
    /// suppresses the immediate re-show "Show me later" needs.
    static var hasSeenHowToStash: Bool {
        UserDefaults.standard.bool(forKey: howToStashSeenKey)
    }

    /// "Got it" — the only action that permanently retires the panel for this install.
    static func markHowToStashSeen() {
        UserDefaults.standard.set(true, forKey: howToStashSeenKey)
    }

    /// `true` between a "Show me later" tap and the next EXPLICIT sign-in (see this type's doc
    /// comment) — while `true`, the panel stays suppressed even though `hasSeenHowToStash` is
    /// still `false`.
    static var isHowToStashDeferred: Bool {
        UserDefaults.standard.bool(forKey: howToStashDeferredKey)
    }

    /// "Show me later" — suppresses the panel until the next explicit sign-in, WITHOUT
    /// permanently retiring it the way `markHowToStashSeen()` does.
    static func markHowToStashDeferred() {
        UserDefaults.standard.set(true, forKey: howToStashDeferredKey)
    }

    /// Wired to `StashApp`'s `.signedOut → .signedIn` transition (an explicit user sign-in, never
    /// a cold-launch Keychain restore) — gives a deferred panel a fresh chance to show again.
    static func clearHowToStashDeferred() {
        UserDefaults.standard.removeObject(forKey: howToStashDeferredKey)
    }

    #if DEBUG
    /// UI-test repeatability, same family as `SessionStore`'s `--uitest-reset-auth` handling:
    /// clears BOTH flags so `testOnboardingPanelShowsOnceAfterSignIn` can force the panel to show
    /// again on its next sign-in regardless of what a prior run left behind on this simulator.
    /// Wired from the `--uitest-reset-onboarding` launch argument in `SessionStore.start()`.
    static func resetHowToStashSeenForTests() {
        UserDefaults.standard.removeObject(forKey: howToStashSeenKey)
        UserDefaults.standard.removeObject(forKey: howToStashDeferredKey)
    }
    #endif
}
