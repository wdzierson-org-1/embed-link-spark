// supabase/functions/_shared/appleRevocation.test.ts
// @vitest-environment node
//
// AS-APPLE-REVOCATION acceptance (docs/agent-coordination.md, 2026-10-12): unreadable tokens stop
// the deletion; a transient Apple failure queues the token and the account still goes; the sweep
// retries with backoff and settles to revoked / invalid / exhausted with the token nulled; no
// token is lost before recovery; one owner's deletion never touches another owner's rows.
import { describe, expect, it } from 'vitest';
import {
  MAX_ATTEMPTS,
  PURGE_AFTER_DAYS,
  appleReadiness,
  backoffMs,
  classifyRevokeResponse,
  nextAttemptAt,
  revokeAtApple,
  stageAndRevokeForDeletion,
  sweepRevocations,
  type RevocationRow,
  type RevocationStore,
  type RevokeOutcome,
  type SettlePatch,
  type StoredAppleToken,
} from './appleRevocation';

const NOW = new Date('2026-10-12T20:00:00.000Z');
const MIN = 60_000;
const iso = (d: Date) => d.toISOString();

class FakeStore implements RevocationStore {
  tokens = new Map<string, StoredAppleToken[]>(); // apple_sign_in_tokens, per user
  rows = new Map<string, RevocationRow>(); // apple_revocations, keyed user:client
  log: string[] = [];
  failListTokens = false;
  failEnqueue = false;
  failSettle = false;

  seedRow(row: RevocationRow) {
    this.rows.set(`${row.user_id}:${row.client_id}`, row);
  }
  row(userId: string, clientId: string) {
    return this.rows.get(`${userId}:${clientId}`);
  }
  async listTokens(userId: string) {
    this.log.push(`list:${userId}`);
    if (this.failListTokens) throw new Error('read failed');
    return this.tokens.get(userId) ?? [];
  }
  async enqueue(userId: string, tokens: StoredAppleToken[], now: Date) {
    this.log.push(`enqueue:${userId}:${tokens.length}`);
    if (this.failEnqueue) throw new Error('copy failed');
    for (const t of tokens) {
      this.seedRow({ user_id: userId, client_id: t.client_id, refresh_token: t.refresh_token, status: 'pending', attempts: 0, last_error: null, next_attempt_at: iso(now), updated_at: iso(now), revoked_at: null });
    }
  }
  async settle(userId: string, clientId: string, patch: SettlePatch) {
    this.log.push(`settle:${userId}:${clientId}:${patch.status ?? 'pending'}`);
    if (this.failSettle) throw new Error('update failed');
    const current = this.row(userId, clientId);
    if (!current) throw new Error('missing row');
    this.seedRow({ ...current, ...patch });
  }
  async duePending(now: Date, limit: number) {
    return [...this.rows.values()]
      .filter((r) => r.status === 'pending' && r.next_attempt_at <= iso(now))
      .sort((a, b) => a.next_attempt_at.localeCompare(b.next_attempt_at))
      .slice(0, limit);
  }
  async purge(before: Date) {
    let n = 0;
    for (const [key, r] of this.rows) {
      if (r.status !== 'pending' && r.updated_at < iso(before)) {
        this.rows.delete(key);
        n += 1;
      }
    }
    return n;
  }
}

/** A revoke function scripted per token value; records what it was asked, in order. */
function scriptedRevoke(store: FakeStore, outcomes: Record<string, RevokeOutcome>) {
  return async (token: StoredAppleToken): Promise<RevokeOutcome> => {
    store.log.push(`apple:${token.refresh_token}`);
    return outcomes[token.refresh_token] ?? { kind: 'retry', reason: 'unscripted' };
  };
}

describe('classifyRevokeResponse — only invalid_grant is terminal', () => {
  it.each([
    [200, null, { kind: 'revoked' }],
    [204, null, { kind: 'revoked' }],
    [400, { error: 'invalid_grant' }, { kind: 'invalid', reason: 'invalid_grant' }],
    [400, { error: 'invalid_client' }, { kind: 'retry', reason: 'apple 400 invalid_client' }],
    [400, { error: 'invalid_request' }, { kind: 'retry', reason: 'apple 400 invalid_request' }],
    [429, null, { kind: 'retry', reason: 'apple 429' }],
    [503, {}, { kind: 'retry', reason: 'apple 503' }],
  ])('%s %j → %j', (status, body, expected) => {
    expect(classifyRevokeResponse(status as number, body as { error?: unknown } | null)).toEqual(expected);
  });
});

