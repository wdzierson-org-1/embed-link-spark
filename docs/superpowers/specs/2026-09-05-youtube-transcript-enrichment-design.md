# YouTube transcript enrichment — design

**Date:** 2026-09-05 · **Status:** awaiting Will's review · **Scope:** backend
(`scrape-page-content`), web detail sheet, iOS detail sheet, one-off backfill.

Companion to the thumbnail fix shipped the same day (`_shared/youtube.ts`,
change-log entry "YouTube links: real thumbnail + title from the URL alone").
That fix made the card right; this spec makes the *object* right: a saved
YouTube video gets its transcript, its own description, its duration and
channel, and a video-aware summary, so it is findable in Ask and readable
in the detail sheet without leaving Stash.

## 1. Why

- **Transcripts are the content.** For an article, `page_body` holds the
  article. For a video, the transcript is the equivalent: it is what Ask
  should retrieve against and what the user wants to skim. ETHOS: "server-
  side enrichment (titles, transcripts, OCR, summaries, embeddings) makes
  everything findable."
- **Today's YouTube `page_body` is junk.** YouTube answers Supabase's egress
  IPs with HTTP 429; the scrape cascade then falls to the Jina reader, which
  returns YouTube's navigation chrome ("Skip navigation Search …"). Every
  YouTube link saved since late August carries 1–50 KB of that chrome as
  `page_body`, an AI `summary` *of the chrome*, and embeddings of both. This
  pollutes Ask.
- **Direct caption scraping is dead.** YouTube's caption endpoint returns an
  empty body even from a residential IP (probed 2026-09-05), and cloud IPs are
  blocked outright. Every approach that works in 2026 is a hosted service.

## 2. Evidence gathered (2026-09-05)

