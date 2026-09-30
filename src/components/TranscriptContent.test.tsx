import { describe, expect, it, vi, beforeEach } from 'vitest';
import { render, screen, waitFor, fireEvent } from '@testing-library/react';

const mockInvoke = vi.fn();
const mockUpdate = vi.fn();
const mockGetPublicUrl = vi.fn(() => ({ data: { publicUrl: 'https://example.test/media/a.m4a' } }));

vi.mock('@/integrations/supabase/client', () => ({
  supabase: {
    functions: { invoke: (...args: unknown[]) => mockInvoke(...args) },
    storage: { from: () => ({ getPublicUrl: mockGetPublicUrl }) },
    from: () => ({ update: (...args: unknown[]) => mockUpdate(...args) }),
  },
}));

vi.mock('@/utils/itemOperations', () => ({ scheduleEmbeddingRefresh: vi.fn() }));

import TranscriptContent from '@/components/TranscriptContent';

describe('TranscriptContent — "Transcribe again"', () => {
  beforeEach(() => {
    mockInvoke.mockReset();
    mockUpdate.mockReset();
    mockInvoke.mockResolvedValue({ data: { accepted: true }, error: null });
  });

  const renderIt = () =>
    render(<TranscriptContent itemId="item-1" filePath="u/rec.m4a" transcript="the old transcript" />);

  it('hands the rebuild to the server job by item id', async () => {
    renderIt();
    fireEvent.click(screen.getByRole('button', { name: /transcribe again/i }));
    await waitFor(() => expect(mockInvoke).toHaveBeenCalled());
    const [fn, options] = mockInvoke.mock.calls[0] as [string, { body: Record<string, unknown> }];
    expect(fn).toBe('transcribe-audio');
    expect(options.body).toEqual({ itemId: 'item-1' });
  });

  // The bug: writing page_body from the browser runs as `authenticated`, so the
  // protect_enrichment_edits trigger records it as a user edit and enrichment can
  // never repair that field again. The service-role function owns this write.
  it('never writes the transcript from the browser', async () => {
    // Shaped like the OLD sync preview reply, so this fails loudly if the
    // component ever goes back to persisting the text itself.
    mockInvoke.mockResolvedValue({
      data: { transcription: 'a fresh transcript', description: 'a fresh description' },
      error: null,
    });
    renderIt();
    fireEvent.click(screen.getByRole('button', { name: /transcribe again/i }));
    await waitFor(() => expect(mockInvoke).toHaveBeenCalled());
    expect(mockUpdate).not.toHaveBeenCalled();
  });

  it('keeps showing the existing transcript while the job runs', async () => {
    renderIt();
    fireEvent.click(screen.getByRole('button', { name: /transcribe again/i }));
    await waitFor(() => expect(mockInvoke).toHaveBeenCalled());
    expect(screen.getByText('the old transcript')).toBeInTheDocument();
  });

  it('surfaces a failure and says the original is intact', async () => {
    mockInvoke.mockResolvedValue({ data: null, error: { message: 'boom' } });
    renderIt();
    fireEvent.click(screen.getByRole('button', { name: /transcribe again/i }));
    expect(await screen.findByRole('alert')).toHaveTextContent(/original is preserved/i);
    expect(mockUpdate).not.toHaveBeenCalled();
  });
});
