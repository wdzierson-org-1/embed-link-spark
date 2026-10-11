// src/utils/nonce.ts
// The id-token rule (spec §4.1): the provider receives the SHA-256 of a random nonce and signs
// it into the identity token; Supabase receives the raw nonce and checks the hash matches.
const toHex = (bytes: Uint8Array) => Array.from(bytes, (b) => b.toString(16).padStart(2, '0')).join('');
const toBase64Url = (bytes: Uint8Array) =>
  btoa(String.fromCharCode(...bytes)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');

export const sha256Hex = async (text: string) =>
  toHex(new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(text))));

export type Nonce = { raw: string; hashed: string };

export const makeNonce = async (): Promise<Nonce> => {
  const raw = toBase64Url(crypto.getRandomValues(new Uint8Array(32)));
  return { raw, hashed: await sha256Hex(raw) };
};
