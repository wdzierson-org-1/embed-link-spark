# UI changes — cross-platform log

Purpose: every meaningful web-UI/product-behavior change lands here as a dated
entry so the agents building the **iOS** (`ios/`) and **macOS** clients can
mirror behavior and data contracts without reverse-engineering the web code.
Newest entries first. Write for implementers on another platform: contracts
first, visuals second, with pointers to specs and source.

---

## 2026-08-28 · Capture panel hidden in conversations/focus states; solid conversation rows (web)

- The capture input panel is hidden while the Conversations list is open OR
  focus-sources is active — those are retrieval states; capture returns with
  the normal card grid. (Side effect by design: the panel's 200vh gradient
  backdrop disappears too, so those views render on the plain background.)
- Conversation rows are guaranteed solid white (`relative z-10` above any
  page backdrop overlays). Dark mode is not currently wired on web
  (`darkMode: ["class"]` configured, no theme provider), so light-only.
- iOS: if the Ask/history surfaces share a screen with capture affordances,
  mirror the same rule — no capture entry points while browsing
  conversations or a focused source set.

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
