// supabase/functions/apple-token-exchange/index.test.ts
// @vitest-environment node
import { beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';

const state = vi.hoisted(() => ({
  handler: null as null | ((req: Request) => Promise<Response>),
  user: { id: 'user-1', email: 'will@example.com' } as null | { id: string; email: string },
  upserted: null as null | { row: Record<string, unknown>; opts: Record<string, unknown> },
  apple: { status: 200, body: { refresh_token: 'r1', access_token: 'a1', id_token: 'i1' } as Record<string, unknown> },
  appleForm: null as null | URLSearchParams,
  env: {} as Record<string, string>,
}));

vi.mock('https://esm.sh/@supabase/supabase-js@2.57.2', () => ({
  createClient: () => ({
    auth: { getUser: async () => ({ data: { user: state.user }, error: state.user ? null : { message: 'nope' } }) },
    from: () => ({ upsert: async (row: Record<string, unknown>, opts: Record<string, unknown>) => { state.upserted = { row, opts }; return { error: null }; } }),
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

beforeAll(async () => {
  const pair = await crypto.subtle.generateKey({ name: 'ECDSA', namedCurve: 'P-256' }, true, ['sign', 'verify']);
  const der = new Uint8Array(await crypto.subtle.exportKey('pkcs8', pair.privateKey));
  const pem = `-----BEGIN PRIVATE KEY-----\n${btoa(String.fromCharCode(...der))}\n-----END PRIVATE KEY-----\n`;
  state.env = {
    SUPABASE_URL: 'https://x.supabase.co', SUPABASE_SERVICE_ROLE_KEY: 'service',
    APPLE_TEAM_ID: '3CH3K9NTT2', APPLE_KEY_ID: '3MDLB623WL', APPLE_SIGNIN_PRIVATE_KEY_B64: btoa(pem),
    APPLE_SERVICES_ID: 'it.gostash.web', APPLE_BUNDLE_ID: 'it.gostash.stash',
  };
  vi.stubGlobal('Deno', { env: { get: (k: string) => state.env[k] }, serve: (h: typeof state.handler) => { state.handler = h; } });
  vi.stubGlobal('fetch', async (_url: string, init: RequestInit) => {
    state.appleForm = new URLSearchParams(String(init.body));
    return new Response(JSON.stringify(state.apple.body), { status: state.apple.status, headers: { 'Content-Type': 'application/json' } });
  });
  await import('./index.ts');
});

beforeEach(() => {
  state.user = { id: 'user-1', email: 'will@example.com' };
  state.upserted = null;
  state.appleForm = null;
  state.apple = { status: 200, body: { refresh_token: 'r1' } };
});

describe('apple-token-exchange', () => {
  it('refuses a missing token, an agent token, and a dead session', async () => {
    expect((await call({ code: 'c', client: 'web' }, null)).status).toBe(401);
    expect((await call({ code: 'c', client: 'web' }, agentJwt)).status).toBe(403);
    state.user = null;
    expect((await call({ code: 'c', client: 'web' })).status).toBe(401);
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

  it('reports Apple refusals without storing anything', async () => {
    state.apple = { status: 400, body: { error: 'invalid_grant' } };
    const res = await call({ code: 'stale', client: 'web' });
    expect(res.status).toBe(502);
    expect(await res.json()).toEqual({ stored: false, error: 'invalid_grant' });
    expect(state.upserted).toBeNull();
  });
});
