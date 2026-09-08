import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import ResetPassword from './ResetPassword';

const { mockGetSession, mockUpdateUser, mockNavigate, mockToast } = vi.hoisted(() => ({
  mockGetSession: vi.fn(),
  mockUpdateUser: vi.fn(() => Promise.resolve({ data: { user: { id: 'u1' } }, error: null })),
  mockNavigate: vi.fn(),
  mockToast: vi.fn(),
}));

vi.mock('@/integrations/supabase/client', () => ({
  supabase: {
    auth: {
      getSession: mockGetSession,
      updateUser: mockUpdateUser,
      onAuthStateChange: () => ({ data: { subscription: { unsubscribe: vi.fn() } } }),
    },
  },
}));

vi.mock('@/hooks/use-toast', () => ({ useToast: () => ({ toast: mockToast }) }));

vi.mock('react-router-dom', async () => {
  const actual = await vi.importActual<typeof import('react-router-dom')>('react-router-dom');
  return { ...actual, useNavigate: () => mockNavigate };
});

const withSession = () =>
  mockGetSession.mockResolvedValue({ data: { session: { user: { id: 'u1' } } }, error: null });
const withoutSession = () => mockGetSession.mockResolvedValue({ data: { session: null }, error: null });

const renderPage = () =>
  render(
    <MemoryRouter>
      <ResetPassword expiryGraceMs={0} />
    </MemoryRouter>,
  );

const fill = (password: string, confirm: string) => {
  fireEvent.change(screen.getByPlaceholderText('New password'), { target: { value: password } });
  fireEvent.change(screen.getByPlaceholderText('Confirm new password'), { target: { value: confirm } });
  fireEvent.click(screen.getByRole('button', { name: /update password/i }));
};

describe('ResetPassword', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    window.location.hash = '';
  });

  it('shows the new-password form once the recovery session is present', async () => {
    withSession();
    renderPage();
    expect(await screen.findByRole('button', { name: /update password/i })).toBeTruthy();
  });

  it('rejects mismatched passwords without calling the API', async () => {
    withSession();
    renderPage();
    await screen.findByRole('button', { name: /update password/i });
    fill('hunter2hunter2', 'different1');
    expect(await screen.findByText(/don't match/i)).toBeTruthy();
    expect(mockUpdateUser).not.toHaveBeenCalled();
  });

  it('rejects passwords under 8 characters', async () => {
    withSession();
    renderPage();
    await screen.findByRole('button', { name: /update password/i });
    fill('short', 'short');
    expect(await screen.findByText(/at least 8 characters/i)).toBeTruthy();
    expect(mockUpdateUser).not.toHaveBeenCalled();
  });

  it('updates the password and sends the user home', async () => {
    withSession();
    renderPage();
    await screen.findByRole('button', { name: /update password/i });
    fill('hunter2hunter2', 'hunter2hunter2');
    await waitFor(() => expect(mockUpdateUser).toHaveBeenCalledWith({ password: 'hunter2hunter2' }));
    await waitFor(() => expect(mockNavigate).toHaveBeenCalledWith('/home'));
    expect(mockToast.mock.calls[0][0].title).toMatch(/password updated/i);
  });

  it('surfaces an API error and stays on the form', async () => {
    withSession();
    mockUpdateUser.mockResolvedValueOnce({
      data: { user: null },
      error: { message: 'New password should be different from the old password.' },
    } as never);
    renderPage();
    await screen.findByRole('button', { name: /update password/i });
    fill('hunter2hunter2', 'hunter2hunter2');
    await waitFor(() => expect(mockToast).toHaveBeenCalledTimes(1));
    expect(mockToast.mock.calls[0][0].variant).toBe('destructive');
    expect(mockNavigate).not.toHaveBeenCalled();
  });

  it('offers a new link when there is no recovery session', async () => {
    withoutSession();
    renderPage();
    expect(await screen.findByText(/expired/i)).toBeTruthy();
    const link = screen.getByRole('link', { name: /request a new link/i });
    expect(link.getAttribute('href')).toBe('/auth?mode=reset');
  });

  it('reads an expired-link error from the URL hash even with a session', async () => {
    withSession();
    window.location.hash =
      '#error=access_denied&error_code=otp_expired&error_description=Email+link+is+invalid+or+has+expired';
    renderPage();
    expect(await screen.findByText(/expired/i)).toBeTruthy();
    expect(screen.queryByRole('button', { name: /update password/i })).toBeNull();
  });
});
