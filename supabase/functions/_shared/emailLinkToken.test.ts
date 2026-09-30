import { describe, expect, it } from 'vitest';
import { signEmailLinkToken, verifyEmailLinkToken } from './emailLinkToken';

const uid = '11111111-1111-4111-8111-111111111111';
const secret = 'test-secret';
const future = new Date('2026-10-06T00:00:00Z');
const now = new Date('2026-09-06T00:00:00Z');

describe('email link token', () => {
  it('round-trips', async () => {
    const token = await signEmailLinkToken(uid, secret, future);
    expect(await verifyEmailLinkToken(token, secret, now)).toBe(uid);
    expect(token).not.toContain('+');
    expect(token).not.toContain('/');
    expect(token).not.toContain('=');
  });
  it('rejects tampering, wrong secret, expiry, garbage', async () => {
    const token = await signEmailLinkToken(uid, secret, future);
    const [payload, sig] = token.split('.');
    expect(await verifyEmailLinkToken(`${payload}x.${sig}`, secret, now)).toBeNull();
    expect(await verifyEmailLinkToken(token, 'other', now)).toBeNull();
    expect(await verifyEmailLinkToken(token, secret, new Date('2026-11-01T00:00:00Z'))).toBeNull();
    expect(await verifyEmailLinkToken('nope', secret, now)).toBeNull();
    expect(await verifyEmailLinkToken('', secret, now)).toBeNull();
    expect(await verifyEmailLinkToken(null as unknown as string, secret, now)).toBeNull();
    expect(await verifyEmailLinkToken(undefined as unknown as string, secret, now)).toBeNull();
  });
});
