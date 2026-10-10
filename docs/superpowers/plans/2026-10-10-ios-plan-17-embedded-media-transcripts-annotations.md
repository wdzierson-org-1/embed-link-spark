# Stash iOS Plan 17: Embedded media, the transcript tab, full screen, timestamped notes — and the October 9 parity backlog

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Bring the iOS detail sheet level with the web item panel as of 2026-10-10: a link's own
player (YouTube, TikTok, Reels, Vimeo, Loom, Google Slides, Figma) in place of its picture; a
real PDF reader, Office files in Microsoft's viewer, HTML uploads in a web view; a transcript tab
for video links; full screen for every media stage; timestamped notes (`[1:42]` markers that
seek the player, `+ note at 1:42` while playing). First, land the October 9 web changes iOS has
not mirrored yet (pins and the `all | pinned` view, the card menu, share links, the kind tag as
status, the address-first panel with a cancel cell, the editable summary, one-line notes,
"Resurface in").

**Architecture:** Round 0 is the parity backlog (file-disjoint tasks, three in parallel). Round 1
adds the media stages behind one `MediaStage` container (embed / document / picture) and the
transcript tab. Round 2 adds full screen and the media clock + timestamped notes. Then a
whole-branch review, a fix wave, and the wrap (docs, suites, a TestFlight build).

**Tech Stack:** SwiftUI (iOS 17 floor), StashKit, WKWebView (embeds, Office viewer, HTML), PDFKit
(`PDFView`), AVKit (`AVPlayer`/`AVPlayerViewController`), XCUITest.

**Spec:** `docs/ui-changes.md` entries dated **2026-10-09** (four) and **2026-10-10** (two) —
contracts first; DESIGN-v2 §12.3, §12.6, §12.8, §12.15; DESIGN.md's iOS typography/controls
contract (plan 16); `docs/superpowers/specs/2026-09-05-youtube-transcript-enrichment-design.md`
(the transcript data contract) and `docs/superpowers/specs/2026-10-10-panel-annotation-exploration.md`.

## Global Constraints

- **Contracts are the web's; do not invent new ones.** Every column, attribute and string is in
  the change-log entries above. If iOS needs something the web didn't define, write it into
  `docs/ui-changes.md` in the same branch.
- **Lanes stay clean** (CLAUDE.md): `content` is the person's words (markers included);
  `page_body` is captured source (a transcript once `attributes.link.transcript` is set);
  `attributes` is written whole, preserving keys you don't model (`pinned_at`, `share_token`,
  `shared_at` are columns, not attributes).
- **Never fake enrichment.** A video link without `attributes.enrichment.evidence.transcript === true`
  has no transcript; the tab says "No transcript for this video yet." — never show `page_body` as one.
- **Third parties:** Office files go through `https://view.officeapps.live.com/op/embed.aspx?src=<public URL>`
  (Will accepted that Microsoft fetches the file). HTML uploads load in a WKWebView with a
  non-persistent data store and navigation blocked to other hosts (the web's sandbox equivalent).
- **Keep:** DESIGN.md tokens and the plan-16 typography/controls contract, accessibility
  identifiers, 44 pt hit targets, Dynamic Type, VoiceOver labels on icon-only cells.
- **Process:** a worktree based on **origin/main** (`d9c2530c` or later; web and iOS now land on
  main together — audit `git log` before merging). Single writer per file per round. Max 2
  concurrent `xcodebuild` users; `swift test --package-path ios/StashKit --scratch-path /tmp/sk-<task>`.
  UI tests use the `will+uitest` fixture (`ios/.env.test.local`); delete anything you create on it.
  Never push; commit with the trailer `Co-Authored-By: <your model> <noreply@anthropic.com>`.

---

## Round 0 — the October 9 parity backlog

### Task 0.1: Pins, the `all | pinned` view, and the card menu

**Files:** `ios/StashKit/Sources/StashKit/Item*.swift` (model: `pinned_at`), the library/View tab
list + toolbar, the card context menu, `ios/StashUITests/*`.

- [ ] Model `items.pinned_at` (timestamptz, null when not pinned); include it in the list projection.
- [ ] Card context menu reads: `Pin this` / `Unpin` · `Share to feed` / `Unshare from feed`
      (un-sharing also clears `supplemental_note`) · `Resurface in…` ▸ `1 day · 3 days · 5 days`
      and `Don't resurface` · `Delete this` behind a confirmation: "Delete this item?" / "“{title}”
      and everything Stash knows about it will be removed. This can't be undone." — Cancel / Delete.
      "Report a problem" is gone. Visitors to a public feed see only Comments.
- [ ] A pinned card wears a `pinned` tag (with `public` / `due`). Once anything is pinned the
      toolbar shows two tabs, `all · N` and `pinned · M`; `all` keeps the normal order; `pinned`
      lists pins newest-pinned first; the view falls back to `all` when the last pin goes.
- [ ] Tests: menu items and labels by state; confirmation; tabs appear/disappear; pinned order.

### Task 0.2: Share links

**Files:** the detail sheet's top bar, a `ShareLinkSheet`, StashKit `ShareToken.swift`.

- [ ] A share cell in the detail sheet's bar. First tap mints a token (10 chars of
      `[A-Za-z0-9]`, `SecRandomCopyBytes` with rejection sampling), writes `share_token` +
      `shared_at = now` through the normal owner update, copies `https://www.gostash.it/s/<token>`,
      and shows the share sheet (address, copy, **Stop sharing** → both columns null). A shared
      item's cell wears the accent; a tap only opens the sheet. On a unique violation, mint again.
