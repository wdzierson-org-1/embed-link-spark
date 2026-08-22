import Foundation
import Observation
import Supabase

// MARK: - SubscriptionStatus

/// Decodes `check-subscription`'s response (supabase/functions/check-subscription/index.ts:48-56,
/// 75-87,123-131). That JSON is entirely camelCase and carries more fields than gating needs —
/// `subscriptionStatus`, `trialEnd`, `subscriptionEnd`, `productId`, `hasStripeCustomer` — which
/// this type intentionally omits (Codable synthesis ignores unmatched keys).
///
/// Disclosure vs. the task brief's sketch: the brief proposed snake_case `CodingKeys` (`on_trial`,
/// `days_left`), matching what the *web hook* (useSubscription.tsx:86-93) reads off `data` in
/// camelCase JS — but the edge function itself never emits snake_case at all. The real keys are
/// `subscribed`, `onTrial`, and `daysLeftInTrial` (always a plain number, 0 when not trialing —
/// never `null`). `subscribed`/`onTrial` already match their Swift property names one-for-one, so
/// they need no remapping; only `daysLeft` needs a `CodingKeys` entry, pointed at
/// `daysLeftInTrial` instead of the brief's guessed `days_left`.
public struct SubscriptionStatus: Codable, Equatable, Sendable {
    public var subscribed: Bool
    public var onTrial: Bool
    public var daysLeft: Int?

    enum CodingKeys: String, CodingKey {
        case subscribed, onTrial
        case daysLeft = "daysLeftInTrial"
    }

    public init(subscribed: Bool, onTrial: Bool, daysLeft: Int?) {
        self.subscribed = subscribed
        self.onTrial = onTrial
        self.daysLeft = daysLeft
    }
}

// MARK: - SubscriptionChecking

public protocol SubscriptionChecking: Sendable {
    func check() async throws -> SubscriptionStatus
    func createTrial() async throws
}

/// Thin Supabase-backed adapter — mirrors `SupabaseChatHistory`/`SupabaseEmbeddingSyncer`'s shape
/// (call `StashClient.shared.functions.invoke`, no local state), untested directly since it's a
/// pass-through; `SubscriptionStore`'s own tests exercise the gate/self-heal logic against a stub.
public struct SupabaseSubscriptionChecker: SubscriptionChecking {
    public init() {}

    /// Web calls `supabase.functions.invoke('check-subscription')` with no body — the edge
    /// function reads the user solely off the `Authorization` header (index.ts:33-40).
    public func check() async throws -> SubscriptionStatus {
        try await StashClient.shared.functions.invoke("check-subscription")
    }

    /// Web calls `supabase.functions.invoke('create-trial-subscription')` with no body either;
    /// its response (`{success, subscriptionId, status, trialEnd}` or, when a subscription
    /// already exists, `{message, status}` — create-trial-subscription/index.ts:63-69,101-106)
    /// isn't needed here, so this uses the no-decode `invoke` overload and discards it.
    public func createTrial() async throws {
        try await StashClient.shared.functions.invoke("create-trial-subscription")
    }
}

// MARK: - SubscriptionStore

/// Port of `useSubscription.tsx`'s gate semantics (SubscriptionProvider, :37-216). One boolean —
/// `loading || onTrial || subscribed` — drives every feature gate on the web
/// (canAddContent/canUseAI/canSearch/canAccessFullFeatures all alias the same `hasAccess`,
/// :188-192); this store keeps `canAddContent`/`canUseAI` as the two gates StashKit needs, both
/// defined the same way.
@MainActor
@Observable
public final class SubscriptionStore {
    public private(set) var status: SubscriptionStatus?
    /// Starts `true` — matching the web's `useState(true)` for `loading` — so a view that reads
    /// the gates before the first `refresh()` completes fails open rather than blocking a
    /// brand-new session's first save (useSubscription.tsx:48,188).
    public private(set) var isLoading = true
    public private(set) var lastError: String?

    public var canAddContent: Bool { isLoading || status?.onTrial == true || status?.subscribed == true }
    public var canUseAI: Bool { canAddContent }   // same boolean on web (useSubscription.tsx:188-192)

    private let checker: SubscriptionChecking
    /// Set the moment a self-heal is attempted (success or failure) — never reset — so it fires
    /// at most once per store lifetime, matching `trialEnsuredRef` (useSubscription.tsx:49,68).
    private var triedTrial = false

    /// Plan-4 named requirement (docs/superpowers/plans/2026-08-11-ios-plan-3-parity.md's
    /// post-review addendum) — mirrors `ItemStore.loadGeneration`. Bumped at the start of every
    /// `refresh()` and by `reset()`. Lets a `refresh()` still in flight recognize, once it
    /// resolves, that a newer `refresh()` — or a `reset()` (cross-account sign-out/in) — has
    /// since superseded it, so it can drop its own stale result instead of clobbering state a
    /// fresher call or an intentional reset already wrote.
    private var refreshGeneration = 0

