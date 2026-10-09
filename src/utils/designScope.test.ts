import { isV2Route } from './designScope';

describe('isV2Route', () => {
  it('puts the signed-in app and the pages that share its cards on DESIGN-v2', () => {
    for (const path of ['/home', '/settings', '/discover', '/feed/will', '/s/Xk3mN9pQ2a', '/admin', '/admin/users/abc', '/design/cards']) {
      expect(isV2Route(path), path).toBe(true);
    }
  });

  it('puts the way in on DESIGN-v2: sign in / sign up and choosing a new password', () => {
    for (const path of ['/auth', '/reset-password']) {
      expect(isV2Route(path), path).toBe(true);
    }
  });

  it('leaves marketing, pricing, legal and agent consent on v1 until their own redesign', () => {
    for (const path of ['/', '/pricing', '/privacy', '/terms', '/oauth/consent', '/subscription-success', '/homepage', '/feed', '/authors']) {
      expect(isV2Route(path), path).toBe(false);
    }
  });
});
