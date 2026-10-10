// @vitest-environment node
import { strToU8, unzipSync, zipSync } from 'fflate';
import { beforeEach, describe, expect, it, vi } from 'vitest';

// The edge function imports fflate from esm.sh; the test runs on the npm package
vi.mock('https://esm.sh/fflate@0.8.2', async () => await import('fflate'));

import { ooxmlThumbnail, readDocumentPreview, runDocumentPreviewStep } from './documentPreview.ts';

const JPEG = new Uint8Array([0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 0x4a, 0x46, 0x49, 0x46, 0x00]);
const PNG = new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00]);
const THUMB_REL = 'http://schemas.openxmlformats.org/package/2006/relationships/metadata/thumbnail';

const pptx = (files: Record<string, Uint8Array | string>) =>
  zipSync(Object.fromEntries(Object.entries(files).map(([name, data]) => [name, typeof data === 'string' ? strToU8(data) : data])));

const rels = (target: string) =>
  `<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="ppt/presentation.xml"/><Relationship Target="${target}" Id="rId2" Type="${THUMB_REL}"/></Relationships>`;

describe('ooxmlThumbnail', () => {
  it('finds the thumbnail the package relationships name', () => {
    const bytes = pptx({ '_rels/.rels': rels('/docProps/preview.jpeg'), 'docProps/preview.jpeg': JPEG, 'ppt/presentation.xml': '<p/>' });
    const picture = ooxmlThumbnail(bytes, unzipSync);
    expect(picture?.contentType).toBe('image/jpeg');
    expect(picture?.ext).toBe('jpg');
    expect(picture?.bytes).toEqual(JPEG);
  });

  it('falls back to the conventional docProps/thumbnail.*, and tells a PNG from a JPEG', () => {
    const bytes = pptx({ '_rels/.rels': '<Relationships/>', 'docProps/thumbnail.png': PNG });
    expect(ooxmlThumbnail(bytes, unzipSync)).toMatchObject({ contentType: 'image/png', ext: 'png' });
  });

  it('has nothing for a package without a thumbnail, one browsers cannot show, or a non-package', () => {
    expect(ooxmlThumbnail(pptx({ 'ppt/presentation.xml': '<p/>' }), unzipSync)).toBeNull();
    expect(ooxmlThumbnail(pptx({ 'docProps/thumbnail.wmf': new Uint8Array([0xd7, 0xcd, 0xc6, 0x9a, 0, 0]) }), unzipSync)).toBeNull();
    expect(ooxmlThumbnail(strToU8('%PDF-1.4 not a zip'), unzipSync)).toBeNull();
  });
});

const makeDb = () => {
  const state = { uploaded: null as null | { path: string; bytes: Uint8Array; options: Record<string, unknown> }, attributes: { media: { file_name: 'deck.pptx' }, enrichment: { status: 'pending' } } as Record<string, unknown>, updated: null as null | Record<string, unknown> };
  const db = {
    storage: { from: () => ({ upload: async (path: string, bytes: Uint8Array, options: Record<string, unknown>) => { state.uploaded = { path, bytes, options }; return { error: null }; } }) },
    from: () => ({
      select: () => ({ eq: () => ({ single: async () => ({ data: { attributes: state.attributes }, error: null }) }) }),
      update: (patch: Record<string, unknown>) => { state.updated = patch; return { eq: async () => ({ error: null }) }; },
    }),
  };
  return { db, state };
};

const PUBLIC = 'https://x.supabase.co/storage/v1/object/public/stash-media/u/staging/1.bin';
const item = { id: 'item-1', user_id: 'u', mime_type: 'application/vnd.openxmlformats-officedocument.presentationml.presentation' };

