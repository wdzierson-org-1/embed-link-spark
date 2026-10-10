// @vitest-environment node
import { readFileSync } from 'node:fs';
import { createCanvas, loadImage } from '@napi-rs/canvas';
import { describe, expect, it, vi } from 'vitest';
import { handleDocumentPreview, renderFirstPage } from './document-preview';

/** A one-page PDF: a red square on the left, a blue one on the right, 200×100 pt */
const syntheticPdf = (): Uint8Array => {
  const body = '1 0 0 rg 10 10 80 80 re f 0 0 1 rg 110 10 80 80 re f';
  const objects = [
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 100] /Contents 4 0 R >>',
    `<< /Length ${body.length} >>\nstream\n${body}\nendstream`,
  ];
  let pdf = '%PDF-1.4\n';
  const offsets: number[] = [];
  objects.forEach((object, index) => {
    offsets.push(pdf.length);
    pdf += `${index + 1} 0 obj\n${object}\nendobj\n`;
  });
  const xref = pdf.length;
  pdf +=
    `xref\n0 ${objects.length + 1}\n0000000000 65535 f \n` +
    offsets.map((offset) => `${String(offset).padStart(10, '0')} 00000 n \n`).join('') +
    `trailer\n<< /Root 1 0 R /Size ${objects.length + 1} >>\nstartxref\n${xref}\n%%EOF\n`;
  return new Uint8Array(Buffer.from(pdf, 'latin1'));
};

const pixelAt = async (png: Buffer, x: number, y: number): Promise<number[]> => {
  const image = await loadImage(png);
  const canvas = createCanvas(image.width, image.height);
  const context = canvas.getContext('2d');
  context.drawImage(image, 0, 0);
  return [...context.getImageData(x, y, 1, 1).data];
};

describe('renderFirstPage', () => {
  it('draws the first page at the asked width, as a PNG with what the page shows', async () => {
    const page = await renderFirstPage(syntheticPdf(), 400);
    expect(page.width).toBe(400);
    expect(page.height).toBe(200);
    expect(page.pages).toBe(1);
    expect(page.png.subarray(0, 8)).toEqual(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]));
    expect(await pixelAt(page.png, 100, 100)).toEqual([255, 0, 0, 255]);
    expect(await pixelAt(page.png, 300, 100)).toEqual([0, 0, 255, 255]);
    // Paper is white where the page draws nothing
    expect(await pixelAt(page.png, 200, 5)).toEqual([255, 255, 255, 255]);
  });

  it('renders a real PDF at the preview width', async () => {
    const page = await renderFirstPage(readFileSync('ios/fixtures/uitest-fixture.pdf'));
    expect(page.width).toBe(1200);
    expect(page.height).toBeGreaterThan(0);
    expect(page.pages).toBe(1);
  });

  it('renders without looking up a worker file (the deployed bundle has none to find)', async () => {
    const { GlobalWorkerOptions } = await import('pdfjs-dist/legacy/build/pdf.mjs');
    const before = GlobalWorkerOptions.workerSrc;
    GlobalWorkerOptions.workerSrc = '/nowhere/pdf.worker.mjs';
    try {
      const page = await renderFirstPage(syntheticPdf(), 200);
      expect(page.width).toBe(200);
    } finally {
      GlobalWorkerOptions.workerSrc = before;
    }
  });

  it('refuses what is not a PDF', async () => {
    await expect(renderFirstPage(new Uint8Array(Buffer.from('PK\u0003\u0004 not a pdf')))).rejects.toThrow();
  });
});

const STORAGE = 'https://uqqsgmwkvslaomzxptnp.supabase.co/storage/v1/object/public/stash-media/';

const fakeResponse = () => {
  const headers: Record<string, string> = {};
  const result: { status?: number; body?: unknown } = {};
  const res = {
    setHeader: (name: string, value: string) => { headers[name] = value; },
    status: (code: number) => ({
      send: (body: unknown) => { result.status = code; result.body = body; },
      json: (body: unknown) => { result.status = code; result.body = body; },
    }),
  };
  return { res, headers, result };
};

