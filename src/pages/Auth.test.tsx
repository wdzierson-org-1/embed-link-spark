import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { MemoryRouter, Route, Routes } from 'react-router-dom';
import Auth from './Auth';
import { writeAppleName } from '@/components/auth/appleName';

const { mockReset, mockToast, mockInvoke } = vi.hoisted(() => ({
  mockReset: vi.fn(() => Promise.resolve({ data: {}, error: null })),
  mockToast: vi.fn(),
  mockInvoke: vi.fn(async () => ({ data: { stored: true }, error: null })),
}));

const auth = vi.hoisted(() => ({
  user: null as null | { id: string; email: string; is_anonymous?: boolean; user_metadata?: Record<string, unknown> },
  handle: null as null | { username: string; confirmed: boolean },
  signIn: vi.fn(async () => ({ error: null as null | { message: string } })),
  signUp: vi.fn(async () => ({ error: null })),
  signInWithIdToken: vi.fn(async () => ({ error: null as null | { message: string } })),
  refreshHandle: vi.fn(async () => {}),
}));

vi.mock('@/integrations/supabase/client', () => ({
  supabase: {
    auth: { resetPasswordForEmail: mockReset, getSession: async () => ({ data: { session: { user: auth.user } } }) },
    functions: { invoke: mockInvoke },
    // username availability probe (isUsernameTaken → maybeSingle) — never hit in these tests
    from: () => ({
      select: () => ({
        eq: () => ({ maybeSingle: () => Promise.resolve({ data: null, error: null }) }),
      }),
    }),
  },
}));

vi.mock('@/hooks/useAuth', () => ({ useAuth: () => auth }));
vi.mock('@/components/auth/ProviderButtons', () => ({
  ProviderButtons: ({ onToken }: { onToken: (t: unknown) => void }) => (
    <>
      <button type="button" onClick={() => onToken({ provider: 'google', token: 'g.jwt', nonce: 'raw' })}>Continue with Google</button>
      <button
        type="button"
        onClick={() => onToken({ provider: 'apple', token: 'a.jwt', nonce: 'raw', appleCode: 'apple-code', appleName: { firstName: 'Will', lastName: 'Dzierson' } })}
      >
        Continue with Apple
      </button>
    </>
  ),
}));
vi.mock('@/components/auth/HandleStep', () => ({
  HandleStep: ({ onClaimed, initialUsername, serverUsername }: { onClaimed: () => void; initialUsername: string; serverUsername: string }) => (
    <button type="button" title={serverUsername} onClick={onClaimed}>Continue as {initialUsername}</button>
  ),
}));
vi.mock('@/components/auth/appleName', () => ({ writeAppleName: vi.fn(async () => {}) }));

vi.mock('@/hooks/usePhoneNumber', () => ({
  usePhoneNumber: () => ({ registerPhoneNumber: vi.fn() }),
}));

vi.mock('@/hooks/use-toast', () => ({
  useToast: () => ({ toast: mockToast }),
}));

const authRoutes = (path: string) => (
  <MemoryRouter initialEntries={[path]}>
    <Routes>
      <Route path="/auth" element={<Auth />} />
      <Route path="/home" element={<div>HOME PAGE</div>} />
      <Route path="/oauth/consent" element={<div>CONSENT PAGE</div>} />
    </Routes>
  </MemoryRouter>
);
const renderAuth = (path = '/auth') => render(authRoutes(path));

beforeEach(() => {
  vi.clearAllMocks();
  auth.user = null;
  auth.handle = null;
});

