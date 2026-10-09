import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
const adapters = vi.hoisted(() => ({ html: vi.fn(), jina: vi.fn(), wayback: vi.fn() }));
vi.mock('./blockedContentFallbacks.ts', () => ({
  CRAWLER_UA: 'test-crawler',
  fetchHtml: adapters.html,
  fetchViaJinaReader: adapters.jina,
  fetchViaWayback: adapters.wayback,
  htmlToText: (html: string) => html,
}));
import { extractPage } from './pageExtraction';
const url = 'https://www.youtube.com/watch?v=YGgNBcIgI4s';
const footer = '- YouTube About Press Copyright Contact us Creators Advertise Developers Terms Privacy Policy & Safety How YouTube works Test new features NFL Sunday Ticket &copy; 2026 Google LLC';
beforeEach(() => {
  vi.clearAllMocks();
  adapters.html.mockResolvedValue(footer);
  adapters.jina.mockResolvedValue({ content: footer });
  vi.stubGlobal('fetch', vi.fn().mockResolvedValue(new Response(JSON.stringify({ data: { markdown: footer } }), { status: 200 })));
});
afterEach(() => vi.unstubAllGlobals());
describe('YouTube content fallback', () => {
  it('continues past footer-only provider results to actual video content', async () => {
    const caption = 'Pick ripe tomatoes, salt them, and finish with olive oil.';
    adapters.jina.mockResolvedValue({ content: caption });
    expect(await extractPage(url, 'test-key')).toMatchObject({ text: caption, source: 'jina-reader' });
    expect(adapters.html).toHaveBeenCalledTimes(2);
    expect(adapters.jina).toHaveBeenCalledWith(url);
  });
  it('returns no content when every provider returned only the footer', async () => {
    expect(await extractPage(url, 'test-key')).toBeNull();
    expect(adapters.jina).toHaveBeenCalledWith(url);
    expect(adapters.wayback).not.toHaveBeenCalled();
  });
});
