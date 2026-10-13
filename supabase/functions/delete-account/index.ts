// supabase/functions/delete-account/index.ts
//
// Deletes the calling user's account and everything it owns. Contract in
// docs/PLATFORM_API.md ("Account deletion").
//
// Order matters: every step before the auth delete is safe to retry, so a
// failure part-way leaves the account intact and the user simply tries again;
// once the auth user is gone the answer is `deleted: true`, whatever follows.
//
//   1. Sign in with Apple, staging — FIRST, before anything destructive: copy
//      every refresh token apple-token-exchange stored for this user into
//      apple_revocations (no FK to auth.users, so the row outlives the account).
//      Unreadable tokens or a failed copy refuse the deletion (503, retryable)
//      with nothing touched (2026-10-12).
//   2. Stripe — cancel any live subscription on the customer(s) with this
//      email. The customer record stays (invoice history); it is tagged with
//      `stash_account_deleted_at` so support can tell.
//   3. Storage — remove every object under `<user_id>/` in stash-media
//      (uploads, previews/, staging/, WhatsApp media). No constraint covers
//      storage, so this has to be explicit.
//   4. auth.admin.deleteUser — the DB cascades from migration 20260907120000
//      take items, embeddings, tags, conversations, phone, profile, grants,
//      feedback, logs, and the auth.* rows. A failure here answers 500 with the
//      account intact; the staged rows wait and are never swept while it exists.
//   5. Sign in with Apple, revocation — only now, with the account gone, so a
//      failed deletion never costs a live account its grant. Whatever Apple does
//      not confirm stays queued for apple-revocation-sweep, which acts only on
//      owners confirmed absent. Nothing in this step can turn the answer into
//      `deleted: false`: the account is gone, the rest is retry work.
//
// Only a person's own session may call this: agent (MCP) tokens are refused.

import { serve } from "https://deno.land/std@0.190.0/http/server.ts";
import Stripe from "https://esm.sh/stripe@18.5.0";
import { createClient, type SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.57.2";
import { isAgentToken } from "../_shared/agentToken.ts";
import { appleEnv } from "../_shared/appleClientSecret.ts";
import { allPending, revokeAtApple, revokeStaged, stageForDeletion, supabaseRevocationStore, type DeletionRevocationResult, type RevokeFn, type StoredAppleToken } from "../_shared/appleRevocation.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const BUCKET = "stash-media";
const LIST_PAGE = 1000;
const REMOVE_BATCH = 100;

const log = (step: string, details?: unknown) => {
  const suffix = details === undefined ? "" : ` - ${JSON.stringify(details)}`;
  console.log(`[DELETE-ACCOUNT] ${step}${suffix}`);
};

const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });

// Storage `list` is one folder deep and paginated; folders come back as
// entries without an id. Walk the whole subtree under `prefix`.
async function listAllObjectPaths(admin: SupabaseClient, prefix: string): Promise<string[]> {
  const paths: string[] = [];
  const folders = [prefix];
  while (folders.length > 0) {
    const folder = folders.pop() as string;
    let offset = 0;
    for (;;) {
      const { data, error } = await admin.storage.from(BUCKET).list(folder, { limit: LIST_PAGE, offset });
      if (error) throw new Error(`storage list ${folder}: ${error.message}`);
      if (!data || data.length === 0) break;
      for (const entry of data) {
        const path = `${folder}/${entry.name}`;
        if (entry.id) paths.push(path);
        else folders.push(path);
      }
      if (data.length < LIST_PAGE) break;
      offset += data.length;
    }
  }
  return paths;
}

async function removeObjects(admin: SupabaseClient, paths: string[]): Promise<void> {
  for (let i = 0; i < paths.length; i += REMOVE_BATCH) {
    const batch = paths.slice(i, i + REMOVE_BATCH);
    const { error } = await admin.storage.from(BUCKET).remove(batch);
    if (error) throw new Error(`storage remove: ${error.message}`);
  }
}

