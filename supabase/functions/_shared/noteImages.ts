// supabase/functions/_shared/noteImages.ts
//
// Pictures inside a note. The editors (web, iOS) let a person put images into their note — a
// Novel/TipTap document with `image` nodes whose `src` is a file in the person's own storage
// folder. The words of a note are read by `plainNotes`; the pictures were read by nobody
// (Will, 2026-10-10: "the entirety of the content should be analyzed, stored, and embedded
// (including the image)"). The `analyze-note-images` function describes each picture once
// and keeps the result here, in `attributes.note_images`, as plain text the index joins:
//
//   attributes.note_images = {
//     version: 1,
//     images: [{ src, description, text?, analyzed_at }]   // one per picture, in note order
//   }
//
// `src` is the picture's address as the note holds it (the cache key: a picture is described
// once, however often the note autosaves); `description` is what it shows; `text` is what it
// says, when it says anything. Keep the web's src/utils/noteImages.ts in step.

export interface NoteImage {
  src: string;
  description: string;
  text?: string;
  analyzed_at: string;
}

export interface NoteImages {
  version: 1;
  images: NoteImage[];
}

interface DocNode {
  type?: string;
  attrs?: Record<string, unknown>;
  content?: DocNode[];
}

const isWebAddress = (src: unknown): src is string =>
  typeof src === 'string' && /^https?:\/\//i.test(src.trim());

/**
 * The addresses of the pictures in a note, in document order, each once. Only web addresses
 * count: an inline `data:` picture is a paste the editor hasn't uploaded yet, and plain-text
 * or HTML notes carry no pictures.
 */
export const noteImageSources = (content: string | null | undefined): string[] => {
  if (typeof content !== 'string') return [];
  const trimmed = content.trim();
  if (!trimmed.startsWith('{')) return [];
  let doc: DocNode;
  try {
    doc = JSON.parse(trimmed) as DocNode;
  } catch {
    return [];
  }
  if (!doc || doc.type !== 'doc' || !Array.isArray(doc.content)) return [];

  const sources: string[] = [];
  const walk = (node: DocNode) => {
    if (node.type === 'image' && isWebAddress(node.attrs?.src)) {
      const src = (node.attrs!.src as string).trim();
      if (!sources.includes(src)) sources.push(src);
    }
    node.content?.forEach(walk);
  };
  walk(doc);
  return sources;
};

/** The stored leaf, when it is well formed; anything else reads as no pictures described. */
export const readNoteImages = (attributes: Record<string, unknown> | null | undefined): NoteImages | null => {
  const leaf = attributes?.note_images as Partial<NoteImages> | undefined;
  if (!leaf || leaf.version !== 1 || !Array.isArray(leaf.images)) return null;
  const images = leaf.images.filter(
    (image): image is NoteImage =>
      !!image && typeof image.src === 'string' && typeof image.description === 'string' && typeof image.analyzed_at === 'string',
  );
  return { version: 1, images };
};

/**
 * What the index reads for the pictures: each one's description and the text it carries,
 * as lines. Empty when there are no described pictures.
 */
export const noteImagesSearchText = (noteImages: NoteImages | null | undefined): string => {
  if (!noteImages?.images.length) return '';
  return noteImages.images
    .map((image) => {
      const text = image.text?.trim();
      return text ? `${image.description.trim()}\nText in the image: ${text}` : image.description.trim();
    })
    .filter(Boolean)
    .join('\n\n');
};

/**
 * Reconcile the stored descriptions with the pictures the note holds now: keep the ones still
 * in the note (in the note's order), name the ones that still need describing.
 */
export const reconcileNoteImages = (
  current: NoteImages | null,
  sources: string[],
): { kept: NoteImage[]; missing: string[] } => {
  const bySrc = new Map((current?.images ?? []).map((image) => [image.src, image]));
  const kept: NoteImage[] = [];
  const missing: string[] = [];
  for (const src of sources) {
    const known = bySrc.get(src);
    if (known) kept.push(known);
    else missing.push(src);
  }
  return { kept, missing };
};
