// supabase/functions/_shared/appleRevocation.ts
//
// Sign in with Apple revocation that survives account deletion (AS-APPLE-REVOCATION, 2026-10-12).
//
// Before: delete-account read apple_sign_in_tokens, asked Apple once, counted failures and deleted
// the auth user anyway; the token row cascaded away with the user, so a transient Apple failure
// (or a stalled read) lost the only material that could ever revoke the grant.
//
// Now, in delete-account's order:
//   1. stageForDeletion  — FIRST, before anything destructive: copy every stored token into
//                          apple_revocations (a service-role-only table with NO foreign key to
//                          auth.users) as `pending`. Unreadable or uncopyable tokens throw and the
//                          caller refuses the deletion (503) with nothing touched.
//   2. (the caller cancels Stripe, wipes storage and deletes the auth user)
//   3. revokeStaged      — only now ask Apple, so a deletion that failed never costs a live
//                          account its grant. Each row settles:
//        revoked    Apple answered 2xx (it also answers 200 for a token it no longer knows)
//        invalid    Apple answered 400 invalid_grant — "the token is invalid or expired": terminal
//        pending    anything else (invalid_client, 5xx, timeout, network, missing secrets)
// The sweep (sweepRevocations, cron every 15 min) retries `pending` rows ONLY for owners that are
// confirmed ABSENT. An owner that is confirmed ALIVE (delete-account staged the row and then failed
// before the auth deletion) is deferred — never revoked — and its row dropped after
// PURGE_AFTER_DAYS because the token still sits in apple_sign_in_tokens. An owner whose state is
// UNKNOWN (the probe failed) is only ever deferred: unknown proves nothing about the source token,
// so such a row is never dropped. Retries back off from 15 minutes to 24 hours; after MAX_ATTEMPTS
// a row becomes `exhausted`: an operational failure that KEEPS its token for
// EXHAUSTED_RETENTION_DAYS so an operator can re-queue it after fixing the cause (set status
// 'pending', attempts 0, next_attempt_at now()); the sweep reports it at error level every run,
// and purges it — logged as irrevocable — once that window passes. `revoked` and `invalid` rows
// never carry a token (DB check) and are purged after PURGE_AFTER_DAYS. Nothing here logs a token.
//
// The logic takes a RevocationStore, a revoke function and an owner-state probe so vitest covers
// it with fakes (appleRevocation.test.ts); the Supabase-backed store and the real Apple call are at
// the bottom.

import { makeAppleClientSecret } from './appleClientSecret.ts';

export type RevocationStatus = 'pending' | 'revoked' | 'invalid' | 'exhausted';

export interface StoredAppleToken {
  client_id: string;
  refresh_token: string;
}

export interface RevocationRow {
  user_id: string;
  client_id: string;
  refresh_token: string | null;
  status: RevocationStatus;
  attempts: number;
  last_error: string | null;
  next_attempt_at: string;
  updated_at: string;
  revoked_at?: string | null;
}

export type RevokeOutcome =
  | { kind: 'revoked' }
  | { kind: 'invalid'; reason: string }
  | { kind: 'retry'; reason: string };

export type RevokeFn = (token: StoredAppleToken) => Promise<RevokeOutcome>;

export type SettlePatch = Partial<Pick<RevocationRow, 'refresh_token' | 'status' | 'attempts' | 'last_error' | 'next_attempt_at' | 'revoked_at'>> & {
  updated_at: string;
};

export interface PurgeResult {
  /** `revoked` / `invalid` rows removed. */
  settled: number;
  /** `exhausted` rows removed after their retention window — irrevocable. */
  exhausted: number;
}