- [ ] Nothing else: the page at `/s/<token>` and its link preview are the web's.
- [ ] Tests: token shape; mint-once; stop sharing clears both columns.

### Task 0.3: The detail sheet, October 9 shape

**Files:** `ios/Stash/Detail/ItemDetailView.swift`, `ItemDetailContent.swift`, `DetailURLBar.swift`,
`NotesEditor.swift`, `SectionHeader.swift`.

- [ ] Order: for links the address bar is first, above the title; then title, description, media,
      the source tabs, notes, details, sharing. The source section has no label: its tabs sit left
      on the rule, a full-size icon right opens the active tab full screen (Esc/close returns).
- [ ] The address bar, editing: a red × (cancel) beside the accent ✓ (save).
- [ ] The summary is editable in place (tap → field; leaving saves `summary`, empty clears it;
      cancel abandons). Original content and transcripts are read-only.
- [ ] Notes: empty notes are one line of body text, "Add a note…"; a tap opens the editor focused
      with the accent ring; leaving an empty editor collapses it and writes nothing (treat null,
      whitespace, the empty editor document `{"type":"doc","content":[{"type":"paragraph"}]}` and
      `<p></p>` as empty); the formatting hint only while focused.
- [ ] The kind tag on a card is the machine's status while Stash reads the save (`| gathering more
      info…`), then `✓ all done!` → the kind → hidden at rest (iOS: keep the kind visible at rest,
      there is no hover; play the status → all done → kind sequence, no fade).
- [ ] Tests for each.

---

## Round 1 — the media stages and the transcript tab

### Task 1: `Embeds.swift` and the embed stage

**Files:** `ios/StashKit/Sources/StashKit/Embeds.swift` (+ tests), `ios/Stash/Detail/MediaStage.swift`
(new), `EmbedWebView.swift` (new).

- [ ] Frame from `attributes.link.canonical_url ?? attributes.enrichment.evidence.canonical_url ?? url`
      (`embedSourceFor` on the web): a TikTok shared from the app is a `tiktok.com/t/…` short link
      with no video id; add-url stores the resolved address in `link.canonical_url`, and
      enrichment (`scrape-page-content`, for saves that never passed through add-url) stores it
      as `enrichment.evidence.canonical_url` (docs/ui-changes.md 2026-10-10).
- [ ] Port `src/utils/embeds.ts` exactly: the same hosts, id rules and frame addresses (YouTube
      no-cookie with `enablejsapi=1`, Vimeo, Loom, TikTok long form only, Instagram
      reel/reels/p/tv → `/embed/`, Google Slides `/embed`, Figma `embed?url=`); portrait vs
      landscape; `label`. Unit-test with the web's cases (`embeds.test.ts`).
- [ ] `MediaStage` chooses: embed → `EmbedWebView` (WKWebView, `allowsInlineMediaPlayback`,
      landscape at 16:9 full width, portrait centred 340 × 604); else the picture as today.
- [ ] An embed that fails to load (offline, blocked) falls back to the picture.

### Task 2: The document stage

**Files:** `ios/Stash/Detail/DocumentStage.swift` (new), `MediaStage.swift`.

- [ ] `documentKind(filePath, mime)` as on the web (`pdf` / `office` / `html` / `other`).
- [ ] PDF: PDFKit `PDFView` in single-page mode with previous/next and `page 3 of 12` in the
      micro label style; swipe pages.
- [ ] Office: WKWebView at the Microsoft viewer address. HTML: WKWebView with
      `WKWebsiteDataStore.nonPersistent()`, JavaScript on, navigation to other hosts cancelled.
- [ ] `other`: download/open only, as today.

### Task 3: The transcript tab for video links

**Files:** `ios/StashKit/Sources/StashKit/ItemRules.swift` (`contentTabsConfig`), its tests,
`ItemDetailContent.swift`.

- [ ] `contentTabsConfig` takes the item (type + `attributes.link.flavor` +
      `attributes.enrichment.evidence.transcript`): video links → `summary | original content | transcript`;
      with a transcript (`evidence.transcript === true`) → `summary | transcript`. Model
      `EnrichmentEvidence { transcript?: Bool, transcript_source?, duration_s?, author? }` under
      `enrichment.evidence`, preserving unknown keys.
- [ ] The tab shows `page_body` read-only only when the flag is set; otherwise "No transcript for
      this video yet."
- [ ] Tests mirror `editPanelTabs.video.test.ts`.

---

## Round 2 — full screen, the clock, timestamped notes

### Task 4: Full screen for every stage

**Files:** `MediaStage.swift`, `ItemDetailView.swift`.

- [ ] A full-size cell on every stage (44 pt target; the web calls it "full size" and has no
      separate browser-fullscreen cell any more): video → `AVPlayerViewController` full screen;
      embeds, documents and pictures → a `fullScreenCover` with the same view (keep the view
      instance: a playing embed must not reload), an ink bar naming the stage and a
      close/minimize cell; the system swipe-to-dismiss closes it.

### Task 5: The media clock and timestamped notes

**Files:** `ios/StashKit/Sources/StashKit/Timestamps.swift` (+ tests), `NotesEditor.swift`,
`MarkdownBlocksView.swift`, the player views, `MediaStage.swift`.

- [ ] `Timestamps.swift`: `formatTimestamp(seconds)` (`m:ss`, `h:mm:ss`), `parseTimestamp`,
      `findTimestamps(text)` — the web's rules exactly (`utils/timestamps.ts`).
- [ ] A `MediaClock` observable the detail sheet owns: the active player reports its position;
      `seek(seconds)` goes to it. `AVPlayer` for recordings/videos; the YouTube embed through
      the IFrame API (`player.getCurrentTime()` / `seekTo` via `evaluateJavaScript` + a message
      handler); Vimeo/TikTok/Instagram don't report (no control).
- [ ] The notes section head shows `+ note at 1:42` while the clock reports; a tap appends
      `[1:42] ` to the note (a new paragraph when the note has text) and focuses the editor.
- [ ] In the notes editor and the read-only notes view, `[m:ss]` markers render as tappable
      chips (code voice on the fill, ink underline); a tap seeks and plays. Plain text underneath,
      untouched.
- [ ] Tests: timestamps unit tests; a UI test that adds a note at a time while a voice note plays
      and reads `[0:0x]` in the saved content (reset the fixture afterwards).

---

## Round 4 — places: the map as the picture, the location section (added 2026-10-10)

Contract: docs/ui-changes.md 2026-10-10 "Map-based shares" and `supabase/functions/_shared/place.ts`
(`attributes.place` v1). The pipeline owns the lane and the map; iOS only reads.

### Task 7: `Place.swift` and the location section

**Files:** `ios/StashKit/Sources/StashKit/Place.swift` (+ tests), `ios/Stash/Detail/LocationSection.swift`.

- [ ] Decode `attributes.place` leniently (unknown keys kept on write-back; `readPlace` on the
      web requires `version: 1`, `provider.kind` in apple-maps | google-maps | page and
      `evidence.extraction_version == "place-v1"`).
- [ ] The map needs nothing: it is `file_path` like any picture (`place.map.file_path` says so).
      The kind label reads `place` for a link with the lane (`kindLabel` parity).
- [ ] Port `src/utils/placeFacts.ts`: hours rows Monday-first (`Mon–Thu 4:00–9:00 PM`,
      `1:00 PM–2:00 AM` past midnight), `openState` in the place's zone — **null without a
      `timezone`, then show today's hours and never say open or closed** — directions in the
      provider the save came from, phone formatting, rating/price labels. Unit-test with the
      web's cases (`placeFacts.test.ts`).
- [ ] `LocationSection` above the details tree on the detail sheet: address (opens the
      provider's URL), hours (the machine line, chevron opens the week), phone (`tel:`),
      website, menu, rating, price, category; cells Directions · Call · Menu · Website; the
      muted "From Apple Maps, observed …" line. Hide the beta publisher-facts place rows when the
      lane exists.
- [ ] Share sheet: nothing — a map link saves like any link; the pipeline does the rest.

## Wrap

- [ ] Whole-branch review against the contracts; fix wave.
- [ ] `swift test` green; XCUITests on iOS 17.5 and the newest simulator; VoiceOver pass on the
      new cells; Dynamic Type at accessibility sizes on the detail sheet.
- [ ] DESIGN.md (iOS section): the stages, the cells, the transcript tab, timestamped notes.
      `docs/ui-changes.md`: an iOS entry only where iOS behaviour differs from the web.
- [ ] A TestFlight build; hand the completion report to Will (`docs/ios-plan-17-completion.md`).
