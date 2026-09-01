// Pure helpers for the Stash it extension. No chrome.* usage so node can test
// this file directly (`npm test` in extension/).

// Mirrors MAX_FILE_SIZE_MB in src/services/imageUpload/MediaUploadTypes.ts.
export const MAX_IMAGE_MB = 20;

const EXT_BY_MIME = {
  'image/jpeg': 'jpg',
  'image/jpg': 'jpg',
  'image/png': 'png',
  'image/gif': 'gif',
  'image/webp': 'webp',
  'image/avif': 'avif',
  'image/svg+xml': 'svg',
  'image/bmp': 'bmp',
  'image/x-icon': 'ico',
  'image/vnd.microsoft.icon': 'ico',
  'image/tiff': 'tiff',
  'image/heic': 'heic',
  'image/heif': 'heif',
};

const MIME_BY_EXT = {
  jpg: 'image/jpeg',
  jpeg: 'image/jpeg',
  jfif: 'image/jpeg',
  png: 'image/png',
  gif: 'image/gif',
  webp: 'image/webp',
  avif: 'image/avif',
  svg: 'image/svg+xml',
  bmp: 'image/bmp',
  ico: 'image/x-icon',
  tif: 'image/tiff',
  tiff: 'image/tiff',
  heic: 'image/heic',
  heif: 'image/heif',
};

// Content-Type headers that don't contradict the URL saying "image" — for
// these we fall back to the URL extension instead of failing.
const GENERIC_MIMES = new Set([
  'application/octet-stream',
  'binary/octet-stream',
  'application/binary',
  'application/unknown',
  'unknown/unknown',
]);

/** "image/jpeg; charset=utf-8" → "image/jpeg" (lowercased); null if empty. */
export function cleanMime(contentType) {
  if (!contentType) return null;
  const mime = String(contentType).split(';')[0].trim().toLowerCase();
  return mime || null;
}

/** Mime declared by a data: URL, or null if not a data: URL. */
export function dataUrlMime(url) {
  const match = /^data:([^;,]+)[;,]/i.exec(url ?? '');
  return match ? match[1].trim().toLowerCase() : null;
}

/** Lowercased extension of the URL's pathname, or null. */
export function urlExt(url) {
  try {
    const pathname = new URL(url).pathname;
    const last = pathname.split('/').pop() ?? '';
    const dot = last.lastIndexOf('.');
    if (dot <= 0 || dot === last.length - 1) return null;
    return last.slice(dot + 1).toLowerCase();
  } catch {
    return null;
  }
}

/**
 * Decide the mime type for a fetched image, or null when the bytes are
 * clearly not an image (e.g. a CDN error page served as text/html).
 * Priority: data-URL declaration → image/* Content-Type → URL extension
 * (only when the header is absent or generic).
 */
export function resolveImageMime(srcUrl, contentType) {
  const declared = dataUrlMime(srcUrl);
  if (declared?.startsWith('image/')) return declared;

  const header = cleanMime(contentType);
  if (header?.startsWith('image/')) return header;
  if (header && !GENERIC_MIMES.has(header)) return null;

  const ext = urlExt(srcUrl);
  return (ext && MIME_BY_EXT[ext]) || null;
}

/** File extension for a resolved image mime; derives one for unmapped types. */
export function extForMime(mime) {
  if (EXT_BY_MIME[mime]) return EXT_BY_MIME[mime];
  const subtype = (mime ?? '').split('/')[1] ?? '';
  return subtype.replace(/[^a-z0-9]/g, '') || 'img';
}

/**
 * Filename for a stashed image, from its URL's path ("golden-gate.jpg").
 * Feeds attributes.media.file_name — titles are AI-derived, the filename is
 * metadata (docs/ui-changes.md 2026-08-26). Every card shows this chip, so
 * when the path has no recognizable image extension (CDN ids, dynamic
 * endpoints) we synthesize one from the basename — or the hostname as a last
 * resort — plus the resolved format (`fallbackExt`). Only data:/blob: URLs,
 * which carry no name at all, return null.
 */
export function displayNameFromUrl(url, fallbackExt) {
  try {
    const { protocol, pathname, hostname } = new URL(url);
    if (protocol !== 'http:' && protocol !== 'https:') return null;
    const last = decodeURIComponent(pathname.split('/').pop() ?? '');
    const dot = last.lastIndexOf('.');
    const hasRealExt = dot > 0 && dot < last.length - 1 && MIME_BY_EXT[last.slice(dot + 1).toLowerCase()];
    if (hasRealExt) return last.length > 120 ? null : last;
    if (!fallbackExt) return null;
    const base = (dot > 0 ? last.slice(0, dot) : last) || hostname.replace(/^www\./, '');
    if (!base) return null;
    return `${base.slice(0, 60)}.${fallbackExt}`;
  } catch {
    return null;
  }
}

/** Only http(s) pages can be stashed as links. */
export function isStashableUrl(url) {
  try {
    const { protocol } = new URL(url);
    return protocol === 'http:' || protocol === 'https:';
  } catch {
    return false;
  }
}

/** Storage object name matching the web app's convention (fileUploader.ts). */
export function storageName(nowMs, ext) {
  return `${nowMs}.${ext}`;
}

/** True while the access token has >60s left — refresh otherwise. */
export function sessionIsFresh(session, nowSec) {
  return Boolean(session?.access_token) && (session.expires_at ?? 0) - 60 > nowSec;
}