export interface RevocationStore {
  /** Tokens apple-token-exchange stored for this user. Throws when the table cannot be read. */
  listTokens(userId: string): Promise<StoredAppleToken[]>;
  /** Upsert this user's tokens as fresh `pending` rows. Throws when the copy fails. */
  enqueue(userId: string, tokens: StoredAppleToken[], now: Date): Promise<void>;
  /** Patch one queue row. */
  settle(userId: string, clientId: string, patch: SettlePatch): Promise<void>;
  /** Delete one queue row (a deferred row whose owner is confirmed alive after PURGE_AFTER_DAYS). */
  remove(userId: string, clientId: string): Promise<void>;
  /** Pending rows whose next_attempt_at has passed, oldest first. */
  duePending(now: Date, limit: number): Promise<RevocationRow[]>;
  /** Delete `revoked` / `invalid` rows last touched before `settledBefore` and `exhausted` rows last touched before `exhaustedBefore`. */
  purge(settledBefore: Date, exhaustedBefore: Date): Promise<PurgeResult>;
  /** How many rows are `exhausted` right now (operator attention). */
  exhaustedCount(): Promise<number>;
}

export const MAX_ATTEMPTS = 20;
export const PURGE_AFTER_DAYS = 30;
/** An exhausted row keeps its token this long for an operator to re-queue it; then it is purged as irrevocable. */
export const EXHAUSTED_RETENTION_DAYS = 90;
export const REVOKE_TIMEOUT_MS = 8_000;
export const SWEEP_BATCH = 25;
/** A row whose owner is alive or unknown is looked at again after this long, not every run. */
export const DEFER_MS = 60 * 60_000;
const FIRST_BACKOFF_MS = 15 * 60_000;
const MAX_BACKOFF_MS = 24 * 60 * 60_000;

/** Wait before the next try after `attempts` tries (≥ 1): 15 min, doubling, capped at 24 h. */
export function backoffMs(attempts: number): number {
  const n = Math.max(1, Math.floor(attempts));
  return Math.min(FIRST_BACKOFF_MS * 2 ** (n - 1), MAX_BACKOFF_MS);
}

export function nextAttemptAt(attempts: number, now: Date): string {
  return new Date(now.getTime() + backoffMs(attempts)).toISOString();
}

/**
 * Apple's /auth/revoke answer → what happens to the row. Only `invalid_grant` is terminal: Apple's
 * ErrorResponse defines it as "the authorization grant or refresh token is invalid … invalid refresh
 * token", i.e. there is no grant left to revoke. Every other refusal (invalid_client = our client
 * secret, invalid_request = our form, 5xx, 429…) is retried, bounded by MAX_ATTEMPTS.
 */
export function classifyRevokeResponse(status: number, body: { error?: unknown } | null | undefined): RevokeOutcome {
  if (status >= 200 && status < 300) return { kind: 'revoked' };
  const error = body && typeof body.error === 'string' ? body.error : null;
  if (status === 400 && error === 'invalid_grant') return { kind: 'invalid', reason: 'invalid_grant' };
  return { kind: 'retry', reason: error ? `apple ${status} ${error}` : `apple ${status}` };
}

/**
 * Step 1 of delete-account, run BEFORE anything destructive: copy every stored token into the queue
 * so a failure anywhere later can be retried by the sweep even once the user is gone. Throws — and
 * nothing has been asked of Apple — when the tokens cannot be read or copied; the caller must then
 * refuse the deletion with a retryable error. Returns the staged tokens for revokeStaged.
 */
export async function stageForDeletion(store: RevocationStore, userId: string, now: Date): Promise<StoredAppleToken[]> {
  const tokens = await store.listTokens(userId);
  if (tokens.length > 0) await store.enqueue(userId, tokens, now);
  return tokens;
}

export interface DeletionRevocationResult {
  /** Apple answered 2xx now. */
  revoked: number;
  /** Kept for existing clients: equals `pending`. */
  failed: number;
  /** Queued for the sweep (transient failure or missing secrets); the account is already gone. */
  pending: number;
  /** Apple says the token is already gone or never ours — terminal, nothing to retry. */
  invalid: number;
}

/** What delete-account reports when it could not even ask Apple after the deletion: everything stays queued. */
export function allPending(tokens: StoredAppleToken[]): DeletionRevocationResult {
  return { revoked: 0, failed: tokens.length, pending: tokens.length, invalid: 0 };
}

