// supabase/functions/delete-account/index.test.ts
// @vitest-environment node
import { afterEach, beforeAll, beforeEach, describe, expect, it, vi, type MockInstance } from 'vitest';

const state = vi.hoisted(() => ({
  handler: null as null | ((req: Request) => Promise<Response>),
  tokens: [] as Array<{ client_id: string; refresh_token: string }>,
  calls: [] as string[],
  signals: [] as Array<AbortSignal | null | undefined>,
  revokeStatus: 200,
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
      admin: { deleteUser: async () => { state.calls.push('deleteUser'); return { error: null }; } },
    },
    storage: { from: () => ({ list: async () => ({ data: [], error: null }), remove: async () => ({ error: null }) }) },
    from: () => ({ select: () => ({ eq: async () => ({ data: state.tokens, error: null }) }) }),
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
    return new Response('', { status: state.revokeStatus });
  });
  await import('./index.ts');
});

beforeEach(() => {
  state.tokens = [];
  state.calls = [];
  state.signals = [];
  state.revokeStatus = 200;
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

describe('delete-account — Apple revocation', () => {
  it('revokes every stored Apple token before deleting the user', async () => {
    state.tokens = [{ client_id: 'it.gostash.web', refresh_token: 'r-web' }, { client_id: 'it.gostash.stash', refresh_token: 'r-ios' }];
    const res = await del();
    expect(res.status).toBe(200);
    expect(await res.json()).toMatchObject({ deleted: true, apple: { revoked: 2, failed: 0 } });
    expect(state.calls).toEqual([
      'revoke:it.gostash.web:r-web:refresh_token:https://appleid.apple.com/auth/revoke',
      'revoke:it.gostash.stash:r-ios:refresh_token:https://appleid.apple.com/auth/revoke',
      'deleteUser',
    ]);
    // Nothing the function logged carries a refresh token or a client-secret JWT ("eyJ" is base64url of `{"`).
    const joined = logged();
    expect(joined).toContain('Apple done'); // the capture works, so the next line cannot pass vacuously
    expect(joined).not.toMatch(/r-web|r-ios|eyJ/);
  });

  it('still deletes when Apple refuses the revoke', async () => {
    state.tokens = [{ client_id: 'it.gostash.web', refresh_token: 'r-web' }];
    state.revokeStatus = 400;
    const res = await del();
    expect(await res.json()).toMatchObject({ deleted: true, apple: { revoked: 0, failed: 1 } });
    expect(state.calls.at(-1)).toBe('deleteUser');
  });

  it('skips Apple entirely for an account without Apple tokens', async () => {
    const res = await del();
    expect(await res.json()).toMatchObject({ deleted: true, apple: { revoked: 0, failed: 0 } });
    expect(state.calls).toEqual(['deleteUser']);
  });

  it('skips revocation but still deletes when the Apple secrets are missing', async () => {
    delete state.env.APPLE_KEY_ID;
    state.tokens = [{ client_id: 'it.gostash.web', refresh_token: 'r-web' }, { client_id: 'it.gostash.stash', refresh_token: 'r-ios' }];
    const res = await del();
    expect(res.status).toBe(200);
    expect(await res.json()).toMatchObject({ deleted: true, apple: { revoked: 0, failed: 2 } });
    expect(state.calls).toEqual(['deleteUser']); // Apple was never contacted
  });

  it('counts an unreachable Apple as failed and still deletes', async () => {
    state.tokens = [{ client_id: 'it.gostash.web', refresh_token: 'r-web' }];
    state.fetchError = new Error('network down');
    const res = await del();
    expect(res.status).toBe(200);
    expect(await res.json()).toMatchObject({ deleted: true, apple: { revoked: 0, failed: 1 } });
    expect(state.calls).toEqual(['revoke:it.gostash.web:r-web:refresh_token:https://appleid.apple.com/auth/revoke', 'deleteUser']);
    // A stalled Apple ends the same way: the request carries an 8 s timeout, whose abort lands in the same catch.
    expect(timeout.mock.calls).toEqual([[8_000]]);
    expect(state.signals[0]).toBe(timeout.mock.results[0].value);
  });
});
