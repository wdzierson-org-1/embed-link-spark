// supabase/functions/apple-token-exchange/index.test.ts
// @vitest-environment node
import { afterEach, beforeAll, beforeEach, describe, expect, it, vi, type MockInstance } from 'vitest';

const state = vi.hoisted(() => ({
  handler: null as null | ((req: Request) => Promise<Response>),
  user: { id: 'user-1', email: 'will@example.com' } as null | { id: string; email: string },
  getUserTokens: [] as unknown[],
  upserted: null as null | { row: Record<string, unknown>; opts: Record<string, unknown> },
  upsertError: null as null | { message: string },
  apple: { status: 200, body: { refresh_token: 'r1', access_token: 'a1', id_token: 'i1' } as Record<string, unknown> },
  appleForm: null as null | URLSearchParams,
  fetchCount: 0,
  fetchError: null as null | Error,
  baseEnv: {} as Record<string, string>,
  env: {} as Record<string, string>,
}));

vi.mock('https://esm.sh/@supabase/supabase-js@2.57.2', () => ({
  createClient: () => ({
    auth: {
      getUser: async (token?: string) => {
        state.getUserTokens.push(token);
        return { data: { user: state.user }, error: state.user ? null : { message: 'nope' } };
      },
    },
    from: () => ({ upsert: async (row: Record<string, unknown>, opts: Record<string, unknown>) => { state.upserted = { row, opts }; return { error: state.upsertError }; } }),
  }),
}));

const b64url = (s: string) => btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
const jwt = (payload: Record<string, unknown>) => `${b64url('{"alg":"HS256"}')}.${b64url(JSON.stringify(payload))}.sig`;
const sessionJwt = jwt({ sub: 'user-1' });
const agentJwt = jwt({ sub: 'user-1', client_id: 'agent-1' });

const call = (body: unknown, token: string | null = sessionJwt) =>
  state.handler!(new Request('https://x/apple-token-exchange', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) },
    body: typeof body === 'string' ? body : JSON.stringify(body),
  }));

// Everything the function sent to console.warn, as one string (so a test never depends on how the args are split).
let warn: MockInstance<typeof console.warn>;
const logged = () => warn.mock.calls.map((args) => args.join(' ')).join('\n');

beforeAll(async () => {
  const pair = await crypto.subtle.generateKey({ name: 'ECDSA', namedCurve: 'P-256' }, true, ['sign', 'verify']);
  const der = new Uint8Array(await crypto.subtle.exportKey('pkcs8', pair.privateKey));
  const pem = `-----BEGIN PRIVATE KEY-----\n${btoa(String.fromCharCode(...der))}\n-----END PRIVATE KEY-----\n`;
  state.baseEnv = {
    SUPABASE_URL: 'https://x.supabase.co', SUPABASE_SERVICE_ROLE_KEY: 'service',
    APPLE_TEAM_ID: '3CH3K9NTT2', APPLE_KEY_ID: '3MDLB623WL', APPLE_SIGNIN_PRIVATE_KEY_B64: btoa(pem),
    APPLE_SERVICES_ID: 'it.gostash.web', APPLE_BUNDLE_ID: 'it.gostash.stash',
  };
  vi.stubGlobal('Deno', { env: { get: (k: string) => state.env[k] }, serve: (h: typeof state.handler) => { state.handler = h; } });
  vi.stubGlobal('fetch', async (_url: string, init: RequestInit) => {
    state.fetchCount += 1;
    if (state.fetchError) throw state.fetchError;
    state.appleForm = new URLSearchParams(String(init.body));
    return new Response(JSON.stringify(state.apple.body), { status: state.apple.status, headers: { 'Content-Type': 'application/json' } });
  });
  await import('./index.ts');
});

beforeEach(() => {
  state.user = { id: 'user-1', email: 'will@example.com' };
  state.getUserTokens = [];
  state.upserted = null;
  state.upsertError = null;
  state.appleForm = null;
  state.fetchCount = 0;
  state.fetchError = null;
  state.apple = { status: 200, body: { refresh_token: 'r1' } };
  state.env = { ...state.baseEnv };
  warn = vi.spyOn(console, 'warn').mockImplementation(() => {});
});

afterEach(() => {
  warn.mockRestore();
});

