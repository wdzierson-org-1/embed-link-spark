import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import { MemoryRouter, Route, Routes } from 'react-router-dom';
import AdminUser from './AdminUser';

const { navigateMock, fetchAdminLibraryMock, authState, adminState, gridProps } = vi.hoisted(() => ({
  navigateMock: vi.fn(),
  fetchAdminLibraryMock: vi.fn(),
  authState: {
    user: { id: 'me', email: 'will@dzierson.com' } as null | { id: string; email: string },
    loading: false,
  },
  adminState: { isAdmin: true, loading: false },
  gridProps: { current: null as null | Record<string, unknown> },
}));

vi.mock('react-router-dom', async (importOriginal) => ({
  ...(await importOriginal<typeof import('react-router-dom')>()),
  useNavigate: () => navigateMock,
}));
vi.mock('@/hooks/useAuth', () => ({ useAuth: () => authState }));
vi.mock('@/hooks/useIsAdmin', () => ({ useIsAdmin: () => adminState }));
vi.mock('@/utils/adminApi', () => ({ fetchAdminLibrary: fetchAdminLibraryMock }));
vi.mock('@/components/HeaderSection', () => ({ default: () => null }));
// The real grid drags in every card dependency; capture what it is handed
vi.mock('@/components/ContentGrid', () => ({
  default: (props: { items: { id: string; title: string }[] }) => {
    gridProps.current = props;
    return (
      <div data-testid="grid">
        {props.items.map((item) => (
          <span key={item.id}>{item.title}</span>
        ))}
      </div>
    );
  },
}));

const library = {
  user: {
    user_id: 'r1',
    email: 'rachel@gmail.com',
    username: 'rachel',
    display_name: 'Rachel',
    created_at: '2026-08-15T00:00:00Z',
  },
  items: [
    { id: 'i1', type: 'link', title: 'Alpha link', created_at: '2026-09-01T00:00:00Z', user_id: 'r1' },
    { id: 'i2', type: 'link', title: 'Bravo link', created_at: '2026-09-02T00:00:00Z', user_id: 'r1' },
    { id: 'i3', type: 'text', title: 'Charlie note', created_at: '2026-09-03T00:00:00Z', user_id: 'r1' },
  ],
};

const renderPage = () =>
  render(
    <MemoryRouter initialEntries={['/admin/users/r1']}>
      <Routes>
        <Route path="/admin/users/:userId" element={<AdminUser />} />
      </Routes>
    </MemoryRouter>
  );

describe('Admin member library page', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    gridProps.current = null;
    adminState.isAdmin = true;
    adminState.loading = false;
    fetchAdminLibraryMock.mockResolvedValue(library);
  });

  it('sends non-admins home without loading anything', async () => {
    adminState.isAdmin = false;
    renderPage();
    await waitFor(() => expect(navigateMock).toHaveBeenCalledWith('/home'));
    expect(fetchAdminLibraryMock).not.toHaveBeenCalled();
  });

  it('loads the member from the route and shows who they are', async () => {
    renderPage();
    expect(await screen.findByRole('heading', { name: 'Rachel' })).toBeInTheDocument();
    expect(fetchAdminLibraryMock).toHaveBeenCalledWith('r1');
    expect(screen.getByText('rachel@gmail.com')).toBeInTheDocument();
    expect(screen.getByText('3 items')).toBeInTheDocument();
    expect(screen.getByText('2 links')).toBeInTheDocument();
    expect(screen.getByText('1 note')).toBeInTheDocument();
    expect(screen.getByRole('link', { name: /members/i })).toHaveAttribute('href', '/admin');
  });

  it('recreates the grid read-only: public view, no owner callbacks', async () => {
    renderPage();
    await screen.findByText('Alpha link');
    expect(gridProps.current?.isPublicView).toBe(true);
    expect(gridProps.current?.onCommentClick).toBeUndefined();
    expect(gridProps.current?.onTogglePrivacy).toBeUndefined();
    expect(gridProps.current?.currentUserId).toBeUndefined();
  });

  it('narrows the grid by type and by search', async () => {
    renderPage();
    await screen.findByText('Alpha link');
    fireEvent.click(screen.getByRole('button', { name: 'Links' }));
    expect(gridProps.current?.typeFilter).toBe('link');
    fireEvent.click(screen.getByRole('button', { name: 'All' }));
    expect(gridProps.current?.typeFilter).toBe('all');
    fireEvent.change(screen.getByRole('searchbox', { name: /search this library/i }), {
      target: { value: 'charlie' },
    });
    expect(gridProps.current?.searchQuery).toBe('charlie');
  });

  it('shows the server refusal instead of an empty grid', async () => {
    fetchAdminLibraryMock.mockRejectedValue(new Error('No such user'));
    renderPage();
    expect(await screen.findByText('No such user')).toBeInTheDocument();
    expect(screen.queryByTestId('grid')).not.toBeInTheDocument();
  });
});
