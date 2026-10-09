import { describe, expect, it, vi } from 'vitest';
import { fetchMediumFeedPreview } from './mediumFeedPreview.ts';
const url = 'https://medium.com/@ifader/alighting-on-english-renaissance-poetry-f8a9e1dcf515';
const image = 'https://cdn-images-1.medium.com/max/1075/0*cUmCqjVJrw9s4k47.jpeg';
const entry = (opts: { guid?: string; link?: string; imageLink?: string; image?: string; imageClass?: string } = {}) => `<item>
  <title>Alighting on English Renaissance Poetry</title>
  <guid>${opts.guid ?? 'https://medium.com/p/f8a9e1dcf515'}</guid>
  <link>${opts.link ?? `${url}?source=rss-22537f5ee152------2`}</link>
  <description><![CDATA[<div class="medium-feed-item"><p class="${opts.imageClass ?? 'medium-feed-image'}"><a href="${opts.imageLink ?? url}"><img src="${opts.image ?? image}" width="1075"></a></p><p class="medium-feed-snippet">Public subtitle</p><p class="medium-feed-link"><a href="${url}">Continue reading on Medium</a></p></div>]]></description>
</item>`;
const feed = (items = entry()) => `<rss version="2.0"><channel>${items}</channel></rss>`;
const fetchFeed = (body = feed()) => vi.fn().mockResolvedValue(new Response(body));
describe('public Medium author-feed preview', () => {
  it('accepts only the exact article entry and its linked feed-image', async () => {
    const fetcher = fetchFeed(feed(entry({ guid: 'https://medium.com/p/123456789abc', link: 'https://medium.com/@ifader/another-123456789abc' }) + entry()));
    expect(await fetchMediumFeedPreview(url, fetcher)).toBe(image);
    expect(fetcher).toHaveBeenCalledOnce();
    expect(fetcher).toHaveBeenCalledWith('https://medium.com/feed/@ifader', expect.objectContaining({ redirect: 'error', signal: expect.any(AbortSignal) }));
  });
  it.each([
    'https://medium.com.evil.example/@ifader/poetry-f8a9e1dcf515',
    'https://publication.medium.com/poetry-f8a9e1dcf515',
    'https://medium.com/@ifader', 'https://medium.com/@ifader/article-without-id',
    'https://user:password@medium.com/@ifader/poetry-f8a9e1dcf515',
    'http://medium.com/@ifader/poetry-f8a9e1dcf515',
    'https://medium.com/@ifader%2fother/poetry-f8a9e1dcf515',
  ])('does not request a feed for unsupported source %s', async source => {
    const fetcher = fetchFeed();
    expect(await fetchMediumFeedPreview(source, fetcher)).toBeNull(); expect(fetcher).not.toHaveBeenCalled();
  });
  it.each([
    { guid: 'https://medium.com/p/123456789abc' },
    { guid: 'https://medium.com.evil.example/p/f8a9e1dcf515' },
    { link: 'https://medium.com/@other/another-f8a9e1dcf515' },
    { imageLink: 'https://medium.com/@ifader' },
    { imageClass: 'author-avatar' },
    { image: 'https://127.0.0.1/profile.jpg' },
    { image: 'https://cdn-images-1.medium.com.evil.example/profile.jpg' },
  ])('rejects another entry, byline or unsupported image: %j', async options => {
    expect(await fetchMediumFeedPreview(url, fetchFeed(feed(entry(options))))).toBeNull();
  });
  it('decodes XML-escaped HTML without reading linked article content', async () => {
    const encoded = entry().replace(/<!\[CDATA\[([\s\S]*?)\]\]>/, (_, html: string) => html.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;'));
    const fetcher = fetchFeed(feed(encoded));
    expect(await fetchMediumFeedPreview(`${url}?source=share`, fetcher)).toBe(image);
    expect(fetcher).toHaveBeenCalledOnce();
  });
  it.each([
    () => new Response('no', { status: 403 }),
    () => new Response('redirect', { status: 302, headers: { Location: 'https://example.com/feed' } }),
    () => new Response(feed(), { headers: { 'Content-Length': '2000001' } }),
    () => new Response('x'.repeat(2000001)),
  ])('rejects unsuccessful, redirected or oversized feeds', async response => {
    const fetcher = vi.fn().mockResolvedValue(response());
    expect(await fetchMediumFeedPreview(url, fetcher)).toBeNull(); expect(fetcher).toHaveBeenCalledOnce();
  });
  it('aborts its only feed request after five seconds', async () => {
    vi.useFakeTimers();
    try {
      const fetcher = vi.fn((_url: string, options: RequestInit) => new Promise<Response>((_resolve, reject) => {
        options.signal!.addEventListener('abort', () => reject(new Error('aborted')));
      }));
      const result = fetchMediumFeedPreview(url, fetcher as typeof fetch);
      await vi.advanceTimersByTimeAsync(5000);
      expect(await result).toBeNull(); expect(fetcher).toHaveBeenCalledOnce();
    } finally { vi.useRealTimers(); }
  });
});
