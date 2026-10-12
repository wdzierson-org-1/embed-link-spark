// supabase/functions/_shared/appleClientSecret.test.ts
// @vitest-environment node
import { describe, expect, it } from 'vitest';
import { decodeBase64Secret, makeAppleClientSecret, pemToPkcs8 } from './appleClientSecret';

const b64 = (bytes: Uint8Array) => btoa(String.fromCharCode(...bytes));
const fromB64url = (s: string) => Uint8Array.from(atob(s.replace(/-/g, '+').replace(/_/g, '/') + '='.repeat((4 - (s.length % 4)) % 4)), (c) => c.charCodeAt(0));

async function testKey() {
  const pair = await crypto.subtle.generateKey({ name: 'ECDSA', namedCurve: 'P-256' }, true, ['sign', 'verify']);
  const der = new Uint8Array(await crypto.subtle.exportKey('pkcs8', pair.privateKey));
  const pem = `-----BEGIN PRIVATE KEY-----\n${b64(der).replace(/(.{64})/g, '$1\n')}\n-----END PRIVATE KEY-----\n`;
  return { pair, pem, der };
}

describe('appleClientSecret', () => {
  it('reads a PEM back to its DER bytes and a base64 secret back to text', async () => {
    const { pem, der } = await testKey();
    expect(pemToPkcs8(pem)).toEqual(der);
    expect(decodeBase64Secret(btoa(pem))).toBe(pem);
  });

  it('mints an ES256 JWT Apple will accept: header kid, iss/sub/aud/iat/exp, valid signature', async () => {
    const { pair, pem } = await testKey();
    const now = new Date('2026-10-11T12:00:00Z');
    const jwt = await makeAppleClientSecret({ teamId: '3CH3K9NTT2', keyId: '3MDLB623WL', clientId: 'it.gostash.web', privateKeyPem: pem, now });
    const [h, p, s] = jwt.split('.');
    expect(JSON.parse(new TextDecoder().decode(fromB64url(h)))).toEqual({ alg: 'ES256', kid: '3MDLB623WL', typ: 'JWT' });
    const claims = JSON.parse(new TextDecoder().decode(fromB64url(p)));
    expect(claims).toEqual({ iss: '3CH3K9NTT2', iat: 1791720000, exp: 1791720600, aud: 'https://appleid.apple.com', sub: 'it.gostash.web' });
    const ok = await crypto.subtle.verify({ name: 'ECDSA', hash: 'SHA-256' }, pair.publicKey, fromB64url(s), new TextEncoder().encode(`${h}.${p}`));
    expect(ok).toBe(true);
  });
});