    /// Plan 5 Task 7: the key `gateCacheWrite`'s default writes into `UserDefaults(suiteName:
    /// AppGroup.identifier)` — the share extension's ONLY window into this store's gate, since the
    /// extension has no `SubscriptionStore` of its own and must never make a network call just to
    /// decide whether Save is enabled (every extension flow in this plan's own "never block or
    /// delay a save" constraint). `ShareComposeView`'s read side uses this exact same key. The
    /// key's ABSENCE (never written yet — a fresh install, or an app that predates this task) is
    /// the documented fail-open signal; a written `false` is a real, meaningful "closed" the
    /// extension must honor, never mistaken for "missing".
    /// `nonisolated` — a plain immutable `String` is trivially `Sendable`, but `@MainActor` on the
    /// enclosing class isolates its static members too by default; without this, the default
    /// `gateCacheWrite` closure below (a `@Sendable` value, callable off the main actor) can't read
    /// it (Swift 6 mode: hard error; today: warning). `ShareComposeView` (the extension, a
    /// different module/target entirely) also reads this constant directly.
    public nonisolated static let gateCacheKey = "subscription.canAddContent"

    /// Injectable (Task 7) so tests can observe every write without touching real `UserDefaults` —
    /// same "app supplies the real platform touch point, tests inject a recorder" precedent as
    /// `CaptureViewModel`'s `upload`/`downscale`/`awaitPendingLocation` closures. The default is
    /// `#if os(iOS)`-gated for the SAME reason `AppGroup.containerURL()`/
    /// `SharedKeychainStorage.resolvedAccessGroup` are (see their doc comments): an unsigned macOS
    /// `swift test` host isn't sandboxed, so an ungated `UserDefaults(suiteName:)` write here would
    /// silently create/mutate a real preferences file under the developer's own machine on every
    /// test that doesn't inject a custom `gateCacheWrite` (i.e. every EXISTING `SubscriptionStoreTests`
    /// case) — gating keeps `swift test` hermetic unconditionally, exactly like those two.
    private let gateCacheWrite: @Sendable (Bool) -> Void

    public init(
        checker: SubscriptionChecking,
        gateCacheWrite: @escaping @Sendable (Bool) -> Void = { canAddContent in
            #if os(iOS)
            UserDefaults(suiteName: AppGroup.identifier)?.set(canAddContent, forKey: SubscriptionStore.gateCacheKey)
            #endif
        }
    ) {
        self.checker = checker
        self.gateCacheWrite = gateCacheWrite
    }

