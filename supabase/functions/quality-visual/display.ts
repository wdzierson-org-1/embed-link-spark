export type VisualSurface = {
  surface: 'card' | 'detail';
  mode: 'image' | 'embed' | 'generated' | 'unsupported' | 'missing';
  source_url?: string;
  display_url?: string;
  reason?: string;
};

export type VisualItem = {
  id: string;
  user_id: string;
  type: string;
  url?: string | null;
  file_path?: string | null;
  attributes?: Record<string, any> | null;
};

/** Mirrors src/utils/embeds.ts and src/utils/youtube.ts without a frontend bundle
 * dependency. Parity tests exercise the actual web resolver. This is display
 * resolution only: none of these returned URLs is permission to fetch a target. */
function embedUrl(value: string | null | undefined): string | null {
  if (!value) return null;
  let parsed: URL;
  try { parsed = new URL(value); } catch { return null; }
  const fullHost = parsed.hostname.toLowerCase();
  const host = fullHost.replace(/^www\./, '');
  const segments = parsed.pathname.split('/').filter(Boolean);

  // Keep the UI's current video-ID parser semantics; fetching is independently gated.
  if (fullHost.includes('youtube.com') || fullHost.includes('youtu.be')) {
    let id = fullHost.includes('youtu.be') ? segments[0] : parsed.searchParams.get('v');
    if (!id && !fullHost.includes('youtu.be')) {
      const at = segments.findIndex(segment => ['embed', 'shorts', 'live'].includes(segment));
      if (at >= 0) id = segments[at + 1];
    }
    if (id && /^[A-Za-z0-9_-]{11}$/.test(id)) return `https://www.youtube-nocookie.com/embed/${id}?rel=0&enablejsapi=1`;
  }
  if (host === 'vimeo.com' || host === 'player.vimeo.com') {
    const id = segments.find(segment => /^\d{6,}$/.test(segment));
    return id ? `https://player.vimeo.com/video/${id}` : null;
  }
  if (host === 'loom.com' && ['share', 'embed'].includes(segments[0]) && /^[a-f0-9]{20,}$/i.test(segments[1] || '')) {
    return `https://www.loom.com/embed/${segments[1]}`;
  }
  if (host === 'tiktok.com' || host.endsWith('.tiktok.com')) {
    const at = segments.indexOf('video');
    const id = at >= 0 ? segments[at + 1] : undefined;
    return id && /^\d{10,}$/.test(id) ? `https://www.tiktok.com/embed/v2/${id}` : null;
  }
  if (host === 'instagram.com' && ['reel', 'reels', 'p', 'tv'].includes(segments[0]) && /^[A-Za-z0-9_-]{5,}$/.test(segments[1] || '')) {
    return `https://www.instagram.com/${segments[0] === 'reels' ? 'reel' : segments[0]}/${segments[1]}/embed/`;
  }
  if (host === 'docs.google.com' && segments[0] === 'presentation' && segments[1] === 'd' && segments[2]) {
    return `https://docs.google.com/presentation/d/${segments[2]}/embed?start=false&loop=false`;
  }
  if (host === 'figma.com' && ['file', 'design', 'proto', 'slides', 'board', 'deck'].includes(segments[0])) {
    return `https://www.figma.com/embed?embed_host=stash&url=${encodeURIComponent(value)}`;
  }
  return null;
}

/** Describes the image delivery route the current web UI selects. It does not
 * certify a browser load, crop, iframe contents, or model judgment. The caller
 * must validate ownership and allowed network destinations before collection. */
export function resolveVisualSurfaces(item: VisualItem, supabaseUrl: string): VisualSurface[] {
  if (item.type !== 'link') return [
    { surface: 'card', mode: 'unsupported', reason: 'object_type_not_monitored' },
    { surface: 'detail', mode: 'unsupported', reason: 'object_type_not_monitored' },
  ];
  const base = supabaseUrl.replace(/\/+$/, '');
  const path = item.file_path;
  const external = Boolean(path?.startsWith('http'));
  // getPublicUrl uses encodeURI over the whole address, including existing % escapes.
  const source = !path ? null : external ? path : encodeURI(`${base}/storage/v1/object/public/stash-media/${path}`);
  const card: VisualSurface = !item.url
    ? { surface: 'card', mode: 'missing', reason: 'link_url_missing' }
    : item.attributes?.link?.flavor === 'repo'
      ? { surface: 'card', mode: 'generated', reason: 'repository_plate' }
      : source
        ? { surface: 'card', mode: 'image', source_url: source, display_url: external ? `${base}/functions/v1/image-proxy?url=${encodeURIComponent(source)}` : source }
        : { surface: 'card', mode: 'missing', reason: 'no_preview_image' };

  const canonical = item.attributes?.link?.canonical_url || item.attributes?.enrichment?.evidence?.canonical_url || item.url;
  const embed = embedUrl(canonical);
  const detail: VisualSurface = embed
    ? { surface: 'detail', mode: 'embed', source_url: canonical, display_url: embed, reason: 'embedded_content' }
    : source
      ? { surface: 'detail', mode: 'image', source_url: source, display_url: source }
      : { surface: 'detail', mode: 'missing', reason: 'no_preview_image' };
  return [card, detail];
}
