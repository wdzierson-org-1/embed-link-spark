// Cascading fallbacks for sites that block scrapers (Medium, paywalled press,
// Cloudflare-fronted blogs). Each tier is more aggressive than the last:
//   1. direct fetch with a browser UA (caller does this first)
//   2. crawler UA fetch — beats sites that only sniff the User-Agent
//   3. Jina Reader (r.jina.ai) — a rendering proxy that extracts the readable
//      article; beats Medium and most JS-walled content. Free, no key needed.
//   4. Wayback Machine — last resort, serves the most recent public snapshot.

export interface ExtractedPage {
  title?: string;
  description?: string;
  content?: string;
  source: string;
}

export const CRAWLER_UA =
  'Mozilla/5.0 AppleWebKit/537.36 (KHTML, like Gecko; compatible; Googlebot/2.1; +http://www.google.com/bot.html) Chrome/120.0.0.0 Safari/537.36';

// Block/challenge pages that come back with HTTP 200 but no real content
export const looksBlocked = (text: string): boolean => {
  const sample = text.slice(0, 5000).toLowerCase();
  return /just a moment|enable javascript and cookies|access denied|attention required|are you a robot|please verify you|captcha|sign in to read|to continue reading|checking your browser/.test(sample);
};

export const fetchHtml = async (
  url: string,
  userAgent: string,
  timeoutMs = 10_000
): Promise<string | null> => {
  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const response = await fetch(url, {
      signal: controller.signal,
      headers: {
        'User-Agent': userAgent,
        'Accept': 'text/html,application/xhtml+xml',
        'Accept-Language': 'en-US,en;q=0.9',
      },
    });
    if (!response.ok) return null;
    return await response.text();
  } catch {
    return null;
  } finally {
    clearTimeout(timeoutId);
  }
};

export const fetchViaJinaReader = async (
  url: string,
  timeoutMs = 25_000
): Promise<ExtractedPage | null> => {
  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const response = await fetch(`https://r.jina.ai/${url}`, {
      signal: controller.signal,
      headers: { 'Accept': 'application/json' },
    });
    if (!response.ok) return null;
    const payload = await response.json();
    const data = payload?.data;
    if (!data) return null;
    const content = typeof data.content === 'string' ? data.content.trim() : '';
    const title = typeof data.title === 'string' ? data.title.trim() : '';
    if (!title && content.length < 100) return null;
    return {
      title: title || undefined,
      description: typeof data.description === 'string' && data.description.trim()
        ? data.description.trim()
        : undefined,
      content: content.length >= 100 ? content : undefined,
      source: 'jina-reader',
    };
  } catch {
    return null;
  } finally {
    clearTimeout(timeoutId);
  }
};

export const fetchViaWayback = async (
  url: string,
  timeoutMs = 15_000
): Promise<string | null> => {
  try {
    const availabilityResponse = await fetch(
      `https://archive.org/wayback/available?url=${encodeURIComponent(url)}`,
      { signal: AbortSignal.timeout(8_000) }
    );
    if (!availabilityResponse.ok) return null;
    const availability = await availabilityResponse.json();
    const snapshotUrl = availability?.archived_snapshots?.closest?.url;
    if (!snapshotUrl) return null;
    return await fetchHtml(
      snapshotUrl.replace(/^http:/, 'https:'),
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      timeoutMs
    );
  } catch {
    return null;
  }
};

// A rescue result whose title is just the site's own name (Jina rendering a
// member wall, a challenge page) is not a real extraction
export const isGenericTitle = (title: string | undefined, originalUrl: string): boolean => {
  if (!title) return true;
  const normalized = title.trim().toLowerCase();
  if (['medium', 'just a moment', 'just a moment...', 'access denied', 'attention required'].includes(normalized)) {
    return true;
  }
  try {
    const hostname = new URL(originalUrl).hostname.toLowerCase();
    return normalized === hostname || normalized === hostname.replace(/^www\./, '');
  } catch {
    return false;
  }
};

// First substantive prose line of extracted content — skipping nav clusters of
// markdown links ("[Sitemap](...) [Open in app](...)") that lead many renders
export const deriveDescriptionFromContent = (content: string, maxLength = 220): string | undefined => {
  for (const rawLine of content.split('\n')) {
    const withoutLinks = rawLine
      .replace(/!?\[([^\]]*)\]\([^)]*\)/g, '$1')
      .replace(/https?:\/\/\S+/g, '')
      .replace(/[#>*_`|-]+/g, ' ')
      .replace(/\s+/g, ' ')
      .trim();
    const linkChars = rawLine.length - withoutLinks.length;
    if (withoutLinks.length >= 60 && linkChars < rawLine.length / 2) {
      return withoutLinks.slice(0, maxLength);
    }
  }
  return undefined;
};

const decodeEntities = (text: string): string =>
  text
    .replace(/&nbsp;/g, ' ')
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&#39;|&apos;/g, "'");

export const htmlToText = (html: string): string =>
  decodeEntities(
    html
      .replace(/<script[\s\S]*?<\/script>/gi, ' ')
      .replace(/<style[\s\S]*?<\/style>/gi, ' ')
      .replace(/<noscript[\s\S]*?<\/noscript>/gi, ' ')
      .replace(/<(nav|footer|header|aside|form)[\s\S]*?<\/\1>/gi, ' ')
      .replace(/<!--[\s\S]*?-->/g, ' ')
      .replace(/<[^>]+>/g, ' ')
  ).replace(/\s+/g, ' ').trim();
