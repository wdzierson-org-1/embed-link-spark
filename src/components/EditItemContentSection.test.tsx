import { fireEvent, render, screen, waitFor, within } from '@testing-library/react';
import EditItemContentSection from './EditItemContentSection';

const source = vi.hoisted(() => ({
  state: {} as Record<string, unknown>,
}));
vi.mock('@/hooks/useItemSourceContent', async (importOriginal) => ({
  ...(await importOriginal<typeof import('@/hooks/useItemSourceContent')>()),
  useItemSourceContent: () => source.state,
}));
// The editor is a contenteditable jsdom can't drive: a focusable stand-in that reports its props
vi.mock('@/components/EditItemContentEditor', () => ({
  default: ({ inline }: { inline?: boolean }) => (
    <div data-testid="rich-editor" data-inline={String(Boolean(inline))} tabIndex={0}>
      My context
    </div>
  ),
}));
vi.mock('@/components/TranscriptContent', () => ({ default: () => <div>Speaker transcript</div> }));

const LONG_PAGE = 'A saved article about generative UI, long enough that a summary is worth writing.';

const renderLink = (props: Partial<React.ComponentProps<typeof EditItemContentSection>> = {}) =>
  render(
    <EditItemContentSection
      item={{ id: 'link', type: 'link' }}
      content="My context"
      isContentLoading={false}
      editorKey="link"
      onContentChange={vi.fn()}
      onMaximize={vi.fn()}
      isMobile={false}
      mobileEditorReady
      {...props}
    />,
  );

beforeEach(() => {
  source.state = {
    summary: 'Extracted summary', pageBody: 'Original source', isLoading: false,
    isGenerating: false, generateError: null, generateSummary: vi.fn(), setSummary: vi.fn(),
  };
});

describe('the section order and the source row', () => {
  it('puts the source above the notes, with the tabs on the left and no "source" label', () => {
    renderLink();
    const sourceRegion = screen.getByRole('region', { name: 'Source' });
    const notes = screen.getByRole('region', { name: 'Notes' });
    expect(sourceRegion.compareDocumentPosition(notes) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy();
    expect(screen.queryByText(/^source$/i)).not.toBeInTheDocument();
    expect(screen.getByRole('tab', { name: 'Summary' })).toHaveAttribute('aria-selected', 'true');
    expect(screen.getByRole('tab', { name: 'Original Content' })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'View full size' })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Maximize editor' })).toBeInTheDocument();
  });

  it('switches tabs, and shows the active tab full size on the icon', () => {
    renderLink();
    fireEvent.click(screen.getByRole('tab', { name: 'Original Content' }));
    expect(screen.getByText('Original source')).toBeInTheDocument();
    fireEvent.click(screen.getByRole('button', { name: 'View full size' }));
    const full = screen.getByRole('region', { name: 'original content, full size' });
    expect(full).toHaveTextContent('Original source');
    fireEvent.click(screen.getByRole('button', { name: 'Minimize' }));
    expect(screen.queryByRole('region', { name: /full size/ })).not.toBeInTheDocument();
  });
});

describe('the summary, editable in place', () => {
  it('becomes a field on click and saves the edit on blur', async () => {
    const onSummarySave = vi.fn().mockResolvedValue(undefined);
    renderLink({ onSummarySave });
    fireEvent.click(screen.getByRole('button', { name: 'Edit summary' }));
    const field = screen.getByRole('textbox', { name: 'Summary' });
    expect(field).toHaveValue('Extracted summary');
    fireEvent.change(field, { target: { value: 'My better summary' } });
    fireEvent.blur(field);
    await waitFor(() => expect(onSummarySave).toHaveBeenCalledWith('My better summary'));
    expect(source.state.setSummary).toHaveBeenCalledWith('My better summary');
  });

  it('saves nothing when the text is unchanged, and Escape abandons the edit', () => {
    const onSummarySave = vi.fn();
    renderLink({ onSummarySave });
    fireEvent.click(screen.getByRole('button', { name: 'Edit summary' }));
    fireEvent.change(screen.getByRole('textbox', { name: 'Summary' }), { target: { value: 'Abandoned' } });
    fireEvent.keyDown(screen.getByRole('textbox', { name: 'Summary' }), { key: 'Escape' });
    expect(screen.queryByRole('textbox')).not.toBeInTheDocument();
    expect(onSummarySave).not.toHaveBeenCalled();
    expect(screen.getByText('Extracted summary')).toBeInTheDocument();
  });

  it('Escape abandons the edit before the sheet can hear it, and leaves a full-size view open', () => {
    const heard = vi.fn();
    document.addEventListener('keydown', heard, true);
    renderLink({ onSummarySave: vi.fn() });
    fireEvent.click(screen.getByRole('button', { name: 'View full size' }));
    const full = screen.getByRole('region', { name: 'summary, full size' });
    fireEvent.click(within(full).getByRole('button', { name: 'Edit summary' }));
    fireEvent.keyDown(within(full).getByRole('textbox', { name: 'Summary' }), { key: 'Escape' });
    expect(screen.queryByRole('textbox')).not.toBeInTheDocument();
    expect(screen.getByRole('region', { name: 'summary, full size' })).toBeInTheDocument();
    expect(heard).not.toHaveBeenCalled();
    document.removeEventListener('keydown', heard, true);
  });

  it('is read-only without a save handler, and the original content always is', () => {
    renderLink();
    expect(screen.queryByRole('button', { name: 'Edit summary' })).not.toBeInTheDocument();
    fireEvent.click(screen.getByRole('tab', { name: 'Original Content' }));
    expect(screen.queryByRole('button', { name: /^edit /i })).not.toBeInTheDocument();
  });
});

