// supabase/functions/delete-account/index.ts
//
// Deletes the calling user's account and everything it owns. Contract in
// docs/PLATFORM_API.md ("Account deletion").
//
// Order matters: every step before the final auth delete is safe to retry, so
// a failure part-way leaves the account intact and the user simply tries again.
//
//   1. Stripe — cancel any live subscription on the customer(s) with this
//      email. The customer record stays (invoice history); it is tagged with
//      `stash_account_deleted_at` so support can tell.
//   2. Storage — remove every object under `<user_id>/` in stash-media
//      (uploads, previews/, staging/, WhatsApp media). No constraint covers
//      storage, so this has to be explicit.
//   3. auth.admin.deleteUser — the DB cascades from migration 20260907120000
//      take items, embeddings, tags, conversations, phone, profile, grants,
//      feedback, logs, and the auth.* rows.
//
// Only a person's own session may call this: agent (MCP) tokens are refused.

import { serve } from "https://deno.land/std@0.190.0/http/server.ts";
import Stripe from "https://esm.sh/stripe@18.5.0";
import { createClient, type SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.57.2";
import { isAgentToken } from "../_shared/agentToken.ts";

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

  try {
    const stripe = user.email
      ? await cancelStripeSubscriptions(user.email)
      : { customers: 0, canceled: 0 };
    log("Stripe done", stripe);

    const paths = await listAllObjectPaths(admin, userId);
    await removeObjects(admin, paths);
    log("Storage done", { objects: paths.length });

    const { error: deleteError } = await admin.auth.admin.deleteUser(userId);
    if (deleteError) throw new Error(`auth delete: ${deleteError.message}`);
    log("Auth user deleted", { userId });

    return json(200, { deleted: true, storageObjects: paths.length, stripe });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    log("ERROR", { userId, message });
    return json(500, { deleted: false, error: message });
  }
});
