// supabase/functions/delete-account/index.test.ts
// @vitest-environment node
import { beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';

const state = vi.hoisted(() => ({
  handler: null as null | ((req: Request) => Promise<Response>),
  tokens: [] as Array<{ client_id: string; refresh_token: string }>,
  calls: [] as string[],
  revokeStatus: 200,
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

beforeAll(async () => {
  const pair = await crypto.subtle.generateKey({ name: 'ECDSA', namedCurve: 'P-256' }, true, ['sign', 'verify']);
  const der = new Uint8Array(await crypto.subtle.exportKey('pkcs8', pair.privateKey));
  const pem = `-----BEGIN PRIVATE KEY-----\n${btoa(String.fromCharCode(...der))}\n-----END PRIVATE KEY-----\n`;
  state.env = { SUPABASE_URL: 'https://x.supabase.co', SUPABASE_SERVICE_ROLE_KEY: 'service', APPLE_TEAM_ID: 't', APPLE_KEY_ID: 'k', APPLE_SIGNIN_PRIVATE_KEY_B64: btoa(pem), APPLE_SERVICES_ID: 'it.gostash.web', APPLE_BUNDLE_ID: 'it.gostash.stash' };
  vi.stubGlobal('Deno', { env: { get: (k: string) => state.env[k] } }); // no STRIPE_SECRET_KEY → Stripe step skipped
  vi.stubGlobal('fetch', async (url: string, init: RequestInit) => {
    const form = new URLSearchParams(String(init.body));
    state.calls.push(`revoke:${form.get('client_id')}:${form.get('token')}:${form.get('token_type_hint')}:${url}`);
    return new Response('', { status: state.revokeStatus });
  });
  await import('./index.ts');
});

beforeEach(() => { state.tokens = []; state.calls = []; state.revokeStatus = 200; });

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
});
