/**
 * The first page of a PDF as a picture (docs/ui-changes.md 2026-10-10 "Documents show their
 * first page"). The capture pipeline (add-file's preview step, _shared/documentPreview.ts)
 * asks here for a PDF it has just stored, and puts the answer in the person's storage folder
 * as the card's picture. This runs on Vercel's Node runtime because rendering a page needs a
 * canvas: pdf.js (the same library the panel's reader uses) draws on @napi-rs/canvas.
 *
 * Contract: `GET /api/document-preview?url=<public stash-media object>` with
 * `Authorization: Bearer <DOCUMENT_PREVIEW_SECRET>` → `image/png`, the first page at 1200 px
 * wide, with `X-Page-Count`, `X-Preview-Width`, `X-Preview-Height`. Only objects in the
 * public stash-media bucket are fetched, only with the shared secret: this is not a public
 * rendering service.
 */
import { timingSafeEqual } from 'node:crypto';
import { getDocument } from 'pdfjs-dist/legacy/build/pdf.mjs';
// The worker, imported statically: pdf.js otherwise loads it through a computed dynamic import
// that Vercel's file tracer cannot follow — the deployed bundle lacked pdf.worker.mjs and every
// render failed ("Setting up fake worker failed", 2026-10-10). Imported, it registers itself as
// the in-thread handler and no worker file is looked up at all.
import 'pdfjs-dist/legacy/build/pdf.worker.mjs';
import { createCanvas } from '@napi-rs/canvas';

const STORAGE_PUBLIC = 'https://uqqsgmwkvslaomzxptnp.supabase.co/storage/v1/object/public/stash-media/';
/** ~2× the card and panel widths, crisp on retina; the same width the panel's reader renders */
export const RENDER_WIDTH = 1200;
const MAX_BYTES = 60 * 1024 * 1024;
const FETCH_MS = 20_000;

export interface RenderedPage {
  png: Buffer;
  width: number;
  height: number;
  pages: number;
}

/** Page 1 of a PDF as a PNG, `width` px wide. Throws when the file is not a PDF pdf.js can open. */
export const renderFirstPage = async (data: Uint8Array, width = RENDER_WIDTH): Promise<RenderedPage> => {
  // pdf.js wants a plain Uint8Array, not a Node Buffer
  const bytes = Buffer.isBuffer(data) ? new Uint8Array(data.buffer, data.byteOffset, data.byteLength) : data;
  const doc = await getDocument({ data: bytes, useSystemFonts: true, disableFontFace: true, isEvalSupported: false }).promise;
  try {
    const page = await doc.getPage(1);
    const base = page.getViewport({ scale: 1 });
    if (!(base.width > 0) || !(base.height > 0)) throw new Error('The first page has no size');
    const viewport = page.getViewport({ scale: width / base.width });
    const canvas = createCanvas(Math.ceil(viewport.width), Math.ceil(viewport.height));
    const context = canvas.getContext('2d');
    // A page is paper: white under whatever the PDF draws (pdf.js leaves transparency alone)
    context.fillStyle = '#ffffff';
    context.fillRect(0, 0, canvas.width, canvas.height);
    await page.render({ canvasContext: context as unknown as CanvasRenderingContext2D, viewport }).promise;
    return { png: canvas.toBuffer('image/png'), width: canvas.width, height: canvas.height, pages: doc.numPages };
  } finally {
    await doc.destroy();
  }
};

interface PreviewRequest {
  query?: Record<string, string | string[] | undefined>;
  headers?: Record<string, string | string[] | undefined>;
}
interface PreviewResponse {
  setHeader(name: string, value: string): unknown;
  status(code: number): { send(body: unknown): unknown; json(body: unknown): unknown };
}
interface PreviewDeps {
  fetcher?: typeof fetch;
  secret?: string;
  render?: (data: Uint8Array) => Promise<RenderedPage>;
}

const first = (value: string | string[] | undefined): string | undefined => (Array.isArray(value) ? value[0] : value);

const bearerMatches = (header: string | undefined, secret: string): boolean => {
  const given = Buffer.from(header?.replace(/^Bearer\s+/i, '') ?? '');
  const wanted = Buffer.from(secret);
  return given.length === wanted.length && timingSafeEqual(given, wanted);
};

export const handleDocumentPreview = async (req: PreviewRequest, res: PreviewResponse, deps: PreviewDeps = {}): Promise<void> => {
  const { fetcher = fetch, secret = process.env.DOCUMENT_PREVIEW_SECRET, render = renderFirstPage } = deps;
  res.setHeader('Cache-Control', 'private, no-store');
  if (!secret || !bearerMatches(first(req.headers?.authorization), secret)) {
    res.status(401).json({ error: 'A bearer secret is required' });
    return;
  }
  const url = first(req.query?.url) ?? '';
  if (!url.startsWith(STORAGE_PUBLIC)) {
    res.status(400).json({ error: 'url must be a public stash-media object' });
    return;
  }

  let response: Response;
  try {
    response = await fetcher(url, { signal: AbortSignal.timeout(FETCH_MS) });
  } catch {
    res.status(502).json({ error: 'The document could not be fetched' });
    return;
  }
  if (!response.ok) {
    res.status(502).json({ error: `The document answered ${response.status}` });
    return;
  }
  if (Number(response.headers.get('content-length') ?? 0) > MAX_BYTES) {
    res.status(413).json({ error: 'The document is too large to render' });
    return;
  }
  const bytes = new Uint8Array(await response.arrayBuffer());
  if (bytes.byteLength > MAX_BYTES) {
    res.status(413).json({ error: 'The document is too large to render' });
    return;
  }

  try {
    const page = await render(bytes);
    res.setHeader('Content-Type', 'image/png');
    res.setHeader('X-Page-Count', String(page.pages));
    res.setHeader('X-Preview-Width', String(page.width));
    res.setHeader('X-Preview-Height', String(page.height));
    res.status(200).send(page.png);
  } catch (error) {
    console.error('document-preview: render failed', url, error);
    res.status(422).json({ error: 'The document could not be rendered' });
  }
};

export default async function handler(req: PreviewRequest, res: PreviewResponse): Promise<void> {
  await handleDocumentPreview(req, res);
}
