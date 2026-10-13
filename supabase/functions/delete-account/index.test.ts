// supabase/functions/delete-account/index.test.ts
// @vitest-environment node
//
// The handler end to end with the Deno/esm imports mocked. The Apple step's contract changed on
// 2026-10-12 (AS-APPLE-REVOCATION): tokens are staged in apple_revocations BEFORE the user is
// deleted, Apple is asked only AFTER the auth deletion succeeded (a failed deletion never costs a
// live account its grant); unreadable tokens or a failed copy refuse the deletion (503); Apple
// failures leave the row pending. Queue/sweep logic itself is covered in
// _shared/appleRevocation.test.ts.
import { afterEach, beforeAll, beforeEach, describe, expect, it, vi, type MockInstance } from 'vitest';

const state = vi.hoisted(() => ({
  handler: null as null | ((req: Request) => Promise<Response>),
  tokens: [] as Array<{ client_id: string; refresh_token: string }>,
  tokensError: null as null | string,
  queueError: null as null | string,
  deleteError: null as null | string,
  queue: new Map<string, Record<string, unknown>>(),
  calls: [] as string[],
  signals: [] as Array<AbortSignal | null | undefined>,
  revokeStatus: 200,
  revokeBody: '',
  fetchError: null as null | Error,
  baseEnv: {} as Record<string, string>,
  env: {} as Record<string, string>,
}));

vi.mock('https://deno.land/std@0.190.0/http/server.ts', () => ({ serve: (h: typeof state.handler) => { state.handler = h; } }));
vi.mock('https://esm.sh/stripe@18.5.0', () => ({ default: class {} }));
vi.mock('https://esm.sh/@supabase/supabase-js@2.57.2', () => ({
  createClient: () => ({
    auth: {
      getUser: async () => ({ data: { user: { id: 'user-1', email: 'will@example.com' } }, error: null }),
      admin: {
        deleteUser: async () => {
          state.calls.push('deleteUser');
          return { error: state.deleteError ? { message: state.deleteError } : null };
        },
      },
    },
    storage: { from: () => ({ list: async () => ({ data: [], error: null }), remove: async () => ({ error: null }) }) },
    from: (table: string) => {
      if (table === 'apple_sign_in_tokens') {
        return { select: () => ({ eq: async () => (state.tokensError ? { data: null, error: { message: state.tokensError } } : { data: state.tokens, error: null }) }) };
      }
      if (table === 'apple_revocations') {
        return {
          upsert: async (rows: Array<Record<string, unknown>>) => {
            state.calls.push(`queue:${rows.map((r) => r.client_id).join(',')}`);
            if (state.queueError) return { error: { message: state.queueError } };
            for (const r of rows) state.queue.set(String(r.client_id), { ...r });
            return { error: null };
          },
          update: (patch: Record<string, unknown>) => ({
            eq: () => ({
              eq: async (_column: string, clientId: string) => {
                const row = state.queue.get(clientId);
                if (row) state.queue.set(clientId, { ...row, ...patch });
                return { error: null };
              },
            }),
          }),
        };
      }
      throw new Error(`unexpected table ${table}`);
    },
  }),
}));

const b64url = (s: string) => btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
const sessionJwt = `${b64url('{"alg":"HS256"}')}.${b64url('{"sub":"user-1"}')}.sig`;

// The function logs every step: keep that off the test output, and read it back as one string.
let log: MockInstance<typeof console.log>;
let warn: MockInstance<typeof console.warn>;
const logged = () => [...log.mock.calls, ...warn.mock.calls].map((args) => args.join(' ')).join('\n');
// Calls through to the real thing; it only records which timeouts the revoke requests ask for.
let timeout: MockInstance<typeof AbortSignal.timeout>;

