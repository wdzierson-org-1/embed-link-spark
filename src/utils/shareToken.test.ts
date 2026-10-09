import { SHARE_TOKEN_PATTERN, mintShareToken, shareUrlFor } from './shareToken';

describe('share tokens', () => {
  it('are ten characters of base62, different every time', () => {
    const tokens = new Set(Array.from({ length: 200 }, () => mintShareToken()));
    tokens.forEach((token) => expect(token).toMatch(SHARE_TOKEN_PATTERN));
    expect(tokens.size).toBe(200);
  });

  it('address a save at /s/<token> on the app’s origin', () => {
    expect(shareUrlFor('Xk3mN9pQ2a', 'https://www.gostash.it')).toBe('https://www.gostash.it/s/Xk3mN9pQ2a');
  });
});