describe('Auth — forgot password', () => {
  beforeEach(() => vi.clearAllMocks());

  it('opens the reset form from the sign-in tab', () => {
    renderAuth();
    fireEvent.click(screen.getByRole('button', { name: /forgot password/i }));
    expect(screen.getByRole('button', { name: /send reset link/i })).toBeTruthy();
    // the tabs are gone while resetting
    expect(screen.queryByRole('tab', { name: /sign up/i })).toBeNull();
  });

  it('opens the reset form directly from ?mode=reset (extension + iOS deep link)', () => {
    renderAuth('/auth?mode=reset');
    expect(screen.getByRole('button', { name: /send reset link/i })).toBeTruthy();
  });

  it('sends the reset email with the app redirect and confirms without leaking existence', async () => {
    renderAuth('/auth?mode=reset');
    fireEvent.change(screen.getByLabelText('Email'), { target: { value: 'will@example.com' } });
    fireEvent.click(screen.getByRole('button', { name: /send reset link/i }));

    await waitFor(() => expect(mockReset).toHaveBeenCalledTimes(1));
    const [email, opts] = mockReset.mock.calls[0] as unknown as [string, { redirectTo: string }];
    expect(email).toBe('will@example.com');
    expect(opts.redirectTo).toMatch(/\/reset-password$/);

    expect(await screen.findByText(/check your email/i)).toBeTruthy();
    expect(screen.getByText(/if an account exists/i)).toBeTruthy();
  });

  it('explains a rate limit instead of confirming', async () => {
    mockReset.mockResolvedValueOnce({
      data: null,
      error: { message: 'For security purposes, you can only request this after 52 seconds.', status: 429 },
    } as never);
    renderAuth('/auth?mode=reset');
    fireEvent.change(screen.getByLabelText('Email'), { target: { value: 'will@example.com' } });
    fireEvent.click(screen.getByRole('button', { name: /send reset link/i }));

    await waitFor(() => expect(mockToast).toHaveBeenCalledTimes(1));
    expect(mockToast.mock.calls[0][0].title).toMatch(/wait a moment/i);
    expect(screen.queryByText(/check your email/i)).toBeNull();
  });

  it('returns to sign in from the reset form', () => {
    renderAuth('/auth?mode=reset');
    fireEvent.click(screen.getByRole('button', { name: /back to sign in/i }));
    expect(screen.getByRole('tab', { name: /sign in/i })).toBeTruthy();
  });
});

describe('Auth — credentials for password managers', () => {
  it('marks the email as the login on both forms, and keeps the @handle out of it', () => {
    renderAuth('/auth?mode=signup');
    expect(screen.getByLabelText('Email')).toHaveAttribute('autocomplete', 'username');
    expect(screen.getByLabelText('Password')).toHaveAttribute('autocomplete', 'new-password');
    expect(screen.getByLabelText('Username')).toHaveAttribute('autocomplete', 'off');
  });

  it('fills the sign-in email as the saved login', () => {
    renderAuth('/auth');
    expect(screen.getByLabelText('Email')).toHaveAttribute('autocomplete', 'username');
    expect(screen.getByLabelText('Password')).toHaveAttribute('autocomplete', 'current-password');
  });
});

