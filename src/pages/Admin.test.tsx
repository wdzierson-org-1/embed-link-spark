import { fireEvent, render, screen, waitFor, within } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import Admin from './Admin';
import type { AdminUserRow } from '@/utils/adminStats';

const { navigateMock, fetchAdminUsersMock, authState, adminState } = vi.hoisted(() => ({
  navigateMock: vi.fn(),
  fetchAdminUsersMock: vi.fn(),
  authState: {
    user: { id: 'me', email: 'will@dzierson.com' } as null | { id: string; email: string },
    loading: false,
  },
  adminState: { isAdmin: true, loading: false },
}));

vi.mock('react-router-dom', async (importOriginal) => ({
  ...(await importOriginal<typeof import('react-router-dom')>()),
  useNavigate: () => navigateMock,
}));
vi.mock('@/hooks/useAuth', () => ({ useAuth: () => authState }));
vi.mock('@/hooks/useIsAdmin', () => ({ useIsAdmin: () => adminState }));
vi.mock('@/utils/adminApi', () => ({ fetchAdminUsers: fetchAdminUsersMock }));
vi.mock('@/components/HeaderSection', () => ({ default: () => null }));

// The page reads the wall clock, so "active this week" fixtures are relative
const yesterday = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();

const row = (over: Partial<AdminUserRow>): AdminUserRow => ({
  user_id: 'u',
  email: 'a@example.com',
  username: 'a',
  display_name: null,
  is_anonymous: false,
  created_at: '2026-08-01T00:00:00Z',
  last_sign_in_at: yesterday,
  total_logins: 1,
  active_days: 1,
  last_active_at: yesterday,
  item_count: 0,
  items_last_7d: 0,
  last_item_at: null,
  items_by_type: {},
  ...over,
});

const rows = [
  row({
    user_id: 'r1',
    email: 'rachel@gmail.com',
    username: 'rachel',
    display_name: 'Rachel',
    total_logins: 4,
    item_count: 29,
    items_last_7d: 2,
    items_by_type: { link: 20, image: 9 },
  }),
  row({ user_id: 's1', email: 'susan@gmail.com', username: 'susan', total_logins: 9, item_count: 40 }),
  row({ user_id: 't1', email: 'will+uitest@dzierson.com', username: 'uitest', total_logins: 100, item_count: 1 }),
  row({ user_id: 'anon', email: null, username: null, is_anonymous: true, item_count: 1, items_last_7d: 1 }),
];

const renderPage = () =>
  render(
    <MemoryRouter>
      <Admin />
    </MemoryRouter>
  );

const dataRows = () => within(screen.getByRole('table')).getAllByRole('row').slice(1);

describe('Admin members page', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    adminState.isAdmin = true;
    adminState.loading = false;
    fetchAdminUsersMock.mockResolvedValue(rows);
  });

  it('sends non-admins home without loading anything', async () => {
    adminState.isAdmin = false;
    renderPage();
    await waitFor(() => expect(navigateMock).toHaveBeenCalledWith('/home'));
    expect(fetchAdminUsersMock).not.toHaveBeenCalled();
  });

  it('lists members with links to their library, hiding test accounts and anonymous sessions', async () => {
    renderPage();
    expect(await screen.findByRole('link', { name: 'Rachel' })).toHaveAttribute('href', '/admin/users/r1');
    expect(screen.getByRole('link', { name: 'rachel@gmail.com' })).toHaveAttribute('href', '/admin/users/r1');
    expect(screen.queryByText('will+uitest@dzierson.com')).not.toBeInTheDocument();
    expect(screen.queryByText('Anonymous')).not.toBeInTheDocument();
    expect(screen.getByText('20 links, 9 images')).toBeInTheDocument();
  });

  it('summarises members, weekly actives and items for the accounts on show', async () => {
    renderPage();
    await screen.findByRole('link', { name: 'Rachel' });
    expect(screen.getByTestId('tile-members-value')).toHaveTextContent(/^2$/);
    expect(screen.getByTestId('tile-active-value')).toHaveTextContent(/^2$/);
    expect(screen.getByTestId('tile-items-value')).toHaveTextContent(/^70$/);
    expect(screen.getByTestId('tile-items-week-value')).toHaveTextContent(/^3$/);
    expect(screen.getByText(/1 anonymous/i)).toBeInTheDocument();
  });

  it('reveals test accounts on request and counts them in', async () => {
    renderPage();
    await screen.findByRole('link', { name: 'Rachel' });
    fireEvent.click(screen.getByRole('checkbox', { name: /hide test accounts/i }));
    expect(screen.getByRole('link', { name: 'will+uitest@dzierson.com' })).toBeInTheDocument();
    expect(screen.getByTestId('tile-members-value')).toHaveTextContent(/^3$/);
  });

  it('sorts by a column when its header is clicked, and flips on a second click', async () => {
    renderPage();
    await screen.findByRole('link', { name: 'Rachel' });
    fireEvent.click(screen.getByRole('button', { name: /logins/i }));
    expect(dataRows()[0]).toHaveTextContent('susan');
    fireEvent.click(screen.getByRole('button', { name: /logins/i }));
    expect(dataRows()[0]).toHaveTextContent('Rachel');
  });

  it('filters by name or email as you type', async () => {
    renderPage();
    await screen.findByRole('link', { name: 'Rachel' });
    fireEvent.change(screen.getByRole('searchbox', { name: /search members/i }), { target: { value: 'sus' } });
    expect(dataRows()).toHaveLength(1);
    expect(dataRows()[0]).toHaveTextContent('susan');
  });

  it('shows the server refusal instead of an empty table', async () => {
    fetchAdminUsersMock.mockRejectedValue(new Error('Not an admin'));
    renderPage();
    expect(await screen.findByText('Not an admin')).toBeInTheDocument();
    expect(screen.queryByRole('table')).not.toBeInTheDocument();
  });
});
