# Long audio transcription — design

**Status:** built 2026-09-09 from Will's report that a 44-minute m4a came back
with a filename-guessed description and no transcript or summary. Decisions
below were made in an autonomous session and are flagged where they are
judgment calls.

## What broke (root cause, from the function logs)

Will's `2026-09-09 080004.m4a` is 39,489,464 bytes (37.7 MB, 44:32, mono AAC
at 115 kbps). `transcribe-audio` downloaded it and posted the whole file to
OpenAI, which rejected it twice (once from the chip-time preview, once at
save) with:

```
413: Maximum content size limit (26214400) exceeded
```

OpenAI's transcription endpoint caps uploads at 25 MiB for every model and
has no URL, async, or batch input. The web client then fell through to
`generate-description`, which wrote the "likely contains a recording from
September 9…" guess from the filename. That guess is fake enrichment
(ETHOS: never fake it), and nothing ever writes `summary` for audio/video —
0 of the 37 audio/video items in production have one.

Every audio/video path shares the cap: web save, chip preview, `add-file`
(iOS + extension), and video of any size (the whole video was being posted,
not its audio track).

## Goals

1. Any recording a client is allowed to upload (100 MB audio/video cap on web
   and iOS) gets a full transcript, a real summary, a card blurb, and an
   AI title — even when that takes minutes.
2. Capture never waits on it. Status is visible and honest while it runs;
   failures say why.
3. No new vendor. OpenAI is the only transcription key in production and the
   fix must work with it (see *Alternatives*).

## Design

### 1. Chunk on the server by demuxing, not by re-encoding

Edge functions cannot run ffmpeg (256 MB, 2 s CPU per request), but they do
not need to decode anything. An m4a/mp4/mov file is an ISO-BMFF container:
`moov` holds the sample tables (`stts/stsc/stsz/stco`), `mdat` holds raw AAC
frames. A new pure module, `supabase/functions/_shared/mp4Audio.ts`:

- **`parseAudioTrack(read, fileSize)`** walks the top-level atoms with tiny
  HTTP `Range` reads (Supabase Storage answers 206; Will's file has `moov`
  at the *end*, after a 39 MB `mdat`), fetches only `moov`, and returns the
  `soun` track: timescale, the verbatim `stsd` box (codec config), and
  per-sample offset/size/delta typed arrays. Videos (`.mp4`/`.mov`) are the
  same container; only the audio track is read.
- **`planChunks(track, { maxBytes, maxSeconds })`** cuts the sample list
  into consecutive runs of ≤ 24 MiB *and* ≤ 20 min. Deterministic: the same
  file always yields the same plan, which is what makes resumption safe.
- **`buildChunkFile(read, track, chunk)`** fetches that chunk's bytes in
  ≤ 8 MiB range windows (so an interleaved video costs bandwidth, not
  memory) and muxes a minimal, valid `.m4a` around them: `ftyp` + `moov`
  (copied `stsd`, run-length `stts`, one-chunk `stsc`, `stsz`, `stco`) +
  `mdat`. Peak memory per chunk ≈ 3 × 24 MiB; CPU is byte copying.

Files ≤ 24 MiB in any format OpenAI accepts are still sent whole. Larger
files in a non-ISO-BMFF container (`webm`, `ogg`, `mp3`, `wav`) fail
honestly with `unsupported_container` — MP3/WAV splitters are cheap to add
later but nothing clients produce today needs them (voice memos and phone
video are all m4a/mp4/mov; a 25 MB opus/webm is hours long).

### 2. `transcribe-audio` becomes a job that owns its writes

Two modes, one function:

- **Preview (unchanged contract):** `{ audioUrl, fileName }` →
  `{ transcription, description }`, synchronous, used by the chip before
  save. New: files > 24 MiB return `{ transcription: '', description: '',
  deferred: true }` immediately instead of failing; the chip skips them
  client-side too.
