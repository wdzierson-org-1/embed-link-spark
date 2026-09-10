// supabase/functions/_shared/emailLinkToken.ts
//
// Signed, expiring link for one-click email actions (opt-out today). Web
// Crypto only, so the same file runs under Deno and vitest (Node ≥ 18).

const enc = new TextEncoder();

const b64url = (bytes: Uint8Array) =>
  btoa(String.fromCharCode(...bytes)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');

const fromB64url = (s: string): Uint8Array | null => {
  try {
    const b64 = s.replace(/-/g, '+').replace(/_/g, '/') + '='.repeat((4 - (s.length % 4)) % 4);
    return Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
  } catch {
    return null;
  }
};

async function hmac(secret: string, payload: string): Promise<Uint8Array> {
  const key = await crypto.subtle.importKey('raw', enc.encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  return new Uint8Array(await crypto.subtle.sign('HMAC', key, enc.encode(payload)));
}

export async function signEmailLinkToken(userId: string, secret: string, expiresAt: Date): Promise<string> {
  const payload = b64url(enc.encode(`${userId}.${Math.floor(expiresAt.getTime() / 1000)}`));
  return `${payload}.${b64url(await hmac(secret, payload))}`;
}

export async function verifyEmailLinkToken(token: string, secret: string, now: Date = new Date()): Promise<string | null> {
  const parts = token.split('.');
  if (parts.length !== 2) return null;
  const [payload, sig] = parts;
  const expected = b64url(await hmac(secret, payload));
  if (expected.length !== sig.length) return null;
  let diff = 0;
  for (let i = 0; i < expected.length; i++) diff |= expected.charCodeAt(i) ^ sig.charCodeAt(i);
  if (diff !== 0) return null;
  const raw = fromB64url(payload);
  if (!raw) return null;
  const [userId, exp] = new TextDecoder().decode(raw).split('.');
  if (!userId || !/^\d+$/.test(exp ?? '')) return null;
  if (Number(exp) * 1000 < now.getTime()) return null;
  return userId;
}
