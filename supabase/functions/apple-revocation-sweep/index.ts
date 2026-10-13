// supabase/functions/apple-revocation-sweep/index.ts
//
// Cron pass (every 15 minutes, migration 20261012210000) for Sign in with Apple revocations that
// delete-account could not finish: `pending` rows in apple_revocations whose owner is confirmed
// gone are retried with exponential backoff and settle to revoked / invalid / exhausted (token
// nulled); rows whose owner still exists (a deletion that failed after staging) are deferred, never
// revoked, and dropped after 30 days; revoked/invalid rows older than 30 days are purged.
// `exhausted` rows are retained and reported at error level every run until an operator resolves
// them (see docs/PLATFORM_API.md, "Account deletion"). Logic and acceptance tests:
// _shared/appleRevocation.ts.
//
// Auth: the cron's `x-cron-secret` (vault `cron_secret`, like enrichment-maintenance) or the
// service-role bearer. Logs counts only — never a token.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.57.2";
import { appleEnv } from "../_shared/appleClientSecret.ts";
import { MAX_ATTEMPTS, revokeAtApple, supabaseRevocationStore, sweepRevocations, type RevokeFn, type StoredAppleToken } from "../_shared/appleRevocation.ts";

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

  // Only a confirmed-absent auth user gets its grant revoked here. "Not found" is the only answer
  // that proves absence; any other error throws, and the sweep treats a throw as "alive".
  const userExists = async (userId: string): Promise<boolean> => {
    const { data, error } = await admin.auth.admin.getUserById(userId);
    if (error) {
      if (error.status === 404 || /not found/i.test(error.message)) return false;
      throw new Error(error.message);
    }
    return !!data?.user;
  };

  try {
    const result = await sweepRevocations(supabaseRevocationStore(admin), revoke, { userExists }, new Date());
    console.log(`[APPLE-REVOCATION-SWEEP] ${JSON.stringify(result)}`);
    if (result.exhaustedTotal > 0) {
      console.error(`[APPLE-REVOCATION-SWEEP] OPERATOR ACTION: ${result.exhaustedTotal} Apple revocation(s) exhausted ${MAX_ATTEMPTS} retries and are retained in apple_revocations (status = 'exhausted'); revoke manually or decide to drop them.`);
    }
    return json(200, result);
  } catch (e) {
    const message = e instanceof Error ? e.message : String(e);
    console.error(`[APPLE-REVOCATION-SWEEP] failed - ${message}`);
    return json(500, { error: message });
  }
});
