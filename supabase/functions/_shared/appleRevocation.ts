// supabase/functions/_shared/appleRevocation.ts
//
// Sign in with Apple revocation that survives account deletion (AS-APPLE-REVOCATION, 2026-10-12).
//
// Before: delete-account read apple_sign_in_tokens, asked Apple once, counted failures and deleted
// the auth user anyway; the token row cascaded away with the user, so a transient Apple failure
// (or a stalled read) lost the only material that could ever revoke the grant.
//
// Now: every stored token is first copied into apple_revocations — a service-role-only table with
// NO foreign key to auth.users — as `pending`. Only then is Apple asked, and the row settles:
//   revoked    Apple answered 2xx (it also answers 200 for a token it no longer knows)
//   invalid    Apple answered 400 invalid_grant: expired / already revoked / not ours — terminal
//   pending    anything else (invalid_client, 5xx, timeout, network, missing secrets): the
//              apple-revocation-sweep cron retries with exponential backoff, at most MAX_ATTEMPTS
//   exhausted  MAX_ATTEMPTS retries failed — terminal, counted in the sweep log
// The refresh token is nulled the moment a row leaves `pending` (a DB check enforces it) and
// non-pending rows are purged after PURGE_AFTER_DAYS. Nothing in this module logs a token.
//
// The logic takes a RevocationStore and a revoke function so vitest covers it with fakes
// (appleRevocation.test.ts); the Supabase-backed store and the real Apple call are at the bottom.

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

export interface RevocationStore {
  /** Tokens apple-token-exchange stored for this user. Throws when the table cannot be read. */
  listTokens(userId: string): Promise<StoredAppleToken[]>;
  /** Upsert this user's tokens as fresh `pending` rows. Throws when the copy fails. */
  enqueue(userId: string, tokens: StoredAppleToken[], now: Date): Promise<void>;
  /** Patch one queue row. */
  settle(userId: string, clientId: string, patch: SettlePatch): Promise<void>;
  /** Pending rows whose next_attempt_at has passed, oldest first. */
  duePending(now: Date, limit: number): Promise<RevocationRow[]>;
  /** Delete non-pending rows last touched before `before`; returns how many. */
  purge(before: Date): Promise<number>;
}

export const MAX_ATTEMPTS = 20;
export const PURGE_AFTER_DAYS = 30;
export const REVOKE_TIMEOUT_MS = 8_000;
export const SWEEP_BATCH = 25;
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

/** Apple's /auth/revoke answer → what happens to the row. Only invalid_grant is terminal. */
export function classifyRevokeResponse(status: number, body: { error?: unknown } | null | undefined): RevokeOutcome {
  if (status >= 200 && status < 300) return { kind: 'revoked' };
  const error = body && typeof body.error === 'string' ? body.error : null;
  if (status === 400 && error === 'invalid_grant') return { kind: 'invalid', reason: 'invalid_grant' };
  return { kind: 'retry', reason: error ? `apple ${status} ${error}` : `apple ${status}` };
}

export interface DeletionRevocationResult {
  /** Apple answered 2xx now. */
  revoked: number;
  /** Kept for existing clients: equals `pending`. */
  failed: number;
  /** Queued for the sweep (transient failure or missing secrets); the user is still deleted. */
  pending: number;
  /** Apple says the token is already gone or never ours — terminal, nothing to retry. */
  invalid: number;
}

/**
 * delete-account's Apple step. Copies every stored token into the queue BEFORE asking Apple, so a
 * failure anywhere after this point can be retried by the sweep even once the user is gone.
 * Throws — and never asks Apple — when the tokens cannot be read or copied; the caller must then
 * refuse the deletion with a retryable error.
 */
export async function stageAndRevokeForDeletion(store: RevocationStore, revoke: RevokeFn, userId: string, now: Date): Promise<DeletionRevocationResult> {
  const tokens = await store.listTokens(userId);
  const result: DeletionRevocationResult = { revoked: 0, failed: 0, pending: 0, invalid: 0 };
  if (tokens.length === 0) return result;
  await store.enqueue(userId, tokens, now);
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
      // The row is still `pending` with its token, so the sweep picks it up; a token Apple already
      // revoked costs one harmless extra call (Apple answers 200 again). Counts stay as above.
    }
  }
  result.failed = result.pending;
  return result;
}

export interface SweepResult {
  processed: number;
  revoked: number;
  invalid: number;
  retried: number;
  exhausted: number;
  purged: number;
}

/** The cron pass: retry due rows, settle them, purge old terminal rows. Never touches live accounts. */
export async function sweepRevocations(store: RevocationStore, revoke: RevokeFn, now: Date, limit = SWEEP_BATCH): Promise<SweepResult> {
  const result: SweepResult = { processed: 0, revoked: 0, invalid: 0, retried: 0, exhausted: 0, purged: 0 };
  const due = await store.duePending(now, limit);
  const nowIso = now.toISOString();
  for (const row of due) {
    result.processed += 1;
    if (!row.refresh_token) {
      // Cannot happen while pending (the DB check) — but never call Apple with nothing.
      await store.settle(row.user_id, row.client_id, { status: 'exhausted', refresh_token: null, last_error: 'no token', updated_at: nowIso });
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
        await store.settle(row.user_id, row.client_id, { status: 'exhausted', refresh_token: null, attempts, last_error: outcome.reason, updated_at: nowIso });
        result.exhausted += 1;
      } else {
        await store.settle(row.user_id, row.client_id, { attempts, last_error: outcome.reason, next_attempt_at: nextAttemptAt(attempts, now), updated_at: nowIso });
        result.retried += 1;
      }
    }
  }
  result.purged = await store.purge(new Date(now.getTime() - PURGE_AFTER_DAYS * 86_400_000));
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
    async purge(before) {
      const { count, error } = await admin.from('apple_revocations').delete({ count: 'exact' }).neq('status', 'pending').lt('updated_at', before.toISOString());
      if (error) throw new Error(`apple revocation purge: ${error.message}`);
      return count ?? 0;
    },
  };
}
