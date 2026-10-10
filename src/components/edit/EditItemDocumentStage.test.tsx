import { act, fireEvent, render, screen } from '@testing-library/react';
import EditItemDocumentStage, { documentKind, officeViewerUrl } from './EditItemDocumentStage';

vi.mock('@/components/ui/tooltip', () => ({
  TooltipProvider: ({ children }: { children: React.ReactNode }) => <>{children}</>,
  Tooltip: ({ children }: { children: React.ReactNode }) => <>{children}</>,
  TooltipTrigger: ({ children }: { children: React.ReactNode }) => <>{children}</>,
  TooltipContent: () => null,
}));
vi.mock('@/components/machine/PixelMosaic', () => ({ PixelMosaic: () => null }));

// A three-page document whose pages draw nothing (jsdom has no canvas)
const fakePdf = vi.hoisted(() => ({
  getDocument: vi.fn(() => ({
    promise: Promise.resolve({
      numPages: 3,
      getPage: async () => ({ getViewport: () => ({ width: 600, height: 800 }), render: () => ({ promise: Promise.resolve(), cancel: () => {} }) }),
      destroy: () => {},
    }),
  })),
}));
vi.mock('@/utils/pdfPreview', () => ({ loadPdfjs: async () => fakePdf }));

describe('documentKind', () => {
  it('tells PDFs, Office files and HTML apart by mime or extension', () => {
    expect(documentKind('u/a.pdf', 'application/pdf')).toBe('pdf');
    expect(documentKind('u/a.PDF', null)).toBe('pdf');
    expect(documentKind('u/deck.pptx', 'application/vnd.openxmlformats-officedocument.presentationml.presentation')).toBe('office');
    expect(documentKind('u/doc.docx', null)).toBe('office');
    expect(documentKind('u/sheet.xls', 'application/vnd.ms-excel')).toBe('office');
    expect(documentKind('u/deck.html', 'text/html')).toBe('html');
    expect(documentKind('u/notes.txt', 'text/plain')).toBe('other');
  });

  it('builds the Office viewer address around the public file', () => {
    expect(officeViewerUrl('https://cdn.example/stash-media/u/deck.pptx')).toBe(
      'https://view.officeapps.live.com/op/embed.aspx?src=https%3A%2F%2Fcdn.example%2Fstash-media%2Fu%2Fdeck.pptx',
    );
  });
});

describe('the document stage', () => {
  it('reads a PDF page by page', async () => {
    render(<EditItemDocumentStage url="https://cdn.example/a.pdf" kind="pdf" title="a.pdf" />);
    expect(await screen.findByText('page 1 of 3')).toBeInTheDocument();
    fireEvent.click(screen.getByRole('button', { name: 'Next page' }));
    expect(screen.getByText('page 2 of 3')).toBeInTheDocument();
    fireEvent.keyDown(screen.getByLabelText('PDF reader'), { key: 'ArrowRight' });
    expect(screen.getByText('page 3 of 3')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Next page' })).toBeDisabled();
    fireEvent.keyDown(screen.getByLabelText('PDF reader'), { key: 'ArrowLeft' });
    expect(screen.getByText('page 2 of 3')).toBeInTheDocument();
  });

  it('frames an Office file in Microsoft’s viewer and an HTML upload in a sandbox', () => {
    const { rerender } = render(<EditItemDocumentStage url="https://cdn.example/deck.pptx" kind="office" title="deck.pptx" />);
    const office = screen.getByTitle('Document viewer: deck.pptx');
    expect(office).toHaveAttribute('src', officeViewerUrl('https://cdn.example/deck.pptx'));
    rerender(<EditItemDocumentStage url="https://cdn.example/deck.html" kind="html" title="deck.html" />);
    const page = screen.getByTitle('Page: deck.html');
    expect(page).toHaveAttribute('sandbox', 'allow-scripts allow-pointer-lock allow-presentation');
    expect(page).toHaveAttribute('src', 'https://cdn.example/deck.html');
  });

  it('offers full size like every stage', async () => {
    render(<EditItemDocumentStage url="https://cdn.example/a.pdf" kind="pdf" title="a.pdf" />);
    await screen.findByText('page 1 of 3');
    await act(async () => {
      fireEvent.click(screen.getByRole('button', { name: 'Full size' }));
    });
    expect(screen.getByRole('heading', { level: 2 })).toHaveTextContent('pdf');
    expect(screen.getByTestId('document-stage').className).toContain('inset-0');
  });
});
