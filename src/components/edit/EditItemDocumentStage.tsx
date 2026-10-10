import React, { useEffect, useRef, useState } from 'react';
import { ChevronLeft, ChevronRight } from 'lucide-react';
import { CropMarks, StatusLine } from '@/components/machine/Machine';
import { PixelMosaic } from '@/components/machine/PixelMosaic';
import { StageRoot, useStage, useStageRef } from '@/components/edit/StageFull';
import { loadPdfjs } from '@/utils/pdfPreview';

export type DocumentKind = 'pdf' | 'office' | 'html' | 'other';

const OFFICE_EXTENSIONS = ['pptx', 'ppt', 'docx', 'doc', 'xlsx', 'xls'];
const OFFICE_MIME = /officedocument|msword|ms-excel|ms-powerpoint/i;

/** How the panel can show an upload: a PDF reader, Microsoft's viewer for Office files, a frame for HTML */
export const documentKind = (filePath: string, mimeType?: string | null): DocumentKind => {
  const ext = filePath.toLowerCase().split('?')[0].split('.').pop() ?? '';
  if (mimeType?.includes('pdf') || ext === 'pdf') return 'pdf';
  if ((mimeType && OFFICE_MIME.test(mimeType)) || OFFICE_EXTENSIONS.includes(ext)) return 'office';
  if (mimeType === 'text/html' || ext === 'html' || ext === 'htm') return 'html';
  return 'other';
};

/** Microsoft's viewer renders the file it fetches from our public bucket, slide by slide */
export const officeViewerUrl = (fileUrl: string): string =>
  `https://view.officeapps.live.com/op/embed.aspx?src=${encodeURIComponent(fileUrl)}`;

const cell =
  'grid h-7 w-7 place-items-center text-muted-foreground transition-colors hover:bg-ink hover:text-white disabled:opacity-30 disabled:hover:bg-transparent disabled:hover:text-muted-foreground focus-visible:outline-none focus-visible:bg-ink focus-visible:text-white';

type PdfDocument = { numPages: number; getPage: (n: number) => Promise<PdfPage>; destroy: () => Promise<void> | void };
type PdfPage = {
  getViewport: (options: { scale: number }) => { width: number; height: number };
  render: (options: { canvasContext: CanvasRenderingContext2D; viewport: { width: number; height: number }; transform?: number[] }) => { promise: Promise<void>; cancel: () => void };
};

/**
 * The PDF reader: one page at a time on a canvas as wide as the stage, crisp on retina, with
 * previous/next and `page 3 of 12` in the machine voice. ← → page when the stage has focus.
 */
