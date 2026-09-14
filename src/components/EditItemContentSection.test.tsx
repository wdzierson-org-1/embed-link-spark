import { fireEvent, render, screen } from '@testing-library/react';
import EditItemContentSection from './EditItemContentSection';
vi.mock('@/hooks/useItemSourceContent', () => ({ useItemSourceContent: () => ({
  summary: 'Extracted summary', pageBody: 'Original source', isLoading: false,
}) }));
vi.mock('@/components/EditItemContentEditor', () => ({ default: () => <div data-testid="rich-editor">My context</div> }));
vi.mock('@/components/TranscriptContent', () => ({ default: () => <div>Speaker transcript</div> }));

it('keeps the rich Notes editor above the source tabs while switching source content', () => {
  render(<EditItemContentSection item={{ id: 'link', type: 'link' }} content="My context" isContentLoading={false}
    editorKey="link" onContentChange={vi.fn()} onMaximize={vi.fn()} isMobile={false} mobileEditorReady />);
  expect(screen.queryByRole('tab', { name: 'Notes' })).not.toBeInTheDocument();
  const notes = screen.getByRole('region', { name: 'Notes' });
  const source = screen.getByRole('region', { name: 'Source' });
  expect(notes.compareDocumentPosition(source) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy();
  expect(screen.getByText('Extracted summary')).toBeInTheDocument();
  fireEvent.click(screen.getByRole('tab', { name: 'Original Content' }));
  expect(screen.getByText('Original source')).toBeInTheDocument();
  expect(screen.getByTestId('rich-editor')).toBeInTheDocument();
  expect(screen.getByRole('button', { name: 'Maximize editor' })).toBeInTheDocument();
});
