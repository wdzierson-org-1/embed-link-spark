import { isPublicPreviewUrl } from './previewUrl.ts';
const MAX_FEED_BYTES = 2_000_000;
const decode = (value: string) => value.replace(/&(amp|lt|gt|quot|apos|#\d+|#x[0-9a-f]+);/gi, (entity, name: string) => {
  const named: Record<string, string> = { amp: '&', lt: '<', gt: '>', quot: '"', apos: "'" };
  if (!name.startsWith('#')) return named[name.toLowerCase()] ?? entity;
  const code = /^#x/i.test(name) ? parseInt(name.slice(2), 16) : parseInt(name.slice(1), 10);
  return code > 0 && code <= 0x10ffff ? String.fromCodePoint(code) : entity;
});
const field = (item: string, name: string) => {
  const value = item.match(new RegExp(`<${name}(?:\\s[^>]*)?>([\\s\\S]*?)<\\/${name}>`, 'i'))?.[1].trim() || '';
  return value.startsWith('<![CDATA[') && value.endsWith(']]>') ? value.slice(9, -3).trim() : decode(value);
};
const attribute = (tag: string, name: string) => {
  const match = tag.match(new RegExp(`(?:^|\\s)${name}\\s*=\\s*(?:"([^"]*)"|'([^']*)')`, 'i'));
  return decode(match?.[1] ?? match?.[2] ?? '');
};
/** Read only the author's public RSS preview. The exact GUID, entry link and
 * image's article link must agree; the membership-protected story is untouched. */
export async function fetchMediumFeedPreview(url: string, fetcher: typeof fetch = fetch): Promise<string | null> {
  let source: URL, author: string, articleId: string;
  try {
    source = new URL(url);
    if (!isPublicPreviewUrl(url) || source.hostname !== 'medium.com') return null;
    const match = source.pathname.match(/^\/@([a-z0-9_.-]{1,60})\/[^/]+-([a-f0-9]{12})\/?$/i);
    if (!match) return null;
    [, author, articleId] = match;
  } catch { return null; }
  const sameArticle = (value: string) => {
    try {
      const link = new URL(value);
      return isPublicPreviewUrl(value) && link.hostname === 'medium.com' &&
        link.pathname.replace(/\/$/, '') === source.pathname.replace(/\/$/, '');
    } catch { return false; }
  };
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 5000);
  try {
    const response = await fetcher(`https://medium.com/feed/@${encodeURIComponent(author)}`, {
      redirect: 'error', signal: controller.signal,
      headers: { Accept: 'application/rss+xml,application/xml;q=0.9,text/xml;q=0.8', 'User-Agent': 'StashPreview/1.0' },
    });
    if (!response.ok || response.redirected || Number(response.headers.get('content-length') || 0) > MAX_FEED_BYTES || !response.body) {
      await response.body?.cancel(); return null;
    }
    const reader = response.body.getReader(); const chunks: Uint8Array[] = []; let length = 0;
    try {
      while (true) {
        const part = await reader.read(); if (part.done) break;
        length += part.value.byteLength;
        if (length > MAX_FEED_BYTES) { await reader.cancel(); return null; }
        chunks.push(part.value);
      }
    } finally { reader.releaseLock(); }
    const bytes = new Uint8Array(length); let offset = 0;
    for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
    const xml = new TextDecoder().decode(bytes).replace(/<!--[\s\S]*?-->/g, '');
    if (/<!DOCTYPE|<!ENTITY/i.test(xml) || !/<rss\b/i.test(xml)) return null;
    let count = 0;
    for (const entry of xml.matchAll(/<item\b[^>]*>([\s\S]*?)<\/item>/gi)) {
      if (++count > 100) break;
      const item = entry[1];
      if (field(item, 'guid') !== `https://medium.com/p/${articleId}` || !sameArticle(field(item, 'link'))) continue;
      const html = field(item, 'description');
      for (const paragraph of html.matchAll(/<p\b([^>]*)>([\s\S]*?)<\/p>/gi)) {
        if (!attribute(paragraph[1], 'class').split(/\s+/).includes('medium-feed-image')) continue;
        for (const anchor of paragraph[2].matchAll(/<a\b([^>]*)>([\s\S]*?)<\/a>/gi)) {
          if (!sameArticle(attribute(anchor[1], 'href'))) continue;
          const tag = anchor[2].match(/<img\b([^>]*)>/i)?.[1];
          const image = tag ? attribute(tag, 'src') : '';
          if (!isPublicPreviewUrl(image) || image.length > 16384) continue;
          const host = new URL(image).hostname;
          if (host === 'miro.medium.com' || /^cdn-images-\d+\.medium\.com$/.test(host)) return image;
        }
      }
    }
  } catch { /* Public feeds can be unavailable or omit older articles. */ }
  finally { clearTimeout(timer); }
  return null;
}