const PdfReader = ({ url, full }: { url: string; full: boolean }) => {
  const frameRef = useRef<HTMLDivElement>(null);
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const docRef = useRef<PdfDocument | null>(null);
  const [pages, setPages] = useState(0);
  const [page, setPage] = useState(1);
  const [width, setWidth] = useState(0);
  const [state, setState] = useState<'loading' | 'ready' | 'failed'>('loading');

  useEffect(() => {
    let cancelled = false;
    setState('loading');
    setPages(0);
    setPage(1);
    void (async () => {
      try {
        const pdfjs = await loadPdfjs();
        const doc = (await pdfjs.getDocument({ url }).promise) as unknown as PdfDocument;
        if (cancelled) {
          void doc.destroy();
          return;
        }
        docRef.current = doc;
        setPages(doc.numPages);
        setState('ready');
      } catch (error) {
        console.warn('PDF reader could not open the document:', error);
        if (!cancelled) setState('failed');
      }
    })();
    return () => {
      cancelled = true;
      void docRef.current?.destroy();
      docRef.current = null;
    };
  }, [url]);

  useEffect(() => {
    const frame = frameRef.current;
    if (!frame || typeof ResizeObserver === 'undefined') return;
    const observer = new ResizeObserver(([entry]) => setWidth(Math.floor(entry.contentRect.width)));
    observer.observe(frame);
    setWidth(Math.floor(frame.clientWidth));
    return () => observer.disconnect();
  }, []);

  useEffect(() => {
    const doc = docRef.current;
    const canvas = canvasRef.current;
    if (!doc || !canvas || state !== 'ready' || width <= 0) return;
    let cancelled = false;
    let task: { promise: Promise<void>; cancel: () => void } | null = null;
    void (async () => {
      try {
        const current = await doc.getPage(page);
        if (cancelled) return;
        const base = current.getViewport({ scale: 1 });
        const scale = width / base.width;
        const viewport = current.getViewport({ scale });
        const dpr = Math.min(3, window.devicePixelRatio || 1);
        canvas.width = Math.ceil(viewport.width * dpr);
        canvas.height = Math.ceil(viewport.height * dpr);
        canvas.style.width = `${Math.round(viewport.width)}px`;
        canvas.style.height = `${Math.round(viewport.height)}px`;
        const context = canvas.getContext('2d');
        if (!context) return;
        task = current.render({ canvasContext: context, viewport, transform: dpr !== 1 ? [dpr, 0, 0, dpr, 0, 0] : undefined });
        await task.promise;
      } catch {
        /* a cancelled render, or a page that can't draw: the previous page stays */
      }
    })();
    return () => {
      cancelled = true;
      task?.cancel();
    };
  }, [page, width, state]);

  const previous = () => setPage((p) => Math.max(1, p - 1));
  const next = () => setPage((p) => Math.min(pages || 1, p + 1));
  const onKeyDown = (event: React.KeyboardEvent) => {
    if (event.key === 'ArrowLeft') previous();
    if (event.key === 'ArrowRight') next();
  };

  return (
    <div className={`flex min-h-0 w-full flex-col ${full ? 'h-full' : ''}`} onKeyDown={onKeyDown} tabIndex={0} aria-label="PDF reader">
      <div ref={frameRef} className={`relative w-full ${full ? 'min-h-0 flex-1 overflow-y-auto' : ''}`}>
        {state === 'loading' && (
          <div className="h-64 overflow-hidden border border-line bg-fill">
            <PixelMosaic />
          </div>
        )}
        {state === 'failed' && (
          <div className="py-6">
            <StatusLine tone="error" live={false}>couldn't open this pdf here. open or download it below</StatusLine>
          </div>
        )}
        <canvas ref={canvasRef} className={`block w-full rounded-object border border-line bg-white shadow-object ${state === 'ready' ? '' : 'hidden'}`} />
      </div>
      {pages > 0 && (
        <div className="mt-2 flex items-center justify-center gap-2 font-pixel text-pixel text-muted-foreground">
          <button type="button" onClick={previous} disabled={page <= 1} aria-label="Previous page" className={cell}>
            <ChevronLeft className="h-4 w-4" />
          </button>
          <span role="status" aria-live="polite">page {page} of {pages}</span>
          <button type="button" onClick={next} disabled={page >= pages} aria-label="Next page" className={cell}>
            <ChevronRight className="h-4 w-4" />
          </button>
        </div>
      )}
    </div>
  );
};

/**
 * The item panel's document stage (DESIGN-v2 §12.8): a PDF as a reader, an Office file in
 * Microsoft's viewer (which steps through slides), an uploaded HTML deck in a sandboxed frame.
 * Full size and full screen like every stage. Will, 2026-10-10.
 */
const EditItemDocumentStage = ({ url, kind, title }: { url: string; kind: Exclude<DocumentKind, 'other'>; title: string }) => {
  const stageRef = useStageRef();
  const { full, controls, bar, rootClass } = useStage(stageRef, kind === 'pdf' ? 'pdf' : kind === 'office' ? 'slides' : 'page');

  return (
    <StageRoot ref={stageRef} className={rootClass} data-testid="document-stage" data-kind={kind}>
      {bar}
      {!full && <CropMarks key="marks" />}
      <div key="body" className={full ? 'flex min-h-0 flex-1 flex-col p-6' : 'px-6 py-8'}>
        {kind === 'pdf' && <PdfReader url={url} full={full} />}
        {kind === 'office' && (
          <iframe
            src={officeViewerUrl(url)}
            title={`Document viewer: ${title}`}
            allowFullScreen
            className={`block w-full rounded-object border border-line bg-white shadow-object ${full ? 'h-full' : 'h-[480px]'}`}
          />
        )}
        {kind === 'html' && (
          <iframe
            src={url}
            title={`Page: ${title}`}
            sandbox="allow-scripts allow-pointer-lock allow-presentation"
            referrerPolicy="no-referrer"
            className={`block w-full rounded-object border border-line bg-white shadow-object ${full ? 'h-full' : 'h-[480px]'}`}
          />
        )}
      </div>
      {controls}
    </StageRoot>
  );
};

export default EditItemDocumentStage;