describe('backoff — bounded, doubling from 15 minutes, capped at 24 hours', () => {
  it('doubles then caps', () => {
    expect(backoffMs(1)).toBe(15 * MIN);
    expect(backoffMs(2)).toBe(30 * MIN);
    expect(backoffMs(3)).toBe(60 * MIN);
    expect(backoffMs(7)).toBe(16 * 60 * MIN);
    expect(backoffMs(8)).toBe(24 * 60 * MIN);
    expect(backoffMs(20)).toBe(24 * 60 * MIN);
    expect(backoffMs(0)).toBe(15 * MIN);
  });
  it('stamps the next attempt from now', () => {
    expect(nextAttemptAt(1, NOW)).toBe('2026-10-12T20:15:00.000Z');
    expect(nextAttemptAt(4, NOW)).toBe('2026-10-12T22:00:00.000Z');
  });
  it('gives up after a bounded number of tries', () => {
    expect(MAX_ATTEMPTS).toBe(20);
    expect(PURGE_AFTER_DAYS).toBe(30);
  });
});

describe('stageAndRevokeForDeletion — the Apple step of delete-account', () => {
  const userA = '11111111-1111-4111-8111-111111111111';
  const userB = '22222222-2222-4222-8222-222222222222';

  it('refuses when the tokens cannot be read: throws, nothing queued, Apple never asked', async () => {
    const store = new FakeStore();
    store.failListTokens = true;
    const revoke = scriptedRevoke(store, {});
    await expect(stageAndRevokeForDeletion(store, revoke, userA, NOW)).rejects.toThrow('read failed');
    expect(store.log).toEqual([`list:${userA}`]);
  });

  it('refuses when the copy into the queue fails: throws before any Apple call', async () => {
    const store = new FakeStore();
    store.tokens.set(userA, [{ client_id: 'it.gostash.stash', refresh_token: 'tok-ios' }]);
    store.failEnqueue = true;
    const revoke = scriptedRevoke(store, { 'tok-ios': { kind: 'revoked' } });
    await expect(stageAndRevokeForDeletion(store, revoke, userA, NOW)).rejects.toThrow('copy failed');
    expect(store.log).toEqual([`list:${userA}`, `enqueue:${userA}:1`]);
  });

  it('reports zeros and queues nothing for a person without Apple tokens', async () => {
    const store = new FakeStore();
    const revoke = scriptedRevoke(store, {});
    await expect(stageAndRevokeForDeletion(store, revoke, userA, NOW)).resolves.toEqual({ revoked: 0, failed: 0, pending: 0, invalid: 0 });
    expect(store.log).toEqual([`list:${userA}`]);
    expect(store.rows.size).toBe(0);
  });

  it('queues every token BEFORE asking Apple, then settles each by outcome', async () => {
    const store = new FakeStore();
    store.tokens.set(userA, [
      { client_id: 'it.gostash.stash', refresh_token: 'tok-ok' },
      { client_id: 'it.gostash.web', refresh_token: 'tok-flaky' },
      { client_id: 'it.gostash.legacy', refresh_token: 'tok-dead' },
    ]);
    const revoke = scriptedRevoke(store, {
      'tok-ok': { kind: 'revoked' },
      'tok-flaky': { kind: 'retry', reason: 'apple 503' },
      'tok-dead': { kind: 'invalid', reason: 'invalid_grant' },
    });
    const result = await stageAndRevokeForDeletion(store, revoke, userA, NOW);
    expect(result).toEqual({ revoked: 1, failed: 1, pending: 1, invalid: 1 });

    // Order: read → copy all three → only then Apple
    expect(store.log.slice(0, 2)).toEqual([`list:${userA}`, `enqueue:${userA}:3`]);
    expect(store.log.indexOf('apple:tok-ok')).toBeGreaterThan(store.log.indexOf(`enqueue:${userA}:3`));

    const ok = store.row(userA, 'it.gostash.stash')!;
    expect(ok).toMatchObject({ status: 'revoked', refresh_token: null, last_error: null, revoked_at: iso(NOW) });

    const flaky = store.row(userA, 'it.gostash.web')!;
    expect(flaky).toMatchObject({ status: 'pending', refresh_token: 'tok-flaky', attempts: 1, last_error: 'apple 503', next_attempt_at: '2026-10-12T20:15:00.000Z' });

    const dead = store.row(userA, 'it.gostash.legacy')!;
    expect(dead).toMatchObject({ status: 'invalid', refresh_token: null, last_error: 'invalid_grant' });
  });

  it('keeps the token in the queue when the settle itself fails (the sweep finishes it)', async () => {
    const store = new FakeStore();
    store.tokens.set(userA, [{ client_id: 'it.gostash.stash', refresh_token: 'tok-ok' }]);
    const revoke = scriptedRevoke(store, { 'tok-ok': { kind: 'revoked' } });
    store.failSettle = true;
    await expect(stageAndRevokeForDeletion(store, revoke, userA, NOW)).resolves.toEqual({ revoked: 1, failed: 0, pending: 0, invalid: 0 });
    expect(store.row(userA, 'it.gostash.stash')).toMatchObject({ status: 'pending', refresh_token: 'tok-ok' });
  });

  it('only ever touches the caller’s own rows', async () => {
    const store = new FakeStore();
    store.tokens.set(userA, [{ client_id: 'it.gostash.stash', refresh_token: 'tok-a' }]);
    store.tokens.set(userB, [{ client_id: 'it.gostash.stash', refresh_token: 'tok-b' }]);
    store.seedRow({ user_id: userB, client_id: 'it.gostash.web', refresh_token: 'tok-b-old', status: 'pending', attempts: 2, last_error: 'apple 500', next_attempt_at: iso(NOW), updated_at: iso(NOW), revoked_at: null });
    const revoke = scriptedRevoke(store, { 'tok-a': { kind: 'retry', reason: 'timeout' } });
    await stageAndRevokeForDeletion(store, revoke, userA, NOW);
    expect(store.log.filter((l) => l.includes(userB))).toEqual([]);
    expect(store.log.filter((l) => l.startsWith('apple:'))).toEqual(['apple:tok-a']);
    expect(store.row(userB, 'it.gostash.stash')).toBeUndefined();
    expect(store.row(userB, 'it.gostash.web')).toMatchObject({ status: 'pending', refresh_token: 'tok-b-old', attempts: 2 });
  });
});