const fetcherFor = (bytes: Uint8Array, status = 200, contentLength?: number) =>
  vi.fn(async () =>
    new Response(status === 200 ? bytes : 'nope', {
      status,
      headers: contentLength !== undefined ? { 'content-length': String(contentLength) } : {},
    }),
  ) as unknown as typeof fetch;

describe('the document-preview endpoint', () => {
  const secret = 'shared-secret';
  const render = vi.fn(async () => ({ png: Buffer.from('png'), width: 1200, height: 1600, pages: 3 }));

  it('renders a stash-media object for the capture pipeline', async () => {
    const { res, headers, result } = fakeResponse();
    const fetcher = fetcherFor(syntheticPdf());
    await handleDocumentPreview(
      { query: { url: `${STORAGE}u/staging/deck.pdf` }, headers: { authorization: `Bearer ${secret}` } },
      res,
      { fetcher, secret, render },
    );
    expect(fetcher).toHaveBeenCalledWith(`${STORAGE}u/staging/deck.pdf`, expect.anything());
    expect(result.status).toBe(200);
    expect(result.body).toEqual(Buffer.from('png'));
    expect(headers).toMatchObject({ 'Content-Type': 'image/png', 'X-Page-Count': '3', 'X-Preview-Width': '1200', 'X-Preview-Height': '1600', 'Cache-Control': 'private, no-store' });
  });

  it('is not a public rendering service: the secret and our bucket only', async () => {
    const unauthorized = fakeResponse();
    await handleDocumentPreview({ query: { url: `${STORAGE}u/a.pdf` }, headers: {} }, unauthorized.res, { secret, render, fetcher: fetcherFor(syntheticPdf()) });
    expect(unauthorized.result.status).toBe(401);

    const wrongSecret = fakeResponse();
    await handleDocumentPreview({ query: { url: `${STORAGE}u/a.pdf` }, headers: { authorization: 'Bearer other' } }, wrongSecret.res, { secret, render, fetcher: fetcherFor(syntheticPdf()) });
    expect(wrongSecret.result.status).toBe(401);

    const unset = fakeResponse();
    await handleDocumentPreview({ query: { url: `${STORAGE}u/a.pdf` }, headers: { authorization: 'Bearer ' } }, unset.res, { secret: undefined, render, fetcher: fetcherFor(syntheticPdf()) });
    expect(unset.result.status).toBe(401);

    const elsewhere = fakeResponse();
    const fetcher = fetcherFor(syntheticPdf());
    await handleDocumentPreview({ query: { url: 'https://evil.example/file.pdf' }, headers: { authorization: `Bearer ${secret}` } }, elsewhere.res, { secret, render, fetcher });
    expect(elsewhere.result.status).toBe(400);
    expect(fetcher).not.toHaveBeenCalled();
  });

  it('says so when the object cannot be fetched, is too large, or will not render', async () => {
    const missing = fakeResponse();
    await handleDocumentPreview({ query: { url: `${STORAGE}u/a.pdf` }, headers: { authorization: `Bearer ${secret}` } }, missing.res, { secret, render, fetcher: fetcherFor(syntheticPdf(), 404) });
    expect(missing.result.status).toBe(502);

    const huge = fakeResponse();
    await handleDocumentPreview({ query: { url: `${STORAGE}u/a.pdf` }, headers: { authorization: `Bearer ${secret}` } }, huge.res, { secret, render, fetcher: fetcherFor(syntheticPdf(), 200, 61 * 1024 * 1024) });
    expect(huge.result.status).toBe(413);

    const broken = fakeResponse();
    await handleDocumentPreview({ query: { url: `${STORAGE}u/a.pdf` }, headers: { authorization: `Bearer ${secret}` } }, broken.res, { secret, fetcher: fetcherFor(new Uint8Array(Buffer.from('not a pdf'))) });
    expect(broken.result.status).toBe(422);
  });
});
