import { describe, expect, it } from 'vitest';
import {
  fetchYouTubeOEmbed,
  getYouTubeVideoId,
  pickYouTubeThumbnail,
  resolveYouTubeLink,
  youtubeThumbnailCandidates,
} from './youtube';

type Route = { status: number; contentType?: string; body?: string };

// A fetch stand-in keyed by URL. YouTube's thumbnail host answers a missing
// variant with HTTP 404 *and* an image/jpeg placeholder body, so the status
// code is what must decide — mirror that here.
const fakeFetch = (routes: Record<string, Route>, calls: string[] = []) =>
  (async (input: string | URL | Request, init?: RequestInit) => {
    const url = typeof input === 'string' ? input : input instanceof URL ? input.toString() : input.url;
    calls.push(`${init?.method ?? 'GET'} ${url}`);
    const route = routes[url];
    if (!route) throw new TypeError(`unrouted fetch: ${url}`);
    return new Response(route.body ?? '', {
      status: route.status,
      headers: { 'content-type': route.contentType ?? 'image/jpeg' },
    });
  }) as typeof fetch;

describe('getYouTubeVideoId', () => {
  it('reads the v= query on watch URLs', () => {
    expect(getYouTubeVideoId('https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=42s')).toBe('dQw4w9WgXcQ');
  });

  it('reads the path on youtu.be short links', () => {
    expect(getYouTubeVideoId('https://youtu.be/dQw4w9WgXcQ?si=abc')).toBe('dQw4w9WgXcQ');
  });

  it('reads shorts, embed, and live paths', () => {
    expect(getYouTubeVideoId('https://www.youtube.com/shorts/tPEE9ZwTmy0')).toBe('tPEE9ZwTmy0');
    expect(getYouTubeVideoId('https://www.youtube.com/embed/dQw4w9WgXcQ')).toBe('dQw4w9WgXcQ');
    expect(getYouTubeVideoId('https://www.youtube.com/live/dQw4w9WgXcQ')).toBe('dQw4w9WgXcQ');
  });

  it('accepts mobile and music subdomains', () => {
    expect(getYouTubeVideoId('https://m.youtube.com/watch?v=dQw4w9WgXcQ')).toBe('dQw4w9WgXcQ');
    expect(getYouTubeVideoId('https://music.youtube.com/watch?v=dQw4w9WgXcQ')).toBe('dQw4w9WgXcQ');
  });

  it('returns null for non-YouTube hosts and YouTube pages that are not a video', () => {
    expect(getYouTubeVideoId('https://vimeo.com/123456')).toBeNull();
    expect(getYouTubeVideoId('https://notyoutube.com/watch?v=dQw4w9WgXcQ')).toBeNull();
    expect(getYouTubeVideoId('https://www.youtube.com/@lexfridman')).toBeNull();
    expect(getYouTubeVideoId('https://youtu.be/')).toBeNull();
  });

  it('rejects ids that are not the 11-char YouTube form', () => {
    expect(getYouTubeVideoId('https://www.youtube.com/watch?v=short')).toBeNull();
    expect(getYouTubeVideoId('https://youtu.be/has%20space%20x')).toBeNull();
  });

  it('returns null for unparseable input', () => {
    expect(getYouTubeVideoId('not a url')).toBeNull();
  });
});

describe('youtubeThumbnailCandidates', () => {
  it('lists the 16:9 variants before the letterboxed default, all on i.ytimg.com', () => {
    expect(youtubeThumbnailCandidates('dQw4w9WgXcQ')).toEqual([
      'https://i.ytimg.com/vi/dQw4w9WgXcQ/maxresdefault.jpg',
      'https://i.ytimg.com/vi/dQw4w9WgXcQ/hq720.jpg',
      'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg',
    ]);
  });
});

describe('pickYouTubeThumbnail', () => {
  const [maxres, hq720, hqdefault] = youtubeThumbnailCandidates('dQw4w9WgXcQ');

  it('returns the max-resolution image when it exists, without probing the rest', async () => {
    const calls: string[] = [];
    const fetchImpl = fakeFetch({ [maxres]: { status: 200 } }, calls);
    await expect(pickYouTubeThumbnail('dQw4w9WgXcQ', fetchImpl)).resolves.toBe(maxres);
    expect(calls).toEqual([`HEAD ${maxres}`]);
  });

  it('falls back through hq720 to hqdefault when higher variants answer 404', async () => {
    const fetchImpl = fakeFetch({
      [maxres]: { status: 404 },
      [hq720]: { status: 404 },
      [hqdefault]: { status: 200 },
    });
    await expect(pickYouTubeThumbnail('dQw4w9WgXcQ', fetchImpl)).resolves.toBe(hqdefault);
  });

  it('skips a variant that answers 200 with a non-image body', async () => {
    const fetchImpl = fakeFetch({
      [maxres]: { status: 200, contentType: 'text/html' },
      [hq720]: { status: 200 },
    });
    await expect(pickYouTubeThumbnail('dQw4w9WgXcQ', fetchImpl)).resolves.toBe(hq720);
  });

  it('returns null when every variant is missing or the host is unreachable', async () => {
    await expect(
      pickYouTubeThumbnail(
        'dQw4w9WgXcQ',
        fakeFetch({ [maxres]: { status: 404 }, [hq720]: { status: 404 }, [hqdefault]: { status: 404 } }),
      ),
    ).resolves.toBeNull();
    await expect(pickYouTubeThumbnail('dQw4w9WgXcQ', fakeFetch({}))).resolves.toBeNull();
  });
});

