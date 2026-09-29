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

/// Port of `useSubscription.tsx`'s gate semantics (SubscriptionProvider). One boolean drives every
/// feature gate on the web (canAddContent/canUseAI/canSearch/canAccessFullFeatures all alias the
/// same `hasAccess`); this store keeps `canAddContent`/`canUseAI` as the two gates the app needs,
/// both defined the same way.
@MainActor
@Observable
public final class SubscriptionStore {
    public private(set) var status: SubscriptionStatus?
    /// Starts `true` — matching the web's `useState(true)` for `loading` — so a view that reads
    /// the gates before the first check settles fails open rather than blocking a brand-new
    /// session's first save.
    public private(set) var isLoading = true
    public private(set) var lastError: String?

    /// Web parity (`useSubscription.tsx` `statusKnown`): `true` once the server has given a
    /// definitive answer this session — i.e. a check succeeded and `status` holds it — and `false`
    /// again after `reset()`. A failed check (offline, a `check-subscription` 5xx, a Stripe hiccup)
    /// never sets it: an errored check means "unknown", not "unsubscribed".
    public var statusKnown: Bool { status != nil }

    /// Plan 15 (H2), web parity (`hasAccess = loading || !statusKnown || trialing || active`): the
    /// gates close only on a DEFINITIVE "neither subscribed nor trialing". Until the server has
    /// answered — while the first check is in flight, or if every check so far has failed — they
    /// stay open: blocking a paying user over a transient error (an offline launch, a 5xx) is worse
    /// than letting a lapsed one through briefly, and the server enforces the paywall itself
    /// (`add-*` answers 403 `subscription_required`, which parks the capture in the Outbox).
    public var canAddContent: Bool {
        isLoading || !statusKnown || status?.onTrial == true || status?.subscribed == true
    }
    public var canUseAI: Bool { canAddContent }   // same boolean on web

    /// Plan 15 (snappiness): a successful check younger than this answers a non-forced `refresh()`
    /// without the network — so every `.active` (a Control Center pull, a system sheet, a quick
    /// app switch) stops hitting `check-subscription`. Settings passes `force: true`.
    public static let freshnessInterval: TimeInterval = 180

    private let checker: SubscriptionChecking
    private let now: @Sendable () -> Date
    /// Set the moment a self-heal is attempted (success or failure) — reset only by `reset()` — so
    /// it fires at most once per signed-in session, matching `trialEnsuredRef`.
    private var triedTrial = false

    /// Bumped whenever a check starts and by `reset()`. A check compares its own generation with
    /// this one before every write, so a check that a newer one or a `reset()` (cross-account
    /// sign-out/in) has superseded drops its stale result instead of clobbering fresher state.
    private var refreshGeneration = 0
    /// When the last check that settled with a definitive answer finished (`nil` after `reset()`).
    private var lastSuccessAt: Date?
    /// The check currently running, tagged with its generation — every `refresh()` that arrives
    /// while it is still current waits for it instead of sending a second request.
    private var inFlight: (generation: Int, task: Task<Void, Never>)?

    /// The key `gateCacheWrite`'s default writes into `UserDefaults(suiteName: AppGroup.identifier)`
    /// — the share extension's ONLY window into this store's gate, since the extension has no
    /// `SubscriptionStore` of its own and must never make a network call just to decide whether
    /// Save is enabled. `ShareComposeView` reads this exact key. Its ABSENCE (never answered yet, or
    /// cleared by `reset()`/account deletion) is the documented fail-open signal; a stored `false`
    /// is a real, definitive "closed" the extension honors.
    /// `nonisolated` — a plain immutable `String` is trivially `Sendable`, but `@MainActor` on the
    /// enclosing class isolates its static members too by default; the default `gateCacheWrite`
    /// closure (callable off the main actor) and the extension both read it.
    public nonisolated static let gateCacheKey = "subscription.canAddContent"

    /// Plan 15 (H2): called with the definitive gate (`onTrial || subscribed`) after every check
    /// that got an answer from the server, and with `nil` (remove the key — "unknown", which the
    /// extension treats as open) by `reset()`. Never after a failed or cancelled check: those keep
    /// whatever the last definitive answer cached, instead of writing a `false` no server ever
    /// gave. Injectable so tests can observe every write without touching real `UserDefaults`; the
    /// default is `#if os(iOS)`-gated so an unsandboxed macOS `swift test` host never writes a real
    /// preferences file (same reasoning as `AppGroup.containerURL()`).
    private let gateCacheWrite: @Sendable (Bool?) -> Void

    public init(
        checker: SubscriptionChecking,
        now: @escaping @Sendable () -> Date = { Date() },
        gateCacheWrite: @escaping @Sendable (Bool?) -> Void = { canAddContent in
            #if os(iOS)
            let defaults = UserDefaults(suiteName: AppGroup.identifier)
            if let canAddContent {
                defaults?.set(canAddContent, forKey: SubscriptionStore.gateCacheKey)
            } else {
                defaults?.removeObject(forKey: SubscriptionStore.gateCacheKey)
            }
            #endif
        }
    ) {
        self.checker = checker
        self.now = now
        self.gateCacheWrite = gateCacheWrite
    }

