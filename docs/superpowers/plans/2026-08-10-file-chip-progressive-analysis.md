# File Chip Progressive Analysis Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Dropped files (PDF, docs, images, audio, video) get live capture-input chips that populate progressively — instant local facts, real upload progress, cloud AI summary — and their chip-time analysis is reused at save so submit is near-instant.

**Architecture:** Three new client utils (`localFileAnalysis` for deterministic browser extraction, `stagedUploader` for XHR uploads with progress to a `staging/` storage path, `chipFileAnalysis` orchestrating both plus per-type edge-function analysis), wired into `UnifiedInputPanel`/`InputChip` the same way `hydrateLinkMetadata` feeds link chips. Two edge functions gain stateless/precomputed modes; `contentProcessor` skips whatever the chip already computed.

**Tech Stack:** React 18 + TS + Vite, vitest/jsdom + @testing-library/react (globals on), Supabase (storage `stash-media` bucket, edge functions Deno), framer-motion, `pdfjs-dist` + `exifr` (new, lazy-imported).

**Spec:** `docs/superpowers/specs/2026-08-10-file-chip-progressive-analysis-design.md`

## Global Constraints

- New deps lazy-loaded only: `pdfjs-dist@4.10.38`, `exifr@^7.1.3` via dynamic `import()` — main bundle must not grow.
- Staging path scheme: `${userId}/staging/${Date.now()}-${random6}.${ext}` in bucket `stash-media`.
- Nothing may make saving less reliable than today: every new stage fails silent and the post-save pipeline stays as safety net.
- Chip status copy (exact): "Analyzing...", "Uploading...", `Uploading · N%`, "Will upload when you save".
- Progress percentage/bar only for files ≥ 3 MB (`3 * 1024 * 1024` bytes); smaller files show spinner + "Uploading...".
- Submit awaits in-flight chip analysis max 20 000 ms, then falls back to current save-time processing.
- Sweep deletes only own `staging/` files older than 24 h and not referenced by `items.file_path` / `item_attachments.file_path`.
- Edge functions keep response shapes: analyze-image `{success, description, detected_text, tags}`; quick-pdf-summary `{title, description}`.
- Tests: vitest globals (`describe/it/vi` bare), jsdom; run with `npx vitest run <file>`.
- Commit after every task; messages in imperative style matching repo history (no conventional-commit prefixes), each ending with `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.

---

### Task 1: localFileAnalysis util (deterministic browser extraction)

**Files:**
- Create: `src/utils/localFileAnalysis.ts`
- Test: `src/utils/localFileAnalysis.test.ts`
- Modify: `package.json` (via npm install)

**Interfaces:**
- Consumes: nothing (leaf util).
- Produces (used by Tasks 3, 6):
  - `interface LocalFileFacts { factsLine?: string; snippet?: string; metadataTitle?: string; pageCount?: number; dimensions?: { width: number; height: number }; durationSeconds?: number; thumbnailDataUrl?: string; exifSummary?: string }`
  - `type LocalAnalysisKind = 'pdf' | 'image' | 'audio' | 'video' | 'text' | 'other'`
  - `classifyFile(file: File): LocalAnalysisKind`
  - `analyzeFileLocally(file: File): Promise<LocalFileFacts>` — never rejects; returns `{}` on total failure.

- [ ] **Step 1: Install dependencies**

```bash
npm install pdfjs-dist@4.10.38 exifr@7.1.3
```

- [ ] **Step 2: Write the failing tests**

Create `src/utils/localFileAnalysis.test.ts`:

```ts
import { analyzeFileLocally, classifyFile } from "./localFileAnalysis";

const { pdfjsMock, exifrParseMock } = vi.hoisted(() => {
  const getTextContent = vi.fn().mockResolvedValue({
    items: [{ str: "Employment" }, { str: "Agreement" }, { str: "between parties" }],
  });
  const render = vi.fn(() => ({ promise: Promise.resolve() }));
  const getViewport = vi.fn(() => ({ width: 600, height: 800 }));
  const page = { getTextContent, render, getViewport };
  const doc = {
    numPages: 12,
    getMetadata: vi.fn().mockResolvedValue({ info: { Title: "Employment Agreement 2026" } }),
    getPage: vi.fn().mockResolvedValue(page),
  };
  return {
    pdfjsMock: {
      GlobalWorkerOptions: { workerSrc: "" },
      getDocument: vi.fn(() => ({ promise: Promise.resolve(doc) })),
    },
    exifrParseMock: vi.fn(),
  };
});

vi.mock("pdfjs-dist", () => pdfjsMock);
vi.mock("pdfjs-dist/build/pdf.worker.min.mjs?url", () => ({ default: "/mock-worker.js" }));
vi.mock("exifr", () => ({ default: { parse: exifrParseMock } }));

describe("classifyFile", () => {
  it("routes by mime type with extension fallback", () => {
    expect(classifyFile(new File([""], "a.pdf", { type: "application/pdf" }))).toBe("pdf");
    expect(classifyFile(new File([""], "a.pdf", { type: "" }))).toBe("pdf");
    expect(classifyFile(new File([""], "a.jpg", { type: "image/jpeg" }))).toBe("image");
    expect(classifyFile(new File([""], "a.m4a", { type: "audio/mp4" }))).toBe("audio");
    expect(classifyFile(new File([""], "a.mov", { type: "video/quicktime" }))).toBe("video");
    expect(classifyFile(new File([""], "notes.md", { type: "" }))).toBe("text");
    expect(classifyFile(new File([""], "a.docx", { type: "application/vnd.openxmlformats-officedocument.wordprocessingml.document" }))).toBe("other");
  });
});

describe("analyzeFileLocally", () => {
  beforeEach(() => {
    exifrParseMock.mockReset();
    vi.stubGlobal("URL", Object.assign(Object.create(URL), {
      createObjectURL: vi.fn(() => "blob:mock"),
      revokeObjectURL: vi.fn(),
    }));
  });

  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it("extracts word count and snippet from text files", async () => {
    const file = new File(["alpha beta gamma delta"], "notes.txt", { type: "text/plain" });
    const facts = await analyzeFileLocally(file);
    expect(facts.snippet).toBe("alpha beta gamma delta");
    expect(facts.factsLine).toContain("TXT");
    expect(facts.factsLine).toContain("4 words");
  });

  it("extracts page count, metadata title, snippet, and thumbnail from PDFs", async () => {
    const canvasMock = {
      width: 0,
      height: 0,
      getContext: vi.fn(() => ({})),
      toDataURL: vi.fn(() => "data:image/png;base64,thumb"),
    };
    vi.spyOn(document, "createElement").mockImplementation(((tag: string) =>
      canvasMock) as never);

    const file = new File(["%PDF-1.4"], "kahn-cerf-88.pdf", { type: "application/pdf" });
    const facts = await analyzeFileLocally(file);

    expect(facts.pageCount).toBe(12);
    expect(facts.metadataTitle).toBe("Employment Agreement 2026");
    expect(facts.factsLine).toContain("PDF");
    expect(facts.factsLine).toContain("12 pages");
    expect(facts.snippet).toContain("Employment Agreement");
    expect(facts.thumbnailDataUrl).toBe("data:image/png;base64,thumb");
    vi.restoreAllMocks();
  });

  it("reads image dimensions and EXIF summary", async () => {
    exifrParseMock.mockResolvedValue({
      DateTimeOriginal: new Date("2026-04-01T10:00:00Z"),
      Model: "iPhone 15 Pro",
    });
    class FakeImage {
      onload: (() => void) | null = null;
      onerror: (() => void) | null = null;
      naturalWidth = 4032;
      naturalHeight = 3024;
      set src(_v: string) {
        queueMicrotask(() => this.onload?.());
      }
    }
    vi.stubGlobal("Image", FakeImage);

    const file = new File(["img"], "vb1 (3).jpg", { type: "image/jpeg" });
    const facts = await analyzeFileLocally(file);

    expect(facts.dimensions).toEqual({ width: 4032, height: 3024 });
    expect(facts.factsLine).toContain("JPEG");
    expect(facts.factsLine).toContain("4032×3024");
    expect(facts.exifSummary).toContain("iPhone 15 Pro");
  });

  it("reads audio duration via an Audio element", async () => {
    class FakeAudio {
      preload = "";
      duration = 204;
      onloadedmetadata: (() => void) | null = null;
      onerror: (() => void) | null = null;
      set src(_v: string) {
        queueMicrotask(() => this.onloadedmetadata?.());
      }
    }
    vi.stubGlobal("Audio", FakeAudio);

    const file = new File(["aud"], "memo.m4a", { type: "audio/mp4" });
    const facts = await analyzeFileLocally(file);

    expect(facts.durationSeconds).toBe(204);
    expect(facts.factsLine).toContain("3:24");
  });

  it("returns empty facts instead of throwing when extraction fails", async () => {
    pdfjsMock.getDocument.mockImplementationOnce(() => ({ promise: Promise.reject(new Error("bad pdf")) }));
    const file = new File(["%PDF"], "broken.pdf", { type: "application/pdf" });
    await expect(analyzeFileLocally(file)).resolves.toEqual({});
  });
});
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `npx vitest run src/utils/localFileAnalysis.test.ts`
Expected: FAIL — cannot resolve `./localFileAnalysis`.

- [ ] **Step 4: Implement `src/utils/localFileAnalysis.ts`**

```ts
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

const renderPdfThumbnail = async (
  page: { getViewport: (opts: { scale: number }) => { width: number; height: number }; render: (opts: { canvasContext: unknown; viewport: unknown }) => { promise: Promise<unknown> } }
): Promise<string | undefined> => {
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
    facts.thumbnailDataUrl = await renderPdfThumbnail(await doc.getPage(1));
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
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `npx vitest run src/utils/localFileAnalysis.test.ts`
Expected: PASS (6 tests). If the PDF test fails on `document.createElement` mocking leaking into other tests, ensure `vi.restoreAllMocks()` runs at the end of that test as shown.

- [ ] **Step 6: Commit**

```bash
git add package.json package-lock.json src/utils/localFileAnalysis.ts src/utils/localFileAnalysis.test.ts
git commit -m "Add local file analysis util for capture chips

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: stagedUploader util (XHR progress upload + staging cleanup)

