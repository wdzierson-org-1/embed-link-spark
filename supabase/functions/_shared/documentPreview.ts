// supabase/functions/_shared/documentPreview.ts
//
// A document's first page as its picture (docs/ui-changes.md 2026-10-10 "Documents show
// their first page"; Will: "let's use an image of the first slide from the uploaded
// presentation for the card preview image"). Runs in add-file's document branch, after the
// response, before text extraction, and never fails the save.
//
//   attributes.media.preview = { file_path, source, rendered_at }
//
// `file_path` is a picture in the person's own storage folder (`<uid>/previews/doc_<id>.png`
// or `.jpg`), the same place rendered maps live; `source` says how it was made:
//   'pdf-page-1'      — page 1 of a PDF, drawn by the document-preview renderer
//                       (api/document-preview.ts on Vercel; DOCUMENT_PREVIEW_URL + _SECRET)
//   'ooxml-thumbnail' — the preview an Office app saved inside a pptx/docx/xlsx package
//                       (docProps/thumbnail.*; PowerPoint and Keynote write one, some
//                       exporters don't — then the card keeps its drawn page)
// Cards read it through `readDocumentPreview`; unknown keys of `media` are preserved.
import { unzipSync } from 'https://esm.sh/fflate@0.8.2';

export type PreviewSource = 'pdf-page-1' | 'ooxml-thumbnail';

export interface DocumentPreview {
  file_path: string;
  source: PreviewSource;
  rendered_at: string;
}

export interface PreviewItem {
  id: string;
  user_id: string;
  mime_type: string | null;
}

export interface PreviewOptions {
  /** The document's public address (what the renderer and the unzip step fetch) */
  publicUrl: string;
  rendererUrl?: string;
  rendererSecret?: string;
  fetcher?: typeof fetch;
  unzip?: (data: Uint8Array) => Record<string, Uint8Array>;
}

export type PreviewOutcome = { kept: true; preview: DocumentPreview } | { skipped: string };

export const OOXML_MIMES = new Set([
  'application/vnd.openxmlformats-officedocument.presentationml.presentation',
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
]);

const MAX_PACKAGE_BYTES = 40 * 1024 * 1024;
const RENDER_MS = 45_000;
const FETCH_MS = 30_000;

interface Picture {
  bytes: Uint8Array;
  contentType: 'image/jpeg' | 'image/png';
  ext: 'jpg' | 'png';
}

const sniff = (bytes: Uint8Array): Picture | null => {
  if (bytes.length > 4 && bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff) return { bytes, contentType: 'image/jpeg', ext: 'jpg' };
  if (bytes.length > 8 && bytes[0] === 0x89 && bytes[1] === 0x50 && bytes[2] === 0x4e && bytes[3] === 0x47) return { bytes, contentType: 'image/png', ext: 'png' };
  return null; // wmf/emf thumbnails exist too; browsers can't show them
};

/**
 * The preview picture an Office app saved inside an OOXML package, when there is one. The
 * package relationships name it (Type …/metadata/thumbnail); `docProps/thumbnail.*` is the
 * conventional place and the fallback.
 */
export const ooxmlThumbnail = (bytes: Uint8Array, unzip: PreviewOptions['unzip'] = unzipSync): Picture | null => {
  let files: Record<string, Uint8Array>;
  try {
    files = unzip(bytes);
  } catch {
    return null;
  }
  let target: string | undefined;
  const rels = files['_rels/.rels'];
  if (rels) {
    const xml = new TextDecoder().decode(rels);
    const element = xml.match(/<Relationship\b[^>]*Type="[^"]*\/metadata\/thumbnail"[^>]*>/i)?.[0];
    const named = element?.match(/Target="([^"]+)"/i)?.[1];
    if (named) target = named.replace(/^\//, '');
  }
  if (!target || !files[target]) {
    target = Object.keys(files).find((name) => /^docProps\/thumbnail\.(jpe?g|png)$/i.test(name));
  }
  if (!target) return null;
  const data = files[target];
  return data?.length ? sniff(data) : null;
};

