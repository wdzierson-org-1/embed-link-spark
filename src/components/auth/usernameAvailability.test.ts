// src/components/auth/usernameAvailability.test.ts
import { USERNAME_RE, handlePrefill, isFallbackDisplayName, isUsernameTaken, sanitizeUsername, suggestHandle } from './usernameAvailability';

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

describe('handlePrefill', () => {
  const person = (email: string | undefined, user_metadata: Record<string, unknown> = {}) => ({ email, user_metadata });

  it('starts from the name the provider gave us, ahead of the server handle', () => {
    expect(handlePrefill(person('will@example.com', { full_name: 'Will Dzierson' }), 'stash3')).toBe('willdzierson');
    expect(handlePrefill(person('will@example.com', { name: 'Will Dzierson' }), 'guest-ab12cd34')).toBe('willdzierson');
    // a name too short to make a handle, or not a string at all, is no name
    expect(handlePrefill(person('will@example.com', { full_name: '李' }), 'stash3')).toBe('stash3');
    expect(handlePrefill(person('will@example.com', { full_name: 42 }), 'stash3')).toBe('stash3');
  });

  it('lets a name the client just learned win over the metadata name and the server handle', () => {
    // Apple sends its name in the sign-in event itself; the metadata write that records it can land after the claim step opens
    expect(handlePrefill(person('will@example.com'), 'stash3', 'Will Dzierson')).toBe('willdzierson');
    expect(handlePrefill(person('will@example.com', { full_name: 'Someone Else' }), 'stash3', 'Will Dzierson')).toBe('willdzierson');
    // no such name: the metadata name, then the rest of the chain, exactly as before
    expect(handlePrefill(person('will@example.com', { full_name: 'Will Dzierson' }), 'stash3', null)).toBe('willdzierson');
    expect(handlePrefill(person('will@example.com'), 'stash3', undefined)).toBe('stash3');
  });

  it('keeps the server handle when there is no name and the forms would accept it', () => {
    expect(handlePrefill(person('will@example.com'), 'stash3')).toBe('stash3');
  });

  it('never prefills a guest-shaped handle: the email local part stands in', () => {
    expect(handlePrefill(person('will@example.com'), 'guest-ab12cd34')).toBe('will');
    expect(handlePrefill(person('Will.Dz@Example.com'), '')).toBe('willdz');
  });

  it('prefills nothing when all there is to go on is an Apple relay address, or no address', () => {
    expect(handlePrefill(person('kz8f3q2m@privaterelay.appleid.com'), 'guest-ab12cd34')).toBe('');
    expect(handlePrefill(person(undefined), 'guest-ab12cd34')).toBe('');
  });
});
