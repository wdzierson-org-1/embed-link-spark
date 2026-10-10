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

describe('ContentItemHeader on a document with its first page', () => {
  const withPreview = {
    ...pdf('complete'),
    attributes: {
      enrichment: { status: 'complete' as const, updated_at: new Date().toISOString() },
      media: { preview: { file_path: 'user-1/previews/doc_doc-1.png', source: 'pdf-page-1' as const, rendered_at: '2026-10-10T00:00:00Z' } },
    },
  };

  it('shows the page as its picture instead of the drawn placeholder', () => {
    render(<ContentItemHeader item={withPreview} imageErrors={new Set()} onImageError={() => {}} onEditItem={vi.fn()} />);
    const picture = screen.getByRole('img', { name: 'Quarterly report' });
    expect(picture).toHaveAttribute('src', 'https://cdn.test/report.pdf');
  });

  it('falls back to the drawn page when the picture failed to load', () => {
    render(<ContentItemHeader item={withPreview} imageErrors={new Set(['doc-1'])} onImageError={() => {}} onEditItem={vi.fn()} />);
    expect(screen.queryByRole('img', { name: 'Quarterly report' })).not.toBeInTheDocument();
  });
});