/**
 * Last step of delete-account, run only AFTER the auth user is deleted: ask Apple for each staged
 * token and settle its queue row. A settle failure leaves the row `pending` with its token, which
 * the sweep finishes (Apple answers 200 again for a token it already revoked).
 */
export async function revokeStaged(store: RevocationStore, revoke: RevokeFn, userId: string, tokens: StoredAppleToken[], now: Date): Promise<DeletionRevocationResult> {
  const result: DeletionRevocationResult = { revoked: 0, failed: 0, pending: 0, invalid: 0 };
  const nowIso = now.toISOString();
  for (const token of tokens) {
    const outcome = await revoke(token);
    if (outcome.kind === 'revoked') result.revoked += 1;
    else if (outcome.kind === 'invalid') result.invalid += 1;
    else result.pending += 1;
    try {
      if (outcome.kind === 'revoked') {
        await store.settle(userId, token.client_id, { status: 'revoked', refresh_token: null, last_error: null, updated_at: nowIso, revoked_at: nowIso });
      } else if (outcome.kind === 'invalid') {
        await store.settle(userId, token.client_id, { status: 'invalid', refresh_token: null, last_error: outcome.reason, updated_at: nowIso });
      } else {
        await store.settle(userId, token.client_id, { attempts: 1, last_error: outcome.reason, next_attempt_at: nextAttemptAt(1, now), updated_at: nowIso });
      }
    } catch {
      // Row stays `pending` with its token: the sweep picks it up. Counts above stand.
    }
  }
  result.failed = result.pending;
  return result;
}

/** What the auth admin API says about a queue row's owner. Only `absent` licenses a revoke. */
export type OwnerState = 'absent' | 'alive' | 'unknown';

export interface SweepDeps {
  /** `absent` = not found; `alive` = the user row exists; `unknown` = the probe failed. Throwing counts as `unknown`. */
  ownerState(userId: string): Promise<OwnerState>;
}

export interface SweepResult {
  /** Rows whose owner is confirmed gone and that were retried this run. */
  processed: number;
  revoked: number;
  invalid: number;
  retried: number;
  /** Rows that reached MAX_ATTEMPTS this run (retained with their token for an operator). */
  exhausted: number;
  /** Rows whose owner is confirmed alive (deletion failed after staging): deferred, never revoked. */
  deferred: number;
  /** Rows whose owner could not be determined: deferred, never revoked, never dropped. */
  unknown: number;
  /** Confirmed-alive rows older than PURGE_AFTER_DAYS that were dropped (token still in apple_sign_in_tokens). */
  dropped: number;
  /** `revoked` / `invalid` rows older than PURGE_AFTER_DAYS removed. */
  purged: number;
  /** `exhausted` rows older than EXHAUSTED_RETENTION_DAYS removed — irrevocable. */
  purgedExhausted: number;
  /** All `exhausted` rows in the table after this run — operator attention while > 0. */
  exhaustedTotal: number;
}

