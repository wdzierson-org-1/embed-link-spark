# UI changes — cross-platform log

Purpose: every meaningful web-UI/product-behavior change lands here as a dated
entry so the agents building the **iOS** (`ios/`) and **macOS** clients can
mirror behavior and data contracts without reverse-engineering the web code.
Newest entries first. Write for implementers on another platform: contracts
first, visuals second, with pointers to specs and source.

---

## 2026-10-10 · Maintenance preserves transcript evidence and source descriptions

- **Contract (all platforms):** recovered link transcripts retain `page_body` and
  `attributes.enrichment.evidence { transcript: true, capture_kind: 'transcript',
  transcript_source, language?, duration_s?, author? }`. Maintenance now preserves
  these fields from `scrape-page-content`'s `extractOnly` result, validates the
  body before attaching evidence, and generates a recording-style `summary`.
  Meaningful descriptions and existing richer transcripts survive repair.
- **Recovery:** a usable caption no longer prevents a known YouTube or TikTok
  video from reaching the existing transcript capture path. Pending provider IDs
  prevent a second fallback even when that provider's key is unavailable. Successful
  replacement clears the earlier provider failure; an extraction exception retains
  the attempted flag and updated provider state so it cannot silently restart on
  the next review.
- **Instagram boundary:** successful captures receive the same evidence fix.
  Newly retrying caption-bearing Instagram saves remains deferred until durable
  TranscriptFetch submission and job polling are implemented. Its current HTTP 202
  path loses the job ID, and its timeout exceeds the maintenance request deadline.
  The two outstanding regression cases are explicit TODOs. Historical exhausted
  jobs need a separate bounded replay that preserves pending IDs.
- **Client coordination:** link evidence uses `enrichment.evidence.transcript`;
  uploaded audio/video progress still uses `media.transcript`. When the link flag
  changes, an open detail panel should clear and refetch its loaded source body and
  summary before labeling it a transcript. This frontend follow-up was handed to
  Claude through the shared coordination file; it is not included in this backend
  change. Place enrichment and other attribute leaves keep their existing contracts.
- **Implementation:** `_shared/enrichmentMaintenance.ts`, `enrichmentRepair.ts`,
  and `enrichmentMaintenance.transcripts.test.ts`. This entry describes the code
  change; production deployment is a separate step.

## 2026-10-10 · Full-size stages: one minimize

At full size a media stage showed two minimize controls — the ink bar's cell and the stage's
hover cell (which had turned into "exit full size"). The hover cell now offers only **full
size**, at rest; at full size the bar's **minimize** cell and Esc are the way back
(`edit/StageFull`). iOS: a full-size stage carries one close/minimize affordance.

## 2026-10-10 · Map-based shares: `attributes.place`, the map as the picture, the location section

Will: "let's enrich map-based shares … to show an embedded map as the image for the card as
opposed to the icon we currently show … for business listings … also add the open/closing hours,
phone number, and link to the menu if available … a new 'location details' section, similar to
the item details section at the bottom of the details screen." Decisions (2026-10-10): the map
is a rendered image (Mapbox static), business facts come from the share's own page (no
Yelp/Google lookups), map links first, screenshots and photos with addresses next.

- **Contract (all platforms): `attributes.place` v1** (`supabase/functions/_shared/place.ts`;
  web type `PlaceAttributes`). Written only by the capture pipeline, through the leaf
  compare-and-swap `set_item_place(target_id, expected_url, expected_place, place)`
  (migration `20261010180000`, applied): `name`, `address { lines, street, locality, region,
  region_code, postal_code, country, country_code }`, `geo { latitude, longitude }`,
  `timezone` (IANA, when the provider states it), `phone` (as given, E.164 when known),
  `website`, `menu_url`, `hours` (`[{ days: [0=Sun…6], ranges: [{ open: "HH:MM", close,
  next_day? }] }]`), `rating { score, max, count?, source }`, `price_range { level, max }`,
  `category`, `provider { kind: apple-maps | google-maps | page, place_id?, url }` (the
  resolved place address), `map { file_path, provider: mapbox, style, zoom, rendered_at }`,
  `evidence { source_url, observed_at, method: map-page | map-url | json-ld,
  extraction_version: place-v1 }`. Clients read it with `readPlace()`; unknown keys stay.
- **The picture is the map.** When `MAPBOX_ACCESS_TOKEN` is set, the pipeline renders
  `mapbox/light-v11` with an ink pin at the place (1200×630 @2x, attribution kept) into
  `stash-media/<uid>/previews/map_<itemId>.png` and sets `items.file_path` to it, so the card
  hero, the panel stage, the shared page and the link unfurl all show the map with no client
  work. Only a picture Stash fetched itself (`…/previews/preview_*`, an earlier `map_*`) or no
  picture gives way; a person's upload is never replaced. A map already rendered for the same
  spot is reused.
- **Title:** a save titled by the provider ("Apple Maps", "Google Maps") or a placeholder takes
  the place's name (never a protected title). **Kind label:** a link with `attributes.place`
  reads `place` on cards and in the window bar (`kindLabel`).
- **Pipeline:** `scrape-page-content` runs the place step last (its own snapshot) for
  map-provider addresses — Apple Maps including `maps.apple/p/…` short links, Google Maps
  including `maps.app.goo.gl` — and for listing pages whose publisher facts carry coordinates.
  It follows the address as a browser would (map short links answer 404 to other clients),
  reads the resolved URL (`coordinate`, `name`, `address`, `place-id`; Google's `!3d…!4d…`,
  `@lat,lng`, `q=`), and for Apple Maps the page's own embedded data: the hours calendar,
  telephone, website, the Menu link, Yelp rating and count, price level, category, time zone,
  structured address and centre. Place facts join the search text.
- **Web — the location section** (`edit/LocationDetailsSection`), above the details drawer on
  the panel and the shared page, in the details tree style: address (opens the provider's
  page), hours — `open · closes 9:00 PM` / `closed · opens Fri 4:00 PM` only when the place's
  time zone is known, else today's hours; the week expands — phone (`tel:`), website, menu,
  rating, price, category; cells **Directions** (Apple Maps for Apple saves, Google Maps
  otherwise) · **Call** · **Menu** · **Website**; `From Apple Maps, observed Oct 10, 2026.
  Hours and details can change.` The beta publisher-facts section stands down for a place
  that has the lane.
- **iOS / macOS:** read `attributes.place` and render the same section (plan 17, round 4);
  the map needs nothing — it is the save's picture.
- **Round 2 (same day) — pictures with an address.** After `analyze-image` has read a picture,
  `add-file` runs the image place step (`runImagePlaceStep`): street addresses in the picture's
  own text (OCR in `page_body`, the vision description) — "107 Charles St, Boston, MA 02114",
  a street line with the city line under it, European "Classensgade 4, 2100 København" — are
  confirmed with Mapbox Geocoding v6 (`types=address`, `autocomplete=false`; only `exact` /
  `high` matches count) and kept as the same lane with **`provider.kind: 'ocr'`**,
  `evidence.method: 'ocr-geocode'`, `evidence.source_url: 'stash-media:<file_path>'`, the
  phone and website written in the text, and the map in `place.map`. **The photo stays the
  save's picture**: the location section shows the map itself (an object, 520 px wide at most)
  above the rows; `open in google maps` and Directions use Google Maps. Without
  `MAPBOX_ACCESS_TOKEN` the step records what it would have looked up and keeps nothing. The
  section now renders for any save that has the lane (`readPlace`), not only links; the kind
  label stays `photo` / `screenshot`. Migration `20261010190000` widens `set_item_place`
  (applied). iOS: same section on an image's detail sheet, map from `place.map.file_path`.
- **Later:** a live map on the panel stage; nothing from Yelp/Google beyond the page.

## 2026-10-10 · One capture pipeline: the web composer saves through the platform API

Will: "all consumers of our enrichment APIs should get the exact, high quality outcome,
regardless of where the call is being made from. no browser-based shortcuts." Found while
comparing a TikTok shared from the iOS share sheet (caption only, no transcript, "complete" 30 ms
after insert) with the same link pasted into the web composer (transcript + summary).

- **Contract (all platforms):** `add-note` / `add-url` / `add-file` are THE write path. The web
  composer now calls them too (`src/utils/captureClient.ts`, via `useItemOperations`) and
  inserts nothing itself; the browser orchestrates no enrichment. A save carries only what the
  person supplied: their words (`content`, plain or Novel JSON), the address or the uploaded
  file, `is_public`, and the structured facts known at capture (`attributes.location`,
  `attributes.link.flavor`, `attributes.media.duration_s` / `file_name`). Everything else —
  title, description, preview, scrape, transcript, summary, embeddings — lands behind the
  endpoint, identically for iOS (`capture`), the extension, macOS and the web.
- **`add-url`:** the TikTok shortcut is gone. A resolved TikTok (oEmbed caption, creator,
  stored thumbnail, `link.canonical_url`) skips only the deep metadata pass; the scrape runs for
  it like for every link (SearchApi transcript → `page_body`, `summary`, `evidence.transcript`).
  A TikTok with nothing to transcribe stays `complete` (its caption is its content). The scrape
  call carries `caption`, and `scrape-page-content` keeps it as the `description` once the
  transcript takes `page_body` (the oEmbed line "TikTok by X (@x)" now counts as a placeholder
  description, like "Video by X on TikTok" did). The quick fetch is bounded (8 s page / proxy,
  12 s image) since every client — the web now included — waits on the response.
- **`add-note`:** `content` may be a Novel/TipTap JSON document; the fallback title (first line,
  ≤60 chars — was the first 47 characters of the raw content), the AI title/description and
  the embeddings are built from its plain text (`_shared/notes.ts` `plainNotes` /
  `noteTitleFrom`, mirrors the web's `plainTitleFromContent`).
- **`add-file`:** audio/video now stay `attributes.enrichment.status = 'pending'` until the
  transcript lands; a row trigger (`items_settle_media_enrichment`, migration
  `20261010170000`) settles it from `attributes.media.transcript.status` (`done` → `complete`,
  `failed` → `partial`), whichever writer sets it (the job, its sweep, a rebuild). Cards
  therefore say "transcribing" honestly instead of "all done" with an empty transcript. The
  caller's `attributes.media.file_name` wins over the storage object name; the web's staged
  names (`<timestamp>-<random>.ext`) count as storage names (`isStorageTimestampName`).
- **Web composer:** no chip-time server analysis any more (`analyze-image`, inline
  `transcribe-audio` previews and `quick-pdf-summary` are no longer called before a save; the
  pipeline does each once, after). Chips show the file's own facts (name, size, pages, duration,
  the PDF's own title, a thumbnail). The card's skeleton holds the place until the endpoint
  answers (~1 s; TikTok/YouTube via oEmbed), then the row prints in and reads "gathering more
  info" until enrichment settles. The web now honours the server-side entitlement gate like
  every other client (lapsed subscriptions get the endpoint's `message` in the toast; accounts
  with no subscription still pass).
- **Removed:** `src/utils/contentProcessor.ts`, `pdfProcessor.ts`, `mediaProcessor.ts`,
  `enrichment.ts` (client-side inserts, PDF/office orchestration, collection attachments).
  Legacy `type='collection'` rows still render; none can be created.
- **Not redeployed:** `transcribe-audio` — the deployed v37 carries diarization/rebuild work
  that is not on main; settling moved into the trigger so no function change was needed.
- **iOS/macOS:** nothing to change. Share-sheet TikToks now get transcripts; voice memos' cards
  settle with the transcript.

## 2026-10-10 · Object-specific enrichment data and proposed interactions (beta)

- **Validation follow-up:** live canaries exposed model-rewritten quotations.
  The model now selects server-owned passage IDs; the server supplies quotations.
  Whitespace-only differences resolve to original spans, while paraphrases and
  incorrect attribution remain rejected. Unused quotations cannot invalidate
  otherwise supported facts. Failure diagnostics contain codes, not private text.
- **Contract:** new `attributes.object_intelligence` v1 separates model
  interpretation (recipe/travel/product/place/paper/book/event/general), quoted
  source facts, and a closed catalog of proposed interactions. This is additive;
  storage `type`, existing `object_facts`, card layout and detail panel remain
  compatible. See `docs/PLATFORM_API.md` and `_shared/objectIntelligence.ts`.
- **Evidence:** recipe ingredients/steps, travel places/stays, product attributes,
  and other typed fields require exact source quotations. Prices require validated
  publisher facts. Unknown details remain absent. Visual descriptions and generated
  summaries are not used as raw evidence. Stays/packing lists/price comparisons
  that require further work are proposals, not completed research.
- **Interaction contract:** `capabilities` includes readiness, prerequisites and
  draft/read/write effect. Grocery orders and calendar writes require confirmation.
  This supplies future web interactions/canvas nodes; it does not yet add buttons,
  execute integrations, or create derivative items.
- **Capture:** explicit TikTok and social-provider creators now survive as
  `enrichment.evidence.author` and `creator: {name?,handle?,url?,platform}`. Missing
  identities stay absent; the existing metadata request supplies these fields.
- **Hosted processing:** a service-only queue runs every five minutes with capped
  model calls and bounded retries, including for already-complete cards. It writes
  with source/concurrency checks and records `object-intelligence-v1` attempts in
  the enrichment dashboard. Latest 100 items seed the initial cohort; new source
  captures and revisions enqueue automatically. No client or local Codex process
  needs to remain open.

## 2026-10-10 · TikTok share links play: `link.canonical_url` / `enrichment.evidence.canonical_url`

Will: "tiktoks which are stashed are showing the static image in the detail panel again, as
opposed to the embedded video. what changed?" Nothing in the embed — the saved address did.
TikToks shared from the app arrive as `tiktok.com/t/<code>/` (or `vm.`/`vt.tiktok.com/…`),
which carry no video id, so `embedFor` had nothing to frame; only links saved from the web
(`/@user/video/<id>`) embedded.

- **Contract (all platforms):** `add-url` already resolved TikTok links through oEmbed for the
  card; it now also keeps the resolved address as **`attributes.link.canonical_url`**
  (`https://www.tiktok.com/@user/video/<id>`) when the saved `url` is a short link. Web saves
  don't pass through add-url (the composer inserts the row itself), so `scrape-page-content`
  resolves a short link too and records it as **`attributes.enrichment.evidence.canonical_url`**
  (enrichment can only add evidence; the maintenance loop's TikTok adapter already writes that
  key). The saved `url` is never rewritten. Clients frame the video from
  `link.canonical_url ?? enrichment.evidence.canonical_url ?? url` (`utils/embeds.ts`
  `embedSourceFor(item)`); iOS does the same. Existing short-link saves (49 of 51; two videos
  are gone) were backfilled into `link.canonical_url` (redirect → video id → oEmbed for the handle).
- The transcript path is unaffected: SearchApi accepts the short link as is.

## 2026-10-10 · TikTok and Reel transcripts at save time; the full-screen cell goes; the share tooltip no longer opens with the panel

Will: "there is a tiktok transcript api we may be able to leverage … TIKTOK_SCRAPE_API_KEY …
searchapi.io … for instagram reels, let's use transcriptfetch.com … REELS_SCRAPE_API_KEY";
"get rid of the full screen button on the detail screen"; the `share` tooltip "appears to the
left of the panel" when it opens; "notify the enrichment agent".

- **Transcripts (server; every client reads the same contract as the YouTube entry below):**
  `scrape-page-content` now captures a TikTok's transcript through SearchApi's
  `tiktok_transcripts` engine (long and short links) and an Instagram Reel's / video post's
  through TranscriptFetch (inline for Reels; a 202 for long media is not awaited at save time).
  `page_body` = the transcript, `summary` recording-style, `evidence { transcript: true,
  transcript_source: 'searchapi-tiktok' | 'transcriptfetch-instagram', language, duration_s? }`;
  a Reel's caption becomes the description when the saved one was a placeholder. Without a
  transcript the save behaves as before. Verified live on both. Handoff for the enrichment
  pipeline: `docs/hosted-intelligence-transcripts-2026-10-10.md`.
- **Web:** the stages keep only **full size** (the browser-fullscreen cell is gone; players
  carry their own). Opening the panel now focuses the sheet itself rather than its first cell,
  so the share cell's tooltip no longer opens — and gets placed mid-slide — on open.
- iOS: full screen stays the platform's own presentation (plan 17, Task 4); nothing else changes.
## 2026-10-10 · Admin enrichment review and proposal triage

- `/admin/enrichment`, linked from Members, shows all-account completeness for
  saves in the last 24 hours or seven days: assessed/unassessed denominators,
  New York save cohorts, sources, object types, strategy outcomes and recorded
  latency/cost. These are current recorded states, not factual-accuracy rates or
  historical snapshots. Up to 30 incomplete saves expose five recent attempts.
- The hosted review queue now projects validated proposals into
  `hosted_quality_proposals`. Existing retained results are backfilled; future
  completed results enter atomically. Each occurrence retains its original
  job and source links; similar suggestions are not automatically merged.
- Admins can record `new`, `needs_evidence`, `planned` or `dismissed` plus a
  required note. Decisions append a reviewer/revision history. Conflicts require
  refresh, and unchanged transport retries use the same idempotency key.
  Triage does not change saves, run experiments or deploy a strategy.
- `admin-stats` accepts `enrichment` and `review_proposal` actions. Both require
  the authenticated caller's current `admin_users` membership at the endpoint
  and SQL boundaries. Actors cannot be supplied by a client. Details are never
  exposed to ordinary members. Native clients need no change.
- Proposals and review notes follow the source audit's 35-day lifetime and
  cascade on source deletion. The dashboard displays the three latest notes;
  all retained notes remain in the database. Email stays after 09:00 New York;
  provider acceptance is displayed separately from inbox delivery.

## 2026-10-10 · The panel plays the media: embeds, a PDF reader, a transcript tab, full size / full screen, timestamped notes

Will: "move from static images on the details panel to an embedded, playable version of the
media. for youtube videos, embed the video … for tiktoks, attempt to embed the tiktok rather than
a screenshot. for papers/docs, insert a PDF reader and load the PDF itself. for PPTX or HTML slides,
allow the user to step through the slides. if an embedded version of the item is not available, use
an image"; "for videos, youtube, audio, tiktok, reels, include a new tab (beside summary and
original content) … which includes a transcript of the media"; "media items in the detail panel
should be able to be made full browser height/width, or full screen"; "let's start to explore
controls that will allow for [annotation]". Decisions: Office files through Microsoft's viewer;
the transcript tab now, the link-transcript pipeline revived (Firecrawl, spec 2026-09-05);
timestamped notes on media first; HTML slides = both web decks and uploaded `.html`.

**Contracts (all platforms):**
- **Embeds** (`src/utils/embeds.ts` `embedFor(url)`): a link plays in place of its picture when
  its URL is one of — YouTube (`watch?v=`, `youtu.be/`, `/shorts/` → `youtube-nocookie.com/embed/<id>`),
  Vimeo (`player.vimeo.com/video/<id>`), Loom (`/share/<id>` → `/embed/<id>`), TikTok (only the
  long form `/@user/video/<id>` → `tiktok.com/embed/v2/<id>`; `vm.tiktok.com` and `/t/` short links
  carry no id and keep the picture), Instagram (`/reel|/reels|/p|/tv/<code>` → `instagram.com/<kind>/<code>/embed/`),
  Google Slides (`/presentation/d/<id>/embed`), Figma (`figma.com/embed?url=`). Anything else
  keeps the picture. Phone-shaped players (TikTok, Reels, Shorts) sit centred at phone width
  (340 × 604); the rest take the stage's width at 16:9. iOS: port the same table to StashKit and
  load the same addresses in a WKWebView.
- **Documents** (`edit/EditItemDocumentStage` `documentKind(filePath, mime)`): `pdf` → an inline
  reader (pdf.js; one page at a time, previous/next, `page 3 of 12`, ← → keys); `office`
  (`pptx/ppt/docx/doc/xlsx/xls` by mime or extension) → Microsoft's viewer
  `https://view.officeapps.live.com/op/embed.aspx?src=<public file URL>` (it fetches the file from
  our public bucket — a third party sees the document; Will's call); `html` → the file in a frame
  with `sandbox="allow-scripts allow-pointer-lock allow-presentation"` (an opaque origin: no
  cookies, storage, forms, popups or navigation); anything else keeps only download/open. iOS:
  PDFKit for PDFs, the same viewer address for Office files, a WKWebView with a non-persistent
  store for HTML.
- **Transcript tab for video links** (`utils/editPanelTabs.ts`, flavor-aware per spec 2026-09-05):
  a link whose `attributes.link.flavor === 'video'` gets `summary | original content | transcript`;
  once enrichment has captured a transcript into `page_body` it sets
  **`attributes.enrichment.evidence.transcript = true`** (plus `transcript_source`, and
  `duration_s` / `author` when known) and the tab set becomes `summary | transcript` (the
  transcript is the original content). Until then the tab says "No transcript for this video
  yet." Recordings keep their single `transcript` tab. Clients must never invent a transcript
  from `page_body` without the flag (a YouTube page body before this was navigation chrome).
  **Pipeline (server, 2026-10-10):** `scrape-page-content` → `_shared/pageExtraction` now calls
  Firecrawl **v2** and, for a YouTube watch/live/youtu.be URL, parses the transcript out of the
  markdown (`_shared/youtubeTranscript.ts`): `page_body` = caption lines (≤ 200k chars),
  `summary` = a recording-style summary (`kind: 'video'`), `description` = the video's own first
  paragraph when the saved one was synthetic ("Watch … on YouTube"); no transcript (Shorts,
  captions off, Firecrawl down) → nothing is written and the cascade is **never** run for
  YouTube. TikTok/Instagram transcripts come from the maintenance loop's Supadata adapter
  (`_shared/socialEnrichment.ts`) once `SUPADATA_API_KEY` is set and repairs are enabled — the
  same flag.
- **Timestamped notes** (`utils/timestamps.ts`): a note may carry `[m:ss]` or `[h:mm:ss]` markers
  as **plain text** in `content`. Players make them live: a marker is a seek point into the
  save's media, and while a player reports its position the notes head offers `+ note at 1:42`,
  which appends `[1:42] ` to the note (a new paragraph when the note has text; the empty note's
  first line otherwise) and focuses it. Web: `editor/TimestampLinks` decorates markers
  (`.stash-timestamp`, `data-seconds`) and dispatches `stash:seek`; `edit/MediaClock` carries the
  clock between the player and the notes; native `<audio>`/`<video>` and the YouTube player
  (iframe API over postMessage) report time and seek; Vimeo/TikTok/Instagram don't (no control
  shown). iOS: render markers tappable in the notes, seek `AVPlayer`/the YouTube web player, and
  offer the same `+ note at` while playing.

**Behaviour (web):**
- **Stages** (`edit/StageFull`): every media stage — picture, video, embed, document — has two
  hover cells top-right: **full size** (the item panel goes as wide as the browser and the stage
  fills it, with an ink bar naming it and a minimize cell; Esc returns, caught before the sheet
  can close) and **full screen** (the browser's fullscreen API on the stage). The media element
  is never remounted: a playing video keeps playing. On the shared page the stage fills the
  viewport instead of a sheet. The picture's replace/remove cells moved to its bottom-right.
- The shared page (`/s/<token>`) shows the same embeds and document reader, read-only.
- Not done: TikTok/Instagram short links (no id in the URL — resolving them is server work);
  reveal.js/other HTML decks on the web (framing can't be verified from the browser; needs a
  server probe of `X-Frame-Options`/`frame-ancestors`); transcripts for links (pipeline above).
- Tests: `utils/embeds.test.ts`, `utils/timestamps.test.ts`, `utils/editPanelTabs.video.test.ts`,
  `edit/StageFull.test.tsx`, `edit/EditItemDocumentStage.test.tsx`, `editor/TimestampLinks.test.ts`,
  `EditItemContentSection.test.tsx` (transcript tab, `+ note at`).
- Design: DESIGN-v2 §10 (strings), §12.8 (stages, transcript tab, timestamped notes). The
  annotation exploration: `docs/superpowers/specs/2026-10-10-panel-annotation-exploration.md`.
  iOS: `docs/superpowers/plans/2026-10-10-ios-plan-17-embedded-media-transcripts-annotations.md`.
## 2026-10-10 · Beta product and place details from publisher data

- `attributes.object_facts` is a version-1 additive product/place envelope, defined
  in `supabase/functions/_shared/objectFacts.ts`. It includes JSON-LD source URL,
  observation time and extraction version; preserve all unknown attribute keys.
- New link captures store supported facts server-side. The web detail panel displays
  a beta Product details / Place details section with source and observation date.
  Price at capture is historical publisher data, not a fresh retailer quote.
- Compare retailers / Find similar open external searches (including known variant
  terms). Open map uses extracted coordinates/address. No order, calendar event or
  price comparison executes silently. Native clients can mirror these actions.
- `set_item_object_facts(target_id, expected_url, expected_facts, facts)` returns a
  boolean; false means source/ownership/field-lock/concurrency validation failed.
  It updates only the facts leaf, preserves capture location and user attributes,
  and queues indexing. Never use the place address as the user's capture location.
- Invalid, unknown-version or URL-mismatched facts are hidden. Unresolved variant
  prices, multiple ambiguous objects and historical archive prices are omitted.
- Native binaries are not released by this web/backend change. Existing saves are
  not bulk backfilled; facts appear on newly enriched supported links.

## 2026-10-09 · Share links unfurl with the save's title, description and picture

Will: "update our opengraph card info for items which are shared from the details panel to
include the title of the stashed item and a brief description" (like a TypeSafe AI blog unfurl).

- **How it works (web/Vercel only; nothing for iOS to mirror):** crawlers never run the app, so
  `vercel.json` rewrites `/s/:token` to the Vercel function `api/share.ts` **when the
  user-agent looks like a link unfurler** (Slackbot, facebookexternalhit/iMessage, Twitterbot,
  Discordbot, WhatsApp, Telegram, LinkedIn, Teams, Mastodon, Bluesky, Signal, anything with
  "bot"/"crawler"/"preview"…). The function reads the save through the same `shared_item(token)`
  RPC with the anon key, fetches the app shell (`/app.html`) from the CDN, swaps the site's
  `<title>`, `description`, `og:*` and `twitter:*` tags for the save's, and answers it. People
  keep getting the shell straight from the CDN; the app renders the page as before.
- **The card:** `og:title` = the save's title (120 chars max; "A save on Stash" without one);
  `og:description` = its description, else the summary's first sentence, else "Saved with Stash,
  with the thought that made it worth keeping." (200 chars max, cut at a word); `og:image` = the
  save's picture (an image, or a link's stored cover; a rescued `http…` preview as is) with
  `twitter:card=summary_large_image`, else `/og-v2.jpg` (1200×630) as a `summary` card;
  `og:url` the share link, `og:site_name` Stash, `og:type` article, `robots: noindex`.
- **Dead or malformed token → 404** with no card, so a revoked link unfurls nothing. Cached at
  the edge for 2 minutes (a revoke can take that long to stop unfurling).
- Tests: `api/share.test.ts` (card, head, shell rewrite, handler). The function is typechecked on
  its own (`tsc` over `api/share.ts`), not by `npm run build`.

## 2026-10-09 · The kind tag carries "gathering more info"; a shorter resolve; kind tags hidden until hover; less console noise

Will: "the pixelization effect when adding a new card goes on for a bit longer than it appears
it needs to"; "move the '/ gathering more info' animation to the space currently used for the
item label type while the item is being enriched. after enrichment has completed, quickly cycle
to 'all done!' and swap the message for the item type label using the scramble text effect …
and fade it to opacity 0 after a moment. on all other cards, let's hide the item type label
until the user mouses over the card"; and "suppress non urgent errors like this" (the console
404s after a YouTube save).

**Behaviour (for iOS and macOS to mirror):**
- **The kind tag is the status while reading** (`cards/KindTag`, DESIGN-v2 §12.4): on a card
  with a hero, the black tag top-left reads `| gathering more info…` (or `| reading the
  picture…` / `| transcribing…` / `| reading the pdf…`) in place of the kind while the save is
  being read. When the reading ends: `✓ all done!` for 0.9 s → the kind **decrypts in** (the
  scramble, §8) → holds 1.4 s → fades to opacity 0 over 300 ms. If Stash gave up: `some info
  unavailable` for 1.8 s, then the kind the same way. A card born already finished plays nothing.
  Cards without a hero (notes) keep the status line under the title as before.
- **Kind tags are hidden at rest**: every card's kind tag is opacity 0 until the card is hovered
  or focused (`group-hover` / `group-focus-within`); on screens with no hover (`@media
  (hover: none)`) it is always shown. iOS: show the kind on long-press/hover-equivalent, or keep
  it visible — a touch screen never hides it on the web either.
- **The resolve is bounded** (`READING_BOUND_MS` = 2.6 s in `machine/resolve.ts`): a picture
  holds at 12 px blocks under the lens for at most 2.6 s after it has loaded, then sharpens even
  if enrichment is still running; a boiling placeholder/waveform/page settles after 2.6 s of
  reading the same way. The tag keeps saying Stash is reading until it is done. Before, the hero
  stayed pixelated for the whole enrichment (15–20 s for a link).
- **Console noise:** the composer no longer fetches a YouTube thumbnail for every keystroke of a
  partial video id — `utils/youtube.ts` `getYouTubeVideoId` answers only for a complete
  11-character id (shared by the composer chip and the save path). The panel's favicon lookup
  remembers domains the favicon service 404'd, once per session. (Resource 404s are logged by the
  browser itself; the only way to quiet them is not to make the request.)
- Tests: `cards/KindTag.test.tsx`, `machine/resolveHooks.test.tsx` (the bound), `utils/youtube.test.ts`.
## 2026-10-09 · Contact, terms and privacy are pages of the site

- **Contracts:** `gostash.it/contact` is new; `/terms` and `/privacy` are now static files
  (`public/<page>/index.html`, written by `npm run publish:site` from the homepage prototype),
  which the server answers with before the app's catch-all. The app's `/privacy`, `/terms` and
  `/contact` routes only reload into them (`src/pages/SitePage.tsx`, like `/`). Link to them with
  a **full navigation** (`<a href="/privacy">`), not a router `Link`. The React legal pages
  (`LegalPage.tsx`, `Privacy.tsx`, `Terms.tsx`) are gone; the legal text has one source now.
- **Text:** the policy and terms are unchanged, word for word. Their "last updated" dates stand.
- **Other platforms:** in-app legal or support links open `https://www.gostash.it/privacy`,
  `/terms` or `/contact`. iOS Settings already links privacy and terms; nothing to change.
- **Open:** the Terms promise a 14-day free trial, and the product gives one
  (`create-checkout` sets `trial_period_days: 14`), while the homepage says "$4.99 a month" and
  nothing about a trial. Will decides which changes.

## 2026-10-09 · Hosted quality reviews expand beyond the pilot

- Stash infrastructure rotates one account per hourly audit and chooses up to
  three links with preference for items least recently reviewed. Contexts do not
  mix accounts. Existing capture/enrichment behavior stays behind the platform API.
- Daily live investigations can escalate from Firecrawl to Jina, plus public
  Medium artwork for an exact article identity, within one bounded collection.
  Source identity, source access limits and each attempted strategy are recorded.
- The daily email now separates all-user save/quality counts from sampled Hermes
  findings. It includes source and strategy breakdowns, unknown telemetry, and
  reviewable playbook proposals. Other accounts' URLs, source quotes and model
  free text are withheld from email; aggregate categories remain visible.
- Schedule: after 09:00 America/New_York, covering the prior local calendar day.
  Runtime remains the hosted Fly Sprite and Supabase cron; no local Codex job.
- No automatic playbook/code deployment, image-pixel verification, taste graph,
  or new client facts/action UI is introduced by this infrastructure release.

## 2026-10-09 · YouTube share-sheet routing and profile/article previews

- A complete HTTP(S) URL delivered as plain text is a link capture. iOS promotes
  it before URL-first ordering and before either foreground or background outbox
  serialization. The capture endpoint performs the same normalization for older
  clients, keeping the capture receipt and original URL parameters. Text with
  prose or multiple links stays a note; typed annotations stay in `content`.
- Direct `add-note` calls containing only a URL keep literal metadata rather than
  asking a model to invent the unseen page/video's title or description.
- Preview selection recognizes the page's own Person/ProfilePage schema. A later
  LinkedIn source capture can fill a missing, unprotected portrait with an owned
  storage image; it cannot overwrite an existing or user-protected preview.
- Medium byline portraits are excluded from article-cover candidates. Public
  author-feed artwork is accepted only for the exact saved article identity.
- Web LinkedIn `/in/` placeholders use a local pixel silhouette and the completed
  state text `profile preview unavailable`. Other missing-link/video glyphs remain
  unchanged. iOS's capture changes require a binary release; the server routing
  protection benefits installed versions immediately after backend deployment.

## 2026-10-09 · Live enrichment evidence and product image selection

- The hosted daily investigation now records a public rendered source, retrieval
  outcomes, and candidate images before Hermes produces proposals. Citations are
  checked against the recorded source and remain separate from older captures.
- Metadata image selection prefers the saved product and selected colour and
  rejects navigation campaigns, including the Peter Millar jacket regression.
- Existing saved items are not rewritten by the investigation. No client UI or
  image-pixel verification is added in this slice.

## 2026-10-09 · Hosted enrichment quality pilot

- New infrastructure-only `quality-worker`, `quality-dispatch`, and `quality-model`
  endpoints support leased, read-only source audits on a dedicated Fly Sprite.
  New service-only tables retain jobs, findings, and an idempotent daily email
  outbox. Pilot accounts are explicitly scoped; deployment starts disabled.
- Capture responses and item fields are unchanged. Findings do not overwrite
  items or user edits. The existing enrichment repair queue remains the writer.
