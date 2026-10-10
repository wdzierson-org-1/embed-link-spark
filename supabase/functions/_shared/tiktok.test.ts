import { describe, expect, it } from 'vitest';
import { isTikTokVideoUrl, resolveTikTokLink, titleFromCaption } from './tiktok';

const SHORTLINK = 'https://www.tiktok.com/t/ZTyAgJoM2/';
const oembedUrl = (url: string) => `https://www.tiktok.com/oembed?url=${encodeURIComponent(url)}`;

// Shape of a real oEmbed answer (2026-09-29, trimmed)
const OEMBED = {
  version: '1.0',
  type: 'video',
  title: 'We are soooooooooooo back now with part 6!!! 🤝 5 more tips, steps, hacks #adhd #therapy @someone',
  author_url: 'https://www.tiktok.com/@garthgarthgarth',
  author_name: 'Garth | Psychotherapist',
  author_unique_id: 'garthgarthgarth',
  thumbnail_url: 'https://p16-common-sign.tiktokcdn-us.com/tos-no1a-p-0037-no/okq4jB6SVQ',
  embed_product_id: '7689915860990905622',
};

const fakeFetch = (routes: Record<string, { status: number; body?: unknown }>, calls: string[] = []) =>
  (async (input: string | URL | Request) => {
    const url = typeof input === 'string' ? input : input instanceof URL ? input.toString() : input.url;
    calls.push(url);
    const route = routes[url];
    if (!route) throw new TypeError(`unrouted fetch: ${url}`);
    return new Response(route.body === undefined ? '' : JSON.stringify(route.body), {
      status: route.status,
      headers: { 'content-type': 'application/json' },
    });
  }) as typeof fetch;

describe('isTikTokVideoUrl', () => {
  it('accepts video pages and share shortlinks', () => {
    expect(isTikTokVideoUrl('https://www.tiktok.com/@garthgarthgarth/video/7689915860990905622?_r=1')).toBe(true);
    expect(isTikTokVideoUrl(SHORTLINK)).toBe(true);
    expect(isTikTokVideoUrl('https://vm.tiktok.com/ZMabc123/')).toBe(true);
    expect(isTikTokVideoUrl('https://www.tiktok.com/t/ZT9SmEa4ppAey-OPjKx/?poisharing=x')).toBe(true);
    expect(isTikTokVideoUrl('https://www.tiktok.com/@someone/photo/7689915860990905622')).toBe(true);
  });
  it('rejects profiles, other pages and other hosts', () => {
    expect(isTikTokVideoUrl('https://www.tiktok.com/@garthgarthgarth')).toBe(false);
    expect(isTikTokVideoUrl('https://www.tiktok.com/tag/adhd')).toBe(false);
    expect(isTikTokVideoUrl('https://nottiktok.com/t/ZTyAgJoM2/')).toBe(false);
    expect(isTikTokVideoUrl('not a url')).toBe(false);
  });
});

describe('titleFromCaption', () => {
  it('drops the trailing hashtag and mention run', () => {
    expect(titleFromCaption('Five tips for focus #adhd #fyp @friend')).toBe('Five tips for focus');
  });
  it('keeps tags inside the sentence', () => {
    expect(titleFromCaption('Why #adhd brains love lists')).toBe('Why #adhd brains love lists');
  });
  it('caps long captions at a word boundary', () => {
    const long = 'word '.repeat(40).trim();
    const title = titleFromCaption(long)!;
    expect(title.length).toBeLessThanOrEqual(91);
    expect(title.endsWith('…')).toBe(true);
    expect(title).not.toMatch(/ …$/);
  });
  it('returns undefined for a tags-only caption', () => {
    expect(titleFromCaption('#fyp #viral')).toBeUndefined();
  });
});

