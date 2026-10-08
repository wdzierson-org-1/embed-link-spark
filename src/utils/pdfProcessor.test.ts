import { processPdfContent } from './pdfProcessor';

const { invoke, settle } = vi.hoisted(() => ({ invoke: vi.fn(), settle: vi.fn() }));

vi.mock('@/integrations/supabase/client', () => ({
  supabase: {
    storage: { from: () => ({ getPublicUrl: () => ({ data: { publicUrl: 'https://cdn.test/big.pdf' } }) }) },
    functions: { invoke },
  },
}));
vi.mock('./enrichment', () => ({ settleEnrichment: settle }));

describe('processPdfContent when extraction fails (e.g. a PDF over OpenAI’s 50 MB limit)', () => {
  beforeEach(() => vi.clearAllMocks());

  it('settles the item partial and says so in plain words, never the edge-function error', async () => {
    invoke.mockResolvedValue({ data: null, error: new Error('Edge Function returned a non-2xx status code') });
    const showToast = vi.fn();

    await processPdfContent('item-1', 'user-1/big.pdf', vi.fn().mockResolvedValue(undefined), showToast);

    expect(settle).toHaveBeenCalledWith('item-1', false);
    expect(showToast).toHaveBeenCalledWith({
      title: "Couldn't read this PDF",
      description: "It's saved, and you can still open it.",
      variant: 'destructive',
    });
    expect(JSON.stringify(showToast.mock.calls)).not.toMatch(/Edge Function/);
  });
});
