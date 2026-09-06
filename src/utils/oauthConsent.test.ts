import { afterEach, describe, expect, it, vi } from 'vitest';
import {
  consentReturnTo, decideAuthorization, hostOf, isLoopbackHost, isRedirect, revokeOAuthGrant,
} from './oauthConsent';

describe('isRedirect', () => {
  it('detects the already-consented / decided shape', () => {
    expect(isRedirect({ redirect_url: 'https://claude.ai/api/mcp/auth_callback?code=1' })).toBe(true);
    expect(isRedirect({ authorization_id: 'a', redirect_uri: 'x', client: { id: 'c', name: 'Claude' }, user: { id: 'u', email: 'e' }, scope: 'email' })).toBe(false);
  });
});

describe('consentReturnTo', () => {
  it('round-trips the authorization id through the sign-in page', () => {
    const url = consentReturnTo('abc 123');
    expect(url.startsWith('/auth?returnTo=')).toBe(true);
    const returnTo = new URLSearchParams(url.slice('/auth?'.length)).get('returnTo');
    expect(returnTo).toBe('/oauth/consent?authorization_id=abc%20123');
  });
});

describe('hostOf / isLoopbackHost', () => {
  it('extracts hosts and flags loopback redirects', () => {
    expect(hostOf('https://claude.ai/api/mcp/auth_callback')).toBe('claude.ai');
    expect(hostOf('http://localhost:3118/callback')).toBe('localhost');
    expect(hostOf('not a url')).toBeNull();
    expect(hostOf(undefined)).toBeNull();
    expect(isLoopbackHost('localhost')).toBe(true);
    expect(isLoopbackHost('127.0.0.1')).toBe(true);
    expect(isLoopbackHost('[::1]')).toBe(true);
    expect(isLoopbackHost('claude.ai')).toBe(false);
    expect(isLoopbackHost(null)).toBe(false);
  });
});

describe('REST helpers', () => {
  afterEach(() => vi.unstubAllGlobals());

  it('posts the consent decision with the session token and returns the redirect', async () => {
    const fetchMock = vi.fn(async () => new Response(JSON.stringify({ redirect_url: 'https://x/cb?code=1' }), { status: 200 }));
    vi.stubGlobal('fetch', fetchMock);
    const out = await decideAuthorization('auth-1', 'tok', 'approve');
    expect(out).toEqual({ redirect_url: 'https://x/cb?code=1' });
    const [url, init] = fetchMock.mock.calls[0] as unknown as [string, RequestInit];
    expect(url).toMatch(/\/auth\/v1\/oauth\/authorizations\/auth-1\/consent$/);
    expect(init.method).toBe('POST');
    expect((init.headers as Record<string, string>).Authorization).toBe('Bearer tok');
    expect(init.body).toBe(JSON.stringify({ action: 'approve' }));
  });

  it('surfaces GoTrue error descriptions', async () => {
    vi.stubGlobal('fetch', vi.fn(async () => new Response(JSON.stringify({ error: 'invalid_request', error_description: 'expired' }), { status: 400 })));
    await expect(decideAuthorization('auth-1', 'tok', 'deny')).rejects.toThrow('expired');
  });

  it('revokes by client id with DELETE', async () => {
    const fetchMock = vi.fn(async () => new Response(null, { status: 204 }));
    vi.stubGlobal('fetch', fetchMock);
    await revokeOAuthGrant('client-9', 'tok');
    const [url, init] = fetchMock.mock.calls[0] as unknown as [string, RequestInit];
    expect(url).toMatch(/\/auth\/v1\/user\/oauth\/grants\?client_id=client-9$/);
    expect(init.method).toBe('DELETE');
  });
});
