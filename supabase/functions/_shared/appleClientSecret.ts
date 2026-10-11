// supabase/functions/_shared/appleClientSecret.ts
//
// Apple's "client secret" is a short-lived JWT signed with the team's Sign in with Apple key
// (ES256). Minting it per call means nothing long-lived is ever stored or rotated — the .p8 lives
// in APPLE_SIGNIN_PRIVATE_KEY_B64 (base64 of the PEM) and that is the only credential. Web Crypto
// only, so the same file runs under Deno and vitest.

const enc = new TextEncoder();
const b64url = (bytes: Uint8Array) =>
  btoa(String.fromCharCode(...bytes)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');

export function pemToPkcs8(pem: string): Uint8Array {
  const body = pem.replace(/-----(BEGIN|END) PRIVATE KEY-----/g, '').replace(/\s+/g, '');
  return Uint8Array.from(atob(body), (c) => c.charCodeAt(0));
}

export function decodeBase64Secret(b64: string): string {
  return new TextDecoder().decode(Uint8Array.from(atob(b64.replace(/\s+/g, '')), (c) => c.charCodeAt(0)));
}

export async function makeAppleClientSecret(opts: {
  teamId: string;
  keyId: string;
  clientId: string;
  privateKeyPem: string;
  now?: Date;
  ttlSeconds?: number;
}): Promise<string> {
  const iat = Math.floor((opts.now ?? new Date()).getTime() / 1000);
  const header = b64url(enc.encode(JSON.stringify({ alg: 'ES256', kid: opts.keyId, typ: 'JWT' })));
  const payload = b64url(enc.encode(JSON.stringify({
    iss: opts.teamId, iat, exp: iat + (opts.ttlSeconds ?? 600), aud: 'https://appleid.apple.com', sub: opts.clientId,
  })));
  const key = await crypto.subtle.importKey('pkcs8', pemToPkcs8(opts.privateKeyPem), { name: 'ECDSA', namedCurve: 'P-256' }, false, ['sign']);
  const signature = new Uint8Array(await crypto.subtle.sign({ name: 'ECDSA', hash: 'SHA-256' }, key, enc.encode(`${header}.${payload}`)));
  return `${header}.${payload}.${b64url(signature)}`;
}

export function appleEnv(): { teamId: string; keyId: string; privateKeyPem: string; servicesId: string; bundleId: string } {
  const get = (name: string) => {
    const value = Deno.env.get(name);
    if (!value) throw new Error(`${name} is not set`);
    return value;
  };
  return {
    teamId: get('APPLE_TEAM_ID'),
    keyId: get('APPLE_KEY_ID'),
    privateKeyPem: decodeBase64Secret(get('APPLE_SIGNIN_PRIVATE_KEY_B64')),
    servicesId: get('APPLE_SERVICES_ID'),
    bundleId: get('APPLE_BUNDLE_ID'),
  };
}
