interface LinkMetadataShape {
  title?: string;
  description?: string;
  image?: string;
  previewImageUrl?: string;
}

// Turn a URL slug into a readable title, instantly and locally — the honest
// placeholder shown when a site blocks its preview metadata. Server-side
// enrichment upgrades it after the item is saved.
export const humanizeUrlSlug = (url: string): string | null => {
  try {
    const parsed = new URL(url);
    const segments = parsed.pathname.split('/').filter(Boolean).map(decodeURIComponent);
    const candidate = segments
      .filter(segment => !segment.startsWith('@'))
      .sort((a, b) => b.length - a.length)[0] || '';

    const slug = candidate
      .replace(/\.(html?|php|aspx?)$/i, '')
      .replace(/-[0-9a-f]{8,}$/i, '')
      .replace(/[-_+]+/g, ' ')
      .replace(/\s+/g, ' ')
      .trim();

    if (slug.length < 8 || !/[a-z]/i.test(slug)) return null;

    return slug.replace(/\b\w/g, char => char.toUpperCase());
  } catch {
    return null;
  }
};

// Metadata that only names the hostname (or is missing outright) means the
// site blocked the preview fetch
export const isWeakLinkMetadata = (
  metadata: LinkMetadataShape | null | undefined,
  url: string
): boolean => {
  if (!metadata) return true;
  const title = (metadata.title || '').trim().toLowerCase();
  if (!title) return true;
  try {
    const hostname = new URL(url).hostname.toLowerCase();
    if (title === hostname || title === hostname.replace(/^www\./, '')) return true;
  } catch {
    return true;
  }
  return !metadata.description && !metadata.image && !metadata.previewImageUrl;
};