async function cancelStripeSubscriptions(email: string): Promise<{ customers: number; canceled: number }> {
  const stripeKey = Deno.env.get("STRIPE_SECRET_KEY");
  if (!stripeKey) {
    log("Stripe skipped: STRIPE_SECRET_KEY not set");
    return { customers: 0, canceled: 0 };
  }
  const stripe = new Stripe(stripeKey, { apiVersion: "2025-08-27.basil" });
  const customers = await stripe.customers.list({ email, limit: 10 });
  let canceled = 0;
  for (const customer of customers.data) {
    const subscriptions = await stripe.subscriptions.list({ customer: customer.id, status: "all", limit: 20 });
    for (const subscription of subscriptions.data) {
      if (subscription.status === "canceled" || subscription.status === "incomplete_expired") continue;
      await stripe.subscriptions.cancel(subscription.id);
      canceled += 1;
    }
    await stripe.customers.update(customer.id, {
      metadata: { stash_account_deleted_at: new Date().toISOString() },
    });
  }
  return { customers: customers.data.length, canceled };
}

// One revoke at Apple, now. Missing secrets are a `retry` (the row stays queued for the sweep),
// not a skip. Logic, classification and acceptance tests: _shared/appleRevocation.ts.
const revokeNow: RevokeFn = async (token: StoredAppleToken) => {
  let env: ReturnType<typeof appleEnv>;
  try {
    env = appleEnv();
  } catch (e) {
    return { kind: "retry", reason: `secrets missing: ${e instanceof Error ? e.message : String(e)}` };
  }
  return revokeAtApple({ fetch, env }, token);
};

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });
  if (req.method !== "POST") return json(405, { error: "POST only" });

  const admin = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    { auth: { persistSession: false } },
  );

  const token = req.headers.get("Authorization")?.replace(/^Bearer\s+/i, "").trim();
  if (!token) return json(401, { error: "Missing authorization token" });
  const { data: userData, error: userError } = await admin.auth.getUser(token);
  const user = userData?.user;
  if (userError || !user) return json(401, { error: "Invalid or expired token" });
  if (isAgentToken(token)) return json(403, { error: "Agent tokens cannot delete an account" });

  const userId = user.id;
  log("Started", { userId });

  // Stage the Apple revocation material before anything destructive: if it cannot be read or copied
  // into the queue, nothing has been cancelled, removed or deleted yet, and the call is simply retried.
  const store = supabaseRevocationStore(admin);
  const now = new Date();
  let staged: StoredAppleToken[];
  try {
    staged = await stageForDeletion(store, userId, now);
  } catch (e) {
    log("Apple tokens unavailable", { userId, message: e instanceof Error ? e.message : String(e) });
    return json(503, { deleted: false, error: "apple_tokens_unavailable", retryable: true });
  }
  log("Apple staged", { tokens: staged.length });

  let stripe = { customers: 0, canceled: 0 };
  let paths: string[] = [];
  try {
    stripe = user.email ? await cancelStripeSubscriptions(user.email) : stripe;
    log("Stripe done", stripe);

    paths = await listAllObjectPaths(admin, userId);
    await removeObjects(admin, paths);
    log("Storage done", { objects: paths.length });

    const { error: deleteError } = await admin.auth.admin.deleteUser(userId);
    if (deleteError) throw new Error(`auth delete: ${deleteError.message}`);
    log("Auth user deleted", { userId });
  } catch (error) {
    // The account still exists (every step above is safe to repeat); the staged rows wait and are
    // never swept while it does.
    const message = error instanceof Error ? error.message : String(error);
    log("ERROR", { userId, message });
    return json(500, { deleted: false, error: message });
  }

  // From here on the account is gone: whatever happens next, the answer is `deleted: true`. Ask
  // Apple now — a deletion that failed above never cost a live account its grant — and leave
  // anything Apple does not confirm, or anything that throws here, queued for the sweep.
  let apple: DeletionRevocationResult = allPending(staged);
  try {
    apple = await revokeStaged(store, revokeNow, userId, staged, now);
    log("Apple done", apple);
  } catch (error) {
    log("Apple revocation left to the sweep", { userId, message: error instanceof Error ? error.message : String(error) });
  }
  return json(200, { deleted: true, storageObjects: paths.length, stripe, apple });
});