- No new client UI is required. Future beta facts, suggested views and actions
  are described in `docs/hosted-intelligence-roadmap.md`; those are proposals,
  not newly available product features.
- Accuracy findings describe the sampled source snapshot. Text audits cannot
  certify live pages, image identity, or a population-wide enrichment error rate.


## 2026-10-09 · Public contact address is hello@gostash.it

- **Contract:** every public contact now points at **hello@gostash.it** (Will). Any surface
  that gains a support, contact or feedback link (iOS Settings, the extension's sign-in page,
  App Store or Web Store listings) uses this address, not a personal one.
- **Where it changed on the web:** the site footer's Contact and the iPhone beta "Email us"
  line (both come from `scripts/publish-site.mjs` / the prototype's `js/site.js`, re-published
  into `public/`), the legal pages' "Questions? Email …" (`src/pages/LegalPage.tsx`) and the old
  landing page (`src/pages/Landing.tsx`). Test fixtures and the admin seed keep the real
  account email: those are identities, not contact details.
- **Mail:** gostash.it's MX is Google Workspace; the hello@ mailbox or alias has to exist there.

## 2026-10-09 · A save no longer reports "Failed to add content" when its index rebuild loses to enrichment

Will saved a YouTube link from the web and got "Failed to add content: Edge Function returned a
non-2xx status code", although the card was there and the save was fully indexed 19 s later.

