// src/components/auth/usernameAvailability.test.ts
import { USERNAME_RE, isUsernameTaken, sanitizeUsername, suggestHandle } from './usernameAvailability';

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
});
