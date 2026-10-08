import { render, screen, fireEvent } from '@testing-library/react';
import ContentItemHeader from './ContentItemHeader';

vi.mock('@/integrations/supabase/client', () => ({
  supabase: {
    storage: { from: () => ({ getPublicUrl: () => ({ data: { publicUrl: 'https://cdn.test/report.pdf' } }) }) },
  },
  SUPABASE_URL: 'https://example.supabase.co',
}));

// A PDF saved a minute ago whose summary hasn't landed
const pdf = (status: 'pending' | 'complete' | 'partial') => ({
  id: 'doc-1',
  type: 'document' as const,
  title: 'Quarterly report',
  file_path: 'user-1/report.pdf',
  mime_type: 'application/pdf',
  created_at: new Date(Date.now() - 60_000).toISOString(),
  attributes: { enrichment: { status, updated_at: new Date(Date.now() - 30_000).toISOString() } },
});

const renderHeader = (item: ReturnType<typeof pdf>, onEditItem = vi.fn()) => {
  render(
    <ContentItemHeader item={item} imageErrors={new Set()} onImageError={() => {}} onEditItem={onEditItem} />
  );
  return screen.getByRole('button', { name: 'Quarterly report' });
};

describe('ContentItemHeader on a PDF without its summary', () => {
  it('does not open while the PDF is still being read', () => {
    expect(renderHeader(pdf('pending'))).toBeDisabled();
  });

  it('opens once its extraction has failed (enrichment settled partial, no summary)', () => {
    const onEditItem = vi.fn();
    const title = renderHeader(pdf('partial'), onEditItem);

    expect(title).toBeEnabled();
    fireEvent.click(title);
    expect(onEditItem).toHaveBeenCalledWith(expect.objectContaining({ id: 'doc-1' }));
  });
});
