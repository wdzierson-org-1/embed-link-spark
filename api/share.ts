/**
 * Link previews for share links (docs/ui-changes.md 2026-10-09; DESIGN-v2 §12.15).
 *
 * Crawlers (Slack, iMessage, Twitter, Discord, WhatsApp…) read `/s/<token>` without running the
 * app, so vercel.json sends them here. This answers the app shell with the save's own Open
 * Graph card — its title, a brief description and its picture — in place of the site's card.
 * People never come here: they get the shell straight from the CDN and the app renders the
 * page (pages/SharedItem). A dead or malformed token answers 404, so nothing unfurls for it.
 */
const SUPABASE_URL = 'https://uqqsgmwkvslaomzxptnp.supabase.co';
// The publishable anon key, the same one the web client ships (src/integrations/supabase/client.ts)
const SUPABASE_ANON_KEY =
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVxcXNnbXdrdnNsYW9tenhwdG5wIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTA2MjU0ODcsImV4cCI6MjA2NjIwMTQ4N30.vGWb1EdshtLFLpUHQ54Vy2CDmuPVCTbvc8UYW6_cvmE';
const SITE = 'https://www.gostash.it';
const DEFAULT_IMAGE = `${SITE}/og-v2.jpg`;
const TOKEN = /^[A-Za-z0-9]{10}$/;
const FETCH_MS = 4000;

export interface SharedSave {
  title: string | null;
  description: string | null;
  summary: string | null;
  type: string;
  file_path: string | null;
  username?: string | null;
}

export interface ShareCard {
  title: string;
  description: string;
  image: string;
  imageAlt: string;
  /** The picture is the save's own: a large card. The default image is the site's 1200×630. */
  largeImage: boolean;
  url: string;
}

const collapse = (text: string): string => text.replace(/\s+/g, ' ').trim();

/** At most `max` characters, cut at a word when that leaves most of the room, ending in … */
export const brief = (text: string, max = 200): string => {
  const whole = collapse(text);
  if (whole.length <= max) return whole;
  const cut = whole.slice(0, max - 1);
  const space = cut.lastIndexOf(' ');
  const kept = space > max * 0.6 ? cut.slice(0, space) : cut;
  return `${kept.replace(/[\s,;:.–—-]+$/, '')}…`;
};

const firstSentence = (text: string): string => {
  const whole = collapse(text);
  const match = whole.match(/^.{20,}?[.!?](?=\s|$)/);
  return match ? match[0] : whole;
};

/** A stored path becomes its public address; a rescued link preview is already a URL */
export const pictureOf = (save: SharedSave): string | null => {
  if ((save.type === 'image' || save.type === 'link') && save.file_path) {
    return save.file_path.startsWith('http')
      ? save.file_path
      : `${SUPABASE_URL}/storage/v1/object/public/stash-media/${save.file_path}`;
  }
  return null;
};

export const buildShareCard = (save: SharedSave, url: string): ShareCard => {
  const title = brief(save.title || 'A save on Stash', 120);
  const picture = pictureOf(save);
  const description =
    (save.description && collapse(save.description)) ||
    (save.summary && firstSentence(save.summary)) ||
    'Saved with Stash, with the thought that made it worth keeping.';
  return {
    title,
    description: brief(description, 200),
    image: picture ?? DEFAULT_IMAGE,
    imageAlt: picture ? title : 'Stash',
    largeImage: Boolean(picture),
    url,
  };
};

export const escapeHtml = (text: string): string =>
  text.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');

export const renderShareHead = (card: ShareCard): string => {
  const e = escapeHtml;
  const tags = [
    `<title>${e(card.title)} · Stash</title>`,
    `<meta name="description" content="${e(card.description)}" />`,
    `<meta name="robots" content="noindex" />`,
    `<meta property="og:site_name" content="Stash" />`,
    `<meta property="og:type" content="article" />`,
    `<meta property="og:title" content="${e(card.title)}" />`,
    `<meta property="og:description" content="${e(card.description)}" />`,
    `<meta property="og:url" content="${e(card.url)}" />`,
    `<meta property="og:image" content="${e(card.image)}" />`,
    `<meta property="og:image:alt" content="${e(card.imageAlt)}" />`,
  ];
  if (!card.largeImage) {
    tags.push('<meta property="og:image:width" content="1200" />', '<meta property="og:image:height" content="630" />');
  }
  tags.push(
    `<meta name="twitter:card" content="${card.largeImage ? 'summary_large_image' : 'summary'}" />`,
    `<meta name="twitter:title" content="${e(card.title)}" />`,
    `<meta name="twitter:description" content="${e(card.description)}" />`,
    `<meta name="twitter:image" content="${e(card.image)}" />`,
  );
  return tags.join('\n    ');
};