const fetchBytes = async (fetcher: typeof fetch, url: string, init: RequestInit, max: number): Promise<Uint8Array | { skipped: string }> => {
  const response = await fetcher(url, init);
  if (!response.ok) return { skipped: `fetch_${response.status}` };
  if (Number(response.headers.get('content-length') ?? 0) > max) return { skipped: 'too_large' };
  const bytes = new Uint8Array(await response.arrayBuffer());
  return bytes.byteLength > max ? { skipped: 'too_large' } : bytes;
};

/**
 * Make the document's picture and record it. Throws only on storage/database failure (the
 * caller logs; the save stands); everything about the document itself is a `skipped` outcome.
 */
export const runDocumentPreviewStep = async (db: any, item: PreviewItem, options: PreviewOptions): Promise<PreviewOutcome> => {
  const fetcher = options.fetcher ?? fetch;
  const mime = item.mime_type ?? '';
  let picture: Picture | null = null;
  let source: PreviewSource;

  if (mime === 'application/pdf') {
    if (!options.rendererUrl || !options.rendererSecret) return { skipped: 'renderer_not_configured' };
    const rendered = await fetchBytes(
      fetcher,
      `${options.rendererUrl}?url=${encodeURIComponent(options.publicUrl)}`,
      { headers: { authorization: `Bearer ${options.rendererSecret}` }, signal: AbortSignal.timeout(RENDER_MS) },
      MAX_PACKAGE_BYTES,
    );
    if (!(rendered instanceof Uint8Array)) return { skipped: `renderer_${rendered.skipped}` };
    picture = sniff(rendered);
    if (!picture) return { skipped: 'renderer_not_a_picture' };
    source = 'pdf-page-1';
  } else if (OOXML_MIMES.has(mime)) {
    const packageBytes = await fetchBytes(fetcher, options.publicUrl, { signal: AbortSignal.timeout(FETCH_MS) }, MAX_PACKAGE_BYTES);
    if (!(packageBytes instanceof Uint8Array)) return packageBytes;
    picture = ooxmlThumbnail(packageBytes, options.unzip);
    if (!picture) return { skipped: 'no_embedded_thumbnail' };
    source = 'ooxml-thumbnail';
  } else {
    return { skipped: 'unsupported_type' };
  }

  const path = `${item.user_id}/previews/doc_${item.id}.${picture.ext}`;
  const { error: uploadError } = await db.storage.from('stash-media').upload(path, picture.bytes, { contentType: picture.contentType, upsert: true });
  if (uploadError) throw uploadError;

  // attributes.media is read-merge-write, as add-file's own media step does: preserve every
  // key we don't model
  const { data: current, error: readError } = await db.from('items').select('attributes').eq('id', item.id).single();
  if (readError) throw readError;
  const attributes = ((current?.attributes ?? {}) as Record<string, unknown>) ?? {};
  const media = (attributes.media ?? {}) as Record<string, unknown>;
  const preview: DocumentPreview = { file_path: path, source, rendered_at: new Date().toISOString() };
  const { error: writeError } = await db
    .from('items')
    .update({ attributes: { ...attributes, media: { ...media, preview } } })
    .eq('id', item.id);
  if (writeError) throw writeError;
  return { kept: true, preview };
};

/** The preview a save carries, when it is well formed */
export const readDocumentPreview = (attributes: Record<string, unknown> | null | undefined): DocumentPreview | null => {
  const media = attributes?.media as { preview?: Partial<DocumentPreview> } | undefined;
  const preview = media?.preview;
  if (!preview || typeof preview.file_path !== 'string' || !preview.file_path) return null;
  if (preview.source !== 'pdf-page-1' && preview.source !== 'ooxml-thumbnail') return null;
  return { file_path: preview.file_path, source: preview.source, rendered_at: typeof preview.rendered_at === 'string' ? preview.rendered_at : '' };
};