beforeAll(async () => {
  const pair = await crypto.subtle.generateKey({ name: 'ECDSA', namedCurve: 'P-256' }, true, ['sign', 'verify']);
  const der = new Uint8Array(await crypto.subtle.exportKey('pkcs8', pair.privateKey));
  const pem = `-----BEGIN PRIVATE KEY-----\n${btoa(String.fromCharCode(...der))}\n-----END PRIVATE KEY-----\n`;
  state.baseEnv = { SUPABASE_URL: 'https://x.supabase.co', SUPABASE_SERVICE_ROLE_KEY: 'service', APPLE_TEAM_ID: 't', APPLE_KEY_ID: 'k', APPLE_SIGNIN_PRIVATE_KEY_B64: btoa(pem), APPLE_SERVICES_ID: 'it.gostash.web', APPLE_BUNDLE_ID: 'it.gostash.stash' };
  vi.stubGlobal('Deno', { env: { get: (k: string) => state.env[k] } }); // no STRIPE_SECRET_KEY → Stripe step skipped
  vi.stubGlobal('fetch', async (url: string, init: RequestInit) => {
    const form = new URLSearchParams(String(init.body));
    state.calls.push(`revoke:${form.get('client_id')}:${form.get('token')}:${form.get('token_type_hint')}:${url}`);
    state.signals.push(init.signal);
    if (state.fetchError) throw state.fetchError;
    return new Response(state.revokeBody, { status: state.revokeStatus });
  });
  await import('./index.ts');
});

beforeEach(() => {
  state.tokens = [];
  state.tokensError = null;
  state.queueError = null;
  state.deleteError = null;
  state.queue = new Map();
  state.calls = [];
  state.signals = [];
  state.revokeStatus = 200;
  state.revokeBody = '';
  state.fetchError = null;
  state.env = { ...state.baseEnv };
  log = vi.spyOn(console, 'log').mockImplementation(() => {});
  warn = vi.spyOn(console, 'warn').mockImplementation(() => {});
  timeout = vi.spyOn(AbortSignal, 'timeout');
});

afterEach(() => {
  log.mockRestore();
  warn.mockRestore();
  timeout.mockRestore();
});

const del = () => state.handler!(new Request('https://x/delete-account', { method: 'POST', headers: { Authorization: `Bearer ${sessionJwt}` } }));
const REVOKE = 'https://appleid.apple.com/auth/revoke';