describe('sweepRevocations — the cron pass', () => {
  const gone = '33333333-3333-4333-8333-333333333333'; // a deleted account: no auth.users row exists
  const other = '44444444-4444-4444-8444-444444444444';
  const pendingRow = (userId: string, clientId: string, token: string, attempts: number, nextAt: Date): RevocationRow => ({
    user_id: userId, client_id: clientId, refresh_token: token, status: 'pending', attempts, last_error: 'apple 503', next_attempt_at: iso(nextAt), updated_at: iso(nextAt), revoked_at: null,
  });

  it('retries due rows and settles them: revoked, invalid, backoff, exhausted; leaves the rest alone', async () => {
    const store = new FakeStore();
    const due = new Date(NOW.getTime() - MIN);
    const later = new Date(NOW.getTime() + 60 * MIN);
    store.seedRow(pendingRow(gone, 'c-revoked', 'tok-1', 3, due));
    store.seedRow(pendingRow(gone, 'c-invalid', 'tok-2', 1, due));
    store.seedRow(pendingRow(gone, 'c-retry', 'tok-3', 3, due));
    store.seedRow(pendingRow(gone, 'c-last', 'tok-4', MAX_ATTEMPTS - 1, due));
    store.seedRow(pendingRow(other, 'c-not-yet', 'tok-5', 0, later));
    const revoke = scriptedRevoke(store, {
      'tok-1': { kind: 'revoked' },
      'tok-2': { kind: 'invalid', reason: 'invalid_grant' },
      'tok-3': { kind: 'retry', reason: 'apple 502' },
      'tok-4': { kind: 'retry', reason: 'timeout' },
    });

    const result = await sweepRevocations(store, revoke, NOW);
    expect(result).toEqual({ processed: 4, revoked: 1, invalid: 1, retried: 1, exhausted: 1, purged: 0 });

    expect(store.row(gone, 'c-revoked')).toMatchObject({ status: 'revoked', refresh_token: null, revoked_at: iso(NOW) });
    expect(store.row(gone, 'c-invalid')).toMatchObject({ status: 'invalid', refresh_token: null, last_error: 'invalid_grant' });
    expect(store.row(gone, 'c-retry')).toMatchObject({ status: 'pending', refresh_token: 'tok-3', attempts: 4, last_error: 'apple 502', next_attempt_at: '2026-10-12T22:00:00.000Z' });
    expect(store.row(gone, 'c-last')).toMatchObject({ status: 'exhausted', refresh_token: null, attempts: MAX_ATTEMPTS, last_error: 'timeout' });
    expect(store.row(other, 'c-not-yet')).toMatchObject({ status: 'pending', refresh_token: 'tok-5', attempts: 0 });
    expect(store.log.filter((l) => l.startsWith('apple:'))).toEqual(['apple:tok-1', 'apple:tok-2', 'apple:tok-3', 'apple:tok-4']);
  });

  it('respects the batch limit, oldest first', async () => {
    const store = new FakeStore();
    store.seedRow(pendingRow(gone, 'c-older', 'tok-older', 1, new Date(NOW.getTime() - 10 * MIN)));
    store.seedRow(pendingRow(gone, 'c-newer', 'tok-newer', 1, new Date(NOW.getTime() - 5 * MIN)));
    const revoke = scriptedRevoke(store, { 'tok-older': { kind: 'revoked' }, 'tok-newer': { kind: 'revoked' } });
    const result = await sweepRevocations(store, revoke, NOW, 1);
    expect(result.processed).toBe(1);
    expect(store.log.filter((l) => l.startsWith('apple:'))).toEqual(['apple:tok-older']);
    expect(store.row(gone, 'c-newer')).toMatchObject({ status: 'pending' });
  });

  it('purges terminal rows older than the retention window and keeps recent ones', async () => {
    const store = new FakeStore();
    const old = new Date(NOW.getTime() - (PURGE_AFTER_DAYS + 1) * 86_400_000);
    const recent = new Date(NOW.getTime() - 2 * 86_400_000);
    store.seedRow({ user_id: gone, client_id: 'c-old-revoked', refresh_token: null, status: 'revoked', attempts: 0, last_error: null, next_attempt_at: iso(old), updated_at: iso(old), revoked_at: iso(old) });
    store.seedRow({ user_id: gone, client_id: 'c-old-exhausted', refresh_token: null, status: 'exhausted', attempts: MAX_ATTEMPTS, last_error: 'timeout', next_attempt_at: iso(old), updated_at: iso(old), revoked_at: null });
    store.seedRow({ user_id: gone, client_id: 'c-recent', refresh_token: null, status: 'revoked', attempts: 0, last_error: null, next_attempt_at: iso(recent), updated_at: iso(recent), revoked_at: iso(recent) });
    store.seedRow(pendingRow(other, 'c-pending-old', 'tok-p', 2, new Date(NOW.getTime() + 60 * MIN)));
    const result = await sweepRevocations(store, scriptedRevoke(store, {}), NOW);
    expect(result).toEqual({ processed: 0, revoked: 0, invalid: 0, retried: 0, exhausted: 0, purged: 2 });
    expect(store.row(gone, 'c-old-revoked')).toBeUndefined();
    expect(store.row(gone, 'c-old-exhausted')).toBeUndefined();
    expect(store.row(gone, 'c-recent')).toBeDefined();
    expect(store.row(other, 'c-pending-old')).toBeDefined();
  });
});

