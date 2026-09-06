/**
 * YouTube link resolution from the URL alone — no watch-page fetch.
 *
 * YouTube answers Supabase's egress IPs with HTTP 429 on watch pages, so any
 * enrichment that starts by fetching the page never reaches the
 * YouTube-specific branch. Two endpoints do work from the cloud (verified
 * 2026-09-05 through the image-proxy function): the oEmbed document, which
 * carries title/author, and the i.ytimg.com thumbnail host. This module
 * composes those two into card-ready metadata; callers run it *before* any
 * page fetch and treat its thumbnail as authoritative for the link.
 *
 * Plain TypeScript with an injectable fetch so it runs under vitest as well
 * as Deno. Shared by extract-link-metadata (deep + fast passes) and add-url
 * (the quick pass that shapes the card the user sees immediately).
 */

export type YouTubeOEmbed = {
  title: string;
  authorName?: string;
  thumbnailUrl?: string;
};

export type YouTubeLinkMetadata = {
  videoId: string;
  canonicalUrl: string;
  title?: string;
  authorName?: string;
  description?: string;
  image?: string;
  siteName: 'YouTube';
};

const VIDEO_ID = /^[A-Za-z0-9_-]{11}$/;
const PATH_MARKERS = new Set(['embed', 'shorts', 'live', 'v']);

// 16:9 variants first (maxresdefault 1280×720, hq720 1280×720); hqdefault is
// 480×360 with letterbox bars but exists for every video.
const THUMBNAIL_VARIANTS = ['maxresdefault', 'hq720', 'hqdefault'] as const;

const validId = (candidate: string | null | undefined): string | null =>
  candidate && VIDEO_ID.test(candidate) ? candidate : null;

export const getYouTubeVideoId = (url: string): string | null => {
  let parsed: URL;
  try {
    parsed = new URL(url);
  } catch {
    return null;
  }
  const host = parsed.hostname.toLowerCase();
  const segments = parsed.pathname.split('/').filter(Boolean);

  if (host === 'youtu.be') return validId(segments[0]);

  const isYouTube =
    host === 'youtube.com' || host.endsWith('.youtube.com') ||
    host === 'youtube-nocookie.com' || host.endsWith('.youtube-nocookie.com');
  if (!isYouTube) return null;

  const fromQuery = validId(parsed.searchParams.get('v'));
  if (fromQuery) return fromQuery;

  const markerIndex = segments.findIndex((segment) => PATH_MARKERS.has(segment));
  if (markerIndex !== -1) return validId(segments[markerIndex + 1]);

  return null;
};

export const canonicalYouTubeUrl = (videoId: string): string =>
  `https://www.youtube.com/watch?v=${videoId}`;

export const youtubeThumbnailCandidates = (videoId: string): string[] =>
  THUMBNAIL_VARIANTS.map((variant) => `https://i.ytimg.com/vi/${videoId}/${variant}.jpg`);

/**
 * First thumbnail variant that really exists. i.ytimg.com answers a missing
 * variant with HTTP 404 plus a placeholder JPEG body, so the status decides.
 */
export const pickYouTubeThumbnail = async (
  videoId: string,
  fetchImpl: typeof fetch = fetch,
  timeoutMs = 4_000,
): Promise<string | null> => {
  for (const candidate of youtubeThumbnailCandidates(videoId)) {
    try {
      const response = await fetchImpl(candidate, { method: 'HEAD', signal: AbortSignal.timeout(timeoutMs) });
      if (response.ok && (response.headers.get('content-type') ?? '').startsWith('image/')) {
        return candidate;
      }
    } catch {
      // unreachable variant — try the next one
    }
  }
  return null;
};

export const fetchYouTubeOEmbed = async (
  videoId: string,
  fetchImpl: typeof fetch = fetch,
  timeoutMs = 5_000,
): Promise<YouTubeOEmbed | null> => {
  const endpoint = `https://www.youtube.com/oembed?url=${encodeURIComponent(canonicalYouTubeUrl(videoId))}&format=json`;
  try {
    const response = await fetchImpl(endpoint, {
      headers: { 'User-Agent': 'Mozilla/5.0 (compatible; LinkPreview/1.0)' },
      signal: AbortSignal.timeout(timeoutMs),
    });
    if (!response.ok) return null;
    const data = await response.json();
    const title = typeof data?.title === 'string' ? data.title.trim() : '';
    if (!title) return null;
    return {
      title,
      authorName: typeof data.author_name === 'string' && data.author_name.trim() ? data.author_name.trim() : undefined,
      thumbnailUrl: typeof data.thumbnail_url === 'string' && data.thumbnail_url ? data.thumbnail_url : undefined,
    };
  } catch {
    return null;
  }
};

/**
 * Everything the card needs for a YouTube link, from the URL alone. Returns
 * null for non-video URLs and when neither text nor an image could be had;
 * a thumbnail without a title is still returned (the title can be rescued
 * later, the image can't be beaten).
 */
export const resolveYouTubeLink = async (
  url: string,
  fetchImpl: typeof fetch = fetch,
): Promise<YouTubeLinkMetadata | null> => {
  const videoId = getYouTubeVideoId(url);
  if (!videoId) return null;

  const [oembed, probedImage] = await Promise.all([
    fetchYouTubeOEmbed(videoId, fetchImpl),
    pickYouTubeThumbnail(videoId, fetchImpl),
  ]);

  const image = probedImage ?? oembed?.thumbnailUrl;
  if (!oembed && !image) return null;

  return {
    videoId,
    canonicalUrl: canonicalYouTubeUrl(videoId),
    title: oembed?.title,
    authorName: oembed?.authorName,
    description: oembed
      ? oembed.authorName
        ? `Watch "${oembed.title}" by ${oembed.authorName} on YouTube`
        : `Watch "${oembed.title}" on YouTube`
      : undefined,
    image,
    siteName: 'YouTube',
  };
};