describe('the notes field', () => {
  it('is one line of text until clicked, then the editor, inline', () => {
    renderLink({ content: '' });
    expect(screen.queryByTestId('rich-editor')).not.toBeInTheDocument();
    fireEvent.click(screen.getByRole('button', { name: 'Add a note…' }));
    expect(screen.getByTestId('rich-editor')).toHaveAttribute('data-inline', 'true');
  });

  it('treats a stored empty editor document as no note at all', () => {
    renderLink({ content: '{"type":"doc","content":[{"type":"paragraph"}]}' });
    expect(screen.queryByTestId('rich-editor')).not.toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Add a note…' })).toBeInTheDocument();
  });

  it('shows the editor at once when a note exists, and the formatting hint only while focused', () => {
    renderLink();
    const editor = screen.getByTestId('rich-editor');
    expect(editor).toBeInTheDocument();
    expect(screen.queryByText('type / for formatting')).not.toBeInTheDocument();
    fireEvent.focus(editor);
    expect(screen.getByText('type / for formatting')).toBeInTheDocument();
    fireEvent.blur(editor);
    expect(screen.queryByText('type / for formatting')).not.toBeInTheDocument();
  });
});

describe('the summary tab without a summary', () => {
  it('offers Generate summary when enough text was captured, and runs it', () => {
    const generateSummary = vi.fn();
    source.state = { ...source.state, summary: null, pageBody: LONG_PAGE, generateSummary };
    renderLink();
    fireEvent.click(screen.getByRole('button', { name: /generate summary/i }));
    expect(generateSummary).toHaveBeenCalledTimes(1);
  });

  it('does not offer a summary the server would refuse (under 50 characters of text)', () => {
    source.state = { ...source.state, summary: null, pageBody: '   Help me get on the road 🚐   ' };
    renderLink();
    expect(screen.queryByRole('button', { name: /generate summary/i })).not.toBeInTheDocument();
    expect(screen.getByText(/too little text was captured to summarize/i)).toBeInTheDocument();
  });

  it('shows a failed run as an error line beside the button, so a retry is obvious', () => {
    source.state = { ...source.state, summary: null, pageBody: LONG_PAGE, generateError: "couldn't summarize this. try again" };
    renderLink();
    const line = screen.getByText("couldn't summarize this. try again");
    expect(line.closest('[role="status"]')).toHaveClass('text-error');
    expect(screen.getByRole('button', { name: /generate summary/i })).toBeInTheDocument();
  });

  it('shows the busy line instead of the button while summarizing', () => {
    source.state = { ...source.state, summary: null, pageBody: LONG_PAGE, isGenerating: true };
    renderLink();
    expect(screen.getByText('summarizing…')).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: /generate summary/i })).not.toBeInTheDocument();
  });
});

describe('a document with no extracted text', () => {
  const renderDocument = (status: 'pending' | 'complete' | 'partial') =>
    render(<EditItemContentSection
      item={{ id: 'doc', type: 'document', attributes: { enrichment: { status, updated_at: new Date().toISOString() } } }}
      content="" isContentLoading={false} editorKey="doc" onContentChange={vi.fn()} onMaximize={vi.fn()}
      isMobile={false} mobileEditorReady />);

  beforeEach(() => {
    source.state = { ...source.state, summary: null, pageBody: null };
  });

  it('says the text is still being extracted only while extraction is pending', () => {
    renderDocument('pending');
    expect(screen.getByText('Content is still being extracted from this document.')).toBeInTheDocument();
  });

  it('says the text could not be read once extraction has settled without any (e.g. a PDF over 50 MB)', () => {
    renderDocument('partial');
    expect(screen.getByText("We couldn't read the text in this document.")).toBeInTheDocument();
    expect(screen.queryByText(/still being extracted/)).not.toBeInTheDocument();
  });
});