describe('appleReadiness — what native asks before deletion', () => {
  it('reports an Apple identity with nothing stored (native should re-authorize first)', () => {
    expect(appleReadiness([], [{ provider: 'apple' }, { provider: 'email' }], 'it.gostash.stash')).toEqual({ apple_identity: true, stored: false, clients: [] });
  });
  it('maps stored tokens to ios/web by audience', () => {
    const rows = [
      { client_id: 'it.gostash.stash', created_at: '2026-10-12T19:00:00Z' },
      { client_id: 'it.gostash.web', created_at: '2026-10-11T19:00:00Z' },
    ];
    expect(appleReadiness(rows, [{ provider: 'apple' }], 'it.gostash.stash')).toEqual({
      apple_identity: true,
      stored: true,
      clients: [
        { client: 'ios', obtained_at: '2026-10-12T19:00:00Z' },
        { client: 'web', obtained_at: '2026-10-11T19:00:00Z' },
      ],
    });
  });
  it('is false/empty for a person who never used Apple', () => {
    expect(appleReadiness([], null, null)).toEqual({ apple_identity: false, stored: false, clients: [] });
  });
});

describe('revokeAtApple — the real call, with a fake transport', () => {
  async function testPem() {
    const pair = await crypto.subtle.generateKey({ name: 'ECDSA', namedCurve: 'P-256' }, true, ['sign', 'verify']);
    const der = new Uint8Array(await crypto.subtle.exportKey('pkcs8', pair.privateKey));
    const b64 = btoa(String.fromCharCode(...der));
    return `-----BEGIN PRIVATE KEY-----\n${b64.replace(/(.{64})/g, '$1\n')}\n-----END PRIVATE KEY-----\n`;
  }
  const token = { client_id: 'it.gostash.stash', refresh_token: 'r-secret' };

  it('posts the form Apple expects and classifies a 200', async () => {
    const env = { teamId: '3CH3K9NTT2', keyId: '3MDLB623WL', privateKeyPem: await testPem() };
    let captured: { url: string; init: RequestInit } | null = null;
    const fetchImpl = (async (url: string | URL | Request, init?: RequestInit) => {
      captured = { url: String(url), init: init ?? {} };
      return new Response(null, { status: 200 });
    }) as typeof fetch;
    await expect(revokeAtApple({ fetch: fetchImpl, env, now: NOW }, token)).resolves.toEqual({ kind: 'revoked' });
    const form = new URLSearchParams(String(captured!.init.body));
    expect(captured!.url).toBe('https://appleid.apple.com/auth/revoke');
    expect(form.get('client_id')).toBe('it.gostash.stash');
    expect(form.get('token')).toBe('r-secret');
    expect(form.get('token_type_hint')).toBe('refresh_token');
    expect(form.get('client_secret')!.split('.')).toHaveLength(3);
    expect(captured!.init.signal).toBeInstanceOf(AbortSignal);
  });

  it('reads Apple’s error body on a refusal', async () => {
    const env = { teamId: 'T', keyId: 'K', privateKeyPem: await testPem() };
    const fetchImpl = (async () => new Response(JSON.stringify({ error: 'invalid_grant' }), { status: 400 })) as typeof fetch;
    await expect(revokeAtApple({ fetch: fetchImpl, env, now: NOW }, token)).resolves.toEqual({ kind: 'invalid', reason: 'invalid_grant' });
  });

  it('turns a timeout or a network failure into a retry, never a throw', async () => {
    const env = { teamId: 'T', keyId: 'K', privateKeyPem: await testPem() };
    const timeout = (async () => {
      throw Object.assign(new Error('The operation was aborted due to timeout'), { name: 'TimeoutError' });
    }) as typeof fetch;
    await expect(revokeAtApple({ fetch: timeout, env, now: NOW }, token)).resolves.toEqual({ kind: 'retry', reason: 'timeout' });
    const offline = (async () => {
      throw new TypeError('fetch failed');
    }) as typeof fetch;
    await expect(revokeAtApple({ fetch: offline, env, now: NOW }, token)).resolves.toEqual({ kind: 'retry', reason: 'fetch failed' });
  });

  it('treats an unusable key as a retry (secrets can be fixed later; the token stays queued)', async () => {
    const env = { teamId: 'T', keyId: 'K', privateKeyPem: 'not a key' };
    const fetchImpl = (async () => new Response(null, { status: 200 })) as typeof fetch;
    const outcome = await revokeAtApple({ fetch: fetchImpl, env, now: NOW }, token);
    expect(outcome.kind).toBe('retry');
  });
});
