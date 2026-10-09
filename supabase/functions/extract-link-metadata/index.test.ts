// @vitest-environment node
import { beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
const state = vi.hoisted(() => ({ handler: null as any, html: '', jina: null as any, fetcher: vi.fn() }));
vi.mock('https://deno.land/x/xhr@0.1.0/mod.ts', () => ({}));
vi.mock('https://deno.land/std@0.168.0/http/server.ts', () => ({ serve: (handler: any) => { state.handler = handler; } }));
vi.mock('../_shared/blockedContentFallbacks.ts', async original => ({ ...await original<any>(), fetchHtml: async () => null, fetchViaJinaReader: async () => state.jina }));
vi.mock('https://esm.sh/@supabase/supabase-js@2.50.2', () => ({ createClient: vi.fn() }));
beforeAll(async () => {
  vi.stubGlobal('Deno', { env: { get: () => undefined } });
  vi.stubGlobal('fetch', state.fetcher);
  await import('./index.ts');
});
beforeEach(() => { vi.clearAllMocks(); state.jina = null; state.fetcher.mockImplementation(async () => new Response(state.html)); });
const url = 'https://www.petermillar.com/p/alpine-hybrid-sweater-jacket/197889736936.html';
const image = 'https://res.cloudinary.com/petermillar/image/upload/t_pdp_main/v1787663789/MF26XS49_NAV.jpg';
const request = (fastOnly = true, sourceUrl = url) => new Request('https://stash.example/extract-link-metadata', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ url: sourceUrl, fastOnly }) });
describe('legacy metadata endpoint product image selection', () => {
  it('uses the current Product in JSON-LD graph instead of the first page-wide navigation image', async () => {
    state.html = `<title>Alpine Hybrid Sweater Jacket</title><meta name="description" content="Warm wool jacket with insulated sleeves.">
      <nav><img src="https://example.com/navigation/new-outerwear.jpg"></nav>
      <script type="application/ld+json">${JSON.stringify({ '@graph': [{ '@type': 'WebSite', name: 'Peter Millar' }, { '@type': 'Product', name: 'Alpine Hybrid Sweater Jacket', url, image }] })}</script>
      <main><h1>Alpine Hybrid Sweater Jacket</h1><p>The Alpine Hybrid Sweater Jacket has a warm wool body and insulated sleeves.</p></main>`;
    const result = await (await state.handler(request())).json();
    expect(result).toMatchObject({ success: true, title: 'Alpine Hybrid Sweater Jacket', image });
  });
  it('does not substitute a navigation promotion when the source has no associated product image', async () => {
    state.html = `<title>Alpine Hybrid Sweater Jacket</title><meta name="description" content="Warm wool jacket with insulated sleeves."><nav><img src="https://example.com/nav/new-outerwear.jpg"></nav><main><h1>Alpine Hybrid Sweater Jacket</h1><p>Product information and sizing details.</p></main>`;
    const result = await (await state.handler(request())).json();
    expect(result.title).toBe('Alpine Hybrid Sweater Jacket');
    expect(result.image).toBeUndefined();
  });
  it('rejects a navigation image returned by the deep error-rescue branch', async () => {
    state.fetcher.mockResolvedValue(new Response('Unavailable', { status: 403 }));
    state.jina = { title: 'Alpine Hybrid Sweater Jacket', description: 'Warm wool jacket with insulated sleeves.', image: 'https://example.com/navigation/new-outerwear.jpg' };
    const result = await (await state.handler(request(false))).json();
    expect(result.title).toBe('Alpine Hybrid Sweater Jacket');
    expect(result.image).toBeUndefined();
  });
  it.each([
    'https://www.petermillar.com/nav/2026/10-oct/new-outerwear.jpg',
    'https://www.petermillar.com/campaign.jpg',
    image.replace('MF26XS49_NAV', 'MF26XS49_RED'),
  ])('uses the selected jacket in Jina content ahead of its first image %s', async firstImage => {
    state.fetcher.mockResolvedValue(new Response('Unavailable', { status: 403 }));
    state.jina = { title: 'Alpine Hybrid Sweater Jacket', description: 'Warm wool jacket with insulated sleeves.', image: firstImage,
      content: `![New outerwear](https://www.petermillar.com/nav/2026/10-oct/new-outerwear.jpg)\n# Alpine Hybrid Sweater Jacket\n![Alpine Hybrid Sweater Jacket in Red](${image.replace('MF26XS49_NAV', 'MF26XS49_RED')})\n![Alpine Hybrid Sweater Jacket in Navy](${image})\n## Style With\n![Alpine Hybrid Sweater Jacket styled with belt](https://www.petermillar.com/belt.jpg)` };
    const sourceUrl = 'https://www.petermillar.com/p/alpine-hybrid-sweater-jacket/mf26xs49.html?dwvar_mf26xs49_color=NAV&dwvar_mf26xs49_size=XXL&quantity=1';
    const result = await (await state.handler(request(false, sourceUrl))).json();
    expect(result).toMatchObject({ success: true, title: 'Alpine Hybrid Sweater Jacket', image, strategyUsed: 'jina-reader-rescue' });
  });
  it.each([
    [image, image],
    [image.replace('MF26XS49_NAV', 'MF26XS49_RED'), undefined],
    ['http://images.example.com/jacket.jpg', undefined],
    ['https://127.0.0.1/jacket.jpg', undefined],
  ])('validates Jina image fallback when no content image exists: %s', async (candidate, expected) => {
    state.fetcher.mockResolvedValue(new Response('Unavailable', { status: 403 }));
    state.jina = { title: 'Alpine Hybrid Sweater Jacket', description: 'Warm wool jacket with insulated sleeves.', image: candidate };
    const result = await (await state.handler(request(false, `${url}?dwvar_mf26xs49_color=NAV`))).json();
    expect(result.image).toBe(expected);
  });

});
