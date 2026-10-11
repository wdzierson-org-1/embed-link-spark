import { render, screen, waitFor, act } from '@testing-library/react';
import { AuthProvider, useAuth } from './useAuth';

const state = vi.hoisted(() => ({
  profileRows: [] as Array<Record<string, unknown> | null>, // consumed in order by maybeSingle
  lookups: 0, // how many times the profile row has been asked for
  renders: [] as string[], // every handle value the probe rendered, in order
  session: null as null | { user: { id: string; email: string; is_anonymous?: boolean }; access_token: string },
  authChanged: null as null | ((event: string, session: unknown) => void), // what the provider gave onAuthStateChange
  signInWithIdToken: vi.fn(async () => ({ data: {}, error: null })),
}));

vi.mock('@/integrations/supabase/client', () => ({
  supabase: {
    auth: {
      onAuthStateChange: (callback: (event: string, session: unknown) => void) => {
        state.authChanged = callback;
        return { data: { subscription: { unsubscribe: vi.fn() } } };
      },
      getSession: async () => ({ data: { session: state.session } }),
      signInWithIdToken: state.signInWithIdToken,
      signOut: vi.fn(),
    },
    from: () => ({
      select: () => ({
        eq: () => ({
          maybeSingle: async () => {
            state.lookups += 1;
            return { data: state.profileRows.shift() ?? null, error: null };
          },
        }),
      }),
    }),
  },
}));

const Probe = () => {
  const { handle, loading, signInWithIdToken, refreshHandle } = useAuth();
  const shown = handle ? `${handle.username}:${handle.confirmed}` : 'null';
  state.renders.push(shown);
  return (
    <div>
      <span data-testid="loading">{String(loading)}</span>
      <span data-testid="handle">{shown}</span>
      <button onClick={() => signInWithIdToken({ provider: 'google', token: 'tok', nonce: 'raw' })}>go</button>
      <button onClick={() => refreshHandle()}>refresh</button>
    </div>
  );
};

const renderProbe = () => render(<AuthProvider><Probe /></AuthProvider>);

// What supabase-js does when the session changes: call the listener the provider registered
const emitAuthChange = (event: string, session: unknown) => {
  if (!state.authChanged) throw new Error('the provider has not subscribed to auth changes');
  state.authChanged(event, session);
};

describe('useAuth — handle + id-token', () => {
  beforeEach(() => {
    vi.useFakeTimers({ shouldAdvanceTime: true });
    state.profileRows = [];
    state.lookups = 0;
    state.renders = [];
    state.authChanged = null;
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

  it('retries once and only then fails open', async () => {
    state.profileRows = [null, null];
    renderProbe();
    await waitFor(() => expect(state.lookups).toBe(1)); // missed once; the 500 ms retry is pending
    expect(screen.getByTestId('handle')).toHaveTextContent(/^null$/); // still unknown, not failed open yet
    await act(async () => { await vi.advanceTimersByTimeAsync(500); });
    await waitFor(() => expect(screen.getByTestId('handle')).toHaveTextContent(':true'));
    expect(state.lookups).toBe(2); // one look, one retry, no third
  });

  it('ignores a re-emitted session for the same user', async () => {
    state.profileRows = [{ username: 'will', handle_confirmed: false }];
    renderProbe();
    await waitFor(() => expect(screen.getByTestId('handle')).toHaveTextContent('will:false'));
    const rendersBefore = state.renders.length;
    // supabase-js re-emits SIGNED_IN with a freshly parsed session on every tab refocus
    await act(async () => {
      emitAuthChange('SIGNED_IN', { user: { id: 'u1', email: 'will@example.com' }, access_token: 't2' });
    });
    await act(async () => { await vi.advanceTimersByTimeAsync(600); });
    expect(state.lookups).toBe(1); // the person did not change, so nothing is asked again
    expect(state.renders.slice(rendersBefore)).not.toContain('null'); // and the handle never blinks out
    expect(screen.getByTestId('handle')).toHaveTextContent('will:false');
  });

  it('drops a lookup whose user signed out meanwhile', async () => {
    state.profileRows = [null, { username: 'will', handle_confirmed: false }];
    renderProbe();
    await waitFor(() => expect(state.lookups).toBe(1)); // missed once; the 500 ms retry is pending
    state.session = null;
    await act(async () => { emitAuthChange('SIGNED_OUT', null); });
    await act(async () => { await vi.advanceTimersByTimeAsync(600); }); // the abandoned retry fires and finds a row
    expect(screen.getByTestId('handle')).toHaveTextContent(/^null$/);
    expect(state.renders).not.toContain('will:false');
  });

  it("shows the new person's handle, never the previous one's, when the account switches mid-lookup", async () => {
    // asked in this order: u1 misses, u2 finds bob, then u1's abandoned retry finds will
    state.profileRows = [
      null,
      { username: 'bob', handle_confirmed: false },
      { username: 'will', handle_confirmed: false },
    ];
    renderProbe();
    await waitFor(() => expect(state.lookups).toBe(1)); // u1 missed once; its 500 ms retry is pending
    state.session = { user: { id: 'u2', email: 'bob@example.com' }, access_token: 't2' };
    await act(async () => { emitAuthChange('SIGNED_IN', state.session); });
    await waitFor(() => expect(screen.getByTestId('handle')).toHaveTextContent('bob:false'));
    await act(async () => { await vi.advanceTimersByTimeAsync(600); }); // u1's abandoned retry fires and finds a row
    expect(screen.getByTestId('handle')).toHaveTextContent('bob:false');
    expect(state.renders).not.toContain('will:false');
  });

  it('refreshHandle re-reads the row for the current user', async () => {
    state.profileRows = [
      { username: 'will', handle_confirmed: false },
      { username: 'will', handle_confirmed: true }, // what the row says once the confirm step has written it
    ];
    renderProbe();
    await waitFor(() => expect(screen.getByTestId('handle')).toHaveTextContent('will:false'));
    screen.getByRole('button', { name: 'refresh' }).click();
    await waitFor(() => expect(screen.getByTestId('handle')).toHaveTextContent('will:true'));
    expect(state.lookups).toBe(2);
  });
});
