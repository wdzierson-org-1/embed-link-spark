import { render, screen, waitFor, act } from '@testing-library/react';
import { AuthProvider, useAuth } from './useAuth';

const state = vi.hoisted(() => ({
  profileRows: [] as Array<Record<string, unknown> | null>, // consumed in order by maybeSingle
  session: null as null | { user: { id: string; email: string; is_anonymous?: boolean }; access_token: string },
  signInWithIdToken: vi.fn(async () => ({ data: {}, error: null })),
}));

vi.mock('@/integrations/supabase/client', () => ({
  supabase: {
    auth: {
      onAuthStateChange: () => ({ data: { subscription: { unsubscribe: vi.fn() } } }),
      getSession: async () => ({ data: { session: state.session } }),
      signInWithIdToken: state.signInWithIdToken,
      signOut: vi.fn(),
    },
    from: () => ({
      select: () => ({
        eq: () => ({
          maybeSingle: async () => ({ data: state.profileRows.shift() ?? null, error: null }),
        }),
      }),
    }),
  },
}));

const Probe = () => {
  const { handle, loading, signInWithIdToken } = useAuth();
  return (
    <div>
      <span data-testid="loading">{String(loading)}</span>
      <span data-testid="handle">{handle ? `${handle.username}:${handle.confirmed}` : 'null'}</span>
      <button onClick={() => signInWithIdToken({ provider: 'google', token: 'tok', nonce: 'raw' })}>go</button>
    </div>
  );
};

const renderProbe = () => render(<AuthProvider><Probe /></AuthProvider>);

describe('useAuth — handle + id-token', () => {
  beforeEach(() => {
    vi.useFakeTimers({ shouldAdvanceTime: true });
    state.profileRows = [];
    state.session = { user: { id: 'u1', email: 'will@example.com' }, access_token: 't' };
    state.signInWithIdToken.mockClear();
  });
  afterEach(() => vi.useRealTimers());

  it('loads the handle for a real user', async () => {
    state.profileRows = [{ username: 'will', handle_confirmed: false }];
    renderProbe();
    await waitFor(() => expect(screen.getByTestId('handle')).toHaveTextContent('will:false'));
  });

  it('keeps the handle null for an anonymous session', async () => {
    state.session = { user: { id: 'anon', email: '', is_anonymous: true }, access_token: 't' };
    renderProbe();
    await waitFor(() => expect(screen.getByTestId('loading')).toHaveTextContent('false'));
    expect(screen.getByTestId('handle')).toHaveTextContent('null');
  });

  it('retries once, then fails open when the profile row is missing', async () => {
    state.profileRows = [null, null];
    renderProbe();
    await act(async () => { await vi.advanceTimersByTimeAsync(600); });
    await waitFor(() => expect(screen.getByTestId('handle')).toHaveTextContent(':true'));
  });

  it('passes the raw nonce and token through to Supabase', async () => {
    state.profileRows = [{ username: 'will', handle_confirmed: true }];
    renderProbe();
    await waitFor(() => expect(screen.getByTestId('handle')).toHaveTextContent('will:true'));
    screen.getByRole('button', { name: 'go' }).click();
    await waitFor(() => expect(state.signInWithIdToken).toHaveBeenCalledWith({ provider: 'google', token: 'tok', nonce: 'raw' }));
  });
});