    /// useSubscription.tsx:51-108 — check, and if the account looks brand-new (neither subscribed
    /// nor trialing) self-heal by creating a trial and re-checking, once per store lifetime, so a
    /// first save is never blocked by the signup/Stripe race.
    ///
    /// Disclosure — two adaptations from the web:
    /// 1. Trigger condition: the web fires self-heal on `!data.subscriptionStatus`, `null` only
    ///    for a customer with no subscription at all (not e.g. "canceled"/"past_due"). This port's
    ///    minimal `SubscriptionStatus` doesn't carry `subscriptionStatus`, so the trigger here is
    ///    `!subscribed && !onTrial` — also true for a lapsed subscriber. That's broader but
    ///    harmless: `create-trial-subscription`'s own guard (index.ts:60-70) no-ops with a 200
    ///    whenever any subscription has ever existed, so an extra attempt costs a network call and
    ///    nothing else.
    /// 2. Self-heal failure handling: if `createTrial()` or the post-trial re-check throws, this
    ///    falls back to the already-fetched pre-heal `status` silently, rather than the web's
    ///    behavior of resetting every field to closed/error defaults when specifically the
    ///    post-trial re-check fails (useSubscription.tsx:67-73's reassigned `data`/`error` then
    ///    flows into the `if (error)` reset branch, :75-84). No test exercises this branch; the
    ///    softer fallback avoids flipping gates closed over what's likely a transient hiccup
    ///    immediately after a successful initial check.
    public func refresh() async {
        // Generation token (plan-4 named requirement, mirrors `ItemStore.loadGeneration`): bump
        // first, capture locally, guard every write below on the captured value still matching —
        // so if a newer `refresh()` or a `reset()` supersedes this call before it resolves, its
        // (stale) result is silently dropped instead of clobbering whatever the newer call or the
        // reset already wrote.
        refreshGeneration += 1
        let generation = refreshGeneration

        // `isLoading` is a one-shot first-check flag (web parity: useSubscription's `loading`
        // never re-arms) — later refreshes must not fail-open, so this must never set it back to
        // `true` here; the initializer's `isLoading = true` plus this `defer` are the entire
        // lifecycle. Re-arming it on every call would transiently open the gates for an
        // unsubscribed user during each poll's network round-trip — a leak the web doesn't have.
        //
        // No extra cancellation guard needed on the flip itself: by the time any refresh
        // *Settings' own polling* (SubscriptionSection, Task 7) could ever cancel mid-flight has
        // run, `isLoading` is already `false` — StashApp's launch refresh (fires the moment
        // `SessionStore.state` becomes `.signedIn`) always starts, and normally finishes, before
        // the user can navigate to the Settings tab in the first place. A refresh cancelled
        // before that very first flip would still leave `isLoading` true here — just not a path
        // Settings' own polling can reach. The generation guard below still applies to this flip
        // too, though: without it, a stale refresh resolving after `reset()` re-arms `isLoading`
        // for the next account would flip it back to `false` under that account before its own
        // first refresh ever lands.
        defer {
            if generation == refreshGeneration {
                isLoading = false
                // Task 7: fires on every settled resolve (success, self-heal, or a real —
                // non-cancelled — failure) with the FINAL `canAddContent` for this call, computed
                // AFTER the `isLoading` flip above so a fresh session's first resolve caches the
                // real status, not the pre-flip fail-open `true`. The SAME generation guard as
                // `isLoading`'s own flip excludes a superseded (stale-generation) resolve, so a
                // slow refresh that's since been overtaken by a newer `refresh()` or a `reset()`
                // can never overwrite the cache with a stale value.
                gateCacheWrite(canAddContent)
            }
        }
        do {
            var result = try await checker.check()
            guard generation == refreshGeneration else { return }   // superseded while check() was in flight
            if !result.subscribed, !result.onTrial, !triedTrial {
                triedTrial = true
                if let healed = try? await selfHeal() {
                    result = healed
                }
                guard generation == refreshGeneration else { return }   // ...or while the self-heal re-check was in flight
            }
            status = result
            lastError = nil
        } catch {
            // Review Critical (Task 7 fix round): a cancelled poll is not a failed check.
            // Settings' while-visible 30s poll cancels an in-flight `refresh()` the instant the
            // user switches tabs mid-network-call — treating that `CancellationError` like any
            // other failure wiped `status` to `nil` here, closing every gate (composer Save, Ask)
            // app-wide for an already-subscribed user, with no prompt recovery short of
            // revisiting Settings or a foreground cycle. Leave `status`/`lastError` exactly as
            // they were; only `isLoading` (via the `defer` above) still resolves either way.
            //
            // Plan-4 named requirement: widened to also match `URLError(.cancelled)` — Settings'
            // poll cancels the `Task` running `refresh()`, but that cancellation can surface from
            // underneath `checker.check()`'s network call as a transport-level `URLError` instead
            // of (or in addition to) Swift's `CancellationError`, which `is CancellationError`
            // alone does not catch.
            if error is CancellationError || (error as? URLError)?.code == .cancelled { return }
            guard generation == refreshGeneration else { return }
            // Web parity (plan-4 Task 6b, commit 42c2e67: "fail-open subscription errors"): a
            // transient error checking subscription status does NOT wipe the last known status —
            // an errored check means unknown, not unsubscribed. Keep gates open on a prior
            // success while connection hiccups or other transient failures resolve. Only set
            // `lastError` for UI reporting; never nil `status`.
            lastError = "Couldn't check your subscription status."
        }
    }

    private func selfHeal() async throws -> SubscriptionStatus {
        try await checker.createTrial()
        return try await checker.check()
    }

    /// Cross-account gate-bleed fix (final review, plan 3): call this the instant a session
    /// ends (StashApp's session `.onChange`, on `.signedOut`). This store is app-lifetime —
    /// constructed once in `StashApp` and handed down via environment — so without a reset,
    /// user A's `status` (and any gates A left open) would otherwise persist verbatim into
    /// user B's session until B's own first `refresh()` landed, and indefinitely if that
    /// refresh was ever cancelled. (Web clears its equivalent state the moment `user` goes
    /// `null`: useSubscription.tsx:53-58.)
    ///
    /// Resets `status`/`lastError` to their initializer defaults and re-arms both per-session
    /// flags: `triedTrial = false`, so the next account — a genuinely different account,
    /// possibly itself brand-new — gets its own one-time trial self-heal rather than
    /// inheriting A's already-spent attempt; and `isLoading = true`, putting the store back in
    /// the exact pre-first-refresh state the initializer starts in (see that property's doc
    /// comment above), so the next account's first `refresh()` fails open exactly like a fresh
    /// launch instead of inheriting A's last resolved `canAddContent` value — open *or*
    /// closed — for however long B's own check takes.
    ///
    /// Plan-4 named requirement (post-review addendum to the plan-3 doc above): also bumps
    /// `refreshGeneration`, so a `refresh()` that was already in flight for account A when this
    /// fires can't land its (now-stale) result over account B's freshly-reset state — the narrow
    /// same-device-account-switch race the unconditional resets alone didn't cover.
    public func reset() {
        status = nil
        lastError = nil
        triedTrial = false
        isLoading = true
        refreshGeneration += 1
        // Task 7: re-opens the CACHE the instant a session ends, matching `isLoading`'s own
        // re-arm-to-fail-open above — without this, a share extension launched between this
        // sign-out and the next account's first `refresh()` landing would still read WHATEVER the
        // prior account last cached (open or closed), rather than the fail-open state a fresh,
        // not-yet-checked session is supposed to present.
        gateCacheWrite(canAddContent)
    }
}
