// supabase/functions/stripe-webhook/index.ts
//
// Stripe → subscription_status_cache. Keeps the server-side paywall current
// the moment a subscription changes (trial ends, payment fails, customer
// cancels or resumes) instead of waiting for the next client poll.
//
// Setup (Will, once): Stripe Dashboard → Developers → Webhooks → add endpoint
//   https://uqqsgmwkvslaomzxptnp.supabase.co/functions/v1/stripe-webhook
// with the `customer.subscription.*` events, then
//   supabase secrets set STRIPE_WEBHOOK_SECRET=whsec_… --project-ref uqqsgmwkvslaomzxptnp
// Until that secret exists the function answers 503 and does nothing.
// verify_jwt is off in config.toml — Stripe authenticates with its signature.

import Stripe from "https://esm.sh/stripe@18.5.0";
import { createClient, type SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.57.2";

const CACHE_TABLE = "subscription_status_cache";

const log = (step: string, details?: unknown) => {
  const suffix = details === undefined ? "" : ` - ${JSON.stringify(details)}`;
  console.log(`[STRIPE-WEBHOOK] ${step}${suffix}`);
};

const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

async function findUserIdByEmail(admin: SupabaseClient, email: string): Promise<string | null> {
  const wanted = email.toLowerCase();
  for (let page = 1; page < 50; page++) {
    const { data, error } = await admin.auth.admin.listUsers({ page, perPage: 200 });
    if (error) throw new Error(`listUsers: ${error.message}`);
    const hit = data.users.find((u) => u.email?.toLowerCase() === wanted);
    if (hit) return hit.id;
    if (data.users.length < 200) return null;
  }
  return null;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405, { error: "POST only" });

  const secret = Deno.env.get("STRIPE_WEBHOOK_SECRET");
  const stripeKey = Deno.env.get("STRIPE_SECRET_KEY");
  if (!secret || !stripeKey) {
    log("not configured", { hasSecret: !!secret, hasKey: !!stripeKey });
    return json(503, { error: "STRIPE_WEBHOOK_SECRET / STRIPE_SECRET_KEY not set" });
  }

  const signature = req.headers.get("stripe-signature");
  if (!signature) return json(400, { error: "missing stripe-signature header" });

  const stripe = new Stripe(stripeKey, { apiVersion: "2025-08-27.basil" });
  const body = await req.text();

  let event: Stripe.Event;
  try {
    event = await stripe.webhooks.constructEventAsync(body, signature, secret);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    log("bad signature", { message });
    return json(400, { error: `signature verification failed: ${message}` });
  }

  if (!event.type.startsWith("customer.subscription.")) {
    return json(200, { received: true, ignored: event.type });
  }

  const subscription = event.data.object as Stripe.Subscription;
  const customerId = typeof subscription.customer === "string" ? subscription.customer : subscription.customer.id;
  const status = event.type === "customer.subscription.deleted" ? "canceled" : subscription.status;

  const admin = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    { auth: { persistSession: false } },
  );

  try {
    // Resolve the Stash user: a cache row already tagged with this customer,
    // else the customer's email against auth users.
    const { data: cached } = await admin.from(CACHE_TABLE).select("user_id").eq("stripe_customer_id", customerId).maybeSingle();
    let userId: string | null = cached?.user_id ?? null;
    if (!userId) {
      const customer = await stripe.customers.retrieve(customerId);
      const email = customer.deleted ? null : customer.email;
      if (email) userId = await findUserIdByEmail(admin, email);
    }
    if (!userId) {
      log("no matching user", { customerId, type: event.type });
      return json(200, { received: true, unmatched: customerId });
    }

    const { error } = await admin.from(CACHE_TABLE).upsert({
      user_id: userId,
      status,
      stripe_customer_id: customerId,
      checked_at: new Date().toISOString(),
    });
    if (error) throw new Error(`cache upsert: ${error.message}`);

    log("cached", { userId, status, type: event.type });
    return json(200, { received: true, userId, status });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    log("ERROR", { message, type: event.type });
    // 500 makes Stripe retry, which is what we want for transient DB errors.
    return json(500, { error: message });
  }
});
