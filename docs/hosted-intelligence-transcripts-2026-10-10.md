# Transcripts at save time — handoff to the enrichment pipeline (2026-10-10)

**To:** the enrichment / hosted-intelligence agent. **From:** the web agent (app-redesign-v2).
**Why you're reading this:** Will asked that you be told about these changes and that the
enrichment pipeline (maintenance loop, repairs, evidence checks, backfill) be updated to match.

## What changed today

Video links now get their **transcript at save time**, in `scrape-page-content`, through
`supabase/functions/_shared/pageExtraction.ts` (`extractPage(url, keys, trace?)`):

| Source | Provider | Secret | Adapter | Notes |
|---|---|---|---|---|
| YouTube (`watch`, `live`, `youtu.be`; not Shorts) | Firecrawl **v2** `/v2/scrape`, `maxAge: 0` | `FIRECRAWL_API_KEY` | `_shared/youtubeTranscript.ts` `parseYouTubeMarkdown` | A fresh scrape is required: the cache serves the plain watch page without the `## Transcript` block. 1 credit per save. YouTube **never** falls through to the page cascade (chrome). |
| TikTok (`/@user/video/<id>`, `vm.`/`vt.`/`/t/` short links) | SearchApi `engine=tiktok_transcripts` | `TIKTOK_SCRAPE_API_KEY` | `_shared/socialTranscripts.ts` `fetchTikTokTranscript` | Timestamped segments joined by newline; `available_languages[].is_selected` → `language`. ~2 s. |
| Instagram (`/reel/`, `/reels/`, `/tv/`, `/p/`, `instagr.am`) | TranscriptFetch `POST /api/v2/transcripts/video` (`mode: auto`, `timestamps: false`) | `REELS_SCRAPE_API_KEY` | `_shared/socialTranscripts.ts` `fetchInstagramTranscript` | Held open up to 45 s and answered inline for Reels (1 credit per started 5 min; failures free; repeats cached). A **202** (long media) is *not* awaited at save time — see below. The caption comes back as `title` and becomes the description when the saved one was a placeholder. |

Both social adapters fall through to the existing cascade when they have no transcript, so
nothing that worked before stopped working.

### The contract every client reads

- `page_body` = the transcript (caption lines, no timestamps, ≤ 200k chars).
- `attributes.enrichment.evidence` gains `transcript: true`, `transcript_source`
  (`firecrawl-youtube` | `searchapi-tiktok` | `transcriptfetch-instagram`), `language` when
  known, and `duration_s` / `author` when the provider gives them — written through
  `apply_enrichment_patch`'s `evidence_patch` merge. This is the flag your `recoverSocial` /
  `prepareRepair` already honour (`evidence.transcript`); nothing else marks a transcript.
- `summary` is generated with `kind: 'video'` (the recording prompt).
- The web shows a video link's tabs as `summary | transcript` once the flag is set, and
  `summary | original content | transcript` (with an honest empty transcript tab) before.
  `docs/ui-changes.md` 2026-10-10 has the client-facing entry.

### Diagnosis without writes

`POST scrape-page-content { itemId, url, extractOnly: true }` returns the capture plus a
`trace` of what each adapter answered (e.g. `firecrawl 200: 13819 chars; headings: …`,
`youtube: no transcript section`, `searchapi: 58 segments, 2969 chars`,
`transcriptfetch 202: transcription still running`). Use it before touching code.

## What the pipeline should pick up

1. **Repairs and the hourly loop:** `_shared/socialEnrichment.ts` still points `recoverSocial`
   at Supadata (`SUPADATA_API_KEY`, unset). Switch the transcript step to the adapters above (same
   `evidence.transcript` outcome), or run them first and keep Supadata as a fallback only if a
   key ever lands. The YouTube path should call `extractPage` (Firecrawl, fresh) rather than any
   page fetch.
2. **TranscriptFetch 202s:** save time does not poll. A long Instagram video that returns 202
   leaves no transcript; the loop could poll `poll_url` (or we pass a `callback_url`). Reels are
   short, so this is rare.
3. **Backfill (spec 2026-09-05 §8, awaiting Will's OK):** 117 video links carry page chrome as
   `page_body` (and summaries of it that pollute Ask). Re-running them through `extractPage`
   either replaces the chrome with a transcript or, when none exists, should null `page_body`
   and `summary` so the chrome stops being indexed. Credits: ~1 per YouTube and Reel, 1 SearchApi
   request per TikTok.
4. **Evidence checks:** a transcript capture has `capture_kind: 'transcript'`; the hosted
   review's "video_not_viewed" attempt outcome should distinguish "transcript obtained" from
   "page read".
5. **Costs to watch:** Firecrawl (YouTube only, fresh scrape each save), SearchApi per request,
   TranscriptFetch per delivered transcript. Failed TranscriptFetch requests are free.

## Verified today

- "Me at the zoo" (YouTube) → transcript + summary in 11 s on prod.
- `tiktok.com/@geodesaurus/video/7694829447538576670` → 58 segments / 2,969 chars in 2.1 s (3/3).
- `instagram.com/reel/DdzpI9os_Wg/` → 1,117 chars (en) in 5.6 s, then 0.5 s from the provider's cache.

Deployed: `scrape-page-content` v25. Tests: `_shared/youtubeTranscript.test.ts`,
`_shared/socialTranscripts.test.ts`, `_shared/pageExtraction.test.ts`.
