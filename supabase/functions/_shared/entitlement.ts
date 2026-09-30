// supabase/functions/_shared/entitlement.ts
//
// Server-side paywall decision (punch list B5). Mirrors the web client's rule
// in src/hooks/useSubscription.tsx: block only on a definitive lapsed answer.
// "No subscription yet" ('none'), unknown, or an errored lookup all stay
// permissive, so the signup → trial-creation race can never block a first
// save, and a Stripe outage degrades to "last known answer", not "locked out".
//
// Import-free so it runs under Deno and vitest. The Deno adapter that wires
// Stripe + the subscription_status_cache table is entitlementGate.ts.

export interface CachedStatus {
  status: string | null;
  checked_at: string | null;
}

export interface EntitlementDeps {
  /** Last cached answer for this user, or null. May throw. */
  readCache: () => Promise<CachedStatus | null>;
  /** Persist a freshly fetched status. May throw; failures never block. */
  writeCache: (status: string) => Promise<void>;
  /** Ask Stripe. Resolves to a subscription status or 'none'. May throw. */
  fetchLiveStatus: () => Promise<string>;
  now?: () => number;
  maxAgeMs?: number;
}

export interface Entitlement {
  allowed: boolean;
  status: string | null;
  source: 'cache' | 'live' | 'fallback';
}

export const DEFAULT_MAX_AGE_MS = 5 * 60_000;

// Every Stripe status that means "was subscribed, is not anymore". Anything
// else — trialing, active, 'none', or nothing known — passes.
export const BLOCKING_STATUSES: ReadonlySet<string> = new Set([
  'past_due',
  'unpaid',
  'canceled',
  'incomplete',
  'incomplete_expired',
  'paused',
]);

export const ENTITLEMENT_DENIED = {
  error: 'subscription_required',
  message: 'Your trial has ended. Add a payment method at gostash.it/settings to keep capturing and asking.',
} as const;

export const isBlockingStatus = (status: string | null | undefined): boolean =>
  !!status && BLOCKING_STATUSES.has(status);

export const isCacheFresh = (cached: CachedStatus | null, nowMs: number, maxAgeMs: number): boolean => {
  if (!cached?.checked_at) return false;
  const checked = Date.parse(cached.checked_at);
  return Number.isFinite(checked) && nowMs - checked < maxAgeMs;
};

export async function checkEntitlement(deps: EntitlementDeps): Promise<Entitlement> {
  const now = deps.now?.() ?? Date.now();
  const maxAge = deps.maxAgeMs ?? DEFAULT_MAX_AGE_MS;

  let cached: CachedStatus | null = null;
  try {
    cached = await deps.readCache();
  } catch {
    cached = null;
  }

  if (isCacheFresh(cached, now, maxAge)) {
    const status = cached?.status ?? null;
    return { allowed: !isBlockingStatus(status), status, source: 'cache' };
  }

  try {
    const status = await deps.fetchLiveStatus();
    try {
      await deps.writeCache(status);
    } catch {
      // cache is an optimisation; the live answer still stands
    }
    return { allowed: !isBlockingStatus(status), status, source: 'live' };
  } catch {
    const status = cached?.status ?? null;
    return { allowed: !isBlockingStatus(status), status, source: 'fallback' };
  }
}
