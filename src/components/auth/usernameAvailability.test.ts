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

  it('folds accents into their letters instead of dropping them', () => {
    expect(sanitizeUsername('José García')).toBe('josegarcia');
    expect(sanitizeUsername('Zoë')).toBe('zoe');
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

  it('starts from the name the provider gave us, ahead of the email and the server handle', () => {
    expect(handlePrefill(person('will@example.com', { full_name: 'Will Dzierson' }), 'stash3')).toBe('willdzierson');
    expect(handlePrefill(person('will@example.com', { name: 'Will Dzierson' }), 'guest-ab12cd34')).toBe('willdzierson');
  });

  it('lets a name the client just learned win over the metadata name and the rest of the chain', () => {
    // Apple sends its name in the sign-in event itself; the metadata write that records it can land after the claim step opens
    expect(handlePrefill(person('will@example.com'), 'stash3', 'Will Dzierson')).toBe('willdzierson');
    expect(handlePrefill(person('will@example.com', { full_name: 'Someone Else' }), 'stash3', 'Will Dzierson')).toBe('willdzierson');
    // no such name: the metadata name, then the rest of the chain
    expect(handlePrefill(person('will@example.com', { full_name: 'Will Dzierson' }), 'stash3', null)).toBe('willdzierson');
    expect(handlePrefill(person('will@example.com'), 'stash3', undefined)).toBe('will');
  });

  it('falls back to the email local part when there is no name, ahead of the server handle', () => {
    expect(handlePrefill(person('will@example.com'), 'stash3')).toBe('will');
    expect(handlePrefill(person('will@example.com'), 'guest-ab12cd34')).toBe('will');
    expect(handlePrefill(person('Will.Dz@Example.com'), '')).toBe('willdz');
    // a name that leaves too little (a non-Latin one), or is not a string at all, is no name — and the
    // email says more than the server's digit-padded handle
    expect(handlePrefill(person('ivanpetrov@example.com', { full_name: 'Иван Петров' }), '123')).toBe('ivanpetrov');
    expect(handlePrefill(person('will@example.com', { full_name: 42 }), 'stash3')).toBe('will');
  });

  it('takes the server handle when there is no name and the email gives nothing: a relay address, or too short a local part', () => {
    expect(handlePrefill(person('kz8f3q2m@privaterelay.appleid.com'), 'stash3')).toBe('stash3');
    expect(handlePrefill(person('jo@example.com'), 'jo2')).toBe('jo2');
  });

  it('prefills nothing when nothing usable is left: no name, no usable email, a guest-shaped handle', () => {
    expect(handlePrefill(person('kz8f3q2m@privaterelay.appleid.com'), 'guest-ab12cd34')).toBe('');
    expect(handlePrefill(person(undefined), 'guest-ab12cd34')).toBe('');
  });
});
