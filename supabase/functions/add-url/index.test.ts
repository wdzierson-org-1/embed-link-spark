// @vitest-environment node
import { beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';

const state = vi.hoisted(() => ({
  handler: null as any,
  row: null as any,
  background: [] as Promise<unknown>[],
  rpc: vi.fn(), invoke: vi.fn(), tiktok: vi.fn(),
}));
vi.mock('https://esm.sh/@supabase/supabase-js@2.50.2', () => ({
  createClient: () => ({
    auth: { getUser: async () => ({ data: { user: { id: 'owner-1' } }, error: null }) },
    from: () => ({
      insert: (row: any) => { state.row = { id: 'item-1', ...structuredClone(row) }; return { select: () => ({ single: async () => ({ data: structuredClone(state.row), error: null }) }) }; },
      select: () => ({ eq: () => ({ single: async () => ({ data: structuredClone(state.row), error: null }) }) }),
    }),
    rpc: state.rpc, functions: { invoke: state.invoke },
    storage: { from: () => ({ upload: async () => ({ error: null }) }) },
  }),
}));
vi.mock('../_shared/agentToken.ts', () => ({ isAgentToken: () => false }));
vi.mock('../_shared/entitlementGate.ts', () => ({ requireEntitlement: async () => null }));
vi.mock('../_shared/youtube.ts', () => ({ resolveYouTubeLink: async () => null }));
vi.mock('../_shared/tiktok.ts', () => ({ resolveTikTokLink: state.tiktok }));

const source = 'https://shop.example/jacket';
const facts = { version: 1, beta: true, kind: 'product', name: 'Alpine Jacket', product: { brand: 'Example', sku: 'ALPINE-NAV', offer: { price: '748', currency: 'USD' } },
  evidence: { source_url: source, observed_at: '2026-10-10T12:00:00Z', method: 'json-ld', extraction_version: 'object-facts-v1', schema_type: 'Product' } };
beforeAll(async () => {
  vi.stubGlobal('Deno', { env: { get: () => 'test' }, serve: (handler: any) => { state.handler = handler; } });
  vi.stubGlobal('EdgeRuntime', { waitUntil: (promise: Promise<unknown>) => state.background.push(promise) });
  vi.stubGlobal('fetch', vi.fn(async () => new Response('Unavailable', { status: 503 })));
  await import('./index.ts');
});
beforeEach(() => {
  vi.clearAllMocks(); state.row = null; state.background = [];
  state.tiktok.mockResolvedValue(null);
  state.invoke.mockImplementation(async (name: string) => ({ data: name === 'extract-link-metadata' ? {
    title: 'Alpine Jacket', description: 'A navy wool jacket with a removable insulated hood.',
    previewImagePath: 'owner-1/previews/alpine.jpg', objectFacts: structuredClone(facts),
  } : { success: true }, error: null }));
  state.rpc.mockImplementation(async (name: string, args: any) => {
    if (name === 'apply_enrichment_patch') {
      // The real RPC compares every field in itemSnapshot, including attributes.
      // Model that persistence boundary, rather than mocking applyCandidate success.
      const matches = Object.entries(args.expected).every(([key, value]) => JSON.stringify(state.row[key] ?? null) === JSON.stringify(value));
      if (matches) Object.assign(state.row, structuredClone(args.patch));
      return { data: matches, error: null };
    }
    if (name === 'set_item_object_facts') {
      const matches = args.expected_url === state.row.url && args.facts.evidence.source_url === args.expected_url &&
        JSON.stringify(state.row.attributes?.object_facts ?? null) === JSON.stringify(args.expected_facts);
      if (matches) state.row.attributes.object_facts = structuredClone(args.facts);
      return { data: matches, error: null };
    }
    return { data: null, error: null };
  });
});

async function save(body: Record<string, unknown> = {}) {
  const response = await state.handler(new Request('https://stash.example/add-url', { method: 'POST',
    headers: { authorization: 'Bearer owner-token', 'content-type': 'application/json' },
    body: JSON.stringify({ url: source, attributes: { location: { name: 'Saved at home' } }, ...body }),
  }));
  await Promise.all(state.background); return response;
}
const invoked = () => state.invoke.mock.calls.map(([name]) => name);
const settledStatus = () => state.rpc.mock.calls.find(([name]) => name === 'set_item_enrichment')?.[1].next_status;

describe('add-url source creator evidence', () => {
  const url = 'https://www.tiktok.com/t/SharedVideo/';
  const caption = 'A creator describes how to prepare a tomato salad with fresh herbs.';
  it('persists the oEmbed creator independently from descriptive prose', async () => {
    state.tiktok.mockResolvedValue({ title: 'Tomato salad', caption, authorName: 'Recipe Author', authorHandle: 'recipe.author',
      authorUrl: 'https://www.tiktok.com/@recipe.author', siteName: 'TikTok', canonicalUrl: 'https://www.tiktok.com/@recipe.author/video/123456789012' });
    expect((await save({ url, title: 'Dinner idea' })).status).toBe(200);
    expect(state.row).toMatchObject({ title: 'Dinner idea', page_body: caption, attributes: {
      location: { name: 'Saved at home' }, enrichment: { protected_fields: { title: true }, evidence: {
        author: 'Recipe Author', creator: { name: 'Recipe Author', handle: 'recipe.author', url: 'https://www.tiktok.com/@recipe.author', platform: 'tiktok' },
      } },
    } });
    expect(state.row.attributes.enrichment.evidence).not.toHaveProperty('transcript');
    // The scrape (transcript, summary) runs for a TikTok like for every link; only the deep
    // metadata pass is skipped, oEmbed having covered it
    expect(invoked()).toEqual(['generate-embeddings', 'scrape-page-content']);
    expect(state.rpc.mock.calls.map(([name]) => name)).toEqual(['set_item_enrichment']);
  });
  it('does not infer a creator from a caption, user attributes or URL', async () => {
    state.tiktok.mockResolvedValue({ title: 'A clip by @someone', caption, siteName: 'TikTok' });
    expect((await save({ url: 'https://www.tiktok.com/@guess/video/123456789012',
      attributes: { enrichment: { evidence: { author: 'Spoofed author', creator: { name: 'Spoofed author' } } } },
    })).status).toBe(200);
    expect(state.row.attributes.enrichment.evidence?.creator).toBeUndefined();
    expect(state.row.attributes.enrichment.evidence?.author).toBeUndefined();
  });
});

describe('add-url product facts and preview persistence', () => {
  it('saves facts alongside the real title, description and owned preview under snapshot CAS', async () => {
    expect((await save()).status).toBe(200);
    expect(state.row).toMatchObject({ title: 'Alpine Jacket', description: 'A navy wool jacket with a removable insulated hood.', file_path: 'owner-1/previews/alpine.jpg',
      attributes: { location: { name: 'Saved at home' }, object_facts: { kind: 'product', product: { sku: 'ALPINE-NAV', offer: { price: '748', currency: 'USD' } } } } });
    expect(state.rpc.mock.calls.map(([name]) => name)).toEqual(['apply_enrichment_patch', 'set_item_object_facts', 'set_item_enrichment']);
  });
  it('preserves the user title while adding object facts and an owned preview', async () => {
    expect((await save({ title: 'My winter shortlist' })).status).toBe(200);
    expect(state.row).toMatchObject({ title: 'My winter shortlist', file_path: 'owner-1/previews/alpine.jpg', attributes: { enrichment: { protected_fields: { title: true } }, object_facts: { kind: 'product' } } });
    expect(state.rpc.mock.calls.find(([name]) => name === 'apply_enrichment_patch')?.[1].patch).not.toHaveProperty('title');
  });
});

describe('add-url TikTok: the same pipeline as every other link', () => {
  const shortLink = 'https://www.tiktok.com/t/ZTygmPyEv/';
  const resolved = {
    canonicalUrl: 'https://www.tiktok.com/@katina.bajaj/video/7685488427462167838',
    title: 'Are our creative brains eating mental junk food?', caption: 'Are our creative brains eating mental junk food? Full caption here.',
    description: 'TikTok by Katina Bajaj (@katina.bajaj)', image: null, siteName: 'TikTok',
  };
  beforeEach(() => { state.tiktok.mockResolvedValue(resolved); });

  it('runs the scrape (transcript, summary) after the response, skipping only the deep metadata pass oEmbed already covered', async () => {
    expect((await save({ url: shortLink })).status).toBe(200);
    expect(state.row).toMatchObject({ page_body: resolved.caption, attributes: { link: { canonical_url: resolved.canonicalUrl }, enrichment: { status: 'pending' } } });
    expect(invoked()).toEqual(['generate-embeddings', 'scrape-page-content']);
    expect(state.invoke.mock.calls.find(([name]) => name === 'scrape-page-content')?.[1].body).toEqual({ itemId: 'item-1', url: shortLink, caption: resolved.caption });
    expect(settledStatus()).toBe('complete');
  });

  it('stays complete when there is nothing to transcribe — the caption is the content', async () => {
    state.invoke.mockImplementation(async (name: string) => ({ data: name === 'scrape-page-content' ? { success: false, reason: 'No usable source content' } : { success: true }, error: null }));
    await save({ url: shortLink });
    expect(settledStatus()).toBe('complete');
  });

  it('is partial when the scrape itself fails', async () => {
    state.invoke.mockImplementation(async (name: string) => (name === 'scrape-page-content' ? { data: null, error: new Error('boom') } : { data: { success: true }, error: null }));
    await save({ url: shortLink });
    expect(settledStatus()).toBe('partial');
  });
});