describe('resolveTikTokLink', () => {
  it('builds card metadata from oEmbed without fetching the video page', async () => {
    const calls: string[] = [];
    const result = await resolveTikTokLink(SHORTLINK, fakeFetch({ [oembedUrl(SHORTLINK)]: { status: 200, body: OEMBED } }, calls));
    expect(calls).toEqual([oembedUrl(SHORTLINK)]);
    expect(result).toEqual({
      canonicalUrl: 'https://www.tiktok.com/@garthgarthgarth/video/7689915860990905622',
      title: 'We are soooooooooooo back now with part 6!!! 🤝 5 more tips, steps, hacks',
      caption: OEMBED.title,
      authorName: 'Garth | Psychotherapist',
      authorHandle: 'garthgarthgarth',
      authorUrl: OEMBED.author_url,
      description: 'TikTok by Garth | Psychotherapist (@garthgarthgarth)',
      image: OEMBED.thumbnail_url,
      siteName: 'TikTok',
    });
  });
  it('returns null when oEmbed refuses (private or removed video)', async () => {
    expect(await resolveTikTokLink(SHORTLINK, fakeFetch({ [oembedUrl(SHORTLINK)]: { status: 400 } }))).toBeNull();
  });
  it('returns null when the fetch fails', async () => {
    expect(await resolveTikTokLink(SHORTLINK, fakeFetch({}))).toBeNull();
  });
  it('never calls out for non-TikTok URLs', async () => {
    const calls: string[] = [];
    expect(await resolveTikTokLink('https://example.com/a', fakeFetch({}, calls))).toBeNull();
    expect(calls).toEqual([]);
  });
  it('falls back to the canonical form when a shortlink redirects to the mobile page', async () => {
    const MOBILE = 'https://www.tiktok.com/t/ZTyrNGAGy/';
    const canonical = 'https://www.tiktok.com/@_/video/7611949468442742030';
    const calls: string[] = [];
    const routes: Record<string, Response> = {
      [oembedUrl(MOBILE)]: new Response('{"code":400}', { status: 400 }),
      [MOBILE]: new Response(null, { status: 301, headers: { location: 'https://m.tiktok.com/v/7611949468442742030.html?_t=x' } }),
      [oembedUrl(canonical)]: new Response(JSON.stringify({ ...OEMBED, title: 'Medicube tips' }), { status: 200 }),
    };
    const fetcher = (async (input: string | URL | Request) => {
      const url = typeof input === 'string' ? input : input instanceof URL ? input.toString() : input.url;
      calls.push(url);
      const hit = routes[url];
      if (!hit) throw new TypeError(`unrouted fetch: ${url}`);
      return hit;
    }) as typeof fetch;
    const result = await resolveTikTokLink(MOBILE, fetcher);
    expect(calls).toEqual([oembedUrl(MOBILE), MOBILE, oembedUrl(canonical)]);
    expect(result?.title).toBe('Medicube tips');
  });
  it('does not chase redirects for full video URLs', async () => {
    const full = 'https://www.tiktok.com/@a/video/7689915860990905622';
    const calls: string[] = [];
    expect(await resolveTikTokLink(full, fakeFetch({ [oembedUrl(full)]: { status: 400 } }, calls))).toBeNull();
    expect(calls).toEqual([oembedUrl(full)]);
  });
  it('keeps the creator when the caption is empty', async () => {
    const result = await resolveTikTokLink(SHORTLINK, fakeFetch({ [oembedUrl(SHORTLINK)]: { status: 200, body: { ...OEMBED, title: '' } } }));
    expect(result?.title).toBeUndefined();
    expect(result?.caption).toBeUndefined();
    expect(result?.description).toBe('TikTok by Garth | Psychotherapist (@garthgarthgarth)');
  });
  it('retains an explicit handle even if other oEmbed fields are absent', async () => {
    const result = await resolveTikTokLink(SHORTLINK, fakeFetch({ [oembedUrl(SHORTLINK)]: { status: 200, body: { author_unique_id: 'author' } } }));
    expect(result?.authorHandle).toBe('author');
    expect(result?.authorName).toBeUndefined();
    expect(result?.authorUrl).toBeUndefined();
  });
  it.each(['https://elsewhere.example/@author', 'javascript:alert(1)', 'https://user:secret@www.tiktok.com/@author',
    'https://www.tiktok.com/@author?token=secret'])('does not persist an unsafe creator URL: %s', async (author_url) => {
      const result = await resolveTikTokLink(SHORTLINK, fakeFetch({ [oembedUrl(SHORTLINK)]: { status: 200, body: { ...OEMBED, author_url } } }));
      expect(result?.authorUrl).toBeUndefined();
      expect(result?.canonicalUrl).toBeUndefined();
    });
});

describe('tikTokCaption (maintenance social adapter)', () => {
  it('returns the caption through the shared resolver', async () => {
    const { tikTokCaption } = await import('./socialEnrichment');
    const result = await tikTokCaption(SHORTLINK, fakeFetch({ [oembedUrl(SHORTLINK)]: { status: 200, body: OEMBED } }));
    expect(result).toEqual({
      text: OEMBED.title,
      canonical: 'https://www.tiktok.com/@garthgarthgarth/video/7689915860990905622',
      evidence: { author: OEMBED.author_name, creator: { name: OEMBED.author_name, handle: OEMBED.author_unique_id, url: OEMBED.author_url, platform: 'tiktok' } },
    });
  });
});
