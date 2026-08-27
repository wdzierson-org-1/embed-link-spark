import { render, screen } from '@testing-library/react';
import ContentGrid from './ContentGrid';

const { mockIn, mockSelect, mockFrom } = vi.hoisted(() => {
  const inFn = vi.fn(() => Promise.resolve({ data: [], error: null }));
  const select = vi.fn(() => ({ in: inFn }));
  const from = vi.fn(() => ({ select }));
  return { mockIn: inFn, mockSelect: select, mockFrom: from };
});

vi.mock('@/integrations/supabase/client', () => ({
  supabase: { from: mockFrom },
}));

// user: null keeps the tag fetch inert (fetchItemTags early-returns)
vi.mock('@/hooks/useAuth', () => ({
  useAuth: () => ({ user: null }),
}));

// ContentItem drags in heavy deps — stub it down to the title
vi.mock('./ContentItem', () => ({
  default: ({ item }: { item: { title: string } }) => <div data-testid="card">{item.title}</div>,
}));

const items = [
  { id: 'a', title: 'Alpha card', type: 'text', created_at: '2026-08-01T00:00:00Z' },
  { id: 'b', title: 'Bravo card', type: 'text', created_at: '2026-08-02T00:00:00Z' },
  { id: 'c', title: 'Charlie card', type: 'text', created_at: '2026-08-03T00:00:00Z' },
];

const baseProps = {
  items,
  onDeleteItem: () => {},
  onEditItem: () => {},
  onChatWithItem: () => {},
  tagFilters: [] as string[],
};

describe('ContentGrid rank precedence', () => {
  beforeEach(() => vi.clearAllMocks());

  it('focusItemIds beats server results AND the client substring filter', () => {
    render(
      <ContentGrid
        {...baseProps}
        focusItemIds={['b']}
        serverResultIds={['a', 'c']}
        searchQuery="zzz-no-match"
      />
    );

    expect(screen.getByText('Bravo card')).toBeInTheDocument();
    expect(screen.queryByText('Alpha card')).not.toBeInTheDocument();
    expect(screen.queryByText('Charlie card')).not.toBeInTheDocument();
  });

  it('without focus, server results filter and order the grid', () => {
    render(
      <ContentGrid
        {...baseProps}
        focusItemIds={null}
        serverResultIds={['c', 'a']}
        searchQuery="anything"
      />
    );

    const titles = screen.getAllByTestId('card').map(el => el.textContent);
    expect(titles).toEqual(['Charlie card', 'Alpha card']); // server relevance order
    expect(screen.queryByText('Bravo card')).not.toBeInTheDocument();
  });
});
