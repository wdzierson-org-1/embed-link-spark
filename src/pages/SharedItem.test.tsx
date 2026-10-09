import { fireEvent, render, screen } from '@testing-library/react';
import { MemoryRouter, Route, Routes } from 'react-router-dom';
import SharedItem from './SharedItem';

const rpc = vi.hoisted(() => vi.fn());
vi.mock('@/integrations/supabase/client', () => ({
  supabase: {
    rpc,
    storage: { from: () => ({ getPublicUrl: (path: string) => ({ data: { publicUrl: `https://cdn.example/${path}` } }) }) },
  },
  SUPABASE_URL: 'https://example.supabase.co',
}));
vi.mock('@/components/machine/PaperBackdrop', () => ({ PaperBackdrop: () => null }));
vi.mock('@/components/ReadOnlyNovelRenderer', () => ({ default: ({ content }: { content: string }) => <div data-testid="note">{content}</div> }));

const link = {
  id: 'item-1', type: 'link', title: 'Superr design system', description: 'Cream paper, charcoal, Geist.',
  url: 'https://styles.refero.design/style/abc', file_path: null, mime_type: null, file_size: null,
  summary: 'The summary of the page.', page_body: 'The whole page, captured.', content: '', attributes: {},
  created_at: '2026-10-08T00:00:00Z', shared_at: '2026-10-09T00:00:00Z', username: 'will', display_name: 'Will',
};

const renderAt = (token: string) =>
  render(
    <MemoryRouter initialEntries={[`/s/${token}`]}>
      <Routes>
        <Route path="/s/:token" element={<SharedItem />} />
      </Routes>
    </MemoryRouter>,
  );

beforeEach(() => rpc.mockReset());

it('shows the save read-only: the bar, the address, title, description, source tabs, and who shared it', async () => {
  rpc.mockResolvedValue({ data: [link], error: null });
  renderAt('Xk3mN9pQ2a');
  expect(await screen.findByRole('heading', { level: 1, name: 'Superr design system' })).toBeInTheDocument();
  expect(rpc).toHaveBeenCalledWith('shared_item', { p_token: 'Xk3mN9pQ2a' });
  expect(screen.getByText('from @will’s stash')).toBeInTheDocument();
  expect(screen.getByRole('link', { name: 'Get Stash' })).toHaveAttribute('href', 'https://www.gostash.it/');
  expect(screen.getByText('Cream paper, charcoal, Geist.')).toBeInTheDocument();
  // The strip's address link (the details facts list the domain as a link too)
  expect(screen.getAllByRole('link', { name: /styles\.refero\.design/ })[0]).toHaveAttribute('href', link.url);
  expect(screen.queryByRole('button', { name: 'Edit address' })).not.toBeInTheDocument();
  expect(screen.getByRole('tab', { name: 'Summary' })).toHaveAttribute('aria-selected', 'true');
  expect(screen.getByText('The summary of the page.')).toBeInTheDocument();
  expect(screen.queryByRole('button', { name: /edit summary/i })).not.toBeInTheDocument();
  fireEvent.click(screen.getByRole('tab', { name: 'Original Content' }));
  expect(screen.getByText('The whole page, captured.')).toBeInTheDocument();
  expect(screen.queryByRole('region', { name: 'Notes' })).not.toBeInTheDocument();
  expect(document.title).toBe('Superr design system · Stash');
});

it('shows the notes when the person wrote some', async () => {
  rpc.mockResolvedValue({ data: [{ ...link, content: '{"type":"doc","content":[{"type":"paragraph","content":[{"type":"text","text":"My take"}]}]}' }], error: null });
  renderAt('Xk3mN9pQ2a');
  await screen.findByRole('heading', { level: 1 });
  expect(screen.getByRole('region', { name: 'Notes' })).toBeInTheDocument();
  expect(screen.getByTestId('note')).toHaveTextContent('My take');
});

it('a note is the object itself, with no source tabs', async () => {
  rpc.mockResolvedValue({ data: [{ ...link, type: 'text', url: null, title: 'A thought', summary: null, page_body: null, content: '{"type":"doc","content":[{"type":"paragraph","content":[{"type":"text","text":"Just this"}]}]}' }], error: null });
  renderAt('Xk3mN9pQ2a');
  await screen.findByRole('heading', { level: 1, name: 'A thought' });
  expect(screen.queryByRole('tablist')).not.toBeInTheDocument();
  expect(screen.getByTestId('note')).toHaveTextContent('Just this');
});

it('says the link no longer works when the token is unknown', async () => {
  rpc.mockResolvedValue({ data: [], error: null });
  renderAt('Xk3mN9pQ2a');
  expect(await screen.findByText('This link no longer works.')).toBeInTheDocument();
  // In the header and again under the message
  expect(screen.getAllByRole('link', { name: 'Get Stash' })).toHaveLength(2);
});

it('does not even ask for a malformed token', () => {
  renderAt('nope');
  expect(screen.getByText('This link no longer works.')).toBeInTheDocument();
  expect(rpc).not.toHaveBeenCalled();
});
