// Deterministic, no-network extraction of file facts for capture-input chips.
// Heavy parsers (pdfjs, exifr) are lazy-imported so the main bundle is unchanged.

export interface LocalFileFacts {
  factsLine?: string;
  snippet?: string;
  metadataTitle?: string;
  pageCount?: number;
  dimensions?: { width: number; height: number };
  durationSeconds?: number;
  thumbnailDataUrl?: string;
  exifSummary?: string;
}

export type LocalAnalysisKind = 'pdf' | 'image' | 'audio' | 'video' | 'text' | 'other';

const SNIPPET_LIMIT = 1500;
const TEXT_SAMPLE_BYTES = 64 * 1024;
const THUMBNAIL_WIDTH = 120;

export const classifyFile = (file: File): LocalAnalysisKind => {
  if (file.type === 'application/pdf' || /\.pdf$/i.test(file.name)) return 'pdf';
  if (file.type.startsWith('image/')) return 'image';
  if (file.type.startsWith('audio/')) return 'audio';
  if (file.type.startsWith('video/')) return 'video';
  if (file.type.startsWith('text/') || /\.(md|csv|json|txt)$/i.test(file.name)) return 'text';
  return 'other';
};

const withTimeout = <T,>(promise: Promise<T>, ms: number, fallback: T): Promise<T> =>
  Promise.race([
    promise,
    new Promise<T>((resolve) => window.setTimeout(() => resolve(fallback), ms)),
  ]);

const joinFacts = (...parts: Array<string | undefined>): string =>
  parts.filter((part): part is string => Boolean(part && part.trim())).join(' · ');

const formatMb = (bytes: number): string => `${(bytes / 1024 / 1024).toFixed(1)} MB`;

const formatDuration = (totalSeconds: number): string => {
  const minutes = Math.floor(totalSeconds / 60);
  const seconds = Math.round(totalSeconds % 60);
  return `${minutes}:${seconds.toString().padStart(2, '0')}`;
};

const extensionLabel = (file: File): string | undefined =>
  file.name.includes('.') ? file.name.split('.').pop()?.toUpperCase() : undefined;

const analyzeText = async (file: File): Promise<LocalFileFacts> => {
  const sample = await file.slice(0, TEXT_SAMPLE_BYTES).text();
  const words = sample.trim().split(/\s+/).filter(Boolean).length;
  const truncated = file.size > TEXT_SAMPLE_BYTES;
  const estimatedWords = truncated && sample.length > 0
    ? Math.round(words * (file.size / sample.length))
    : words;
  const wordLabel = `${truncated ? '~' : ''}${estimatedWords.toLocaleString()} word${estimatedWords === 1 ? '' : 's'}`;
  return {
    snippet: sample.replace(/\s+/g, ' ').trim().slice(0, SNIPPET_LIMIT) || undefined,
    factsLine: joinFacts(extensionLabel(file) || 'Text', wordLabel, formatMb(file.size)),
  };
};

const readImageDimensions = (file: File): Promise<{ width: number; height: number } | undefined> =>
  withTimeout(
    new Promise<{ width: number; height: number } | undefined>((resolve) => {
      const objectUrl = URL.createObjectURL(file);
      const image = new Image();
      image.onload = () => {
        URL.revokeObjectURL(objectUrl);
        resolve({ width: image.naturalWidth, height: image.naturalHeight });
      };
      image.onerror = () => {
        URL.revokeObjectURL(objectUrl);
        resolve(undefined);
      };
      image.src = objectUrl;
    }),
    3000,
    undefined
  );

const readExifSummary = async (file: File): Promise<string | undefined> => {
  try {
    const exifr = (await import('exifr')).default;
    const exif = await exifr.parse(file, ['DateTimeOriginal', 'Model']);
    if (!exif) return undefined;
    const capturedAt = exif.DateTimeOriginal instanceof Date
      ? exif.DateTimeOriginal.toLocaleDateString(undefined, { month: 'short', year: 'numeric' })
      : undefined;
    const camera = typeof exif.Model === 'string' ? exif.Model.trim() : undefined;
    return joinFacts(capturedAt, camera) || undefined;
  } catch {
    return undefined;
  }
};

const analyzeImage = async (file: File): Promise<LocalFileFacts> => {
  const [dimensions, exifSummary] = await Promise.all([
    readImageDimensions(file),
    readExifSummary(file),
  ]);
  const subtype = file.type.split('/')[1]?.toUpperCase();
  return {
    dimensions,
    exifSummary,
    factsLine: joinFacts(
      subtype || 'Image',
      dimensions ? `${dimensions.width}×${dimensions.height}` : undefined,
      exifSummary,
      formatMb(file.size)
    ),
  };
};

const analyzeAudio = (file: File): Promise<LocalFileFacts> =>
  withTimeout(
    new Promise<LocalFileFacts>((resolve) => {
      const objectUrl = URL.createObjectURL(file);
      const audio = new Audio();
      audio.preload = 'metadata';
      audio.onloadedmetadata = () => {
        URL.revokeObjectURL(objectUrl);
        const duration = Number.isFinite(audio.duration) ? audio.duration : undefined;
        resolve({
          durationSeconds: duration,
          factsLine: joinFacts(
            'Audio',
            duration !== undefined ? formatDuration(duration) : undefined,
            formatMb(file.size)
          ),
        });
      };
      audio.onerror = () => {
        URL.revokeObjectURL(objectUrl);
        resolve({});
      };
      audio.src = objectUrl;
    }),
    3000,
    {}
  );

