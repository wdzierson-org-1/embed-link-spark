import type { JSONContent } from 'novel';

/**
 * The pictures inside a note, as the platform reads them: the `image` nodes of the Novel
 * document whose `src` is a web address (an inline `data:` picture is a paste the editor has
 * not uploaded yet). Mirrors supabase/functions/_shared/noteImages.ts `noteImageSources`;
 * keep the two in step (noteImages.parity.test.ts). The web only needs to know *whether* a
 * saved note has pictures, to ask `analyze-note-images` to describe them.
 */
export const noteImageSources = (content: string | null | undefined): string[] => {
  if (typeof content !== 'string') return [];
  const trimmed = content.trim();
  if (!trimmed.startsWith('{')) return [];
  let doc: JSONContent;
  try {
    doc = JSON.parse(trimmed) as JSONContent;
  } catch {
    return [];
  }
  if (!doc || doc.type !== 'doc' || !Array.isArray(doc.content)) return [];

  const sources: string[] = [];
  const walk = (node: JSONContent) => {
    const src = node.attrs?.src;
    if (node.type === 'image' && typeof src === 'string' && /^https?:\/\//i.test(src.trim())) {
      const address = src.trim();
      if (!sources.includes(address)) sources.push(address);
    }
    node.content?.forEach(walk);
  };
  walk(doc);
  return sources;
};

/** A note that holds pictures now, or held described ones before: either way the platform reconciles */
export const noteNeedsPictureAnalysis = (row: { content?: string | null; attributes?: unknown } | null | undefined): boolean => {
  if (!row) return false;
  if (noteImageSources(row.content).length > 0) return true;
  const attributes = row.attributes as { note_images?: unknown } | null | undefined;
  return Boolean(attributes && typeof attributes === 'object' && attributes.note_images);
};