/** The cron pass. Revokes only for owners that are confirmed gone. */
export async function sweepRevocations(store: RevocationStore, revoke: RevokeFn, deps: SweepDeps, now: Date, limit = SWEEP_BATCH): Promise<SweepResult> {
  const result: SweepResult = { processed: 0, revoked: 0, invalid: 0, retried: 0, exhausted: 0, deferred: 0, unknown: 0, dropped: 0, purged: 0, purgedExhausted: 0, exhaustedTotal: 0 };
  const due = await store.duePending(now, limit);
  const nowIso = now.toISOString();
  const dropCutoff = new Date(now.getTime() - PURGE_AFTER_DAYS * 86_400_000);
  const exhaustedCutoff = new Date(now.getTime() - EXHAUSTED_RETENTION_DAYS * 86_400_000);
  const deferTo = new Date(now.getTime() + DEFER_MS).toISOString();
  for (const row of due) {
    let owner: OwnerState = 'unknown';
    try {
      owner = await deps.ownerState(row.user_id);
    } catch {
      owner = 'unknown';
    }
    if (owner === 'alive') {
      // delete-account staged this row and then failed before the auth deletion: the source token is
      // still in apple_sign_in_tokens, so after PURGE_AFTER_DAYS the copy is not needed.
      if (new Date(row.updated_at).getTime() < dropCutoff.getTime()) {
        await store.remove(row.user_id, row.client_id);
        result.dropped += 1;
      } else {
        await store.settle(row.user_id, row.client_id, { last_error: 'account still exists', next_attempt_at: deferTo, updated_at: row.updated_at });
        result.deferred += 1;
      }
      continue;
    }
    if (owner === 'unknown') {
      // Unknown proves nothing about the source token: never revoke, never drop — look again later.
      await store.settle(row.user_id, row.client_id, { last_error: 'owner state unknown', next_attempt_at: deferTo, updated_at: row.updated_at });
      result.unknown += 1;
      continue;
    }
    result.processed += 1;
    if (!row.refresh_token) {
      // Cannot happen while pending (the DB check) — but never call Apple with nothing; nothing can recover this row.
      await store.settle(row.user_id, row.client_id, { status: 'exhausted', last_error: 'no token (irrevocable)', updated_at: nowIso });
      result.exhausted += 1;
      continue;
    }
    const outcome = await revoke({ client_id: row.client_id, refresh_token: row.refresh_token });
    if (outcome.kind === 'revoked') {
      await store.settle(row.user_id, row.client_id, { status: 'revoked', refresh_token: null, last_error: null, updated_at: nowIso, revoked_at: nowIso });
      result.revoked += 1;
    } else if (outcome.kind === 'invalid') {
      await store.settle(row.user_id, row.client_id, { status: 'invalid', refresh_token: null, last_error: outcome.reason, updated_at: nowIso });
      result.invalid += 1;
    } else {
      const attempts = row.attempts + 1;
      if (attempts >= MAX_ATTEMPTS) {
        // The token stays on the row: an operator can re-queue it after fixing the cause.
        await store.settle(row.user_id, row.client_id, { status: 'exhausted', attempts, last_error: outcome.reason, updated_at: nowIso });
        result.exhausted += 1;
      } else {
        await store.settle(row.user_id, row.client_id, { attempts, last_error: outcome.reason, next_attempt_at: nextAttemptAt(attempts, now), updated_at: nowIso });
        result.retried += 1;
      }
    }
  }
  const purged = await store.purge(dropCutoff, exhaustedCutoff);
  result.purged = purged.settled;
  result.purgedExhausted = purged.exhausted;
  result.exhaustedTotal = await store.exhaustedCount();
  return result;
}

export interface AppleReadiness {
  /** The auth user has a Sign in with Apple identity. */
  apple_identity: boolean;
  /** At least one Apple refresh token is on file for revocation. */
  stored: boolean;
  clients: Array<{ client: 'ios' | 'web'; obtained_at: string }>;
}

/** What `GET apple-token-exchange` answers: whether deletion will have anything to revoke. */
export function appleReadiness(
  rows: Array<{ client_id: string; created_at: string }>,
  identities: Array<{ provider?: string }> | null | undefined,
  bundleId: string | null,
): AppleReadiness {
  return {
    apple_identity: (identities ?? []).some((identity) => identity.provider === 'apple'),
    stored: rows.length > 0,
    clients: rows.map((row) => ({ client: bundleId && row.client_id === bundleId ? 'ios' : 'web', obtained_at: row.created_at })),
  };
}

// ---------------------------------------------------------------------------------------------
// Real collaborators (used by the edge functions; not exercised by the unit tests)

export const APPLE_REVOKE_URL = 'https://appleid.apple.com/auth/revoke';

export interface AppleRevokeEnv {
  teamId: string;
  keyId: string;
  privateKeyPem: string;
}