    /// Checks the subscription (useSubscription.tsx `checkSubscription`), and if the account looks
    /// brand-new (neither subscribed nor trialing) self-heals by creating a trial and re-checking,
    /// once per session, so a first save is never blocked by the signup/Stripe race.
    ///
    /// Plan 15 (snappiness), all behind this one call so every call site gets it:
    /// - **One check at a time.** A call made while a (current) check is running waits for that
    ///   check instead of sending another — a cold launch's "signed in" refresh and its first
    ///   `.active` refresh arrive together, and Settings appearing mid-check joins it too.
    /// - **Throttle.** A non-forced call returns at once when a check succeeded less than
    ///   `freshnessInterval` ago. `force: true` (Settings' on-appear refresh and while-visible
    ///   poll) always asks the server. A sign-out (`reset()`) forgets the last success, so the next
    ///   account's first refresh always goes to the network.
    /// - The check itself runs in its own task: a caller that goes away (Settings' `.task` is
    ///   cancelled on a tab switch) neither aborts it nor turns that into an error — the status
    ///   still lands.
    ///
    /// Disclosure — two adaptations from the web:
    /// 1. Trigger condition: the web fires self-heal on `!data.subscriptionStatus`, `null` only
    ///    for a customer with no subscription at all. This port's minimal `SubscriptionStatus`
    ///    doesn't carry `subscriptionStatus`, so the trigger is `!subscribed && !onTrial` — also
    ///    true for a lapsed subscriber. Broader but harmless: `create-trial-subscription` no-ops
    ///    with a 200 whenever any subscription has ever existed.
    /// 2. Self-heal failure: if `createTrial()` or the post-trial re-check throws, this keeps the
    ///    already-fetched pre-heal `status` (a definitive server answer) rather than the web's
    ///    reset-to-closed defaults.
    public func refresh(force: Bool = false) async {
        if let inFlight, inFlight.generation == refreshGeneration {
            await inFlight.task.value
            return
        }
        if !force, let lastSuccessAt, now().timeIntervalSince(lastSuccessAt) < Self.freshnessInterval {
            return
        }
        refreshGeneration += 1
        let generation = refreshGeneration
        let task = Task { await self.check(generation: generation) }
        inFlight = (generation, task)
        await task.value
        if inFlight?.generation == generation { inFlight = nil }
    }

    private func check(generation: Int) async {
        // `isLoading` is a one-shot first-check flag (web parity: `loading` never re-arms except
        // on a session change, `reset()`): later checks must never set it back to `true` — that
        // would transiently fail OPEN for a known-lapsed user during every poll's round trip. The
        // generation guard keeps a stale check that resolves after `reset()` from flipping it for
        // the next account before that account's own first check lands.
        defer {
            if generation == refreshGeneration { isLoading = false }
        }
        do {
            var result = try await checker.check()
            guard generation == refreshGeneration else { return }   // superseded while check() was in flight
            if !result.subscribed, !result.onTrial, !triedTrial {
                triedTrial = true
                if let healed = try? await selfHeal() {
                    result = healed
                }
                guard generation == refreshGeneration else { return }   // ...or while the self-heal ran
            }
            status = result
            lastError = nil
            lastSuccessAt = now()
            gateCacheWrite(result.onTrial || result.subscribed)
        } catch {
            // A cancelled check is not a failed check (`reset()` cancels a superseded one; a
            // cancellation can surface from URLSession as `URLError(.cancelled)` rather than
            // `CancellationError`). Nothing changes.
            if error is CancellationError || (error as? URLError)?.code == .cancelled { return }
            guard generation == refreshGeneration else { return }
            // Web parity ("fail-open subscription errors"): a failed check never wipes the last
            // known status, never writes the extension's cache, and — with no prior answer at all —
            // leaves the gates open (`statusKnown` stays false). Only `lastError` records it, for
            // Settings to show.
            lastError = "Couldn't check your subscription status."
        }
    }

    private func selfHeal() async throws -> SubscriptionStatus {
        try await checker.createTrial()
        return try await checker.check()
    }

    /// Cross-account gate-bleed fix: call this the instant a session ends (StashApp's session
    /// `.onChange`, on `.signedOut`). This store is app-lifetime, so without a reset user A's
    /// `status` — and any gates A left open or closed — would carry into user B's session until
    /// B's own first check landed. (Web clears its equivalent state the moment `user` goes `null`.)
    ///
    /// Puts the store back in its exact pre-first-check state: `status`/`lastError` cleared,
    /// `isLoading` re-armed (fail open until B's first answer), `triedTrial` re-armed (B gets its
    /// own one-time self-heal), the throttle forgotten (B's first refresh always asks the server),
    /// and the generation bumped + any running check cancelled, so A's in-flight answer can never
    /// land on B's state. The extension's cached gate is REMOVED (unknown → open) rather than left
    /// holding A's last answer.
    public func reset() {
        status = nil
        lastError = nil
        triedTrial = false
        isLoading = true
        lastSuccessAt = nil
        refreshGeneration += 1
        inFlight?.task.cancel()
        inFlight = nil
        gateCacheWrite(nil)
    }
}
