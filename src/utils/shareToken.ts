/**
 * Share links (docs/ui-changes.md 2026-10-09): a save's unlisted, read-only address is
 * `/s/<token>`, where the token is ten characters of base62, minted here and stored in
 * `items.share_token`. Ten characters is ~59 bits: short enough to read out, far too many to
 * guess. iOS mints the same shape.
 */
const ALPHABET = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
export const SHARE_TOKEN_LENGTH = 10;
export const SHARE_TOKEN_PATTERN = /^[A-Za-z0-9]{10}$/;

export const mintShareToken = (): string => {
  let token = '';
  while (token.length < SHARE_TOKEN_LENGTH) {
    const bytes = new Uint8Array(SHARE_TOKEN_LENGTH * 2);
    crypto.getRandomValues(bytes);
    for (const byte of bytes) {
      // Rejection sampling keeps every character equally likely (256 is not a multiple of 62)
      if (byte >= 248) continue;
      token += ALPHABET[byte % 62];
      if (token.length === SHARE_TOKEN_LENGTH) break;
    }
  }
  return token;
};

export const shareUrlFor = (token: string, origin: string = window.location.origin): string =>
  `${origin}/s/${token}`;