describe('apple-token-exchange', () => {
  it('refuses a missing token, an agent token, and a dead session', async () => {
    expect((await call({ code: 'c', client: 'web' }, null)).status).toBe(401);
    expect((await call({ code: 'c', client: 'web' }, agentJwt)).status).toBe(403);
    // Neither of those got as far as Supabase or Apple.
    expect(state.getUserTokens).toEqual([]);
    expect(state.fetchCount).toBe(0);
    state.user = null;
    expect((await call({ code: 'c', client: 'web' })).status).toBe(401);
    // A dead session did ask Supabase (with its token) and never reached Apple.
    expect(state.getUserTokens).toEqual([sessionJwt]);
    expect(state.fetchCount).toBe(0);
  });

  it('rejects a bad body', async () => {
    expect((await call('not json')).status).toBe(400);
    expect((await call({ code: '', client: 'web' })).status).toBe(400);
    expect((await call({ code: 'c', client: 'android' })).status).toBe(400);
  });

  it('exchanges a web code against the Services ID with the return URL and stores the refresh token', async () => {
    const res = await call({ code: 'c0de', client: 'web' });
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ stored: true });
    expect(state.getUserTokens).toEqual([sessionJwt]);
    expect(state.appleForm!.get('client_id')).toBe('it.gostash.web');
    expect(state.appleForm!.get('grant_type')).toBe('authorization_code');
    expect(state.appleForm!.get('code')).toBe('c0de');
    expect(state.appleForm!.get('redirect_uri')).toBe('https://www.gostash.it/auth');
    expect(state.appleForm!.get('client_secret')!.split('.')).toHaveLength(3);
    expect(state.upserted).toEqual({ row: { user_id: 'user-1', client_id: 'it.gostash.web', refresh_token: 'r1' }, opts: { onConflict: 'user_id,client_id' } });
  });

  it('exchanges an iOS code against the bundle id without a return URL', async () => {
    await call({ code: 'c0de', client: 'ios' });
    expect(state.appleForm!.get('client_id')).toBe('it.gostash.stash');
    expect(state.appleForm!.has('redirect_uri')).toBe(false);
    expect(state.upserted!.row.client_id).toBe('it.gostash.stash');
  });

  it('reports Apple refusals without storing anything, and logs only the error code', async () => {
    state.apple = { status: 400, body: { error: 'invalid_grant', access_token: 'LEAK' } };
    const res = await call({ code: 'stale', client: 'web' });
    expect(res.status).toBe(502);
    expect(await res.json()).toEqual({ stored: false, error: 'invalid_grant' });
    expect(state.upserted).toBeNull();
    expect(warn).toHaveBeenCalledTimes(1);
    expect(logged()).toContain('invalid_grant');
    expect(logged()).not.toContain('LEAK');
  });

  it('treats a 200 without a refresh token as a refusal and still logs no token', async () => {
    state.apple = { status: 200, body: { access_token: 'LEAK', id_token: 'LEAK' } };
    const res = await call({ code: 'c0de', client: 'web' });
    expect(res.status).toBe(502);
    expect(await res.json()).toEqual({ stored: false, error: 'apple 200' });
    expect(state.upserted).toBeNull();
    expect(warn).toHaveBeenCalledTimes(1);
    expect(logged()).toContain('no refresh_token');
    expect(logged()).not.toContain('LEAK');
  });

  it('reports an upsert failure as 500', async () => {
    state.upsertError = { message: 'boom' };
    const res = await call({ code: 'c0de', client: 'web' });
    expect(res.status).toBe(500);
    expect(await res.json()).toEqual({ stored: false, error: 'boom' });
  });

  it('answers 500 with JSON when the Apple secrets are missing', async () => {
    delete state.env.APPLE_KEY_ID;
    const res = await call({ code: 'c0de', client: 'web' });
    expect(res.status).toBe(500);
    expect(res.headers.get('Access-Control-Allow-Origin')).toBe('*');
    expect(await res.json()).toEqual({ stored: false, error: 'APPLE_KEY_ID is not set' });
    expect(warn).toHaveBeenCalledWith('[APPLE-TOKEN-EXCHANGE] failed', 'APPLE_KEY_ID is not set');
    expect(state.fetchCount).toBe(0);
    expect(state.upserted).toBeNull();
  });

  it('answers 500 with JSON when Apple cannot be reached', async () => {
    state.fetchError = new TypeError('error sending request for url (https://appleid.apple.com/auth/token)');
    const res = await call({ code: 'c0de', client: 'web' });
    expect(res.status).toBe(500);
    expect(res.headers.get('Access-Control-Allow-Origin')).toBe('*');
    expect(await res.json()).toEqual({ stored: false, error: state.fetchError.message });
    expect(state.upserted).toBeNull();
  });
});
