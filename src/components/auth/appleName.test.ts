// src/components/auth/appleName.test.ts
import type { MockInstance } from 'vitest';
import { writeAppleName } from './appleName';

const db = vi.hoisted(() => ({
  profile: { username: 'stash3', display_name: 'stash3' } as Record<string, unknown> | null,
  updateUser: vi.fn(async () => ({ data: {}, error: null as null | { message: string } })),
  profileUpdate: null as null | Record<string, unknown>,
  profileError: null as null | { message: string },
}));
vi.mock('@/integrations/supabase/client', () => ({
  supabase: {
    auth: { updateUser: db.updateUser },
    from: () => ({
      select: () => ({ eq: () => ({ maybeSingle: async () => ({ data: db.profile, error: null }) }) }),
      update: (row: Record<string, unknown>) => { db.profileUpdate = row; return { eq: async () => ({ error: db.profileError }) }; },
    }),
  },
}));

const user = { id: 'u1', email: 'kz8f3q2m@privaterelay.appleid.com' } as never;
let warn: MockInstance<typeof console.warn>;

describe('appleName', () => {
  beforeEach(() => {
    db.profile = { username: 'stash3', display_name: 'stash3' };
    db.profileUpdate = null;
    db.profileError = null;
    db.updateUser.mockClear();
    db.updateUser.mockResolvedValue({ data: {}, error: null });
    warn = vi.spyOn(console, 'warn').mockImplementation(() => {});
  });
  afterEach(() => warn.mockRestore());

  it('writes the name to the user metadata and replaces a fallback display name', async () => {
    await writeAppleName(user, { firstName: 'Will', lastName: 'Dzierson' });
    expect(db.updateUser).toHaveBeenCalledWith({ data: { full_name: 'Will Dzierson', given_name: 'Will', family_name: 'Dzierson' } });
    expect(db.profileUpdate).toEqual({ display_name: 'Will Dzierson', first_name: 'Will', last_name: 'Dzierson' });
    expect(warn).not.toHaveBeenCalled();
  });

  it('never overwrites a chosen display name, and does nothing without a name', async () => {
    db.profile = { username: 'stash3', display_name: 'Chosen Name' };
    await writeAppleName(user, { firstName: 'Will' });
    expect(db.profileUpdate).toBeNull();
    await writeAppleName(user, {});
    expect(db.updateUser).toHaveBeenCalledTimes(1);
  });

  it('warns when the metadata write is refused, and still writes the profile', async () => {
    db.updateUser.mockResolvedValueOnce({ data: {}, error: { message: 'session expired' } });
    await writeAppleName(user, { firstName: 'Will', lastName: 'Dzierson' });
    expect(warn).toHaveBeenCalledWith('[auth] apple name write failed:', 'session expired');
    expect(db.profileUpdate).toEqual({ display_name: 'Will Dzierson', first_name: 'Will', last_name: 'Dzierson' });
  });

  it('warns when the profile write is refused', async () => {
    db.profileError = { message: 'permission denied for table user_profiles' };
    await writeAppleName(user, { firstName: 'Will', lastName: 'Dzierson' });
    expect(db.updateUser).toHaveBeenCalledTimes(1); // the metadata write went first and stands
    expect(warn).toHaveBeenCalledWith('[auth] apple name write failed:', 'permission denied for table user_profiles');
  });
});
