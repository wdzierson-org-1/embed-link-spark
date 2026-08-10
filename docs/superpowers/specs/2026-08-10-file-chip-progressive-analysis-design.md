# File chips: progressive analysis on drop

**Date:** 2026-08-10
**Status:** Approved by Will (design + approach questions answered in session)

## Problem

Pasting a link into the capture input produces a chip that populates progressively within
moments (provisional domain/YouTube guess → fast metadata fetch → merged details). Dropping a
PDF, doc, voice note, image, or video produces a dead chip: icon, filename, size — nothing
else until after "Add to Stash", when everything happens at once (upload with no progress,
insert-blocking Whisper transcription for audio, a PDF "quick summary" that only reads the
filename, post-save vision analysis).

Goal: file chips behave like link chips. The chip indicates it is analyzing immediately, shows
locally extractable facts within ~100ms, shows upload progress for large files, and upgrades to
a smart title + summary within seconds — demonstrating the app deeply understands what it was
handed, before the user even saves.

## Decisions made with Will

1. **Upload timing:** files upload to Supabase storage immediately on drop (staging path),
   not on submit. Enables server analysis at chip time and near-instant submit. Orphans are
   handled by delete-on-remove plus a per-user sweep (§6).
2. **Pre-processing brain:** local *deterministic* extraction in the browser (pdf.js, EXIF,
   media durations, text snippets) + existing fast cloud models (gpt-4o-mini, gpt-4o vision,
   whisper-1) for the smart summary. No in-browser ML models.
3. **Save-path reuse:** chip-time analysis rides the insert so nothing is recomputed at save
   and library cards appear pre-enriched.

## 1. Chip experience (stages overlap; each merges into the display)

| Stage | Latency | Source | Chip shows |
|---|---|---|---|
| 0 Instant | 0ms | none | icon/thumbnail, filename, size, "Analyzing…" |
| 1 Local facts | ~50–300ms | browser | facts line replaces bare size; real thumbnails |
| 2 Upload | 0ms → done | XHR | thin progress bar + % (spinner only if < ~3MB) |
| 3 Smart summary | ~1–4s after upload | edge fns | AI title + one-line description (link-chip layout) |

Per-type stage 1 facts:
- **PDF:** page count, embedded metadata title/author, first-page text snippet (≤ ~1,500
  chars from pages 1–2), first-page rendered thumbnail (pdf.js canvas → data URL). Facts line
  e.g. `PDF · 12 pages`.
- **Image:** dimensions, EXIF capture date + camera model when present (exifr). Facts line
  e.g. `JPEG · 4032×3024 · Apr 2026`. Keeps existing object-URL thumbnail.
- **Audio:** duration via `<audio>` `loadedmetadata`. Facts line e.g. `Audio · 3:24`.
- **Video:** duration + dimensions + poster frame captured ~0.5s in (canvas → data URL) used
  as the chip thumbnail. e.g. `Video · 1:12 · 1920×1080`.
- **Text-like (txt/md/csv/json):** word count + opening snippet (first ~2KB read).
- **docx/other binaries:** type + size only (no client parsing in v1).

Per-type stage 3 analysis (after upload completes):
- **Image:** `analyze-image` stateless mode → description, detected_text, tags.
- **Audio:** `transcribe-audio` (already stateless) → full transcript + summary; chip shows
  the summary, transcript kept on the item state for save.
- **PDF + all other documents:** `quick-pdf-summary` with the *locally extracted snippet* +
  filename → content-based title + description. Empty snippet (scanned/encrypted PDF, docx)
  degrades to today's filename-only guess.
- **Video:** none in v1 (no server video analysis exists); chip keeps local facts.

Transitions reuse the existing link-chip metadata fade (opacity pulse on content signature
change, generalized from the current link-only implementation).

## 2. Client state model

`InputItem` (UnifiedInputPanel) gains for file types:

```ts
interface FileAnalysis {
  // stage 1 (local)
  factsLine?: string;          // "PDF · 12 pages"
  snippet?: string;            // extracted text sample (feeds quick summary + save)
  pageCount?: number;
  dimensions?: { width: number; height: number };
  durationSeconds?: number;
  thumbnailDataUrl?: string;   // pdf page 1 render / video poster
  exifSummary?: string;        // "Apr 2026 · iPhone 15 Pro"
  // stage 3 (server)
  title?: string;
  description?: string;
  transcription?: string;      // full transcript (audio) — for save reuse
  detectedText?: string;       // vision OCR text (image) — for save reuse
  tags?: string[];
  // upload
  uploadedFilePath?: string;   // staging path once upload completes
}

// per-item fields
fileAnalysis?: FileAnalysis;
uploadState?: 'uploading' | 'done' | 'failed';
uploadProgress?: number;        // 0–100
analysisState?: 'local' | 'analyzing' | 'ready' | 'failed';
```

Existing `processingStatus` on InputChip props is superseded for files by
`uploadState`/`analysisState` (link chips keep `metadataStatus` untouched).

## 3. New client units

1. **`src/utils/localFileAnalysis.ts`** — pure `analyzeFileLocally(file: File):
   Promise<LocalFileFacts>` + per-type helpers. Lazy `import('pdfjs-dist')` (worker via Vite
   `?url` import) and `import('exifr')` so the main bundle is unchanged. All failures return
   partial facts, never throw.
2. **`src/utils/stagedUploader.ts`** — `uploadToStaging(file, userId, onProgress)` using
   XMLHttpRequest against the storage REST endpoint with the session token (supabase-js
   `upload()` cannot report progress); path scheme `${userId}/staging/${Date.now()}.${ext}`
   in the `stash-media` bucket. Also `removeStagedFile(path)` and
   `sweepStagingOrphans(userId)` (§6). One automatic retry on upload failure.