**Files:**
- Create: `src/utils/stagedUploader.ts`
- Test: `src/utils/stagedUploader.test.ts`

**Interfaces:**
- Consumes: `supabase`, `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY` from `@/integrations/supabase/client`.
- Produces (used by Tasks 3, 7, 9):
  - `uploadToStaging(file: File, userId: string, onProgress: (percent: number) => void, opts?: { signal?: AbortSignal }): Promise<string>` — resolves storage path; retries once with a fresh path; rejects on abort or double failure.
  - `removeStagedFile(path: string): Promise<void>` — never rejects.
  - `sweepStagingOrphans(userId: string): Promise<void>` — never rejects.
  - `buildStagingPath(userId: string, fileName: string): string`

- [ ] **Step 1: Write the failing tests**

Create `src/utils/stagedUploader.test.ts`:

```ts
import { buildStagingPath, removeStagedFile, sweepStagingOrphans, uploadToStaging } from "./stagedUploader";

const { getSessionMock, storageRemoveMock, storageListMock, itemsInMock, attachmentsInMock } = vi.hoisted(() => ({
  getSessionMock: vi.fn(),
  storageRemoveMock: vi.fn().mockResolvedValue({ data: null, error: null }),
  storageListMock: vi.fn(),
  itemsInMock: vi.fn(),
  attachmentsInMock: vi.fn(),
}));

vi.mock("@/integrations/supabase/client", () => ({
  SUPABASE_URL: "https://example.supabase.co",
  SUPABASE_PUBLISHABLE_KEY: "anon-key",
  supabase: {
    auth: { getSession: getSessionMock },
    storage: {
      from: vi.fn(() => ({ remove: storageRemoveMock, list: storageListMock })),
    },
    from: vi.fn((table: string) => ({
      select: vi.fn(() => ({ in: table === "items" ? itemsInMock : attachmentsInMock })),
    })),
  },
}));

class FakeXhr {
  static instances: FakeXhr[] = [];
  upload = { onprogress: null as ((e: { lengthComputable: boolean; loaded: number; total: number }) => void) | null };
  status = 200;
  onload: (() => void) | null = null;
  onerror: (() => void) | null = null;
  onabort: (() => void) | null = null;
  headers: Record<string, string> = {};
  openArgs: string[] = [];
  sent: unknown = null;
  aborted = false;
  open(method: string, url: string) { this.openArgs = [method, url]; }
  setRequestHeader(key: string, value: string) { this.headers[key] = value; }
  send(body: unknown) { this.sent = body; FakeXhr.instances.push(this); }
  abort() { this.aborted = true; this.onabort?.(); }
}

describe("stagedUploader", () => {
  beforeEach(() => {
    FakeXhr.instances = [];
    vi.stubGlobal("XMLHttpRequest", FakeXhr);
    getSessionMock.mockResolvedValue({ data: { session: { access_token: "jwt-token" } }, error: null });
    storageRemoveMock.mockClear().mockResolvedValue({ data: null, error: null });
  });

  afterEach(() => vi.unstubAllGlobals());

  it("builds staging paths under the user's staging folder", () => {
    const path = buildStagingPath("user-1", "report.pdf");
    expect(path).toMatch(/^user-1\/staging\/\d+-[a-z0-9]{6}\.pdf$/);
  });

  it("uploads via XHR with auth headers and reports progress", async () => {
    const onProgress = vi.fn();
    const file = new File(["data"], "report.pdf", { type: "application/pdf" });
    const promise = uploadToStaging(file, "user-1", onProgress);

    await vi.waitFor(() => expect(FakeXhr.instances.length).toBe(1));
    const xhr = FakeXhr.instances[0];
    expect(xhr.openArgs[0]).toBe("POST");
    expect(xhr.openArgs[1]).toContain("https://example.supabase.co/storage/v1/object/stash-media/user-1/staging/");
    expect(xhr.headers.Authorization).toBe("Bearer jwt-token");
    expect(xhr.headers.apikey).toBe("anon-key");

    xhr.upload.onprogress?.({ lengthComputable: true, loaded: 50, total: 100 });
    expect(onProgress).toHaveBeenCalledWith(50);

    xhr.onload?.();
    await expect(promise).resolves.toMatch(/^user-1\/staging\//);
  });

  it("retries once on failure with a fresh path", async () => {
    const file = new File(["data"], "report.pdf", { type: "application/pdf" });
    const promise = uploadToStaging(file, "user-1", vi.fn());

    await vi.waitFor(() => expect(FakeXhr.instances.length).toBe(1));
    FakeXhr.instances[0].status = 500;
    FakeXhr.instances[0].onload?.();

    await vi.waitFor(() => expect(FakeXhr.instances.length).toBe(2));
    FakeXhr.instances[1].onload?.();

    await expect(promise).resolves.toMatch(/^user-1\/staging\//);
    expect(FakeXhr.instances[0].openArgs[1]).not.toBe(FakeXhr.instances[1].openArgs[1]);
  });

  it("rejects with AbortError and does not retry when aborted", async () => {
    const controller = new AbortController();
    const file = new File(["data"], "report.pdf", { type: "application/pdf" });
    const promise = uploadToStaging(file, "user-1", vi.fn(), { signal: controller.signal });

    await vi.waitFor(() => expect(FakeXhr.instances.length).toBe(1));
    controller.abort();

    await expect(promise).rejects.toMatchObject({ name: "AbortError" });
    expect(FakeXhr.instances.length).toBe(1);
  });

  it("removeStagedFile swallows storage errors", async () => {
    storageRemoveMock.mockRejectedValueOnce(new Error("gone"));
    await expect(removeStagedFile("user-1/staging/1.pdf")).resolves.toBeUndefined();
  });

  it("sweeps only stale unreferenced staging files", async () => {
    const staleDate = new Date(Date.now() - 48 * 60 * 60 * 1000).toISOString();
    const freshDate = new Date().toISOString();
    storageListMock.mockResolvedValue({
      data: [
        { name: "old-orphan.pdf", created_at: staleDate },
        { name: "old-referenced.pdf", created_at: staleDate },
        { name: "fresh.pdf", created_at: freshDate },
      ],
      error: null,
    });
    itemsInMock.mockResolvedValue({ data: [{ file_path: "user-1/staging/old-referenced.pdf" }], error: null });
    attachmentsInMock.mockResolvedValue({ data: [], error: null });

    await sweepStagingOrphans("user-1");

    expect(storageRemoveMock).toHaveBeenCalledWith(["user-1/staging/old-orphan.pdf"]);
  });
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `npx vitest run src/utils/stagedUploader.test.ts`
Expected: FAIL — cannot resolve `./stagedUploader`.

- [ ] **Step 3: Implement `src/utils/stagedUploader.ts`**

```ts
// Chip-time uploads land in `${userId}/staging/` immediately on drop, with real
// XHR progress (supabase-js upload() cannot report progress). Saved items keep
// their staging path; anything unreferenced after 24h is swept on app load.

import { supabase, SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY } from '@/integrations/supabase/client';

const BUCKET = 'stash-media';
const STAGING_MAX_AGE_MS = 24 * 60 * 60 * 1000;
const SWEEP_LIST_LIMIT = 100;

export const buildStagingPath = (userId: string, fileName: string): string => {
  const ext = fileName.includes('.') ? fileName.split('.').pop() : 'bin';
  const random = Math.random().toString(36).slice(2, 8);
  return `${userId}/staging/${Date.now()}-${random}.${ext}`;
};

const uploadOnce = (
  file: File,
  path: string,
  accessToken: string,
  onProgress: (percent: number) => void,
  signal?: AbortSignal
): Promise<void> =>
  new Promise((resolve, reject) => {
    const xhr = new XMLHttpRequest();
    xhr.open('POST', `${SUPABASE_URL}/storage/v1/object/${BUCKET}/${path}`);
    xhr.setRequestHeader('Authorization', `Bearer ${accessToken}`);
    xhr.setRequestHeader('apikey', SUPABASE_PUBLISHABLE_KEY);
    xhr.setRequestHeader('x-upsert', 'false');
    if (file.type) xhr.setRequestHeader('Content-Type', file.type);
    xhr.upload.onprogress = (event) => {
      if (event.lengthComputable && event.total > 0) {
        onProgress(Math.round((event.loaded / event.total) * 100));
      }
    };
    xhr.onload = () => {
      if (xhr.status >= 200 && xhr.status < 300) {
        resolve();
      } else {
        reject(new Error(`Staged upload failed with status ${xhr.status}`));
      }
    };
    xhr.onerror = () => reject(new Error('Staged upload failed (network error)'));
    xhr.onabort = () => reject(new DOMException('Staged upload aborted', 'AbortError'));
    signal?.addEventListener('abort', () => xhr.abort(), { once: true });
    xhr.send(file);
  });

export const uploadToStaging = async (
  file: File,
  userId: string,
  onProgress: (percent: number) => void,
  opts: { signal?: AbortSignal } = {}
): Promise<string> => {
  const { data: { session } } = await supabase.auth.getSession();
  if (!session?.access_token) {
    throw new Error('Authentication required for staged upload');
  }

  const path = buildStagingPath(userId, file.name);
  try {
    await uploadOnce(file, path, session.access_token, onProgress, opts.signal);
    return path;
  } catch (error) {
    if (error instanceof DOMException && error.name === 'AbortError') throw error;
    // One automatic retry on a fresh path (a same-ms name collision would 409)
    const retryPath = buildStagingPath(userId, file.name);
    await uploadOnce(file, retryPath, session.access_token, onProgress, opts.signal);
    return retryPath;
  }
};

export const removeStagedFile = async (path: string): Promise<void> => {
  try {
    await supabase.storage.from(BUCKET).remove([path]);
  } catch (error) {
    console.error('Failed to remove staged file (non-fatal):', error);
  }
};

