import { renderHook, waitFor } from '@testing-library/react';
import { useIsAdmin } from './useIsAdmin';

const { authState, maybeSingleMock, fromMock } = vi.hoisted(() => {
  const maybeSingle = vi.fn();
  const eq = vi.fn(() => ({ maybeSingle }));
  const select = vi.fn(() => ({ eq }));
  const from = vi.fn(() => ({ select }));
  return {
    authState: { user: null as null | { id: string }, loading: false },
    maybeSingleMock: maybeSingle,
    fromMock: from,
  };
});

vi.mock('@/hooks/useAuth', () => ({ useAuth: () => authState }));
vi.mock('@/integrations/supabase/client', () => ({ supabase: { from: fromMock } }));

describe('useIsAdmin', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    authState.user = null;
    authState.loading = false;
  });

  it('is false without a signed-in user and never queries', async () => {
    const { result } = renderHook(() => useIsAdmin());
    await waitFor(() => expect(result.current.loading).toBe(false));
    expect(result.current.isAdmin).toBe(false);
    expect(fromMock).not.toHaveBeenCalled();
  });

  it('is true when the user has an admin_users row', async () => {
    authState.user = { id: 'u1' };
    maybeSingleMock.mockResolvedValue({ data: { user_id: 'u1' }, error: null });
    const { result } = renderHook(() => useIsAdmin());
    await waitFor(() => expect(result.current.loading).toBe(false));
    expect(result.current.isAdmin).toBe(true);
    expect(fromMock).toHaveBeenCalledWith('admin_users');
  });

  it('is false when there is no row or the query fails', async () => {
    authState.user = { id: 'u1' };
    maybeSingleMock.mockResolvedValue({ data: null, error: { message: 'nope' } });
    const { result } = renderHook(() => useIsAdmin());
    await waitFor(() => expect(result.current.loading).toBe(false));
    expect(result.current.isAdmin).toBe(false);
  });

  it('stays loading while auth itself is still resolving', () => {
    authState.loading = true;
    const { result } = renderHook(() => useIsAdmin());
    expect(result.current.loading).toBe(true);
    expect(fromMock).not.toHaveBeenCalled();
  });
});
