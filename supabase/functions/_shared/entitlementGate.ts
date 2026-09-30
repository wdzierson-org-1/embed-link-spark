// supabase/functions/_shared/entitlementGate.ts
//
// Deno adapter for the server-side paywall: wires entitlement.ts to Stripe and
// the service-role-only `subscription_status_cache` table. One call per
// request in add-note / add-url / add-file / chat-with-all-content:
//
//   const denied = await requireEntitlement(admin, user, corsHeaders);
//   if (denied) return denied;
//
// Fast path is a single PostgREST read (the client's 30 s check-subscription
// poll keeps the cache fresh); Stripe is only consulted when the cache is
// missing or older than DEFAULT_MAX_AGE_MS.

import Stripe from "https://esm.sh/stripe@18.5.0";
import { checkEntitlement, ENTITLEMENT_DENIED } from "./entitlement.ts";

const CACHE_TABLE = "subscription_status_cache";

// Minimal structural slice of a supabase-js client so callers on different
// supabase-js versions (2.7 … 2.57) all fit.
interface MaybeSingleResult {
  data: { status: string | null; checked_at: string | null } | null;
  error: { message: string } | null;
}
interface CacheClient {
  from(table: string): {
    select(columns: string): { eq(column: string, value: string): { maybeSingle(): Promise<MaybeSingleResult> } };
    upsert(row: Record<string, unknown>): PromiseLike<{ error: { message: string } | null }>;
  };
}

interface GateUser {
  id: string;
  email?: string | null;
}

export async function stripeSubscriptionStatus(
  email: string | null | undefined,
): Promise<{ status: string; customerId: string | null }> {
  const stripeKey = Deno.env.get("STRIPE_SECRET_KEY");
  if (!stripeKey) throw new Error("STRIPE_SECRET_KEY not set");
  if (!email) return { status: "none", customerId: null };

  const stripe = new Stripe(stripeKey, { apiVersion: "2025-08-27.basil" });
  const customers = await stripe.customers.list({ email, limit: 1 });
  if (customers.data.length === 0) return { status: "none", customerId: null };

  const customerId = customers.data[0].id;
  const subscriptions = await stripe.subscriptions.list({ customer: customerId, status: "all", limit: 1 });
  return { status: subscriptions.data[0]?.status ?? "none", customerId };
}

export async function requireEntitlement(
  admin: CacheClient,
  user: GateUser,
  corsHeaders: Record<string, string>,
): Promise<Response | null> {
  let customerId: string | null = null;

  const result = await checkEntitlement({
    readCache: async () => {
      const { data, error } = await admin.from(CACHE_TABLE).select("status, checked_at").eq("user_id", user.id).maybeSingle();
      if (error) throw new Error(error.message);
      return data;
    },
    fetchLiveStatus: async () => {
      const live = await stripeSubscriptionStatus(user.email);
      customerId = live.customerId;
      return live.status;
    },
    writeCache: async (status) => {
      const { error } = await admin.from(CACHE_TABLE).upsert({
        user_id: user.id,
        status,
        stripe_customer_id: customerId,
        checked_at: new Date().toISOString(),
      });
      if (error) throw new Error(error.message);
    },
  });

  if (result.allowed) return null;

  console.log("[ENTITLEMENT] denied", { userId: user.id, status: result.status, source: result.source });
  return new Response(JSON.stringify({ ...ENTITLEMENT_DENIED, status: result.status }), {
    status: 403,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
