import { isPublicPreviewUrl } from './previewUrl.ts';

const decode = (value: string) => value.replace(/&amp;/g, '&').replace(/&quot;/g, '"').replace(/&#39;/g, "'");
const attributes = (tag: string): Record<string, string> => Object.fromEntries(
  [...tag.matchAll(/([\w:-]+)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))/g)].map(m => [m[1].toLowerCase(), decode(m[2] ?? m[3] ?? m[4] ?? '')]),
);
const unrelated = /(?:favicon|\blogo\b|\bavatar\b|\bicon\b|\btracking\b|\bpixel\b|\brecommendation\b)/i;
const relatedBoundary = /^(?:#{1,6}\s*)?(?:you may also like|style with|shop the look|complete the look|related (?:articles|products|posts)|recommended (?:for you|products)|more from this author)\s*$/im;
/** Recognisable site furniture is not evidence of the object being saved. */
export function isPageChromeImage(value: string): boolean {
  try {
    const path = new URL(value, 'https://example.com').pathname;
    return unrelated.test(path) || /(?:^|\/)(?:nav|navbar|navigation|header|footer)(?:\/|$)/i.test(path);
  } catch { return false; }
}
const words = (value: string) => [...new Set(value.toLowerCase().split(/[^a-z0-9]+/).filter(w => w.length > 3))];
const MAX_IMAGE_URL_LENGTH = 16384;
const srcsetImages = (value = ''): string[] => {
  // Raw OG URLs are the common case. Do not run an unanchored descriptor
  // regex over them: a long URL without whitespace causes quadratic retries.
  if (!value || value.length > 65536 || !/\s/.test(value)) return [];
  const images: Array<{ url: string; size: number }> = [];
  let cursor = 0;
  for (let entries = 0; cursor < value.length && entries < 32; entries++) {
    while (cursor < value.length && /[\s,]/.test(value[cursor])) cursor++;
    const start = cursor;
    // Commas inside CDN transformation URLs belong to the URL token.
    while (cursor < value.length && !/\s/.test(value[cursor])) cursor++;
    const url = value.slice(start, cursor);
    while (cursor < value.length && /\s/.test(value[cursor])) cursor++;
    const descriptorStart = cursor;
    while (cursor < value.length && value[cursor] !== ',') cursor++;
    const descriptor = value.slice(descriptorStart, cursor).trim();
    const match = descriptor.length <= 24 && descriptor.match(/^(\d+(?:\.\d+)?)(w|x)$/);
    if (url.length <= MAX_IMAGE_URL_LENGTH && match && Number(match[1]) > 0) images.push({ url, size: Number(match[1]) });
    cursor++;
  }
  return images.sort((a, b) => b.size - a.size).map(image => image.url);
};
const undersizedMediumCrop = (url: URL): boolean => {
  if (url.hostname !== 'miro.medium.com') return false;
  const dimensions = url.pathname.match(/^\/v2\/resize:fill:(\d{1,5}):(\d{1,5})\//);
  // These explicit output dimensions already fail preview storage's minimum.
  return !!dimensions && (Number(dimensions[1]) < 100 || Number(dimensions[2]) < 60);
};
const undersizedAmplienceImage = (url: URL): boolean => {
  if (url.hostname !== 'cdn.media.amplience.net' || !/^\/i\/[^/]+\/[^/]+/.test(url.pathname)) return false;
  // Amplience w/h are output pixels. Additional geometry/presets could change
  // that interpretation, so only reject the simple, documented delivery case.
  // https://amplience.com/developers/docs/apis/media-delivery/media-delivery-reference/sizing-and-scaling/
  const seen = new Set<string>();
  for (const [key] of url.searchParams) {
    if (!['w', 'h', 'fmt', 'qlt', 'bg'].includes(key) || seen.has(key)) return false;
    seen.add(key);
  }
  const width = url.searchParams.get('w'), height = url.searchParams.get('h');
  if ([width, height].some(value => value !== null && !/^[1-9]\d{0,4}$/.test(value))) return false;
  return (width !== null && Number(width) < 100) || (height !== null && Number(height) < 60);
};

const markdownPunctuation = (value = '') => {
  const code = value.charCodeAt(0);
  return (code >= 33 && code <= 47) || (code >= 58 && code <= 64) || (code >= 91 && code <= 96) || (code >= 123 && code <= 126);
};
const unescapeMarkdown = (value: string) => value.replace(/\\(.)/g, (match, char: string) => markdownPunctuation(char) ? char : match);
/** Scan inline images once; nested URL parentheses must not close the image. */
function markdownImages(text: string): Array<{ url: string; alt: string }> {
  const result: Array<{ url: string; alt: string }> = [];
  const labels: Array<{ start: number; depth: number }> = [];
  let cursor = 0;
  let brackets = 0;
  const escaped = () => text[cursor] === '\\' && markdownPunctuation(text[cursor + 1]);
  const linkSpace = () => [' ', '\t', '\n', '\r'].includes(text[cursor]);
  while (cursor < text.length) {
    if (escaped()) { cursor += 2; continue; }
    // Match labels as their closing bracket arrives. An incomplete outer
    // label cannot consume a complete nested image; no rescanning is needed.
    if (text[cursor] === '!' && text[cursor + 1] === '[') {
      labels.push({ start: cursor + 2, depth: ++brackets }); cursor += 2; continue;
    }
    if (text[cursor] === '[') { brackets++; cursor++; continue; }
    if (text[cursor] !== ']') { cursor++; continue; }
    const label = labels.at(-1)?.depth === brackets ? labels.pop() : undefined;
    brackets = Math.max(0, brackets - 1);
    const altEnd = cursor++;
    if (!label || text[cursor] !== '(') continue;
    cursor++;
    while (linkSpace()) cursor++;
    const angle = text[cursor] === '<';
    if (angle) cursor++;
    const start = cursor;
    let depth = 0;
    while (cursor < text.length && text[cursor] !== '\n' && text[cursor] !== '\r') {
      if (escaped()) { cursor += 2; continue; }
      const char = text[cursor];
      if (angle ? char === '>' || char === '<' : /\s/.test(char) || (char === ')' && depth === 0) || char === '<' || char === '>') break;
      if (!angle && char === '(') depth++;
      if (!angle && char === ')') depth--;
      cursor++;
    }
    const end = cursor;
    if (depth !== 0 || (angle && text[cursor] !== '>')) continue;
    if (angle) cursor++;
    const separated = linkSpace();
    while (linkSpace()) cursor++;
    if (separated && ['"', "'", '('].includes(text[cursor])) {
      const close = text[cursor] === '(' ? ')' : text[cursor]; cursor++;
      while (cursor < text.length && text[cursor] !== close) {
        if (close === ')' && (text[cursor] === '\n' || text[cursor] === '\r')) break;
        cursor += escaped() ? 2 : 1;
      }
      if (text[cursor] !== close) continue;
      cursor++;
      while (linkSpace()) cursor++;
    }
    if (text[cursor] !== ')') continue;
    cursor++;
    if (end > start && end - start <= MAX_IMAGE_URL_LENGTH) {
      // Bound label copies for deeply nested/malformed input as well as URLs.
      result.push({ url: unescapeMarkdown(text.slice(start, end)), alt: unescapeMarkdown(text.slice(label.start, Math.min(altEnd, label.start + 2048))) });
    }
  }
  return result;
}

/** Ordered, bounded candidates associated with this object; never arbitrary page-wide images. */
export interface PreviewImageEvidence { url: string; associated: boolean; }
export function previewImageEvidence(input: { url: string; html?: string; text?: string; title?: string }): PreviewImageEvidence[] {
  if (!isPublicPreviewUrl(input.url)) return [];
  const html = (input.html || '').slice(0, 1_500_000);
  const title = html.match(/<h1\b[^>]*>([\s\S]*?)<\/h1>/i)?.[1]?.replace(/<[^>]*>/g, ' ') ||
    html.match(/<title\b[^>]*>([^<]*)<\/title>/i)?.[1] || (input.text || '').match(/^#\s+(.+)$/m)?.[1] || input.title || '';
  const titleWords = words(decode(title.split(/\s[|—]\s/)[0]));
  const relevance = (alt: string) => words(alt).filter(w => titleWords.includes(w)).length;
  const matchesTitle = (alt: string) => titleWords.length > 0 && relevance(alt) === titleWords.length;
  let productId = '', selectedColor = '';
  try {
    const source = new URL(input.url);
    for (const [key, value] of source.searchParams) {
      const variant = key.match(/^dwvar_(.+)_colou?r$/i);
      if (variant) { productId = variant[1].toLowerCase(); selectedColor = value.toLowerCase(); break; }
    }
  } catch { /* Invalid source URLs produce no candidates below. */ }
  const candidates: Array<{ url: string; alt: string; priority: number; associated: boolean }> = [];
  const add = (value: unknown, alt = '', priority = 2, associated = matchesTitle(alt)) => {
    if (typeof value !== 'string' || value.length > MAX_IMAGE_URL_LENGTH || !value.trim() || unrelated.test(value)) return;
    try {
      const resolved = new URL(decode(value.trim()), input.url);
      const filename = resolved.pathname.split('/').pop()?.toLowerCase() || '';
      // Salesforce Commerce URLs explicitly bind a product id to its colour.
      // Enforce that relationship only where the observed filename encodes it.
      if (productId && selectedColor && filename.startsWith(`${productId}_`)) {
        const color = filename.slice(productId.length + 1).split(/[_.]/)[0];
        if (color !== selectedColor) return;
        associated = true;
      }
      // "Logo", "Icon" and "Pixel" can name the actual saved product. A
      // source association may establish that name, but never overrides a
      // navigation/icon asset path or a conflicting product colour.
      if (!associated && unrelated.test(alt)) return;
      if (isPublicPreviewUrl(resolved.href) && !isPageChromeImage(resolved.href) && !undersizedMediumCrop(resolved) && !undersizedAmplienceImage(resolved)) candidates.push({ url: resolved.href, alt, priority, associated });
    } catch { /* Invalid publisher URL is not an image candidate. */ }
  };
  for (const tag of html.match(/<meta\b[^>]*>/gi) || []) {
    const attr = attributes(tag);
    if (/^(?:og:image(?::secure_url|:url)?|twitter:image(?::src)?)$/i.test(attr.property || attr.name || '')) {
      const images = srcsetImages(attr.content); (images.length ? images : [attr.content]).forEach(image => add(image, '', 0));
    }
  }
  const addImage = (value: unknown, name = '', associated = false) => {
    if (Array.isArray(value)) value.slice(0, 10).forEach(v => addImage(v, name, associated));
    else if (value && typeof value === 'object') {
      const image = value as Record<string, unknown>;
      add(image.url || image.contentUrl, name, 1, associated);
    } else add(value, name, 1, associated);
  };
  const nodes: Record<string, unknown>[] = [];
  const visit = (value: unknown, depth = 0) => {
    if (!value || depth > 5) return;
    if (Array.isArray(value)) { value.slice(0, 20).forEach(v => visit(v, depth + 1)); return; }
    if (typeof value !== 'object') return;
    const object = value as Record<string, unknown>;
    nodes.push(object);
    visit(object['@graph'], depth + 1); visit(object.mainEntity, depth + 1);
  };
  for (const match of html.matchAll(/<script\b[^>]*type=["']application\/ld\+json["'][^>]*>([\s\S]*?)<\/script>/gi)) {
    try { visit(JSON.parse(match[1])); } catch { /* Malformed JSON-LD must not break capture. */ }
  }
  const pageIdentities = new Set<string>();
  const identity = (value: unknown): string | undefined => {
    if (typeof value !== 'string') return;
    try {
      const u = new URL(value, input.url); u.hash = '';
      // Only recognised attribution parameters are disposable. Variant,
      // access and unknown parameters may identify a different source.
      for (const key of [...u.searchParams.keys()]) {
        if (/^(?:utm_[a-z0-9_]+|gclid|dclid|fbclid|msclkid|mc_cid|mc_eid)$/i.test(key)) u.searchParams.delete(key);
      }
      return u.href;
    } catch { return; }
  };
  const original = identity(input.url); if (original) pageIdentities.add(original);
  for (const tag of html.match(/<link\b[^>]*>/gi) || []) {
    const attr = attributes(tag), canonical = identity(attr.href);
    if (attr.rel === 'canonical' && canonical && new URL(canonical).origin === new URL(input.url).origin) pageIdentities.add(canonical);
  }
  const productNodes = nodes.filter(object => /(?:^|\s)Product(?:\s|$)/.test(Array.isArray(object['@type']) ? object['@type'].join(' ') : String(object['@type'] || '')));
  const namedMatches = productNodes.filter(object => typeof object.name === 'string' && matchesTitle(object.name));
  for (const object of nodes) {
    const type = Array.isArray(object['@type']) ? object['@type'].join(' ') : String(object['@type'] || '');
    if (/Article|BlogPosting|NewsArticle|Product|VideoObject|SocialMediaPosting|WebPage/.test(type)) {
      const name = typeof object.name === 'string' ? object.name : typeof object.headline === 'string' ? object.headline : '';
      const offers = Array.isArray(object.offers) ? object.offers.slice(0, 20) : [object.offers];
      const explicitUrls = [object.url, ...offers.map(offer => offer && typeof offer === 'object' ? offer.url : undefined)].map(identity).filter(Boolean) as string[];
      const objectUrls = [...explicitUrls, identity(object['@id'])].filter(Boolean) as string[];
      const bound = objectUrls.some(url => pageIdentities.has(url)) || !!(productId && [object.sku, object.mpn].some(value => String(value || '').toLowerCase() === productId));
      // A shared SKU or a page-local graph id cannot override an explicit
      // different-product/variant URL. Publisher canonical URLs still count.
      const conflictingUrl = explicitUrls.some(url => !pageIdentities.has(url));
      const productAccepted = !conflictingUrl && (bound || (!objectUrls.length && namedMatches.length === 1 && matchesTitle(name)));
      if (!/Product/.test(type) || productAccepted) {
        const associated = bound || matchesTitle(name);
        addImage(object.image, name, associated); addImage(object.thumbnailUrl, name, associated); addImage(object.primaryImageOfPage, name, associated);
      }
    }
  }
  const main = html.match(/<(article|main)\b[^>]*>([\s\S]*?)<\/\1>/i)?.[2] || '';
  let scoped = main.replace(/<(?:nav|footer|aside|header|script|style)\b[^>]*>[\s\S]*?<\/(?:nav|footer|aside|header|script|style)>/gi, '');
  for (const heading of scoped.matchAll(/<h([1-6])\b[^>]*>([\s\S]*?)<\/h\1>/gi)) {
    const label = decode(heading[2].replace(/<[^>]*>/g, ' ')).replace(/\s+/g, ' ').trim();
    if (relatedBoundary.test(label)) { scoped = scoped.slice(0, heading.index); break; }
  }
  // Keep a picture's responsive source tied to its img's identity/alt text.
  const withPictures = scoped.replace(/<picture\b[^>]*>([\s\S]*?)<\/picture>/gi, (_all, body: string) => {
    const img = body.match(/<img\b[^>]*>/i)?.[0] || '';
    const attr = attributes(img);
    for (const source of body.match(/<source\b[^>]*>/gi) || []) {
      for (const image of srcsetImages(attributes(source).srcset)) add(image, attr.alt || '', 2);
    }
    return img;
  });
  for (const tag of withPictures.match(/<img\b[^>]*>/gi) || []) {
    const attr = attributes(tag);
    if ((attr.width && Number(attr.width) < 100) || (attr.height && Number(attr.height) < 60)) continue;
    for (const image of [...srcsetImages(attr.srcset || attr['data-srcset']), attr['data-src'], attr.src]) add(image, attr.alt || '', 2);
  }
  const text = (input.text || '').slice(0, 100_000).split(relatedBoundary)[0];
  for (const image of markdownImages(text)) add(image.url, image.alt, 2);
  // Once the source identifies this object, never fall through to a generic
  // campaign image just because downloading the associated image failed.
  const selected = candidates.some(c => c.associated) ? candidates.filter(c => c.associated) : candidates;
  selected.sort((a, b) => a.priority - b.priority || relevance(b.alt) - relevance(a.alt));
  return [...new Map(selected.map(({url,associated}) => [url,{url,associated}])).values()].slice(0, 5);
}

/** Compatibility surface for extractors that only need candidate URLs. */
export function previewImageCandidates(input: Parameters<typeof previewImageEvidence>[0]): string[] {
  return previewImageEvidence(input).map(candidate => candidate.url);
}