/** The app shell with the site's card taken out and the save's put in, after the viewport */
export const applyShareHead = (shell: string, head: string): string => {
  const stripped = shell
    .replace(/<title>[\s\S]*?<\/title>\s*/i, '')
    .replace(/<meta\s+name="description"[^>]*>\s*/gi, '')
    .replace(/<meta\s+property="og:[^"]*"[^>]*>\s*/gi, '')
    .replace(/<meta\s+name="twitter:[^"]*"[^>]*>\s*/gi, '');
  const viewport = /<meta\s+name="viewport"[^>]*>/i;
  return viewport.test(stripped)
    ? stripped.replace(viewport, (tag) => `${tag}\n    ${head}`)
    : stripped.replace(/<head>/i, `<head>\n    ${head}`);
};

const minimalShell = (head: string, url: string): string =>
  `<!doctype html><html lang="en"><head><meta charset="utf-8" /><meta name="viewport" content="width=device-width, initial-scale=1" />\n    ${head}\n  </head><body><p><a href="${escapeHtml(url)}">Open on Stash</a></p></body></html>`;

export const fetchSharedSave = async (token: string, fetcher: typeof fetch = fetch): Promise<SharedSave | null> => {
  try {
    const response = await fetcher(`${SUPABASE_URL}/rest/v1/rpc/shared_item`, {
      method: 'POST',
      headers: { apikey: SUPABASE_ANON_KEY, Authorization: `Bearer ${SUPABASE_ANON_KEY}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ p_token: token }),
      signal: AbortSignal.timeout(FETCH_MS),
    });
    if (!response.ok) return null;
    const rows = (await response.json()) as SharedSave[];
    return Array.isArray(rows) && rows[0] ? rows[0] : null;
  } catch {
    return null;
  }
};

const fetchShell = async (host: string, fetcher: typeof fetch = fetch): Promise<string | null> => {
  try {
    const response = await fetcher(`https://${host}/app.html`, { signal: AbortSignal.timeout(FETCH_MS) });
    if (!response.ok) return null;
    const html = await response.text();
    return /<head>/i.test(html) ? html : null;
  } catch {
    return null;
  }
};

// Only our own hosts serve the shell; anything else (a forged Host header) gets production's
const allowedHost = (host: string | undefined): string =>
  host && /^([a-z0-9-]+\.)*(gostash\.it|vercel\.app)$/i.test(host) ? host : 'www.gostash.it';

interface ShareRequest {
  query?: Record<string, string | string[] | undefined>;
  headers?: Record<string, string | string[] | undefined>;
}
interface ShareResponse {
  setHeader(name: string, value: string): unknown;
  status(code: number): { send(body: string): unknown };
}

export const handleShare = async (req: ShareRequest, res: ShareResponse, fetcher: typeof fetch = fetch): Promise<void> => {
  const raw = req.query?.token;
  const token = (Array.isArray(raw) ? raw[0] : raw) ?? '';
  const save = TOKEN.test(token) ? await fetchSharedSave(token, fetcher) : null;
  res.setHeader('Content-Type', 'text/html; charset=utf-8');
  res.setHeader('X-Robots-Tag', 'noindex');
  if (!save) {
    res.setHeader('Cache-Control', 'public, s-maxage=60');
    res.status(404).send(minimalShell(renderShareHead({
      title: 'Stash',
      description: 'This share link no longer works.',
      image: DEFAULT_IMAGE,
      imageAlt: 'Stash',
      largeImage: false,
      url: `${SITE}/s/${token}`,
    }), SITE));
    return;
  }
  const url = `${SITE}/s/${token}`;
  const head = renderShareHead(buildShareCard(save, url));
  const hostHeader = req.headers?.host;
  const shell = await fetchShell(allowedHost(Array.isArray(hostHeader) ? hostHeader[0] : hostHeader), fetcher);
  res.setHeader('Cache-Control', 'public, s-maxage=120, stale-while-revalidate=600');
  res.status(200).send(shell ? applyShareHead(shell, head) : minimalShell(head, url));
};

export default async function handler(req: ShareRequest, res: ShareResponse): Promise<void> {
  await handleShare(req, res);
}
