// supabase/functions/apple-revocation-sweep/index.ts
//
// Cron pass (every 15 minutes, migration 20261012210000) for Sign in with Apple revocations that
// delete-account could not finish. `pending` rows in apple_revocations whose owner is confirmed
// ABSENT are retried with exponential backoff and settle to revoked / invalid (token nulled) or,
// after 20 attempts, exhausted (token KEPT for 90 days so an operator can re-queue it; purged as
// irrevocable afterwards). Rows whose owner is confirmed ALIVE (a deletion that failed after
// staging) are deferred, never revoked, and dropped after 30 days; rows whose owner is UNKNOWN
// (the probe failed) are deferred and never dropped. Logic and acceptance tests:
// _shared/appleRevocation.ts. Contract: docs/PLATFORM_API.md, "Account deletion".
//
// Auth: the cron's `x-cron-secret` (vault `cron_secret`, like enrichment-maintenance) or the
// service-role bearer. Logs counts only — never a token.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.57.2";
import { appleEnv } from "../_shared/appleClientSecret.ts";
import {
  EXHAUSTED_RETENTION_DAYS,
  MAX_ATTEMPTS,
  revokeAtApple,
  supabaseRevocationStore,
  sweepRevocations,
  type OwnerState,
  type RevokeFn,
  type StoredAppleToken,
} from "../_shared/appleRevocation.ts";

const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

const REQUEUE_SQL =
  "update public.apple_revocations set status = 'pending', attempts = 0, next_attempt_at = now(), last_error = null where status = 'exhausted' and user_id = '<user id>' and client_id = '<audience>'";

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

  // "Not found" is the only answer that proves absence; a present user is alive; anything else —
  // a transport error, a 5xx, an unexpected body — is unknown, and unknown rows are never revoked
  // and never dropped.
  const ownerState = async (userId: string): Promise<OwnerState> => {
    try {
      const { data, error } = await admin.auth.admin.getUserById(userId);
      if (error) return error.status === 404 || /not found/i.test(error.message) ? "absent" : "unknown";
      return data?.user ? "alive" : "unknown";
    } catch {
      return "unknown";
    }
  };

  try {
    const result = await sweepRevocations(supabaseRevocationStore(admin), revoke, { ownerState }, new Date());
    console.log(`[APPLE-REVOCATION-SWEEP] ${JSON.stringify(result)}`);
    if (result.exhaustedTotal > 0) {
      console.error(
        `[APPLE-REVOCATION-SWEEP] OPERATOR ACTION: ${result.exhaustedTotal} Apple revocation(s) exhausted ${MAX_ATTEMPTS} retries; each keeps its token for ${EXHAUSTED_RETENTION_DAYS} days. Fix the cause (last_error), then re-queue: ${REQUEUE_SQL}`,
      );
    }
    if (result.purgedExhausted > 0) {
      console.error(`[APPLE-REVOCATION-SWEEP] IRREVOCABLE: ${result.purgedExhausted} exhausted revocation(s) purged after ${EXHAUSTED_RETENTION_DAYS} days without recovery.`);
    }
    return json(200, result);
  } catch (e) {
    const message = e instanceof Error ? e.message : String(e);
    console.error(`[APPLE-REVOCATION-SWEEP] failed - ${message}`);
    return json(500, { error: message });
  }
});
