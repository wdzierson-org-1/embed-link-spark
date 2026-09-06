// src/utils/oauthConsent.ts
//
// Supabase Auth OAuth-server calls the consent page and Settings need. Our
// supabase-js (2.50) predates `auth.oauth.*`, so these hit GoTrue's REST
// endpoints directly with the session JWT (same calls the newer client makes:
// GET  /auth/v1/oauth/authorizations/{id}
// POST /auth/v1/oauth/authorizations/{id}/consent  { action }
// GET  /auth/v1/user/oauth/grants
// DELETE /auth/v1/user/oauth/grants?client_id=…).
import { SUPABASE_PUBLISHABLE_KEY, SUPABASE_URL } from '@/integrations/supabase/client';

export interface OAuthClient {
  id: string;
  name: string;
  uri?: string;
  logo_uri?: string;
}

export interface AuthorizationDetails {
  authorization_id: string;
  redirect_uri: string;
  client: OAuthClient;
  user: { id: string; email: string };
  scope: string;
}

export interface OAuthRedirect {
  redirect_url: string;
}

export interface OAuthGrant {
  client: OAuthClient;
  scopes: string[];
  granted_at: string;
}

export const isRedirect = (r: AuthorizationDetails | OAuthRedirect): r is OAuthRedirect =>
  typeof (r as OAuthRedirect).redirect_url === 'string';

export const consentReturnTo = (authorizationId: string): string =>
  `/auth?returnTo=${encodeURIComponent(`/oauth/consent?authorization_id=${encodeURIComponent(authorizationId)}`)}`;

export const hostOf = (url: string | undefined): string | null => {
  if (!url) return null;
  try {
    return new URL(url).host.replace(/:\d+$/, '');
  } catch {
    return null;
  }
};

export const isLoopbackHost = (host: string | null): boolean =>
  host === 'localhost' || host === '127.0.0.1' || host === '[::1]';

const errorMessage = async (res: Response): Promise<string> => {
  try {
    const body = await res.json();
    return body.error_description || body.msg || body.message || body.error || `Request failed (${res.status})`;
  } catch {
    return `Request failed (${res.status})`;
  }
};

const authRequest = async (path: string, accessToken: string, init: RequestInit = {}): Promise<Response> => {
  const res = await fetch(`${SUPABASE_URL}/auth/v1${path}`, {
    ...init,
    headers: {
      apikey: SUPABASE_PUBLISHABLE_KEY,
      Authorization: `Bearer ${accessToken}`,
      'Content-Type': 'application/json',
      ...(init.headers as Record<string, string> | undefined),
    },
  });
  if (!res.ok) throw new Error(await errorMessage(res));
  return res;
};

export async function fetchAuthorizationDetails(authorizationId: string, accessToken: string): Promise<AuthorizationDetails | OAuthRedirect> {
  const res = await authRequest(`/oauth/authorizations/${encodeURIComponent(authorizationId)}`, accessToken);
  return res.json();
}

export async function decideAuthorization(authorizationId: string, accessToken: string, action: 'approve' | 'deny'): Promise<OAuthRedirect> {
  const res = await authRequest(`/oauth/authorizations/${encodeURIComponent(authorizationId)}/consent`, accessToken, {
    method: 'POST',
    body: JSON.stringify({ action }),
  });
  return res.json();
}

export async function listOAuthGrants(accessToken: string): Promise<OAuthGrant[]> {
  const res = await authRequest('/user/oauth/grants', accessToken);
  return res.json();
}

export async function revokeOAuthGrant(clientId: string, accessToken: string): Promise<void> {
  await authRequest(`/user/oauth/grants?client_id=${encodeURIComponent(clientId)}`, accessToken, { method: 'DELETE' });
}
