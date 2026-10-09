// @vitest-environment node
import { afterEach, describe, expect, it, vi } from 'vitest';
import { collectLiveEvidence } from './liveEvidence.ts';

const url = 'https://www.petermillar.com/p/alpine-hybrid-sweater-jacket/mf26xs49.html?dwvar_mf26xs49_color=NAV&dwvar_mf26xs49_size=XXL&quantity=1';
const item = { id: '11111111-1111-4111-8111-111111111111', url };
// Reduced regression fixture based on the reported product and its verified CDN path.
const image = 'https://res.cloudinary.com/petermillar/image/upload/t_pdp_main/v1787663789/MF26XS49_NAV.jpg';
const title = 'Alpine Hybrid Sweater Jacket';
const markdown = `# ${title}\n![Alpine Hybrid Sweater Jacket in Navy](${image})\nThe Alpine is crafted from superfine Merino wool blended with soft Italian cashmere. MF26XS49`;
const html = `<nav><img src="https://www.petermillar.com/assets/nav/new-outerwear.jpg"></nav><script type="application/ld+json">${JSON.stringify({ '@type': 'Product', name: title, url, sku: 'MF26XS49', image })}</script><main><h1>${title}</h1><img src="${image}" alt="Alpine Hybrid Sweater Jacket in Navy"></main>`;
const response = (data: any = { markdown, rawHtml: html, metadata: { title, sourceURL: url, url } }) => new Response(JSON.stringify({ success: true, data }), { headers: { 'content-type': 'application/json' } });
const fetcherFor = (r = response()) => vi.fn(async () => r) as unknown as typeof fetch & ReturnType<typeof vi.fn>;
afterEach(() => { vi.useRealTimers(); vi.unstubAllGlobals(); });