describe('runDocumentPreviewStep', () => {
  beforeEach(() => vi.clearAllMocks());

  it('keeps a presentation’s embedded preview as its picture and records it under media', async () => {
    const { db, state } = makeDb();
    const packageBytes = pptx({ '_rels/.rels': rels('docProps/thumbnail.jpeg'), 'docProps/thumbnail.jpeg': JPEG });
    const fetcher = vi.fn(async () => new Response(packageBytes, { status: 200 })) as unknown as typeof fetch;
    const outcome = await runDocumentPreviewStep(db, item, { publicUrl: PUBLIC, fetcher, unzip: unzipSync });
    expect(fetcher).toHaveBeenCalledWith(PUBLIC, expect.anything());
    expect(outcome).toMatchObject({ kept: true, preview: { file_path: 'u/previews/doc_item-1.jpg', source: 'ooxml-thumbnail' } });
    expect(state.uploaded).toMatchObject({ path: 'u/previews/doc_item-1.jpg', bytes: JPEG, options: { contentType: 'image/jpeg', upsert: true } });
    const attributes = state.updated?.attributes as Record<string, any>;
    expect(attributes.enrichment).toEqual({ status: 'pending' });
    expect(attributes.media.file_name).toBe('deck.pptx');
    expect(attributes.media.preview).toMatchObject({ file_path: 'u/previews/doc_item-1.jpg', source: 'ooxml-thumbnail' });
    expect(attributes.media.preview.rendered_at).toMatch(/^\d{4}-\d{2}-\d{2}T/);
  });

  it('has a PDF’s first page drawn by the renderer, with the shared secret, and keeps the PNG', async () => {
    const { db, state } = makeDb();
    const fetcher = vi.fn(async () => new Response(PNG, { status: 200 })) as unknown as typeof fetch;
    const outcome = await runDocumentPreviewStep(db, { ...item, mime_type: 'application/pdf' }, {
      publicUrl: PUBLIC, fetcher, rendererUrl: 'https://www.gostash.it/api/document-preview', rendererSecret: 's3cret',
    });
    const [url, init] = (fetcher as unknown as ReturnType<typeof vi.fn>).mock.calls[0];
    expect(url).toBe(`https://www.gostash.it/api/document-preview?url=${encodeURIComponent(PUBLIC)}`);
    expect(init.headers).toEqual({ authorization: 'Bearer s3cret' });
    expect(outcome).toMatchObject({ kept: true, preview: { file_path: 'u/previews/doc_item-1.png', source: 'pdf-page-1' } });
    expect(state.uploaded?.options).toEqual({ contentType: 'image/png', upsert: true });
  });

  it('skips honestly: no renderer configured, a renderer failure, no thumbnail, other formats', async () => {
    const { db } = makeDb();
    const noPdf = await runDocumentPreviewStep(db, { ...item, mime_type: 'application/pdf' }, { publicUrl: PUBLIC, fetcher: vi.fn() as unknown as typeof fetch });
    expect(noPdf).toEqual({ skipped: 'renderer_not_configured' });

    const failing = vi.fn(async () => new Response('nope', { status: 422 })) as unknown as typeof fetch;
    const failed = await runDocumentPreviewStep(db, { ...item, mime_type: 'application/pdf' }, { publicUrl: PUBLIC, fetcher: failing, rendererUrl: 'https://r', rendererSecret: 's' });
    expect(failed).toEqual({ skipped: 'renderer_fetch_422' });

    const bare = vi.fn(async () => new Response(pptx({ 'ppt/presentation.xml': '<p/>' }), { status: 200 })) as unknown as typeof fetch;
    expect(await runDocumentPreviewStep(db, item, { publicUrl: PUBLIC, fetcher: bare, unzip: unzipSync })).toEqual({ skipped: 'no_embedded_thumbnail' });

    expect(await runDocumentPreviewStep(db, { ...item, mime_type: 'text/csv' }, { publicUrl: PUBLIC, fetcher: vi.fn() as unknown as typeof fetch })).toEqual({ skipped: 'unsupported_type' });
  });
});

describe('readDocumentPreview', () => {
  it('reads a well-formed preview and nothing else', () => {
    expect(readDocumentPreview({ media: { preview: { file_path: 'u/previews/doc_1.png', source: 'pdf-page-1', rendered_at: 't' } } })).toEqual({ file_path: 'u/previews/doc_1.png', source: 'pdf-page-1', rendered_at: 't' });
    expect(readDocumentPreview({ media: { preview: { file_path: 'u/x.png', source: 'drawn-by-hand' } } })).toBeNull();
    expect(readDocumentPreview({ media: {} })).toBeNull();
    expect(readDocumentPreview(null)).toBeNull();
  });
});
