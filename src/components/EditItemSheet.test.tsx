import { render, screen } from '@testing-library/react';
import EditItemSheet from './EditItemSheet';

// Only the sheet's own open/close gate is under test; its contents are stubbed.
vi.mock('@/hooks/useEditItemSheet', () => ({
  useEditItemSheet: () => ({ hasImage: false, activeTab: 'details', saveStatus: 'idle', lastSaved: null }),
}));
vi.mock('@/hooks/use-mobile', () => ({ useIsMobile: () => false }));
vi.mock('@/components/EditItemDetailsTab', () => ({ default: () => <div>item details</div> }));
vi.mock('@/components/EditItemImageTab', () => ({ default: () => null }));
vi.mock('@/components/EditItemTabNavigation', () => ({ default: () => null }));
vi.mock('@/components/EditItemAutoSaveIndicator', () => ({ default: () => null }));

// A PDF saved a minute ago whose summary hasn't landed
const pdf = (status: 'pending' | 'partial') => ({
  id: 'doc-1',
  type: 'document',
  title: 'Big PDF',
  mime_type: 'application/pdf',
  file_path: 'user-1/big.pdf',
  created_at: new Date(Date.now() - 60_000).toISOString(),
  attributes: { enrichment: { status, updated_at: new Date(Date.now() - 30_000).toISOString() } },
});

const renderSheet = (item: ReturnType<typeof pdf>) => {
  const onOpenChange = vi.fn();
  render(<EditItemSheet open item={item} onOpenChange={onOpenChange} onSave={vi.fn()} />);
  return onOpenChange;
};

describe('EditItemSheet on a PDF without its summary', () => {
  it('closes itself while the PDF is still being read', () => {
    expect(renderSheet(pdf('pending'))).toHaveBeenCalledWith(false);
  });

  it('stays open once the extraction has failed (enrichment settled partial)', () => {
    const onOpenChange = renderSheet(pdf('partial'));
    expect(onOpenChange).not.toHaveBeenCalledWith(false);
    expect(screen.getByText('item details')).toBeInTheDocument();
  });
});
