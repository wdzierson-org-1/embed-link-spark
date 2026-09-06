// supabase/functions/_shared/agentToken.ts
//
// Supabase OAuth-server access tokens are ordinary user JWTs plus a
// `client_id` claim (docs: auth/oauth-server/oauth-flows → "Access token
// structure"). That claim is how every endpoint tells an agent token from a
// person's session. Decoding here is NOT verification — callers verify with
// auth.getUser first; this only reads claims off an already-trusted token.
// Import-free so it runs under Deno and vitest.

export function bearerToken(header: string | null | undefined): string | null {
  if (!header) return null;
  const match = /^Bearer\s+(.+)$/i.exec(header.trim());
  const token = match?.[1]?.trim();
  return token ? token : null;
}

export function decodeJwtPayload(token: string): Record<string, unknown> | null {
  const parts = token.split('.');
  if (parts.length !== 3) return null;
  try {
    const b64 = parts[1].replace(/-/g, '+').replace(/_/g, '/');
    const padded = b64 + '='.repeat((4 - (b64.length % 4)) % 4);
    const json = atob(padded);
    const payload = JSON.parse(json);
    return typeof payload === 'object' && payload !== null ? payload as Record<string, unknown> : null;
  } catch {
    return null;
  }
}

export function agentClientId(token: string): string | null {
  const payload = decodeJwtPayload(token);
  const clientId = payload?.client_id;
  return typeof clientId === 'string' && clientId.length > 0 ? clientId : null;
}

export function isAgentToken(token: string | null | undefined): boolean {
  return !!token && agentClientId(token) !== null;
}
