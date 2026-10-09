// @vitest-environment node
import { beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
const state = vi.hoisted(() => ({
  handler: null as any, item: null as any, capture: null as any,
  apply: vi.fn(), recover: vi.fn(), remove: vi.fn(), invoke: vi.fn(), summary: vi.fn(), apiKey: undefined as string | undefined,
}));
vi.mock('https://deno.land/std@0.168.0/http/server.ts', () => ({ serve: (handler: any) => { state.handler = handler; } }));
vi.mock('https://esm.sh/@supabase/supabase-js@2.7.1', () => ({ createClient: () => ({
  storage: { from: () => ({ remove: state.remove }) }, functions: { invoke: state.invoke },
}) }));
vi.mock('../_shared/enrichmentAuth.ts', () => ({ requireItemAccess: async () => state.item }));
vi.mock('../_shared/pageExtraction.ts', () => ({ extractPage: async () => state.capture }));
vi.mock('../_shared/capturedPreview.ts', () => ({ recoverCapturedPreview: (...args: any[]) => state.recover(...args) }));
vi.mock('../_shared/enrichmentStore.ts', () => ({ ENRICHMENT_COLUMNS: 'id', applyCandidate: (...args: any[]) => state.apply(...args) }));
vi.mock('../_shared/summarize.ts', () => ({ deriveTitleFromContent: async () => null, generateSummary: (...args: any[]) => state.summary(...args) }));
beforeAll(async () => { vi.stubGlobal('Deno', { env: { get: (key: string) => key === 'OPENAI_API_KEY' ? state.apiKey : undefined } }); await import('./index.ts'); });
beforeEach(() => {
  vi.clearAllMocks();
  state.apiKey = undefined; state.summary.mockResolvedValue(null);
  state.item = { id: 'item-id', user_id: 'owner-id', type: 'link', url: 'https://www.linkedin.com/in/scottjenson/', file_path: null };
  state.capture = { text: '# Scott Jenson\nPublic profile evidence.', source: 'jina-reader', kind: 'page' };
  state.apply.mockResolvedValue(true); state.recover.mockResolvedValue({ path: 'owner-id/previews/new.jpg' });
  state.invoke.mockResolvedValue({ data: { success: true } }); state.remove.mockResolvedValue({ error: null });
});
const request = (extra = {}) => new Request('https://stash.example/scrape-page-content', {
  method: 'POST', headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({ itemId: 'item-id', url: state.item.url, ...extra }),
});
describe('captured preview persistence', () => {
  it('applies the recovered preview and captured text in the same guarded patch', async () => {
    const result = await (await state.handler(request())).json();
    expect(result.success).toBe(true);
    expect(state.apply).toHaveBeenCalledWith(expect.anything(), state.item,
      { page_body: state.capture.text, file_path: 'owner-id/previews/new.jpg' }, 'jina-reader', { capture_kind: 'page' });
    expect(state.remove).not.toHaveBeenCalled();
  });
  it('retains captured text when no safe portrait could be stored', async () => {
    state.recover.mockResolvedValue(null);
    await state.handler(request());
    expect(state.apply.mock.calls[0][2]).toEqual({ page_body: state.capture.text });
  });
  it('removes only its newly recovered upload when the item snapshot changes', async () => {
    state.apply.mockResolvedValue(false);
    const result = await (await state.handler(request())).json();
    expect(result).toEqual({ success: false, reason: 'item_changed' });
    expect(state.remove).toHaveBeenCalledWith(['owner-id/previews/new.jpg']);
    expect(state.invoke).not.toHaveBeenCalled();
  });
  it('does not download or mutate previews in extract-only mode', async () => {
    const result = await (await state.handler(request({ extractOnly: true }))).json();
    expect(result.success).toBe(true);
    expect(state.recover).not.toHaveBeenCalled(); expect(state.apply).not.toHaveBeenCalled();
  });
  it('does not upload an image when summary generation fails before patching', async () => {
    state.apiKey = 'test-key'; state.summary.mockRejectedValue(new Error('Provider unavailable'));
    const response = await state.handler(request());
    expect(response.status).toBe(500);
    expect(await response.json()).toEqual({ success: false, reason: 'Extraction failed' });
    expect(state.recover).not.toHaveBeenCalled(); expect(state.apply).not.toHaveBeenCalled();
    expect(state.remove).not.toHaveBeenCalled();
  });
});
