import { fireEvent, render, screen } from '@testing-library/react';
import EditItemContentSection from './EditItemContentSection';

const source = vi.hoisted(() => ({
  state: {} as Record<string, unknown>,
}));
vi.mock('@/hooks/useItemSourceContent', async (importOriginal) => ({
  ...(await importOriginal<typeof import('@/hooks/useItemSourceContent')>()),
  useItemSourceContent: () => source.state,
}));
vi.mock('@/components/EditItemContentEditor', () => ({ default: () => <div data-testid="rich-editor">My context</div> }));
vi.mock('@/components/TranscriptContent', () => ({ default: () => <div>Speaker transcript</div> }));

const LONG_PAGE = 'A saved article about generative UI, long enough that a summary is worth writing.';

const renderLink = () =>
  render(<EditItemContentSection item={{ id: 'link', type: 'link' }} content="My context" isContentLoading={false}
    editorKey="link" onContentChange={vi.fn()} onMaximize={vi.fn()} isMobile={false} mobileEditorReady />);

beforeEach(() => {
  source.state = {
    summary: 'Extracted summary', pageBody: 'Original source', isLoading: false,
    isGenerating: false, generateError: null, generateSummary: vi.fn(),
  };
});

it('keeps the rich Notes editor above the source tabs while switching source content', () => {
  renderLink();
  expect(screen.queryByRole('tab', { name: 'Notes' })).not.toBeInTheDocument();
  const notes = screen.getByRole('region', { name: 'Notes' });
  const sourceRegion = screen.getByRole('region', { name: 'Source' });
  expect(notes.compareDocumentPosition(sourceRegion) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy();
  expect(screen.getByText('Extracted summary')).toBeInTheDocument();
  fireEvent.click(screen.getByRole('tab', { name: 'Original Content' }));
  expect(screen.getByText('Original source')).toBeInTheDocument();
  expect(screen.getByTestId('rich-editor')).toBeInTheDocument();
  expect(screen.getByRole('button', { name: 'Maximize editor' })).toBeInTheDocument();
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