describe('Auth — Google and Apple', () => {
  // The pair is the first thing in the open tab: the one Google button comes before the Email field
  const expectPairAboveTheForm = () => {
    const google = screen.getByRole('button', { name: /continue with google/i });
    expect(google.compareDocumentPosition(screen.getByLabelText('Email')) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy();
  };

  it('shows the provider pair above both forms with the footnote and the rule', () => {
    renderAuth();
    expectPairAboveTheForm();
    expect(screen.getByText('one account per email. sign in the same way each time.')).toBeInTheDocument();
    expect(screen.getByText('or with your email')).toBeInTheDocument();
    fireEvent.mouseDown(screen.getByRole('tab', { name: /sign up/i })); // Radix opens a tab on mousedown; a bare click leaves it shut
    expect(screen.getByLabelText('Username')).toBeInTheDocument(); // the sign-up form is the one showing
    expectPairAboveTheForm();
    expect(screen.getByText('or with your email')).toBeInTheDocument();
  });

  it('hands the token and the raw nonce to Supabase', async () => {
    renderAuth();
    fireEvent.click(screen.getByRole('button', { name: /continue with google/i }));
    await waitFor(() => expect(auth.signInWithIdToken).toHaveBeenCalledWith({ provider: 'google', token: 'g.jwt', nonce: 'raw' }));
  });

  it('surfaces a Supabase refusal and keeps the email form', async () => {
    auth.signInWithIdToken.mockResolvedValueOnce({ error: { message: 'Unsupported provider: provider is not enabled' } });
    renderAuth();
    fireEvent.click(screen.getByRole('button', { name: /continue with google/i }));
    await waitFor(() => expect(mockToast).toHaveBeenCalledWith(expect.objectContaining({ title: "Sign-in didn't complete.", description: 'Unsupported provider: provider is not enabled' })));
    expect(screen.getByLabelText('Email')).toBeInTheDocument();
  });

  it('says it is opening while the handle is unknown', () => {
    auth.user = { id: 'u1', email: 'will@example.com' };
    renderAuth();
    expect(screen.getByRole('status')).toHaveTextContent('opening…');
    expect(screen.queryByText('HOME PAGE')).toBeNull();
  });

  it('opens the handle step for an unconfirmed handle, then routes to returnTo after the claim', async () => {
    auth.user = { id: 'u1', email: 'will@example.com', user_metadata: { full_name: 'Will Dzierson' } };
    auth.handle = { username: 'stash3', confirmed: false };
    const view = renderAuth('/auth?returnTo=/oauth/consent');
    expect(screen.getByText('Claim your address.')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Continue as willdzierson' })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Continue as willdzierson' })).toHaveAttribute('title', 'stash3');
    fireEvent.click(screen.getByRole('button', { name: /continue as/i }));
    await waitFor(() => expect(auth.refreshHandle).toHaveBeenCalled());
    auth.handle = { username: 'willdzierson', confirmed: true };
    view.rerender(
      <MemoryRouter initialEntries={['/auth?returnTo=/oauth/consent']}>
        <Routes>
          <Route path="/auth" element={<Auth />} />
          <Route path="/oauth/consent" element={<div>CONSENT PAGE</div>} />
        </Routes>
      </MemoryRouter>,
    );
    expect(await screen.findByText('CONSENT PAGE')).toBeInTheDocument();
  });

  it('routes a confirmed person home at once, including from ?mode=handle', async () => {
    auth.user = { id: 'u1', email: 'will@example.com' };
    auth.handle = { username: 'will', confirmed: true };
    renderAuth('/auth?mode=handle');
    expect(await screen.findByText('HOME PAGE')).toBeInTheDocument();
  });

  it('adds the provider hint to a failed password sign-in', async () => {
    auth.signIn.mockResolvedValueOnce({ error: { message: 'Invalid login credentials' } });
    renderAuth();
    fireEvent.change(screen.getByLabelText('Email'), { target: { value: 'will@example.com' } });
    fireEvent.change(screen.getByLabelText('Password'), { target: { value: 'nope' } });
    fireEvent.click(screen.getByRole('button', { name: /^sign in$/i }));
    await waitFor(() => expect(mockToast).toHaveBeenCalled());
    const call = mockToast.mock.calls.at(-1)![0] as { description: unknown };
    expect(JSON.stringify(call.description)).toContain('Signed up with Google or Apple? Use that button.');
  });

  it('stops saying signing in once Supabase has answered, so the claim step is not announced as a sign-in', async () => {
    const view = renderAuth();
    fireEvent.click(screen.getByRole('button', { name: /continue with google/i }));
    await waitFor(() => expect(auth.signInWithIdToken).toHaveBeenCalled());
    // the session lands and the server has made this person's handle
    auth.user = { id: 'u1', email: 'will@example.com' };
    auth.handle = { username: 'stash3', confirmed: false };
    view.rerender(authRoutes('/auth'));
    expect(await screen.findByText('Claim your address.')).toBeInTheDocument();
    expect(screen.queryByRole('status')).toBeNull();
  });

  it('hands Apple’s name to the profile and its one-shot code to the server', async () => {
    auth.user = { id: 'u1', email: 'kz8f3q2m@privaterelay.appleid.com' };
    renderAuth();
    fireEvent.click(screen.getByRole('button', { name: /continue with apple/i }));
    await waitFor(() => expect(writeAppleName).toHaveBeenCalledWith(auth.user, { firstName: 'Will', lastName: 'Dzierson' }));
    expect(auth.signInWithIdToken).toHaveBeenCalledWith({ provider: 'apple', token: 'a.jwt', nonce: 'raw' });
    expect(mockInvoke).toHaveBeenCalledWith('apple-token-exchange', { body: { code: 'apple-code', client: 'web' } });
  });
});
