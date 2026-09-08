import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import DeleteAccountSection from './DeleteAccountSection';

const { mockInvoke, mockSignOut, mockNavigate, mockToast } = vi.hoisted(() => ({
  mockInvoke: vi.fn(),
  mockSignOut: vi.fn(() => Promise.resolve()),
  mockNavigate: vi.fn(),
  mockToast: vi.fn(),
}));

vi.mock('@/integrations/supabase/client', () => ({
  supabase: { functions: { invoke: mockInvoke } },
}));

vi.mock('@/hooks/useAuth', () => ({
  useAuth: () => ({ signOut: mockSignOut, user: { id: 'u1', email: 'will@example.com' } }),
}));

vi.mock('@/hooks/use-toast', () => ({ useToast: () => ({ toast: mockToast }) }));

vi.mock('react-router-dom', async () => {
  const actual = await vi.importActual<typeof import('react-router-dom')>('react-router-dom');
  return { ...actual, useNavigate: () => mockNavigate };
});

const renderSection = () =>
  render(
    <MemoryRouter>
      <DeleteAccountSection />
    </MemoryRouter>,
  );

const openDialog = () => fireEvent.click(screen.getByRole('button', { name: /delete my account/i }));
const confirmButton = () => screen.getByRole('button', { name: /delete everything/i });
const typeConfirmation = (value: string) =>
  fireEvent.change(screen.getByLabelText(/type delete to confirm/i), { target: { value } });

describe('DeleteAccountSection', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockInvoke.mockResolvedValue({ data: { deleted: true }, error: null });
  });

  it('keeps the destructive action disabled until DELETE is typed exactly', async () => {
    renderSection();
    openDialog();
    expect(await screen.findByRole('alertdialog')).toBeTruthy();
    expect((confirmButton() as HTMLButtonElement).disabled).toBe(true);
    typeConfirmation('delete');
    expect((confirmButton() as HTMLButtonElement).disabled).toBe(true);
    typeConfirmation('DELETE');
    expect((confirmButton() as HTMLButtonElement).disabled).toBe(false);
    expect(mockInvoke).not.toHaveBeenCalled();
  });

  it('calls delete-account, signs out locally, and lands on the homepage', async () => {
    renderSection();
    openDialog();
    await screen.findByRole('alertdialog');
    typeConfirmation('DELETE');
    fireEvent.click(confirmButton());

    await waitFor(() => expect(mockInvoke).toHaveBeenCalledWith('delete-account', expect.objectContaining({ method: 'POST' })));
    await waitFor(() => expect(mockSignOut).toHaveBeenCalledTimes(1));
    await waitFor(() => expect(mockNavigate).toHaveBeenCalledWith('/'));
    expect(mockToast.mock.calls[0][0].title).toMatch(/account has been deleted/i);
  });

  it('keeps the account and explains when the server refuses', async () => {
    mockInvoke.mockResolvedValueOnce({ data: null, error: { message: 'Edge Function returned a non-2xx status code' } });
    renderSection();
    openDialog();
    await screen.findByRole('alertdialog');
    typeConfirmation('DELETE');
    fireEvent.click(confirmButton());

    await waitFor(() => expect(mockToast).toHaveBeenCalledTimes(1));
    expect(mockToast.mock.calls[0][0].variant).toBe('destructive');
    expect(mockSignOut).not.toHaveBeenCalled();
    expect(mockNavigate).not.toHaveBeenCalled();
  });
});
