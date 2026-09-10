import { renderHook, waitFor, act } from '@testing-library/react';
import { useUserPreferences } from './useUserPreferences';

const { single, upsert, testUser } = vi.hoisted(() => ({
  single: vi.fn(() => Promise.resolve({ data: { hide_add_section: false, reminder_emails: false }, error: null })),
  upsert: vi.fn(() => Promise.resolve({ error: null })),
  // Stable reference: useAuth() in real usage returns the same user object across
  // re-renders. useUserPreferences' effect depends on [user], so a mock that hands
  // back a fresh object literal per call would refire the effect on every render
  // (including the one caused by updateReminderEmails' own setState) and clobber
  // the just-written value with the original fetched data.
  testUser: { id: 'u1' },
}));

vi.mock('@/integrations/supabase/client', () => ({
  supabase: { from: () => ({ select: () => ({ eq: () => ({ single }) }), upsert }) },
}));
vi.mock('@/hooks/useAuth', () => ({ useAuth: () => ({ user: testUser }) }));
vi.mock('@/hooks/use-toast', () => ({ useToast: () => ({ toast: vi.fn() }) }));

describe('useUserPreferences reminder emails', () => {
  it('reads reminder_emails and writes it back through upsert', async () => {
    const { result } = renderHook(() => useUserPreferences());
    await waitFor(() => expect(result.current.loading).toBe(false));
    expect(result.current.reminderEmails).toBe(false);
    await act(() => result.current.updateReminderEmails(true));
    expect(upsert).toHaveBeenCalledWith(
      expect.objectContaining({ user_id: 'u1', reminder_emails: true }),
      { onConflict: 'user_id' },
    );
    expect(result.current.reminderEmails).toBe(true);
  });
});
