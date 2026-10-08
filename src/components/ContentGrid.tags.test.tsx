import { render, screen, waitFor } from '@testing-library/react';
import ContentGrid from './ContentGrid';

/**
 * The grid's tag fetch. It used to send every item id in the URL; at 841 saves that was a
 * 31 KB URL and the gateway answered 400 on every refetch. Now it reads the person's item_tags
 * (RLS scopes them) in pages, with no id filter.
 */
const { mockRange, mockSelect, mockFrom, pages, user } = vi.hoisted(() => {
  const pages: Array<Array<{ item_id: string; tags: { name: string } }>> = [];
  const range = vi.fn(() => Promise.resolve({ data: pages.shift() ?? [], error: null }));
  const select = vi.fn(() => ({ range, in: () => { throw new Error('the id list must not go in the URL'); } }));
  const from = vi.fn(() => ({ select }));
  // One stable user, as the real hook gives: a fresh object per render would re-run the fetch
  return { mockRange: range, mockSelect: select, mockFrom: from, pages, user: { id: 'u1' } };
});

vi.mock('@/integrations/supabase/client', () => ({ supabase: { from: mockFrom } }));
vi.mock('@/hooks/useAuth', () => ({ useAuth: () => ({ user }) }));
vi.mock('./ContentItem', () => ({
  default: ({ item, tags }: { item: { title: string }; tags?: string[] }) => (
    <div data-testid="card" data-tags={(tags ?? []).join(',')}>{item.title}</div>
  ),
}));

const items = Array.from({ length: 3 }, (_, i) => ({
  id: `item-${i}`,
  title: `Card ${i}`,
  type: 'text',
  created_at: `2026-08-0${i + 1}T00:00:00Z`,
}));

const baseProps = { items, onDeleteItem: () => {}, onEditItem: () => {}, onChatWithItem: () => {}, tagFilters: [] as string[] };

beforeEach(() => {
  vi.clearAllMocks();
  pages.length = 0;
});

it('fetches the person’s item tags without putting item ids in the URL, and groups them by item', async () => {
  pages.push([
    { item_id: 'item-0', tags: { name: 'design' } },
    { item_id: 'item-0', tags: { name: 'reading' } },
    { item_id: 'item-2', tags: { name: 'travel' } },
  ]);
  render(<ContentGrid {...baseProps} />);
  await waitFor(() => expect(screen.getByText('Card 0')).toHaveAttribute('data-tags', 'design,reading'));
  expect(screen.getByText('Card 2')).toHaveAttribute('data-tags', 'travel');
  expect(screen.getByText('Card 1')).toHaveAttribute('data-tags', '');
  expect(mockFrom).toHaveBeenCalledWith('item_tags');
  expect(mockSelect).toHaveBeenCalledWith('item_id, tags!inner(name)');
  expect(mockRange).toHaveBeenCalledWith(0, 999);
});

it('keeps reading pages until a short one, so a library past 1,000 tags loses none', async () => {
  pages.push(
    Array.from({ length: 1000 }, (_, i) => ({ item_id: `item-${i % 3}`, tags: { name: `t${i}` } })),
    [{ item_id: 'item-1', tags: { name: 'last' } }],
  );
  render(<ContentGrid {...baseProps} />);
  await waitFor(() => expect(mockRange).toHaveBeenCalledTimes(2));
  expect(mockRange).toHaveBeenLastCalledWith(1000, 1999);
  await waitFor(() => expect(screen.getByText('Card 1').getAttribute('data-tags')).toContain('last'));
});
