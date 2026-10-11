// src/utils/nonce.test.ts
import { webcrypto } from 'node:crypto';
import { makeNonce, sha256Hex } from './nonce';

// jsdom has no subtle crypto; the browser does
if (!globalThis.crypto?.subtle) vi.stubGlobal('crypto', webcrypto);

describe('nonce', () => {
  it('hashes with SHA-256 as lowercase hex', async () => {
    expect(await sha256Hex('abc')).toBe('ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
  });

  it('makes a fresh base64url raw nonce whose hash is what the provider gets', async () => {
    const a = await makeNonce();
    const b = await makeNonce();
    expect(a.raw).toMatch(/^[A-Za-z0-9_-]{43}$/);
    expect(a.hashed).toBe(await sha256Hex(a.raw));
    expect(a.raw).not.toBe(b.raw);
  });
});
