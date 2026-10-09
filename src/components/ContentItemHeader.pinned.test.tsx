import { render, screen } from '@testing-library/react';
import ContentItemHeader from './ContentItemHeader';

vi.mock('@/integrations/supabase/client', () => ({
  supabase: { storage: { from: () => ({ getPublicUrl: () => ({ data: { publicUrl: '' } }) }) } },
  SUPABASE_URL: 'https://example.supabase.co',
}));

const note = (pinned: boolean) => ({
  id: 'note-1',
  type: 'text' as const,
  title: 'A pinned thought',
  created_at: '2026-10-01T00:00:00Z',
  pinned_at: pinned ? '2026-10-09T00:00:00Z' : null,
});

const renderHeader = (item: ReturnType<typeof note>, isPublicView = false) =>
  render(<ContentItemHeader item={item} imageErrors={new Set()} onImageError={() => {}} onEditItem={vi.fn()} isPublicView={isPublicView} />);

it('wears a pinned tag when pinned, and none otherwise', () => {
  renderHeader(note(true));
  expect(screen.getByText('pinned')).toBeInTheDocument();
});

it('has no pinned tag when not pinned', () => {
  renderHeader(note(false));
  expect(screen.queryByText('pinned')).not.toBeInTheDocument();
});

it('keeps pins private: a visitor to the public feed sees no tag', () => {
  renderHeader(note(true), true);
  expect(screen.queryByText('pinned')).not.toBeInTheDocument();
});