| Probe | Result |
|---|---|
| Watch page from Supabase egress | `HTTP 429: Too Many Requests` (function logs) |
| `youtube.com/oembed` from Supabase egress | 200, title + author + `hqdefault` thumbnail |
| `youtube.com/api/timedtext` (caption XML) from residential IP | 200, **0 bytes** |
| Firecrawl scrape of a watch URL | markdown with thumbnail, title, uploader, upload date, length, views, likes, category, `## Description` block, `## Transcript` block; `postprocessorsUsed: ["youtube"]`, 1 credit |
| `FIRECRAWL_API_KEY` in Supabase secrets | **not set** (so `scrape-page-content`'s Firecrawl branch has never run) |
| Link volume | Aug 2026: 90 links / 6 YouTube / 5 users; Sep so far: 20 / 0 / 3 |

Firecrawl's YouTube post-processor (firecrawl/firecrawl PR #2157) triggers on
`youtube.com/watch`, `youtube.com/live/`, `youtu.be/`, and mobile hosts. It
does **not** trigger on `/shorts/`. The transcript language follows
`location.languages[0]`, default English. No TikTok/Instagram support.

Pricing: Firecrawl 1 credit per scrape; Free 1,000 credits, Hobby $16/month
for 5,000, $5 top-ups. Supadata ($5/month for 300, covers TikTok/Instagram/X)
was considered and deferred: it only helps video links, needs a new
integration, and TikTok volume is ~1/month.

## 3. Decisions

1. **Transcript source = Firecrawl v2 `/v2/scrape`** (`formats: ['markdown']`,
   `onlyMainContent: true`, `location: { languages: ['en'] }`). The existing
   `scrape-page-content` already calls Firecrawl first when the key is set;
   we move it from `/v1/scrape` to `/v2/scrape` (same `data.markdown` shape,
   and v2 is where the YouTube post-processor is documented). **Will creates
   the Firecrawl account and sets `FIRECRAWL_API_KEY`** in Supabase secrets;
   the code path stays inert until then.
2. **Firecrawl runs for every link, not just video.** That is what the
   function was written for, it improves article extraction, and at ~100
   links/month the cost is a rounding error. The cascade (direct → crawler UA
   → Jina → Wayback) remains the fallback when Firecrawl returns nothing or
   the key is absent. Revisit gating if volume grows past the plan.
3. **Video-flavor YouTube links never store cascade chrome.** If Firecrawl
   yields no transcript (no key, Shorts, captions disabled, credits
   exhausted), `page_body` stays **null** and no summary is generated. An
   honest empty state beats a decorative one (ETHOS: never fake enrichment).
4. **Lanes stay clean.** Transcript → `page_body`. The video's own description
   → `description` (short form). AI summary of the transcript → `summary`.
   Structured facts → `attributes.link`. Nothing is pasted into `content`.
5. **Detail sheet: video links get a Transcript tab** on web and iOS, reusing
   the transcript tab audio/video files already have. Tab config becomes
   flavor-aware (`type` + `attributes.link.flavor`), not a new item type.
6. **Out of scope:** TikTok/Instagram transcripts (Supadata later), Whisper
   fallback for caption-less videos (Firecrawl `audio` format + our
   `transcribe-audio`; expensive, revisit on demand), timestamps/chapter
   navigation, transcript language selection.

## 4. Data contract (all platforms)

For a link whose `attributes.link.flavor === 'video'` and whose URL carries a
YouTube video id:

| Field | Value | Written by |
|---|---|---|
| `page_body` | Transcript as plain text, one caption line per line, no timestamps. Cap **200,000 chars** (≈3.5 h of speech; the general link cap of 50,000 stays for non-video). | `scrape-page-content` |
| `description` | First non-empty paragraph of the video's own description, ≤300 chars, entity-decoded. Replaces the synthetic `Watch "<title>" by <channel> on YouTube` line **only when the real description is non-empty**. | `scrape-page-content` |
| `summary` | `generateSummary(kind: 'video')` over the transcript (new kind; prompt says "a saved video's transcript"). Null when no transcript. | `scrape-page-content` |
| `attributes.link.duration_s` | Parsed from Firecrawl's `**Length**` (`MM:SS` / `HH:MM:SS`). Already modeled; the web card already renders a duration chip for video flavor from it. | `scrape-page-content` |
| `attributes.link.author` | Firecrawl's `**Uploaded by**` (channel name). Already modeled. | `scrape-page-content` |
| `attributes.link.transcript` | **New.** `{ source: 'youtube-captions', language: 'en', captured_at: ISO }` — present only when a transcript was stored. Lets list views (which omit `page_body`) know a transcript exists. Whole-blob read-merge-write; unknown keys preserved. | `scrape-page-content` |
| `title` | Unchanged (oEmbed title from the thumbnail fix). | — |
| embeddings | Re-embedded as today: title + description + summary + notes + URL + `page_body`. 600-char chunks; a 2-hour transcript is ~200 chunks, cost negligible. | `generate-embeddings` |

Type additions: `LinkAttributes.transcript?: { source: 'youtube-captions'; language?: string; captured_at?: string }` in `src/types/itemAttributes.ts` and the StashKit `LinkAttributes` mirror (both round-trip unknown keys already).

## 5. Enrichment flow

`add-url` is unchanged: quick pass → respond → deep metadata → `scrape-page-content`.

`scrape-page-content` becomes:

```
1. firecrawl = key ? scrapeWithFirecrawl(url, { v2, location.languages ['en'] }) : null
2. if getYouTubeVideoId(url):
     parsed = parseYouTubeMarkdown(firecrawl?.markdown)   // pure, tested
     if parsed.transcript:
        page_body   = parsed.transcript (≤200k)
        description = parsed.descriptionShort ?? keep
        attributes.link += { duration_s, author, transcript: {…} }  (read-merge-write)
        summary     = generateSummary(kind 'video', transcript)
        re-embed
     else:
        log reason (no-key | no-transcript | firecrawl-error); write nothing; return { success:false, reason }
     return   // never fall through to the cascade for YouTube
3. else (non-YouTube): today's behavior — Firecrawl markdown if usable, else cascade
```

`parseYouTubeMarkdown` (new, `_shared/youtubeTranscript.ts`): splits on the
`## Description` / `## Transcript` headings, strips the fenced code block
around the description, reads `**Length**: …` and `**Uploaded by**: [name](…)`
from the metadata lines. Unit-tested against a fixture captured from the real
Firecrawl response (the "Me at the zoo" scrape from the spike) plus edge
cases: no transcript section, description without a code fence, `HH:MM:SS`
length, missing uploader.

Firecrawl errors: 30 s timeout as today; non-2xx (incl. 402 credits
exhausted) logged with status and treated as "no transcript". Nothing retries
in-request; `retry-pending-scrapes` already re-runs links whose `page_body`
is null, so a transient failure gets another attempt on its normal schedule.

## 6. Detail sheet

**Tabs (web `getContentTabsConfig`, iOS `contentTabsConfig`)** gain a flavor
argument. For `link` + `flavor === 'video'`:

- Title "Notes & Transcript"; tabs **Summary / Transcript / Notes**; default
  `summary`.
- Transcript tab renders `page_body` read-only through the same
  `ReadOnlyText`/`MarkdownBlocksView` path audio uses (transcript is plain
  lines, so it renders as paragraphs).
- Empty states (honest): item younger than the enrichment window
  (`itemAssembly`'s existing "enrichment can run this long" constant on web;
  same value on iOS) → "Fetching transcript…"; otherwise → "No transcript
  available for this video." Summary tab absent → "No summary yet".
- `needsSourceContent` is true for these items (it already is for links).

Non-video links keep Summary / Original Content / Notes. Audio/video files
are untouched.

**Cards:** no new layout. The video-flavor card already shows a duration chip
from `attributes.link.duration_s`; it now has data. Optional: a "transcript
saved" meta chip when `attributes.link.transcript` is present, mirroring the
article card's "full text saved" — cheap, ships with the web change, iOS
mirrors when convenient.

## 7. Ask / retrieval

No contract change. Transcript chunks flow through the existing embedding and
`search-items` paths; the "Video" filter already matches video flavor.
Citations show the item as today.

## 8. Backfill

One-off script (not a function): for every `type='link'` YouTube row, call
`scrape-page-content`. With the new YouTube branch that either replaces the
chrome with a transcript (and regenerates summary + embeddings) or, when no
transcript is available, **nulls `page_body` and `summary`** so the chrome
and its fake summary stop polluting Ask. ~20 rows today. `retry-pending-
scrapes` will not do this on its own because it only selects null
`page_body`.

## 9. Testing

- `_shared/youtubeTranscript.test.ts` — parser fixtures (vitest).
- `_shared/summarize` — `kind: 'video'` label test.
- `src/utils/editPanelTabs.test.ts` — flavor-aware config (video link → 3
  tabs incl. transcript; article link unchanged; audio unchanged).
- StashKit `ItemRulesTests` — same matrix for `contentTabsConfig`.
- Live: save a YouTube URL as `will+uitest`; within ~30 s expect
  `page_body` = transcript text, `summary` non-null, `attributes.link`
  carrying `duration_s`/`author`/`transcript`; open the detail sheet on web
  and confirm the Transcript tab. Delete the row afterwards.
- Negative: a Shorts URL → `page_body` null, `summary` null, empty state copy
  shown.

## 10. Rollout order

1. Will: create the Firecrawl account, `supabase secrets set FIRECRAWL_API_KEY=…`.
2. Deploy `scrape-page-content` (parser + v2 + YouTube branch + video summary kind).
3. Web: `itemAttributes.ts` type, `editPanelTabs.ts` flavor arg, transcript
   tab empty states, optional chip. `docs/ui-changes.md` entry; PLATFORM_API
   note under `add-url` enrichment.
4. iOS: `LinkAttributes.transcript`, `contentTabsConfig(for:flavor:)`,
   `ItemDetailContent` empty-state copy.
5. Backfill script over existing YouTube rows.

Steps 2–4 can land before step 1; nothing breaks without the key, YouTube
links simply keep an empty transcript tab instead of chrome.

## 11. Open questions

None blocking. Two things to confirm on the first live run with the key:
whether Firecrawl's v2 response for a very long video (2 h+) arrives inside
the 30 s timeout, and that a captioned video really costs the documented
1 credit per scrape (Firecrawl's `audio` format, which we do not request,
is priced separately).