describe('bounded live page evidence', () => {
  it('preserves the saved product variant and renders once through the fixed provider', async () => {
    const fetcher = fetcherFor(); const result = await collectLiveEvidence(item, { apiKey: 'private-provider-key', fetcher });
    expect(fetcher).toHaveBeenCalledTimes(1);
    const [target, init] = fetcher.mock.calls[0];
    expect(target).toBe('https://api.firecrawl.dev/v2/scrape');
    expect(JSON.parse(init.body)).toEqual({ url, formats: ['markdown', 'rawHtml'], onlyMainContent: true, maxAge: 0, waitFor: 1000, timeout: 11000, parsers: [], storeInCache: false, skipTlsVerification: false, proxy: 'auto' });
    expect(init.redirect).toBe('error');
    expect(result).toMatchObject({ schema_version: 1, item_id: item.id, url, outcome: 'retrieved', title, text: markdown, source_truncated: false, image_candidates: [{ url: image, associated: true }] });
    expect(result.attempts).toHaveLength(1); expect(result.attempts[0].strategy).toBe('firecrawl_rendered');
    expect(result.limitations).toContain('image_pixels_not_verified');
    expect(JSON.stringify(result)).not.toContain('private-provider-key');
  });
  it.each(['http://example.com/a', 'https://127.0.0.1/a', 'https://[::1]/a', 'https://localhost/a', 'https://metadata.google.internal/a', 'https://example.com:8443/a', 'https://user:secret@example.com/a', 'https://example.com/a?access_token=secret', 'https://example.com/a?X-Amz-Signature=secret', 'https://example.com/a?%74oken=secret', 'https://example.com/a#access_token=secret'])('does not send private or credential-bearing URLs: %s', async unsafe => {
    const fetcher = fetcherFor(); const result = await collectLiveEvidence({ ...item, url: unsafe }, { apiKey: 'key', fetcher });
    expect(fetcher).not.toHaveBeenCalled(); expect(result).toMatchObject({ url: unsafe, outcome: 'unavailable', attempts: [{ reason: 'unsafe_url' }] });
    expect(JSON.stringify({ ...result, url: '' })).not.toContain('secret');
  });
  it('preserves immutable job identity for a private session URL without sending it to the provider', async () => {
    const privateUrl = 'https://private.example.com/?sessionid=private-session'; const fetcher = fetcherFor();
    const result = await collectLiveEvidence({ ...item, url: privateUrl }, { apiKey: 'provider-secret', fetcher });
    expect(result.url).toBe(privateUrl); expect(result.attempts[0].reason).toBe('unsafe_url'); expect(fetcher).not.toHaveBeenCalled();
    expect(result.text).toBe(''); expect(result.image_candidates).toEqual([]); expect(JSON.stringify(result)).not.toContain('provider-secret');
  });
  it('does not send an unconfigured provider request', async () => {
    const fetcher = fetcherFor(); const result = await collectLiveEvidence(item, { apiKey: '', fetcher });
    expect(fetcher).not.toHaveBeenCalled(); expect(result.attempts[0].reason).toBe('provider_unconfigured');
  });
  it.each(['https://www.petermillar.com/', 'https://other.example/product', url.replace('color=NAV', 'color=RED'), url.split('?')[0]])('rejects wrong source and changed variant: %s', async wrong => {
    const result = await collectLiveEvidence(item, { apiKey: 'key', fetcher: fetcherFor(response({ markdown, rawHtml: html, metadata: { title, sourceURL: url, url: wrong } })) });
    expect(result).toMatchObject({ outcome: 'mismatch', title: '', text: '', image_candidates: [], attempts: [expect.objectContaining({ reason: 'source_identity_mismatch' }), expect.objectContaining({ strategy: 'jina_reader' })] });
  });
  it('labels unknown final URL and never treats image association as visual verification', async () => {
    const result = await collectLiveEvidence(item, { apiKey: 'key', fetcher: fetcherFor(response({ markdown, rawHtml: html, metadata: { title } })) });
    expect(result.outcome).toBe('retrieved'); expect(result.limitations).toContain('final_url_not_confirmed'); expect(result.limitations).toContain('image_pixels_not_verified');
  });
  it.each([
    { title: 'Sign Up | LinkedIn', markdown: '750 million+ members | Manage your professional identity. Build and engage with your professional network.' },
    { title: 'Just a moment...', markdown: 'Checking your browser before accessing this website.' },
    { title: 'Access Denied', markdown: 'You do not have permission to access this page.' },
    { title: 'Medium', markdown: 'Sign in to read this story. Create an account to continue.' },
    { title: 'A better way to think about AI', markdown: 'Create an account to read the full story. The author made this story available to Medium members only.' },
  ])('does not promote an authwall or challenge to retrieved content: $title', async blocked => {
    const result = await collectLiveEvidence(item, { apiKey: 'key', fetcher: fetcherFor(response({ markdown: blocked.markdown, rawHtml: '<h1>Blocked</h1>', metadata: { title: blocked.title, sourceURL: url } })) });
    expect(result).toMatchObject({ outcome: 'blocked', text: '', image_candidates: [], attempts: [expect.objectContaining({ reason: 'access_wall' }), expect.objectContaining({ strategy: 'jina_reader' })] });
  });
  it('does not treat an article discussing registration as an access wall', async () => {
    const text = 'Many publishers ask visitors to create an account to read the full story. This article compares registration experiences and provides examples of effective signup forms.';
    const result = await collectLiveEvidence(item, { apiKey: 'key', fetcher: fetcherFor(response({ markdown: text, metadata: { title: 'Designing useful registration pages', url } })) });
    expect(result.outcome).toBe('retrieved'); expect(result.text).toBe(text);
  });
  it('retains real page content when a normal footer mentions reCAPTCHA', async () => {
    const result = await collectLiveEvidence(item, { apiKey: 'key', fetcher: fetcherFor(response({ markdown: `${markdown}\nProtected by reCAPTCHA`, rawHtml: html, metadata: { title, url } })) });
    expect(result.outcome).toBe('retrieved');
  });
  it('bounds evidence fields without exposing raw HTML', async () => {
    const result = await collectLiveEvidence(item, { apiKey: 'key', fetcher: fetcherFor(response({ markdown: 'a'.repeat(8000), rawHtml: html, metadata: { title: 't'.repeat(900), url } })) });
    expect(result.text).toHaveLength(6000); expect(result.title).toHaveLength(400); expect(result.source_truncated).toBe(true); expect(result.image_candidates.length).toBeLessThanOrEqual(5); expect(result).not.toHaveProperty('rawHtml');
  });
  it.each([
    new Response('not json'),
    new Response(JSON.stringify({ success: true, data: [] })),
    new Response(JSON.stringify({ success: true, data: { markdown: 42 } })),
  ])('returns a safe code for a malformed provider response', async bad => {
    const result = await collectLiveEvidence(item, { apiKey: 'key', fetcher: fetcherFor(bad) });
    expect(result).toMatchObject({ outcome: 'unavailable', attempts: [expect.objectContaining({ reason: 'invalid_provider_response' }), expect.objectContaining({ strategy: 'jina_reader' })] });
  });
  it('cancels an oversized provider stream before parsing it', async () => {
    const cancel = vi.fn(); let chunks = 0;
    const stream = new ReadableStream({ pull(controller) { chunks++; controller.enqueue(new Uint8Array(600_000)); }, cancel });
    const result = await collectLiveEvidence(item, { apiKey: 'key', fetcher: fetcherFor(new Response(stream)) });
    expect(result.attempts[0].reason).toBe('provider_response_too_large'); expect(cancel).toHaveBeenCalled(); expect(chunks).toBeLessThan(7);
  });
  it('enforces the overall deadline even if the provider never responds', async () => {
    vi.useFakeTimers(); let signal: AbortSignal | undefined;
    const fetcher = vi.fn((_url, init) => { signal = init.signal; return new Promise(() => {}); }) as unknown as typeof fetch;
    const pending = collectLiveEvidence(item, { apiKey: 'key', fetcher });
    await vi.advanceTimersByTimeAsync(24000); const result = await pending;
    expect(result.attempts[0].reason).toBe('provider_timeout'); expect(signal?.aborted).toBe(true); expect(result.attempts[0].duration_ms).toBeLessThanOrEqual(25000);
  });
  it('enforces the deadline while the response body is stalled', async () => {
    vi.useFakeTimers(); const cancel = vi.fn(); const stream = new ReadableStream({ cancel });
    const pending = collectLiveEvidence(item, { apiKey: 'key', fetcher: fetcherFor(new Response(stream)) });
    await vi.advanceTimersByTimeAsync(24000); const result = await pending;
    expect(result.attempts[0].reason).toBe('provider_timeout'); expect(cancel).toHaveBeenCalled();
  });
  it('never persists provider error messages or credentials', async () => {
    const result = await collectLiveEvidence(item, { apiKey: 'secret', fetcher: fetcherFor(new Response('Bearer secret at https://secret.example', { status: 429 })) });
    expect(result).toMatchObject({ outcome: 'unavailable', attempts: [expect.objectContaining({ reason: 'provider_rate_limited' }), expect.objectContaining({ strategy: 'jina_reader' })] }); expect(JSON.stringify(result)).not.toContain('secret');
  });
});