export const sweepStagingOrphans = async (userId: string): Promise<void> => {
  try {
    const prefix = `${userId}/staging`;
    const { data: files, error } = await supabase.storage
      .from(BUCKET)
      .list(prefix, { limit: SWEEP_LIST_LIMIT });
    if (error || !files?.length) return;

    const cutoff = Date.now() - STAGING_MAX_AGE_MS;
    const stalePaths = files
      .filter((file) => file.created_at && new Date(file.created_at).getTime() < cutoff)
      .map((file) => `${prefix}/${file.name}`);
    if (!stalePaths.length) return;

    const [itemRefs, attachmentRefs] = await Promise.all([
      supabase.from('items').select('file_path').in('file_path', stalePaths),
      supabase.from('item_attachments').select('file_path').in('file_path', stalePaths),
    ]);
    const referenced = new Set(
      [...(itemRefs.data ?? []), ...(attachmentRefs.data ?? [])]
        .map((row) => row.file_path)
        .filter(Boolean)
    );

    const orphans = stalePaths.filter((path) => !referenced.has(path));
    if (orphans.length) {
      await supabase.storage.from(BUCKET).remove(orphans);
    }
  } catch (error) {
    console.error('Staging sweep failed (non-fatal):', error);
  }
};
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `npx vitest run src/utils/stagedUploader.test.ts`
Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
git add src/utils/stagedUploader.ts src/utils/stagedUploader.test.ts
git commit -m "Add staged uploader with XHR progress and orphan sweep

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: chipFileAnalysis orchestrator

**Files:**
- Create: `src/utils/chipFileAnalysis.ts`
- Test: `src/utils/chipFileAnalysis.test.ts`

**Interfaces:**
- Consumes: `analyzeFileLocally`, `LocalFileFacts` (Task 1); `uploadToStaging` (Task 2); `supabase` client (`functions.invoke`, `storage.from().getPublicUrl`).
- Produces (used by Tasks 6, 7):
  - `type ChipFileKind = 'image' | 'video' | 'audio' | 'document'`
  - `interface FileAnalysis extends LocalFileFacts { title?: string; description?: string; transcription?: string; detectedText?: string; tags?: string[]; uploadedFilePath?: string }`
  - `interface ChipAnalysisUpdate { analysis?: Partial<FileAnalysis>; uploadState?: 'uploading' | 'done' | 'failed'; uploadProgress?: number; analysisState?: 'local' | 'analyzing' | 'ready' }`
  - `interface ChipAnalysisHandle { done: Promise<FileAnalysis>; abort: () => void }`
  - `analyzeDroppedFile(file: File, kind: ChipFileKind, userId: string, onUpdate: (update: ChipAnalysisUpdate) => void): ChipAnalysisHandle` — `done` never rejects; resolves with everything gathered.

- [ ] **Step 1: Write the failing tests**

Create `src/utils/chipFileAnalysis.test.ts`:

```ts
import { analyzeDroppedFile, ChipAnalysisUpdate } from "./chipFileAnalysis";

const { analyzeLocallyMock, uploadMock, invokeMock } = vi.hoisted(() => ({
  analyzeLocallyMock: vi.fn(),
  uploadMock: vi.fn(),
  invokeMock: vi.fn(),
}));

vi.mock("./localFileAnalysis", () => ({ analyzeFileLocally: analyzeLocallyMock }));
vi.mock("./stagedUploader", () => ({ uploadToStaging: uploadMock }));
vi.mock("@/integrations/supabase/client", () => ({
  supabase: {
    functions: { invoke: invokeMock },
    storage: {
      from: vi.fn(() => ({
        getPublicUrl: vi.fn((path: string) => ({ data: { publicUrl: `https://cdn.example/${path}` } })),
      })),
    },
  },
}));

const collectUpdates = () => {
  const updates: ChipAnalysisUpdate[] = [];
  return { updates, onUpdate: (update: ChipAnalysisUpdate) => updates.push(update) };
};

