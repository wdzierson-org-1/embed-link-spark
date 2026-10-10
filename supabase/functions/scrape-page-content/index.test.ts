// @vitest-environment node
import { beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';

const state = vi.hoisted(() => ({
  handler: null as any, row: null as any,
  extract: vi.fn(), resolve: vi.fn(), rpc: vi.fn(), invoke: vi.fn(), remove: vi.fn(), preview: vi.fn(),
}));
vi.mock('https://deno.land/std@0.168.0/http/server.ts', () => ({ serve: (handler: any) => { state.handler = handler; } }));
vi.mock('https://esm.sh/@supabase/supabase-js@2.7.1', () => ({ createClient: () => ({
  rpc: state.rpc, functions: { invoke: state.invoke }, storage: { from: () => ({ remove: state.remove }) },
}) }));
vi.mock('../_shared/enrichmentAuth.ts', () => ({ requireItemAccess: async () => structuredClone(state.row) }));
vi.mock('../_shared/pageExtraction.ts', () => ({ extractPage: state.extract }));
vi.mock('../_shared/tiktok.ts', () => ({ resolveTikTokLink: state.resolve, isTikTokVideoUrl: (url: string) => url.includes('tiktok.com/') }));
vi.mock('../_shared/capturedPreview.ts', () => ({ recoverCapturedPreview: state.preview }));
vi.mock('../_shared/summarize.ts', () => ({ deriveTitleFromContent: vi.fn(), generateSummary: vi.fn() }));

const shortUrl = 'https://www.tiktok.com/t/SharedVideo/';
const canonicalUrl = 'https://www.tiktok.com/@recipe.author/video/123456789012';
const creator = { name: 'Recipe Author', handle: 'recipe.author', url: 'https://www.tiktok.com/@recipe.author', platform: 'tiktok' };
const caption = 'A creator describes how to prepare a tomato salad with fresh herbs.';

beforeAll(async () => {
  vi.stubGlobal('Deno', { env: { get: (key: string) => key.startsWith('SUPABASE_') ? 'test' : undefined } });
  vi.stubGlobal('fetch', vi.fn(async () => { throw new Error('Unexpected network request'); }));
  await import('./index.ts');
});
beforeEach(() => {
  vi.clearAllMocks();
  state.row = { id: 'item-1', user_id: 'owner-1', type: 'link', url: shortUrl, title: 'Dinner idea',
    attributes: { location: { name: 'Saved at home' }, enrichment: { evidence: { existing: true } } } };
  state.extract.mockResolvedValue({ text: caption, kind: 'caption', source: 'tiktok-caption' });
  state.resolve.mockResolvedValue({ canonicalUrl, authorName: creator.name, authorHandle: creator.handle, authorUrl: creator.url });
  state.preview.mockResolvedValue(null);
  state.invoke.mockResolvedValue({ data: { success: true }, error: null });
  state.rpc.mockImplementation(async (name: string, args: any) => {
    if (name !== 'apply_enrichment_patch') throw new Error(`Unexpected RPC: ${name}`);
    // Match the production whole-item snapshot check, including attributes. An
    // early creator write would make the content write fail this same boundary.
    const matches = Object.entries(args.expected).every(([key, value]) => JSON.stringify(state.row[key] ?? null) === JSON.stringify(value));
    if (matches) {
      Object.assign(state.row, structuredClone(args.patch));
      state.row.attributes = { ...state.row.attributes, enrichment: { ...state.row.attributes.enrichment,
        evidence: { ...state.row.attributes.enrichment.evidence, ...structuredClone(args.evidence_patch) } } };
    }
    return { data: matches, error: null };
  });
});

async function scrape(body: Record<string, unknown> = {}) {
  const response = await state.handler(new Request('https://stash.example/scrape-page-content', { method: 'POST',
    headers: { authorization: 'Bearer owner-token', 'content-type': 'application/json' },
    body: JSON.stringify({ itemId: state.row.id, url: state.row.url, ...body }),
  }));
  return { status: response.status, body: await response.json() };
}

describe('scrape-page-content existing TikTok lookup creator evidence', () => {
  it('saves creator and captured content together under the original snapshot', async () => {
    expect(await scrape()).toMatchObject({ status: 200, body: { success: true, indexed: true } });
    expect(state.row).toMatchObject({ page_body: caption, attributes: { location: { name: 'Saved at home' }, enrichment: { evidence: {
      existing: true, capture_kind: 'caption', canonical_url: canonicalUrl, author: creator.name, creator,
    } } } });
    expect(state.row.attributes.enrichment.evidence).not.toHaveProperty('transcript');
    expect(state.rpc).toHaveBeenCalledTimes(1);
    expect(state.resolve).toHaveBeenCalledTimes(1);
    expect(state.extract).toHaveBeenCalledTimes(1);
    expect(state.invoke).toHaveBeenCalledWith('generate-embeddings', { body: { itemId: 'item-1' } });
    expect(fetch).not.toHaveBeenCalled();
  });

  it('retains source creator evidence even when no usable body was captured', async () => {
    state.extract.mockResolvedValue(null);
    expect(await scrape()).toMatchObject({ body: { success: false, reason: 'No usable source content' } });
    expect(state.row.attributes.enrichment.evidence).toMatchObject({ canonical_url: canonicalUrl, author: creator.name, creator });
    expect(state.row.page_body).toBeUndefined();
    expect(state.rpc).toHaveBeenCalledTimes(1);
    expect(state.invoke).not.toHaveBeenCalled();
  });

  it('can retain author-only provider metadata without inventing a canonical URL', async () => {
    state.extract.mockResolvedValue(null);
    state.resolve.mockResolvedValue({ authorName: creator.name });
    await scrape();
    expect(state.row.attributes.enrichment.evidence).toMatchObject({ author: creator.name, creator: { name: creator.name, platform: 'tiktok' } });
    expect(state.row.attributes.enrichment.evidence).not.toHaveProperty('canonical_url');
    expect(state.rpc).toHaveBeenCalledTimes(1);
  });

  it('adds creator evidence while preserving an already recovered transcript', async () => {
    state.row.page_body = 'An existing complete transcript';
    state.row.attributes.enrichment.evidence.transcript = true;
    expect(await scrape()).toMatchObject({ body: { success: true, reason: 'richer_content_preserved' } });
    expect(state.row).toMatchObject({ page_body: 'An existing complete transcript', attributes: { enrichment: { evidence: {
      transcript: true, author: creator.name, creator, canonical_url: canonicalUrl,
    } } } });
    expect(state.rpc).toHaveBeenCalledTimes(1);
    expect(state.invoke).not.toHaveBeenCalled();
  });

  it('does not infer a creator from the canonical URL or caption', async () => {
    state.resolve.mockResolvedValue({ canonicalUrl, caption: 'Made by @someone' });
    await scrape();
    expect(state.row.attributes.enrichment.evidence).not.toHaveProperty('creator');
    expect(state.row.attributes.enrichment.evidence).not.toHaveProperty('author');
  });

  it('keeps extraction-only diagnosis free of creator lookups and writes', async () => {
    expect(await scrape({ extractOnly: true })).toMatchObject({ body: { success: true, text: caption } });
    expect(state.resolve).not.toHaveBeenCalled();
    expect(state.rpc).not.toHaveBeenCalled();
    expect(state.invoke).not.toHaveBeenCalled();
  });

  it('adds no metadata lookup for full video URLs', async () => {
    state.row.url = canonicalUrl;
    state.extract.mockResolvedValue({ text: 'A complete spoken transcript', kind: 'transcript', source: 'tiktok-transcript', facts: { author: 'Transcript Author' } });
    expect(await scrape()).toMatchObject({ body: { success: true } });
    expect(state.resolve).not.toHaveBeenCalled();
    expect(state.row.attributes.enrichment.evidence).toMatchObject({ transcript: true, author: 'Transcript Author' });
    expect(state.row.attributes.enrichment.evidence).not.toHaveProperty('creator');
  });

  it.each(['caption', 'preserved transcript', 'no capture'])('rejects a stale snapshot on the %s path', async (path) => {
    if (path === 'preserved transcript') state.row.attributes.enrichment.evidence.transcript = true;
    state.resolve.mockImplementation(async () => {
      state.row.attributes.location.name = 'A concurrent user change';
      return { canonicalUrl, authorName: creator.name };
    });
    if (path === 'no capture') state.extract.mockResolvedValue(null);
    expect(await scrape()).toMatchObject({ body: { success: false, reason: 'item_changed' } });
    expect(state.row.attributes.location.name).toBe('A concurrent user change');
    expect(state.row.attributes.enrichment.evidence).not.toHaveProperty('creator');
    expect(state.row.page_body).toBeUndefined();
    expect(state.invoke).not.toHaveBeenCalled();
  });
});
