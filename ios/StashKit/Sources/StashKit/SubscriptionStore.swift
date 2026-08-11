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
    public var lastError: String?

    public var canAddContent: Bool { isLoading || status?.onTrial == true || status?.subscribed == true }
    public var canUseAI: Bool { canAddContent }   // same boolean on web (useSubscription.tsx:188-192)

    private let checker: SubscriptionChecking
    /// Set the moment a self-heal is attempted (success or failure) — never reset — so it fires
    /// at most once per store lifetime, matching `trialEnsuredRef` (useSubscription.tsx:49,68).
    private var triedTrial = false

    public init(checker: SubscriptionChecking) {
        self.checker = checker
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
        isLoading = true
        defer { isLoading = false }
        do {
            var result = try await checker.check()
            if !result.subscribed, !result.onTrial, !triedTrial {
                triedTrial = true
                if let healed = try? await selfHeal() {
                    result = healed
                }
            }
            status = result
            lastError = nil
        } catch {
            status = nil
            lastError = "Couldn't check your subscription status."
        }
    }

    private func selfHeal() async throws -> SubscriptionStatus {
        try await checker.createTrial()
        return try await checker.check()
    }
}