const jinaResponse = (target = url, content = markdown, pageTitle = title) => new Response(JSON.stringify({ code: 200, data: { url: target, title: pageTitle, content } }));
const mediumUrl = 'https://medium.com/@ifader/alighting-on-english-renaissance-poetry-f8a9e1dcf515?source=share';
const mediumImage = 'https://cdn-images-1.medium.com/max/1075/0*cover.jpeg';
const mediumFeed = `<rss><channel><item><guid>https://medium.com/p/f8a9e1dcf515</guid><link>${mediumUrl.split('?')[0]}</link><description><![CDATA[<p class="medium-feed-image"><a href="${mediumUrl.split('?')[0]}"><img src="${mediumImage}"></a></p>]]></description></item></channel></rss>`;
describe('evidence-based escalation', () => {
  it.each(['blocked', 'unavailable', 'mismatch'])('tries the reader after a %s render and keeps both strategy outcomes', async failure => {
    const first = failure === 'blocked' ? response({ markdown: 'Sign in to read this story.', metadata: { title: 'Sign In', url } }) : failure === 'mismatch' ? response({ markdown, metadata: { title, url: 'https://www.petermillar.com/' } }) : new Response('', { status: 503 });
    const fetcher = vi.fn().mockResolvedValueOnce(first).mockResolvedValueOnce(jinaResponse()) as unknown as typeof fetch & ReturnType<typeof vi.fn>;
    const result = await collectLiveEvidence(item, { apiKey: 'firecrawl-secret', jinaApiKey: 'reader-secret', fetcher } as any);
    expect(result).toMatchObject({ outcome: 'retrieved', text: markdown });
    expect(result.attempts.map(a => [a.strategy, a.outcome])).toEqual([['firecrawl_rendered', failure], ['jina_reader', 'retrieved']]);
    expect(fetcher.mock.calls[1][0]).toBe(`https://r.jina.ai/${url}`);
    expect(fetcher.mock.calls[1][1].redirect).toBe('error');
    expect(fetcher.mock.calls[1][1].headers.authorization).toBe('Bearer reader-secret');
    expect(JSON.stringify(result)).not.toMatch(/firecrawl-secret|reader-secret/);
  });
  it('does not accept the reader response after a wrong variant or hostile redirect', async () => {
    for (const wrong of [url.replace('color=NAV', 'color=RED'), url.split('?')[0], 'https://www.petermillar.com.evil.example/p/alpine.html']) {
      const fetcher = vi.fn().mockResolvedValueOnce(new Response('', { status: 503 })).mockResolvedValueOnce(jinaResponse(wrong)) as unknown as typeof fetch;
      const result = await collectLiveEvidence(item, { apiKey: 'key', fetcher });
      expect(result).toMatchObject({ outcome: 'mismatch', text: '', image_candidates: [] });
    }
  });
  it.each([
    [mediumUrl, 'https://medium.com/p/f8a9e1dcf515'],
    ['https://youtu.be/YGgNBcIgI4s?si=share-token', 'https://www.youtube.com/watch?v=YGgNBcIgI4s'],
    ['https://m.youtube.com/shorts/YGgNBcIgI4s', 'https://www.youtube.com/watch?v=YGgNBcIgI4s'],
  ])('accepts a verified same-object canonical redirect %s', async (requested, finalUrl) => {
    const fetcher = fetcherFor(response({ markdown, rawHtml: html, metadata: { title, sourceURL: requested, url: finalUrl } }));
    const result = await collectLiveEvidence({ ...item, url: requested }, { apiKey: 'key', fetcher });
    expect(result.outcome).toBe('retrieved'); expect(result.attempts).toHaveLength(1); expect(result.url).toBe(requested);
  });
  it.each([
    [mediumUrl, 'https://medium.com/p/aaaaaaaaaaaa'],
    [mediumUrl, 'https://medium.com.evil.example/p/f8a9e1dcf515'],
    [mediumUrl, 'https://medium.com/m/signin?redirect=/p/f8a9e1dcf515'],
    ['https://youtu.be/YGgNBcIgI4s', 'https://www.youtube.com/watch?v=kYkIdXwW2AE'],
    ['https://youtu.be/YGgNBcIgI4s', 'https://youtube.com.evil.example/watch?v=YGgNBcIgI4s'],
    ['https://www.youtube.com/watch?v=YGgNBcIgI4s&list=PL123', 'https://www.youtube.com/watch?v=YGgNBcIgI4s'],
  ])('rejects a mismatched canonical identity %s -> %s', async (requested, finalUrl) => {
    const fetcher = vi.fn().mockResolvedValueOnce(response({ markdown, metadata: { title, sourceURL: requested, url: finalUrl } })).mockResolvedValueOnce(jinaResponse(finalUrl)) as unknown as typeof fetch;
    const result = await collectLiveEvidence({ ...item, url: requested }, { apiKey: 'key', fetcher });
    expect(result).toMatchObject({ outcome: 'mismatch', text: '', image_candidates: [] });
  });
  it('rejects YouTube footer-only evidence and tries another source', async () => {
    const videoUrl = 'https://www.youtube.com/watch?v=YGgNBcIgI4s';
    const footer = '- YouTube About Press Copyright Contact us Creators Advertise Developers Terms Privacy Policy & Safety How YouTube works Test new features NFL Sunday Ticket &copy; 2026 Google LLC';
    const real = 'What Is Jev? The AI Model That Does Not Generate Text. This public video description explains joint embedding architectures.';
    const fetcher = vi.fn().mockResolvedValueOnce(response({ markdown: footer, metadata: { title: 'YouTube', url: videoUrl } })).mockResolvedValueOnce(jinaResponse(videoUrl, real, 'What Is Jev?')) as unknown as typeof fetch;
    const result = await collectLiveEvidence({ ...item, url: videoUrl }, { apiKey: 'key', fetcher });
    expect(result).toMatchObject({ outcome: 'retrieved', text: real });
    expect(result.attempts[0].reason).toBe('navigation_only');
    expect(result.limitations).toContain('video_not_viewed');
  });
  it('collects exact-entry public Medium artwork without claiming a blocked article was read', async () => {
    const fetcher = vi.fn().mockResolvedValueOnce(response({ markdown: 'Sign in to read this story.', metadata: { title: 'Sign In', url: mediumUrl } })).mockResolvedValueOnce(jinaResponse(mediumUrl, 'Sign in to read this story.', 'Sign In')).mockResolvedValueOnce(new Response(mediumFeed)) as unknown as typeof fetch & ReturnType<typeof vi.fn>;
    const result = await collectLiveEvidence({ ...item, url: mediumUrl }, { apiKey: 'key', fetcher });
    expect(result).toMatchObject({ outcome: 'blocked', text: '', image_candidates: [{ url: mediumImage, associated: true }] });
    expect(result.attempts.map(a => a.strategy)).toEqual(['firecrawl_rendered', 'jina_reader', 'medium_public_feed']);
    expect(result.limitations).toContain('public_feed_artwork_only');
    expect(fetcher.mock.calls[2][0]).toBe('https://medium.com/feed/@ifader');
  });
  it('bounds the whole escalation including nonresponsive providers at 23 seconds', async () => {
    vi.useFakeTimers(); const signals: AbortSignal[] = [];
    const fetcher = vi.fn((_target, init) => { signals.push(init.signal); return new Promise(() => {}); }) as unknown as typeof fetch;
    const pending = collectLiveEvidence({ ...item, url: mediumUrl }, { apiKey: 'key', fetcher });
    await vi.advanceTimersByTimeAsync(23_100); const result = await pending;
    expect(result.attempts).toHaveLength(3);
    expect(result.attempts.reduce((sum, a) => sum + a.duration_ms, 0)).toBeLessThanOrEqual(23_000);
    expect(signals.every(s => s.aborted)).toBe(true);
  });
});
