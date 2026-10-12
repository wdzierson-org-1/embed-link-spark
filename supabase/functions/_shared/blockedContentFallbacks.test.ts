import { afterEach, describe, expect, it, vi } from 'vitest';
import { fetchViaJinaReader, verifyRemoteImage } from './blockedContentFallbacks';

describe('remote preview verification', () => {
  afterEach(() => vi.unstubAllGlobals());

  it.each([
    'https://emoji.discourse-cdn.com/twitter/frowning.png?v=15',
    'https://community.openai.com/images/emoji/twitter/frowning.png?v=15',
    'https://community.openai.com/plugins/discourse-reactions/images/heart.png',
  ])('rejects decorative forum assets before fetching them: %s', async image => {
    const fetcher = vi.fn(async () => new Response(new Uint8Array(1000), { headers: { 'content-type': 'image/png' } }));
    vi.stubGlobal('fetch', fetcher);
    expect(await verifyRemoteImage(image)).toBe(false);
    expect(fetcher).not.toHaveBeenCalled();
  });

  it.each([
    'https://us1.discourse-cdn.com/openai1/original/4X/d/8/c/d8cf6e3a0407f847f9785a3f45949a8bad13bf73.jpeg',
    'https://shop.example/products/emoji-reaction-tote.jpg',
    'https://media.licdn.com/dms/image/v2/person/profile-displayphoto-shrink_200_200/photo.jpg',
    'https://avatars.discourse-cdn.com/v4/letter/a/abcdef/48.png',
    'https://us1.discourse-cdn.com/openai1/user_avatar/community.openai.com/person/96/12345.png',
    'https://community.openai.com/user_avatar/community.openai.com/person/96/12345.png',
  ])('continues to verify actual article, product and profile candidates: %s', async image => {
    const fetcher = vi.fn(async () => new Response(new Uint8Array(1000), { headers: { 'content-type': 'image/jpeg' } }));
    vi.stubGlobal('fetch', fetcher);
    expect(await verifyRemoteImage(image)).toBe(true);
    expect(fetcher).toHaveBeenCalledOnce();
  });
});


describe('reader publisher preview metadata', () => {
  afterEach(() => vi.unstubAllGlobals());
  const url = 'https://community.openai.com/t/decisions-api-is-now-available-in-public-beta/1403877';
  const article = 'https://us1.discourse-cdn.com/openai1/optimized/4X/d/8/c/d8cf6e3a0407f847f9785a3f45949a8bad13bf73_2_1024x576.jpeg';
  const emoji = 'https://emoji.discourse-cdn.com/twitter/frowning.png?v=15';
  const content = `A reader discusses access to the API and asks when the Python SDK will be available. ![:frowning:](${emoji})`;
  const read = async (metadata: unknown, responseUrl = url) => {
    vi.stubGlobal('Deno', { env: { get: () => undefined } });
    vi.stubGlobal('fetch', vi.fn(async () => Response.json({ data: {
      url: responseUrl, title: 'Decisions API is now available in Public Beta', content,
      images: { logo: 'https://example.com/logo.png', reaction: emoji }, metadata,
    } })));
    return fetchViaJinaReader(url);
  };
  it('retains the publisher image when readable text contains only replies', async () => {
    expect(await read({ 'og:image': article })).toMatchObject({ publisherImage: article, content });
  });
  it('accepts a publisher Twitter image when Open Graph is absent', async () => {
    expect((await read({ 'twitter:image': article }))?.publisherImage).toBe(article);
  });
  it.each([
    { 'og:image': emoji },
    { 'og:image': 'http://127.0.0.1/image.png' },
    { 'og:image': 'https://miro.medium.com/v2/resize:fill:48:48/1*author.jpeg' },
    { 'og:image': { unexpected: article } },
  ])('does not trust unsafe or decorative publisher metadata: %j', async metadata => {
    expect((await read(metadata))?.publisherImage).toBeUndefined();
  });
  it('does not attribute a different response page image to the requested article', async () => {
    expect((await read({ 'og:image': article }, 'https://example.com/sign-in'))?.publisherImage).toBeUndefined();
  });
});
