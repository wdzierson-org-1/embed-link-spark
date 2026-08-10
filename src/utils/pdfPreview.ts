// First-page PDF preview for the edit panel. pdfjs is lazy-imported (same as
// localFileAnalysis) so the main bundle is unchanged.

// Rendered previews keyed by file URL — reopening the edit sheet for the same
// document must not refetch and re-render the PDF.
const previewCache = new Map<string, string>();

const RENDER_WIDTH = 1200; // ~2x the edit panel's content width, crisp on retina

export const renderPdfFirstPage = async (fileUrl: string): Promise<string | null> => {
  const cached = previewCache.get(fileUrl);
  if (cached) return cached;

  try {
    const pdfjs = await import('pdfjs-dist');
    if (!pdfjs.GlobalWorkerOptions.workerSrc) {
      const worker = await import('pdfjs-dist/build/pdf.worker.min.mjs?url');
      pdfjs.GlobalWorkerOptions.workerSrc = worker.default;
    }

    const doc = await pdfjs.getDocument({ url: fileUrl }).promise;
    try {
      const page = await doc.getPage(1);
      const baseViewport = page.getViewport({ scale: 1 });
      if (!baseViewport.width) return null;
      const viewport = page.getViewport({ scale: RENDER_WIDTH / baseViewport.width });

      const canvas = document.createElement('canvas');
      canvas.width = Math.ceil(viewport.width);
      canvas.height = Math.ceil(viewport.height);
      const context = canvas.getContext('2d');
      if (!context) return null;

      await page.render({ canvasContext: context, viewport }).promise;
      const dataUrl = canvas.toDataURL('image/png');
      previewCache.set(fileUrl, dataUrl);
      return dataUrl;
    } finally {
      void doc.destroy();
    }
  } catch (error) {
    console.error('PDF preview render failed:', error);
    return null;
  }
};
