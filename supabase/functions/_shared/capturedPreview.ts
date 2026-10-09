import type { EnrichmentItem } from './enrichmentQuality.ts';
import { previewImageEvidence } from './pagePreview.ts';
const MAX_BYTES = 5_000_000;
/** Narrow recovery adapter: public LinkedIn profile portraits on LinkedIn's
 * own media CDN. Do not turn captured Markdown URLs into arbitrary fetches. */
export async function recoverCapturedPreview(db: any, item: EnrichmentItem, text: string, fetcher: typeof fetch = fetch): Promise<{ path: string } | null> {
  if (item.type !== 'link' || item.file_path || !item.url || !item.id || !item.user_id) return null;
  // A user may deliberately clear a preview. The patch RPC preserves protected
  // fields and can still return true, so avoid an upload it cannot attach.
  if (item.attributes?.enrichment?.protected_fields?.file_path) return null;
  try {
    const source = new URL(item.url);
    if (!/(^|\.)linkedin\.com$/.test(source.hostname) || !/^\/in\/[^/]+\/?$/.test(source.pathname)) return null;
  } catch { return null; }
  const candidates = previewImageEvidence({ url: item.url, title: item.title || undefined, text })
    .filter(candidate => {
      if (!candidate.associated) return false;
      const target = new URL(candidate.url);
      return target.hostname === 'media.licdn.com' && /^\/dms\/image\//.test(target.pathname) &&
        /\/profile-displayphoto-[^/]+\//.test(target.pathname);
    }).slice(0, 2);
  for (const candidate of candidates) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 6000);
    try {
      const response = await fetcher(candidate.url, {
        redirect: 'error', signal: controller.signal,
        headers: { Accept: 'image/jpeg,image/png,image/webp', 'User-Agent': 'StashPreview/1.0' },
      });
      const mime = (response.headers.get('content-type') || '').split(';')[0].trim().toLowerCase();
      if (!response.ok || response.redirected || !['image/jpeg', 'image/png', 'image/webp'].includes(mime) ||
          Number(response.headers.get('content-length') || 0) > MAX_BYTES || !response.body) {
        await response.body?.cancel();
        continue;
      }
      const reader = response.body.getReader();
      const chunks: Uint8Array[] = []; let length = 0;
      try {
        while (true) {
          const part = await reader.read(); if (part.done) break;
          length += part.value.byteLength;
          if (length > MAX_BYTES) { await reader.cancel(); break; }
          chunks.push(part.value);
        }
      } finally { reader.releaseLock(); }
      if (length < 100 || length > MAX_BYTES) continue;
      const bytes = new Uint8Array(length); let offset = 0;
      for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
      const starts = (signature: number[], at = 0) => signature.every((value, index) => bytes[index + at] === value);
      const format = starts([0xff, 0xd8, 0xff]) ? ['image/jpeg', 'jpg'] :
        starts([137, 80, 78, 71, 13, 10, 26, 10]) ? ['image/png', 'png'] :
        starts([82, 73, 70, 70]) && starts([87, 69, 66, 80], 8) ? ['image/webp', 'webp'] : null;
      if (!format || format[0] !== mime) continue;
      const path = `${item.user_id}/previews/${item.id}-${crypto.randomUUID()}.${format[1]}`;
      const { error } = await db.storage.from('stash-media').upload(path, bytes, { contentType: mime, upsert: false });
      if (!error) return { path };
    } catch { /* A missed portrait must not discard useful captured text. */ }
    finally { clearTimeout(timer); }
  }
  return null;
}
