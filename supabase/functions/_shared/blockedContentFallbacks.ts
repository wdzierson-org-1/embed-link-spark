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
  image?: string;
  source: string;
}

// Large favicon as the image of last resort — a branded tile beats an empty
// card while the retry queue hunts for the real article image
export const faviconImageForUrl = (url: string): string | undefined => {
  try {
    const hostname = new URL(url).hostname;
    return `https://www.google.com/s2/favicons?domain=${hostname}&sz=256`;
  } catch {
    return undefined;
  }
};

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
    // A paid Jina key (JINA_API_KEY secret) lifts rate limits and unlocks the
    // full browser-rendering engine; without one the free tier still works
    const jinaKey = Deno.env.get('JINA_API_KEY');
    const headers: Record<string, string> = {
      'Accept': 'application/json',
      'X-With-Images-Summary': 'true',
    };
    if (jinaKey) {
      headers['Authorization'] = `Bearer ${jinaKey}`;
      headers['X-Engine'] = 'browser';
    }
    const response = await fetch(`https://r.jina.ai/${url}`, {
      signal: controller.signal,
      headers,
    });
    if (!response.ok) return null;
    const payload = await response.json();
    const data = payload?.data;
    if (!data) return null;
    const content = typeof data.content === 'string' ? data.content.trim() : '';
    const title = typeof data.title === 'string' ? data.title.trim() : '';
    if (!title && content.length < 100) return null;

    // Article image: the reader's images summary first, else the first inline
    // markdown image in the content
    let image: string | undefined;
    if (data.images && typeof data.images === 'object') {
      const candidates = Object.values(data.images).filter(
        (value): value is string => typeof value === 'string' && value.startsWith('http')
      );
      image = candidates[0];
    }
    if (!image) {
      image = content.match(/!\[[^\]]*\]\((https?:[^)\s]+)/)?.[1];
    }

    return {
      title: title || undefined,
      description: typeof data.description === 'string' && data.description.trim()
        ? data.description.trim()
        : undefined,
      content: content.length >= 100 ? content : undefined,
      image,
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

// Ask the Wayback Machine to capture the page now — it browses as its own
// agent from its own infrastructure, so a snapshot is often available on the
// next retry even when every direct tier is blocked. Fire-and-forget.
export const requestWaybackSnapshot = (url: string): void => {
  fetch(`https://web.archive.org/save/${url}`, {
    method: 'GET',
    headers: {
      'User-Agent': 'Mozilla/5.0 (compatible; StashBot/1.0)',
    },
    signal: AbortSignal.timeout(20_000),
  }).then((res) => {
    console.log('Wayback snapshot request for', url, '->', res.status);
  }).catch(() => {
    // Best effort only
  });
};

// When every fetch tier fails, the URL itself still names the topic. Turn the
// slug into a readable title and (when a key is available) let a small model
// phrase the gist — clearly labeled as inferred so the UI is honest about it.
export const inferMetadataFromUrl = async (
  url: string,
  openAIApiKey?: string
): Promise<{ title: string; description: string } | null> => {
  let slugTitle = '';
  let hostname = '';
  try {
    const parsed = new URL(url);
    hostname = parsed.hostname.replace(/^www\./, '');
    const segments = parsed.pathname.split('/').filter(Boolean).map(decodeURIComponent);
    const candidate = segments
      .filter((s) => !s.startsWith('@'))
      .sort((a, b) => b.length - a.length)[0] || '';
    slugTitle = candidate
      .replace(/\.(html?|php|aspx?)$/i, '')
      .replace(/-[0-9a-f]{8,}$/i, '')   // trailing content ids (Medium etc.)
      .replace(/[-_+]+/g, ' ')
      .replace(/\s+/g, ' ')
      .trim();
  } catch {
    return null;
  }

  if (slugTitle.length < 8 || !/[a-z]/i.test(slugTitle)) return null;

  const fallbackTitle = slugTitle.replace(/\b\w/g, (c) => c.toUpperCase());
  const fallbackDescription = `Saved from ${hostname}. The page couldn't be read yet — topic inferred from the link; Stash will keep trying to fetch the full content.`;

  if (!openAIApiKey) {
    return { title: fallbackTitle, description: fallbackDescription };
  }

  try {
    const response = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${openAIApiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model: 'gpt-4o-mini',
        messages: [
          {
            role: 'system',
            content: 'You turn URL slugs into metadata. Reply with exactly two lines:\nTITLE: <the article title implied by the slug, in natural casing>\nGIST: <one sentence starting with "Appears to be about" describing the likely topic>',
          },
          {
            role: 'user',
            content: `Site: ${hostname}\nSlug: ${slugTitle}`,
          },
        ],
        max_tokens: 120,
        temperature: 0.2,
      }),
      signal: AbortSignal.timeout(10_000),
    });
    if (!response.ok) throw new Error(`OpenAI ${response.status}`);
    const data = await response.json();
    const text: string = data.choices?.[0]?.message?.content || '';
    const title = text.match(/TITLE:\s*(.+)/i)?.[1]?.trim();
    const gist = text.match(/GIST:\s*(.+)/i)?.[1]?.trim();
    return {
      title: title || fallbackTitle,
      description: gist
        ? `${gist} (Inferred from the link — Stash will keep trying to fetch the full page.)`
        : fallbackDescription,
    };
  } catch {
    return { title: fallbackTitle, description: fallbackDescription };
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

// Boilerplate a site serves instead of the real description (404 copy,
// challenge text) — worse than an inferred gist
export const isJunkDescription = (description: string | undefined): boolean => {
  if (!description) return true;
  return /page that doesn't exist|stories will take you somewhere new|just a moment|enable javascript|access denied|verify you are human/i.test(description);
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
