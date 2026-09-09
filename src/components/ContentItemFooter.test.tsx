import { render, screen, fireEvent } from '@testing-library/react';
import ContentItemFooter from './ContentItemFooter';

const { mockGetPublicUrl, mockSaveItem, mockToast } = vi.hoisted(() => ({
  mockGetPublicUrl: vi.fn(() => ({ data: { publicUrl: '' } })),
  mockSaveItem: vi.fn(),
  mockToast: vi.fn(),
}));

vi.mock('@/integrations/supabase/client', () => ({
  supabase: { storage: { from: () => ({ getPublicUrl: mockGetPublicUrl }) } },
}));

vi.mock('@/hooks/use-toast', () => ({
  useToast: () => ({ toast: mockToast }),
}));

vi.mock('@/utils/itemOperations', () => ({
  saveItem: mockSaveItem,
}));

// These pull in heavy deps unrelated to the reminder behaviour under test.
vi.mock('@/components/CardFeedbackDialog', () => ({ default: () => null }));
vi.mock('@/components/AnimatedCommentCount', () => ({ AnimatedCommentCount: () => null }));

const dueItem = {
  id: 'item-1',
  type: 'text' as const,
  title: 'A reminder-bearing card',
  created_at: '2026-08-01T00:00:00Z',
  user_id: 'owner-1',
  remind_at: new Date(Date.now() - 60_000).toISOString(),
  reminder_cleared_at: null,
};

const noop = () => {};

describe('ContentItemFooter reminders (public vs owner)', () => {
  beforeEach(() => vi.clearAllMocks());

  it('hides reminder chip and controls in a public view', () => {
    render(
      <ContentItemFooter
        item={dueItem}
        onDeleteItem={noop}
        onEditItem={noop}
        isPublicView
        currentUserId="owner-1"
      />
    );

    expect(screen.queryByTestId('reminder-chip-due')).not.toBeInTheDocument();
    expect(screen.queryByText('Remove reminder')).not.toBeInTheDocument();
  });

  it('shows the reminder chip and lets the owner clear the reminder', async () => {
    render(
      <ContentItemFooter
        item={dueItem}
        onDeleteItem={noop}
        onEditItem={noop}
        isPublicView={false}
        currentUserId="owner-1"
      />
    );

    expect(screen.getByTestId('reminder-chip-due')).toBeInTheDocument();

    // The due chip's inline dismiss control (DESIGN.md: never hover-only).
    fireEvent.click(screen.getByRole('button', { name: 'Remove reminder' }));

    expect(mockSaveItem).toHaveBeenCalledWith(
      'item-1',
      expect.objectContaining({ reminder_cleared_at: expect.any(String) }),
      expect.any(Function),
      mockToast,
      expect.any(Object)
    );
  });
});

// A read-only view (public feed, admin member view) only gets the overflow
// menu when it would contain something — an empty menu is a dead control.
describe('ContentItemFooter menu (public view)', () => {
  const base = { created_at: '2026-08-01T00:00:00Z', user_id: 'owner-1' };

  it('renders no menu trigger when a public view has nothing to offer', () => {
    render(
      <ContentItemFooter item={{ ...base, id: 'n1', type: 'text' }} onDeleteItem={noop} onEditItem={noop} isPublicView />
    );
    expect(screen.queryByRole('button')).not.toBeInTheDocument();
  });

  it('keeps the menu for a public link, which can still be opened', () => {
    render(
      <ContentItemFooter
        item={{ ...base, id: 'l1', type: 'link', url: 'https://example.test' }}
        onDeleteItem={noop}
        onEditItem={noop}
        isPublicView
      />
    );
    expect(screen.getByRole('button')).toBeInTheDocument();
  });
});