- **What happened:** after inserting, the web client asks `generate-embeddings` to index the new
  row right away. The function rebuilds the index with a compare-and-swap (`replace_item_embeddings`
  with the row's snapshot); server enrichment was writing the same row at that moment, so the swap
  failed and the function answered **`409 {"success":false,"reason":"item_changed"}`** — by
  design, since whoever changed the row re-indexes it (the enrichment did: 19 chunks). The web
  treated the 409 as the add failing. The same 409 showed up as console noise after quick title /
  summary edits (the items trigger reassesses the row).
- **Contract, for every client:** `item_changed` from `generate-embeddings` is **deferred, not
  failed** — do nothing, the row's changer re-indexes. **The function now answers `200` with the
  outcome in the body** (`{"success":false,"chunksProcessed":0,"reason":"item_changed"}`) instead
  of `409`, because browsers log every non-2xx resource in red and this one raced on most link
  saves. iOS's `EmbeddingRefresher` mapped the 409 to `.itemChanged` (benign); with a 200 it
  simply succeeds, which is the same outcome. The web's `generateEmbeddings` resolves
  `{ deferred: true }` for that body (and still for a 409 from an older deployment) and only
  throws on other statuses.
- **Web behaviour:** indexing right after an insert is best effort: a real failure there is logged
  and the save still succeeds (the server re-indexes as enrichment lands). The Chrome extension
  saves through the platform API and never calls the function.
- Tests: `utils/aiOperations.test.ts` (409 → deferred, 500 → throws), `utils/contentProcessor.test.ts`.

## 2026-10-09 · Share a save by link; the address leads the panel; a cancel cell while editing it; "Resurface in"

Will: "move the address for the object above the title"; "add an X button to exit edit mode if the
user decides to edit the URL"; "add a share button to the upper right of the detail screen. this
should create a unique URL (if we can limit the length somehow, great). it will bring whomever
clicks on the link to a read only view of everything on the detail screen. stash logo in the upper
left, standard 12 column grid width (centered), the same background we use for the main grid"; on
cards, "change 'remind me' to 'resurface in'". Decisions: the page shows **everything on the panel**
(notes and details included); the link is **unlisted and separate from the public feed**; the page
carries the logo, `from @username’s stash`, and Get Stash.

**Data contract (all platforms):**
- `items.share_token text null` (unique partial index `items_share_token_key`) and
  `items.shared_at timestamptz null` — migration `supabase/migrations/20261009123000_items_share_token.sql`,
  applied to prod. The token is **10 characters of base62** (`[A-Za-z0-9]{10}`, ~59 bits), minted
  **by the client** (`src/utils/shareToken.ts` `mintShareToken`, rejection-sampled from
  `crypto.getRandomValues`) and written through the normal owner update (`share_token`,
  `shared_at = now()`). **Stop sharing** writes both back to null. A shared item keeps its token: the
  client never re-mints while one exists. iOS: mint the same shape, write the same two columns through
  the same update; on a unique violation (astronomically unlikely) mint again.
- The link is `https://www.gostash.it/s/<token>` (`shareUrlFor`).
- Reading: **`public.shared_item(p_token text)`**, SECURITY DEFINER, executable by `anon` and
  `authenticated`; returns at most one row: `id, type (text), title, description, url, file_path,
  mime_type, file_size, summary, page_body, content, attributes, created_at, shared_at, username,
  display_name` (the owner's `user_profiles`). It never returns pins, reminders, `is_public`, the
  sticky note or the user id, and nothing can list tokens. Media comes from the public `stash-media`
  bucket (`file_path` → public URL; an `http…` file_path is already a URL). RLS is unchanged.
- `share_token` is in the web list projection (`ITEM_LIST_COLUMN_NAMES`) and the admin grid columns.

**Behaviour (for iOS and macOS to mirror):**
- **Panel: the address leads.** For links the source address strip is the first thing in the panel
  body, above the title (then title, description, media, source tabs, notes, details, sharing).
- **Address strip, editing:** a red **×** cell (`aria-label` "Cancel editing", tooltip `cancel`)
  appears to the left of the spot ✓ while editing; it leaves edit mode and keeps the old address
  (Esc still does the same).
- **Share cell** in the panel's window bar, top-right beside close (`edit/ShareControl`): tooltip
  `share`. **One click mints the link, stores it, copies it, and opens the share window** — an ink
  bar `share`, the status `✓ link copied · anyone with it can view` (then `anyone with the link can
  view`), the address in the code voice with a copy cell (`copy link` / `copied`), the line
  `not on your feed · read only`, and **Stop sharing** (error red). Once shared the cell wears the
  spot colour (tooltip `shared · anyone with the link`) and a click only opens the window. Stop
  sharing clears the token; the old link then shows the dead-link page. A failed write says
  `✕ couldn't update the link. try again` in the window.
- **The shared page** `/s/<token>` (`src/pages/SharedItem.tsx`; DESIGN-v2 §12.15), on the library's
  paper: a 68 px header with the logo (to gostash.it), `from @username’s stash` in the machine voice,
  and **Get Stash** at the right; the object centred on the marketing 12-column grid (max 1360 px,
  columns 3–10 from `lg`, full width below): the same window bar, the address strip (copy and open
  only), the title, description, media (audio/video player, picture stage, document preview), the
  source tabs (`summary | original content`, or `transcript`), the notes as read-only rich text when
  there are any, and the details facts. A note shows its text as the object. Nothing is editable;
  no comments. A dead or malformed token gets "This link no longer works." with Get Stash. The
  document title becomes `<title> · Stash`. Link previews (OG tags for iMessage/Slack) need a
  server-rendered head — not done; follow-up.
- **Cards:** the menu reads **`Resurface in…`** ▸ `1 day · 3 days · 5 days` and **`Don't resurface`**
  (was `Remind me…` / `Change reminder…` / `Remove reminder`). The data (`remind_at`) and the
  card's clock chip are unchanged.
- Tests: `edit/ShareControl.test.tsx`, `pages/SharedItem.test.tsx`, `utils/shareToken.test.ts`,
  `EditItemLinkSection.test.tsx` (cancel cell), `ContentItemFooter.menu.test.tsx`,
  `utils/designScope.test.ts` (`/s/` is on DESIGN-v2).

## 2026-10-09 · Cards: pin, share, delete from the menu; the panel: source first, the summary editable, notes one line

Will: on the card menu, "remove 'report a problem'", "re-introduce 'delete this' with a confirmation
dialog styled like the app", "add 'pin this'", "when anything is pinned show two tabs above the grid
'all | pinned'", "add 'share to feed' toggle (unshare too)"; in the detail view, "move 'source' above
'notes'", "move the 'summary | original content' tabs to the left with no 'source' label, a full-size
icon on the right"; notes as "one line of normal text, hover light grey, click to edit with the bright
green border", hide "type / for formatting" until focused; the summary "editable like title/description"
and stored; "original content not editable"; and "make opening the detail panel snappier". Decisions:
the full-size icon opens **the active tab** full screen; `all` keeps the normal order (pins don't float).

**Data contract (all platforms):**
- `items.pinned_at timestamptz null` (migration `supabase/migrations/20261009090000_items_pinned_at.sql`,
  applied to prod; partial index `items_pinned_idx (user_id, pinned_at desc) where pinned_at is not
  null`). **Pin** = set it to now; **unpin** = null. It's in the web list projection
  (`ITEM_LIST_COLUMN_NAMES`) and the admin grid's columns. Pins are the owner's: never rendered on a
  public feed, never sent to a visitor.
- **Share / unshare from the card** writes `is_public`; **un-sharing also clears `supplemental_note`**
  (the sticky note), the rule the panel's sharing switch already followed. No new columns.
- **Delete** uses the existing delete path (`onDeleteItem(id)`), only after the confirmation.
- **The summary is now a person-editable field:** the panel saves `items.summary` through the same
  save path as the title (`saveItem`; a trimmed-empty summary stores `null`); `summary` is one of
  the text fields whose change re-indexes the item (`textFieldsChanged` → `generate-embeddings`), so
  Ask and MCP see the edit. Original content (`page_body`) and transcripts stay read-only.
- **Notes stay empty until a person writes:** opening the notes field and leaving it writes nothing.
  Before, the editor's blur safety-save wrote its empty document
  (`{"type":"doc","content":[{"type":"paragraph"}]}`) over an empty `content`; now an empty editor
  over an empty note is a no-op, and a stored empty document counts as no note
  (`src/utils/noteContent.ts` `noteIsEmpty`: null, whitespace, the empty doc, `<p></p>`). Clearing a
  note that had text still saves (that's an edit). iOS: treat the same four shapes as "no note".

**Behaviour (for iOS and macOS to mirror):**
- **Card menu** (owner, `ContentItemFooter`): `Pin this` / `Unpin` · `Share to feed` / `Unshare from
  feed` · `Remind me…` ▸ (`Change reminder…` once set) and `Remove reminder` · a rule · `Delete
  this` in error red. **"Report a problem" and its feedback dialog are gone.** `Delete this` opens an
  app dialog: title "Delete this item?", body "“{title}” and everything Stash knows about it will be
  removed. This can't be undone." (`Untitled` when there's no title), buttons Cancel and a red
  **Delete**; Cancel keeps the item. A visitor to a public feed gets only **Comments**.
- **Card:** a pinned item wears a black `pinned` state tag top-right (with `public` / `due`).
- **Library toolbar** (`LibraryToolbar`): with no pins, `59 saves` as before. Once anything is pinned,
  a tablist (`aria-label` "Library view") with `all · 59` and `pinned · 3` (the open tab inverts to
  ink), the reading count beside it. `all` is the normal order; `pinned` lists pins newest-pinned
  first (`pinned_at desc`). The view falls back to `all` when the last pin goes.
- **Panel order** (`EditItemContentSection`): the **source** section comes first, then **notes**,
  then details and sharing. The source section has **no label**: its tabs row sits on the left of
  the rule (`summary | original content` for links and documents; `transcript` for audio and video),
  and a 24 px **full-size** cell (`aria-label` "View full size") sits on the right. Full size opens
  **the active tab** over the panel (`edit/MaximizedSource`): the same window chrome as the notes'
  maximize (an ink bar naming the tab, a Minimize button), the text in a reading column; **Esc or
  Minimize returns** to the panel (Esc is stopped before the sheet hears it).
- **Summary** (links and documents): rest plain, fill on hover, click → an auto-growing field with the
  ink edge and spot ring (the title's treatment); **leaving it saves** when the text changed
  (`saving the summary…`, then the text; on failure `couldn't save the summary. try again` and the
  old text); **Esc abandons** the edit and does not close the panel (nor a full-size view). Without a
  save handler (public views) it's plain text.
- **Notes:** empty notes are **one line of body text**, "Add a note…" (muted; fill on hover). A click
  mounts the editor **focused**, inline (no box of its own), inside the field treatment (white, ink
  edge, spot ring while focused); `type / for formatting` shows only while it's focused. Leaving an
  empty editor collapses it back to the line (and writes nothing, above). Existing notes show the
  editor at once, plain, taking the ring on focus. The maximize cell stays on the notes rule.
- **Snappier panel:** the sheet now slides in over **200 ms** and out over **150 ms** on `--ease`
  (`ui/sheet.tsx`, v2 only; was 500 / 300). Measured on a 60-save library: the panel's content is in
  the DOM ~80 ms after the tap and the sheet is fully in at ~250 ms (was ~560 ms). Empty notes no
  longer mount the editor on open. (Note for Tailwind 3.4: an arbitrary `duration-[240ms]` under
  the stacked `v2:data-[state=open]:` variant is not generated; use scale values.)
- Tests: `ContentItemFooter.menu.test.tsx`, `ContentItemHeader.pinned.test.tsx`,
  `LibraryToolbar.test.tsx`, `EditItemContentSection.test.tsx`, `editor/EditorContainer.test.tsx`,
  `utils/noteContent.test.ts`. `src/test/setup.ts` now stubs `ResizeObserver` for Radix poppers.
- Design: DESIGN-v2 §8 (panel timing), §10 (strings), §12.3 (menu, `pinned` tag), §12.6 (tabs),
  §12.8 (order, summary, notes, full size).

## 2026-10-08 · The library no longer breaks when Ask docks

Will: "show x sources" and maximizing Ask "cause the right side of the screen to misrender".
Both dock the Ask panel (showing sources docks it so the cards can be seen beside the answer),
and docking drops the library from three columns to two.

- **Root cause (web only):** the masonry counted the grid's columns from the computed track
  list, and Chrome's list includes the implicit columns that stale card placements create. After
  the drop to two columns, cards still carried their third-column placement, so a phantom third
  track existed, the count stayed three, and every third card was placed back into the phantom
  column, which sized itself to the cards' natural width (976 px on a 1,440 px window) and
  squeezed the two real columns to nothing. A page loaded with Ask already docked never showed
  it; only docking (or narrowing) after the grid had laid out did.
- **Fix:** the masonry clears every card's placement before counting, so only the explicit
  columns count, and heights are read at the right widths. Verified at runtime: docking now gives
  two 500 px tracks with cards alternating between them, and un-docking restores three.
- iOS packs its own columns and is unaffected.

## 2026-10-08 · The panel follows the live row; no jump while its picture loads; the address strip edits; the 400s are gone

Will's notes after the launch: the panel's photo "lazy loads and the content jumps"; the address
should be clickable, with copy and edit; JavaScript errors cycling in the console; and the panel
"sometimes loads with temporary content ('untitled', no image, no description)".

**Behaviour (for iOS and macOS to mirror):**
- **The item panel shows the open card's live row.** It used to show a snapshot taken at the tap,
  so a save opened while Stash was still reading it stayed "Untitled" with no picture until it was
  closed and reopened. Now, as enrichment lands, the panel's title and description fill in, and the
  picture and window bar follow, unless the person has already typed in that field, in which case
  their words stay. (Nothing about how cards open had changed; the snapshot was old behaviour that
  the redesign's reading state made more visible.)
- **Realtime re-reads only what changed.** On every enrichment write the library used to refetch
  all of itself (at 841 saves, ~535 KB, several times a minute). It now re-reads the rows the event
  named, in one read per 400 ms burst; a delete drops the row with no read; an event with no row id
  falls back to the full refetch.
- **The console errors:** the grid fetched tags with every item id in the URL. At 841 saves that
  was a 31 KB URL, the gateway answered `400 Bad Request`, and it re-ran on every refetch. The
  fetch now sends no ids (RLS scopes `item_tags` to the person's items) and reads in pages of
  1,000. The test account, at 59 saves, never hit it; the threshold is between 500 and 841 saves.
- **The picture stage is a fixed 448 px** before and after the picture loads, with the mosaic
  until it has; a picture that fails to load takes the stage with it. (No item stores its image's
  size, on any platform; storing width and height at capture would let the stage match the picture
  exactly and is worth adding to the capture contract.)
- **The address strip:** the whole address is a link. Copy (`copy address`, then `copied` for two
  seconds), edit (the strip becomes a field; the cell turns spot and becomes save; Enter saves, Esc
  cancels; `https://` is supplied for a bare host; a non-address is refused), and open. Saving
  writes `items.url`; the quality loop reassesses the save (the items trigger queues it).
- **"Failed to add content"** now says why (`Failed to add content: <reason>`), in both the
  composer's and the operation's toasts. The refero.design save Will reported could not be
  reproduced (on the test account it saved and enriched cleanly in ~95 s, with no failed request),
  and his account holds exactly one refero row from that day, titled and enriched, so the server
  save succeeded. Next time, the toast names the step.

**Tests:** the grid's tag fetch (no ids, paged), the realtime merge and per-row read, the panel's
adoption of landing values, the picture stage, the address strip (link, copy, edit/save/cancel,
refusal, failed save), and the Index's live binding. Checked in the browser on the dev server with
images held back 1.5 s: the stage and everything under it held still while the picture loaded; the
address edit saved and the window bar followed; no console errors.

## 2026-10-07 · Files up to 100 MB, and a PDF that couldn't be read still opens

Will: "let's up the upload limit for files to 100mb". Branch `upload-limit-100mb`.

**Contracts (iOS, macOS, the extension, anything that uploads):**
- **One cap for every file kind: 100 MiB (104,857,600 bytes).** It was 20 MB for images and
  documents and 100 MB for audio/video. Exactly 100 MiB is accepted; one byte more is refused.
- **Storage enforces it.** Supabase Storage's project upload limit went from 50 MiB to 100 MiB
  (live 2026-10-07: dashboard → Storage → Settings, or Management API
  `PATCH /v1/projects/<ref>/config/storage {"fileSizeLimit": 104857600}`). Until then any object
  over 50 MiB failed at Storage, including the audio/video the clients advertised up to 100 MB. A
  bigger upload gets HTTP 400 with `{"statusCode":"413",…,"code":"EntityTooLarge"}`
  (`docs/PLATFORM_API.md` → "Per-file cap"). `supabase/config.toml`'s local-stack limit matches.
- **Web:** `MAX_FILE_SIZE_MB = 100` (`src/services/imageUpload/MediaUploadTypes.ts`); the notes
  editor's inline-image check now uses it too (it was a hardcoded 20). The composer's refusal reads
  `"<name>" is 101.0MB. Maximum file size is 100MB. Please choose a smaller file.`
- **iOS:** `CaptureAttachment.byteLimit(kind:mimeType:)` is 100 MiB for every `.file` (photos still
  have none; they're prepared down). Ships with the next build. The share extension has no size
  pre-check; a share over 100 MiB is refused at Storage during its background upload, as above.
- **Extension:** unchanged. Page images still cap at 20 MB (`MAX_IMAGE_MB`); no release was cut.
- `capture`'s 45 MiB one-shot limit is unchanged: it's a transport threshold (bigger files go
  two-step), not a product cap.

**Saving is not reading.** `extract-pdf-text` hands the PDF to OpenAI, whose file inputs must be
under 50 MB, and `extract-office-text` refuses anything over 40 MiB. A file past those saves (on the
web with its chip-time title and description) but gets no `summary` or `page_body`, and
`attributes.enrichment.status` settles `partial`. The card says "some info unavailable". Very large images can likewise miss
their AI description (`analyze-image` sends OpenAI the original, or a Storage transform, which
refuses sources over 25 MB). All of these are contained: the item is saved and opens.

**Fixed: a PDF whose extraction failed could never be opened.** "No summary" meant "still reading"
forever, so the card's title and hero ignored clicks and the edit sheet closed itself on open. That
was already true of any failed PDF; the new cap would have made it certain for every PDF over 50 MB.
- `isReadingDocument(item, nowMs)` (`src/utils/itemAssembly.ts`) is now: a PDF with no summary,
  whose enrichment is still `pending` (an absent status counts as pending), within 10 minutes of its
  save. The card header and the edit sheet gate on it instead of `isDocumentProcessing`, which stays
  the bare "no summary yet" fact.
- The edit panel's empty Summary / Original Content tabs say "Content is still being extracted from
  this document." only while enrichment is pending, otherwise "We couldn't read the text in this
  document."
- The web's failure toast for a PDF read plain words instead of the client's error message ("PDF
  Processing Failed — Edge Function returned a non-2xx status code"). It now reads: "Couldn't read
  this PDF". "It's saved, and you can still open it." (error colour).
- **iOS:** `Item.isProcessingDocument` (`ItemRules.swift`) mirrors the web rule: no summary,
  `attributes.enrichmentStatus(at:)` pending or absent, and saved under 10 minutes ago. A failed
  document now stops shimmering and is no longer redacted. Not mirrored yet: any detail-view copy for
  a document with no text.

**Verified:**
- **Storage,** probed as the uitest fixture. Before the change, 50 MiB + 1 byte → `EntityTooLarge`.
  After it, 60 MiB → 200, exactly 100 MiB → 200, 100 MiB + 1 → `EntityTooLarge`.
- **The branch's web app against production,** in a browser:
  - A 101 MiB PDF is refused with the new copy.
  - A 30 MB PDF saved and extracted: verbatim `page_body`, a summary, and enrichment `complete`
    in ~20 s.
  - A 60 MB PDF saved, then `extract-pdf-text` answered 500 and enrichment settled `partial` 12 s
    later. The card read "some info unavailable" with a clickable title, and the sheet opened and
    showed "We couldn't read the text in this document."
- The test items and files were deleted.
- **Tests** (on main at 5da73fc0): web 646 in 83 files; StashKit 896. The new header, sheet, panel
  and rule tests each fail on the old code.

**Follow-ups, not done:**
- Reading PDFs over 50 MB needs an extractor that doesn't go through OpenAI's file input.
- `extract-pdf-text` should refuse a PDF of 50 MB or more before downloading it. Today it buffers the
  whole file twice (the worker limit is 256 MB) and deletes its OpenAI upload only on success, so each
  failed PDF leaves a file behind at OpenAI.
- An extraction that runs past the gateway's 150 s gets a 504 and is marked `partial` while the
  function keeps going (up to 400 s on paid plans). In that gap the card opens and says the text
  couldn't be read; the status stays `partial` after the summary lands. This predates the change.
- Cards load the full-size original (there are no thumbnails), so very large images cost bandwidth
  and memory.

## 2026-10-07 · Videos play in place on the card, and as video in the item panel

**Behaviour (for iOS and macOS to mirror):**
- **Card:** an uploaded video plays in place. Play grows the frame to the video's own shape (up to
  420 px tall) and shows the native controls (full screen is theirs). A white square **close**
  button (ink edge, print shadow) sits top-right while it plays; it stops the video, rewinds it and
  brings the poster back, returning focus to Play. The hover-only "Expand video" lightbox is gone
  from cards.
- **Why:** the lightbox was rendered inside the card, and the card's v2 hover lift is a CSS
  transform, which pins a `position: fixed` overlay to the card. With the pointer on the card the
  "full-screen" overlay shrank into the card (438 × 304 instead of 1440 × 900), the pointer left
  the card, the lift dropped, the overlay went full screen again, and so on: the flicker. Its
  white × sat over the grey page.
- **The lightbox itself** (still used by multi-part attachments) now renders into `document.body`,
  has a white square close fixed to the viewport's corner, and closes on Escape.
- **Item panel:** a video item shows the video (on the dotted stage with crop marks, native
  controls, `download original`) instead of the audio player strip. Audio items keep the strip.

**Tests:** the card's player (rest, play in place, close, clicks kept from the card), the panel's
media zone (video vs. audio), and the lightbox (portalled, close, Escape). Checked in the browser on
an uploaded test clip (since deleted): the card played in place with the close visible, no overlay
appeared while the pointer swept on and off the card, and the panel showed the video.

## 2026-10-07 · iOS masonry and motion

- View packs fixed left/right columns independently, preserving newest-first order and chronological VoiceOver navigation.
- Sign-in adopts the web hero’s lime ASCII pool and stipple. Native fluid responds to phone tilt and movement; the form stays still. Motion pauses during typing/inactivity and respects Reduce Motion.
- Ask uses a single rotating cursor throughout thinking and streaming, with accessible status text and no active cursor after completion or failure.
- See [simulator handoff](ios-design-v2-handoff.md) and [motion preview](ios-design-v2/ascii-motion.mp4).

## 2026-10-07 · iOS adopts the v2 web design

- **Contracts:** capture, sign-in, search, chat, detail editing, sharing, and the durable
  queues keep their existing APIs. Cards remain one tap target opening the detail sheet.
  Native keyboard dismissal, 44 pt controls, Dynamic Type, VoiceOver and Reduce Motion remain.
- **Visuals:** paper/white/black with one lime spot; ST4SH wordmark and A/4 symbol/icon;
  near-square objects and square controls; Montreal human text, Departure Mono machine
  labels, JetBrains Mono literal strings. Applies to Add, View, Ask, detail, sign-in,
  settings, onboarding and the share extension. Replaces the purple gradient and type tints.
- **Library:** two columns at normal phone text sizes, one at accessibility sizes; black
  kind tags, ruled metadata, grayscale plates, honest cursor status while enrichment runs.
- **Native adaptation:** the tab bar and modal presentation remain native. Settings keeps
  its existing account/phone/subscription actions in a flat numbered list; no new web-only
  settings or connected-agent flows are introduced by this styling change.
- **Reference:** October 7 `app-redesign-v2` design guide; `DESIGN-v2.md` now contains that
  complete reference. See `ios-design-v2-handoff.md` for build and simulator verification.

## 2026-10-07 · The new homepage is live at gostash.it, and the app moves off "/"

Will: "deploy the new homepage, sign in/up, and web app design." The homepage prototype (v0.6) is now
the live site, published from its source by `scripts/publish-site.mjs` (`DESIGN-v2.md` §12.13).

**Contracts (for iOS, macOS, the extension and anything that links to gostash.it):**
- **`https://www.gostash.it/` is the static marketing site,** not the app. The app's shell is
  `app.html`; `vercel.json` rewrites every route that isn't a file to it, so `/home`, `/auth`,
  `/settings`, `/feed/*`, `/privacy` and the rest are unchanged. Link to `/home` (or `/auth`) when you
  mean the app.
- **New pages:** `/extension` (replaces the old install page: the same zip at
  `/stash-it-extension.zip`, and the same `data-version` / `data-size` stamps for
  `extension/scripts/publish-hosted-zip.sh`), `/connect` (connecting an AI over MCP; `/mcp` is still
  the MCP server itself), `/iphone`.
- **Into the app:** the site's **Sign in** opens `/auth` and both **Get Stash** buttons open
  `/auth?mode=signup`. A signed-in visitor who taps Sign in is passed straight on to `/home`.
- **"/" inside the app** (signing out, the way-in wordmark, an anonymous visitor bounced from
  `/home`) now reloads into the site (`SiteHome`). If the app is ever served at "/" itself, it shows the
  old landing page rather than reloading forever.
- The installed web app's `start_url` is `/home`; sign-up's `emailRedirectTo` is `/home` (auto-confirm
  is on, so no confirmation email goes out today).
- The old landing page's anonymous try-it is retired; the homepage's try-it calls the public
  `homepage-enrich` function (live since 2026-10-06; caps 15 per 10 minutes and 60 a day per IP).
- **Social card:** `/og-v2.jpg` (rendered from `brand/og-src.html` by `scripts/render-og.mjs`) for the
  site and the app shell, whose title is now "Stash — save it fast, find it when you need it".

**What publishing changed from the prototype** (all checked by the publisher and by
`scripts/publish-site.test.ts`): absolute asset paths under `/site/`; real titles, descriptions,
icons and social tags; no design-history comments and no review panel; the pages on clean URLs; the
footer's and the iPhone page's "Notify me" (no list behind it) replaced by "It's in beta now. Want
to try it? Email us"; and the receipt screenshot's café (a real business, Blue Bottle Coffee, at its
real address) replaced by an illustrative one, Fernwood Coffee, in both images that show it.

**Shipped as written, unverified** (Will's call): the TikTok transcripts and on-screen text implied
by the scripted examples; the ChatGPT developer-mode, Claude Code `/mcp` and Cursor first-use steps on
`/connect`; what `/iphone` says the beta does.

**Also:** the header's account button is labelled "Account menu" (its name was the bare initial).

**Verified:** a production build served with `vercel.json`'s routing, walked in a browser: the
homepage with its fonts and pictures, Sign in, Get Stash, `/extension`, `/connect`, `/iphone`, the
footer links, the way-in wordmark back to `/`, signing in to `/home`, and signing out to the site. No
console errors, failed requests or 4xx. Tests: 630 in 77 files.

## 2026-10-07 · v2 second pass: the way in, a decrypting loading screen, Resolve, and Generate summary fixed

Will's notes on the 2026-10-06 redesign: a redesigned sign in / sign up connected to the
homepage's Sign in; a decrypting loading screen that cycles cheeky lines; "make it cool": the
pixel-to-visible effect instead of the green scan line; JetBrains Mono; texture and a little noise
on the library background; the composer's hint only on focus; the details drawer open by default;
no "Press '/' for commands" in the panel's notes; and "about half the time [Generate summary]
doesn't do anything. what should it do?" `DESIGN-v2.md` records it all (§4, §7, §8, §10,
§12.4–12.10, §12.14). Branch `app-redesign-v2`.

**Fixed in production: Generate summary.** Root cause: `summarize-content` v8 (deployed
2026-09-29) checked the caller with a bare `auth.getUser()` on `supabase-js@2.7.1`, which esm.sh
now bundles with `gotrue-js@2.117.2`. That auth client treats a bare call with no stored session as
signed out unless the client flags a custom Authorization header, and 2.7.1 never does, so every
request was answered `401 Not authenticated` in about 0.3 s, whatever the item. The button showed
"summarizing…" for a moment and then its small error line, which looked like nothing happening.
- Server: the function now reads the bearer token and calls `getUser(token)` with the service
  client, as every other function does. Deployed as **v9** (2026-10-07). Verified against
  production: eight real page bodies from 51 to 30,502 characters, each summarized twice, 16/16
  `200`s in 1.7–6.9 s (a repro script copied them onto throwaway fixture items and deleted them).
- What it does (the contract, unchanged): summarizes the item's `page_body` with the ingestion
  prompt (gpt-4o-mini, at most ~250 words), writes `summary`, refreshes embeddings, returns
  `{ success, summary }`; `{ success: false, reason: 'no_source_content' }` under 50 characters.
- Client: the button shows only when `page_body` has at least 50 characters after trimming
  (`canSummarizeSource`, mirroring the server); under that the tab says "Too little text was
  captured to summarize. It's all under Original Content." A failure is an error line in the
  machine voice (`couldn't summarize this. try again`; `nothing captured to summarize yet`) with
  the button still there to retry.
- Same bug in `chat-with-content` (v117): the bare `getUser()` on the same pairing, so its owner
  check never passed and it answered from the slim list row (no page text or summary). Fixed in
  code the same way, **not deployed**: its only caller (the per-card chat) has no entry point in
  the UI today, so the next deploy of the function carries the fix.
- Found while diffing deployed code (not changed here): production `transcribe-audio` (v28) gives
  recording summaries a 60 s timeout, but `_shared/summarize.ts` on main gives every kind 20 s (the
  2026-09-29 merges dropped `task === 'recording' ? 60_000 : 20_000`). The next deploy of
  `transcribe-audio` from main would shorten it.

**The way in (sign in, sign up, a new password) is v2.** `/auth` and `/reset-password` join the v2
scope (`src/utils/designScope.ts`); `/oauth/consent` stays v1.
- One floating machine window on the textured paper, its bar naming the address in the code voice
  (`stash://sign-in`, `stash://sign-up`, `stash://reset`, `stash://new-password`); a screen title
  ("Welcome back.", "Start your stash.") and a decrypting prompt (`> knock knock. who’s there?`,
  `> new here? pull up a chair.`, `> happens to the best of us.`).
- Fields have visible labels; placeholders are examples (`you@example.com`, `At least 8
  characters`). The username field shows the feed address it makes. Password managers save the
  email as the login (`autocomplete="username"` on both email fields); the @handle is
  `autocomplete="off"`.Field errors are wrapping
  machine lines tied to the field (`✕ that username is taken. try another.`, `✕ that number is
  already on an account. use another.`).
- Behaviour unchanged: the anonymous-session guard, `returnTo` / `commentItem`, the `mode=reset` and
  `mode=signup` deep links, the username / phone checks, the reset rate-limit toast, the recovery
  link handling.
- **The homepage prototype's nav** (`docs/superpowers/prototypes/2026-10-06-stashe-homepage/js/site.js`):
  **Sign in** → `/auth`, **Get Stash** → `/auth?mode=signup` (same origin when served; the live
  site from a `file://` checkout). The hero and closing "Get Stash" buttons still point at `#start`.

**Loading screen.** The paper, the symbol and a line in JetBrains Mono that decrypts behind a spot
head, holds 1.8 s behind the block cursor, scrambles out and gives way to the next. Twelve lines;
each load opens on the next (`localStorage.stash_loading_line`). Screen readers hear one status,
"Opening your stash". Reduced motion: the line, plainly. For iOS: the same lines and timing
(`src/components/machine/decryptCycle.ts`, a pure function of time).

**Resolve replaces the scan bar** (the reading state; same `enrichmentState` contract):
- A photo or link cover being read holds at 12 px pixel blocks while a square lens of finer blocks
  steps across it in rows; when the card leaves the reading state it sharpens 8 → 5 → 3 → 1 px.
- A picture that lands while the person watches (the `preview` reveal) resolves in from 26 → 18
  → 12 px (then the lens, if still reading) or all the way to sharp. It no longer prints in.
- A link placeholder's pixel glyph boils while reading; a voice note's waveform jitters while
  transcribing; a document's page lines flicker while the PDF is read. Each settles over three
  beats.
- A picture still downloading shows a shimmering mosaic of 8 px grey blocks (never an empty grey
  box). The optimistic "saving" card and the panel's PDF preview loader use the same mosaic (the
  checker is retired).
- One shared 110 ms beat drives all of it; off-screen canvases don't paint. Reduced motion: sharp
  pictures, still glyphs and waveforms, a still mosaic, read live, so switching it on with the
  app open settles a running effect at once.

**Library background:** paper with tooth, fixed behind the library, the loading screen and the
way in: a 4 px dot grid at 5.5% ink (a CSS tile), two stippled spheres from the corners (ordered
dither, 16%; 2–9 ms to draw, cached and reused between the loading screen and the library, not
redrawn when a phone's toolbar slides), and grain (12%). Settings stays flat.

**Smaller changes:**
- Composer: `type / for commands` appears only while the composer is focused.
- Item panel: the Details drawer opens expanded, and again for each new item; collapsing still
  works. Links no longer list an "Original file" (it was the stored cover, `preview_….jpg`).
- Item panel notes: the empty line says "Add a note…"; "Press '/' for commands or start typing…"
  is gone (the hint under the editor already says `type / for formatting`). The full-screen editor
  shows that hint in its footer. Links in notes are ink, not blue.
- Code voice (JetBrains Mono, new): the MCP address, the `claude mcp add …` command, the username,
  the public feed address, phone numbers, the panel's URL strip and code in notes. They were in the
  11 px pixel font, where `l`, `1` and `I` blur.

**Tests:** the summary tab (offer / refuse / error / busy), the details drawer (open by default,
no original file on links), the composer hint on focus, the decrypt cycle, Resolve's pure parts
(schedules, the lens path, object-fit geometry, boiling) and its hooks (resolve and hand back the
`<img>`, reduced motion switched on mid-effect, no sharp flash when a boil settles, no leaked
observer), the backdrop's stipple spans, the auth fields' `autocomplete`, and the v2 scope of the
auth routes. Full suite: 588 tests in 75 files. An independent review of the pass found the
reduced-motion, autocomplete, settle-flash, observer and backdrop-cost issues above; all fixed.

## 2026-10-07 · Web favicon is the A/4 symbol

- **Contracts:** none change. The icon files keep their paths (`/favicon.svg`,
  `/favicon.ico`, `/favicon-16.png`, `/favicon-32.png`, `/apple-touch-icon.png`,
  `/icon-192.png`, `/icon-512.png`). Every page that links them now adds `?v=a4`
  so browsers drop the cached S. This covers `index.html`, `public/site.webmanifest`
  and the extension install page. Bump the token whenever the icons change.
- **Visual:** the web icon set is the DESIGN-v2 mark, the A/4 symbol from the ST4SH kit,
  in warm white `#f3f2ee` on a charcoal `#171b1a` tile. Favicons have rounded 22% corners;
  the touch and PWA icons are square, because the OS masks them. Sources:
  `brand/stash-a4.svg` and `brand/web-icon-src.html`; `node brand/build.mjs` renders
  them (see DESIGN.md › Logo).
- **Other platforms: no action yet.** The iOS app icon, share-extension icon, onboarding
  tile and Chrome-extension icons deliberately keep the S on the purple→blue wash until
  those surfaces move to DESIGN-v2. Don't copy the web icon into them.

## 2026-10-06 · Web app redesign on DESIGN-v2 ("clean objects, DIY machinery")

Will asked for the app to match the new homepage, with retro, near-square cards, pixel type for
card labels, terminal-like touches, and the share sheet's cursor as the card's "gathering more
info" animation. `DESIGN-v2.md` is now the design system of reference, and §12 records every app
decision. The layout and data contracts are unchanged: no wire, schema or edge-function changes.
Branch `app-redesign-v2`.

**Scope.** `<html data-ui="v2">` on `/home`, `/settings`, `/discover`, `/feed/*`, `/admin*` and
`/design/*` (`src/components/DesignScope.tsx`). Landing, pricing, legal, auth and OAuth consent stay
v1 until the homepage prototype is ported. `?spot=violet` or `?spot=lime` on an app URL switches
the spot colour and is remembered, so Will can compare the two.

**Behaviour that changed (contracts for iOS and macOS to mirror):**
- **Enrichment state on a card** (same `enrichmentState` contract, new presentation):
  - The status pill and the 50% dimming are gone.
  - A one-line machine status sits under the title, or in its place before there is one: the
    cursor `| / - \` (130 ms per frame, one shared ticker) plus the label.
    - `gathering more info…` by default.
    - `reading the picture…` for images.
    - `transcribing…` for audio and video.
    - `reading the pdf…` while `isDocumentProcessing`.
  - A spot-coloured scan bar sweeps the media while the card is pending or processing.
  - Dotted placeholder lines hold the description's place when a description is one of the
    `missingPieces`.
  - When pieces land, the title decrypts in, and the description and picture print in.
  - At completion the line reads `✓ filled in` for 2.2 s. On partial it reads
    `some info unavailable` and stays.
  - New: a PDF counts as being read for 10 minutes at most (`isReadingDocument` in
    `src/utils/itemAssembly.ts`). Failed extraction writes nothing, so after that the line reads
    `some info unavailable` instead of reading forever. The editor block on processing
    documents is unchanged.
  - Reduced motion: the cursor stays still at `|`, there's no scan bar, and nothing scrambles.
- **Library toolbar:** `N saves` (was "N items"). While any save is pending or processing it adds
  `· | reading N…`. This is new: the count ticks every 30 s while any are open.
- **Optimistic "saving" card:** the rotating per-type messages ("Uploading audio…",
  "Transcribing…", "Almost done…") are removed, because they claimed steps the client can't see.
  It now shows a checker hero with the kind tag and `| saving…`. A placeholder title
  ("Processing …") is no longer shown as a title.
- **Card anatomy:**
  - The kind is always visible, as a black tag on the media (it was a hover-only chip in the
    footer). Kinds without media show it in the meta row.
  - The link domain moved from the kicker above the title into the meta row. It is still a link
    that opens the source in a new tab, now an `<a>`.
  - The chips row is gone: format, size, duration and read time ride in the meta row.
  - The date moved to the right of the meta row (`oct 3`, with the year if it's not this year).
  - The title's "Click to edit" tooltip is removed; the whole card still opens the panel.
  - `preview limited, saved anyway` on an imageless link shows only once enrichment is no
    longer pending.
  - The imageless-link placeholder shows the domain with no favicon. Fetching one per card
    would send the domains of the person's saves to Google on every library load. v1's letter
    tile didn't fetch either. The item panel's URL strip keeps its single favicon, as before.
- **Composer:**
  - The placeholder is now "Paste a link, drop a file, or type a note". `type / for commands`
    moved to a hint on the bottom row.
  - A blinking block cursor follows the placeholder while the editor isn't focused.
  - The send icon is an up arrow, and a turning cursor shows while it submits.
  - Chip statuses are now lowercase machine lines: `fetching more details…`,
    `reading the link…`, `analyzing…`, `uploading…`, `uploading · 45%`.
- **Ask:**
  - Each answer opens with a tool-step line:
    1. `| searching your stash…` before the first token.
    2. `| writing the answer…` while it streams.
    3. `✓ searched your stash · N saves` once done (also on reloaded history, from
       `source_items`).
  - "⌖ Focus sources (N)" is now `⌖ show N sources` (`showing` when active).
  - The dead "View all sources" link is removed (its handler was a no-op).
  - Uncited sources show as small cards under `also from`.
  - The feedback toast is "Feedback saved" (it was "Thank you!").
  - The launcher's mic has an aria-label ("Ask by voice").
- **Item panel:**
  - A 44 px ink window bar shows the kind, source and `saved <date>`. The tinted type chip and
    "uploaded · date" eyebrow are removed from the body.
  - The details are a `├─`/`└─` tree.
  - The autosave line reads `| saving…`, `✓ saved 9:41 pm`, or `changes save automatically`.
  - Source tabs render lowercase; their accessible names are unchanged.
  - "Press / for formatting options" is now `type / for formatting`.
- **Settings:**
  - A numbered vertical index replaces the five tabs. The new order is Your information,
    Connected agents, Phone & WhatsApp, Subscription, Tags.
  - Sections deep-link as `/settings#account`, `#agents`, `#phone`, `#subscription` and `#tags`.
  - Copy is sentence case ("Your information", "Save changes", "Phone & WhatsApp",
    "Register number").
  - The plan reads "$4.99 a month"; "Start 7-Day Free Trial" is now "Start the 7-day free trial".
  - Premium's list now reads "Unlimited summaries, transcripts and enrichment", "Search by
    meaning, not just keywords" and "Ask about everything you've saved"; it was "AI-powered
    insights" etc.
  - Agent activity is shown as a log.
- **Empty and loading states:** "Save your first thing." replaces "Start building your knowledge
  base". "Nothing matches that." replaces "No results found". Loading says `| opening your
  stash…` and keeps `aria-label="Loading"`.
- **Trial banner:** "$4.99 a month" (was "$4.99/month"); when urgent or paused it takes the spot
  field.
- **Sticky notes** (public items) are paper slips with an ink edge, no longer yellow. The delete
  confirmation now reads "Delete this sticky note?".
- **Brand:** the app header shows the ST4SH wordmark from the homepage kit. The PP Mori logo
  licence is still an open decision; confirm it before this ships. Swapping the mark back is a
  change to `src/components/brand/St4sh.tsx` only.

**Visual system:**
- Near-square: objects are 2 px, everything else is 0.
- Departure Mono (`font-pixel`, 11 / 16.5 / 22 px) for every label; Montreal for titles and
  sentences.
- Paper `#F3F4F1`, ink `#000`, one spot colour.
- Hovered cards lift onto a hard 4 px print shadow; floating windows cast it too.
- Dithered scrim behind sheets and dialogs.
- Square switches, inputs and tabs.

Full spec, with sizes, is in `DESIGN-v2.md` §5, §6, §8, §10 and §12.

**For iOS:** `DESIGN-v2.md` §12.11 maps each piece to SwiftUI. The card's machine line and its
copy table (§10) are the parity contract: the same states, the same words, with native controls.

**Verification:**
- `npm test`: 69 files, 540 tests. Changed assertions follow the copy changes above. New tests
  cover glyph integrity, kind labels and glyphs, route scoping, the status line, the saving card
  and the autosave line.
- `tsc` is clean.
- Checked in the browser as the UI-test fixture at 1440 and 390 px, with lime, violet and reduced
  motion. Ask was driven against a stubbed stream (no rows written).
- `/design/cards` (dev only) loops the enrichment sequence on a real card.

## 2026-10-05 · Citation detail edits after background delivery

An open Ask citation detail sheet now adopts title, description and sticky-note values that
finish saving through the shared queue. Changing one back to its earlier value is correctly
saved, including when the sheet closes before autosave. Text still being typed, newer queued
edits and saves in flight retain their existing protections. The durable queue is unchanged.

See [completion and remaining release checks](ios-plan-16-completion.md) for verification and
simulator review details.

## 2026-10-04 · iOS plan 16 stabilization and local integration

The interrupted Ask scrolling follow-ups are now included. The rendered tail moves whole
question-and-answer exchanges. Shedding above a reader at the end requires working scroll holds;
a send from above the tail can move offscreen rows before jumping. On iOS 17.4 and later, long system scrolls jump across
unbuilt history; the known iOS 17.0–17.3 streaming/assistive-scroll limitation remains.

Location saves now join the pending-edit delivery record inside the item's serialized write.
For example, after Brooklyn was delivered and Queens was saved, a failed change back to Brooklyn
continues to show its save error; an older Brooklyn delivery cannot make it read as saved.
The write still merges only location into the latest server attributes, preserving enrichment.

The live Ask smoke test now waits for a new assistant response using role-specific identifiers
from one snapshot. It starts a fresh conversation without deleting history. This corrects a test
that selected an old response even when the new cited answer was visible.

See [completion and remaining release checks](ios-plan-16-completion.md) for the fixed acceptance
scope, results, and explicitly deferred limitations. No wire contract or backend deployment changes.

## 2026-09-30 · iOS accessibility pass, Ask keyboard, white-S icon (plan 16)

Will's 2026-09-30 on-device review of the plan-15 build, answered in four parts: two Ask
keyboard fixes; a Human Interface Guidelines + accessibility pass over every iOS surface
(Dynamic Type, Bold Text, 44 pt targets, WCAG 2.2 AA contrast, VoiceOver); the S on every
icon turned white; and two visual bugs from his screenshots (a raw UUID file name as the
detail title, and the View-tab search pill half-covered by the first card as it hid).
iOS-only except the icon, which every surface shares. Look and feel is otherwise kept
(palette, layout, components, every accessibility identifier, 1 px strokes, light-only);
visible changes are called out where they happen. Plan:
`docs/superpowers/plans/2026-09-30-ios-plan-16-accessibility-ask-keyboard-white-icon.md`
(its Outcome lists commits, rulings and open items). Rules and tokens are in `DESIGN.md`
(Typography › iOS type roles, Color › Contrast, Components › Controls (iOS)); this entry is
the contract for the other platforms, and "For web and macOS" at the end flags what web
should adopt or consider. In order: Ask keyboard · typography · controls · contrast · links ·
detail sheet · edit queue and sharing · View tab · Add tab, Settings, onboarding, share sheet ·
Ask · the white S · for web and macOS.

**Ask keyboard (iOS; web has no on-screen keyboard).**
- While `ask.input` has the keyboard, the header's right side shows "Cancel"
  (`ask.dismissKeyboard`, the shared `StashCancelButton`) in place of New chat and History.
  Tap = dismiss the keyboard only; the draft is kept.
- The keyboard is put away before anything is shown over or in place of the composer:
  Conversations (History), a restored conversation (the restore banner) and a citation sheet;
  a Conversations row tap clears the search field's focus first. So choosing an earlier
  conversation can no longer leave a keyboard up with no composer.
- Cause, for the record (iOS 26.5 only; 17.5 doesn't do it): with the composer focused,
  pushing Conversations hid the keyboard, and when the stack popped iOS 26 handed the keyboard
  back to the composer while SwiftUI's keyboard avoidance missed it. The composer sat behind the
  keyboard with nothing on screen to dismiss it. The fix is an explicit `@FocusState` on
  `AskView`, cleared before each of those screens.

**Typography (iOS; web keeps its desktop scale).** iOS sets every piece of text with a role
(`.stashFont(.reading)`), never a raw point size: a Neue Montreal face at Apple's default
(Large) size for its text style, scaled with the user's text size
(`Font.custom(_:size:relativeTo:)`).
- Large sizes: `reading` 17 (was 14: the detail description, notes, summary and transcript;
  chat bubbles and the Ask composer; the Add editor; the share-sheet note; search fields;
  markdown headings in Semibold; the user's own words in Italic) · `secondary` 15 (card
  descriptions, previews and notes; settings secondary lines; conversation previews; row
  titles) · `meta` 13 (was 12: dates, facts, footers, status lines) · `chip`, `microLabel` and
  `kicker` 12 (were 11) · `textButton` 17 (Cancel and plain text buttons; the one primary text
  action is Medium) · `inlineButton` 15 Medium (inline text actions, never smaller).
- Titles keep their sizes and now scale: display 32 · panel 28 · screen title (Ask's) 22 ·
  card 20. Nothing a person reads is below 11 pt at the default size; smaller is decorative
  art, hidden from VoiceOver.
- At xxxLarge reading text is 22 and at AX3 it is 37 (iOS scales custom faces on
  `UIFontMetrics`' curve, slightly flatter than SF's own 23 / 40). Full table: DESIGN.md ›
  Typography › iOS type roles.
- **Bold Text.** SwiftUI does not embolden bundled faces (measured on iOS 17.0 and 26.5), so
  with Bold Text on every role draws the next heavier face (Book → Medium, Medium → Semibold;
  Semibold and Book Italic have no heavier bundled face and stay), live, with no rebuild of the
  view tree. SF text follows the setting by itself.
- **Leading.** Extra line spacing is an em fraction of the role's size, scaled with its text
  style, never a fixed `lineSpacing`. The detail sheet's reading text is 0.55 em; on Neue
  Montreal's 1.2 em line that is CSS line-height ≈ 1.75 (not the 1.55 an earlier note said),
  and Ask's 0.35 em is ≈ 1.55. At the accessibility sizes the gap is capped at 0.35 em, so
  reading text tapers from ≈ 1.75 to ≈ 1.55 (measured at AX3: 57.3 pt per line, was 64.7);
  xSmall to xxxLarge are unchanged.

**Controls (iOS).** Rules: DESIGN.md › Components › Controls (iOS).
- **44 × 44 pt targets.** Every tappable element takes touches across at least 44 × 44 pt
  whatever it looks like: a smaller visual keeps its size and position and its target
  overhangs it instead of growing the layout (the circles stay 36 / 40 pt; `PillTabs` take
  taps across the whole pill, where an unselected tab used to take them on its word only,
  36.7 × 17 pt). Pill tabs grow with the text up to xxxLarge and use the Large Content Viewer
  beyond. A text field takes taps across its whole box (a `TextField`'s own target is its line
  of text): the composers, the View-tab search pill, the title, description and sticky note,
  the sign-in fields and the share note. Web keeps WCAG's 24 px floor.
- **One keyboard Cancel.** `StashCancelButton`: 17 pt text, violet-600, a 44 pt target that
  overhangs the word, one line that never breaks. It is the only Cancel shown while a field has
  the keyboard: Ask (`ask.dismissKeyboard`), the Add tab (`capture.dismissKeyboard`) and the
  View-tab search (`library.search.cancel`, which also clears the query). Over the gradient wash
  it sits on an opaque paper capsule (violet-600 straight on the wash measures 2.8–3.3:1;
  visible change). ⌘. cancels from a hardware keyboard. After Cancel, VoiceOver's focus returns
  to the field (Add, View search) or to the last answer on screen (Ask).
- **The header at accessibility sizes.** The word outgrows the wordmark, so the header would
  jump when Cancel appears. The Add tab reserves Cancel's line height at rest (a hidden,
  zero-width "Cancel": the resting header is 0.67 pt taller at Large and about 25 pt taller at
  AX3) so nothing moves as the keyboard rises; Ask reserves both states' sizes, with the
  controls on a row of their own above the title; the View tab's header grows (Cancel goes
  under the pill and the cards move about 57 pt at AX3, an accepted trade-off).
- **Names and state.** Every icon-only control has a VoiceOver label and shows its name in the
  Large Content Viewer at accessibility sizes (`stashIconControl`); a toggle such as the
  location pin says On / Off; pill tabs carry the Selected trait; section labels and markdown
  headings carry the header trait; decorative glyphs and art are hidden.
- **Text grows, containers follow.** Anything holding text uses `minHeight`; screens that can
  overflow scroll; at accessibility sizes a row that can't fit reflows (HStack → VStack)
  instead of truncating what the user needs to read. System-styled controls keep SF (the delete
  sheet's Cancel and Delete everything, Settings' phone "Add").

**Contrast (iOS now; web can adopt it as is).** Text a person reads meets 4.5:1 on the
background it actually sits on (3:1 once large: 24 pt, or 18.7 pt bold); a control's only glyph
and other graphics that carry meaning meet 3:1; disabled controls and pure decoration are exempt.
- **Meta text is `muted` `#646b76`** (5.38:1 on white, at least 4.54 on every type tint):
  dates, facts, footers, section labels, the autosave line, placeholders. **`faint` `#959ba6`
  (2.79:1) is decorative or disabled only**, never text a person reads; an enabled control's
  only glyph is `muted` or `ink`. The system placeholder colour (1.7:1) is replaced by a
  `muted` prompt.
- **New token `violet-700` `#5d49cb`** (`StashColor.violet700`) for violet text on a type tint
  or a violet tint (session pill, due chip), where violet-600 text falls to 4.37–4.50:1.
  Violet glyphs and fills stay violet-600.
- Nothing but `ink` sits directly on the gradient wash; text over it sits on paper. A wash or
  tint stacked on a non-white surface needs its own check (a chip wash on `#f2f2f7` takes
  `muted` to 4.36). The full table of pairs is in DESIGN.md › Color › Contrast.
- Measured fixes on iOS: card dates and places 1.73 → 5.38; section labels, facts, autosave
  and hints 2.79 → 5.38; field placeholders 1.7 → 5.38; the error banner's white on orange
  2.20 → ink 6.89; Settings red 3.55 → `destructive` 5.06; Settings captions 3.30 → 4.82.

**Links in reading text are underlined (WCAG 1.4.1).** One shared style on the detail sheet's
markdown and in Ask answers: `violet-600` text with a solid underline in `violet-600` at 80 %
alpha (≈ `#8a7cd9` on white or paper, 3.52:1; ≈ `#8879d8` on Ask's `#f2f2f7` bubble, 3.26:1, so
the underline itself clears 3:1 where reading text sits; 75 % would be 2.99 on the bubble).
Colour alone can't mark a link: violet-600 is 2.93:1 against `ink` body text and 1.04:1 against
a `muted` quote. iOS: `Text.LineStyle.stashLinkUnderline` (`StashColor.linkUnderline`,
`StashDesign.swift`). **Web CSS:** `text-decoration-line: underline; text-decoration-color:
rgb(109 91 208 / 0.8)`. Links that are chrome ("Copy link", "Learn more") are unchanged.
Supersedes plan 8's violet-without-underline links. (A visible change; Will can veto it.)

**Detail sheet (iOS).**
- **Title fallback.** On audio, image, video and file items, a title that is empty, or only a
  storage object name (`<uuid>.<ext>`, or a 10–17-digit timestamp name), reads as the item's
  type label ("Voice note" / "Recording", "Photo" / "Screenshot", "Video", "File"): on the card
  and as the detail title field's placeholder. Text and link items (and legacy
  collection / unknown) keep "Untitled". Before plan 16 the sheet showed the raw file name.
- **The title field.** An object-name title opens as an empty field with the type label as its
  placeholder. Opening and closing the sheet writes nothing; typing a title saves it; clearing a
  title that was already sent writes `""`, which the server still treats as a placeholder
  (`isPlaceholderTitle("")`), so the transcription job's AI title can fill it. The field wraps
  but stays one line of text: Return is "done", even over a selection or an autocorrection, and
  ends editing; a pasted line break becomes a space. A title the server sends while the field
  has focus is shown as the server has it.
- **URL bar.** Standard sizes: one line, middle-truncated, scheme included. Accessibility
  sizes: at most 3 lines, without the scheme (the host starts line 1), middle-truncated (the
  test URL went from 11.2 lines at AX3 to 3). A long press always previews the whole URL,
  wrapped after "/", "." and "-", with Copy link and Open link (the preview used to be clipped);
  VoiceOver reads the whole URL.
- **Busy inline actions** ("Transcribing…", "Generating summary…") are one control in both
  states, drawn `muted` (5.38:1) and never dimmed, still disabled to VoiceOver, so VoiceOver's
  cursor stays on it.
- **Details header and facts.** A long collapsed summary (a long domain) is shortened beside
  DETAILS at standard sizes and moves under the label at accessibility sizes; DETAILS is a
  heading. Facts show label and value side by side at standard sizes and label over value at
  accessibility sizes.
- **Footer at accessibility sizes.** Only "Delete item" shows: the resting "Changes saved
  automatically" caption is hidden. Up to AX3, "Saving…" is a spinner in the Delete row
  (VoiceOver: "Saving…"), never taller than the row. At AX4 and AX5 there is no "Saving…"
  (measured at AX5: the row needs 326 pt without a spinner, against 335 on a 375 pt phone).
  The footer keeps its height and position through every save; only an error takes a line
  under Delete.
- **Also.** The sticky note gets the sheet's hide-keyboard control and VoiceOver reads its name
  once; the location editor types at 15 pt; card titles' tight leading is −0.1 em and scales
  with the title; the rendered rich note stays set solid (its blank-line paragraph breaks would
  double at the reading leading; per-block rendering is deferred).

**The detail sheet's edit queue and sharing rules (iOS).** Closing the sheet never waits on the
network (plan 15's durable pending-edits queue); these are the rules it follows.
- **Last value wins.**
  - A field needs saving when it differs from the server's value or from a value still queued
    for it (in flight or failed): title, description, sticky note, and a plain note through its
    draft. So a clear or a revert made after another value was sent supersedes it, even when
    the sheet is closed straight away, and the sent value's response never refills the field.
    Rich notes are append-only.
  - A queue confirm never drops a later value that equals an earlier one; only capture times
    decide. X → Y → X ends at X (one redundant PATCH when Y never landed).
  - A sheet's save never lands over a later value a flush already delivered. A save with
    nothing left to send counts as saved and lands against the values that flush delivered: a
    field the user has moved on from since is queued and sent, and a rich note's paragraph
    leaves the box and is never appended twice.
  - A flushed row never replaces a field while the user's change to it is still on its way:
    typed and in the autosave's debounce, being sent, or queued. A sheet adopts the rows its own
    flushes deliver.
  - Every saved landing brings the server's note document into the sheet: the newest save or
    not, a sheet opened on a queued note or not, another note save still queued or not. With
    saves overlapping (Done, more typing, Done again) each note is delivered once, and the next
    note is appended to the document the server holds, in Ask citation sheets too.
- **A rich note is delivered once.** Its text leaves the notes box when its own save lands, and
  also when the document the sheet shows becomes one the sheet queued that text as: the
  journal's draft (the app left the foreground), or a note save that failed. That holds
  whatever delivers the document, in whatever order: the sheet's own Sharing flush, the app's
  refresh, or a realtime echo of a PATCH whose response was lost, even one that reached the
  sheet before the save reported its failure. It is the document the sheet shows, never an
  incoming row's: a sheet opened on a queued note keeps its own copy, and the text stays in the
  box to go out with the next note (so does an Ask citation sheet that never sees the row that
  delivered it). Every such draft is kept until the sheet shows it or closes.
- **Sharing is privacy-first.** A share that failed is never published later; a failed un-share
  keeps the item public with its note.
  - *The journal.* When the sheet closes, or the app leaves the foreground, the journal queues
    what the switch shows whenever the server hasn't confirmed it: when it differs from the
    sheet's last server row, or from a Sharing value still queued, including a switch turned
    back to the server's value over a queued share.
  - *Never while open.* A share is never queued while the sheet stays open. Leaving the app
    mid-share doesn't queue it, and a kill then leaves the item private. An un-share is
    always queued.
  - *A failed share* leaves the switch at what the server holds, as far as the app knows: the
    sheet's last server row, or a Sharing value the app's queue delivered after that row was
    read, in whatever order that happened. An inline error shows unless that is the user's
    choice. So a failed share never stays on, with no error, over an item the app made
    private, up to one approximation: a delivery that lands between a row being read and the
    sheet taking it (normally about one round trip) counts as seen. In that window the switch
    can stay on with no error while the item is private; nothing publishes it.
  - *A failed un-share* leaves the switch at the sheet's last server row, or off when the
    app's queue delivered an un-share after that row was read; a share the queue delivered
    never turns it back on. When it goes back on, an inline error shows and the sticky note
    comes back (while the sheet is open; closing during the un-share leaves it and its note
    removal queued and retried). When it settles off no error shows, and over a share the
    queue delivered the item is public until the re-asserted private lands (next point).
  - *Settling off (the A-3 fail-safe).* When the switch settles off, private is queued again and
    sent at once, in one attempt, so it is re-asserted whatever reached the server meanwhile: a
    flush an Ask citation sheet never saw, or a share the server applied whose response was
    lost. Cost: one PATCH of a value the server usually holds already. If that attempt also
    fails (a dead link is the usual reason the toggle failed), private goes out at the close or
    at the app's next refresh; until then an Ask citation sheet can show Private with no error
    while the item is still public, and a share made on another device before that PATCH lands
    is undone by it. *Settling on* takes any other queued Sharing value back.
  - A toggle that lands while a newer save has started isn't adopted by the sheet, but its
    result is still what a later failed toggle settles on.
  - A sticky note typed while a share is in flight is saved like any field. If the share then
    fails the note stays on the private item and is published with the next share. This is
    intended: it's the user's own text.
- **Known residuals (honest).**
  - The citation text baseline gap was fixed October 5: values delivered by a shared-queue
    flush now advance the open sheet's baseline, and subsequent reverts are sent. See the
    October 5 entry above.
  - Pre-existing, not widened: a failed un-share whose sticky note matches neither the
    server's nor the queue's (another device changed it mid-flight) isn't restored, and the
    next autosave clears the server's note.
- **Edit queue:** a refused edit's backoff never ends more than 6 h from now, even after the
  clock is set back.

**View tab (iOS).**
- **The search pill scrolls away cleanly.** The tab is one scroll view for every state (cards,
  loading, searching, empty, no matches, error) and the search row is its first element, so it
  scrolls away with the content and a card can never overlap it. The row fades by its own
  position, 1:1 with the scroll, down to a floor of 1 % opacity so it stays in the
  accessibility tree (SwiftUI drops a view at exactly 0). A resting position part-way out snaps
  to the nearer end, so the pill never rests half-faded (the snap stands aside under
  VoiceOver). A status-bar scrim in the page's own background colour covers the top band once
  the row is gone: it reads as a white band over the wash (visible change; masking the content
  instead would cost an offscreen pass per scroll frame). Tapping into a part-way pill scrolls
  it back to rest, typing never moves it, and pull-to-refresh now works in every state. Plan
  12's keyboard behaviours and every identifier are kept.
- **The search field.** The whole 44 pt pill focuses the field; the clear × is a 44 pt target
  that stops 2 pt short of the field, so tapping the end of a long query places the caret;
  Cancel is the shared `StashCancelButton` on a paper capsule, and clearing and Return are
  unchanged. At accessibility sizes Cancel sits under the pill and the row grows when the
  field is focused.
- **State panes follow the keyboard.** "No matches", "Nothing here yet" and "Couldn't load"
  centre below the search row, in the part of the tab the keyboard leaves while it is up and in
  all of it once the keyboard has gone, on iOS 17 and 26. On iOS 17.0 the pane used to keep
  whichever height it had read last (centred above a keyboard that had gone, or in the whole tab
  while the keyboard was up).
- **Cards.** The card title is unclamped at accessibility sizes; the description and note are
  15 pt with twice the lines at accessibility sizes; the footer stacks there; dates and places
  are `muted`; the sticky badge is capped at Large.

**Add tab, Settings, onboarding, sign-in, share sheet (iOS).**
- **Toasts (Add tab).** A paper pill (white, hairline, card shadow) with an intent glyph and ink
  text; it wraps at large sizes, lasts 3 s and is announced to VoiceOver. Glyphs: a success
  check `#2f9e63`; an amber warning triangle `#7a4b00` for a save that dropped files; a
  violet-600 clock for offline / will sync; a `destructive` circle for refused. Only a saved
  toast is tappable (it opens View); every other toast lets taps through to the controls under
  it. It replaces white text on a coloured pill (white on `success` is 3.39:1, on orange 2.20).
  Other surfaces: the same intent mapping, never white text on a coloured pill.
- **Outbox badge.** The system orange (no token) with ink digits (6.9:1 on iOS 17's orange, 6.6
  on iOS 26's; it was white digits). VoiceOver says "N captures waiting to sync". It rests at
  the header's trailing edge and moves left of Cancel, at its own width, while composing.
- **Add header.** At the accessibility sizes it reserves the Cancel line's height (not its
  width) at rest, so nothing jumps as the keyboard rises; the View tab's header grows instead
  (see Controls).
- **Delete-account sheet (Settings).** On iOS 26 it has an opaque paper background instead of
  the half-height glass, which let the Settings list show through its copy and buttons so AA
  couldn't be promised there (visible change). It opens full height at accessibility sizes, and
  its controls are 46 pt (44.2 on screen at iOS 26's medium-detent scale).
- **Settings.** A row stacks its label over its value when they don't fit (the email breaks
  after the "@"); section captions are `muted` and Sign Out and Delete account use
  `destructive`; legal links are 15 pt Medium text actions in 44 pt rows; a registered phone
  number wraps instead of truncating (two lines at AX3 and AX5).
- **Voice recorder.** The sheet scrolls; its Cancel, Stop, Re-record and Save buttons are large
  system buttons, 50 pt tall and tinted violet-700 (violet-600 text on its own tint was 4.05:1,
  now 4.87), stacked at xxxLarge and above (they used to be 34.3 pt tall and broke mid-word at
  AX3); the record glyph grows with the text, capped at 44 pt.
- **Sign-in.** Placeholders are a `muted` prompt; fields are at least 44 pt tall and take taps
  across the whole field (the padding above and below the text line used to be dead); the "@"
  sits beside the username instead of overlaid (2.57 → 4.95:1); Forgot password is 15 pt with a
  44 pt target.
- **Onboarding.** The card hugs its content and is measured from the tallest panel (a fixed 490
  pt height clipped every larger size); it scrolls at large sizes; the art is a fixed-scale
  picture hidden from VoiceOver (the title and caption say what it shows); "Step N" is a
  micro-label. Skip and Next both take taps to their edges (Skip's 44 pt target starts at
  Next's bottom edge). **The step-3 art** is re-shot at native resolution (344×688 @2x,
  516×1032 @3x; the old art was upscaled ≈ 2.2×) and shows today's share card: the new
  wordmark, example.com, no personal data (visible change).
- **Attachments.** The remove × is a 44 pt target, moved 6 pt toward its chip so it clears the
  edge of the row's scroll view (on iOS 17 the top ~5 pt of taps are lost there); the tile's
  file name is ink (`muted` measures 4.44:1 on the tile) and capped at xxxLarge inside its fixed
  64 pt tile (VoiceOver reads it whole).
- **Share sheet.** The note is 17 pt reading text with a `muted` placeholder, and a tap
  anywhere on its card focuses it; Save is at least 52 pt tall and grows with the text (60.7 at
  AX3); the location pin is a toggle; each file tile is one accessibility element.

**Ask (iOS).**
- **Text.** Answers, the welcome text and the composer are `reading` 17 pt (was 14), with
  0.35 em leading (≈ 1.55) at every size; status lines are `meta` in `muted`; markdown headings
  in answers are Semibold (they rendered Book); a quote's `muted` colour now applies (it drew
  ink). Links in answers use the shared underline above.
- **Controls.** New chat and History keep their 36 pt circles with 44 pt targets, 44 apart;
  read-aloud, Helpful and Not helpful are 44 × 44 targets, 44 apart (they were 18.3 × 13.3), and
  a given rating is selected and disables both; the composer's whole pill focuses the field,
  padding included, and Send is named; source chips are 44 pt tall; the session pill is
  violet-700 on its tint (5.46:1, violet-600 was 4.41); banner text uses `destructive`
  (5.06:1).
- **Header and Conversations.** At accessibility sizes the controls take a row above the title,
  and the header doesn't jump when Cancel swaps in, at any size. Conversations titles are 15 pt
  Medium and wrap to two lines above Large, previews 15, dates and counts 13 in `muted`;
  section headers are micro-labels with the header trait; rows stack at accessibility sizes.
- **The thread always lands on its last message.** Sending from far up a long thread, or
  opening or restoring a long conversation, now lands on the last message (it used to land
  blank on iOS 17 and 18 and could hang on iOS 26: the lazy thread estimates the height of rows
  it hasn't built, and every jump aimed at an estimate). The end of the thread is laid out in
  full; far jumps cut with no ease and a hop within one screen eases. What you are reading
  stays put when the keyboard comes up, on rotation and on a text-size change. The resting gap
  under the last bubble is 14 pt (was 19 at rest, 15 while streaming).
- **Leaving the end.** Only a drag used to stop the thread following a streaming answer. Now a
  status-bar tap, or a VoiceOver or Switch Control scroll, leaves the end too, so the answer
  stops pulling the reader back. A status-bar tap cuts to the top of the thread instead of
  animating through it (the animated scroll could freeze the app on iOS 26.5 in a long thread
  while an answer streamed). While VoiceOver or Switch Control runs every row is laid out, so
  focus reaches the whole history in order. Reduce Motion turns the near-send ease into a cut
  and the streaming cursor static; the cursor no longer drifts over the answer's text.
- **Tail follow-up (completed October 4).** Shedding above a reader at the end requires working
  scroll holds. A send from above the tail can shed offscreen exchanges before jumping, without
  holds; a send from inside the tail waits to shed until it lands. Corrections of overwritten offsets are bounded. A status-bar cut
  prevents a queued follow-scroll from pulling the reader back down.
- **Known platform limit.** On iOS 17.0–17.3, animated keyboard/assistive scrolls can still be
  pulled back during streaming. This is explicitly covered by expected-failure checks, not
  claimed as resolved. See `docs/ios-plan-16-completion.md`. iOS only; no web impact.

**The white S (every surface).** The wordmark's first S on the purple→blue wash is now `#ffffff`
instead of ink `#22262f`: the iOS app icon and the share extension's, the onboarding tile, the
favicons (`.svg`, `.ico`, 16, 32), the Apple touch icon, the PWA 192 / 512 icons and the Chrome
extension's 16 / 32 / 48 / 128. The wash and the 62 % scale are unchanged and the "Stash"
wordmark stays ink. White measures at least 3.44:1 against the wash under every part of the S
(WCAG's floor for graphics is 3:1); keep it above that if the wash stops ever change. The only
sources are `brand/icon-src.html` and `brand/build.mjs`; `node brand/build.mjs` regenerates the
15 files, and a run on the unchanged sources reproduced the old files byte for byte, so the
diff is purely the S colour. Chrome extension 1.2.0 → 1.2.1: the hosted zip and the
install-page stamps are refreshed (`extension/scripts/publish-hosted-zip.sh`) and the store
docs name 1.2.1; the Chrome Web Store submission (B13) is still pending. **macOS lives in
another repo (`stash-mac`)** and doesn't follow until that repo re-runs the source
(`brand/icon-src.html#size=1024`). Supersedes the ink-S description in the 2026-09-15 entry.
The App Store screenshots and the extension store screenshots 02 and 04 still show older art.

**For web and macOS (flagged).**
- **WEB SHOULD ADOPT: the link underline** (above), for links in summaries, notes and answers.
- **WEB SHOULD ADOPT: the contrast token.** Micro-labels and dates → `muted` (web still renders
  `faint` there; DESIGN.md › Typography); `faint` decorative only; placeholders `muted`
  (`src/components/EditItemTitleSection.tsx` draws its "Untitled" in `#959ba6`, 2.79:1);
  `violet-700` for violet text on tints; the stacked-background rule; WCAG's "large" read as
  24 / 18.66 CSS px.
- **WEB SHOULD ADOPT: empty media titles read as their type.** On audio, image, video and file
  items an empty or object-name title reads as the type label, on the card and as the title
  field's placeholder, and clearing writes `""`. `src/utils/titlePolicy.ts` already has the
  narrow tests (`isUuidObjectName`, `isStorageTimestampName`); `isPlaceholderTitle` is broader
  (any filename-shaped title). `src/components/EditItemTitleSection.tsx` still shows an
  object-name title as it is, with an "Untitled" placeholder, and Task 4's report says the card
  title needs the same (not re-checked here).
- **WEB MAY WANT: toasts.** The same intent mapping, never white text on a coloured pill.
- **WEB MAY WANT: the edit-queue rules.** The web edit sheet has no durable queue. Its
  equivalents are "a revert while a save is in flight must still be sent" and "a failed share
  toggle shows the server's value and never retries the opposite".
- **WEB CONVERSION NOTE: leading.** 0.55 em on Neue Montreal's 1.2 em line is line-height 1.75,
  not 1.55; Ask's 0.35 em is ≈ 1.55. The web has no accessibility sizes, so there is no taper
  to mirror.
- **SERVER, every client: Ask's source chips.** The chip shows the server's `title`, and
  `chat-with-all-content` sends the literal "Untitled" for an empty one
  (`supabase/functions/chat-with-all-content/index.ts:274`), so a cleared voice note's chip
  reads "Untitled" while its card reads "Voice note", and a fresh voice note's chip shows its
  object name. The fix is server-side: send the raw title (null when empty) and use a type
  label in the model's context. Carried to Will.
- **macOS:** the menubar icon (above).

**October 4 disposition.** Batch B's stale-error fixes and the final location-delivery fix are
included. The bounded completion review and acceptance results are in
`docs/ios-plan-16-completion.md`. TestFlight build 10, App Store screenshots and physical-device
accessibility checks remain separate release work; no upload or App Store submission is implied.

## 2026-09-29 · Enrichment quality loop on main · transcript summaries unified · one correction

Housekeeping wave, mostly server-side. Five completed-but-unmerged branches were
merged into `main` (reminders email, Ask-Stash notes in search, logo refresh,
long-audio transcription, enrichment quality loop). The first four already had
their own entries below — this entry covers the fifth, two behaviour changes that
affect every platform's summaries, and a correction to a commit message.

- **Enrichment quality loop (server-only; was ALREADY LIVE before this merge).**
  `main` had no source for infrastructure that has been running in production on
  an hourly cron. It does now. Nothing for a client to call and no UI, but two
  facts clients should know: it writes `attributes.enrichment.*` (status,
  evidence, protected_fields) and `attributes.media.*` on items it repairs, so
  the usual `attributes` rule matters more than before — **whole-blob writes must
  preserve keys you do not model**, or you will erase enrichment state. And
  repairs are currently DISABLED in production (`ENRICHMENT_REPAIR_ENABLED`
  unset): the loop assesses and defers, it does not yet rewrite anyone's items.
  Source: `supabase/functions/_shared/enrichment*.ts`,
  `supabase/functions/enrichment-maintenance/`, migrations `20260923120000` and
  `20260923121000`.

- **DO NOT set `ENRICHMENT_REPAIR_ENABLED=true` yet — read this first.** The
  enrichment loop currently ASSESSES ONLY. That one environment variable is the
  switch between "looks at your items" and "rewrites your items", and two known
  issues sit behind it. (1) Legacy `type='collection'` rows are in the pipeline:
  the `enqueue_enrichment_assessment` trigger has no type predicate, so all 14
  legacy collections in production are queued, assessed and counted (~1.4% of
  `enrichment_quality` rows, so metrics from that table include them). Collections
  are legacy read-only per `CLAUDE.md` and must never be patched. They are
  currently double-guarded — `assessEnrichment` returns `unsupported` for them and
  the repair gate skips `unsupported`, and since 2026-09-29 the summary path also
  refuses to map that type — but nothing stops them ENTERING the queue, and the
  clean fix (excluding the type in the trigger) has not been made. (2) The repair
  path is the only caller that reaches `generateSummary` with a raw DB item type,
  so it is the path where a type-vocabulary mistake becomes a written summary; an
  unmapped type is now recorded as a failed attempt with
  `unmapped_item_type:<type>` rather than guessing a prompt. Before enabling
  repairs: decide the collection exclusion, and watch `enrichment_attempts` for
  `unmapped_item_type:` reasons. Turning it on is a release, not a config tweak.

- **Transcript summaries: one prompt, one budget, whichever path produced them.**
  Behaviour change worth mirroring in expectations, not code. Summary prompts were
  selected by DB type, and the two callers label the same thing differently —
  capture sends `recording` for every audio/video, while the new repair path sent
  the raw type (`audio`/`video`). The result was that repairing a recording
  DEGRADED a summary the capture path got right: generic prompt instead of the
  transcript prompt, a 600-token instead of 700-token budget. All three notions of
  "is this a transcript" (prompt, input cap, output budget) now share one set, so
  capture and repair agree by construction. A voice memo gets the same summary
  whichever path last touched it. Source: `supabase/functions/_shared/summarize.ts`,
  locked by `summarize.test.ts`.

- **Every summary prompt now says the source is untrusted.** Applies to links,
  documents and recordings, which previously did not carry it: the model is told
  to treat captured source text as data and never as instructions, and to
  preserve specific names, models, places and cited resources. Captured pages are
  third-party text; a page that says "ignore your instructions" is a page, not an
  instruction. Expect slightly more literal, less paraphrased summaries.

- **CORRECTION — commit `b66b0ca6` contains a claim that is DISPROVEN.** That
  merge commit's message has a section headed "RELATED PROD FINDING" asserting
  that production runs the older diarized synchronous `transcribe-audio` rather
  than the asynchronous job version, and that the `transcribe-audio-sweep` cron
  had been firing every 10 minutes against an endpoint unable to service it.
  **Both claims are false and there is no broken-cron defect.** `transcribe-audio`
  was deployed as v28 on 2026-09-29 05:50:18 UTC, and `net._http_response` shows
  the sweep returning `200 {"due":0,"started":[]}` — a response shape only the job
  version can produce. The cron is being serviced correctly.
  The reasoning error, recorded because it generalizes: current deployment state
  was inferred from item rows created on 2026-09-10 and 2026-09-17. **Item rows
  are creation-time artifacts — they evidence what was deployed when they were
  written, not what is deployed now.** Production had churned between the two
  designs. To answer "what is running", read the Management API function list and
  `net._http_response`, not stored data.
  Still **OPEN in both directions**: whether the deployed v28 also diarizes the
  synchronous preview path. It has not been established either way — do not
  assume diarization is absent. (Separately and NOT retracted: within this
  repository, merge `b66b0ca6` did leave `formatDiarizedTranscript` with a passing
  test and no production caller. That is a source-level fact and stands.)

- **"Transcribe with speakers" is now "Transcribe again" (web + iOS).** The server
  no longer diarizes: `formatDiarizedTranscript` survives in
  `supabase/functions/_shared/transcript.ts` but has NO production caller, and
  `transcribe-audio` contains no speaker handling at all. The button's behaviour is
  UNCHANGED and still worth offering — it re-invokes `transcribe-audio` on the
  original media and patches only `page_body` + `description`, never `content`,
  preserving the previous transcript on failure. Only the promise was wrong.
  Web `src/components/TranscriptContent.tsx`: idle "Transcribe again", busy
  "Transcribing…", helper copy unchanged. iOS `ItemDetailContent.swift`: idle
  string only — "Transcribing…" already matched. **Supersedes the "Transcribe with
  speakers" bullet in the 2026-09-13 plan-14 entry below** — only that bullet; the
  rest of that entry is unrelated and stands. Two things in it no longer hold: the
  button name itself, which advertises speaker separation as the feature's purpose,
  and the parenthetical "labels come from the server's diarization", which the
  merged `transcribe-audio` does not do at all. Note what was NOT wrong: that
  bullet states the copy "never claims real speaker names", and it did not — the
  old copy deliberately disclaimed them. The defect was advertising speaker
  separation as the button's purpose and documenting a diarization premise that no
  longer exists, not inventing speaker identities. Everything else that bullet
  describes — the media-URL resolution, the `{audioUrl, fileName}` body, patching
  only `page_body` + `description`, never touching `content`, preserving the
  previous transcript on failure, the busy state disabling the button — is still
  accurate. Accessibility identifier
  `detail.transcribeSpeakers` is deliberately unchanged (stable test contract, now
  a mild misnomer). Whether diarization returns is an open decision — if it does,
  re-advertising speakers is a deliberate copy change, not a revert.

- **CORRECTION — a reported defect in `summarize-content` was RAISED, REVIEWED AND
  WITHDRAWN. It was never real.** Commit `2c4f9a4d`'s message claims that before the
  enrichment merge an image/audio/video/text item could reach `generateSummary`
  through `summarize-content` and produce a system prompt containing the literal
  string `undefined`, calling it a reachable defect in a deployed function. A HIGH
  review finding was then raised on top of that claim, arguing a legacy
  `type='collection'` row could have a summary generated and written by the same
  path. **Both are false.** `summarize-content/index.ts:65` carries an allowlist —
  `if (item.type !== 'link' && item.type !== 'document')` returns early — and it
  precedes that function's single `generateSummary` call and its
  `update({ summary })` write. It was introduced in `f311b95a` and never changed, so
  the guard held at every point in this history. Only `link` and `document` reach
  the summarizer there, which are exactly the two kinds with hand-written prompts,
  so neither a generic-fallback prompt, nor an `undefined` prompt, nor a summary
  write onto a collection row was ever reachable from that endpoint. The finding was
  withdrawn in full; the false claim remains inside `2c4f9a4d`'s commit message,
  which cannot be rewritten.
  The reasoning error, recorded because it generalizes: the call site was read and
  reasoned about without reading the guard clauses nineteen lines above it. **A type
  that is unnarrowed AT a call site can still be constrained BY control flow —
  proving a path is reachable means reading the path, not the line.**
  This does NOT weaken the change `2c4f9a4d` made. The enrichment repair path is the
  only caller that hands `generateSummary` a raw DB item type, and merge 5 widened
  the transcript vocabulary to `audio`/`video`; the explicit mapping makes that
  widened vocabulary safe **by construction** rather than by a behavioural status
  check that could later change. All six callers are constrained, which is the
  evidence that there is no seventh door: `transcribe-audio:372` and
  `scrape-page-content:33` pass the literals `'recording'` and `'link'`;
  `extract-pdf-text` and `extract-office-text` pass `'document'`;
  `summarize-content` is allowlisted at `:65`; and
  `_shared/enrichmentMaintenance.ts` narrows through `summaryKindFor`.

## 2026-09-27 · iOS background share, instant library, functional tune-up (plan 15)

Will's on-device feedback (share sheet too slow on cellular, View-tab taps opening the
wrong card, slow first load) plus an audit-driven tune-up of the whole app. iOS-only
except the new platform `capture` endpoint, which other clients may adopt. Plan:
`docs/superpowers/plans/2026-09-27-ios-plan-15-background-share-and-tuneup.md`.
Look and feel unchanged except where noted.

**Platform — idempotent `capture` endpoint (new).** `POST /functions/v1/capture` wraps
`add-note`/`add-url`/`add-file` with an idempotency receipt keyed by a client-generated
`capture_id` (table `capture_receipts`, attempt-fenced so a stalled attempt can never
double-insert). JSON for notes/links; multipart (`meta` part first, then `file` with a
`filename=`) for files ≤ 10 MiB on iOS (server cap 45 MiB); larger files upload to
`stash-media/<uid>/<capture_id>.<ext>` first and register with `file_path`. Contract,
status table and limits: `docs/PLATFORM_API.md` "capture". iOS routes every capture
through it; web, the Chrome extension and macOS still call `add-*` directly and can adopt
`capture` whenever they add retries.

**iOS Outbox contract.** Every capture (composer, voice note, share sheet) is written to
the per-user Outbox BEFORE any network call, and its entry id is the `capture_id`, so any
retry from any process is deduplicated server-side. States: `pending`, `parked` (403
`subscription_required`; unparked when entitlement returns), `transferring` (owned by a
background upload; resent by a drain only after 600 s, or 3900 s for a storage upload
that hasn't checkpointed). 409 `capture_in_progress` never counts as an attempt; 413
`file_too_large` switches the entry to the two-step path; 400/`meta_too_large` count and
don't loop. Composer network failures now queue instead of dropping attachments.

**Share sheet.** Save persists the entries, hands them to one background `URLSession`
shared by app and extension (`it.gostash.stash.capture-transfers`, App Group container),
shows the existing "Saved to Stash" confirmation ~50 ms after the tap and closes ~0.8 s
later; the upload finishes in the background even if the extension is gone (the system
wakes the app to finish). A token with < 5 min left is refreshed first (≤ 2.5 s); a
401/expired-JWT completion refreshes and restarts that phase once. If the background
session is busy, a bounded (≤ 6 s) foreground send runs instead; anything left is
drained by the app later. A resolving location pin no longer delays the confirmation (it
is merged into the entries before upload, ≤ 2.5 s). Any file type is accepted. Visual:
the gradient backdrop is gone (plain paper) and the header has extra inset so the
wordmark clears iOS 26's larger sheet corners.

**Image policy (every iOS image capture).** Longest edge ≤ 2560 px (big sources decode
subsampled, so a 12 MP photo lands at 2016×1512), JPEG quality 0.82, EXIF orientation
applied, all metadata incl. GPS stripped (passthrough JPEGs are GPS-stripped losslessly),
GIF passed through, alpha composited onto white, RAW uses its embedded preview, original
name kept in `attributes.media.file_name`. Fixes HEIC originals that Chrome and the
vision model couldn't read, and cuts cellular upload size ~4×.

**View tab.** On iOS the whole card is ONE tap target that opens the detail sheet — no
in-card note editing, no "Add a note", no kicker link (web keeps its inline note
editor; DESIGN.md "Card note" records the difference). Root cause of the mis-taps: hero
images scaled to fill overflowed their clipped frames and still received taps, so the
next card stole taps aimed at the bottom of the card above. The item store now lives at
app scope per signed-in user with a disk-cached first page (purged on sign-out and
account deletion), refreshes at sign-in, on foreground and on tab open (30 s staleness
rule; pull forces), and re-reads only changed rows on realtime events (deletes made on
another device appear on the next refresh — realtime can't filter DELETE by user).
Search uses `search-items` like web, with literal matches (on displayed plain text) shown
first, then server relevance — an intentional divergence web may want to adopt. Images
load through one downsampling loader with memory + disk caches and prefetch. Titles that
are bare UUID or timestamp file names display a type label ("Voice note", "Photo",
"Video", "File"); card chips read `attributes.media.kind`.

**Detail sheet.** Closing never waits on the network: unconfirmed edits go to a durable
per-user pending-edits queue (latest value wins per field; flushed before every refresh;
backoff min(30 s·2^(n−1), 6 h); dropped with a log after 20 server refusals; offline
failures don't count), and the list shows queued values until confirmed. A zero-row
PATCH is only treated as "item deleted" after a verified-token read. Location edits
merge onto the server's current attributes (never a stale whole blob). The summary shows
immediately; `page_body` is fetched only when missing; empty summaries get "Generate
summary" (`summarize-content`). Load failures show a retryable state. "Transcribe with
speakers" now asks the server to rebuild the transcript as a job (`transcribe-audio`
`{itemId, rebuild: true}` → 202) and follows `attributes.media.transcript` until it
finishes; the client no longer writes `page_body`/`description` itself, so the new
`protect_enrichment_edits` trigger never mistakes a transcript for a user edit, and
recordings over 24 MiB work the same way. An empty Transcript tab reads that same
status: a job that ended `failed` says "No speech was detected in this recording."
(`error: no_speech`) or "Couldn't transcribe this recording." (any other code) instead of
"Transcription in progress…" forever; the header's "Transcribe again" button (relabelled
from "Transcribe with speakers" on 2026-09-29) is the retry. (Web's empty transcript reads "No transcript available for this recording."
whatever the job status — web could adopt the status-aware copy.)

**Attributes.** `location`, `link` and `media` now round-trip unknown nested keys, so
iOS edits no longer delete server-written keys such as `media.kind` and
`media.transcript`.

**Ask.** Retrieval-only on iOS too (implements the 2026-08-27 all-platform decision;
placeholder "Ask your stash…"). Each answer is written to the conversation it was asked
in; new chat / history / restore wait while an answer streams. Streaming updates are
batched (~10 Hz); the thread follows the answer until the user drags it. An interrupted
answer keeps its partial text with Retry. The server's `status` frames show as
"Searching your stash…"/"Reading…" before the first token (web ignores them — worth
adopting). Read-aloud strips markdown and citations (web's `stripForSpeech` still reads
bare citation ids aloud — web follow-up). A `403 subscription_required` from chat shows
the existing subscription gate and re-checks entitlement instead of a generic failure.

**Session, settings, composer.** A cold launch uses the stored session, so an offline or
expired-token launch opens the app instead of the sign-in screen; signed-in requests that
can't get a token fail locally instead of going out anonymously; only an explicit
sign-in can switch accounts. Subscription gates stay open until the server gives a
definite answer (web parity; the server enforces the paywall). Entitlement checks are
coalesced: an open answer is reused for 180 s, while a closed one is re-checked on every
foreground so someone who just subscribed on the web isn't held back.
Delete-account allows 120 s and confirms with Auth before reporting; sign-out keeps the
per-user queues for the same user's next sign-in, deletion purges them. Sign-up offers
strong-password AutoFill (`.newPassword`) and Return walks the form. Voice memos keep
recording through screen lock (`UIBackgroundModes: audio`, app target only) and show
"Recording was interrupted at m:ss" after an interruption. Attachments load off the main
thread with a pending chip and a toast on failure.

**Privacy manifests.** App: UserDefaults (CA92.1, 1C8F.1) and file timestamps (C617.1).
Share extension: UserDefaults (1C8F.1) and file timestamps (C617.1). No system-boot-time
API anywhere (`BootTimeAPIUsageTests` guards it).

**Production state as of 2026-09-29** (deployed 05:50–05:57Z from the branches merged to
`main` in the 2026-09-29 entry above): `add-url`, `add-file` and `chat-with-all-content` now
also return 403 `subscription_required` for lapsed accounts (`docs/PLATFORM_API.md`
previously named only `add-note`); `transcribe-audio` v28 defers files over 24 MiB to its
job mode; `generate-embeddings` v120 checks item ownership and replaces rows by
compare-and-swap; new `items` triggers `protect_enrichment_edits` and
`enqueue_enrichment_assessment` mark user-edited fields and queue enrichment.

## 2026-09-18 · Chrome extension install page + hosted zip refresh

Unlisted install instructions for the zip-distributed extension, for anyone who
isn't going to load an unpacked folder from a git checkout.

- **URL**: `https://www.gostash.it/extension` — static
  `public/extension/index.html`, `noindex, nofollow`, not linked from any nav or
  footer (share the link by hand). Vercel serves the directory index ahead of
  the SPA catch-all rewrite, same as `/prototypes-for-feedback/mutations`.
- **Contents**: download tile for `/stash-it-extension.zip` (version + size
  stamped in), six steps (unzip to a permanent folder → `chrome://extensions`
  with a copy button, since web pages can't link to `chrome://` → Developer
  mode → Load unpacked → pin → sign in once), the three capture gestures, a
  "good to know" list (developer-mode startup notice, Chromium-only, red badge
  = check sign-in), and update instructions (replace folder contents + reload
  keeps the session; remove + re-add signs out).
- **Hosted zip refreshed** to 1.2.0 (`public/stash-it-extension.zip` was still
  1.1.1: old `<all_urls>` host permission, no forgot-password link on the
  sign-in page). New `extension/scripts/publish-hosted-zip.sh` runs
  `package.sh`, copies the result to `public/`, copies `icon128.png` next to
  the page, and rewrites the page's `data-version` / `data-size` stamps — run
  it with every extension release so the hosted copy stops drifting.
- **Shared web fonts**: the four PP Neue Montreal woff2 files moved from
  `public/prototypes-for-feedback/mutations/fonts/` to `public/fonts/` so any
  static page outside the Vite build can use them; the mutations prototype
  now points there too.
- Design: DESIGN.md tokens copied inline (Montreal only, ink/muted/faint,
  violet-600 on exactly one element, 1px hairlines, 16px tile radius, no
  emoji, reduced-motion guard). iOS/macOS: nothing to mirror — desktop-only.

## 2026-09-15 · Logo refresh — "Stash" wordmark + first-S app icon on the wash

Brand swap on every surface; no behavior or data-contract change. Will's call: the new wordmark
is the five letters only (the two blue strokes and the tagline in the source art are dropped),
and the app icon is the wordmark's first S in near-black on the purple/blue gradient.

- **Sources.** `brand/stash-wordmark.svg` (viewBox `0 0 1003.84 306.57`, aspect 3.27:1 — the old
  mark was 3.89:1, so at the same height the new one is ~16% narrower) and `brand/stash-s.svg`
  (`0 0 222.77 294.3`). `brand/icon-src.html` composes the icon; `node brand/build.mjs` at the
  repo root regenerates every derived file below — never hand-edit a PNG.
- **Icon composition.** S in ink `#22262f`, 62% of the tile height, centred; gradient
  `linear-gradient(45deg, #764ba2, #9d5fd8, #667eea, #4facfe)` (the page-wash palette minus the
  magenta stop, drawn bottom-left → top-right like iOS `AnimatedGradient`). Square full-bleed
  where the OS masks (`AppIcon-1024`, `apple-touch-icon`, PWA 192/512, onboarding tile); 20%
  corner radius with transparent corners where nothing masks (`favicon.svg/.png/.ico`, Chrome
  extension 16/32/48/128).
- **Web.** `StashWordmark.tsx` carries the new paths (same `className`/`currentColor` contract,
  `aspectRatio` updated); every caller keeps its height class. `public/` favicon set,
  `apple-touch-icon`, `icon-192/512`, `favicon.ico` (16/32/48 PNG entries) regenerated; `og.jpg`
  re-lettered in place (same art, new wordmark at the old one's spot and height, ink sampled
  from the old lettering).
- **Chrome extension.** `icons/` regenerated from the shared source (`icons/icon-src.html`
  removed; README points at `brand/`). The sign-in page's `<h1>Stash</h1>` is now the wordmark
  SVG at 26px (`h1.wordmark`).
- **iOS.** `StashWordmark.imageset/stash-wordmark.svg` (app + share extension) replaced with the
  new vector — still template-rendered with `preserves-vector-representation`, so `StashHeader`
  (20pt), `SignInView` (28pt) and `SplashView` (40pt) need no code change; they just get
  narrower. `AppIcon-1024.png` (app + share extension) and `onboarding.stashTile@2x/@3x` (the
  share-sheet tutorial's tile, 180/270px) regenerated from the same source.
- **Not in this change.** The macOS menubar app (separate `stash-mac` repo) still carries its
  legacy icons — `brand/icon-src.html` at `#size=1024` is the master to hand it. App Store and
  Chrome Web Store listing screenshots still show the old wordmark and need retakes.
- **DESIGN.md.** "Brand elements are flat" rewritten as **Logo**: the wordmark stays
  single-colour; the app icon is the one sanctioned gradient mark (2026-09-03 note superseded).
- Review sheet: `docs/superpowers/prototypes/2026-09-15-logo-refresh.html` (+ `.png`) — every
  shipped size old → new, three gradient reads (B chosen), S-scale and ink comparisons.

## 2026-09-14 · Search + Ask Stash surface and boost the user's notes

Backend-only; nothing visual changes on any client, but every client that
renders search results or builds an Ask-style agent should know about the
new field. Diagnosis: a note ("potential investor for Stash") on a long
LinkedIn link WAS indexed, but each search result carries one snippet = the
best-matching chunk, so a page-body chunk about other investors took the
slot and the model never saw the note. Fix, three parts:

- **Contract:** `POST /search-items` (and MCP `search_stash`) results gain
  `notes` — the user's note as plain text (Novel/TipTap JSON and legacy HTML
  rendered to words; ≤280 chars; `null` when empty), independent of
  `snippet`. Existing fields unchanged; additive. iOS decoders that ignore
  unknown keys need nothing; a client showing server results may render it.
- **Ranking:** `hybrid_search_content` v4 (migration
  `20260914000000_hybrid_search_v4_notes.sql`) returns `item_content` and
  adds a third RRF list over the notes alone (`notes_weight`, default 1.5),
  so an item whose note matches outranks items that merely mention the words
  in captured text. New SQL helper `notes_plain_text(text)` turns the JSON
  document into words so its keys never become search lexemes.
- **Ask Stash (`chat-with-all-content`):** each `search_stash` result block
  now carries a `Notes:` line; `get_item` renders notes as words instead of
  raw JSON and is logged to `retrieval_log` (tool `get_item`, filters
  `{id}`); the system prompt tells the model to search with the user's own
  words before browsing the catalog and to treat a matching note as decisive.
- **Shared helper:** `supabase/functions/_shared/notes.ts` (`plainNotes`,
  `notesSnippet`) mirrors the web's `contentExtractor.ts`; iOS has the same
  logic in `renderTipTap` — keep the three in step.
- **Also fixed while verifying:** the model regularly sends `types:["note"]`
  (not a storage type) and the RPC failed with an enum error, costing an
  agent round. `coerceSearchTypes` (`_shared/search.ts`) maps model
  vocabulary onto storage types (`note` → text+audio, `photo` → image,
  `pdf`/`file` → document, `url`/`article` → link) and drops the rest;
  failed searches are now logged to `retrieval_log` with `filters.error`.

## 2026-09-13 · iOS housekeeping mirror + App Store readiness (plan 14)

Mirrors the 2026-09-13 web housekeeping changes (`docs/2026-09-13-housekeeping-handoff.md`)
into the native app and closes the engineering gaps standing between TestFlight and an App
Store 1.0 submission. iOS-only entry — the web side of housekeeping is documented in the
handoff doc above, not repeated here. Version 1.0, build 10.

- **Card notes on iOS.** Empty-content cards show an explicit "Add a note" affordance
  (`card.addNote`, plus-glyph, in the old chip area); cards with a note are tappable
  (`card.note`) with a straight, square-ended 2pt violet-600 fill rule along the left edge
  (only the right corners of the hover surface rounded) and clamp to five lines outside
  editing. Tapping opens a compact `.medium`-detent sheet (`CardNoteEditorSheet`) built on the
  same `NotesEditorModel` the detail sheet's Notes tab uses: plain-text notes edit in place;
  rich (TipTap) notes render the existing document read-only above an append-only draft field
  — `content` is never flattened to plain text, appends go through the existing
  `appendNoteParagraph` merge path. Explicit Save/Cancel; native Return inserts a newline;
  Cancel discards; an unchanged Save just closes. A confirmed save shows a 450ms violet-300
  @0.25→0 wash plus a 2s checkmark/"Saved" acknowledgment (static under Reduce Motion);
  failure keeps the draft in the sheet with an inline error. Both hit areas use
  `.highPriorityGesture` so the whole-card tap (open detail sheet) still wins everywhere else.
  VoiceOver: note = button "Edit note", add = button "Add a note".
- **Montreal card headings.** New `StashType.cardTitle()` token — PP Neue Montreal medium
  20pt, tracking −0.014em — replaces `editorialTitle()` on library card titles (web parity;
  the detail sheet's own title token is unaffected). Library grid gutter 14pt → 24pt,
  natural-height cards (no masonry on the phone's single column).
- **Notes editor footprint.** `NotesEditor` frame `minHeight 80/maxHeight 220` →
  `minHeight 44/maxHeight 110` via `@ScaledMetric` (web's 150px parity, roughly halved),
  scrollable inside, grows with Dynamic Type, keyboard stays visible.
- **"Transcribe with speakers"** — text button in `ItemDetailContent`'s Transcript header
  (`detail.transcribeSpeakers`, audio/video items with a stored media file only). Resolves the
  stored media URL the same way the player does, invokes `transcribe-audio` with the same
  `{audioUrl, fileName}` body web sends, then patches only `page_body` + `description` via new
  `StashKit.TranscriptionService`, refreshes embeddings, and refreshes the item store.
  `content` is never touched; the previous transcript is preserved on failure; copy never
  claims real speaker names (labels come from the server's diarization). Busy state disables
  the button ("Transcribing…"); errors surface inline under the header.
- **Account deletion (Settings).** New `DeleteAccountSection` after Sign Out
  (`settings.deleteAccount`) → sheet with consequence copy mirroring
  `src/components/settings/DeleteAccountSection.tsx`, a "Type DELETE to confirm" field, and a
  destructive "Delete everything" button (`settings.deleteAccount.confirm`) enabled only on an
  exact match. Calls the already-deployed `delete-account` edge function
  (`POST` + bearer token, no body → `200 {deleted, storageObjects, stripe}` / `401` / `403` /
  `500`). On success: local purge (Outbox cleared outright, staged files discarded, App Group
  `subscription.canAddContent` cache cleared, Keychain session signed out local-scope) and
  land on sign-in with a one-line "Your account was deleted." banner
  (`auth.deletedBanner`). Failure leaves the account intact with an inline error.
  `StashKit.AccountDeleter` is unit-tested against 200/401/403/500 response shapes.
- **Phone storage bug fixed (punch-list A8).** iOS sign-up and the Settings phone section now
  store `user_phone_numbers.phone_number` as bare-digit E.164-without-plus, matching web's
  `src/utils/phoneNumber.ts` exactly (US 10 digits → prepend `1`; `1` + 10 digits kept; anything
  else rejected). New `StashKit.PhoneNumber.normalize` ported with parity tests; wired into
  `SessionStore.signUp` and `PhoneSection`'s stored (not display) value. Previously, sign-up
  stored a bare-digit number with no country-code prefix while Settings normalized it — the two
  paths diverged for the same real number.
  - Server paywall (B5) is now live for real: adding content while `canAddContent == false`
    returns `403 {error: "subscription_required"}`. Outbox now **parks** an entry on that
    specific 403 instead of retrying it (no attempt burned, no drain loop); the Add tab's
    existing gate strip covers the UI. Parked entries auto-drain (`Outbox.unparkAll()`) on the
    next `SubscriptionStore` refresh that reports `canAddContent == true`. This makes the
    lapsed `will+uitest` fixture account hit a *live* gate on any add-note flow — see
    "Standing UI-test failures" below.
- **Privacy manifests** (audit H1): `ios/Stash/PrivacyInfo.xcprivacy` +
  `ios/StashShareExtension/PrivacyInfo.xcprivacy`, declared as `project.yml` resources.
  `NSPrivacyTracking: false`. Declared required-reason APIs: UserDefaults (`CA92.1`), file
  timestamp (`C617.1`, from Outbox/StagedFileStore reading modification dates). Declared
  collected data types (linked to identity, not used for tracking): email, phone number, user
  content (photos/video, audio, other), precise location downgraded to **coarse**
  (`kCLLocationAccuracyHundredMeters`, app-functionality, opt-in), user ID.
- **Version 1.0, build 10.** `MARKETING_VERSION` `0.1.0` → `1.0`, `CURRENT_PROJECT_VERSION` →
  `10`. App Store metadata (description, keywords, promotional text, support/marketing/
  privacy URLs, categories Productivity/Utilities, copyright, age rating all NONE/false) and
  the 6 required 6.9" screenshots (View library, detail sheet, Add tab, Ask with a citation,
  share sheet, share-tutorial panel 2 — captured against the seeded `will+review@dzierson.com`
  account) are pushed to App Store Connect via `ios/scripts/asc-api.sh`; full field-by-field
  record in `docs/app-store/2026-09-13-listing.md` and `docs/RELEASING.md`'s "App Store
  submission (1.0)" section.
- **Still manual (Will):** App Privacy nutrition-label answers (not settable via the ASC API;
  exact answers in `docs/app-store/2026-09-13-app-privacy-answers.md`), the final "Submit for
  Review" click, and a Stripe comp for the `will+review` demo account so it doesn't lapse
  mid-review.
- **Standing UI-test failures growing while `will+uitest` is lapsed:** with the paywall gate
  now live in production, every UI-test flow that adds a note (not just fresh captures) on
  that fixture account now hits the same `403 subscription_required` gate. The standing
  failure set (previously `testCaptureSmoke`/`testLocationPinSmoke`/`testAskSmoke`) grows to
  include tests that add a card note as a setup step — confirm each failure is happening ON
  the gate (a `403` from `add-note`/capture), not a genuine regression, before treating it as
  expected. Resolves once Will comps `will+uitest`'s subscription.
- **Removed-banner check:** the native app has no recurring paste/drop tutorial banner to
  remove (only the Ask composer placeholder) — nothing to do here.
- **Fix wave B (opus whole-branch review, pre-App-Store-submission build):** share-extension
  gate copy no longer names `gostash.it` ("Subscribe on gostash.it to add items" → "An active
  subscription is required to save new items.", App Review 3.1.1/3.1.3(f) — the composer's and
  Ask's own "Subscribe…"/"…needs an active trial or subscription." copy and Settings' "Manage
  on gostash.it" link are unaffected, Will's call). A foreground `CaptureViewModel.submit()`
  that gets a live `403 subscription_required` now enqueues straight to `.parked` (not
  `.pending`), and the Add tab's outbox badge excludes parked entries — both were previously
  only true after the *next* `Outbox.drain` pass rediscovered the same 403. Parked entries also
  unpark on the app's own launch/foreground `SubscriptionStore.refresh()` (not just the Add
  tab's own `.onChange`), so resubscribing on the web drains without ever opening Add.
  `ItemCardView`'s `TimelineView(.periodic(by: 30))` now only wraps a card whose
  `attributes.enrichment` key actually exists — a card that can never dim/pill no longer pays
  for a perpetual 30s re-render. The detail Notes editor's "Editing note"/"Adds when you tap
  Done…" hint only shows while focused or with draft content, not under a standing empty field.
  **Delete-account sheet presentation bug (product bug, not test-only):**
  `AccountUITests.testDeleteAccountEndToEnd` failed 5/5 under the full UI suite (root cause:
  `DeleteAccountSection`'s sheet was presented from its own `List` row; `AccountSection`'s
  async `loadUsername()` resolving on a brand-new account reflowed the List mid-presentation
  and a second row-hosted presentation attempt collided with it — UIKit tore down the loser
  ~1.1s after it opened). Fixed by moving the sheet's `@State`/`.sheet(isPresented:)` up to
  `SettingsView`'s own `List` root (alongside the pre-existing sign-out confirmation and
  How-to-Stash cover, both already root-anchored and never affected) — `DeleteAccountSection`
  now only flips a `@Binding`; the confirm UI itself moved into a new `DeleteAccountConfirmSheet`
  with its own local state, using `.interactiveDismissDisabled(isDeleting)` in place of the old
  custom dismiss-guard `Binding`.
- **App Store metadata correction + Search History disclosure:** the ASC description and
  review notes had external-purchase-steering language (App Review 3.1.3(f)) — cut. Review
  notes' account-deletion path corrected. Ask conversation history (questions + answers
  persisted server-side, revisited via the Ask header's history icon) is now declared as
  **Search History** (App Functionality only, no tracking) in both `PrivacyInfo.xcprivacy`
  manifests and `docs/app-store/2026-09-13-app-privacy-answers.md` — previously omitted.
  All six 6.9" App Store screenshots retaken with a non-charging status bar and
  keyboard-free composer/Ask frames; 01 now leads with a real photo (not a no-speech voice
  note) and 05 uses nasa.gov (not example.com) — all COMPLETE in ASC's screenshot set.

Spec: `docs/superpowers/plans/2026-09-13-ios-plan-14-housekeeping-mirror-and-app-store-readiness.md`.
Progress ledger with every decision: `.superpowers/sdd/plan-14/progress.md`.

---

## 2026-09-09 · Long recordings transcribe fully, asynchronously (all platforms)

Spec `docs/superpowers/specs/2026-09-09-long-audio-transcription-design.md`.
Root cause: OpenAI caps transcription uploads at 25 MiB. A 44-minute m4a
(37.7 MB) was rejected twice and the web wrote a description guessed from
the filename; no audio/video item has ever had a `summary`. Now every
audio/video item gets a transcript, summary, card blurb and AI title
regardless of length — asynchronously, with visible status.

- **Contract — `attributes.media.transcript`** (additive; whole-blob
  read-merge-write, preserve unknown keys):
  `{ status: 'pending' | 'processing' | 'done' | 'failed',
  source?: 'openai:<model>', chunks_total?, chunks_done?, attempts?,
  updated_at?, error?: 'download_failed' | 'no_audio_track' |
  'unsupported_container' | 'transcription_failed' | 'no_speech' }`.
  Written by the server (`transcribe-audio`, `add-file`) and, for the
  initial `pending`, by the web save path. Lanes unchanged: transcript →
  `page_body` (fills in chunk by chunk; cap 200,000 chars); card blurb →
  `description` (**null until the transcript exists — never a filename
  guess**); long AI summary → `summary` (new for recordings: topics in
  order, decisions, action items, open questions; ≤ ~300 words). Title:
  filename-shaped titles are replaced from the transcript by the job
  (existing 2026-08-26 policy, `KEEP_FILENAME` respected).
- **Endpoint — `POST /transcribe-audio`** (gateway `verify_jwt` off; auth
  in-function). `{ itemId }` with the owner's JWT or the service role →
  `202 { accepted: true, itemId }`; the work continues server-side and lands
  via realtime. Files over 24 MiB are split **without re-encoding** by
  reading the m4a/mp4/mov sample tables (`_shared/mp4Audio.ts`) into
  ≤ 24 MiB / ≤ 20-minute chunks; other containers over the cap fail with
  `unsupported_container`. `{ sweep: true }` + `x-cron-secret` (pg_cron,
  every 10 min) resumes stalled jobs and retries failures, 3 attempts max.
  The chip's preview call `{ audioUrl, fileName }` → `{ transcription,
  description }` is unchanged for files ≤ 24 MiB; larger files answer
  `{ deferred: true }`.
- **`add-file`** now writes `media.kind`, `media.file_name`,
  `transcript.status = 'pending'` and a baseline embedding, then starts the
  job. iOS / extension callers change nothing.
- **Web:** save inserts audio/video immediately (description null, status
  pending) and starts the job fire-and-forget, like `analyze-image`; the
  chip skips the inline preview above 24 MiB. Detail sheet Transcript tab
  (`src/utils/transcriptStatus.ts` for the copy): "Transcribing… part N of
  M" above the partial text as chunks land, "Transcribing… long recordings
  can take a few minutes." before the first chunk, a per-`error` reason when
  failed (with "It will be retried automatically." while attempts remain),
  else the existing "No transcript available". Cards keep expecting
  `description` for audio/video; the assembling chip retires honestly at
  its 2.5-minute window for long recordings.
- **iOS to mirror:** decode `media.transcript` (StashKit `MediaAttributes`
  drops unknown *nested* keys on a round trip today — add the field so a
  media edit can't erase job state), render the same Transcript-tab states
  with the copy above, and don't treat a missing description as a stalled
  capture for long recordings.

## 2026-09-08 · Admin dashboard (web-only, temporary)

Spec `docs/superpowers/specs/2026-09-08-admin-dashboard-design.md`. Internal
tooling for the alpha: no member-facing behavior changes and nothing for
iOS / macOS / the extension to mirror. Logged because it adds a table, an
RPC and an edge function that other agents will meet in the schema.

- **Gate:** `public.admin_users` (RLS: read your own row only; service-role
  writes only). The migration seeds Will's account. **Kill switch:**
  `DELETE FROM public.admin_users;` hides the menu entry and makes every
  admin call 403. Agent (MCP) tokens are fenced from it like every table.
- **Data:** `public.admin_user_stats()` (SECURITY DEFINER, service role
  only) joins `auth.users` + `auth.audit_log_entries` + `user_profiles` +
  `items`. Per account: email, username / display name, joined, last login,
  explicit login count (`login` audit entries), active days (distinct UTC
  days with a login *or* a token refresh), last active, item count, items
  in the last 7 days, last saved, items by type.
- **Endpoint:** `POST /functions/v1/admin-stats` (JWT + apikey; gateway
  `verify_jwt` on, then an `admin_users` check). `{ action: 'users' }` →
  `{ users: [...] }`; `{ action: 'items', user_id }` → `{ user, items }`
  with the same columns the library grid loads (`ITEM_LIST_COLUMN_NAMES` +
  `user_id`, parity-tested). 401 / 403 / 400 / 404 as JSON `{ error }`.
  Every admin read is logged in the function logs (admin id → target id).
- **Web:** the avatar menu gains "Admin" (Lucide `Gauge`) for admins only.
  `/admin` = four stat tiles (members, active in the last 7 days, items
  saved, saved in the last 7 days) and a sortable member table; name and
  email link to the member page; a "Hide test accounts" checkbox (on by
  default) hides the `will+…` fixtures; anonymous try-it sessions are never
  listed, only counted. `/admin/users/:userId` = identity strip with type
  chips, search and type pills over `ContentGrid` in **public-view mode**: a
  read-only recreation of the member's grid (no card menu, edit, delete,
  reminders, comments or privacy controls; link titles open the URL).
  Non-admins are sent to `/home`.
- **Privacy posture:** a deliberate, time-boxed exception to "only you see
  your stash" while every member is a known early tester. Remove with the
  kill switch above once there is a critical mass of members.

---

## 2026-09-07 · Server-side paywall (launch punch list B5)

Backend-only; no visual change on web. Every client is affected by the new
`403`.

- **Capture and Ask now enforce the subscription on the server.** `add-note`,
  `add-url`, `add-file` and `chat-with-all-content` answer
  `403 { "error": "subscription_required", "message": "Your trial has ended. Add a payment method at gostash.it/settings to keep capturing and asking.", "status": "<stripe status>" }`
  for a lapsed account. The rule mirrors the web client's gate
  (`src/hooks/useSubscription.tsx`): blocked only on a definitive lapsed
  Stripe status (`paused`, `canceled`, `unpaid`, `past_due`, `incomplete`,
  `incomplete_expired`); `trialing`, `active`, no-subscription-yet (`none`)
  and unknown all pass, so a brand-new account's first save is never blocked
  by the signup → trial race, and a Stripe outage degrades to the last known
  answer rather than a lock-out. Decision module
  `supabase/functions/_shared/entitlement.ts` (unit-tested, import-free);
  Deno adapter `entitlementGate.ts`.
- **`subscription_status_cache`** (migration `20260907130000`): a
  service-role-only table (RLS on, no policies, no client grants) holding each
  user's last Stripe status + customer id. Written by `check-subscription` on
  every call (the web client polls it every 30 s), by the gate itself when the
  row is missing or older than 5 minutes (one Stripe round-trip, then cached),
  and by the new `stripe-webhook`.
- **`stripe-webhook`** (deployed, inert until configured): verifies the Stripe
  signature and upserts the cache on `customer.subscription.*` events, so a
  trial ending or a payment failing takes effect immediately instead of on the
  next poll. Will's step: register
  `https://uqqsgmwkvslaomzxptnp.supabase.co/functions/v1/stripe-webhook` in
  the Stripe dashboard for those events and run
  `supabase secrets set STRIPE_WEBHOOK_SECRET=whsec_… --project-ref uqqsgmwkvslaomzxptnp`.
  Until then the function answers `503` and polling alone feeds the cache.
- **Clients**: web already blocks before calling (banner + disabled capture),
  so users see no change. iOS and the extension should map
  `403 subscription_required` to their existing "trial ended — subscribe on
  gostash.it" copy instead of a generic failure (the extension currently shows
  the bare `!` badge — punch list B13).

## 2026-09-07 · Hashtag-free link titles (platform) + iOS Ask composer cleanup

Will's notes, same day: LinkedIn titles "often have hashtags in the titles —
let's try to disambiguate these further"; Ask tab font mismatch between sent
messages and replies; remove the mic; top-align Send on a multi-line composer.

- **Link titles lose their hashtags at capture — all clients, no client
  change needed.** `add-url` (quick pass and the deep `enrichAfterResponse`
  pass) and `extract-link-metadata` now run scraped titles through
  `cleanMetaTitle(title, description)` from
  `supabase/functions/_shared/textHygiene.ts` (mirrored in
  `src/utils/textHygiene.ts`; `src/utils/textHygiene.test.ts` covers the
  rules and asserts the two copies are byte-identical from `NAMED_ENTITIES`
  on). Caller-supplied titles are still stored verbatim. Rules:
  - A tag is `#` + a letter at a word start — `C#`, `#42`, `Issue #3` are
    untouched.
  - Two or more tags in a row are a tag block and are removed wherever they
    sit (`…Link in bio. #maven #ai #llms` → `…Link in bio.`; `#hiring #jobs
    We're looking…` → `We're looking…`; a block inside Instagram's closing
    quote tightens back onto the quote).
  - A lone tag closing a segment is removed; a lone tag inside prose keeps
    its word (`from #Stanford examines` → `from Stanford examines`).
  - Titles are treated as ` | ` segments (LinkedIn's `lead | Author | 13
    comments`): the engagement tail (`N comments/reactions/likes/reposts`)
    is dropped, and a lead segment that was *only* tags is replaced by the
    first sentence of `description` (the post body), capped at 90 chars at a
    word boundary with `…`. Sentence detection skips initials (`Fabio A.`)
    and common abbreviations; a description that is just a URL yields no
    lead. Example: `#aiagents #opensource | André Lindenberg | 13 comments`
    + body "OfficeCLI gives an AI agent a single binary…" →
    `OfficeCLI gives an AI agent a single binary that reads, writes and
    creates Word, Excel… | André Lindenberg`.
  - If nothing readable is left, the title falls back exactly as before (the
    URL in `add-url`, the hostname in `extract-link-metadata`).
- **Backfill (2026-09-07):** the 16 existing `type='link'` rows on
  will@dzierson.com whose title carried a hashtag were rewritten in place
  with the same helper (before/after log kept with the session); the 3
  matching rows on another account were deliberately left alone.
- **iOS Ask tab** (`ios/Stash/Ask/`):
  - User bubbles and the composer `TextField` now use `StashType.body()`
    with the compact `14 * 0.35` line spacing — the same face and rhythm
    `MarkdownBlocksView(compact: true)` gives assistant replies. Both were
    bare SwiftUI text before, i.e. SF at the system size next to Neue
    Montreal 14.
  - The mic / live-dictation button is gone: `DictationController.swift`,
    StashKit's `DictationMerge.swift` (+ its tests) and
    `NSSpeechRecognitionUsageDescription` (project.yml + Info.plist) are
    removed; `NSMicrophoneUsageDescription` now reads "voice notes" only —
    voice capture stays on the Add tab's voice memo. `ChatComposerBar` no
    longer takes a `dictation` parameter and `ChatBubble` no longer takes
    `isDictating` (the speaker button is never disabled for it). The
    `ask.mic` identifier no longer exists; `ask.input` / `ask.send` are
    unchanged.
  - The composer `HStack` is `.top`-aligned (was `.bottom`), so the send
    circle stays on the first line while the field grows to its four-line
    cap.

---

## 2026-09-07 · Password reset + account deletion (launch punch list B1, B2)

Web + backend round; iOS and the extension get links only. Punch list:
`docs/gtm/2026-09-07-v1-launch-punch-list.md`.

- **Password reset (web)** — "Forgot password?" under the sign-in form
  (`src/pages/Auth.tsx`) swaps the card to an in-place reset form; the tabs
  hide while it is showing. `?mode=reset` deep-links straight to it (the
  extension and iOS use this). Submitting calls
  `supabase.auth.resetPasswordForEmail(email, { redirectTo: origin + '/reset-password' })`
  and then shows the same confirmation whether or not the address exists —
  "Check your email · If an account exists for … a reset link is on its way.
  It expires in an hour." (no account enumeration). A GoTrue throttle (HTTP
  429 / "For security purposes…") is surfaced as "Wait a moment before trying
  again" rather than the raw message.
- **`/reset-password` (new route, `src/pages/ResetPassword.tsx`)** — the
  recovery-email landing page. supabase-js turns the `#access_token…&type=recovery`
  hash into a session on load; the page waits for that (2.5 s grace), then
  shows New password + Confirm (min 8 characters, client-side; server minimum
  is 6) → `auth.updateUser({ password })` → toast "Password updated" →
  `/home`, signed in. A dead link (`#error_code=otp_expired…` in the hash, or
  no session inside the grace period) shows "This reset link has expired" with
  "Request a new link" → `/auth?mode=reset`.
- **Supabase auth config** (changed live via the Management API, not in
  repo): the redirect allowlist is now only `https://www.gostash.it/**`,
  `https://gostash.it/**`, `http://localhost:8080/**`, `http://127.0.0.1:8080/**`
  — the dead Lovable preview domains are gone. Recovery email subject is
  "Reset your Stash password" with plain copy. Still on Supabase's default
  mailer (no custom SMTP): reset mail is capped at 2 sends/hour project-wide
  until Resend is wired as the auth SMTP (punch list B4).
- **Extension** — `extension/signin.html` gains "Forgot your password? Reset
  it at gostash.it" → `https://www.gostash.it/auth?mode=reset` (new tab).
- **iOS** — `SignInView` gains a "Forgot password?" `Link` (identifier
  `auth.forgotPassword`, `StashType.meta` / `StashColor.muted`, underlined)
  under the sign-in button, sign-in tab only, opening the same web URL. No
  native reset flow: recovery is email-driven and the link lands on web.
- **Account deletion** — Settings → Your Information → new "Delete account"
  card (`src/components/settings/DeleteAccountSection.tsx`, hairline tinted
  `#c93a3a`/25): destructive "Delete my account" → AlertDialog "Delete your
  account?" → type `DELETE` (exact, case-sensitive) enables "Delete
  everything" → `POST delete-account` → local sign-out → `/` with toast "Your
  account has been deleted". A server refusal keeps the account and toasts
  the reason. Wire contract in `docs/PLATFORM_API.md` → "Account deletion".
- **Backend** — migration `20260907120000_account_deletion_cascades`:
  `items.user_id` and `conversations.user_id` now cascade from `auth.users`
  (they were NO ACTION, which is why deleting a user who owned anything
  500'd); `chat_feedback`, `card_feedback`, `pending_intents`, `retrieval_log`
  gain cascading FKs (orphans purged first). New edge function
  `delete-account` (JWT required, agent tokens refused): cancels every live
  Stripe subscription on the customer(s) with the user's email (customer kept,
  tagged `stash_account_deleted_at`), removes `stash-media/<user_id>/**` via
  the storage API, then `auth.admin.deleteUser`. Steps run in that order so a
  failure part-way is retryable with the account intact.
- **Privacy policy** — "Deleting your data" now describes the in-app path
  instead of "email us"; `lastUpdated` bumped to September 7, 2026.
- **iOS to mirror (App Store 5.1.1(v))** — a Settings → "Delete account" row
  with the same type-`DELETE` gate calling `delete-account`; on success clear
  the session (`SessionStore`) and return to sign-in. Not in this cut.

---

## 2026-09-07 · iOS share tutorial carousel (plan 13)

iOS-only round; no web changes. Plan:
`docs/superpowers/plans/2026-09-07-ios-plan-13-share-tutorial-carousel.md`.
Full outcome (commits, suites, decisions): plan's own Outcome section +
`.superpowers/sdd/plan-13/progress.md`.

- **"How to easily stash" is now a three-panel paged carousel**, replacing
  plan 12's single-card, three-column-strip version
  (`ios/Stash/Onboarding/HowToStashView.swift`). `TabView(selection:)` in
  `.page(indexDisplayMode: .never)` style with custom dots (active 24×6
  violet600 capsule, inactive 6pt faint circle). Panel copy (final, from the
  approved HTML prototype
  `docs/superpowers/prototypes/2026-09-07-ios-share-tutorial-swipe.html`):
  persistent title "How to easily stash" + lead "Save from any app: tap
  Share, then Stash."; kicker `STEP N`.
  - **Panel 1** "Look for the share button" / "In Safari, Photos, or any
    app, tap Share." — art is the iOS `square.and.arrow.up` Share glyph.
  - **Panel 2** "Pick Stash" / "Choose Stash in the share sheet." / hint
    "Don't see Stash? Tap More, then add Stash to your favorites." — art is
    a natively drawn mock share sheet with a glowing Stash tile (real app
    icon via a new `onboarding.stashTile` imageset) among stand-in rows.
  - **Panel 3** "Add a note, save" / "Add an optional note, then Save.
    Stash does the rest." — the plan-12 "subscribe to add items" panel is
    removed; art is the existing ungated `onboarding.step3` capture.
  - `onboarding.step1`/`onboarding.step2` imagesets deleted (no longer
    referenced).
- **Button semantics**: primary button is `onboarding.gotIt` (label "Next"
  on panels 1–2, "Got it" on panel 3); `onboarding.skip` is a muted text
  link. **Both Got It and Skip mark `onboarding.howToStash.seen`** — unlike
  plan 12, Skip is not a "remind me later." The deferred-path plumbing
  (`markHowToStashDeferred`/`clearHowToStashDeferred`/
  `isHowToStashDeferred` in `OnboardingState`) is retained in code for
  Settings/relaunch logic even though no button currently drives it; the
  screen stays reachable any time from Settings → "How to stash."
- **One documented non-token color**: panel 1's Share glyph uses
  `Color(uiColor: .systemBlue)` rather than a Stash token, deliberately — it
  is quoting the OS's own Share-sheet icon color, which the user is meant to
  visually match against their own share sheet.
- **Native mock share sheet** (panel 2): a `MockShareSheet` view (wash
  sheet, grabber, three app tiles — a Reminders stand-in, the real Stash
  icon, and "More" — then a grouped action list) with the Stash tile ringed
  in 1px violet600 and a pulsing violet300 glow (radius 6→14pt, 1.6s
  autoreverse; static at radius 10 when `accessibilityReduceMotion` is on).
- **Home-indicator gesture-zone lesson** (found and fixed during
  implementation, worth carrying to any platform with a similar bottom-of-
  screen gesture strip): a tappable text link (here, `onboarding.skip`)
  placed too close to the bottom edge on a Face-ID iPhone can land inside
  the zone iOS reserves for the home-indicator swipe. XCUITest still reports
  the element `hittable`, but the OS swallows the touch before the app ever
  sees it — the tap *looks* like it worked (no error, and the tab bar
  underneath a `.fullScreenCover` is still present in the accessibility
  tree while covered) but the app-side handler never runs, so state that
  should have been persisted silently isn't. Keep bottom-anchored tappable
  text at least ~40pt clear of the bottom edge on those devices. Fixed here
  by shrinking the card (`panelHeight` 490pt) rather than moving the button.
- **SE-width note**: on a 375×667 iPhone SE the card content runs to
  roughly 700pt tall — taller than the screen — but the card is inside a
  `ScrollView`, so it scrolls rather than clips; no layout change needed for
  that screen size.

---

## 2026-09-06 · Reminders: "bring this back in 1 / 3 / 5 days" — web + platform (iOS + email follow)

Spec `docs/superpowers/specs/2026-09-06-reminders-design.md`; plans
`docs/superpowers/plans/2026-09-06-reminders-{1-backend-web,2-ios,3-email}.md`.

- **Contract (all clients):** three columns on `items` — `remind_at`,
  `reminder_cleared_at`, `reminder_notified_at`. State is derived with a 24h
  window (`none / scheduled / due / cleared`); see `docs/PLATFORM_API.md`
  → Reminders for the table, the two write shapes, and the due-items query.
  Capture endpoints accept an optional top-level `remind_at`; invalid values
  are ignored, never a 4xx.
- **Ordering rule:** due items first (`remind_at` asc), then chronological.
  Skipped while a server search rank is active.
- **Web:** footer chip after the date — scheduled `in 3d` (muted, clock),
  due `Due` (violet, bell) with an always-visible × "Remove reminder"; a
  violet `Due` pill joins the hero-corner badge zone. Card menu gains
  "Remind me…" (In 1 / 3 / 5 days), "Change reminder…" and "Remove reminder"
  when one is active. None of it renders in public views. One `NowProvider`
  clock per grid (60 s tick + visibilitychange) drives state.
- **Backend + email (shipped):** `reminder-digest` runs 13:00 UTC; one email
  per user per day listing due reminders (title → content excerpt → host →
  type fallback; "Saved Sep 3 · reminder for today"; deep link per item);
  signed opt-out link (confirmation page → POST; RFC 8058 one-click headers)
  + Settings → Account "Email me when reminders are due" switch
  (`user_preferences.reminder_emails`). Sent through Resend from
  `reminders@mail.gostash.it`. Per-user timezone is a later refinement.
- **iOS (plan 2):** share-sheet chips `1 day · 3 days · 5 days` above Save;
  View tab badge = due count; due block at the top of the grid; same footer
  chip + Due overlay + dismiss.
- **Not in this cut:** inferred resurfacing, Keep/Done/Let go, push, custom
  dates, per-user timezone, controls in the in-app composer / extension /
  web capture box.

---

## 2026-09-07 · iOS feedback round 3 (plan 12)

iOS-only round (Will's first on-device pass); no web changes. Plan:
`docs/superpowers/plans/2026-09-06-ios-plan-12-feedback-round-3.md`. Full
outcome (commits, suites, decisions, carried items): plan's own Outcome
section + `.superpowers/sdd/plan-12/progress.md`.

- **Keyboard-control decision — iOS 26's floating toolbar retired app-wide.**
  The system's `.toolbar(placement: .keyboard)` floating accessory (used in
  plan 8/11 for the composer's dismiss-keyboard control) proved unfixable at
  narrow widths: on iOS 26 it renders as a free-floating capsule whose width
  is driven by its content, not the card column, so any control wide enough
  to tap comfortably overflowed the card (and on iPhone SE, the screen).
  Replaced with two surface-specific controls instead of one shared
  mechanism: **composer** = a plain-text "Cancel" button in the card's
  top-right corner, visible only while the editor is focused
  (`capture.dismissKeyboard`) — semantics are "dismiss the keyboard only,"
  the draft is kept, not a form-cancel; **detail** = a small round
  keyboard-dismiss icon in the pinned footer bar (next to the autosave
  label), not the notes-section header — closer to where a user's thumb
  already is when editing. Web is unaffected; this is a native-only control
  because web has no on-screen keyboard to manage.
- **Whole-card tap regression fixed.** The link kicker's tap gesture used to
  claim its entire domain-text label as a "open in Safari" hit target; on
  compact cards the card's visual center landed on that label, so tapping
  the middle of a link card opened Safari instead of the detail sheet.
  Narrowed to a small trailing `arrow.up.right` icon only — the rest of the
  card (including the kicker row outside that icon) now falls through to the
  card's own tap → detail sheet, matching every other card type.
- **View tab**: the search pill now fades out on scroll (via a
  `UIViewRepresentable` KVO observer on the underlying `UIScrollView`'s
  `contentOffset` — SwiftUI's `PreferenceKey` scroll-offset approach proved
  dead on iOS 17 for a *live* scroll gesture, only fired on settle) instead
  of always being visible; the item-count row above the grid is removed
  entirely. Four ways to dismiss the search keyboard/pill: tapping the ×,
  tapping system Cancel, pressing return, or tapping any card.
- **Ask tab title re-added** — see the amended 2026-09-03 (plan 8) bullet
  above; this is the *second* reversal of that decision. Current state:
  "Chat with your Stash" (medium weight, 22pt), no live item count, no
  wordmark. View and Settings still have no title.
- **Add tab spacing pass** (Will: "increase the padding — things feel
  cramped"): every composer spacing value that was shared across rows scaled
  ×1.1 (margin 12→13, wordmark-area whitespace 16→18, inner horizontal
  16→18, vertical 10→11/8→9). Editor insets separately increased twice this
  round — first pass under-corrected (17pt → 16pt, the wrong direction);
  final state is `.padding(.leading, 15)` (+5pt `TextEditor` intrinsic
  `lineFragmentPadding` = ~20pt from the card's left edge) and
  `.padding(.top, 4)` (+8pt intrinsic = ~12pt from the top edge) — caret and
  placeholder now sit noticeably further from the card's corner than the
  original built-in-only inset.
- **Post-sign-in "How to easily stash" onboarding panel** (new,
  `HowToStashView`, real share-sheet step screenshots from an on-device
  capture, not mockups). Shown once per **install** (not per account) via
  two `UserDefaults.standard` flags — `onboarding.howToStash.seen` (set
  only by "Got it," permanent for the install) and
  `onboarding.howToStash.deferred` (set by "Show me later," suppresses the
  panel across cold launches but is cleared again on the next *explicit*
  sign-in — a `.signedOut → .signedIn` transition in `StashApp`, never a
  cold-launch Keychain restore). Showing rule:
  `!hasSeenHowToStash && !isHowToStashDeferred`, checked on the transition
  into `.signedIn`, held behind `SplashView`'s own completion so the splash
  animation is never interrupted. Re-openable any time from
  Settings → "How to stash" (`settings.howToStash`) regardless of either
  flag. DEBUG-only `--uitest-reset-onboarding` launch arg clears both flags
  for repeatable UI-test runs (`SessionStore.start()`). **Carried, not
  shipped this round:** Will now wants a three-panel *swipeable* tutorial
  instead of the current single static panel; an HTML prototype is up for
  his review at
  `docs/superpowers/prototypes/2026-09-07-ios-share-tutorial-swipe.html`
  before that gets built.
- **Delete-error surfacing.** The detail sheet's delete action now
  distinguishes a real "this item is already gone" outcome (PostgREST
  matched 0 rows — see the new Delete-contract note in `PLATFORM_API.md`)
  from every other failure mode: `ItemEditorError.deleteMatchedNoRows` →
  "Couldn't delete this item — it may not exist anymore or you may not have
  permission."; anything else (network failure, an unreadable response body
  — `.deleteResponseUnreadable` — or any other thrown error) → "Couldn't
  delete — try again." (plausibly transient, so "try again" is the right
  steer only for that bucket).
- **Link items with an og-image now render on the detail hero**, matching
  web's `hasImage` gate exactly. The hero gate used to be `.image`-type-only,
  which excluded `.link` items that have a scraped og-image
  (`thumbnailURL` populated) even though the library card already rendered
  that same image — widened to `(item.type == .image || item.type == .link)
  && thumbnailURL != nil`.

### Tests

`StashUITests.swift`: `testDeleteSmoke` now self-seeds its own row (creates
it, captures the id, deletes it, verifies via search-empty / pull-refresh /
a REST re-query) instead of depending on a `STASH_DELETE_MARKER` fixture set
up out-of-band. `testOnboardingPanelShowsOnceAfterSignIn` relaunches with NO
launch arguments for its main assertion (a real Keychain-restore path, not
`--uitest-reset-auth`, which would trivially satisfy "seen") plus a
Show-me-later / sign-out / sign-in branch proving the deferred flag's
lifecycle. 24 test methods total across the file; the permanent
`UITEST-FIXTURE` item count on `will+uitest@dzierson.com` grew from 5 to 10
over this round — noted for the next agent touching fixture-dependent tests,
not a regression. Wrap-time fix: `testDetailSheets` reproduced a
deterministic (not flaky — 2/2) failure at its clear-search-field step —
"Neither element nor any descendant has keyboard focus" — because this
round's search-pill dismissal work (above) now drops search focus on card
tap, so the field is no longer focused by the time the sheet is dismissed;
added a `searchField.tap()` before the clearing `typeText` to re-acquire
focus, matching every other call site in the same helper. Re-ran the full
suite twice after the fix: both runs landed on exactly the 3 standing
gate-blocked failures (`testCaptureSmoke`/`testLocationPinSmoke`/
`testAskSmoke`).

---

## 2026-09-05 · YouTube links: real thumbnail + title from the URL alone — all clients

Server-side only (`add-url`, `extract-link-metadata`, new
`_shared/youtube.ts`); no client code changes, nothing to mirror — every
platform saves through `add-url` and gets this for free.

- **What was wrong:** YouTube answers Supabase's egress IPs with HTTP 429 on
  watch pages. The YouTube oEmbed branch lived *inside* the HTML parser,
  which only ran after a successful page fetch, so from production it never
  ran. The error path's Jina rescue then returned the watch URL itself in
  the image slot, `add-url` correctly rejected it, and every YouTube card
  saved since 2026-08-22 sat on the favicon plate with `file_path = null`.
- **Now:** for any URL that carries a YouTube video id (`watch?v=`,
  `youtu.be/`, `/shorts/`, `/embed/`, `/live/`, mobile/music subdomains) the
  server resolves metadata with **no page fetch**: oEmbed for title/author
  and a HEAD-probed `i.ytimg.com` thumbnail (`maxresdefault` 1280×720 →
  `hq720` → `hqdefault` 480×360, the only one guaranteed to exist; a missing
  variant is a 404 that still carries a placeholder JPEG, so status decides).
  Both endpoints verified reachable from the cloud. The quick pass in
  `add-url` uses the same resolver, so the immediate `{ item }` response
  already carries the real title, `description` (`Watch "<title>" by <channel>
  on YouTube`), and a stored preview in `<uid>/previews/` — the card is
  finished on first paint instead of after deep enrichment. If oEmbed is
  down the thumbnail still lands and the deep pass rescues the title.
- **Contract:** unchanged. `file_path` is our own storage path (preferred)
  or, on the rare error path, a raw `i.ytimg.com` URL that verifiably served
  an image. `attributes.link.flavor = 'video'` as before.
  `strategyUsed: 'youtube-oembed'` in the enrichment response identifies
  the new path.
- **Known limits (next entry covers them):** `description` is still the
  synthetic "Watch … on YouTube" line, not the video's own description, and
  `page_body` for YouTube links is still whatever the scrape cascade found
  (YouTube's nav chrome). Both are addressed by the transcript enrichment
  spec `docs/superpowers/specs/2026-09-05-youtube-transcript-enrichment-design.md`.
- Tests: `supabase/functions/_shared/youtube.test.ts` (vitest, injected
  fetch). Deployed 2026-09-06 UTC.

## 2026-09-05 · Connect an agent (MCP server) — web

Read-only MCP server at `https://www.gostash.it/mcp` behind Supabase's OAuth
2.1 server; spec `docs/superpowers/specs/2026-09-05-mcp-server-design.md`,
plan `docs/superpowers/plans/2026-09-05-mcp-server.md`, wire contract in
`docs/PLATFORM_API.md` → "Agents (MCP)".

- **New route `/oauth/consent`** (Supabase redirects here with
  `?authorization_id=`): one card — "<Agent> wants to connect to your Stash",
  *It can* (search your stash · read saved items in full), *It can't* (add,
  edit or delete anything · export your stash · see your account or billing),
  signed-in email, "Returns to <host>" with an amber warning for loopback
  hosts, **Allow access** / **Deny**. Signed-out visitors bounce through
  `/auth?returnTo=…` and come back. Approve upserts `agent_grants`
  (`scopes = ['read']`, `revoked_at = null`) before consent is sent.
- **Settings gains a fifth tab, "Connected agents"** (lucide `Bot`): Connect
  card (URL + copy, Claude / Claude Code / other how-tos), Connected list
  (name · connected · last used · **Revoke** with confirm), Activity list
  (last 50 sentences from `agent_access_log`, e.g. "Claude searched for
  “restaurants in Saratoga” · 3 results", "Claude read “Beyond the Basics”").
  No subscription gate.
- **Library deep link:** `/home#item=<uuid>` opens that card once the library
  loads (used by agent citations); the hash is cleared afterwards.
- **Contracts for iOS/macOS** (no screens yet): read `agent_grants`
  (`revoked_at is null`) and `agent_access_log` (owner RLS); revoke = GoTrue
  `DELETE /auth/v1/user/oauth/grants?client_id=` then set `revoked_at`.
  Sentence rules: `src/utils/agentActivity.ts`.
- **Behavior change for all clients:** OAuth-issued agent tokens are rejected
  by every non-MCP edge function (403) and by RLS. Session tokens are
  unaffected. Supabase auth `site_url` is now `https://www.gostash.it` (was a
  Lovable-era `localhost:3000`).

## 2026-09-05 · Chrome extension: minimal permissions + Chrome Web Store prep (v1.2.0)

Chrome extension (`extension/`) only — user-visible behavior unchanged. Full plan:
`docs/superpowers/plans/2026-09-05-extension-cws-submission.md`.

- **Permissions narrowed**: `host_permissions` dropped from `<all_urls>` to
  `["http://*/*", "https://*/*"]` — drops `file://`/`ftp://`/other non-web
  schemes Stash never touched anyway; every real capture flow (toolbar save,
  selection note, right-click image save on any host) still works exactly as
  before. `activeTab` was evaluated per the plan but doesn't cover the actual
  behavior: the image-save flow does a credentialed cross-origin `fetch`
  straight from the service worker to whatever origin hosts the image (often
  a different origin than the page — CDN-hosted images), and `activeTab`'s
  grant only covers the invoking tab's own top-level origin. Verified via curl
  (real image CDNs send `Access-Control-Allow-Origin: *` with no
  `Access-Control-Allow-Credentials`, which fails a credentialed fetch per the
  Fetch spec) and empirically in a live loaded extension (an `activeTab`-only
  grant still failed the cross-origin image fetch; the host list succeeded,
  REST-verified, then cleaned up). `manifest.json` version bumped to `1.2.0`.
- **Store submission package added** (`extension/store/`, all committed):
  `listing.md` (name, ≤132-char summary, full description),
  `permissions-justifications.md` (per-permission paragraphs mapped to CWS's
  dashboard fields, data-use disclosure table, remote-code "No"),
  `SUBMISSION.md` (Will's click-by-click runbook — dev account, upload,
  paste-in fields, Unlisted-first recommendation), and 4 screenshots
  (1280×800): 1 real capture (signed-in options page, with a disclosed
  cosmetic patch masking the real test account's email), 2 composed and
  marked illustrative (saved-confirmation badge, native image context menu —
  both are OS-drawn browser chrome this environment couldn't screen-capture
  directly), 1 composed promo frame. `extension/scripts/package.sh` builds
  the submission zip (manifest + runtime sources + icons only).
- What remains: Will's CWS developer account + the actual dashboard
  upload/submission — nothing else is blocked.

## 2026-09-04 · iOS share sheet round 2 (plan 11)

Six of Will's design notes against the share extension's compose screen, plus one new
cross-platform color token. Ships TestFlight build 5. Full plan:
`docs/superpowers/plans/2026-09-04-ios-plan-11-share-sheet-polish.md`; outcome appended to that
file.

**2026-09-05 amendment (build 7, supersedes build 6):** the `share.gate` strip ("Subscribe on
gostash.it to add items") moved out of the scrolling content column — where it sat between the
shared-item card and the note field — into the pinned bottom bar, directly above the Save button,
per Will's direct follow-up request; the plan 9 negative-vertical-padding workaround on the strip's
background/overlay (needed only because the strip used to share a VStack with `share.note`) is
gone now that it doesn't.

- **NEW token — `success` (`#2F9E63`), DESIGN.md §Color.** First legitimate need for a green in
  the design system: confirmation icons/labels (e.g. "Saved to Stash"). **Web should adopt this
  for its own confirmation states** — previously a bare `.green`/system green with no token on
  iOS (the share sheet's saved-checkmark, Ask's "Saved to your stash" caption), no equivalent on
  web at all. The adjacent "will sync" (queued/offline) outcome state uses the existing
  `violet-600` token, not a new color — it's an active/in-progress state, not a distinct
  confirmation intent.
- **Cards and the close (X) button lose their gray hairline stroke** — fill + shadow only now
  (the compose note field, URL/image preview cards, and the circular close button). The amber
  gate-strip border is unchanged/intentional (a warning affordance, not decoration).
  1px-stroke-only rule elsewhere in the design system is untouched; this only drops strokes that
  were purely decorative on these specific surfaces.
- **Note placeholder copy:** "Add a note…" → "Optional note…" — clarifies the field is
  optional without a separate label.
- **Save button is full-width and pinned to the bottom of the screen** (standard iOS sizing: 52pt
  height, full width minus 20pt margins, `violet-600` fill, white 17pt medium label), via
  `.safeAreaInset(edge: .bottom)` so it stays above the keyboard when the note field is focused.
  Previously a smaller capsule button inline with the rest of the content. Disabled (gate-blocked)
  state swaps fill + label color (`StashColor.wash` fill, `StashColor.muted` text) rather than
  dimming opacity — a Fix round 1 correction after the initial whole-button `.opacity(0.4)` dimmed
  fill and label together into an illegible washed-lavender pill; never hidden either way — the
  account-gate messaging still needs a visible (if inert) Save target.
- **Save preview is full-width, not a thumbnail.** Image shares now render a full-content-width,
  aspect-fit hero (max ~45% of the sheet height) instead of a small square thumbnail; URL shares
  get a larger favicon (32pt) with a bigger title/domain stack. Multi-item shares keep a
  full-width hero for the first item plus the existing compact "+N" row for the rest. Still
  thumbnails from the staged file via ImageIO — never decodes the original whole file into memory.
- **Outcome icons recolored:** "Saved to Stash" checkmark is now the new `success` green
  (previously `violet-600`); "Saved — will sync" (queued/offline) clock is now `violet-600`
  (previously a bare `.orange` literal) — treats "queued to sync" as an active/in-progress state,
  not a warning.
- Accessibility identifiers unchanged throughout (`share.outcome`, `share.save`, `share.cancel`,
  `share.gate`, `share.note`).

---

## 2026-09-04 · iOS feedback round 2 (plan 10)

Fixes four pieces of Will's 2026-09-04 feedback against the iOS app. Ships
TestFlight build 4. Full plan:
`docs/superpowers/plans/2026-09-04-ios-plan-10-feedback-round-2.md`; outcome
appended to that file.

- **The "animated white box" gradient bug is fixed with a deterministic
  two-tier render, not a live SwiftUI effect.** Root cause: `AnimatedGradient`
  used a live `LinearGradient` + `.blur(radius: 40)` + `.drawingGroup()`
  (plan 8) — `.drawingGroup()` rasterizes into an offscreen buffer sized from
  the view's *pre-effect* layout bounds, and `.blur`'s bleed extends past
  those bounds; on some simulator GPU/driver paths (reproduced on iOS 17.0
  and 17.4, not 17.2/17.5/18.5/26.5 — genuinely environment-dependent) the
  un-rasterized remainder read as raw background white. Fixed by rendering
  the gradient off SwiftUI's rasterizer entirely: `UIGraphicsImageRenderer` +
  `CGGradient` draws it, `CIGaussianBlur` blurs it once into a plain
  `UIImage`, cached per view size — no live `.blur`, no `.drawingGroup()`.
  A follow-up hitch fix split this into two tiers (an instant unblurred
  first frame, the blur rendered off-main and faded in over ~0.35s) so the
  ~272ms blur cost never lands on the very first frame of a cold launch.
  **Web is unaffected** — this is an iOS-only rendering pipeline; nothing
  about the gradient's palette, direction, or CSS changed.
- **Composer card is capped at 2/3 of the tab's height, with a full-tab
  gradient wash behind and below it.** iOS's Add-tab composer used to claim
  the whole screen inside its card chrome (an open question from plan 9);
  **decision: the share sheet is the primary capture path on iOS, the in-app
  composer is secondary** (Will, 2026-09-04) — so the card caps at
  `⌊2/3 × container height⌋`, the editor scrolls internally past that, and
  the page-level gradient wash now fills the *entire* tab (not just a
  fixed-height band up top) so the space behind/below the capped card reads
  as the same ambient wash instead of flat white void. **Web's own capture
  panel is unaffected** — it has no height cap and isn't expected to grow
  one; this is iOS-only, driven by the share-sheet-primary decision above.
- **Detail sheet: one content inset, one section-header component, unified
  rhythm.** iOS's detail sheet had accumulated inconsistent horizontal
  insets and three hand-rolled section headings with different spacing.
  Normalized to a single `DetailLayout.inset` (20pt) and one `SectionHeader`
  component (micro-label + hairline, identical rhythm) used by NOTES &
  SUMMARY/TRANSCRIPT, DETAILS, and SHARING. Title/description fields also
  had their text sitting 6pt right of that inset (an artifact of their own
  hit-target padding) — now compensated so the glyphs themselves land flush
  with the eyebrow/URL bar above. **Web-only cosmetic**, no data-model or
  contract change.
- **1px-stroke rule, enforced everywhere on iOS — web should follow.** Per
  Will's "never use a 2px stroke around a button or element. 1px stroke
  only," every stroke on iOS (composer ring, sign-in focus ring, detail-sheet
  focus rings) is now 1px; `DESIGN.md` states the rule explicitly. **Web
  currently violates it in two places and should follow**: `UnifiedInputPanel`'s
  composer-ring stroke layer is 1.5px, and its input focus rings are 2px —
  both should drop to 1px to match.
- **NEW `ios/README.md`** documents that `ios/Stash.xcodeproj` is
  XcodeGen-generated and gitignored: run `cd ios && xcodegen generate` after
  every pull (and after any `project.yml` edit) before building in Xcode —
  a stale generated project is the #1 cause of "Cannot find 'StashType'"-
  style errors. `docs/RELEASING.md` gained the same note in its
  Prerequisites section.

## 2026-09-03 · iOS visual harvest (plan 9)

Re-derives the still-missing product ideas from the never-merged
`worktree-ios-plan6-visual` branch against the current `DESIGN.md` (not a
port of that branch's code). Ships TestFlight build 3. Full plan:
`docs/superpowers/plans/2026-09-03-ios-plan-9-visual-harvest.md`; outcome
appended to that file.

- **Composer is now a floating card with a focus ring — web parity.** The Add
  tab's editor no longer sits full-bleed on the gradient backdrop; it's
  wrapped in a card (`StashRadius.composer` = 6, `paper@90%` + blur) matching
  web `UnifiedInputPanel.tsx:914-926`. Idle: a neutral hairline + tempered
  shadow. Composing (focused or has content — mirrors web's `isPanelActive` /
  `hasAnyContent`, which iOS extends to count attachments too): a three-layer
  **violet-600** focus ring (stroke @ .5, 6px halo @ .08, drop shadow @ .35),
  2px lift, 1.006 scale, spring transition. **NOTE for web:** the ring recipe
  web ships today still hard-codes `rgba(139,92,246,…)` (Tailwind violet-500)
  — a legacy pre-token literal that predates DESIGN.md's `violet-600`
  (`#6d5bd0`) token. This plan retokenized the DESIGN.md bullet to name
  `violet-600` as the source of truth; web should migrate its literal to the
  token in a follow-up so the two platforms are reading the same value, not
  just visually close.
- **PP Editorial New card titles are now on iOS** (app target only — the
  share sheet renders no cards, so its target doesn't bundle the face).
  `StashType.editorialTitle()` (20pt, tight line height, 2-line clamp) is
  what DESIGN.md has specified for the card-title role since plan 7; iOS was
  still rendering Neue Montreal Medium 18 with a comment admitting no
  Editorial face was bundled. That gap is closed — `PPEditorialNew-Regular.ttf`
  converted from web's own `.woff2` via the same fontTools pipeline plan 7
  used for Neue Montreal, `UIAppFonts` entry on the `Stash` target only.
- **A leading type chip now appears on every library card**, replacing the
  old hover-only footer type badge (DESIGN.md's chips grammar: "tinted type
  chip — always visible"). Two flavors: **tinted**, reading DESIGN.md's
  type-spectrum field/text tokens, for voice note / recording / document
  (label = lowercased extension, e.g. "pdf" or "doc"; spreadsheet extensions
  — xlsx/xls/csv — read "spreadsheet") / screenshot; **neutral** (plain
  `MetaChip`, no tint) for photo / video / note / the item's link flavor
  (article/video/repo/book/"post" for social/"link" default) / collections
  ("N items"). Photos, videos, and link covers still use real imagery for
  their hero — no chip tint, matching DESIGN.md's "no field, no tint" rule.
  Chip copy is byte-identical (lowercase) to web `ContentItemContent.tsx`'s
  `typeChipFor`/`LINK_FLAVOR_LABELS`. The chips row now wraps (`FlowLayout`)
  instead of clipping when a card's chips exceed its width.
- **The raw-filename mono chip is dropped from cards entirely** — matching a
  web removal already in place. The filename still lives on iOS, just moved
  to the detail sheet's Details drawer (original filename row) instead of the
  card face. `MetaChip`'s `mono` parameter is now unused as a result (no
  remaining call site passes `mono: true`) — flagged as a carried item below,
  not removed this round.
- **Tinted plates + repo owner split.** Voice/document/screenshot card plates
  (where a flat plate exists, i.e. no real imagery) now read the same
  type-spectrum tokens as their chip. The repo link plate is a dark
  `#0d1117` slab with `owner/repo` in mono `#e6edf3`, but the owner segment
  is split into its own `#8b7bd8` (violet) run — mirrors web's two-tone repo
  treatment, not flattened to one color.
- **Gate strip is now a DESIGN.md token (NEW — web should adopt).** The
  lapsed-account capture-lock message (Add tab composer + share-sheet
  compose) is a tokenized strip: background `#fff7e6`, border `#f3d9a4`
  (1px), text `#7a4b00`, radius 12, `lock.fill` in the same text color. Web
  currently renders its own gate messaging ad hoc — DESIGN.md's new "Gate
  strip" bullet (§Color) is the recipe to point web's own gate UI at, not a
  new invention to re-derive independently.
- **Light-only rule is now enforced on the app AND the share extension.**
  DESIGN.md's light-only rule (added this plan) was initially only true on
  the main app (`StashApp.swift`'s `.preferredColorScheme(.light)`); the
  share extension runs as a separate process and wasn't covered by that
  scene-level pin, so under system Dark appearance its own chrome
  (`Color(.systemBackground)`/`tertiarySystemFill`) rendered dark under
  otherwise-light tokens. Fixed with `overrideUserInterfaceStyle = .light`
  set explicitly on `ShareViewController`'s own view and hosting view —
  verified with a dark-appearance screenshot proof (both surfaces now render
  identically regardless of system appearance).
- **`testVisualSweepScreenshots`** — a new, cheap regression guard (ported
  intent, not code, from the unmerged branch): launches signed-in, visits
  Add → Ask → View → Settings, attaches a `.keepAlways` screenshot per tab.
  Run under both light and dark system appearance as part of this plan's
  verification; every pair came back pixel-identical apart from the
  simulator clock, confirming the light lock holds everywhere the sweep
  looks.

### Outcome, decisions of record, and the old branch's disposition

See `docs/superpowers/plans/2026-09-03-ios-plan-9-visual-harvest.md`
("Outcome" section, appended by Task 4) for the full commit list, suite
counts, decisions of record (including the composer's OPEN QUESTION for
Will — whether the card should cap its full-bleed height), carried items,
and the OBSOLETE disposition of `worktree-ios-plan6-visual` with the exact
deletion commands.

---

## 2026-09-03 · iOS feedback round 1 (plan 8)

Will's device review of the plan-7 build. One plan-7 decision is reversed;
five more issues fixed. Full plan:
`docs/superpowers/plans/2026-09-03-ios-plan-8-feedback-round-1.md`.

- **Ask affordance REVERSED — header circle buttons, not footer links.** The
  plan-7 entry below said the two header icon buttons were retired in favor
  of "Start new chat · Earlier conversations" text links under the composer.
  Will's review called that a regression on a phone screen — plan 8 restores
  the header `CircleIcon` pair (`ask.newChat`/`ask.history`) as the sole
  affordance and removes the footer links entirely. **No web change** — this
  is iOS-only. The plan-7 bullet is amended in place (below) rather than left
  standing in contradiction.
- **Page-wash gradient stops are now DESIGN.md tokens** (§Color, "Page wash
  gradient"): the six-stop `-45deg` sweep web already ships (`src/index.css:
  237`, `.animated-gradient`) is now the one recipe both platforms read from
  — `#667eea, #764ba2, #9d5fd8, #c2418f, #4facfe, #38bdf8`. Web's own
  implementation is unchanged by this; if web ever revisits this gradient,
  point at the DESIGN.md block instead of re-deriving the stops. iOS draws it
  bottom-leading → top-trailing over a 2× canvas with a 40pt blur (no stop
  banding) — `StashColor.gradientStops` in `StashDesign.swift`, animated on
  sign-in, Add, View, launch splash, and the share-sheet compose screen;
  static under reduced motion.
- **No wordmark/title on View, Ask, or Settings.** `StashHeader` (the
  wordmark) is now Add-tab + share-sheet only. **Assumption, Will to
  confirm**: Add keeps the wordmark as the brand/launch moment — reversible
  in one line if wrong. Ask's title block ("Ask Stash" / live item count) is
  gone too; the intro bubble ("Ask anything about what you've saved —
  answers cite the cards they came from.") is the only per-conversation copy
  now.
  **2026-09-07 (plan 12) — REVERSED AGAIN**: Will asked for the Ask title
  back. `AskView` now shows "Chat with your Stash" (medium weight, 22pt) —
  not the original "Ask Stash"/live-count block, just a static title, no
  item-count. View and Settings remain title-less. See "2026-09-07 · iOS
  feedback round 3 (plan 12)" below for the fuller writeup.
- **Composer**: the keyboard accessory is now an icon-only minimize-keyboard
  button (`capture.dismissKeyboard`) — was a text "Done", which read as a
  second active primary action alongside the violet send button. The
  public/lock toggle is removed from the composer entirely — sharing is
  detail-sheet-only now (`CaptureViewModel.isPublic` stays `false` by
  default). The attachment row's remove-× (`xmark.circle.fill`) is no longer
  clipped by the scroll view's edge.
- **Inline citation links in chat — shared `messages.content` convention.**
  Both platforms now bake citation links into the persisted assistant
  message text *before* saving (not just at render time), so a reloaded
  conversation's citations stay clickable without needing the `sources`
  array again. Format: `[Title](#item=<uuid>)` (web: `src/utils/
  chatCitations.ts`, baked in `ChatMole.tsx:357-361`; iOS: `StashKit`'s new
  `ChatCitations.swift`, baked in `ChatStore`). **The uuid must be
  lowercase** — web's extraction regex is `/[0-9a-f-]+/`, case-sensitive; an
  uppercase-baked id is silently dead on web. iOS also recognizes
  (read-only, never writes) a legacy `stash://item/<uuid>` form left over
  from an early plan-8 fix round — harmless, nothing produces it anymore.
  Per-source chip fallback (the old default rendering) now shows **only**
  when an answer has zero resolved inline links; iOS strips any unresolved
  `[Title](#N)` marker down to plain text rather than rendering a
  dead-looking violet link. **Divergence, flagged for a decision, not
  reconciled this round**: iOS renders these links violet with no
  underline; web underlines them (`underline decoration-violet-300`).
- **Notes editor semantics changed** (detail sheet). Plain-text notes are
  now a fully editable, whole-field autosaving editor — 600ms debounce,
  flushed immediately on blur/Done/dismiss — where they used to be
  append-only like rich notes. Rich (TipTap JSON) notes stay
  read-only-render + append-only, but the append now fires only on
  blur/Done, never on the debounce tick (appending mid-keystroke was
  splitting paragraphs and emptying the field while the user was still
  typing). Identifiers changed: `detail.notesComposer.*` →
  `detail.notes.editor` / `detail.notes.hint` / `detail.dismissKeyboard`
  (the same minimize-keyboard control the composer uses). A save failure
  now surfaces "Couldn't save — try again." in the destructive color under
  `detail.autosave.error`, distinct from the resting `detail.autosave`
  identifier — applies to both the notes flush and the title/description
  field save; nothing typed is discarded on a failed save, and the next
  successful save on any field clears the error state.

Suite state at this commit: StashKit 312→341 (`ChatCitations`,
`tipTapLastParagraphText`, `SaveGeneration`, `Debouncer.cancel`, notes
merge-flag tests); iOS UI suite 19→21
(`testAskFooterLinksRenderAndOpenConversations` renamed to
`testAskHeaderButtonsOpenConversations`, `testComposerKeyboardAccessory`
new, `testDetailSheetAnatomy` extended with a focus assertion); both app
targets build warning-free.

---

## 2026-09-03 · Subject-aware hero crops + "Report a problem" on cards

Two things from Will's Farfetch example: a portrait product shot (glasses in
the bottom third of a white 3:4 image) rendered as a blank white hero because
the card `cover`-crops around the centre; and there was no way for a beta
tester to flag a card that looks wrong.

- **Hero crop rule (DESIGN.md, Components)**: cover-cropped heroes centre on
  the detected subject. Web does it client-side, no model, no server work:
  after the `<img>` loads (`crossOrigin="anonymous"` — the storage bucket and
  `image-proxy` both send `Access-Control-Allow-Origin: *`), sample it to a
  ≤64px thumbnail, take the border ring's median colour as background, bound
  every pixel whose |ΔR|+|ΔG|+|ΔB| from it exceeds 60, and set
  `object-position` so that box's centre sits at the centre of the crop
  window (exact formula in `src/utils/heroFocal.ts: coverObjectPosition`).
  Applies to `LinkCover` (standard, non-tall) and `AspectAwareImage`
  (landscape branch); portrait uploads keep contained-on-blur. Busy photos
  degrade to the plain centre (their "subject" is the whole frame). Result is
  cached per image URL for the session; nothing is persisted yet — if iOS
  needs the numbers without recomputing, the next step is writing
  `attributes.media.focal {x,y}` from the client on first analysis.
  **iOS**: mirror the three steps with CoreGraphics on the card hero
  (`heroFocal.ts` header comment is the contract; thresholds 30 / 60 / 0.8).
- **Card feedback (all platforms)**: new table `card_feedback`
  (`supabase/migrations/20260903120000_card_feedback.sql`, applied to
  production 2026-09-03). Columns: `user_id`, `item_id` (FK, null on delete),
  `issues text[]` (codes below, ≥1), `note`, `client` ('web' | 'ios' |
  'extension' | 'macos'), `snapshot jsonb` (`type,title,description,url,
  file_path,flavor,has_summary` as the card showed them), `created_at`. RLS:
  users insert/select their own. Codes (`src/utils/cardFeedback.ts`):
  `image_crop`, `image_wrong`, `title`, `description`, `summary`, `type`,
  `other`. Insert directly with supabase-js; no edge function.
- **Web UI**: card overflow menu (own library only) gets **Report a
  problem** (flag icon) above Delete → `CardFeedbackDialog`: checkbox list
  of the seven codes, optional note, violet **Send report**; toast on
  success. **iOS**: same entry point in the card's context menu / detail
  sheet overflow, same list and codes, `client: 'ios'`.
- **Reviewing**: `node scripts/card-feedback-report.ts [--days N]` prints the
  newest reports with the item's current title/url beside the snapshot.

---

## 2026-09-03 · Metadata text hygiene (entities/markdown) + full-width panel title/description

Link titles and descriptions were being stored with HTML entities still
encoded (`&amp;`, `&quot;`, `&#x2019;`, `&#039;`, and LinkedIn's
double-encoded `&amp;#39;`) and with markdown emphasis markers from social
captions (`**1. Terms**`), so every surface rendered them literally. Root
cause was the two metadata parsers: `add-url` never decoded, and
`extract-link-metadata` decoded only four named entities in a single pass.
Both also cut a meta `content` value at the first quote of *either* kind, so a
double-quoted description containing an apostrophe truncated to `"I"`.

- **Contract (platform)**: `title` and `description` returned by
  `extract-link-metadata` and written by `add-url` are now clean text — HTML
  entities decoded (named, decimal, hex; repeated until stable for
  double-encoded sources), markdown emphasis (`**`, `__`, `*x*`, `_x_`,
  `` `x` ``) unwrapped, whitespace collapsed. Caller-supplied titles (the
  user's own words) are stored verbatim. Shared helper:
  `supabase/functions/_shared/textHygiene.ts`, paired with the vitest-tested
  `src/utils/textHygiene.ts` (`decodeHtmlEntities`, `cleanMetaText`,
  `cleanOptionalMetaText`). Meta-tag `content` is now matched to its own
  opening quote.
- **Backfill**: `scripts/backfill-text-hygiene.ts` ran 2026-09-03 against
  production — 51 `type='link'` rows rewritten (24 titles, 38 descriptions);
  zero remain. **iOS / extension / macOS need no change**: stored data is
  clean and new saves arrive clean. Rendering a decode as a safety net is
  optional.
- **Web safety net**: cards decode the title (`ContentItemHeader`) and clean
  the description (`ContentItemContent`) at render; the edit panel decodes
  entities into its initial title/description state (`useEditItemState`) so a
  blur-save writes real text.
- **Panel title: clamp at rest, full when editing** (revised same day,
  Will): `EditItemTitleSection` has two states. At rest it is a two-line
  clamped block with an ellipsis (`line-clamp-2`; full text in the tooltip),
  replacing the one-line `<Input>` that clipped long titles at the panel edge
  with no ellipsis. Clicking it swaps in an auto-growing textarea showing
  every line, focused with the caret at the end; blur saves the trimmed
  title and returns to the clamped view; Enter is "done"; pasted newlines
  flatten to spaces. Same DESIGN.md inline-editable styling (wash on hover,
  wash + violet-300 ring while editing). iOS: detail-sheet title `lineLimit(2)`
  with truncation at rest, full multi-line `TextField` when active.
- **Panel description spans the panel**: dropped the `max-w-[64ch]` cap on the
  description textarea; its right edge now matches the title and the rest of
  the panel.

---

## 2026-09-03 · iOS design consolidation (plan 7)

iOS now runs on the current `DESIGN.md` token set (it had drifted onto a
pre-`DESIGN.md` palette shipped 2026-08-30 as `c4e9a5b`) and closes five
web-parity gaps Will flagged from screenshots: login, item detail sheet,
Ask-tab access to conversations, conversations list, and the app icon. Full
plan: `docs/superpowers/plans/2026-09-03-ios-plan-7-design-consolidation.md`.

- **Tokens/typography**: `ios/Stash/Design/StashDesign.swift`/`StashType.swift`
  re-derived so every value (ink `#22262f`, muted `#646b76`, faint `#959ba6`,
  violet-600 `#6d5bd0` accent, violet-300 `#b6a8ef`, destructive `#c93a3a`,
  radii 16/20, card+sheet shadows) matches `DESIGN.md` verbatim — ~75 call
  sites across 19 files migrated off system fonts/hardcoded colors. PP Neue
  Montreal (Book/BookItalic/Medium/Semibold, converted losslessly from the
  web's woff2 via fontTools) is now bundled in **both** the app and the share
  extension targets (the appex can't read the host bundle), SF Pro fallback
  only on load failure — the share sheet renders Neue Montreal too, no longer
  simplified. Global accent is violet-600 (`AccentColor` asset + root `.tint`)
  — was the default iOS blue.
- **App icon = the favicon**: flat ink `#22262f` stitched second-S on white,
  identical glyph to `public/favicon.svg`, no gradient — same PNG in both the
  app and extension asset catalogs. This **revokes** `DESIGN.md`'s "iOS app
  icon (standing exception)" clause (edited in the same change; the older
  gradient icon shipped 2026-08-29 is gone). *`docs/ui-changes.md` amendment:
  the 2026-09-01 entry below still said "and the iOS app icon, standing
  exception" — corrected in place.*
- **Sign-in card parity + sign-up added**: wordmark, "Sign in or create your
  account.", pill Sign in/Sign up tabs (equal-width), quiet violet-tinted
  inputs, violet-600 CTA — matches `src/pages/Auth.tsx`. Sign-up is new on
  iOS: mirrors web's `signUp` exactly (auth.signUp → `user_profiles`
  username/display_name insert → optional `send-welcome-message` invoke when
  a phone is given), with a live username/phone availability probe against
  the same tables/columns/threshold as web. **Product note for web/mac**:
  since iOS can now create accounts, Apple 5.1.1(v) requires in-app account
  deletion before the app can go out on the *public* App Store (TestFlight is
  unaffected) — carried forward as a named requirement for the next iOS
  plan.
- **Ask tab**: header is now "Ask Stash" / "Answers from your N items"
  (live count); the two header icon buttons are retired — "Start new chat ·
  Earlier conversations" text links now live under the composer instead
  (same `ask.newChat`/`ask.history` identifiers, just relocated + relabeled).
  Welcome bubble copy matches web verbatim. Conversations rows: 8pt
  violet-300 dot, 1-line muted excerpt, stacked date + message count,
  month-bucket micro-labels. (iOS still diverges from web on pagination —
  infinite scroll vs. web's Prev/Next — that divergence note lower in this
  file stands unchanged.)
  **2026-09-03 (plan 8) — REVERSED**: Will's device review called the footer
  text links a regression on a phone screen. The header icon buttons are
  back as the sole affordance (still `ask.newChat`/`ask.history`); the
  footer links and the title/item-count header block are both gone. See
  "2026-09-03 · iOS feedback round 1 (plan 8)" above — no title/wordmark on
  this tab at all now, not just no footer links.
- **Item detail sheet rebuilt to `DESIGN.md`'s panel order**: eyebrow pill
  (type + domain) → editable title (invisible chrome at rest, violet wash on
  focus) → description → media → **URL bar** (favicon + mono URL + open
  affordance, new — no iOS favicon-image helper existed before this, added
  to StashKit's `CardMetadata`) → micro-label ("NOTES & SUMMARY" etc., per
  type) + pill tabs → tab content rendered through a new pure Markdown block
  parser (`StashKit`'s `MarkdownBlocks.parse`/`looksLikeMarkdown`, tested,
  ported byte-for-byte from `EditItemContentSection.tsx`'s heuristic) so AI
  summaries/notes render real headings/bullets/bold instead of raw
  `**`/`-` characters → **Details drawer** (collapsed by default, matching
  web's `useState(false)` — header is a one-line summary + chevron; expands
  to dotted key/value rows: Saved/Type/Size/Duration/Source/**Location**,
  the last absorbing the old standalone location editor, which no longer
  renders twice) → **Sharing** tile (lock/globe, violet switch, feed-link
  copy chip gated on the user's own username actually having loaded — never
  renders/copies a bare `gostash.it/feed/`) → footer (Delete left, autosave
  status right, always visible — not scrolled-under).
  `DESIGN.md`'s panel-order sentence now names the URL bar explicitly (both
  platforms render it right after media).
- **Tags UI retired on iOS** — matches web (`DESIGN.md` §Components: "no tag
  UI on cards or panel"). Removed from the detail sheet and from Settings
  (`TagsSection` deleted). Tag *data* (StashKit `TagsAPI`, `items.tags`) is
  untouched — this is a UI-only removal, same as web's.
- **Status colors**: iOS uses the system `.orange`/`.green` at a few sites
  (outbox/gate badges, a saved-chip) because `DESIGN.md` has no
  warning/success token yet — flagged here so web/mac can add one if/when
  it's worth standardizing; iOS's own `.red` sites were already converted to
  the `destructive` token.

Suite state at this commit: StashKit 293→312 (new: `MarkdownBlocksTests`,
19 tests); iOS UI suite grew from 15 to include seven new smokes
(`testDesignSystemFontsLoad`, `testSignUpTabRenders`,
`testAskFooterLinksRenderAndOpenConversations`, `testDetailSheetAnatomy`,
`testPublicSmoke` [renamed from `testTagsAndPublicSmoke`, tag steps already
removed], `testLocationEditSmoke`, `testShareExtensionURLSmoke`); both app
targets build warning-free.

---

## 2026-09-01 · Favicon corrected to the full flat second-S; interstitial simplified (amends the entry below)

- **Favicon redrawn**: the first cut used only two of the second-S's five
  glyph paths and a gradient tile — it didn't read as the wordmark's S. Now:
  all five paths, flat ink `#22262f` on white, no gradient. Same set of files
  (`favicon.svg/ico`, pngs, apple-touch, manifest icons, extension icons).
- **New standing rule (DESIGN.md · Iconography): brand elements are flat** —
  no gradients in buttons, icons, favicons, or marks; the splash gradient is
  for page washes only. (Amended 2026-09-03: the iOS app icon was a standing
  exception here — it no longer is; see the entry above.)
- **Loading interstitial simplified**: it shows for a split second, so the
  animated mark + cycling copy never landed. Now a quiet arc spinner
  (hairline track, violet-600 rounded-cap arc, 0.9s) on the grey wash.

## 2026-08-30 · Sign-in polish, playful loading interstitial, brand favicon, tag filtering hidden (web; iOS/extension mirror notes inline)

- **Sign-in**: "Welcome to Stash" heading removed (wordmark + "Sign in or
  create your account." carry the page); background is now the app's ambient
  `.animated-gradient` wash at 30% (same as the library), faded toward the
  card. `.animated-gradient` gained a global `prefers-reduced-motion` guard.
- **Post-login loading interstitial** (`src/components/LoadingInterstitial.tsx`):
  replaces the grey spinner + "Loading..." on `/home`. The wordmark's stitched
  second-S with a rotating splash-gradient fill and a gentle breathe, over
  playful cycling copy ("Unpacking your stash…", "Rehanging the gallery…", …).
  Reduced-motion: static mark, single message. iOS: the launch/loading moment
  should adopt the same mark + copy tone (copy list in the component).
- **Favicon/site icons**: the stitched second-S over the splash gradient
  (same glyph + slice as the iOS app icon) now ships locally —
  `favicon.svg/ico`, `favicon-32/16.png`, `apple-touch-icon.png`,
  `icon-192/512.png`, webmanifest updated. The Supabase-hosted icon set and
  any Lovable-era hearts are retired. **Chrome extension icons** updated to
  the same mark (`extension/icons/*`) — note `public/stash-it-extension.zip`
  is now stale and needs rebuilding at the next extension release.
- **Tag filtering hidden**: the "Filter by tag" control and selected-tag chips
  are gone from the library toolbar (`LibraryToolbar.tsx`; props kept so the
  Index contract is unchanged). With the card/panel tag editors already
  removed, there is now NO tag UI anywhere — tags data remains in place;
  **themes** will replace tags as the grouping model. Other platforms: hide
  any tag affordances the same way, don't delete data.

## 2026-08-30 · Design-system revisions after live review (amends the three entries below; DESIGN.md updated to match)

- **Card titles are serif again**: upright PP Editorial New returns for the
  library-card title *only* — the one serif role in the product ("this is a
  saved object"). Panel titles and everything else stay Neue Montreal. iOS:
  mirror exactly this split.
- **Screenshots render full-bleed** like any image; the framed-window hero was
  reverted. The screenshot identity lives in the tinted type chip.
- **Document tint moved from coral to violet** (`rgba(150,70,190)` @ ~.10,
  text `#7d3f9e`) — the coral read peach. Spectrum table in DESIGN.md updated.
- **Page gradient rebalanced toward purple/blue** (`.animated-gradient` stops:
  milky orchid/salmon → `#9d5fd8`/`#c2418f`, cyan tail deepened) — kills the
  "pepto" cast at the 30%-opacity wash.
- **"Chat with item" removed from the card overflow menu** (behavior change —
  other platforms drop the same affordance; chat with a single item remains
  reachable through Ask). `onChatWithItem` prop still accepted, now unused.
- **og.jpg regenerated** (1200×630) to match the current periphery-cards
  homepage: new card anatomy (icon+kind row, Tobias titles, violet voice
  waveform, tag chips, real photography) on the deeper purple wash.

## 2026-08-30 · DESIGN.md introduced; app typeface is now PP Neue Montreal everywhere; login redesigned (all platforms take note)

- **`DESIGN.md` now exists at the repo root** and is the single source of truth
  for look-and-feel across web, homepage, iOS app, iOS share sheet, Chrome
  extension, and macOS. It's linked from `CLAUDE.md`'s read-first list. All
  three 2026-08-30 entries below implement it. Token or rule changes must edit
  `DESIGN.md` in the same branch.
- **Typeface contract — for the iOS/mobile agent especially:** the product
  typeface on every surface is **PP Neue Montreal** (weights: 400 UI/body,
  500 object titles, 600 display; 400 italic for user annotations). PP Mori is
  retired everywhere; upright PP Editorial New is retired from product
  surfaces (serif titles are gone — titles are now NM 500 with negative
  tracking). Marketing pages keep exactly two display exceptions: Tobias and
  PP Editorial Ultralight Italic accent words. **iOS must bundle
  `PPNeueMontreal-{Book,Medium,Semibold,BookItalic}` in both the app and
  share-extension targets** (appex can't read host-bundle fonts — same pattern
  as the icon catalogs) and update `StashDesign.swift` to match DESIGN.md's
  type table; SF Pro is fallback only. Web files live in `src/assets/fonts/`;
  web plumbing: `font-montreal` in `tailwind.config.ts`, faces + body default
  in `src/index.css`.
- **Login (`/auth`) redesigned** to the design language (grey wash, centered
  400px card, wordmark in ink, pill tabs, violet-600 CTAs, quiet inputs).
  Contracts unchanged: all handlers, redirects, and the 2026-08-29
  anonymous-session rule are byte-identical; `Auth.test.tsx` still covers the
  lockout regression.
- **Consistency directive:** web app, homepage, iOS app, iOS share sheet, and
  the (upcoming) Chrome-extension restyle must all reference `DESIGN.md`
  rather than copying each other's CSS. Stylistic drift between surfaces is a
  bug; when a surface can't express a token exactly, note the deviation in
  `DESIGN.md`'s per-surface section in the same change.

## 2026-08-30 · Web detail panel: one surface, Details drawer, in-panel player (DESIGN.md pass 3)

Spec: `DESIGN.md` ("Detail panel", "Sharing row states", "Player") + reference
implementation `docs/superpowers/prototypes/2026-08-30-detail-panel-surface-neue-montreal.html`.
Web edit sheet only; iOS/macOS mirror from DESIGN.md. All data flows, autosave,
and props contracts are unchanged — this is structure + skin.

- **Section grammar** (`src/components/edit/EditPanelSection.tsx`): the boxed
  `sectionCard` treatment is deleted everywhere. Every section is an uppercase
  11px/600/+0.11em micro-label over a `rgba(0,0,0,.07)` hairline on one
  continuous surface (sheet bg `#fff → #f8f8fa`; the pink tint is gone).
- **Header zone**: tinted type-chip eyebrow (Lucide icon + subtype label —
  reads `attributes.media.kind` via the cards' `audioSubtype`/
  `isScreenshotItem` helpers) + source hint (domain, or `uploaded/saved ·
  date`), then the title (Neue Montreal 500 / 28px / −0.02em) and description
  as chrome-less inline editables: violet wash on hover, wash + 2px violet-300
  ring on focus. Same blur-to-save handlers as before.
- **Details drawer** (`src/components/edit/EditItemDetailsDrawer.tsx`): new
  collapsible section, closed by default; the header shows an inline
  `format · size · duration` summary. Open, it's dotted-leader key/value rows:
  Original file (from `attributes.media.file_name` or the `file_path`
  basename, mono), Format, Duration, Source URL (links), Saved (with time),
  and Location — the existing location editor moved into this row unchanged
  in behavior (manual label, clear-to-remove).
- **Media plays in the panel** (`src/components/edit/EditItemPlayerStrip.tsx`):
  audio/video items get the DESIGN.md player strip above the content tabs —
  flat type-tint field, solid accent play/pause with real `<audio>` playback,
  deterministic waveform (same `waveformHeights(id)` identity as the card),
  click-to-seek, times, and a 1×→1.5×→2× speed pill; quiet "Download
  original" below. Links get a hairline favicon/url/open row.
- **Sharing row**: private = grey 34px lock tile + "Private / Only you can
  see this item"; public = violet globe tile + violet switch + feed-link chip
  (`gostash.it/feed/{username}`, copy-with-check) + inline un-share hint. The
  unshare-confirm dialog (sticky-note deletion) and public sticky-note editor
  are unchanged in behavior.
- **Footer**: delete is `#c93a3a` + `trash-2`; autosave indicator unchanged.
  All motion ≤200ms with `prefers-reduced-motion` guards; Lucide only.

## 2026-08-30 · Web library cards: Neue Montreal card system (DESIGN.md pass 3)

Spec: `DESIGN.md` (tokens, per-type hero table, chips grammar) + reference
implementation `docs/superpowers/prototypes/2026-08-30-card-type-gallery-neue-montreal.html`.
Web library cards only; iOS/macOS should mirror from DESIGN.md. Subtype data
contract (`attributes.media.kind`) is documented in the enrichment entry below;
cards read it with client fallbacks: audio `duration_s ≥ 600s` renders as
`recording` (else voice note), and an image renders as a screenshot when
`kind === 'screenshot'` **or** its title starts with `"Screenshot of"`.

- **Audio cards** (`PlayerHero`, `src/components/cards/CardHero.tsx`): the
  grey `MediaPlayer` bar is gone from cards (component kept — composer
  surfaces still use it). The hero is a functional player on the flat
  type-tint field — 116px voice / 96px recording, solid accent play circle
  (`#544eba` voice / `#8b4a9e` recording), deterministic waveform bars
  hashed from the item id (played 1.0, unplayed .26), tabular-numeral time.
- **Document cards** (`DocumentHero`): flat document field + white CSS
  page-glyph (grid variant for spreadsheets) + format badge (PDF `#a33d52`,
  sheets `#1d6f42`, decks `#c43e1c`, docs `#2b579a`). A real first-page
  thumbnail can slot into the glyph later without layout change.
- **Screenshot cards** (`ScreenshotHero`): screenshot field + white
  window-frame (title bar, three dots) around the real capture, top-aligned.
  Non-screenshot images unchanged.
- **Video cards** (`VideoPosterHero`): resting state is a poster frame
  (`preload="metadata"`, no native chrome) + centered play badge + duration
  pill on a bottom scrim; native controls appear only once playback starts.
  Expand-to-lightbox unchanged. Hero height joins the two-height scale (h-40).
- **Chips grammar** (in order, nothing else): always-visible type chip first
  — tinted with an 11px Lucide icon for voice note (mic) / recording
  (audio-lines) / screenshot (scan-line) / document (file or table-2),
  neutral for photo / note / video / link flavors — then `FORMAT · size`
  (mono), then one salient fact (duration / read-time). Filename chips are
  gone from cards; the hover-only footer type badge is gone. Footer keeps
  date + location pin + overflow (`more-horizontal`, 24px round target).
- **Tags UI removed from cards**: `ContentItem` no longer renders
  `ItemTagsManager` (component untouched); grouping moves to themes.
- **Tokens**: hero-bottom → body-top gap is **18px for every hero type**;
  no-hero cards take 22px top; body side padding stays 24px. Card titles are
  PP Neue Montreal 500, 20/1.24, −0.014em (`font-editorial` retired from
  cards). Card shadows go neutral grey
  (`0 1px 2px rgba(20,22,30,.05), 0 8px 24px rgba(30,33,44,.08)`, hover
  deepens + 2px lift) — purple-tinted shadows are gone from cards. Spectrum
  fields are flat tints + grain via the shared `SpectrumField`
  (`src/components/cards/CardBits.tsx`).

## 2026-08-30 · Media/document AI titles + `attributes.media.kind` subtype (backend + web; iOS/macOS render against the new contract)

Uploaded media and documents now get real AI titles instead of filenames, and
audio/video items carry a renderable subtype.

- **Shared title policy** — `supabase/functions/_shared/titlePolicy.ts`
  (vitest-tested web mirror: `src/utils/titlePolicy.ts`; keep in sync).
  `isPlaceholderTitle(title, filePath)`: empty, equal to the file basename,
  extension-suffixed (`Recording.m4a`, `deck.pptx`), storage-timestamp
  (`1724900000000.webm`), or UUID-shaped (`72322570-….m4a`) titles are
  placeholders enrichment may replace; **anything else is the user's and is
  never touched**. Guards always re-fetch the current title first (renames
  during enrichment win); fetch failure ⇒ skip the title write. Titles capped
  at 90 chars (`capTitle`). `analyze-image` keeps its own earlier copy of the
  same policy (unchanged).
- **Audio/video (`add-file`)**: after transcription, a placeholder title is
  replaced with a 3–9-word gpt-4o-mini title from the transcript. Privacy
  rule: for deeply personal content (health, relationships, grief, finances,
  private confessions) the model returns `KEEP_FILENAME` and the filename
  title stays. Web upload path mirrors this via `generate-title` with
  `{ kind: 'transcript' }` (same shared prompt; callers must treat a
  `KEEP_FILENAME` response as "keep the current title").
- **`attributes.media.kind`** (whole-blob read-merge-write, unknown keys
  preserved): `'voice_note'` (audio < 600 s or unknown duration),
  `'recording'` (audio ≥ 600 s, from `attributes.media.duration_s`),
  `'video'` (video files — **new `MediaKind` value**, added to
  `src/types/itemAttributes.ts`). Meaningful original filenames land in
  `attributes.media.file_name`; storage-timestamp/UUID names never do.
- **Documents**: `quick-pdf-summary` now writes its AI title over
  placeholder (filename) titles too, not just empty ones (page_body-null
  condition kept). `extract-office-text` gains a guarded gpt-4o-mini title
  from the first ~1500 extracted chars.
- **Deploy needed** (not yet deployed): `add-file`, `quick-pdf-summary`,
  `extract-office-text`, `generate-title`.

## 2026-08-30 · Ask retrieval reliability + WhatsApp/SMS intent gate (backend; no client changes required)

Spec: `docs/superpowers/specs/2026-08-29-ask-retrieval-reliability-and-intent-gate-spec.md`.
Root cause + reproduction of the 2026-08-30 retrieval misses are in the spec.

- **Ask (`chat-with-all-content`), all platforms:** `search_stash` type/tag
  filters are now **soft** — an unfiltered backstop search always runs, and
  strong hits the filter excluded are surfaced ranked by score, labeled
  "outside your filters". "Video" also matches links whose
  `attributes.link.flavor` is `video` (YouTube etc.). New internal
  `browse_catalog` tool lists the user's whole library for bare-word/fuzzy
  queries. **SSE contract:** unchanged except a new optional status value —
  `data:{"status":"browsing"}` — verified no current client parses status
  frames (web and iOS both ignore them), so nothing to mirror; any future
  status UI should treat unknown values as "working".
  Sources/citations behavior unchanged. Every retrieval is logged to the new
  service-role `retrieval_log` table; golden regression set at
  `supabase/evals/golden-retrieval.json` (`node scripts/eval-retrieval.mjs`),
  5/5 passing post-deploy, including both real 2026-08-30 failures at rank 1.
- **WhatsApp/SMS (`twilio-webhook`):** inbound messages now pass an intent
  gate (`_shared/intentGate.ts`) instead of a forced note/question guess.
  Rules first: bare URLs and media saves — and a texted URL now becomes a
  real **link item** (scrape + embeddings via `scrape-page-content`), not a
  text note. Ambiguous text gets one confirm question ("Reply 1 to save it,
  or 2 for an answer"), held in the new `pending_intents` table (15-min TTL,
  one per user+channel). After an auto-save the reply offers `undo` / `ask`
  one-word flips; classifier failure now defaults to answering (recoverable)
  instead of silently saving. `sms_conversations.intent` gains values
  `clarify` (confirm question sent) alongside note/question/command.
- **DB:** `hybrid_search_content` v3 adds `item_flavor` output column
  (appended last; existing callers unaffected). New tables `retrieval_log`,
  `pending_intents` (both service-role only, RLS on/no policies).
- Not shipped yet (follow-ups in spec): doc2query enrichment + audio titles
  (R5), web/iOS save-suggestion chip via `data:{suggest:'save'}` frame (G4),
  WhatsApp quick-reply buttons (needs a Twilio Content template).

## 2026-08-29 · Web: landing page back to periphery-cards hero; cards rebuilt as authentic library items (web only)

- **Reverted the TryStash progressive-capture landing** (2026-08-28's anonymous
  capture hero + ledger section — it was a concept) to the periphery-cards
  layout from `1e582d7`: six floating stashed-item cards down the left/right
  edges (Cloth fabric physics, light rays, scroll parallax), hero CTA to
  /pricing, capabilities grid, paste demo, screenshots, chat demo. `TryStash.tsx`
  and the anon-profile plumbing stay in the tree, just unmounted.
- **Cards rebuilt as believable saved objects**, one per capture type, each
  with the anatomy that type really has instead of one photo+badge template:
  recipe (pasta photo, cook-time meta), **voice note with waveform + play
  chip + duration + transcript snippet (no cover)**, ceramics inspiration
  image, place (café photo, name + neighborhood meta + user's own note),
  article link (read-time meta, "full text saved"), and a **plain note with
  auto-tag chips**. Shared anatomy: optional cover → icon+kind meta row
  (replaces the black badge-on-photo) → tobias title → mori note. No
  contract changes — marketing page only; nothing for iOS/macOS to mirror.
- **All cover photos are now real photographs** (Unsplash-licensed, credits
  in the commit); the AI-generated mockups (gibberish handwriting, fake app
  UIs) are deleted. Standing rule, commented in `Landing.tsx`: card covers
  must be real photography, never AI renders or mocked-up interfaces.
- Source: `src/pages/Landing.tsx` (`StashedCard`, `FLOATING_CARDS`).
- **Sign-in lockout fixed** (latent since the TryStash landing): `/auth`'s
  already-signed-in redirect fired for **anonymous** try-stash sessions too,
  and `/home` bounces anonymous users to `/`, so visitors with a lingering
  `signInAnonymously()` session flashed the sign-in form then landed on the
  homepage — locked out. `/auth` now redirects only real (non-anonymous)
  accounts; an anonymous session stays on the form and is replaced on
  sign-in. Contract for other platforms: treat `is_anonymous` sessions as
  signed-out everywhere except the try-stash surface itself.

## 2026-08-29 · iOS: app icon (wordmark's second S over splash gradient); share card redesigned in the design language (iOS)

- **App icon shipped** (was empty — TestFlight upload hard-fails without one):
  the wordmark's stitched second-S glyph, white, centered at ~55% height over
  the splash gradient's pink-hued slice (`#667eea → #764ba2 → #f093fb →
  #f5576c`, 135°). Single 1024 universal PNG in
  `ios/Stash/Assets.xcassets/AppIcon.appiconset`. The **share extension
  carries the same icon** in its own catalog
  (`ios/StashShareExtension/Assets.xcassets` — an appex bundle can't see the
  host app's catalog), so the share sheet shows the branded S too;
  `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon` set on both targets in
  `project.yml`. Source of truth for regenerating: the icon is rendered from
  the wordmark SVG's second-S paths (x≈587–726 in the viewBox) — no separate
  design file.
- **Share compose card redesigned** to the app design language
  (`StashDesign.swift` now compiled into the extension target, same
  shared-glue pattern as `LocationCapture.swift`): gradient backdrop +
  wordmark header replace the `NavigationStack` inline "Stash" title; Cancel
  is a round `xmark` `CircleIcon`; previews + note field sit on hairline
  cards (solid bg, gray hairline, soft shadow — no stock `.roundedBorder`);
  URL glyph wears the violet toggled-circle treatment; pin is the composer's
  `CircleIcon` mappin (violet when pinned, spinner in-circle while
  resolving); Save is the weighted violet capsule (CircleSubmitIcon's
  hot/resting split, never dimmed). **Contracts unchanged:** every
  `share.*` accessibility identifier, element type (note stays a
  vertical-axis TextField → bridges as TextView), and all
  save/gate/abandon-tracker behavior byte-identical.
  `testShareExtensionURLSmoke` re-verified green against production.

## 2026-08-29 · iOS: chat sessions + Conversations screen (iOS ports web 2026-08-27/28)

Prototype (reviewed & approved): `docs/superpowers/prototypes/2026-08-29-ios-ask-conversations.html`.
Client-only — the trigger, gap convention, and `list_conversations` RPC were
already deployed by the web migrations.

- **`ChatSessions` (StashKit):** port of `chatSessions.ts` — 3h gap
  (`resolveTarget`), bucket labels (Today/Yesterday/This week [Mon start]/
  month), timestamptz parsing. Unit-tested (gap boundaries, buckets).
- **`ChatHistoryStoring` reshaped:** `latestConversation` (by
  `last_message_at`), `createConversation` (title null, lazy),
  `generateTitle` + `setTitle` (auto-title, non-fatal), `listConversations`
  (RPC pass-through). The old eager `loadOrCreateConversation` (earliest-ever
  row titled "Ask Stash") is gone.
- **`ChatStore` session machine:** open-time resolution (continue < 3h, else
  fresh; row created lazily on first send), `ensureSessionForSend` (explicit
  resumes gap-exempt; stale thread clears first; brand-new session sends NO
  prior turns), auto-title after the first exchange (optimistic
  question-fallback title, generated title replaces it), `openConversation` /
  `startNewChat` / `letGoIfExplicit` / `restorePrevious` + `lastLoaded`.
  All unit-tested with an injected clock.
- **Ask tab UI:** NavigationStack (the one pushed screen in the app — back
  reads "‹ Ask" under the hidden wordmark header, per the titling
  convention); header gains new-chat + history circle buttons; violet title
  pill while an explicit old conversation is open; "Load previous
  conversation — <title>" restore banner on an empty thread.
  **Let-go trigger on iOS = leaving the Ask tab** (the analog of collapsing
  the web mole), via the NavigationStack's `onDisappear`.
- **`ConversationsListView`:** server-paged (25/page, infinite scroll instead
  of web's Prev/Next), debounced search (300ms, titles + message contents),
  bucket labels, untitled rows italic. Row tap loads explicit + pops.
- Card **focus mode intentionally not ported** (Will's call, 2026-08-29).
- New `testConversationsSmoke` (ungated — listing needs no subscription):
  passes green against production.

## 2026-08-29 · iOS polish: Add-tab tab-bar hairline; search submit key (iOS)

- Add tab forces `.toolbarBackground(.visible, for: .tabBar)` — the other tabs
  get the bar's material + hairline for free from content scrolling beneath
  it; Add has no scroll view, so the bar rendered transparent there (no
  separator line).
- Library search pill: `.submitLabel(.search)` — return dismisses the
  keyboard (the custom pill spawns no system Cancel button, unlike
  `.searchable`). UI tests updated accordingly; `testTagFilterSheetOpens`
  deleted with the tag filter. `testLibrarySmoke` + `testDetailSheets`
  verified green against production after the redesign.

## 2026-08-28 · iOS: web design language adopted — round buttons, wordmark headers, gradient, splash; chips/tags removed from View (iOS)

Second pass the same day (below entry is the first): the iOS app now mirrors
the web's visual conventions instead of stock-iOS chrome.

- **Design system** (`ios/Stash/Design/StashDesign.swift`): the web's exact
  values ported — Tailwind violet/gray hexes, `UnifiedInputPanel.tsx`'s round
  iconographic buttons (white circle, hairline gray border, soft shadow;
  violet-tinted active state; the one weighted control is the violet-filled
  #8B5CF6 paperplane submit, never dimmed when disabled — white/gray instead),
  and `index.css`'s six-stop `.animated-gradient` (15s ease shift) as a
  page-level backdrop fading to background.
- **One titling convention across all four tabs:** no per-screen titles (the
  tab bar already says where you are; no tab goes deeper than one level).
  Every tab carries the same compact header — Stash wordmark leading (ported
  as a template-rendered SVG asset), per-tab accessory trailing (View: item
  count; Add: outbox badge). If push navigation ever arrives, the system
  inline back bar slots underneath without clashing.
- **View tab decluttered:** type chips (All/Links/Notes/…) removed entirely;
  tag filter removed (tags are being deprecated product-wide — they remain
  visible only in Settings for now); large title + `.searchable` bar replaced
  by the header row + one pill search field (web `LibraryToolbar`'s
  rounded-full pill, violet ring while focused). Cards are white surfaces
  with hairline border + soft shadow over the gradient backdrop.
- **Ask composer** restyled to the same circles (mic resting = white circle;
  live dictation keeps its red state signal; send = weighted violet circle).
- **Splash screen** (`SplashView`): wordmark centered over the animated
  gradient at 0.35 opacity, ~1.6s on cold launch, cross-fades out while
  session restore continues underneath. Sign-in screen intentionally plain.
- UI tests updated: chip/tag steps dropped; search now targets the custom
  pill field (`library.search` text field, not `searchFields`), which spawns
  no system Cancel button.

## 2026-08-28 · iOS: single-column card grid on phones; full-screen Add composer (iOS)

- **Library grid is single-column on compact width** (phones); two-up only on
  regular width (iPad). `LibraryView.columns` switches on
  `horizontalSizeClass`. Motivation: the two-up grid shipped with a card-width
  blowout — `.fill`-scaled hero images inflated cards past their grid column.
  Structural fix in `CardHero.swift`: `TallContainedImage` /
  `StandardCoverImage` now render imagery in an `.overlay` of a fixed-height
  base (overlays don't participate in layout negotiation), so a hero can never
  drive card width again, at any column count.
- **Add composer owns the whole screen.** The editor fills all space between
  the large title and a bottom stack (no bounded 160–220pt frame, no dead
  space — there's no card grid under the input on iOS, unlike the web's
  panel-over-grid). Full-bleed panel (12pt text inset only). Bottom stack
  order, top→bottom: URL chip → attachments row → subscription gate →
  location line → controls row. The location preview gets its own line
  directly above the controls, never inline between buttons.
- Controls row buttons are `.borderless` (was `.bordered`): seven bordered
  controls exceeded a phone's width, overflowing the composer off both display
  edges (Save clipped entirely off-screen).
- `MainTabView` accepts `--uitest-tab-view` / `--uitest-tab-ask` /
  `--uitest-tab-settings` launch arguments (same family as
  `--uitest-reset-auth`) so headless verification can land on a tab directly.

## 2026-08-28 · Capture panel hidden in conversations/focus states; gradient page-level; conversations search + pagination (web)

- The capture input panel is hidden while the Conversations list is open OR
  focus-sources is active — retrieval states; capture returns with the card
  grid. The animated gradient backdrop moved from inside the panel to the
  page level (Index content wrapper), so the ambience persists in every
  state; conversation rows are positioned (`relative`) solid white above it.
  Dark mode is not wired on web (`darkMode:["class"]`, no provider) —
  light-only for now.
- Focusing sources from a FLOATING mole auto-pins it — the floating panel
  otherwise overlays the focus pill's Clear button (found via real-browser
  pixel/click verification).
- **Conversations list gained search + pagination.**
  `list_conversations(search_text, page_limit, page_offset)` v2 (migration
  `20260828100000`, applied): search matches title OR any message content
  (ILIKE), pages clamp 1–100, rows carry `total_count`. UI: debounced
  search box, "Showing X–Y of Z", 25/50/100 page-size select, Prev/Next.
  iOS: same RPC serves a paged history screen directly.
- iOS: if Ask/history surfaces share a screen with capture affordances,
  mirror the hide rule — no capture entry points while browsing
  conversations or a focused source set.
- **Letting go of loaded conversations (same-day addition):** collapsing the
  mole while an explicitly loaded old conversation is open clears the thread
  (reopen = mostly clean mole) and remembers it; an empty mole then shows a
  "Load previous conversation — <title>" restore banner at the top of the
  thread. A persistent "Start new chat" link sits beside "Earlier
  conversations" in the mole footer — it clears the thread and forces the
  next send into a brand-new session (gap rule bypassed; behavior
  unit-tested). Nothing is ever lost: old threads always remain in the
  Conversations list. iOS: mirror all three behaviors on the Ask surface.

## 2026-08-27 · Chat sessions, retrieval-only mole, Conversations view, focus sources (web + contract)

Spec: `docs/superpowers/specs/2026-08-27-chat-sessions-design.md` ·
Prototype: `docs/superpowers/prototypes/2026-08-27-chat-workspace.html`

- **Sessions (all platforms — client convention):** a conversation is a burst
  of activity; 3+ hours of silence starts a new one. Resolve on open AND on
  send: latest conversation by `last_message_at`, continue iff < 3h old, else
  create a row lazily on first send (`title` null → auto-titled from the
  first question via `generate-title`). Send only the current session as
  `conversationHistory`. Explicitly opened old sessions resume (gap exempt).
  DB: `conversations.last_message_at` (trigger-maintained) + RPC
  `list_conversations()` → `(id, title, last_message_at, message_count,
  preview)` (migration `20260827120000_chat_sessions.sql`, applied).
- **Mole is retrieval-only (product decision, all platforms):** capture
  routing removed from the web mole (`moleRouting.ts` deleted); composer
  placeholder "Ask your stash…". iOS: remove `MessageRouting` from the Ask
  composer to match. Capture belongs to capture surfaces.
- **"Earlier conversations"** link replaces the footer hint under the mole
  composer; it swaps the main pane between the card grid and a bucketed
  Conversations list (Today / Yesterday / This week / month / older). Row
  click loads that session into the mole (pinning it if minimized).
- **Focus sources:** answers with sources show "⌖ Focus sources (n)"; click
  filters the card grid to the cited items in citation order with a
  "Showing n cards from this answer · Clear" pill. Focus overrides search
  filtering while active and always switches the main pane back to cards.
  Works on reloaded history via `messages.source_items`.

## 2026-08-27 · Ask Stash citations: item titles are inline links; sources row only for extras (server deployed + web)

When an answer names a saved item, the title itself is now a clickable link
that opens the card, and the bottom "Source(s):" row only lists sources NOT
already linked in the text — usually none, so it disappears.

- **Contract (server, deployed):** the model cites by writing item titles as
  markdown links targeting the citation number — `[Beyond the Basics](#3)` —
  and bare `[3]` markers only for claims that don't name the item. Each entry
  in the `done` frame's `sources` array now carries its citation number `n`:
  `{id, title, type, url, n}`.
- **Client baking (web; iOS/mac mirror this):** at stream end, rewrite the
  markdown using the `n` map — `](#3)` → `](#item=<uuid>)` and bare `[3]` →
  `[[3]](#item=<uuid>)` — and persist the BAKED text (util:
  `src/utils/chatCitations.ts`, unit-tested incl. idempotence). History
  reloads restore only message text, so baked links keep working forever;
  mid-stream `(#n)` targets render as plain text until baked.
- **Rendering (web):** ReactMarkdown custom `a` — `#item=` hrefs render as
  violet underlined buttons calling the same open-card handler as source
  chips; other hrefs open in a new tab. Bottom row = sources filtered by
  `extractLinkedItemIds(content)`. Read-aloud flattens links to their text.
- iOS: parse `[text](#item=<uuid>)` in chat markdown into taps that open the
  item; hide any source chip whose id already appears inline.

## 2026-08-26 · Ask Stash goes agentic: tool-calling retrieval loop (server, deployed)

Retrieval-overhaul phase 3. `chat-with-all-content` rewritten from one-shot
RAG (embed message → one search → stuff 7,000 chars) into a **tool-calling
loop**: the model drives retrieval via `search_stash` (hybrid search with
type/date/tag filters) and `get_item` (full notes/summary/captured text), up
to 4 tool rounds per turn. What this changes for users on every platform:

- **Follow-ups finally work** — "what were the two priorities from it
  again?" gets rewritten into a real query using conversation history before
  searching (verified live).
- Time/type-anchored questions ("that PDF from last week") can use real
  filters; the system prompt knows today's date.
- The model reads items in full before quoting, instead of seeing only a
  1,500-char truncation; per-item context is no longer pre-truncated.
- Honest empty results: it searches before ever claiming something isn't
  saved, and says so plainly when it isn't. App-usage questions skip search.
- Model: `gpt-5-mini` (reasoning_effort low) replaces `gpt-4.1-mini`.

**Wire contract unchanged** — same `{delta}` / `{done, sources}` SSE frames;
no client changes needed anywhere. New optional `{status:"searching"|"reading"}`
frames stream while tools run (all frames remain valid JSON; parse and ignore
unknown keys). `sources` is now the items the answer cites (fallback: items
read in full) rather than everything retrieved. History cap raised 6 → 10
turns. Clients that want a "searching your stash…" shimmer can render the
status frames (web doesn't yet). Contract details in `PLATFORM_API.md`.

Shared auth for edge functions moved to `_shared/auth.ts`
(chat-with-all-content's local copy removed; search-items uses it too).

Known issue found while testing (NOT fixed, needs a product decision):
deleting an auth user fails with an FK violation once they own items —
`items_user_id_fkey` references `auth.users` without `ON DELETE CASCADE`.
Account deletion is effectively broken for active accounts.

## 2026-08-26 · `search-items` endpoint; web library search goes server-side; chat context gains dates (server + web, deployed)

Retrieval-overhaul phase 2. **`search-items` is the canonical search surface**
— every retrieval consumer (web toolbar today; chat tool-calling, MCP, and
iOS/Siri next) should build on it rather than on the RPC directly.

- **New edge function `POST /functions/v1/search-items`** (Supabase JWT auth).
  Request: `{ query?, types?, tags?, after?, before?, limit? }` — `types` is
  an array of item types, `tags` any-of (lowercased), `after`/`before` ISO
  timestamps, `limit` 1–50 (default 20). Two modes:
  - *query mode* (non-empty `query`): hybrid semantic+keyword search
    (embeds the query, calls `hybrid_search_content` v2), deduped to one
    result per item, relevance-ordered.
  - *filter mode* (no query): newest-first listing under the same filters.
  Response: `{ results: [{ id, title, type, url, created_at, description,
  snippet, score }] }` (`score` null in filter mode; `snippet` is the best
  matching chunk in query mode, the description otherwise).
- **`hybrid_search_content` v2** (migration
  `20260826110000_search_filters_recency.sql`): optional `filter_types`,
  `after_ts`/`before_ts`, `filter_tags` (any-of), and a gentle recency boost
  (`score += recency_weight/(rrf_k + age_days)`, default weight 0.3, pass 0
  to disable). Result rows gained `item_description`. Existing callers
  unaffected (new params have defaults). Still service_role-only.
- **Web library search now upgrades to server results** (`useServerSearch`
  hook → `search-items`, 300 ms debounce, ≥2 chars, per-query session
  cache). While pending or on failure the instant client substring filter
  keeps working; when results land the grid switches to **relevance order**
  (otherwise chronological). Net new capability on web: keyword search
  finally reaches `page_body`/`summary`, plus semantic matching. iOS: mirror
  by calling `search-items` when the library search box is non-empty (keep
  the local filter as the instant/offline layer).
- **Ask Stash context blocks now carry saved dates** — headers read
  `[n] Title (type · saved 2026-08-26)` and the system prompt tells the
  model to use them for time-anchored questions ("when did I save…").
  No client changes; SSE contract unchanged.

## 2026-08-26 · Search hygiene: RPC locked to service_role, FTS covers summaries/URLs, fairer ranking (server, deployed)

Retrieval-overhaul phase 1. No client code changes required on any platform,
but the contracts below matter to anyone building retrieval features.

- **`hybrid_search_content` is no longer callable with the anon or user JWT**
  (REST probe now returns 42501). It is `SECURITY DEFINER` with a
  caller-supplied `target_user_id` — tenancy lives in the edge functions —
  so the default PUBLIC grant let any API-key holder read any user's chunks.
  Clients must never call it directly; go through `chat-with-all-content`
  (or future search endpoints). Legacy `search_similar_content` is dropped.
- **RPC result shape gained `item_created_at`** (timestamptz) so callers can
  render/reason about recency. Existing callers are unaffected (they select
  fields by name).
- **Ranking fixes:** the FTS top-30 is now actually ordered by rank before
  the cut (was arbitrary), and vector hits are capped at **2 chunks per
  item** so one long document can't crowd the fused list (parity with the
  SMS path's dedupe).
- **`items.fts` rebuilt to include `summary` and `url`** — keyword search
  now reaches AI summaries and link hosts/slugs. All 563 items repopulated.
- **`increment_tag_usage` now enforces tenancy** (`user_uuid` must match
  `auth.uid()` for authenticated callers; service-role passes through; anon
  grant revoked). Web/iOS callers pass their own id already — no change.
- **Embedding chunker fixed (`generate-embeddings`, deployed):** whitespace
  normalization was collapsing newlines before the paragraph splitter ran,
  so every text >1200 chars went through the blind sliding window.
  Paragraph-aware chunking now actually fires; giant single paragraphs get
  windowed with overlap. Applies to new/re-embedded items only (no backfill).
- Migration: `supabase/migrations/20260826090000_search_hygiene.sql` (applied
  to prod + recorded). `src/integrations/supabase/types.ts` regenerated from
  the live schema (was stale: missing `hybrid_search_content`, `fts`,
  `attributes`, scrape-retry columns).

## 2026-08-26 · Link cover images verified at save; media filename chip everywhere (server + extension)

- **Only verified images land in `file_path` (deployed):** the deep
  `extract-link-metadata` pass now (a) sanitizes the extracted image URL
  (first token of srcset-style values, trailing commas stripped, page URLs
  like YouTube watch links rejected) and (b) drops any external image that
  doesn't answer a GET with `image/*` bytes ≥100B (`verifyRemoteImage`,
  `_shared/blockedContentFallbacks.ts`). `add-url` and
  `retry-pending-scrapes` apply the same check before writing a raw external
  URL; a stored copy in `previews/` still always wins. Net effect for all
  clients: `file_path` on a link is either our own storage path or an
  external URL that served an image at save time — cards degrade to the
  favicon plate instead of a broken cover. One-time cleanup ran 2026-08-26:
  9 of 28 stored external URLs were dead/malformed and were nulled.
- **Media filename chip is now universal (extension):** the web upload path
  always records `attributes.media.file_name`; the extension previously only
  did when the source URL ended in a known image extension. It now
  synthesizes a name for any http(s) source — path basename (or hostname as
  last resort) plus the resolved format extension ("photo-14556789.avif") —
  and also records `attributes.media.source_url` for provenance. iOS/mac:
  mirror this — every media save should carry `media.file_name`; cards show
  it as a mono chip under the description and the search bar matches it
  (`src/utils/itemSearch.ts`). Only data:/blob: sources may omit it.

## 2026-08-26 · Assembling copy + dim; AVIF vision; junk-title rescue (web + server)

Three related fixes; the server parts are deployed and benefit every channel
with zero client changes.

- **Assembling card, new look (web; iOS/mac mirror the rules):** the chip now
  reads **"Gathering more info…"** (was "Filling in the blanks…"), and while
  assembling the whole card sits at **50% opacity with a subtle pulse**
  (0.5 → 0.65, 2.6s loop) instead of the old near-invisible 1.0 → 0.96
  breathe. Full opacity returns when assembly completes/retires.
  `prefers-reduced-motion`: static 50%, no pulse. Same state machine as the
  entry below (`itemAssembly.ts` unchanged).
- **`analyze-image` accepts every stored image format (deployed):** OpenAI
  Vision only takes png/jpeg/gif/webp, so avif/heic/tiff/bmp/ico/svg uploads
  silently produced no title/description (confirmed: extension AVIF saves).
  The function now routes non-safe extensions through Supabase Storage's
  `render/image` transcoder (`Accept: image/jpeg`, width 1024) and inlines
  the result as a base64 data URL for the vision call. Any transcode failure
  falls back to the original URL (fails honestly, as before). Clients keep
  uploading originals — do **not** transcode client-side.
- **Challenge-page titles never stick (deployed):** bot walls that 200 with
  "Client Challenge" / "Just a moment…" pages were being stored as titles.
  New shared `isBlockedPageTitle` (`_shared/blockedContentFallbacks.ts`):
  `add-url` discards challenge-page quick-fetch metadata and lets the deep
  pass replace junk; `extract-link-metadata` treats a junk title as blocked
  (triggers the rescue cascade) and never returns one; `retry-pending-scrapes`
  treats junk titles as placeholders worth upgrading.
- **Final-review headline rescue (deployed):** after a successful scrape,
  `scrape-page-content` checks the stored title — if it's still junk, the
  bare hostname, or the raw URL, it derives the real headline from the
  scraped content (`deriveTitleFromContent`, gpt-4o-mini, ≤140 chars) and
  writes it (also folded into the re-embed text). User-typed titles are
  structurally safe: they never match the junk patterns.

## 2026-09-03 · Web sign-out is local-scope everywhere (was logging out every device)

- **Root cause of "the chrome extension signs me out every few days":** the
  header's Sign out (`HeaderSection.tsx`) called `supabase.auth.signOut()`
  bare, which in supabase-js defaults to **scope `global`** — it deleted
  every session on the account (extension, iOS, other browsers, and the
  prod extension even when the sign-out happened on `localhost:3000`, since
  dev and prod share one Supabase project). Confirmed from the auth audit
  log: each extension logout matched a `POST /logout` from the web app, and
  after each one no older `auth.sessions` rows survived. The 2026-08-21
  scope:'local' fix only covered `useAuth.signOut`; this call site bypassed
  it (unchanged since the June 2025 scaffold).
- **Contract (all platforms):** signing out on one surface signs out *that
  surface only*. Web now routes every sign-out through `useAuth.signOut`
  (scope `local`); iOS already uses `.local`. A vitest guard
  (`HeaderSection.test.tsx`) fails the build if any bare
  `auth.signOut()` reappears in `src/`. The extension's own sign-out never
  hits the logout endpoint (it only clears its local session) — unchanged.
- **mac agent:** verify `stash-mac` passes `scope: 'local'` too; a global
  sign-out from any client still logs the extension out.

## 2026-08-26 · Feed: "assembling" cards while enrichment lands (web)

Behavior contract first — iOS/mac should mirror the *rules*, with
platform-native motion.

- **A fresh capture visibly assembles.** While an item is less than
  `ASSEMBLY_WINDOW_MS` (2.5 min) old **and** the pipeline still owes it
  pieces, its card breathes gently and carries a small top-left chip:
  **"Filling in the blanks…"**. Each piece animates in as realtime delivers
  it (short rise + violet wash echoing the card shadows). When the last
  expected piece lands, the chip flips to **"Filled in ✓"** for ~2s and
  everything goes quiet. If enrichment dies, the state retires honestly at
  the window edge — no eternal pulsing.
- **Expected pieces per type** (ETHOS: never fake enrichment — only promise
  what reliably arrives): image → description + AI title (placeholder-title
  rule from the entry below); audio/video → description; PDF → summary (the
  existing "summary present = done" contract); links and notes promise
  nothing, but whatever does land (description, better title, preview image,
  summary) still gets its reveal moment.
- **Mechanics** (`src/utils/itemAssembly.ts`, pure + unit-tested): the grid
  diffs each realtime items snapshot against the previous one
  (`landedPieces`) — no new realtime wiring, so it works for captures from
  **any** channel (web box, chrome extension, iOS share sheet, SMS). New
  cards younger than 15s also get an entrance rise.
- **Motion discipline:** transform/opacity only; `prefers-reduced-motion`
  disables all of it (the chip still renders statically — the information
  survives, the motion doesn't).

## 2026-08-26 · Image titles are AI-derived; filenames become metadata (all channels)

Written for the iOS/mac agents — contracts first.

- **`analyze-image` contract change (deployed):** the vision pass now also
  returns a `TITLE:` line — ultra-short (3–7 words), "Screenshot of X" when
  the image is a screenshot of an app/website/chat/code/any UI, "Image of X"
  otherwise. On its DB-write path the function replaces the item's title
  **only when the current title is a placeholder**: empty, equal to the
  storage basename, or any filename-looking string (`*.png`, `*.jpg`, …). A
  user-typed title is never touched. `precomputed` may now carry `title`;
  filename-ish precomputed titles are ignored server-side. If neither vision
  nor precomputed supplies one (older client, older chip result), the title
  is composed from the description via gpt-4o-mini — so **every channel gets
  the behavior with zero client changes**.
- **The filename is metadata, not a title.** When a *real* filename title is
  replaced ("CleanShot 2026-08-11.png" — not our own `<timestamp>.ext`
  storage names), it's preserved into `attributes.media.file_name`
  (whole-blob merge, existing key from the media-attributes design). It now
  also rides in the re-embed text, and the web search predicate
  (`src/utils/itemSearch.ts`) matches it — finding an image by its filename
  works even though the filename no longer appears as the title. Web cards
  already render `media.file_name` as the mono chip on image/audio/video.
- **Clients:** web chip analysis captures the vision title, so box-saved
  images carry the AI title from first paint (no rename flicker). Chrome
  extension v1.1.0 sends `attributes.media.file_name` derived from the image
  URL's path. **iOS action item:** keep sending the original filename (as
  `title` or ideally `attributes.media.file_name`) — the server upgrade path
  then applies unchanged.

## 2026-08-26 · Chrome extension: "Stash it" capture surface (`extension/`)

Written for the iOS/mac agents — contracts first.

- **New capture client** at `extension/` — Chrome MV3, plain JS, no build
  step, no dependencies; loads unpacked (not on the Web Store yet). Three
  gestures, all against existing platform endpoints — **zero server changes**:
  - Toolbar button → `add-url` with the active tab's URL (http/https only;
    anything else shows the failure badge).
  - Right-click selected text → **"Stash it"** → `add-note` with the
    selection as `content`. Exact text (newlines preserved) is read via a
    `scripting` injection; where injection is blocked (PDF viewer, chrome://
    pages) it falls back to Chrome's whitespace-collapsed `selectionText`.
  - Right-click an image → **"Stash it"** → service worker fetches the image
    bytes (with that site's cookies), uploads to
    `stash-media/<userId>/<Date.now()>.<ext>` (same naming as web
    `fileUploader.ts`), then `add-file` — so it becomes a real image item
    with vision/OCR enrichment, not a link. 20 MB cap mirroring
    `MAX_FILE_SIZE_MB`; `blob:` URLs and non-image content-types (CDN error
    pages) fail visibly rather than saving garbage.
- **Deliberate scope decision (Will, 2026-08-26): no annotation UI
  anywhere.** Capture is zero-input; context gets added later in the app.
  Selection saves as a plain note — no source URL attached in v1.
- **Feedback contract:** transient badge on the toolbar icon, scoped to the
  originating tab — `…` while saving, green `✓` ~2.2 s on success, red `!`
  ~4 s on failure. No page injection for feedback.
- **Auth:** one-time email/password sign-in (the options page doubles as the
  sign-in page), raw GoTrue REST (`/auth/v1/token`, the path
  `PLATFORM_API.md` sanctions), session in `chrome.storage.local`,
  refresh-on-demand (<60 s token life → refresh, single-flight, one retry on
  401) — the MV3-safe pattern, since service-worker sleeps kill timers. A
  signed-out save opens the sign-in page instead of failing silently.
- **Mac-agent note:** this is the desktop-browser sibling of the iOS share
  extension, but it does **not** implement iOS's direct-vs-queue Outbox rule
  — any failure just shows `!` and the user retries. Judged acceptable for a
  v1 on an effectively always-online desktop; adopt the Outbox pattern if
  offline capture ever matters here.

## 2026-08-22 · iOS share extension: system share sheet capture (iOS plan 5)

Written for the web/mac agents — contracts first.

- **The app now has a share extension** (`StashShareExtension`, bundle id
  `it.gostash.stash.share`) — share links, text, photos/screenshots, videos,
  audio, and PDFs into Stash from any app via the system share sheet.
  Activation rule (Apple's real constraint keys — there is no separate
  "audio" key; audio shares through the generic file count): 1 web URL,
  unlimited plain text, up to 10 images, up to 3 movies, up to 5 generic
  files. Whichever rule matches the shared UTIs activates the extension;
  anything outside every count (e.g. 2 URLs at once) doesn't offer Stash at
  all. **Correction (final fix wave, honesty pass):** the "up to 5 generic
  files" activation clause accepts **any** file UTI — it is not scoped to
  PDFs — but `ProviderLoader` only maps `public.image`/`.movie`/`.audio`/
  `com.adobe.pdf` providers into a `SharedObject`. Share a file type outside
  that list (a `.docx`/`.txt` from the Files app, say) and the extension
  still opens and still activates, but that attachment comes back
  unreadable and surfaces through the existing "N item(s) couldn't be read"
  line — it doesn't silently vanish, but it also doesn't save. **Plan-6
  candidate:** a generic-`else` staging branch in `ProviderLoader` (stage
  the raw bytes, tag with a best-guess mime, let `add-file` decide) would
  light up the OOXML support `add-file` already has server-side (see the
  2026-08-22 plan-4 entry below) for free, with no new server work.
- **Session + durable state are shared with the app via two OS mechanisms:**
  an App Group (`group.it.gostash.stash`) holds the Outbox/staging
  directories both processes read and write, and a shared keychain access
  group holds the Supabase auth session (a custom `AuthLocalStorage` backed
  by `SecItemAdd`/`SecItemCopyMatching` scoped to that access group) — the
  extension never re-authenticates, it just sees the app's session directly.
  **One-time cost:** moving the session onto a new keychain service string
  means every existing dev install signs out once on first launch after this
  ships (dev-stage decision, nothing migrated, no real users affected).
  **Decision of record (final fix wave):** the plan's original constraint
  was "the extension never initiates a token refresh"; the shipped Save
  path actually resolves its access token via `auth.session` (the same
  refreshing accessor the full app uses elsewhere), not the non-refreshing
  `auth.currentSession` the compose card's own `load()` uses — so a Save can
  trigger a network refresh call if the stored token has expired. Reviewed
  and **kept**: the SDK single-flights a refresh per process, and any
  resulting failure still falls back to the Outbox exactly like any other
  Save-time failure — judged better UX than forcing an expired-token share
  to queue when a quiet refresh would otherwise have succeeded.
- **Direct-vs-queue rule** (a mac client sharing this convention should match
  it): URLs/text always try a direct `add-url`/`add-note` first. Files ≤ 8 MB
  direct-upload (streamed from a staged file on disk — never loaded into
  memory whole) + `add-file`. Files > 8 MB skip the direct attempt and go
  straight into the shared Outbox with `local_file_path` pointing at the
  still-staged file, for the app to drain on next foreground/launch. **Any**
  failure on any unit (network/auth/5xx) falls back the same way — the user
  always sees a success line ("Saved to Stash" / "Saved — will sync"), never
  an error, then the sheet auto-dismisses (~0.8 s, no "open app" affordance).
  Because app + extension can now drain the same Outbox directory from two
  OS processes, drain claims are cross-process: each pending entry is
  claimed via an atomic `O_EXCL` sidecar file before sending (stale after 10
  min, then reclaimable), so the two processes can never double-send one
  entry. **A mac client adopting this Outbox container would need the same
  claim-sidecar convention, not just the same directory.**
- **Multi-item shares are N single-object items, never a collection** — the
  OS handing over several attachments is not a user grouping decision, so
  each becomes its own item; a note typed on the compose card attaches to
  the **first** item only. **New decision of record:** if any shared object
  is a URL, it is hoisted to index 0 before submit, so the note always lands
  on the URL regardless of the OS's own ordering or how many files came with
  it. This makes iOS's **URL-first deterministic** note-placement rule (see
  the entry below) span **both** iOS capture surfaces — the Add-tab composer
  and the share extension — consistently. It is still an iOS-only rule, not
  applied on web; see the flagged divergence below, now updated.
- **New decision of record — shared text + a typed note plain-merge into
  `content`:** when the OS hands the extension plain text (not a URL) and
  the user also types a note, the two are not stored as separate fields —
  the shared text is treated as the base content and the note is appended as
  a new paragraph (the same helper the notes-append composer uses — the
  web's own "paste, then annotate" model). No structural marker separates
  the two in v1.
- **Subscription gate is a cross-process cache, not a live check:** the
  extension has no budget to spend on a network subscription lookup before
  rendering, so it reads a cached bool (`subscription.canAddContent`) from
  `UserDefaults(suiteName: "group.it.gostash.stash")`, written by the app's
  `SubscriptionStore` on **every** resolve — success, error, and reset, not
  just success. Missing key (fresh install, never resolved yet) fails open
  (Save enabled, no gate line), matching the live gate's own "open while
  unknown" rule. `false` → Save disabled + an inline "Subscribe on
  gostash.it to add items" line. **No Supabase session at all** (not merely
  gated) shows only "Sign in to the Stash app to share." + Cancel — nothing
  is staged or queued, since there's no user id to scope a directory under.
- **Location pin is hidden, not shown-then-blocked, when permission was
  never asked** (`CLLocationManager().authorizationStatus == .notDetermined`)
  — v1 scope decision, a prompt was judged too heavy for a save-and-dismiss
  surface. `.denied`/`.restricted` still show the pin. Observed live: the
  extension does **not** need its own permission grant — granting location
  to the **host app's** bundle id was sufficient for the extension process
  to read the authorized state too; no separate extension-scoped prompt
  appeared.
- **Mac note:** the App Group + Outbox-with-claims convention above is
  designed to generalize — a menubar app sharing the same container and
  using the same atomic-sidecar claim file would interoperate with iOS's
  Outbox directly, no protocol changes needed on either side.

---

## 2026-08-22 · Capture endpoints: `attributes` passthrough + server-side link flavor (iOS plan 4)

Written for the web agent — contracts first. This is the iOS client absorbing
the 2026-08-11→16 entry below into the platform API; the endpoint changes
apply to every caller, including web's own server-side/API paths.

- **`add-note`, `add-url`, `add-file` all accept an optional `attributes`
  object** in the request body now — the same whole-blob shape the web
  already writes client-side (`src/types/itemAttributes.ts`). Non-object
  (including array) values sanitize to `{}` server-side rather than 500ing.
  Web's own client-side `attributes` inserts are unaffected (this is additive
  — existing callers that never send `attributes` see no change); this only
  matters to you if some web code path calls these edge functions directly
  instead of inserting via the client SDK.
- **`add-url` now classifies `attributes.link.flavor` server-side when the
  caller doesn't supply one** (`supabase/functions/_shared/linkFlavor.ts`, a
  verbatim port of `src/utils/linkFlavor.ts:1-54`). Caller-supplied flavor
  always wins. **This closes the gap for any link saved through `add-url`
  without a client-computed flavor** — e.g. ChatMole/API-driven captures that
  don't run `UnifiedInputPanel`'s own client-side classification — with zero
  web code change required; the fix is entirely server-side.
- **`LocationSource` (`src/types/itemAttributes.ts:14`) widened**:
  `'browser-geolocation' | 'device-geolocation' | 'photo-exif' | 'manual'`.
  `'device-geolocation'` is iOS's CoreLocation-sourced fixes — same
  `CapturedLocation` shape as `'browser-geolocation'`, just a different
  collector. No web rendering change needed (the label/source distinction was
  already designed to be open-ended).
- **`add-file`'s document branch now gates on MIME** (parity with web commits
  83e9809 + c4cbdd0): exactly `mime_type === 'application/pdf'` enters the
  `quick-pdf-summary`/`extract-pdf-text` pipeline; the three OOXML mimes
  (pptx/docx/xlsx) invoke `extract-office-text`; everything else settles
  immediately via `generate-description` + `summary = description`. Was
  previously PDF-pipeline-for-everything on iOS's add-file (pre-dating the
  web's own 83e9809 fix) — now matches.
- **Flagged divergence, awaiting product sign-off — not yet aligned either
  direction:** iOS's single-object batch note-placement is **URL-first
  deterministic** (a detected URL is always its own unit and always receives
  the batch's note, regardless of attachment count or order) rather than the
  web's **chip-order** rule (`UnifiedInputPanel.tsx:754-873` — whichever
  object the user chipped first gets the note). The two agree whenever a URL
  is typed/pasted before attachments are added (the common case) and diverge
  only when files are attached first and a URL is added after. iOS's rule
  also happens to fix a pre-existing single-attachment+URL fold bug. Needs a
  decision: align iOS to chip-order, align web to URL-first, or keep the
  platform difference — tracked for plan 7, not resolved here. **Update
  (plan 5):** the share extension applies the identical URL-hoist before
  submit (see the 2026-08-22 plan-5 entry above), so this is now iOS's one
  internally-consistent rule across both its capture surfaces — the
  sign-off decision itself is still open.

---

## 2026-08-18 · Grid ordering: row-major chronology, not masonry columns

The dashboard grid is a plain row-major CSS grid again: **newest item
top-left, then left-to-right across the columns, row by row.** (The short-
lived masonry `columns` layout flowed top-to-bottom per column, which
scrambled reading order.) Each row stretches to its tallest card — card
bodies flex and footers pin to the bottom, so mixed hero heights still align
per row. Any client rendering the library must preserve this reading order:
reverse-chronological across the row, not down a column.

---

## 2026-08-17 · Office documents: no fake PDF processing + real text extraction

- **Only PDFs are "extracting."** `isDocumentProcessing` (the
  `summary IS NULL` overlay/edit-block marker) applies to PDFs only (mime
  `application/pdf`, or `.pdf` extension when mime is absent). Office formats
  must never enter a blocking processing state — they previously hung forever
  because only the PDF extractor writes `summary`.
- **Non-PDF documents settle instantly**: client writes `summary` =
  description right after insert. Never send non-PDFs to
  `extract-pdf-text`/`quick-pdf-summary` (they 500).
- **pptx/docx/xlsx get real extraction** via the new `extract-office-text`
  edge function (unzip + Office Open XML parsing, no external vendors):
  writes `page_body` (slide/paragraph/sheet text, "Slide N:" prefixes +
  speaker notes for decks), regenerates `summary` + `description` from real
  content, re-embeds the whole item. Clients invoke it fire-and-forget after
  settle with `{ fileUrl, itemId, fileName, mimeType }` — the item upgrades
  silently; a failure changes nothing. iOS: the add-file edge function should
  gain the same gate + invoke (it currently mirrors the old PDF-only logic —
  check before shipping office uploads on iOS).
- Office mimes display proper chips (`PPTX`/`DOCX`/`XLSX`/`PPT`/`XLS`/`DOC`),
  not truncated mime subtypes.
- Known limits: no OCR of text inside slide images; legacy binary `.ppt`/
  `.doc`/`.xls` settle without extraction; extraction capped at 50k chars.

---

## 2026-08-11 → 2026-08-16 · Capture rework, location, single-object model, card system

### Data contracts (apply to every client — read this even if you skip the rest)

- **`items.attributes` (jsonb, GIN-indexed, default `{}`)** — extensible
  per-item facts. TS shapes in `src/types/itemAttributes.ts`. Known keys:
  - `location`: `{ label, latitude?, longitude?, accuracy_m?, city?, region?,
    country?, source: 'browser-geolocation'|'photo-exif'|'manual', captured_at? }`.
    Only the friendly `label` is required. Hand-edited locations use
    `source:'manual'` and **must drop stale coordinates**. Never store a
    location the user didn't opt into.
  - `link`: `{ flavor: 'article'|'video'|'repo'|'book'|'social'|'generic',
    author?, duration_s?, stars?, read_time_min? }`. Flavor is classified once
    at save from the URL — port `src/utils/linkFlavor.ts` rules verbatim.
  - `media`: `{ duration_s?, file_name? }` — duration measured locally at
    capture; `file_name` is the original filename (titles are AI-derived;
    filenames are metadata, never titles).
- **Field semantics (all types):** `content` = the user's own note/annotation
  — including for links (moved out of `description` on 2026-08-16).
  `description` = the object's own text (og/AI). `page_body` = captured source
  material (scraped page, extracted doc text, **A/V transcripts** — moved out
  of `content` on 2026-08-16). `summary` = long AI summary. Rich notes are
  Novel/Tiptap JSON strings (`{"type":"doc",…}`); plain notes are plain text.
- **No "posted from …" text lines** in content — retired. Location renders
  from `attributes.location` only.
- **Single-object model:** one object = one item, always. Never create
  `type='collection'`. A capture with N objects saves N items; the note (if
  any) attaches to the **first**; show a polite notice ("Saved as N items —
  Stash keeps one object per item; your note went with the first one.").
  Legacy collections still render read-only (attachment strip) but are never
  created. Spec: `docs/superpowers/specs/2026-08-16-single-object-items-design.md`.

### Capture behaviors (web reference implementation: `UnifiedInputPanel` + `CaptureEditor`)

- Capture surface is **always visible** (minimize/collapse removed entirely).
  It animates on activation: slight lift/scale + violet ring.
- The note field is a rich editor (same engine as the edit sheet's notes tab):
  `/` slash commands (to-do list, headings, lists, quote, code, inline image),
  selection bubble menu. **Enter submits only while the note is a single plain
  paragraph**; inside any structure Enter belongs to the editor; Shift+Enter =
  line break; Escape clears.
- URLs typed/pasted become link chips (metadata fetched immediately); pasted
  images become analyzed file chips; the URL text is stripped from the note at
  save so it isn't stored twice.
- **Location pin toggle** sits next to Send: on enable, resolve device
  location → reverse-geocode to a friendly label (web uses BigDataCloud,
  key-less; label = "City, Region"), preview it next to the pin ("posted from
  Saratoga Springs, New York" — preview only, not stored text), cache ~5 min.
  Failures toast and flip the pin off. On save, write the full
  `attributes.location` (coords included) to **every** item in the batch.

### The card system (web reference: `src/components/cards/` + `ContentItemHeader/Content`)

Shared anatomy, top to bottom — every type follows it:
1. **Object zone** (see per-type below) — exactly two hero heights:
   standard **10rem** and tall **14rem** (portrait media, contained)
2. **Kicker** (links only): clickable domain, uppercase, above the title
3. **Title** — the object's own title, editorial serif (PPEditorialNew)
4. **Description** — extracted/og text, muted, clamped
5. **Annotation** — the user's `content`, violet left-bar treatment, clamped;
   always visually distinct from extracted text
6. **Metadata chips** — mono filename, `PNG · 1.0 MB`, duration `0:58`
7. **Footer** — date · location pin + label (from `attributes.location`) ·
   type badge (hover-revealed on web)

Per-type object zones:
- **link** by `attributes.link.flavor`:
  - `repo` → dark plate: mono `owner/repo`, description, (stars/language when
    enrichment lands)
  - `video`/`book` with preview image → tall contained-on-blur hero
    (`video` adds play overlay), domain pill at bottom
  - others with image → standard cover
  - **no usable image → favicon plate**: letter avatar + domain +
    "preview limited · saved anyway". Never a broken or decorative hero.
- **image** → aspect-aware: portrait (h > w×1.05) renders contained on a
  blurred self-backdrop at tall height; landscape covers standard height;
  missing file → labeled file plate (never a broken img)
- **video** → inline player, duration badge from `attributes.media.duration_s`
- **audio** → no hero; player + title + transcript-excerpt description + chips
- **document** → file plate header (icon + mono filename + `PDF · size`)
- **text** → no hero; the note text IS the body (AI description not shown)
- **collection (legacy only)** → rich note + attachment tile strip
- **No decorative gradient heroes anywhere.** Grid is masonry columns
  (1/2/3 by width), not fixed rows.

### Edit sheet

- Location row under description: click to edit, Enter/blur saves, clearing
  removes; manual edit ⇒ `source:'manual'`, coords dropped. "Add a location"
  affordance when absent.
- Notes section sits **above** the (legacy) Attachments section; the section
  is called "Attachments", not "Collection Items".

### Pending enrichment (designed, not yet captured — don't fake these)

`link.author`, `link.duration_s` (oEmbed), `link.stars` (GitHub API),
`link.read_time_min`; venue-level location names (re-geocode from stored
coords). Chips render only when the data exists.

### Deeper reading

- `docs/superpowers/specs/2026-08-11-capture-panel-upgrade-design.md`
- `docs/superpowers/specs/2026-08-16-single-object-items-design.md`
- Live visual reference: dev-only route `/design/cards` (mock gallery + real
  wired components)