describe('fetchYouTubeOEmbed', () => {
  const oembedUrl =
    'https://www.youtube.com/oembed?url=https%3A%2F%2Fwww.youtube.com%2Fwatch%3Fv%3DdQw4w9WgXcQ&format=json';

  it('returns title, author, and thumbnail from the oEmbed document', async () => {
    const fetchImpl = fakeFetch({
      [oembedUrl]: {
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          title: 'Never Gonna Give You Up',
          author_name: 'Rick Astley',
          thumbnail_url: 'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg',
        }),
      },
    });
    await expect(fetchYouTubeOEmbed('dQw4w9WgXcQ', fetchImpl)).resolves.toEqual({
      title: 'Never Gonna Give You Up',
      authorName: 'Rick Astley',
      thumbnailUrl: 'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg',
    });
  });

  it('returns null on a non-OK answer, a document without a title, or a network error', async () => {
    await expect(
      fetchYouTubeOEmbed('dQw4w9WgXcQ', fakeFetch({ [oembedUrl]: { status: 401, contentType: 'application/json' } })),
    ).resolves.toBeNull();
    await expect(
      fetchYouTubeOEmbed(
        'dQw4w9WgXcQ',
        fakeFetch({ [oembedUrl]: { status: 200, contentType: 'application/json', body: '{"author_name":"x"}' } }),
      ),
    ).resolves.toBeNull();
    await expect(fetchYouTubeOEmbed('dQw4w9WgXcQ', fakeFetch({}))).resolves.toBeNull();
  });
});

describe('resolveYouTubeLink', () => {
  const oembedUrl =
    'https://www.youtube.com/oembed?url=https%3A%2F%2Fwww.youtube.com%2Fwatch%3Fv%3DdQw4w9WgXcQ&format=json';
  const [maxres, , hqdefault] = youtubeThumbnailCandidates('dQw4w9WgXcQ');
  const oembedOk: Route = {
    status: 200,
    contentType: 'application/json',
    body: JSON.stringify({ title: 'Never Gonna Give You Up', author_name: 'Rick Astley', thumbnail_url: hqdefault }),
  };

  it('returns null for URLs that are not a YouTube video', async () => {
    await expect(resolveYouTubeLink('https://vimeo.com/1', fakeFetch({}))).resolves.toBeNull();
  });

  it('combines oEmbed text with the best probed thumbnail and a canonical watch URL', async () => {
    const fetchImpl = fakeFetch({ [oembedUrl]: oembedOk, [maxres]: { status: 200 } });
    await expect(resolveYouTubeLink('https://youtu.be/dQw4w9WgXcQ?si=abc', fetchImpl)).resolves.toEqual({
      videoId: 'dQw4w9WgXcQ',
      canonicalUrl: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
      title: 'Never Gonna Give You Up',
      authorName: 'Rick Astley',
      description: 'Watch "Never Gonna Give You Up" by Rick Astley on YouTube',
      image: maxres,
      siteName: 'YouTube',
    });
  });

  it('still returns the thumbnail when oEmbed is unavailable, leaving title undefined', async () => {
    const fetchImpl = fakeFetch({ [oembedUrl]: { status: 429, contentType: 'text/html' }, [maxres]: { status: 200 } });
    const result = await resolveYouTubeLink('https://www.youtube.com/watch?v=dQw4w9WgXcQ', fetchImpl);
    expect(result?.title).toBeUndefined();
    expect(result?.description).toBeUndefined();
    expect(result?.image).toBe(maxres);
  });

  it('falls back to the oEmbed thumbnail when no probed variant answers', async () => {
    const fetchImpl = fakeFetch({ [oembedUrl]: oembedOk });
    const result = await resolveYouTubeLink('https://www.youtube.com/watch?v=dQw4w9WgXcQ', fetchImpl);
    expect(result?.image).toBe(hqdefault);
  });

  it('returns null when neither text nor image could be resolved', async () => {
    const fetchImpl = fakeFetch({ [oembedUrl]: { status: 500, contentType: 'text/html' } });
    await expect(resolveYouTubeLink('https://www.youtube.com/watch?v=dQw4w9WgXcQ', fetchImpl)).resolves.toBeNull();
  });
});