- **Job (new):** `{ itemId }` → `202 { accepted: true }` at once; work
  continues in `EdgeRuntime.waitUntil`. Auth: the item's owner (user JWT),
  the service role (from `add-file`), or `x-cron-secret` (sweep and
  self-continuation). The job:
  1. Marks `attributes.media.transcript = { status: 'processing', … }`.
  2. Plans chunks (or sends the whole file when small).
  3. Transcribes chunks **in order**, passing the tail of the previous
     chunk's text as `prompt` for continuity, and appends each chunk's text
     to `page_body` as it lands (the Transcript tab fills in live), bumping
     `chunks_done`.
  4. When the wall-clock budget (240 s of the Pro plan's 400 s) runs low with
     chunks left, it persists progress and re-invokes itself with the cron
     secret. If that invocation never runs, the sweep resumes from
     `chunks_done` — resumption is the normal path, not a special case.
  5. Finalizes: `description` (≤ 60-word card blurb), `summary`
     (`generateSummary` kind `recording`: participants/topics/decisions/
     action items, ≤ ~300 words), AI title when the title is still
     filename-shaped (existing `titlePolicy`), `attributes.media.kind`, and
     `generate-embeddings` over title + notes + transcript + summary. Sets
     `status: 'done'`.
  6. Any failure sets `status: 'failed'` with a machine `error` code and
     increments `attempts`; `page_body` keeps whatever landed.

Model: `gpt-4o-transcribe` (same $0.006/min as `whisper-1`, lower word
error rate), with an automatic per-chunk fallback to `whisper-1` on a
non-transient API error. Env `TRANSCRIBE_MODEL` overrides. *Judgment call:*
no speaker diarization yet — `gpt-4o-transcribe-diarize` cannot keep speaker
identities consistent across chunks without reference audio.

- **Sweep:** `{ sweep: true }` + `x-cron-secret`, scheduled by pg_cron every
  10 minutes (migration mirrors `reminder-digest`). Picks up to 3 audio/video
  items from the last 14 days that are `pending`, `failed` with
  `attempts < 3`, `processing` but untouched for 15 min, or have no
  transcript state at all (legacy rows and Will's item), and runs the job
  for each. This is also how a crashed job or a closed browser tab gets
  finished.

### 3. Data contract (all platforms)

`attributes.media.transcript` (additive; whole-blob read-merge-write,
unknown keys preserved — iOS's `MediaAttributes` drops nested unknown keys
today, so the iOS mirror should add the field when it next touches media):

| Key | Value |
|---|---|
| `status` | `'pending' \| 'processing' \| 'done' \| 'failed'` |
| `source` | `'openai:<model>'` once a chunk has succeeded |
| `chunks_total`, `chunks_done` | integers; `chunks_total` is 1 for whole-file sends |
| `attempts` | job starts, for the sweep's back-off |
| `updated_at` | ISO; staleness signal for the sweep |
| `error` | only when failed: `download_failed`, `no_audio_track`, `unsupported_container`, `transcription_failed`, `no_speech` |

Lanes stay clean: transcript → `page_body` (cap 200,000 chars); short AI
blurb → `description`; long AI summary → `summary`; nothing in `content`.
`description` stays **null** until the transcript exists — no filename
guesses for audio/video anywhere.

### 4. Clients

- **`add-file`:** sets `media.kind` + `media.file_name` and
  `transcript.status = 'pending'` in its post-response step, then invokes
  the job with `{ itemId }`. It no longer parses transcription results or
  derives titles (that logic moves into the job).
- **Web save (`contentProcessor`):** audio/video with chip results insert
  as today. Without them, the item inserts immediately (description null,
  `transcript.status = 'pending'`) and the job is invoked fire-and-forget
  after insert, like `analyze-image`. The `generateDescription` filename
  fallback for audio/video is removed.
- **Web chip (`chipFileAnalysis`):** skips the preview call for files
  > 24 MiB.
- **Web detail sheet:** the Transcript tab's empty state reads
  `transcript.status`: "Transcribing… part 2 of 3" / "Transcribing…" while
  it runs, a plain-language reason when failed, and the existing "No
  transcript available" only when there is nothing to say. Cards keep
  expecting `description` for audio/video (the assembly chip retires
  honestly at its 2.5-minute window; long recordings finish after it).

### 5. Testing

- `mp4Audio.test.ts` (vitest, Node): three committed fixtures generated
  with `say` + `afconvert`/`ffmpeg` (moov-first m4a, moov-last m4a, mp4 with
  a video track). Asserts track parsing, that a moov-last file never reads
  `mdat` to find `moov`, chunk plans by bytes and by seconds, and that every
  chunk file round-trips through the parser with byte-identical samples and
  bounded range windows.
- Dev-time: the module run under Node over Will's real file writes chunk
  files that `ffprobe` decodes with durations summing to 44:32.
- Web: `contentProcessor.test.ts` / `chipFileAnalysis.test.ts` cover the
  insert-then-job path and the size skip.
- Production: after deploy, the sweep (or a manual `{ itemId }` call) runs
  Will's item; `page_body`, `summary`, `description`, title and
  `transcript.status = 'done'` are verified by SQL.

## Alternatives considered

- **AssemblyAI / Deepgram / ElevenLabs Scribe** accept a public URL, have no
  practical size cap, run async with webhooks, and add speaker labels. They
  would make the demuxer unnecessary, but each needs a new account and key
  Will has to create. Recommended as the follow-up if speaker labels matter;
  the job/status contract here is provider-agnostic, so swapping the chunk
  loop for a URL submit + webhook is contained to `transcribe-audio`.
- **Client-side splitting** (Web Audio API on web, AVAssetExportSession on
  iOS): rejected — clients must never orchestrate enrichment (ETHOS), and it
  would have to be built twice.
- **Raising the upload cap / rejecting big files:** rejected — recording a
  meeting is the recording use case.
