import { render, screen, waitFor, fireEvent } from '@testing-library/react';
import ConversationsView from './ConversationsView';

const { mockRpc } = vi.hoisted(() => ({ mockRpc: vi.fn() }));
vi.mock('@/integrations/supabase/client', () => ({ supabase: { rpc: mockRpc } }));

const rows = [
  { id: 'c1', title: 'Claude automation', last_message_at: new Date().toISOString(), message_count: 6, preview: 'Beyond the basics…' },
  { id: 'c2', title: null, last_message_at: new Date().toISOString(), message_count: 2, preview: null },
];

describe('ConversationsView', () => {
  beforeEach(() => vi.clearAllMocks());

  it('lists conversations from the RPC in buckets and opens on click', async () => {
    mockRpc.mockResolvedValue({ data: rows, error: null });
    const onOpen = vi.fn();
    render(<ConversationsView onOpenConversation={onOpen} onBack={() => {}} />);

    await waitFor(() => expect(screen.getByText('Claude automation')).toBeTruthy());
    expect(mockRpc).toHaveBeenCalledWith('list_conversations');
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
});