/** One revoke call at Apple. Never throws: anything unexpected becomes a `retry` outcome. */
export async function revokeAtApple(deps: { fetch: typeof fetch; env: AppleRevokeEnv; now?: Date }, token: StoredAppleToken): Promise<RevokeOutcome> {
  try {
    const clientSecret = await makeAppleClientSecret({
      teamId: deps.env.teamId,
      keyId: deps.env.keyId,
      clientId: token.client_id,
      privateKeyPem: deps.env.privateKeyPem,
      now: deps.now ?? new Date(),
    });
    const res = await deps.fetch(APPLE_REVOKE_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({ client_id: token.client_id, client_secret: clientSecret, token: token.refresh_token, token_type_hint: 'refresh_token' }).toString(),
      // A stalled Apple must never hold up deletion: the abort lands in the catch and the row stays pending.
      signal: AbortSignal.timeout(REVOKE_TIMEOUT_MS),
    });
    const body = res.ok ? null : await res.json().catch(() => null);
    return classifyRevokeResponse(res.status, body as { error?: unknown } | null);
  } catch (e) {
    const name = e instanceof Error ? e.name : '';
    const message = e instanceof Error ? e.message : String(e);
    return { kind: 'retry', reason: name === 'TimeoutError' || name === 'AbortError' ? 'timeout' : message };
  }
}

// Minimal shape of the supabase-js client this module needs; typed loosely so the module stays
// runtime-agnostic (Deno in the functions, Node under vitest).
// deno-lint-ignore no-explicit-any
// eslint-disable-next-line @typescript-eslint/no-explicit-any
type AdminClient = { from: (table: string) => any };

export function supabaseRevocationStore(admin: AdminClient): RevocationStore {
  return {
    async listTokens(userId) {
      const { data, error } = await admin.from('apple_sign_in_tokens').select('client_id, refresh_token').eq('user_id', userId);
      if (error) throw new Error(`apple tokens unreadable: ${error.message}`);
      return (data ?? []) as StoredAppleToken[];
    },
    async enqueue(userId, tokens, now) {
      const nowIso = now.toISOString();
      const rows = tokens.map((token) => ({
        user_id: userId,
        client_id: token.client_id,
        refresh_token: token.refresh_token,
        status: 'pending',
        attempts: 0,
        last_error: null,
        next_attempt_at: nowIso,
        updated_at: nowIso,
        revoked_at: null,
      }));
      const { error } = await admin.from('apple_revocations').upsert(rows, { onConflict: 'user_id,client_id' });
      if (error) throw new Error(`apple revocation queue: ${error.message}`);
    },
    async settle(userId, clientId, patch) {
      const { error } = await admin.from('apple_revocations').update(patch).eq('user_id', userId).eq('client_id', clientId);
      if (error) throw new Error(`apple revocation update: ${error.message}`);
    },
    async remove(userId, clientId) {
      const { error } = await admin.from('apple_revocations').delete().eq('user_id', userId).eq('client_id', clientId);
      if (error) throw new Error(`apple revocation remove: ${error.message}`);
    },
    async duePending(now, limit) {
      const { data, error } = await admin
        .from('apple_revocations')
        .select('user_id, client_id, refresh_token, status, attempts, last_error, next_attempt_at, updated_at')
        .eq('status', 'pending')
        .lte('next_attempt_at', now.toISOString())
        .order('next_attempt_at', { ascending: true })
        .limit(limit);
      if (error) throw new Error(`apple revocation queue unreadable: ${error.message}`);
      return (data ?? []) as RevocationRow[];
    },
    async purge(settledBefore, exhaustedBefore) {
      const settled = await admin.from('apple_revocations').delete({ count: 'exact' }).in('status', ['revoked', 'invalid']).lt('updated_at', settledBefore.toISOString());
      if (settled.error) throw new Error(`apple revocation purge: ${settled.error.message}`);
      const exhausted = await admin.from('apple_revocations').delete({ count: 'exact' }).eq('status', 'exhausted').lt('updated_at', exhaustedBefore.toISOString());
      if (exhausted.error) throw new Error(`apple revocation purge (exhausted): ${exhausted.error.message}`);
      return { settled: settled.count ?? 0, exhausted: exhausted.count ?? 0 };
    },
    async exhaustedCount() {
      const { count, error } = await admin.from('apple_revocations').select('user_id', { count: 'exact', head: true }).eq('status', 'exhausted');
      if (error) throw new Error(`apple revocation count: ${error.message}`);
      return count ?? 0;
    },
  };
}