const analyzeVideo = (file: File): Promise<LocalFileFacts> =>
  withTimeout(
    new Promise<LocalFileFacts>((resolve) => {
      const objectUrl = URL.createObjectURL(file);
      const video = document.createElement('video');
      video.preload = 'metadata';
      video.muted = true;
      let settled = false;
      const finish = (facts: LocalFileFacts) => {
        if (settled) return;
        settled = true;
        URL.revokeObjectURL(objectUrl);
        resolve(facts);
      };
      video.onerror = () => finish({});
      video.onloadedmetadata = () => {
        const duration = Number.isFinite(video.duration) ? video.duration : undefined;
        const dimensions = video.videoWidth
          ? { width: video.videoWidth, height: video.videoHeight }
          : undefined;
        const facts: LocalFileFacts = {
          durationSeconds: duration,
          dimensions,
          factsLine: joinFacts(
            'Video',
            duration !== undefined ? formatDuration(duration) : undefined,
            dimensions ? `${dimensions.width}×${dimensions.height}` : undefined,
            formatMb(file.size)
          ),
        };
        video.onseeked = () => {
          try {
            const canvas = document.createElement('canvas');
            const ratio = video.videoWidth ? video.videoHeight / video.videoWidth : 9 / 16;
            canvas.width = THUMBNAIL_WIDTH;
            canvas.height = Math.round(THUMBNAIL_WIDTH * ratio);
            const context = canvas.getContext('2d');
            if (context) {
              context.drawImage(video, 0, 0, canvas.width, canvas.height);
              facts.thumbnailDataUrl = canvas.toDataURL('image/jpeg', 0.7);
            }
          } catch {
            // poster frame is a bonus; keep the metadata facts
          }
          finish(facts);
        };
        try {
          video.currentTime = Math.min(0.5, (duration || 1) / 2);
        } catch {
          finish(facts);
        }
      };
      video.src = objectUrl;
    }),
    4000,
    {}
  );

interface PdfPageLike {
  getViewport: (opts: { scale: number }) => { width: number; height: number };
  render: (opts: { canvasContext: unknown; viewport: unknown }) => { promise: Promise<unknown> };
  getTextContent: () => Promise<{ items: Array<{ str?: string }> }>;
}

const renderPdfThumbnail = async (page: PdfPageLike): Promise<string | undefined> => {
  const baseViewport = page.getViewport({ scale: 1 });
  if (!baseViewport.width) return undefined;
  const viewport = page.getViewport({ scale: THUMBNAIL_WIDTH / baseViewport.width });
  const canvas = document.createElement('canvas');
  canvas.width = Math.ceil(viewport.width);
  canvas.height = Math.ceil(viewport.height);
  const context = canvas.getContext('2d');
  if (!context) return undefined;
  await page.render({ canvasContext: context, viewport }).promise;
  return canvas.toDataURL('image/png');
};

const analyzePdf = async (file: File): Promise<LocalFileFacts> => {
  const pdfjs = await import('pdfjs-dist');
  if (!pdfjs.GlobalWorkerOptions.workerSrc) {
    const worker = await import('pdfjs-dist/build/pdf.worker.min.mjs?url');
    pdfjs.GlobalWorkerOptions.workerSrc = worker.default;
  }
  const data = await file.arrayBuffer();
  const doc = await pdfjs.getDocument({ data }).promise;

  const facts: LocalFileFacts = {
    pageCount: doc.numPages,
    factsLine: joinFacts(
      'PDF',
      `${doc.numPages} page${doc.numPages === 1 ? '' : 's'}`,
      formatMb(file.size)
    ),
  };

  try {
    const { info } = await doc.getMetadata();
    const metaTitle = (info as { Title?: string } | undefined)?.Title;
    if (metaTitle?.trim()) facts.metadataTitle = metaTitle.trim();
  } catch {
    // metadata is optional
  }

  try {
    const chunks: string[] = [];
    const pagesToRead = Math.min(doc.numPages, 2);
    for (let pageNumber = 1; pageNumber <= pagesToRead; pageNumber++) {
      const page = await doc.getPage(pageNumber);
      const textContent = await page.getTextContent();
      chunks.push(
        (textContent.items as Array<{ str?: string }>).map((item) => item.str ?? '').join(' ')
      );
      if (chunks.join(' ').length >= SNIPPET_LIMIT) break;
    }
    const snippet = chunks.join(' ').replace(/\s+/g, ' ').trim().slice(0, SNIPPET_LIMIT);
    if (snippet) facts.snippet = snippet;
  } catch {
    // scanned/encrypted PDFs have no extractable text
  }

  try {
    facts.thumbnailDataUrl = await renderPdfThumbnail(await doc.getPage(1) as unknown as PdfPageLike);
  } catch {
    // thumbnail is a bonus
  }

  return facts;
};

const analyzeOther = (file: File): LocalFileFacts => ({
  factsLine: joinFacts(extensionLabel(file), formatMb(file.size)),
});

export const analyzeFileLocally = async (file: File): Promise<LocalFileFacts> => {
  try {
    switch (classifyFile(file)) {
      case 'pdf':
        return await analyzePdf(file);
      case 'image':
        return await analyzeImage(file);
      case 'audio':
        return await analyzeAudio(file);
      case 'video':
        return await analyzeVideo(file);
      case 'text':
        return await analyzeText(file);
      default:
        return analyzeOther(file);
    }
  } catch {
    return {};
  }
};