describe("analyzeDroppedFile", () => {
  beforeEach(() => {
    analyzeLocallyMock.mockReset().mockResolvedValue({ factsLine: "PDF · 3 pages", snippet: "First page text" });
    uploadMock.mockReset().mockResolvedValue("user-1/staging/123-abc.pdf");
    invokeMock.mockReset();
  });

  it("emits local facts, upload completion, and document summary in order", async () => {
    invokeMock.mockResolvedValue({ data: { title: "Kahn Cert", description: "A certificate" }, error: null });
    const { updates, onUpdate } = collectUpdates();
    const file = new File(["%PDF"], "kahn-cerf-88.pdf", { type: "application/pdf" });

    const handle = analyzeDroppedFile(file, "document", "user-1", onUpdate);
    const result = await handle.done;

    expect(invokeMock).toHaveBeenCalledWith("quick-pdf-summary", {
      body: { fileName: "kahn-cerf-88.pdf", snippet: "First page text" },
    });
    expect(result.uploadedFilePath).toBe("user-1/staging/123-abc.pdf");
    expect(result.title).toBe("Kahn Cert");
    expect(result.description).toBe("A certificate");

    const states = updates.map((u) => u.analysisState).filter(Boolean);
    expect(states).toEqual(["local", "analyzing", "ready"]);
    const factsIndex = updates.findIndex((u) => u.analysis?.factsLine);
    const summaryIndex = updates.findIndex((u) => u.analysis?.title);
    expect(factsIndex).toBeGreaterThanOrEqual(0);
    expect(summaryIndex).toBeGreaterThan(factsIndex);
  });

  it("forwards upload progress and marks upload done", async () => {
    uploadMock.mockImplementation(async (_f, _u, onProgress) => {
      onProgress(40);
      onProgress(90);
      return "user-1/staging/123-abc.pdf";
    });
    invokeMock.mockResolvedValue({ data: { title: "T", description: "D" }, error: null });
    const { updates, onUpdate } = collectUpdates();

    await analyzeDroppedFile(new File(["x"], "a.pdf", { type: "application/pdf" }), "document", "user-1", onUpdate).done;

    const progress = updates.map((u) => u.uploadProgress).filter((p) => p !== undefined);
    expect(progress).toContain(40);
    expect(progress).toContain(90);
    expect(updates.some((u) => u.uploadState === "done")).toBe(true);
  });

  it("calls analyze-image without itemId and normalizes 'none' detected text", async () => {
    invokeMock.mockResolvedValue({
      data: { success: true, description: "A whiteboard", detected_text: "none", tags: ["sketch"] },
      error: null,
    });

    const result = await analyzeDroppedFile(
      new File(["img"], "photo.jpg", { type: "image/jpeg" }), "image", "user-1", vi.fn()
    ).done;

    expect(invokeMock).toHaveBeenCalledWith("analyze-image", {
      body: { imageUrl: "https://cdn.example/user-1/staging/123-abc.pdf" },
    });
    expect(result.description).toBe("A whiteboard");
    expect(result.detectedText).toBeUndefined();
    expect(result.tags).toEqual(["sketch"]);
  });

  it("keeps transcript and summary for audio", async () => {
    invokeMock.mockResolvedValue({
      data: { transcription: "full transcript here", description: "Voice memo about a contract" },
      error: null,
    });

    const result = await analyzeDroppedFile(
      new File(["a"], "memo.m4a", { type: "audio/mp4" }), "audio", "user-1", vi.fn()
    ).done;

    expect(invokeMock).toHaveBeenCalledWith("transcribe-audio", {
      body: { audioUrl: expect.stringContaining("https://cdn.example/"), fileName: "memo.m4a" },
    });
    expect(result.transcription).toBe("full transcript here");
    expect(result.description).toBe("Voice memo about a contract");
  });

  it("skips server analysis for video and still resolves ready", async () => {
    const { updates, onUpdate } = collectUpdates();
    await analyzeDroppedFile(new File(["v"], "clip.mp4", { type: "video/mp4" }), "video", "user-1", onUpdate).done;
    expect(invokeMock).not.toHaveBeenCalled();
    expect(updates.at(-1)?.analysisState).toBe("ready");
  });

  it("marks upload failed, skips server analysis, and still resolves with local facts", async () => {
    uploadMock.mockRejectedValue(new Error("network down"));
    const { updates, onUpdate } = collectUpdates();

    const result = await analyzeDroppedFile(
      new File(["x"], "a.pdf", { type: "application/pdf" }), "document", "user-1", onUpdate
    ).done;

    expect(invokeMock).not.toHaveBeenCalled();
    expect(updates.some((u) => u.uploadState === "failed")).toBe(true);
    expect(updates.at(-1)?.analysisState).toBe("ready");
    expect(result.factsLine).toBe("PDF · 3 pages");
    expect(result.uploadedFilePath).toBeUndefined();
  });

  it("stops emitting after abort", async () => {
    let resolveUpload: (path: string) => void = () => undefined;
    uploadMock.mockImplementation(() => new Promise((resolve) => { resolveUpload = resolve; }));
    const { updates, onUpdate } = collectUpdates();

    const handle = analyzeDroppedFile(
      new File(["x"], "a.pdf", { type: "application/pdf" }), "document", "user-1", onUpdate
    );
    await vi.waitFor(() => expect(updates.length).toBeGreaterThan(0));
    const countAtAbort = updates.length;
    handle.abort();
    resolveUpload("user-1/staging/late.pdf");
    await handle.done;

    expect(updates.length).toBe(countAtAbort);
    expect(invokeMock).not.toHaveBeenCalled();
  });
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `npx vitest run src/utils/chipFileAnalysis.test.ts`
Expected: FAIL — cannot resolve `./chipFileAnalysis`.

- [ ] **Step 3: Implement `src/utils/chipFileAnalysis.ts`**

```ts
// Orchestrates chip-time file understanding, mirroring hydrateLinkMetadata's
// role for links: local extraction and staged upload run in parallel from t0,
// then the per-type edge function turns the uploaded file (plus any locally
// extracted snippet) into a smart title/summary. Every stage is non-fatal.

import { supabase } from '@/integrations/supabase/client';
import { analyzeFileLocally, type LocalFileFacts } from './localFileAnalysis';
import { uploadToStaging } from './stagedUploader';

export type ChipFileKind = 'image' | 'video' | 'audio' | 'document';

export interface FileAnalysis extends LocalFileFacts {
  title?: string;
  description?: string;
  transcription?: string;
  detectedText?: string;
  tags?: string[];
  uploadedFilePath?: string;
}

export interface ChipAnalysisUpdate {
  analysis?: Partial<FileAnalysis>;
  uploadState?: 'uploading' | 'done' | 'failed';
  uploadProgress?: number;
  analysisState?: 'local' | 'analyzing' | 'ready';
}

export interface ChipAnalysisHandle {
  done: Promise<FileAnalysis>;
  abort: () => void;
}

const getPublicUrl = (path: string): string =>
  supabase.storage.from('stash-media').getPublicUrl(path).data.publicUrl;

const analyzeUploadedFile = async (
  file: File,
  kind: ChipFileKind,
  uploadedPath: string,
  snippet: string | undefined
): Promise<Partial<FileAnalysis> | null> => {
  if (kind === 'image') {
    const { data, error } = await supabase.functions.invoke('analyze-image', {
      body: { imageUrl: getPublicUrl(uploadedPath) },
    });
    if (error || !data?.success) return null;
    const detected =
      typeof data.detected_text === 'string' &&
      data.detected_text.trim() &&
      data.detected_text.trim().toLowerCase() !== 'none'
        ? data.detected_text.trim()
        : undefined;
    return { description: data.description, detectedText: detected, tags: data.tags };
  }

  if (kind === 'audio') {
    const { data, error } = await supabase.functions.invoke('transcribe-audio', {
      body: { audioUrl: getPublicUrl(uploadedPath), fileName: file.name },
    });
    if (error || !data) return null;
    return { description: data.description, transcription: data.transcription };
  }

  // Documents (PDF and everything else): content-based when we have a snippet,
  // filename-based guess otherwise — same graceful ladder as before.
  const { data, error } = await supabase.functions.invoke('quick-pdf-summary', {
    body: { fileName: file.name, snippet },
  });
  if (error || !data) return null;
  return { title: data.title, description: data.description };
};

export const analyzeDroppedFile = (
  file: File,
  kind: ChipFileKind,
  userId: string,
  onUpdate: (update: ChipAnalysisUpdate) => void
): ChipAnalysisHandle => {
  const controller = new AbortController();
  const accumulated: FileAnalysis = {};

  const emit = (update: ChipAnalysisUpdate) => {
    if (controller.signal.aborted) return;
    if (update.analysis) Object.assign(accumulated, update.analysis);
    onUpdate(update);
  };

  const localRun = analyzeFileLocally(file)
    .then((facts) => emit({ analysis: facts }))
    .catch(() => undefined);

  const uploadRun = (async () => {
    emit({ uploadState: 'uploading', uploadProgress: 0 });
    const path = await uploadToStaging(
      file,
      userId,
      (percent) => emit({ uploadProgress: percent }),
      { signal: controller.signal }
    );
    emit({ analysis: { uploadedFilePath: path }, uploadState: 'done', uploadProgress: 100 });
    return path;
  })();
  // Rejection is observed via the await below; this keeps it from surfacing as
  // an unhandled rejection if the await hasn't been reached yet.
  void uploadRun.catch(() => undefined);

  const done = (async (): Promise<FileAnalysis> => {
    emit({ analysisState: 'local' });
    await localRun;

    let uploadedPath: string | null = null;
    try {
      uploadedPath = await uploadRun;
    } catch (error) {
      if (error instanceof DOMException && error.name === 'AbortError') {
        return accumulated;
      }
      console.error('Staged upload failed (chip will fall back to save-time upload):', error);
      emit({ uploadState: 'failed' });
    }

    if (controller.signal.aborted) return accumulated;

    if (uploadedPath && kind !== 'video') {
      emit({ analysisState: 'analyzing' });
      try {
        const serverAnalysis = await analyzeUploadedFile(file, kind, uploadedPath, accumulated.snippet);
        if (serverAnalysis) emit({ analysis: serverAnalysis });
      } catch (error) {
        console.error('Chip server analysis failed (non-fatal):', error);
      }
    }

    emit({ analysisState: 'ready' });
    return accumulated;
  })();

  return {
    done,
    abort: () => controller.abort(),
  };
};
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `npx vitest run src/utils/chipFileAnalysis.test.ts`
Expected: PASS (7 tests).

- [ ] **Step 5: Commit**

```bash
git add src/utils/chipFileAnalysis.ts src/utils/chipFileAnalysis.test.ts
git commit -m "Add chip file analysis orchestrator (local + upload + cloud stages)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: analyze-image edge function — stateless + precomputed modes

**Files:**
- Modify: `supabase/functions/analyze-image/index.ts`

**Interfaces:**
- Consumes: existing function body (vision call, `parseVisionResponse`, DB update + embeddings block).
- Produces: request body now `{ itemId?, imageUrl?, precomputed?: { description: string; detected_text?: string; tags?: string[] } }`.
  - No `itemId` → run vision, return results, **no DB writes, no embeddings**.
  - `precomputed` + `itemId` → **skip vision**, run existing DB update + embeddings with precomputed values.
  - Validation: reject unless `imageUrl` or (`itemId` and `precomputed`). Response shape unchanged.

No Deno test infra exists in this repo (none of the 27 functions have tests) — verification is careful diff review; deploy happens in Task 10.

- [ ] **Step 1: Update request parsing and validation**

Replace:

```ts
    const { itemId, imageUrl } = await req.json();

    if (!itemId || !imageUrl) {
      return new Response(JSON.stringify({ success: false, error: 'itemId and imageUrl are required' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }
```

with:

```ts
    const { itemId, imageUrl, precomputed } = await req.json();

    // Modes: chip-time (imageUrl only → vision, no DB writes), save-time reuse
    // (itemId + precomputed → DB writes without re-running vision), and the
    // original full mode (itemId + imageUrl).
    if (!imageUrl && !(itemId && precomputed)) {
      return new Response(JSON.stringify({ success: false, error: 'imageUrl or (itemId + precomputed) is required' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }
```

- [ ] **Step 2: Branch around the vision call**

The existing code runs the vision fetch then `const { description, detected_text, tags } = parseVisionResponse(rawContent);`. Restructure so those three variables come from either source. Wrap the entire block from `console.log('Starting Vision analysis...')` through `parseVisionResponse` in an else-branch:

```ts
    let description: string;
    let detected_text: string;
    let tags: string[];

    if (precomputed && typeof precomputed.description === 'string') {
      description = precomputed.description;
      detected_text = typeof precomputed.detected_text === 'string' && precomputed.detected_text.trim()
        ? precomputed.detected_text
        : 'none';
      tags = Array.isArray(precomputed.tags) ? precomputed.tags : [];
      console.log('Using precomputed vision results for item:', itemId);
    } else {
      console.log('Starting Vision analysis for item:', itemId ?? '(chip-time, no item)', 'image:', imageUrl);
      // ... existing vision fetch + parse, unchanged, ending with:
      // const parsed = parseVisionResponse(rawContent);
      // description = parsed.description; detected_text = parsed.detected_text; tags = parsed.tags;
    }
```

(Change the existing destructuring `const { description, detected_text, tags } = parseVisionResponse(rawContent);` to assignments into the outer `let` bindings: `const parsed = parseVisionResponse(rawContent); description = parsed.description; detected_text = parsed.detected_text; tags = parsed.tags;`)

- [ ] **Step 3: Guard the DB update + embeddings with `if (itemId)`**

Wrap the block starting at `const hasOcrText = ...` through the `generate-embeddings` invoke (inclusive) in:

```ts
    if (itemId) {
      // ... existing hasOcrText, items update, textContent build, generate-embeddings invoke ...
    }
```

Keep the final success `Response` (`{ success: true, description, detected_text, tags }`) outside the guard, unchanged.

- [ ] **Step 4: Review the full diff**

Run: `git diff supabase/functions/analyze-image/index.ts`
Check: (1) chip-time call (`{imageUrl}` only) can never touch the DB; (2) precomputed mode never calls OpenAI; (3) full mode behaves byte-for-byte like before; (4) `hasOcrText` still derives from `detected_text` inside the guard.

- [ ] **Step 5: Commit**

```bash
git add supabase/functions/analyze-image/index.ts
git commit -m "Support stateless and precomputed modes in analyze-image

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 5: quick-pdf-summary edge function — snippet-aware + return-only mode

**Files:**
- Modify: `supabase/functions/quick-pdf-summary/index.ts`

**Interfaces:**
- Produces: request body now `{ fileUrl?, itemId?, fileName, snippet? }`.
  - `snippet` present → prompt is content-based (first-page text), not filename-based.
  - No `itemId` → skip the DB update entirely (return-only). Response shape `{title, description}` unchanged.

- [ ] **Step 1: Parse snippet**

Replace `const { fileUrl, itemId, fileName } = await req.json();` with:

```ts
    const { fileUrl, itemId, fileName, snippet } = await req.json();
```

- [ ] **Step 2: Make the prompt content-based when a snippet is provided**

Replace the `messages` array in the OpenAI call with:

```ts
        messages: [
          {
            role: 'system',
            content: 'You are a document analyzer. Generate a concise title (5-10 words) and a brief one-sentence description for documents. Be specific and descriptive. Respond with exactly two lines: the title line, then the description line.'
          },
          {
            role: 'user',
            content: snippet && String(snippet).trim().length > 0
              ? `Here is the beginning of a document named "${fileName}":\n"""${String(snippet).slice(0, 1500)}"""\n\nBased on this text, generate a title and a one-sentence description of what this document contains.`
              : `Based on the filename "${fileName}", generate a title and description. Title should be clear and descriptive. Description should be one sentence explaining what this document likely contains.`
          }
        ],
```

- [ ] **Step 3: Guard the DB update with `if (itemId)`**

Wrap the block from `const supabaseUrl = Deno.env.get('SUPABASE_URL')!;` through the `updateError` logging (inclusive) in `if (itemId) { ... }`. The final `Response` with `{ title, description }` stays outside, unchanged.

- [ ] **Step 4: Review the full diff**

Run: `git diff supabase/functions/quick-pdf-summary/index.ts`
Check: (1) no-`itemId` calls cannot touch the DB; (2) with `itemId` and no snippet, behavior matches today; (3) snippet is truncated to 1500 chars.

- [ ] **Step 5: Commit**

```bash
git add supabase/functions/quick-pdf-summary/index.ts
git commit -m "Make quick-pdf-summary snippet-aware with return-only mode

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 6: InputChip — rich file rendering

**Files:**
- Modify: `src/components/InputChip.tsx`
- Test (create): `src/components/InputChip.test.tsx`

**Interfaces:**
- Consumes: `FileAnalysis` type from Task 3.
- Produces (props consumed by Task 7):

```ts
interface InputChipProps {
  type: 'text' | 'link' | 'image' | 'video' | 'audio' | 'document';
  content: any;
  onRemove: () => void;
  ogData?: OpenGraphData;
  metadataStatus?: 'fast-loading' | 'deep-loading' | 'inferred' | 'ready' | 'failed';
  fileAnalysis?: FileAnalysis;
  uploadState?: 'uploading' | 'done' | 'failed';
  uploadProgress?: number;
  analysisState?: 'local' | 'analyzing' | 'ready';
}
```

The `processingStatus` prop is removed (UnifiedInputPanel is the only consumer; Task 7 updates it in the same PR).

- [ ] **Step 1: Write the failing tests**

Create `src/components/InputChip.test.tsx`:

```tsx
import { render, screen } from "@testing-library/react";
import InputChip from "./InputChip";

vi.mock("@/integrations/supabase/client", () => ({
  SUPABASE_URL: "https://example.supabase.co",
}));

describe("InputChip file rendering", () => {
  beforeEach(() => {
    vi.stubGlobal("URL", Object.assign(Object.create(URL), {
      createObjectURL: vi.fn(() => "blob:mock"),
      revokeObjectURL: vi.fn(),
    }));
  });

  afterEach(() => vi.unstubAllGlobals());

  const baseContent = { name: "kahn-cerf-88.pdf", size: 0.3 * 1024 * 1024, type: "application/pdf" };

  it("shows filename, size, and analyzing state before any facts arrive", () => {
    render(
      <InputChip type="document" content={baseContent} onRemove={vi.fn()} analysisState="local" />
    );
    expect(screen.getByText("kahn-cerf-88.pdf")).toBeInTheDocument();
    expect(screen.getByText("0.3 MB")).toBeInTheDocument();
    expect(screen.getByText("Analyzing...")).toBeInTheDocument();
  });

  it("shows the facts line instead of bare size once local analysis lands", () => {
    render(
      <InputChip
        type="document"
        content={baseContent}
        onRemove={vi.fn()}
        analysisState="analyzing"
        fileAnalysis={{ factsLine: "PDF · 12 pages · 0.3 MB" }}
      />
    );
    expect(screen.getByText("PDF · 12 pages · 0.3 MB")).toBeInTheDocument();
    expect(screen.queryByText("0.3 MB")).not.toBeInTheDocument();
  });

  it("shows percentage progress for large uploads", () => {
    render(
      <InputChip
        type="video"
        content={{ name: "clip.mp4", size: 50 * 1024 * 1024, type: "video/mp4" }}
        onRemove={vi.fn()}
        analysisState="local"
        uploadState="uploading"
        uploadProgress={45}
      />
    );
    expect(screen.getByText("Uploading · 45%")).toBeInTheDocument();
  });

  it("shows spinner-only uploading text for small files", () => {
    render(
      <InputChip
        type="document"
        content={baseContent}
        onRemove={vi.fn()}
        analysisState="local"
        uploadState="uploading"
        uploadProgress={45}
      />
    );
    expect(screen.getByText("Uploading...")).toBeInTheDocument();
    expect(screen.queryByText("Uploading · 45%")).not.toBeInTheDocument();
  });

  it("renders AI title, description, and thumbnail when analysis is ready", () => {
    render(
      <InputChip
        type="document"
        content={baseContent}
        onRemove={vi.fn()}
        analysisState="ready"
        uploadState="done"
        fileAnalysis={{
          title: "Kahn-Cerf Internet Certificate",
          description: "A 1988 certificate signed by Vint Cerf.",
          factsLine: "PDF · 2 pages · 0.3 MB",
          thumbnailDataUrl: "data:image/png;base64,thumb",
        }}
      />
    );
    expect(screen.getByText("Kahn-Cerf Internet Certificate")).toBeInTheDocument();
    expect(screen.getByText("A 1988 certificate signed by Vint Cerf.")).toBeInTheDocument();
    expect(screen.queryByText("kahn-cerf-88.pdf")).not.toBeInTheDocument();
    expect(screen.queryByText("Analyzing...")).not.toBeInTheDocument();
    const thumb = document.querySelector('img[src="data:image/png;base64,thumb"]');
    expect(thumb).not.toBeNull();
  });

  it("notes save-time fallback when the staged upload failed", () => {
    render(
      <InputChip
        type="document"
        content={baseContent}
        onRemove={vi.fn()}
        analysisState="ready"
        uploadState="failed"
      />
    );
    expect(screen.getByText("Will upload when you save")).toBeInTheDocument();
  });
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `npx vitest run src/components/InputChip.test.tsx`
Expected: FAIL — props not supported / texts not found.

- [ ] **Step 3: Implement the InputChip changes**

In `src/components/InputChip.tsx`:

1. Import `FileAnalysis`: `import type { FileAnalysis } from '@/utils/chipFileAnalysis';` and add `useEffect, useRef, useState` usage (already imported).

2. Replace `processingStatus?: 'uploading' | 'processing' | 'ready' | 'error';` in `InputChipProps` with:

```ts
  fileAnalysis?: FileAnalysis;
  uploadState?: 'uploading' | 'done' | 'failed';
  uploadProgress?: number;
  analysisState?: 'local' | 'analyzing' | 'ready';
```

3. Add above the component:

```ts
const PROGRESS_BAR_MIN_BYTES = 3 * 1024 * 1024;

const formatMb = (bytes: number) => `${(bytes / 1024 / 1024).toFixed(1)} MB`;

// Stable object URL per file (and revoked on cleanup) instead of a fresh
// createObjectURL every render.
const useFileObjectUrl = (file?: File) => {
  const [url, setUrl] = useState<string | undefined>(undefined);
  useEffect(() => {
    if (!file) {
      setUrl(undefined);
      return;
    }
    const objectUrl = URL.createObjectURL(file);
    setUrl(objectUrl);
    return () => URL.revokeObjectURL(objectUrl);
  }, [file]);
  return url;
};
```

4. Add a `FileChipContent` component in the same file (above `InputChip`):

```tsx
interface FileChipContentProps {
  type: 'image' | 'video' | 'audio' | 'document';
  content: any;
  fileAnalysis?: FileAnalysis;
  uploadState?: 'uploading' | 'done' | 'failed';
  uploadProgress?: number;
  analysisState?: 'local' | 'analyzing' | 'ready';
  isTransitioning: boolean;
}

const FileChipContent = ({
  type,
  content,
  fileAnalysis,
  uploadState,
  uploadProgress,
  analysisState,
  isTransitioning,
}: FileChipContentProps) => {
  const objectUrl = useFileObjectUrl(type === 'image' ? content.file : undefined);
  const thumbnailUrl = fileAnalysis?.thumbnailDataUrl || objectUrl;

  const title = fileAnalysis?.title || fileAnalysis?.metadataTitle || content.name;
  const factsLine =
    fileAnalysis?.factsLine || (content.size ? formatMb(content.size) : undefined);
  const isBusy = analysisState === 'local' || analysisState === 'analyzing';
  const showPercent =
    uploadState === 'uploading' && (content.size ?? 0) >= PROGRESS_BAR_MIN_BYTES;

  const fallbackIcon = () => {
    switch (type) {
      case 'image':
        return <Image className="h-5 w-5 text-muted-foreground" />;
      case 'video':
        return <Video className="h-5 w-5 text-muted-foreground" />;
      case 'audio':
        return <FileAudio className="h-5 w-5 text-muted-foreground" />;
      default:
        return <File className="h-5 w-5 text-muted-foreground" />;
    }
  };

  return (
    <div className="flex items-center gap-3 max-w-[300px]">
      {thumbnailUrl ? (
        <img src={thumbnailUrl} alt="" className="w-10 h-10 rounded object-cover flex-shrink-0" />
      ) : (
        <div className="w-10 h-10 rounded bg-muted flex items-center justify-center flex-shrink-0">
          {fallbackIcon()}
        </div>
      )}
      <div
        className={`flex-1 min-w-0 transition-opacity duration-200 ${
          isTransitioning ? 'opacity-70' : 'opacity-100'
        }`}
      >
        <div className="text-sm font-medium line-clamp-2 leading-tight">{title}</div>
        {fileAnalysis?.description && (
          <div className="text-xs text-muted-foreground line-clamp-2 mt-0.5">
            {fileAnalysis.description}
          </div>
        )}
        {factsLine && (
          <div className="text-xs text-muted-foreground mt-0.5 truncate">{factsLine}</div>
        )}
        {uploadState === 'uploading' && (
          <div className="text-xs text-muted-foreground flex items-center gap-1 mt-0.5">
            <Loader2 className="h-3 w-3 animate-spin" />
            {showPercent ? `Uploading · ${uploadProgress ?? 0}%` : 'Uploading...'}
          </div>
        )}
        {uploadState === 'failed' && (
          <div className="text-xs text-muted-foreground mt-0.5">Will upload when you save</div>
        )}
        {uploadState !== 'uploading' && isBusy && (
          <div className="text-xs text-muted-foreground flex items-center gap-1 mt-0.5">
            <Loader2 className="h-3 w-3 animate-spin" />
            Analyzing...
          </div>
        )}
      </div>
    </div>
  );
};
```

5. In `InputChip`, update the transition signature so file chips also pulse on new data. Replace the existing `metadataSignature` line and effect guard:

```ts
  const metadataSignature =
    type === 'link'
      ? `${ogData?.title || ''}|${ogData?.description || ''}|${ogData?.image || ''}|${ogData?.previewImageUrl || ''}`
      : `${fileAnalysis?.title || ''}|${fileAnalysis?.description || ''}|${fileAnalysis?.factsLine || ''}|${fileAnalysis?.thumbnailDataUrl ? 't' : ''}`;
```

and in the `useEffect`, change `if (type !== 'link') return;` to `if (type === 'text') return;`.

6. In `getDisplayContent()`, replace the `case 'image':` and the combined `case 'video': case 'audio': case 'document':` branches with a single delegation:

```tsx
      case 'image':
      case 'video':
      case 'audio':
      case 'document':
        return (
          <FileChipContent
            type={type}
            content={content}
            fileAnalysis={fileAnalysis}
            uploadState={uploadState}
            uploadProgress={uploadProgress}
            analysisState={analysisState}
            isTransitioning={isMetadataTransitioning}
          />
        );
```

7. Update the root element: remove the old `isFileProcessing` spinner block and its variable; restrict the leading icon to non-file chips; add `relative overflow-hidden` and the progress bar. The root return becomes:

```tsx
  const showProgressBar =
    uploadState === 'uploading' && (content?.size ?? 0) >= PROGRESS_BAR_MIN_BYTES;

  return (
    <div className="relative overflow-hidden flex items-center gap-2 bg-white border border-border rounded-lg px-3 py-2 shadow-sm max-w-fit">
      {(type === 'link' || type === 'text') && !ogData?.previewImageUrl && !ogData?.image && getIcon()}
      {getDisplayContent()}
      <Button
        variant="ghost"
        size="sm"
        onClick={onRemove}
        className="h-6 w-6 p-0 hover:bg-destructive/10 flex-shrink-0"
      >
        <X className="h-3 w-3" />
      </Button>
      {showProgressBar && (
        <div
          className="absolute bottom-0 left-0 h-0.5 bg-violet-500 transition-[width] duration-200"
          style={{ width: `${uploadProgress ?? 0}%` }}
        />
      )}
    </div>
  );
```

8. Update the component signature to destructure the new props:

```ts
const InputChip = ({ type, content, onRemove, ogData, metadataStatus, fileAnalysis, uploadState, uploadProgress, analysisState }: InputChipProps) => {
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `npx vitest run src/components/InputChip.test.tsx`
Expected: PASS (6 tests).

- [ ] **Step 5: Run the panel test to catch prop breakage**

Run: `npx vitest run src/components/UnifiedInputPanel.test.tsx`
Expected: PASS — panel passes `processingStatus` which is now ignored (unknown prop, TS may flag). If TypeScript errors on `processingStatus` in `UnifiedInputPanel.tsx`, remove that prop pass-through now (`processingStatus={item.processingStatus}` line) and the `processingStatus: 'ready',` field in `addFileItem` — Task 7 rebuilds this wiring properly.

- [ ] **Step 6: Commit**

```bash
git add src/components/InputChip.tsx src/components/InputChip.test.tsx src/components/UnifiedInputPanel.tsx
git commit -m "Render progressive file analysis in input chips

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 7: UnifiedInputPanel wiring (start/abort analysis, submit passthrough)

**Files:**
- Modify: `src/components/UnifiedInputPanel.tsx`
- Test: `src/components/UnifiedInputPanel.test.tsx` (extend)

**Interfaces:**
- Consumes: `analyzeDroppedFile`, `ChipAnalysisHandle`, `ChipAnalysisUpdate`, `FileAnalysis`, `ChipFileKind` (Task 3); `removeStagedFile` (Task 2); InputChip props (Task 6).
- Produces — `onAddContent` payload contract consumed by Task 8:
  - Single media: `{ file, uploadedFilePath?, title, description?, content?, detectedText?, tags?, snippet?, type, is_public }` where `content` is the audio transcription.
  - Collection attachments gain: `uploadedFilePath?, title?, description?, processedContent?`.

- [ ] **Step 1: Write the failing tests**

Append to `src/components/UnifiedInputPanel.test.tsx`. First extend the hoisted block and mocks at the top of the file:

```ts
// Add to the vi.hoisted destructuring:
const { invokeMock, analyzeDroppedFileMock, removeStagedFileMock, chipDriver } = vi.hoisted(() => {
  const driver: {
    onUpdate?: (update: unknown) => void;
    resolveDone?: (analysis: unknown) => void;
    abort: ReturnType<typeof vi.fn>;
  } = { abort: vi.fn() };
  return {
    invokeMock: vi.fn(),
    removeStagedFileMock: vi.fn().mockResolvedValue(undefined),
    chipDriver: driver,
    analyzeDroppedFileMock: vi.fn((_file, _kind, _userId, onUpdate) => {
      driver.onUpdate = onUpdate;
      return {
        done: new Promise((resolve) => { driver.resolveDone = resolve; }),
        abort: driver.abort,
      };
    }),
  };
});

// Add module mocks alongside the existing ones:
vi.mock("@/utils/chipFileAnalysis", () => ({ analyzeDroppedFile: analyzeDroppedFileMock }));
vi.mock("@/utils/stagedUploader", () => ({ removeStagedFile: removeStagedFileMock }));
```

Then add a new describe block at the bottom:

```tsx
describe("UnifiedInputPanel file chips", () => {
  const renderPanel = (onAddContent = vi.fn().mockResolvedValue(undefined)) => {
    render(
      <UnifiedInputPanel
        isInputUICollapsed={false}
        onToggleInputUI={vi.fn()}
        onAddContent={onAddContent}
        getSuggestedTags={vi.fn().mockResolvedValue([])}
      />
    );
    return onAddContent;
  };

  const dropFile = (file: File) => {
    const dropzone = screen.getByTestId("capture-dropzone");
    fireEvent.drop(dropzone, { dataTransfer: { files: [file] } });
  };

  it("starts chip analysis when a file is dropped", async () => {
    renderPanel();
    const file = new File(["%PDF"], "kahn-cerf-88.pdf", { type: "application/pdf" });
    dropFile(file);

    await waitFor(() => expect(analyzeDroppedFileMock).toHaveBeenCalledTimes(1));
    expect(analyzeDroppedFileMock.mock.calls[0][0]).toBe(file);
    expect(analyzeDroppedFileMock.mock.calls[0][1]).toBe("document");
    expect(analyzeDroppedFileMock.mock.calls[0][2]).toBe("user-1");
  });

  it("renders orchestrator updates in the chip", async () => {
    renderPanel();
    dropFile(new File(["%PDF"], "kahn-cerf-88.pdf", { type: "application/pdf" }));
    await waitFor(() => expect(analyzeDroppedFileMock).toHaveBeenCalled());

    act(() => {
      chipDriver.onUpdate?.({ analysis: { factsLine: "PDF · 12 pages · 0.3 MB" }, analysisState: "analyzing" });
      chipDriver.onUpdate?.({ analysis: { title: "Kahn-Cerf Certificate", description: "A 1988 certificate." } });
    });

    expect(await screen.findByText("PDF · 12 pages · 0.3 MB")).toBeInTheDocument();
    expect(screen.getByText("Kahn-Cerf Certificate")).toBeInTheDocument();
  });

  it("aborts analysis and deletes the staged file when a chip is removed", async () => {
    renderPanel();
    dropFile(new File(["%PDF"], "kahn-cerf-88.pdf", { type: "application/pdf" }));
    await waitFor(() => expect(analyzeDroppedFileMock).toHaveBeenCalled());

    act(() => {
      chipDriver.onUpdate?.({ analysis: { uploadedFilePath: "user-1/staging/1-abc.pdf" }, uploadState: "done" });
    });

    fireEvent.click(screen.getByRole("button", { name: "Remove" }));

    await waitFor(() => expect(chipDriver.abort).toHaveBeenCalled());
    expect(removeStagedFileMock).toHaveBeenCalledWith("user-1/staging/1-abc.pdf");
  });

  it("passes chip analysis through to onAddContent for a single media item", async () => {
    const onAddContent = renderPanel();
    dropFile(new File(["aud"], "memo.m4a", { type: "audio/mp4" }));
    await waitFor(() => expect(analyzeDroppedFileMock).toHaveBeenCalled());

    chipDriver.resolveDone?.({
      uploadedFilePath: "user-1/staging/2-def.m4a",
      description: "Voice memo about the contract",
      transcription: "full transcript",
      factsLine: "Audio · 3:24",
    });

    fireEvent.click(screen.getByRole("button", { name: "Add to Stash" }));

    await waitFor(() => expect(onAddContent).toHaveBeenCalled());
    const [type, payload] = onAddContent.mock.calls[0];
    expect(type).toBe("audio");
    expect(payload.uploadedFilePath).toBe("user-1/staging/2-def.m4a");
    expect(payload.description).toBe("Voice memo about the contract");
    expect(payload.content).toBe("full transcript");
    expect(payload.title).toBe("memo.m4a");
  });
});
```

Add `act` to the testing-library import at the top: `import { act, fireEvent, render, screen, waitFor } from "@testing-library/react";`

- [ ] **Step 2: Run tests to verify they fail**

Run: `npx vitest run src/components/UnifiedInputPanel.test.tsx`
Expected: FAIL — `capture-dropzone` test id missing, `analyzeDroppedFile` never called, "Remove" button name missing.

- [ ] **Step 3: Implement the panel wiring**

In `src/components/UnifiedInputPanel.tsx`:

1. Imports:

```ts
import { analyzeDroppedFile, type ChipAnalysisHandle, type ChipAnalysisUpdate, type ChipFileKind, type FileAnalysis } from '@/utils/chipFileAnalysis';
import { removeStagedFile } from '@/utils/stagedUploader';
```

2. Replace the `processingStatus?: ...` field in `InputItem` with:

```ts
  fileAnalysis?: FileAnalysis;
  uploadState?: 'uploading' | 'done' | 'failed';
  uploadProgress?: number;
  analysisState?: 'local' | 'analyzing' | 'ready';
```

3. Add near the other refs:

```ts
  const fileAnalysisHandlesRef = useRef<Map<string, ChipAnalysisHandle>>(new Map());
  const ANALYSIS_SUBMIT_TIMEOUT_MS = 20000;
```

4. Add the update applier (near `updateMetadataStatus`):

```ts
  const applyChipUpdate = useCallback((itemId: string, update: ChipAnalysisUpdate) => {
    setInputItems(prev =>
      prev.map(item => {
        if (item.id !== itemId) return item;
        return {
          ...item,
          fileAnalysis: update.analysis
            ? { ...item.fileAnalysis, ...update.analysis }
            : item.fileAnalysis,
          uploadState: update.uploadState ?? item.uploadState,
          uploadProgress: update.uploadProgress ?? item.uploadProgress,
          analysisState: update.analysisState ?? item.analysisState,
        };
      })
    );
  }, []);
```

5. Rewrite `addFileItem` (keep validation):

```ts
  const addFileItem = useCallback((file: File) => {
    const validation = validateFileSize(file);
    if (!validation.valid) {
      toast({
        title: "File too large",
        description: validation.error,
        variant: "destructive",
      });
      return;
    }

    let fileType: ChipFileKind;
    if (file.type.startsWith('image/')) {
      fileType = 'image';
    } else if (file.type.startsWith('video/')) {
      fileType = 'video';
    } else if (file.type.startsWith('audio/')) {
      fileType = 'audio';
    } else {
      fileType = 'document';
    }

    const itemId = generateId();
    setInputItems(prev => [...prev, {
      id: itemId,
      type: fileType,
      content: { file, name: file.name, size: file.size, type: file.type },
      analysisState: 'local',
    }]);

    // Chip-time understanding starts immediately (local facts + staged upload +
    // cloud summary); without a signed-in user the chip stays static and the
    // save path handles everything as before.
    if (user?.id) {
      const handle = analyzeDroppedFile(file, fileType, user.id, (update) =>
        applyChipUpdate(itemId, update)
      );
      fileAnalysisHandlesRef.current.set(itemId, handle);
    }
  }, [toast, user?.id, applyChipUpdate]);
```

6. Rewrite `removeInputItem`:

```ts
  const removeInputItem = (id: string) => {
    const item = inputItems.find(candidate => candidate.id === id);
    const handle = fileAnalysisHandlesRef.current.get(id);
    handle?.abort();
    fileAnalysisHandlesRef.current.delete(id);
    const stagedPath = item?.fileAnalysis?.uploadedFilePath;
    if (stagedPath) {
      void removeStagedFile(stagedPath);
    }
    setInputItems(prev => prev.filter(candidate => candidate.id !== id));
  };
```

7. Add the submit-time resolver (above `handleSubmit`):

```ts
  // Submit reuses whatever the chip pipeline produced; if it's still running,
  // wait briefly rather than redoing the work — past the timeout the save path
  // simply falls back to today's post-save processing.
  const resolveFileAnalysis = async (item: InputItem): Promise<FileAnalysis | undefined> => {
    const handle = fileAnalysisHandlesRef.current.get(item.id);
    if (!handle) return item.fileAnalysis;
    const timeout = new Promise<FileAnalysis | undefined>((resolve) =>
      window.setTimeout(() => resolve(item.fileAnalysis), ANALYSIS_SUBMIT_TIMEOUT_MS)
    );
    return Promise.race([handle.done, timeout]);
  };
```

8. In `handleSubmit`, replace Case 2 with:

```ts
      else if (mediaItems.length === 1 && !hasText && linkItems.length === 0) {
        const mediaItem = mediaItems[0];
        const analysis = await resolveFileAnalysis(mediaItem);
        await onAddContent(mediaItem.type, {
          file: mediaItem.content.file,
          uploadedFilePath: analysis?.uploadedFilePath,
          title: analysis?.title || analysis?.metadataTitle || mediaItem.content.name,
          description: analysis?.description,
          content: analysis?.transcription,
          detectedText: analysis?.detectedText,
          tags: analysis?.tags,
          snippet: analysis?.snippet,
          type: mediaItem.type,
          is_public: isPublic
        });
      }
```

9. In Case 4, replace the media attachments loop with:

```ts
        for (const mediaItem of mediaItems) {
          const analysis = await resolveFileAnalysis(mediaItem);
          attachments.push({
            type: mediaItem.type,
            file: mediaItem.content.file,
            name: mediaItem.content.name,
            size: mediaItem.content.size,
            fileType: mediaItem.content.type,
            uploadedFilePath: analysis?.uploadedFilePath,
            title: analysis?.title || analysis?.metadataTitle,
            description: analysis?.description,
            processedContent: analysis?.transcription || analysis?.snippet,
          });
        }
```

10. At the end of the `try` block in `handleSubmit` (after the case chain, before `catch`), add:

```ts
      fileAnalysisHandlesRef.current.clear();
```

(On error the items are restored, so handles must survive — the clear stays inside the success path only.)

11. Update the InputChip render call:

```tsx
                            <InputChip
                              type={item.type}
                              content={item.content}
                              onRemove={() => removeInputItem(item.id)}
                              ogData={item.ogData}
                              metadataStatus={item.metadataStatus}
                              fileAnalysis={item.fileAnalysis}
                              uploadState={item.uploadState}
                              uploadProgress={item.uploadProgress}
                              analysisState={item.analysisState}
                            />
```

12. Add `data-testid="capture-dropzone"` to the drop container (the `p-4 space-y-4 relative ...` div that has `onDrop={handleDrop}`).

13. Give the remove button an accessible name in `InputChip.tsx` (needed by the test): add `aria-label="Remove"` to the remove `<Button>`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `npx vitest run src/components/UnifiedInputPanel.test.tsx src/components/InputChip.test.tsx`
Expected: PASS (all, including the pre-existing link tests).

- [ ] **Step 5: Run the whole suite**

Run: `npx vitest run`
Expected: PASS. `Index.test.tsx` mocks the panel's collaborators already; if it renders the real panel and fails on the new `chipFileAnalysis` import, add `vi.mock("@/utils/chipFileAnalysis", ...)` and `vi.mock("@/utils/stagedUploader", ...)` stubs there mirroring Step 1.

- [ ] **Step 6: Commit**

```bash
git add src/components/UnifiedInputPanel.tsx src/components/UnifiedInputPanel.test.tsx src/components/InputChip.tsx src/pages/Index.test.tsx
git commit -m "Wire progressive chip analysis into the capture panel

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 8: contentProcessor save-path reuse

**Files:**
- Modify: `src/utils/contentProcessor.ts`
- Test: `src/utils/contentProcessor.test.ts` (extend)

**Interfaces:**
- Consumes: payload contract from Task 7; edge-function modes from Tasks 4–5.
- Produces: no new exports — behavior changes only:
  1. Audio with provided `description` + `content`: no `transcribe-audio` call (already emergent from the existing `if (!aiDescription ...)` guard — covered by a test, no code change).
  2. Image: `analyze-image` invoked with `precomputed` when the chip provided a description.
  3. Document: filename-only `quick-pdf-summary` phase skipped when `data.description` exists; when it runs, it now passes `snippet`.
  4. `processAttachments`: uses `attachment.uploadedFilePath` instead of re-uploading; skips `processMediaAttachment` when chip analysis provided.

- [ ] **Step 1: Write the failing tests**

Extend `src/utils/contentProcessor.test.ts` with a new describe block (reuse the existing hoisted mocks — `invokeMock`, `itemsInsertPayloads`, etc. — and follow the existing test structure in that file for arranging `fromMock`):

```ts
describe("chip-analysis reuse at save", () => {
  it("skips transcription for audio when description and content are provided", async () => {
    await processAndInsertContent(
      "audio",
      {
        file: new File(["a"], "memo.m4a", { type: "audio/mp4" }),
        uploadedFilePath: "user-1/staging/2-def.m4a",
        title: "memo.m4a",
        description: "Voice memo about the contract",
        content: "full transcript",
      },
      "user-1",
      true,
      fetchItemsMock,
      vi.fn()
    );

    const transcribeCalls = invokeMock.mock.calls.filter(([name]) => name === "transcribe-audio");
    expect(transcribeCalls).toHaveLength(0);
    const inserted = itemsInsertPayloads.at(-1);
    expect(inserted.content).toBe("full transcript");
    expect(inserted.description).toBe("Voice memo about the contract");
    expect(inserted.file_path).toBe("user-1/staging/2-def.m4a");
  });

  it("passes precomputed vision results to analyze-image instead of re-running vision", async () => {
    await processAndInsertContent(
      "image",
      {
        file: new File(["i"], "photo.jpg", { type: "image/jpeg" }),
        uploadedFilePath: "user-1/staging/3-ghi.jpg",
        title: "photo.jpg",
        description: "A whiteboard sketch",
        detectedText: "Q3 roadmap",
        tags: ["sketch", "planning"],
      },
      "user-1",
      true,
      fetchItemsMock,
      vi.fn()
    );

    const analyzeCall = invokeMock.mock.calls.find(([name]) => name === "analyze-image");
    expect(analyzeCall).toBeDefined();
    expect(analyzeCall![1].body.precomputed).toEqual({
      description: "A whiteboard sketch",
      detected_text: "Q3 roadmap",
      tags: ["sketch", "planning"],
    });
  });

  it("skips the filename-only quick summary when the chip already described the document", async () => {
    vi.useFakeTimers();
    try {
      await processAndInsertContent(
        "document",
        {
          file: new File(["%PDF"], "kahn-cerf-88.pdf", { type: "application/pdf" }),
          uploadedFilePath: "user-1/staging/4-jkl.pdf",
          title: "Kahn-Cerf Certificate",
          description: "A 1988 certificate",
          snippet: "First page text",
        },
        "user-1",
        true,
        fetchItemsMock,
        vi.fn()
      );
      await vi.advanceTimersByTimeAsync(1500);

      const quickCalls = invokeMock.mock.calls.filter(([name]) => name === "quick-pdf-summary");
      expect(quickCalls).toHaveLength(0);
      const extractCalls = invokeMock.mock.calls.filter(([name]) => name === "extract-pdf-text");
      expect(extractCalls.length).toBeGreaterThan(0);
    } finally {
      vi.useRealTimers();
    }
  });

  it("reuses uploaded attachment files and chip analysis in collections", async () => {
    await processAndInsertContent(
      "collection",
      {
        content: "note",
        attachments: [
          {
            type: "audio",
            name: "memo.m4a",
            size: 1234,
            fileType: "audio/mp4",
            uploadedFilePath: "user-1/staging/5-mno.m4a",
            title: "Contract voice memo",
            description: "Voice memo about the contract",
            processedContent: "full transcript",
          },
        ],
      },
      "user-1",
      true,
      fetchItemsMock,
      vi.fn()
    );

    // No storage upload attempted (uploadFile would need a real session and File)
    const attachmentInsert = attachmentInsertPayloads.at(-1);
    expect(attachmentInsert.file_path).toBe("user-1/staging/5-mno.m4a");
    expect(attachmentInsert.title).toBe("Contract voice memo");
    expect(attachmentInsert.description).toBe("Voice memo about the contract");
    expect(attachmentInsert.metadata.processedContent).toBe("full transcript");
  });
});
```

Notes for the implementer: the existing hoisted harness captures item insert payloads (`itemsInsertPayloads`); mirror that pattern to capture `item_attachments` insert payloads (add an `attachmentInsertPayloads` array to the hoisted block and push from the attachments-insert mock) if it doesn't already exist. `analyze-collection` invoke should resolve `{ data: { title: "T", description: "D" }, error: null }` via the existing `invokeMock` default. Adjust argument-order details to match the existing file's harness exactly.

- [ ] **Step 2: Run tests to verify they fail**

Run: `npx vitest run src/utils/contentProcessor.test.ts`
Expected: New tests FAIL — `precomputed` missing from analyze-image body; `quick-pdf-summary` still invoked; attachment insert has no `file_path` from `uploadedFilePath`. (The audio test may already pass — the existing guard skips transcription when a description is provided; keep it as a regression lock.)

- [ ] **Step 3: Implement contentProcessor changes**

1. Extend `ContentData`:

```ts
  detectedText?: string;
  tags?: string[];
  snippet?: string;
```

and the attachments entry type:

```ts
    uploadedFilePath?: string;
    processedContent?: string;
```

2. Image analysis block — replace the `analyze-image` invoke body:

```ts
  if (type === 'image' && (filePath || data.uploadedFilePath)) {
    const imagePath = filePath || data.uploadedFilePath;
    const { data: imgUrlData } = supabase.storage.from('stash-media').getPublicUrl(imagePath);
    // Chip-time vision results ride along so the function writes page_body +
    // embeddings without paying for a second vision pass
    const precomputed = data.description
      ? {
          description: data.description,
          detected_text: data.detectedText ?? 'none',
          tags: data.tags ?? [],
        }
      : undefined;
    supabase.functions
      .invoke('analyze-image', {
        body: {
          itemId: insertedItem.id,
          imageUrl: imgUrlData.publicUrl,
          ...(precomputed ? { precomputed } : {}),
        },
      })
      .then(() => fetchItems())
      .catch((err) => console.error('Image analysis failed (non-fatal):', err));
  }
```

3. Document phase 1 — wrap the quick-summary `setTimeout` in a guard and pass the snippet through:

```ts
    // Phase 1: Quick summary (immediate) — skipped when the chip already
    // produced a content-based summary at capture time
    if (!data.description) {
      setTimeout(async () => {
        try {
          const fileName = data.file?.name || 'document.pdf';
          const pdfPath = filePath || data.uploadedFilePath;
          const { data: urlData } = supabase.storage.from('stash-media').getPublicUrl(pdfPath);

          console.log('Calling quick-pdf-summary for:', insertedItem.id);
          await supabase.functions.invoke('quick-pdf-summary', {
            body: {
              fileUrl: urlData.publicUrl,
              itemId: insertedItem.id,
              fileName,
              snippet: data.snippet,
            }
          });

          // Refresh UI with quick summary
          await fetchItems();
        } catch (error) {
          console.error('Quick PDF summary failed:', error);
        }
      }, 500);
    }
```

(Phase 2 `processPdfContent` stays unconditional.)

4. `processAttachments` media branch — replace the `if (attachment.file)` block:

```ts
        // Handle file upload for media attachments (chip-time staged uploads
        // are reused instead of uploading again)
        const uploadedPath = attachment.uploadedFilePath
          ?? (attachment.file ? await uploadFile(attachment.file, userId) : undefined);

        if (uploadedPath) {
          attachmentData.file_path = uploadedPath;
          attachmentData.file_size = attachment.size;
          attachmentData.mime_type = attachment.fileType;

          const hasChipAnalysis = Boolean(attachment.description || attachment.processedContent);
          if (hasChipAnalysis) {
            attachmentData.metadata = {
              ...attachmentData.metadata,
              originalName: attachment.name || attachment.title,
              aiProcessed: true,
              processedContent: attachment.processedContent,
            };
          } else {
            // Process media with AI for better descriptions
            const { processMediaAttachment } = await import('./mediaProcessor');
            const mediaResult = await processMediaAttachment(
              uploadedPath,
              attachment.type,
              attachment.name || attachment.title
            );

            if (mediaResult.title) attachmentData.title = mediaResult.title;
            if (mediaResult.description) attachmentData.description = mediaResult.description;

            attachmentData.metadata = {
              ...attachmentData.metadata,
              originalName: attachment.name || attachment.title,
              aiProcessed: true,
              processedContent: mediaResult.content
            };
          }
        }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `npx vitest run src/utils/contentProcessor.test.ts`
Expected: PASS (existing + 4 new).

- [ ] **Step 5: Commit**

```bash
git add src/utils/contentProcessor.ts src/utils/contentProcessor.test.ts
git commit -m "Reuse chip-time analysis in the save pipeline

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 9: Staging sweep on app load

**Files:**
- Modify: `src/pages/Index.tsx`
- Test: `src/pages/Index.test.tsx` (extend)

**Interfaces:**
- Consumes: `sweepStagingOrphans` (Task 2).
- Produces: nothing — fire-and-forget effect.

- [ ] **Step 1: Write the failing test**

In `src/pages/Index.test.tsx`, add alongside the other module mocks:

```ts
const sweepMock = vi.fn().mockResolvedValue(undefined);
vi.mock("@/utils/stagedUploader", () => ({
  sweepStagingOrphans: sweepMock,
}));
```

and a test (inside the existing describe, following its render pattern):

```ts
  it("sweeps staging orphans once for the signed-in user", async () => {
    render(<Index />);
    await waitFor(() => expect(sweepMock).toHaveBeenCalledWith("user-1"));
    expect(sweepMock).toHaveBeenCalledTimes(1);
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `npx vitest run src/pages/Index.test.tsx`
Expected: New test FAILS (`sweepMock` not called).

- [ ] **Step 3: Implement**

In `src/pages/Index.tsx`:

```ts
import { useState, useEffect, useRef } from 'react';
import { sweepStagingOrphans } from '@/utils/stagedUploader';
```

Inside the `Index` component, after the hooks:

```ts
  // Once per session: clear abandoned chip-time uploads (>24h, unreferenced)
  const stagingSweepRanRef = useRef(false);
  useEffect(() => {
    if (!user?.id || stagingSweepRanRef.current) return;
    stagingSweepRanRef.current = true;
    void sweepStagingOrphans(user.id);
  }, [user?.id]);
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `npx vitest run src/pages/Index.test.tsx`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/pages/Index.tsx src/pages/Index.test.tsx
git commit -m "Sweep abandoned staging uploads on app load

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 10: Full verification + edge function deploy

**Files:** none created — verification, deploy, and any fixes.

- [ ] **Step 1: Full test suite + lint + build**

```bash
npx vitest run
npm run lint
npm run build
```

Expected: all tests pass; no new lint errors (pre-existing warnings acceptable); build succeeds and shows `pdfjs-dist` in a separate lazy chunk, not the entry chunk.

- [ ] **Step 2: Deploy the two edge functions**

```bash
supabase functions deploy analyze-image
supabase functions deploy quick-pdf-summary
```

Expected: both deploy without errors (per repo deploy process — edge functions ship via supabase CLI, independent of the Lovable frontend push).

- [ ] **Step 3: Live browser verification**

Start `npm run dev`, then with the Playwright browser tools: log in, drop a real PDF into the capture area, and verify the chip shows (a) "Analyzing..." immediately, (b) a facts line like `PDF · N pages`, (c) a first-page thumbnail, (d) an AI title + description within a few seconds. Repeat with an image (dimensions + vision description) and a small audio file (duration + transcript summary). Then submit and confirm the saved card already carries the title/description, and that the network panel shows no duplicate transcription/vision calls at save time.

If live login isn't possible in the session, do a reduced smoke check: `npm run dev`, open the page, confirm no console errors from the new modules, and note the limitation in the final report.

- [ ] **Step 4: Push frontend**

```bash
git push
```

(Lovable deploys the frontend from git per the repo's deploy process.)

- [ ] **Step 5: Report**

Summarize: what shipped per stage, test counts, deploy status, anything skipped (e.g., live-login verification) — with file:line references to the key integration points.

---

## Self-review notes (completed)

- **Spec coverage:** chip stages (Tasks 1/3/6), upload progress + 3MB threshold (2/6), staging + sweep (2/9), edge modes (4/5), save reuse incl. collections (7/8), submit await ≤20s (7), silent failure ladder (1/3/6/8), out-of-scope items untouched. Video poster + duration: Task 1; video has no server stage (Task 3 skips) matching spec.
- **Type consistency:** `FileAnalysis`/`ChipAnalysisUpdate`/`ChipAnalysisHandle`/`ChipFileKind` defined once in Task 3, consumed by name in 6–7; `LocalFileFacts` from Task 1 extended by Task 3; `uploadedFilePath`/`processedContent` attachment fields match between Tasks 7 and 8; status unions match between Tasks 3, 6, 7 (`'local' | 'analyzing' | 'ready'`).
- **Placeholder scan:** all steps carry real code/commands; the two edge-function tasks use diff-review instead of tests because the repo has no Deno test infra (deliberate, documented).
