/**
 * TikTok link resolution from the URL alone — no video-page fetch.
 *
 * TikTok serves crawlers a "Couldn't find this page" shell titled
 * "TikTok - Make Your Day", so page-based enrichment produced placeholder
 * cards and summaries of the site footer. The public oEmbed endpoint is
 * reachable from Supabase's egress IPs (probed 2026-09-29 through the
 * image-proxy function), accepts the phone share-sheet shortlinks
 * (tiktok.com/t/…, vm.tiktok.com/…) as-is, and returns the caption, the
 * creator and a thumbnail. Mirrors _shared/youtube.ts: callers run this
 * before any page fetch and treat its thumbnail as authoritative.
 *
 * The thumbnail is a signed, expiring CDN URL — callers must copy it into
 * our bucket rather than store the URL.
 *
 * Plain TypeScript with an injectable fetch so it runs under vitest as well
 * as Deno.
 */

export type TikTokLinkMetadata = {
  canonicalUrl?: string;
  /** Card title derived from the caption; undefined when the caption is empty */
  title?: string;
  /** The creator's caption, verbatim — captured source material (page_body) */
  caption?: string;
  authorName?: string;
  authorHandle?: string;
  /** Explicit oEmbed creator profile URL, never inferred from the saved URL. */
  authorUrl?: string;
  description?: string;
  image?: string;
  siteName: 'TikTok';
};

const TITLE_MAX = 90;

const isTikTokHost = (host: string): boolean =>
  host === 'tiktok.com' || host.endsWith('.tiktok.com');

/** Videos and share shortlinks; profiles, tags, music and search pages are not saved objects we can resolve. */
export const isTikTokVideoUrl = (url: string): boolean => {
  let parsed: URL;
  try {
    parsed = new URL(url);
  } catch {
    return false;
  }
  const host = parsed.hostname.toLowerCase();
  if (!isTikTokHost(host)) return false;
  if (host === 'vm.tiktok.com' || host === 'vt.tiktok.com') return parsed.pathname.length > 1;
  return /^\/@[^/]+\/(video|photo)\/\d+/.test(parsed.pathname) || /^\/t\/[A-Za-z0-9_-]+\/?$/.test(parsed.pathname);
};

/** Captions carry hashtags and mentions at the end; a title reads better without them. */
export const titleFromCaption = (caption: string): string | undefined => {
  const words = caption
    .replace(/\s+/g, ' ')
    .trim()
    .split(' ');
  // Drop the trailing run of #tags / @mentions, keep any inside the sentence
  while (words.length && /^[#@]\S+$/.test(words[words.length - 1])) words.pop();
  const text = words.join(' ').trim();
  if (!text) return undefined;
  if (text.length <= TITLE_MAX) return text;
  const cut = text.slice(0, TITLE_MAX);
  const lastSpace = cut.lastIndexOf(' ');
  return `${(lastSpace > 40 ? cut.slice(0, lastSpace) : cut).replace(/[\s,;:.!?-]+$/, '')}…`;
};

const text = (value: unknown): string | undefined =>
  typeof value === 'string' && value.trim() ? value.trim() : undefined;

const isShortlink = (url: string): boolean => {
  try {
    const parsed = new URL(url);
    return parsed.pathname.startsWith('/t/') || /^v[mt]\.tiktok\.com$/i.test(parsed.hostname);
  } catch {
    return false;
  }
};

const fetchOEmbed = async (
  target: string,
  fetchImpl: typeof fetch,
  timeoutMs: number,
): Promise<Record<string, unknown> | null> => {
  try {
    const response = await fetchImpl(`https://www.tiktok.com/oembed?url=${encodeURIComponent(target)}`, {
      headers: { 'User-Agent': 'Mozilla/5.0 (compatible; LinkPreview/1.0)' },
      signal: AbortSignal.timeout(timeoutMs),
    });
    return response.ok ? await response.json() : null;
  } catch {
    return null;
  }
};

/**
 * Some shortlinks redirect to the mobile form (m.tiktok.com/v/<id>.html),
 * which oEmbed refuses although the video is public; the canonical
 * /@user/video/<id> form works with any handle, so read the id off the
 * redirect.
 */
export const videoIdFromShortlink = async (
  url: string,
  fetchImpl: typeof fetch,
  timeoutMs: number,
): Promise<string | null> => {
  try {
    const response = await fetchImpl(url, { redirect: 'manual', signal: AbortSignal.timeout(timeoutMs) });
    const location = response.headers.get('location') ?? '';
    return location.match(/\/(?:video|v)\/(\d{8,})/)?.[1] ?? null;
  } catch {
    return null;
  }
};

/**
 * Everything the card needs for a TikTok video, from the URL alone. Returns
 * null for non-video URLs and when oEmbed has nothing for us (private or
 * removed videos answer 400/404).
 */
export const resolveTikTokLink = async (
  url: string,
  fetchImpl: typeof fetch = fetch,
  timeoutMs = 6_000,
): Promise<TikTokLinkMetadata | null> => {
  if (!isTikTokVideoUrl(url)) return null;
  let data = await fetchOEmbed(url, fetchImpl, timeoutMs);
  if (!data && isShortlink(url)) {
    const videoId = await videoIdFromShortlink(url, fetchImpl, timeoutMs);
    if (videoId) data = await fetchOEmbed(`https://www.tiktok.com/@_/video/${videoId}`, fetchImpl, timeoutMs);
  }
  if (!data) return null;
  const caption = text(data.title);
  const authorName = text(data.author_name);
  const authorHandle = text(data.author_unique_id);
  const image = text(data.thumbnail_url);
  if (!caption && !authorName && !authorHandle && !image) return null;

  let authorUrl: string | undefined;
  try {
    const supplied = new URL(text(data.author_url) ?? '');
    if (supplied.protocol === 'https:' && isTikTokHost(supplied.hostname) && !supplied.username && !supplied.password &&
      !supplied.port && !supplied.search && !supplied.hash && /^\/@[^/]+\/?$/.test(supplied.pathname)) authorUrl = supplied.href.replace(/\/$/, '');
  } catch { /* Creator details may be absent. */ }
  const videoId = text(data.embed_product_id);
  const canonicalUrl = authorUrl && videoId && /^\d+$/.test(videoId) ? `${authorUrl}/video/${videoId}` : undefined;
  const creator = authorName && authorHandle && authorName !== authorHandle
    ? `${authorName} (@${authorHandle})`
    : authorName ?? (authorHandle ? `@${authorHandle}` : undefined);

  return {
    canonicalUrl,
    title: caption ? titleFromCaption(caption) : undefined,
    caption,
    authorName,
    authorHandle,
    authorUrl,
    description: creator ? `TikTok by ${creator}` : undefined,
    image,
    siteName: 'TikTok',
  };
};