3. **`src/utils/chipFileAnalysis.ts`** — orchestrator mirroring `hydrateLinkMetadata`'s role:
   `analyzeDroppedFile(file, userId, onUpdate, opts)` runs stage 1 and stage 2 in parallel,
   then stage 3 for the type; emits partial `FileAnalysis` merges + state changes through
   `onUpdate`. Returns a handle exposing a promise of the final analysis (submit awaits
   in-flight work, §5) and an `abort()` used on chip removal. UI-free, unit-testable.

## 4. Touched client units

- **`UnifiedInputPanel.tsx`** — `addFileItem` starts the orchestrator per chip;
  `removeInputItem` aborts analysis and fire-and-forgets staging delete; `handleSubmit`
  threads `uploadedFilePath` + analysis into `onAddContent` for both single-media and
  collection attachment payloads.
- **`InputChip.tsx`** — file chips adopt the link-chip layout (thumbnail, title line,
  description line, status line, bottom progress bar). File rendering extracted to a
  `FileChipContent` subcomponent in the same file. Status copy: "Analyzing…" while
  local/serving, "Uploading · 45%", "Will upload when you save" on upload failure. Analysis
  failure is silent (facts stay).
- **`contentProcessor.ts`** — skip logic (§5) + collection attachment passthrough.

## 5. Save-path reuse

`handleSubmit` payload additions — single media: `uploadedFilePath`, `title` (AI title ||
filename), `description`, `content` (audio transcript), `detectedText`, `tags`, `snippet`.
Collection attachments: `uploadedFilePath`, `title`, `description`, `processedContent`
(transcript/snippet-derived), `fileType`, `size` (existing).

`processAndInsertContent` / `processAttachments` changes:
- Upload already skipped when `uploadedFilePath` present (single media); `processAttachments`
  gains the same skip + uses provided title/description/processedContent instead of calling
  `processMediaAttachment`.
- **Audio:** provided `description` + `content` mean the insert-blocking transcription branch
  is skipped entirely. If chip analysis is still in flight at submit, submit awaits the
  orchestrator's promise (bounded by a ~20s timeout fallback to today's behavior) rather than
  re-running Whisper.
- **Image:** insert carries description; post-insert call becomes `analyze-image` with
  `{itemId, imageUrl, precomputed: {description, detected_text, tags}}` → function skips
  vision, performs its existing DB update (`description`, `page_body` when OCR text real) +
  embeddings re-generation. No second vision spend.
- **Document:** insert carries content-based title/description; the filename-only
  `quick-pdf-summary` post-insert call is skipped when a description was provided; full
  `extract-pdf-text` phase runs unchanged (it still replaces everything with real full-text
  results and owns `page_body`).
- No chip analysis (failure/legacy paths, WhatsApp/Twilio ingest): behavior identical to
  today. Nothing may make saving less reliable than the current pipeline.

## 6. Staging cleanup

- Chip removed → `removeStagedFile` fire-and-forget.
- Abandoned tabs → once per session on app load: list own `${userId}/staging/` (storage RLS
  scopes to own folder), collect files older than 24h, drop any whose path is referenced by
  `items.file_path` or `item_attachments.file_path` (saved items keep their staging path;
  no move-on-save), delete the rest. Client-side, fire-and-forget, no new tables, no cron.

## 7. Edge function changes

- **`analyze-image`:** `itemId` optional → without it, run vision, return
  `{description, detected_text, tags}`, no DB writes. New optional `precomputed` → with
  `itemId`, skip vision and run only the existing update + embeddings block.
- **`quick-pdf-summary`:** optional `snippet` param included in the prompt for content-based
  results; `itemId` optional for return-only mode (skip DB update). Handles any document
  type; function name unchanged.
- **`transcribe-audio`:** unchanged.
- Deploy via `supabase functions deploy <name>` per existing process.

## 8. Error handling summary

| Failure | Behavior |
|---|---|
| Local extraction (encrypted PDF, bad EXIF, huge file) | silent; chip keeps filename+size; stages 2–3 proceed |
| Upload (after 1 retry) | chip notes "Will upload when you save"; save path uploads as today |
| Server analysis | silent; chip keeps local facts; post-save pipeline unchanged as safety net |
| Submit while analysis in flight | await orchestrator ≤ ~20s, else fall back to today's save-time processing |
| Chip removed mid-flight | orchestrator aborted; staged file deleted |

## 9. Testing

- `localFileAnalysis.test.ts` — per-type extraction with fixture blobs; pdf.js mocked;
  failure paths return partial facts.
- `chipFileAnalysis.test.ts` — mocked uploader + `supabase.functions.invoke`; asserts update
  sequence (facts before upload-done before summary), abort behavior, retry-once, promise
  resolution for submit-await.
- `UnifiedInputPanel.test.tsx` (extend) — drop populates chip states progressively; submit
  payload carries `uploadedFilePath` + enrichment; chip removal triggers staged delete.
- `contentProcessor.test.ts` (extend) — audio insert skips transcription when content
  provided; image path calls analyze-image with `precomputed`; document path skips
  quick-pdf-summary when description present; attachments passthrough.
- TDD (superpowers:test-driven-development) during implementation.

## 10. Out of scope

In-browser ML models, docx/office client-side parsing, server video analysis, upload
concurrency queues / TUS resumable uploads, WhatsApp/Twilio capture enrichment, tag
persistence changes (analyze-image returns tags but persists none today — unchanged).

## New dependencies

`pdfjs-dist`, `exifr` — both dynamically imported at first use.
