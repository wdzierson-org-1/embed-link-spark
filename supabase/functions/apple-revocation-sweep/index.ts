// supabase/functions/apple-revocation-sweep/index.ts
//
// Cron pass (every 15 minutes, migration 20261012210000) for Sign in with Apple revocations that
// delete-account could not finish: rows in apple_revocations that are still `pending` get retried
// with exponential backoff, settle to revoked / invalid / exhausted (token nulled), and terminal
// rows older than 30 days are purged. Logic and acceptance tests: _shared/appleRevocation.ts.
//
// Auth: the cron's `x-cron-secret` (vault `cron_secret`, like enrichment-maintenance) or the
// service-role bearer. Logs counts only — never a token or a user id.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.57.2";
import { appleEnv } from "../_shared/appleClientSecret.ts";
import { revokeAtApple, supabaseRevocationStore, sweepRevocations, type RevokeFn, type StoredAppleToken } from "../_shared/appleRevocation.ts";

const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405, { error: "POST only" });
  const secret = Deno.env.get("CRON_SECRET");
  const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const bySecret = !!secret && req.headers.get("x-cron-secret") === secret;
  const byService = !!service && req.headers.get("authorization") === `Bearer ${service}`;
  if (!bySecret && !byService) return json(401, { error: "unauthorized" });

  const admin = createClient(Deno.env.get("SUPABASE_URL") ?? "", service, { auth: { persistSession: false } });

  // Missing Apple secrets are a `retry`, not a crash: the rows stay queued until they are set.
  const revoke: RevokeFn = async (token: StoredAppleToken) => {
    let env: ReturnType<typeof appleEnv>;
    try {
      env = appleEnv();
    } catch (e) {
      return { kind: "retry", reason: `secrets missing: ${e instanceof Error ? e.message : String(e)}` };
    }
    return revokeAtApple({ fetch, env }, token);
  };

  try {
    const result = await sweepRevocations(supabaseRevocationStore(admin), revoke, new Date());
    console.log(`[APPLE-REVOCATION-SWEEP] ${JSON.stringify(result)}`);
    return json(200, result);
  } catch (e) {
    const message = e instanceof Error ? e.message : String(e);
    console.error(`[APPLE-REVOCATION-SWEEP] failed - ${message}`);
    return json(500, { error: message });
  }
});
