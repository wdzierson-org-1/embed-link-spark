import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import Auth from './Auth';

const { mockReset, mockToast } = vi.hoisted(() => ({
  mockReset: vi.fn(() => Promise.resolve({ data: {}, error: null })),
  mockToast: vi.fn(),
}));

vi.mock('@/integrations/supabase/client', () => ({
  supabase: {
    auth: { resetPasswordForEmail: mockReset },
    // username / phone uniqueness probes — never hit in these tests
    from: () => ({
      select: () => ({
        eq: () => ({ single: () => Promise.resolve({ data: null, error: { code: 'PGRST116' } }) }),
      }),
    }),
  },
}));

vi.mock('@/hooks/useAuth', () => ({
  useAuth: () => ({ signIn: vi.fn(), signUp: vi.fn(), user: null }),
}));

vi.mock('@/hooks/usePhoneNumber', () => ({
  usePhoneNumber: () => ({ registerPhoneNumber: vi.fn() }),
}));

vi.mock('@/hooks/use-toast', () => ({
  useToast: () => ({ toast: mockToast }),
}));

const renderAuth = (path = '/auth') =>
  render(
    <MemoryRouter initialEntries={[path]}>
      <Auth />
    </MemoryRouter>,
  );

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
    fireEvent.change(screen.getByPlaceholderText('Email'), { target: { value: 'will@example.com' } });
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
    fireEvent.change(screen.getByPlaceholderText('Email'), { target: { value: 'will@example.com' } });
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
