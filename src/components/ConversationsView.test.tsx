import { render, screen, waitFor, fireEvent, act } from '@testing-library/react';
import ConversationsView from './ConversationsView';

const { mockRpc } = vi.hoisted(() => ({ mockRpc: vi.fn() }));
vi.mock('@/integrations/supabase/client', () => ({ supabase: { rpc: mockRpc } }));

const row = (id: string, title: string | null, total = 2) => ({
  id,
  title,
  last_message_at: new Date().toISOString(),
  message_count: 6,
  preview: 'a preview',
  total_count: total,
});

describe('ConversationsView', () => {
  beforeEach(() => vi.clearAllMocks());

  it('lists conversations from the RPC in buckets and opens on click', async () => {
    mockRpc.mockResolvedValue({ data: [row('c1', 'Claude automation'), row('c2', null)], error: null });
    const onOpen = vi.fn();
    render(<ConversationsView onOpenConversation={onOpen} onBack={() => {}} />);

    await waitFor(() => expect(screen.getByText('Claude automation')).toBeTruthy());
    expect(mockRpc).toHaveBeenCalledWith('list_conversations', {
      search_text: null,
      page_limit: 25,
      page_offset: 0,
    });
    expect(screen.getByText('Today')).toBeTruthy();
    expect(screen.getByText('New chat')).toBeTruthy(); // null-title fallback

    fireEvent.click(screen.getByText('Claude automation'));
    expect(onOpen).toHaveBeenCalledWith({ id: 'c1', title: 'Claude automation' });
  });

  it('shows the empty state and back link', async () => {
    mockRpc.mockResolvedValue({ data: [], error: null });
    const onBack = vi.fn();
    render(<ConversationsView onOpenConversation={() => {}} onBack={onBack} />);

    await waitFor(() => expect(screen.getByText(/No conversations yet/i)).toBeTruthy());
    fireEvent.click(screen.getByText('← Back to your stash'));
    expect(onBack).toHaveBeenCalled();
  });

  it('pages forward with Next when more rows exist than the page size', async () => {
    const fullPage = Array.from({ length: 25 }, (_, i) => row(`c${i}`, `Chat ${i}`, 60));
    mockRpc.mockResolvedValue({ data: fullPage, error: null });
    render(<ConversationsView onOpenConversation={() => {}} onBack={() => {}} />);

    await waitFor(() => expect(screen.getByText('Showing 1–25 of 60')).toBeTruthy());
    fireEvent.click(screen.getByText('Next →'));
    await waitFor(() =>
      expect(mockRpc).toHaveBeenLastCalledWith('list_conversations', {
        search_text: null,
        page_limit: 25,
        page_offset: 25,
      })
    );
  });

  it('changing the page size refetches from page 0', async () => {
    mockRpc.mockResolvedValue({ data: [row('c1', 'A', 30)], error: null });
    render(<ConversationsView onOpenConversation={() => {}} onBack={() => {}} />);
    await waitFor(() => expect(screen.getByText('A')).toBeTruthy());

    fireEvent.change(screen.getByRole('combobox'), { target: { value: '100' } });
    await waitFor(() =>
      expect(mockRpc).toHaveBeenLastCalledWith('list_conversations', {
        search_text: null,
        page_limit: 100,
        page_offset: 0,
      })
    );
  });

  it('debounces search and queries with the trimmed text', async () => {
    vi.useFakeTimers();
    try {
      mockRpc.mockResolvedValue({ data: [row('c1', 'Sourdough', 1)], error: null });
      render(<ConversationsView onOpenConversation={() => {}} onBack={() => {}} />);

      fireEvent.change(screen.getByPlaceholderText('Search conversations…'), {
        target: { value: '  bread  ' },
      });
      await act(async () => {
        vi.advanceTimersByTime(300);
      });
      expect(mockRpc).toHaveBeenLastCalledWith('list_conversations', {
        search_text: 'bread',
        page_limit: 25,
        page_offset: 0,
      });
    } finally {
      vi.useRealTimers();
    }
  });
});