describe('delete-account — Apple revocation', () => {
  it('queues every stored Apple token, deletes the user, and only then revokes each', async () => {
    state.tokens = [{ client_id: 'it.gostash.web', refresh_token: 'r-web' }, { client_id: 'it.gostash.stash', refresh_token: 'r-ios' }];
    const res = await del();
    expect(res.status).toBe(200);
    expect(await res.json()).toMatchObject({ deleted: true, apple: { revoked: 2, failed: 0, pending: 0, invalid: 0 } });
    expect(state.calls).toEqual([
      'queue:it.gostash.web,it.gostash.stash', // the copy that outlives the account comes first
      'deleteUser', // the account goes before Apple hears anything
      `revoke:it.gostash.web:r-web:refresh_token:${REVOKE}`,
      `revoke:it.gostash.stash:r-ios:refresh_token:${REVOKE}`,
    ]);
    expect(state.queue.get('it.gostash.web')).toMatchObject({ user_id: 'user-1', status: 'revoked', refresh_token: null });
    expect(state.queue.get('it.gostash.stash')).toMatchObject({ status: 'revoked', refresh_token: null });
    // Nothing the function logged carries a refresh token or a client-secret JWT ("eyJ" is base64url of `{"`).
    const joined = logged();
    expect(joined).toContain('Apple done'); // the capture works, so the next line cannot pass vacuously
    expect(joined).not.toMatch(/r-web|r-ios|eyJ/);
  });

  it('refuses to delete when the stored tokens cannot be read (nothing queued, Apple never asked)', async () => {
    state.tokensError = 'connection reset';
    const res = await del();
    expect(res.status).toBe(503);
    expect(await res.json()).toEqual({ deleted: false, error: 'apple_tokens_unavailable', retryable: true });
    expect(state.calls).toEqual([]);
  });

  it('refuses to delete when the copy into the queue fails (Apple never asked)', async () => {
    state.tokens = [{ client_id: 'it.gostash.web', refresh_token: 'r-web' }];
    state.queueError = 'permission denied';
    const res = await del();
    expect(res.status).toBe(503);
    expect(await res.json()).toEqual({ deleted: false, error: 'apple_tokens_unavailable', retryable: true });
    expect(state.calls).toEqual(['queue:it.gostash.web']);
    expect(logged()).not.toMatch(/r-web|eyJ/);
  });

  it('leaves the queued token untouched and reports 500 when the auth deletion fails (Apple never asked)', async () => {
    state.tokens = [{ client_id: 'it.gostash.web', refresh_token: 'r-web' }];
    state.deleteError = 'boom';
    const res = await del();
    expect(res.status).toBe(500);
    expect(await res.json()).toEqual({ deleted: false, error: 'auth delete: boom' });
    expect(state.calls).toEqual(['queue:it.gostash.web', 'deleteUser']);
    // The row waits with its token; the sweep leaves it alone while the account exists, and the
    // next delete-account run re-stages it.
    expect(state.queue.get('it.gostash.web')).toMatchObject({ status: 'pending', refresh_token: 'r-web', attempts: 0 });
    expect(logged()).not.toMatch(/r-web|eyJ/);
  });

  it('still deletes when Apple refuses the revoke, leaving the token queued for the sweep', async () => {
    state.tokens = [{ client_id: 'it.gostash.web', refresh_token: 'r-web' }];
    state.revokeStatus = 503;
    const res = await del();
    expect(res.status).toBe(200);
    expect(await res.json()).toMatchObject({ deleted: true, apple: { revoked: 0, failed: 1, pending: 1, invalid: 0 } });
    expect(state.calls).toEqual(['queue:it.gostash.web', 'deleteUser', `revoke:it.gostash.web:r-web:refresh_token:${REVOKE}`]);
    expect(state.queue.get('it.gostash.web')).toMatchObject({ status: 'pending', refresh_token: 'r-web', attempts: 1, last_error: 'apple 503' });
  });

  it('treats Apple’s invalid_grant as terminal: nothing to retry, token dropped, account deleted', async () => {
    state.tokens = [{ client_id: 'it.gostash.web', refresh_token: 'r-web' }];
    state.revokeStatus = 400;
    state.revokeBody = JSON.stringify({ error: 'invalid_grant' });
    const res = await del();
    expect(await res.json()).toMatchObject({ deleted: true, apple: { revoked: 0, failed: 0, pending: 0, invalid: 1 } });
    expect(state.queue.get('it.gostash.web')).toMatchObject({ status: 'invalid', refresh_token: null, last_error: 'invalid_grant' });
    expect(state.calls).toEqual(['queue:it.gostash.web', 'deleteUser', `revoke:it.gostash.web:r-web:refresh_token:${REVOKE}`]);
  });

  it('skips Apple entirely for an account without Apple tokens', async () => {
    const res = await del();
    expect(await res.json()).toMatchObject({ deleted: true, apple: { revoked: 0, failed: 0, pending: 0, invalid: 0 } });
    expect(state.calls).toEqual(['deleteUser']);
    expect(state.queue.size).toBe(0);
  });

  it('queues the tokens and still deletes when the Apple secrets are missing (Apple never contacted)', async () => {
    delete state.env.APPLE_KEY_ID;
    state.tokens = [{ client_id: 'it.gostash.web', refresh_token: 'r-web' }, { client_id: 'it.gostash.stash', refresh_token: 'r-ios' }];
    const res = await del();
    expect(res.status).toBe(200);
    expect(await res.json()).toMatchObject({ deleted: true, apple: { revoked: 0, failed: 2, pending: 2, invalid: 0 } });
    expect(state.calls).toEqual(['queue:it.gostash.web,it.gostash.stash', 'deleteUser']);
    expect(state.queue.get('it.gostash.web')).toMatchObject({ status: 'pending', refresh_token: 'r-web', attempts: 1 });
    expect(String(state.queue.get('it.gostash.web')!.last_error)).toMatch(/secrets missing/);
    expect(logged()).not.toMatch(/r-web|r-ios|eyJ/);
  });

  it('counts an unreachable Apple as pending and still deletes', async () => {
    state.tokens = [{ client_id: 'it.gostash.web', refresh_token: 'r-web' }];
    state.fetchError = new Error('network down');
    const res = await del();
    expect(res.status).toBe(200);
    expect(await res.json()).toMatchObject({ deleted: true, apple: { revoked: 0, failed: 1, pending: 1, invalid: 0 } });
    expect(state.calls).toEqual(['queue:it.gostash.web', 'deleteUser', `revoke:it.gostash.web:r-web:refresh_token:${REVOKE}`]);
    expect(state.queue.get('it.gostash.web')).toMatchObject({ status: 'pending', refresh_token: 'r-web', last_error: 'network down' });
    // A stalled Apple ends the same way: the request carries an 8 s timeout, whose abort lands in the same catch.
    expect(timeout.mock.calls).toEqual([[8_000]]);
    expect(state.signals[0]).toBe(timeout.mock.results[0].value);
  });
});
