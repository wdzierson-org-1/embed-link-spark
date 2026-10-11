// src/components/auth/appleName.test.ts
import { writeAppleName } from './appleName';

const db = vi.hoisted(() => ({
  profile: { username: 'stash3', display_name: 'stash3' } as Record<string, unknown> | null,
  updateUser: vi.fn(async () => ({ data: {}, error: null })),
  profileUpdate: null as null | Record<string, unknown>,
}));
vi.mock('@/integrations/supabase/client', () => ({
  supabase: {
    auth: { updateUser: db.updateUser },
    from: () => ({
      select: () => ({ eq: () => ({ maybeSingle: async () => ({ data: db.profile, error: null }) }) }),
      update: (row: Record<string, unknown>) => { db.profileUpdate = row; return { eq: async () => ({ error: null }) }; },
    }),
  },
}));

const user = { id: 'u1', email: 'kz8f3q2m@privaterelay.appleid.com' } as never;

describe('appleName', () => {
  beforeEach(() => { db.profileUpdate = null; db.updateUser.mockClear(); });

  it('writes the name to the user metadata and replaces a fallback display name', async () => {
    await writeAppleName(user, { firstName: 'Will', lastName: 'Dzierson' });
    expect(db.updateUser).toHaveBeenCalledWith({ data: { full_name: 'Will Dzierson', given_name: 'Will', family_name: 'Dzierson' } });
    expect(db.profileUpdate).toEqual({ display_name: 'Will Dzierson', first_name: 'Will', last_name: 'Dzierson' });
  });

  it('never overwrites a chosen display name, and does nothing without a name', async () => {
    db.profile = { username: 'stash3', display_name: 'Chosen Name' };
    await writeAppleName(user, { firstName: 'Will' });
    expect(db.profileUpdate).toBeNull();
    await writeAppleName(user, {});
    expect(db.updateUser).toHaveBeenCalledTimes(1);
  });
});
