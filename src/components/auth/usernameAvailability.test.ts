// src/components/auth/usernameAvailability.test.ts
import { USERNAME_RE, isFallbackDisplayName, isUsernameTaken, sanitizeUsername, suggestHandle } from './usernameAvailability';

const probe = vi.hoisted(() => ({ row: null as null | { id: string } }));
vi.mock('@/integrations/supabase/client', () => ({
  supabase: {
    from: () => ({ select: () => ({ eq: () => ({ maybeSingle: async () => ({ data: probe.row, error: null }) }) }) }),
  },
}));

describe('usernameAvailability', () => {
  it('sanitizes to lowercase [a-z0-9], max 20', () => {
    expect(sanitizeUsername('@Will Dzierson!')).toBe('willdzierson');
    expect(sanitizeUsername('a'.repeat(30))).toHaveLength(20);
    expect(USERNAME_RE.test('ab')).toBe(false);
    expect(USERNAME_RE.test('abc')).toBe(true);
  });

  it('suggests a handle from a name only when it is long enough', () => {
    expect(suggestHandle('Will Dzierson')).toBe('willdzierson');
    expect(suggestHandle('李')).toBeNull();
    expect(suggestHandle(undefined)).toBeNull();
  });

  it('treats the person\'s own row as available', async () => {
    probe.row = { id: 'u1' };
    expect(await isUsernameTaken('will')).toBe(true);
    expect(await isUsernameTaken('will', 'u1')).toBe(false);
    probe.row = null;
    expect(await isUsernameTaken('free')).toBe(false);
  });

  it('knows a server fallback display name when it sees one', () => {
    expect(isFallbackDisplayName('stash3', 'stash3', 'x@privaterelay.appleid.com')).toBe(true); // the handle itself
    expect(isFallbackDisplayName('will', 'will7', 'will@gostash.it')).toBe(true); // the email's local part
    expect(isFallbackDisplayName(null, 'will7', 'will@gostash.it')).toBe(true); // nothing
    expect(isFallbackDisplayName('Will Dzierson', 'will7', 'will@gostash.it')).toBe(false); // a name the person has
    expect(isFallbackDisplayName('', 'a', undefined)).toBe(true);
  });
});
