import { describeInvokeError, fetchAdminLibrary, fetchAdminUsers } from './adminApi';

const { invokeMock } = vi.hoisted(() => ({ invokeMock: vi.fn() }));

vi.mock('@/integrations/supabase/client', () => ({
  supabase: { functions: { invoke: invokeMock } },
}));

describe('adminApi', () => {
  beforeEach(() => vi.clearAllMocks());

  it('asks admin-stats for the member list', async () => {
    invokeMock.mockResolvedValue({ data: { users: [{ user_id: 'u1' }] }, error: null });
    await expect(fetchAdminUsers()).resolves.toEqual([{ user_id: 'u1' }]);
    expect(invokeMock).toHaveBeenCalledWith('admin-stats', { body: { action: 'users' } });
  });

  it('asks admin-stats for one member library', async () => {
    invokeMock.mockResolvedValue({ data: { user: { user_id: 'u1' }, items: [] }, error: null });
    await expect(fetchAdminLibrary('u1')).resolves.toEqual({ user: { user_id: 'u1' }, items: [] });
    expect(invokeMock).toHaveBeenCalledWith('admin-stats', { body: { action: 'items', user_id: 'u1' } });
  });

  it('surfaces the server error text when the function refuses', async () => {
    invokeMock.mockResolvedValue({
      data: null,
      error: {
        message: 'Edge Function returned a non-2xx status code',
        context: { json: async () => ({ error: 'Not an admin' }) },
      },
    });
    await expect(fetchAdminUsers()).rejects.toThrow('Not an admin');
  });

  it('falls back to the client message without a response body', async () => {
    await expect(describeInvokeError({ message: 'Failed to send a request' })).resolves.toBe(
      'Failed to send a request'
    );
  });
});
