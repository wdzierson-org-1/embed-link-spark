// @vitest-environment node
import { beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';

const state = vi.hoisted(() => ({
  handler: null as any,
  row: null as any,
  background: [] as Promise<unknown>[],
  rpc: vi.fn(), invoke: vi.fn(), update: vi.fn(),
}));
vi.mock('https://esm.sh/@supabase/supabase-js@2.50.2', () => ({
  createClient: () => ({
    auth: { getUser: async () => ({ data: { user: { id: 'owner-1' } }, error: null }) },
    from: () => ({
      insert: (row: any) => { state.row = { id: 'item-1', ...structuredClone(row) }; return { select: () => ({ single: async () => ({ data: structuredClone(state.row), error: null }) }) }; },
      select: () => ({ eq: () => ({ single: async () => ({ data: structuredClone(state.row), error: null }) }) }),
      update: (patch: any) => { state.update(patch); Object.assign(state.row, patch); return { eq: async () => ({ error: null }) }; },
    }),
    rpc: state.rpc, functions: { invoke: state.invoke },
  }),
}));
vi.mock('../_shared/agentToken.ts', () => ({ isAgentToken: () => false }));
vi.mock('../_shared/entitlementGate.ts', () => ({ requireEntitlement: async () => null }));
const placeStep = vi.hoisted(() => vi.fn(async () => ({ skipped: 'no_address' })));
vi.mock('../_shared/placeEnrichment.ts', () => ({ runImagePlaceStep: placeStep }));
const previewStep = vi.hoisted(() => vi.fn(async () => ({ skipped: 'renderer_not_configured' })));
vi.mock('../_shared/documentPreview.ts', () => ({ runDocumentPreviewStep: previewStep }));

beforeAll(async () => {
  vi.stubGlobal('Deno', { env: { get: () => 'https://stash.example' }, serve: (handler: any) => { state.handler = handler; } });
  vi.stubGlobal('EdgeRuntime', { waitUntil: (promise: Promise<unknown>) => state.background.push(promise) });
  await import('./index.ts');
});
beforeEach(() => {
  vi.clearAllMocks(); state.row = null; state.background = [];
  state.invoke.mockResolvedValue({ data: { success: true }, error: null });
  state.rpc.mockResolvedValue({ data: true, error: null });
});
async function save(body: Record<string, unknown>) {
  const response = await state.handler(new Request('https://stash.example/add-file', { method: 'POST',
    headers: { authorization: 'Bearer owner-token', 'content-type': 'application/json' },
    body: JSON.stringify({ file_path: 'owner-1/staging/123-abc.bin', ...body }),
  }));
  await Promise.all(state.background); return response;
}
const invoked = () => state.invoke.mock.calls.map(([name]) => name);
const settled = () => state.rpc.mock.calls.filter(([name]) => name === 'set_item_enrichment').map(([, args]) => args.next_status);

describe('add-file: one pipeline for every client', () => {
  it('describes an image through analyze-image and settles the save', async () => {
    expect((await save({ file_path: 'owner-1/staging/123-abc.jpg', mime_type: 'image/jpeg', file_size: 1234, title: 'photo.jpg' })).status).toBe(200);
    expect(state.row).toMatchObject({ type: 'image', title: 'photo.jpg', attributes: { enrichment: { status: 'pending' } } });
    expect(invoked()).toEqual(['analyze-image']);
    expect(settled()).toEqual(['complete']);
    // After the picture is read, its text is checked for an address (the place step)
    expect(placeStep).toHaveBeenCalledWith(expect.anything(), 'item-1', { mapboxToken: 'https://stash.example' });
  });

  it('skips the place step when the picture could not be read', async () => {
    state.invoke.mockResolvedValue({ data: null, error: new Error('vision down') });
    await save({ file_path: 'owner-1/staging/123-abc.jpg', mime_type: 'image/jpeg', title: 'photo.jpg' });
    expect(placeStep).not.toHaveBeenCalled();
    expect(settled()).toEqual(['partial']);
  });

  it('starts the transcription job for audio and leaves the status for the job to settle', async () => {
    await save({ file_path: 'owner-1/staging/123-abc.m4a', mime_type: 'audio/mp4', file_size: 4096, title: 'memo.m4a', attributes: { media: { duration_s: 42, file_name: 'memo.m4a' } } });
    expect(state.row).toMatchObject({ type: 'audio', attributes: { media: { kind: 'voice_note', file_name: 'memo.m4a', transcript: { status: 'pending' } } } });
    expect(invoked()).toEqual(['generate-embeddings', 'transcribe-audio']);
    expect(settled()).toEqual([]);
  });

  it('reads a PDF through the quick summary and the full extraction, then settles', async () => {
    await save({ file_path: 'owner-1/staging/123-abc.pdf', mime_type: 'application/pdf', file_size: 9000, title: 'paper.pdf', content: 'read this' });
    expect(state.row).toMatchObject({ type: 'document', description: 'PDF file uploaded - text extraction in progress' });
    expect(invoked()).toEqual(['generate-embeddings', 'quick-pdf-summary', 'extract-pdf-text']);
    expect(settled()).toEqual(['complete']);
  });

  it('refuses a file outside the caller’s own folder', async () => {
    expect((await save({ file_path: 'someone-else/staging/x.jpg', mime_type: 'image/jpeg' })).status).toBe(403);
    expect(invoked()).toEqual([]);
  });
});

describe('add-file document previews', () => {
  it('asks for a PDF’s first page before extraction, from the stored object', async () => {
    const response = await save({ mime_type: 'application/pdf', file_path: 'owner-1/staging/deck.pdf' });
    expect(response.status).toBe(200);
    await Promise.all(state.background);
    expect(previewStep).toHaveBeenCalledTimes(1);
    const [, item, options] = previewStep.mock.calls[0] as unknown as [unknown, { id: string; user_id: string; mime_type: string }, { publicUrl: string; rendererUrl: string }];
    expect(item).toEqual({ id: 'item-1', user_id: 'owner-1', mime_type: 'application/pdf' });
    expect(options.publicUrl).toBe('https://stash.example/storage/v1/object/public/stash-media/owner-1/staging/deck.pdf');
    expect(options.rendererUrl).toBe('https://stash.example');
    const order = state.invoke.mock.calls.map(([name]) => name);
    expect(order.indexOf('quick-pdf-summary')).toBeGreaterThan(-1);
    expect(previewStep.mock.invocationCallOrder[0]).toBeLessThan(state.invoke.mock.invocationCallOrder[order.indexOf('quick-pdf-summary')]);
  });

  it('asks for a presentation’s saved preview too, and never for a picture', async () => {
    await save({ mime_type: 'application/vnd.openxmlformats-officedocument.presentationml.presentation', file_path: 'owner-1/staging/deck.pptx' });
    await Promise.all(state.background);
    expect(previewStep).toHaveBeenCalledTimes(1);
    previewStep.mockClear();
    await save({ mime_type: 'image/png', file_path: 'owner-1/staging/photo.png' });
    await Promise.all(state.background);
    expect(previewStep).not.toHaveBeenCalled();
  });

  it('keeps the save and its extraction when the preview step throws', async () => {
    previewStep.mockRejectedValueOnce(new Error('renderer exploded'));
    const response = await save({ mime_type: 'application/pdf', file_path: 'owner-1/staging/deck.pdf' });
    expect(response.status).toBe(200);
    await Promise.all(state.background);
    expect(state.invoke.mock.calls.map(([name]) => name)).toContain('extract-pdf-text');
    expect(state.rpc).toHaveBeenCalledWith('set_item_enrichment', { target_id: 'item-1', next_status: 'complete' });
  });
});
