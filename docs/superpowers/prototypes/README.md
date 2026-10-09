# Prototype index

Every interactive comp built for Stash, newest first. Files live in this directory and are
meant to be opened from a repo checkout (the fonts load through relative paths into
`src/assets/fonts/`). This index is checked in with every prototype it describes — add the
row in the same commit as the file, and commit at every version bump so the earlier version
stays reachable in git history.

## Conventions

- **File name** `YYYY-MM-DD-<topic>.html`. Reference renders sit beside the file as
  `YYYY-MM-DD-<topic>-<state>.png` so a variant can be glanced at without opening the page.
- **Version.** The first prototype on a topic on a given day is `v0.1`. A substantive same-day
  revision bumps it (`v0.2`, `v0.3` …): stamp the version in the file's eyebrow and in the
  table below, and commit at the bump. A revisit on a later day gets a new dated file; its
  lineage is noted in the row.
- **Status** vocabulary: `exploring` · `awaiting pick` · `chosen` · `shipped` · `reference`
  (cited by DESIGN.md or a spec) · `superseded` (by a later file, named).
- **Deep links.** Where a file supports hash parameters they are listed so a specific state can
  be linked to directly.
- Prototypes are explorations, not specs. A chosen direction becomes a `DESIGN.md` and
  `docs/ui-changes.md` change before any code moves.

## 2026-10-06

| Prototype | Version | Status | What it shows | Related |
|---|---|---|---|---|
| [stashe-homepage](2026-10-06-stashe-homepage.html) | v0.7 | **shipped** 2026-10-07: live at gostash.it (`/`, `/extension`, `/connect`, `/iphone`), published by `scripts/publish-site.mjs`; v0.7 (2026-10-09) adds `/contact`, `/terms`, `/privacy`, published and awaiting the push | **v0.7 (Will, round 7, 2026-10-09):** `contact.html`, `terms.html` and `privacy.html` in the same system, published to /contact, /terms and /privacy; the legal text ported verbatim from the app's React pages (now deleted), with a machine contents window beside the reading; the contact page is one address with subject-filled mailtos. Open: the Terms promise a 14-day trial the homepage doesn't mention. **v0.6 (Will, round 6):** in the phone film, "That book you saw at the store" (the cover on a bookshop display table) and **"A voice note"**. The note is recorded in Stash, transcribed word by word on its own screen, then named and enriched (what it is, mentions, make into). **v0.5 (`0dcab327`):** a solid spot scan bar on the try-it card. Realistic example images: GitHub's real gum card, a composed TikTok screen, and a new Instagram Reel. The list now reads "…a TikTok, a Reel, a repo", and "link" became a product page. Every result ends in a lime **make into** window (beta), with transformation buttons per kind. "One tap. Saved." / "Share to Stash from any [share] button", plus a TikTok scene through TikTok's own share panel. **`DESIGN-v2.md`** (repo root) writes the whole system down for the web and iOS redesigns: target, not live. **v0.4 (`02503c81`):** a "Stash, wherever you are." section with three running pictures and `more >>` links: the Chrome extension saving a page and then a selection (`js/browser.js`, also the hero of `extension.html`); a cloned copy of the phone saving from Safari (Android coming soon); and a Claude-style chat answering from the stash (`js/ask.js`, also on `mcp.html`; saving from your AI coming soon). The footer halftone can no longer cover its text and dials back while you're in the footer. The hero hint is gone. The updated brand assets didn't arrive (see NOTES). **v0.3 (`09097332`):** "Save it fast. Find it when you need it." over a quiet stippled texture (typesafe's dithered desktop, quieter). Saves hang labelled (`link: …`, `place: …`) for half a second before they drop, and pictures drop as 18×18 low-res tiles: photos, plus pixel-art place, paper and book. Drops only hang in clear sky, measured from the copy's line boxes. The ripple lives only in the ASCII (no halo). "STASH ENRICHES YOUR ITEMS AUTOMATICALLY" eyebrow. The try-it card no longer keeps the previous example's picture: a blank frame per run, a link's real og:image within 0.75 s or else a type placeholder (glyph, favicon, domain) that a late image resolves over, and a text file previewing its own first lines. The phone shows real screenshots (Maps, Threads, a receipt, a boarding pass, Messages) and a book on a café table. A column footer, plus three pages in the same system: `extension.html` (the install page, redrawn), `mcp.html` (connect your AI), and `iphone.html` (in beta; Notify me, not wired); chrome lives in `js/site.js`. v0.2 (`13f98ef4`): back to Stash with the ST4SH kit, $4.99/month, live `homepage-enrich` try-it, reacting pool, Cursor and Claude windows. v0.1 (`f60a8a8a`): the "Stashe" round. Deep links `#spot=violet`, `#ex=link\|shot\|article\|paper\|tiktok`, `#scene=shots\|book\|article\|library`, `#ai=cursor\|claude`, `#still`. Renders: `…-lime`, `…-violet`, `…-mobile`, `…-extension`, `…-mcp`, `…-iphone.png`. Notes, sources, claims to verify and open questions: `2026-10-06-stashe-homepage/NOTES.md`. | `supabase/functions/homepage-enrich` (4826d2bb); migration 20261006150000; lineage: the fieldnotes studies (`public/prototypes/stash-fieldnotes/` v2–v6, lime "Signal" `#a3f53b`). No DESIGN.md change until a direction is picked. |

## 2026-09-15

| Prototype | Version | Status | What it shows | Related |
|---|---|---|---|---|
| [logo-refresh](2026-09-15-logo-refresh.html) | v0.1 | shipped (branch `worktree-logo-refresh`) | The new "Stash" wordmark (letters only, strokes dropped) beside the old stitched mark at every shipped size — web header, auth, pricing/legal, landing nav, iOS header/sign-in/splash, share-sheet header, extension sign-in — then the first-S app icon on the wash gradient: three gradient reads (A full six-stop, **B purple→blue chosen**, C three-stop), S scale 56/62/68%, ink #22262f/#0c0d0f/#000, and in-context Home Screen dark/light, onboarding share-sheet tile, browser tab + Chrome toolbar at 16/32, touch/PWA squares. Render: `2026-09-15-logo-refresh.png`. | DESIGN.md §Logo; ui-changes 2026-09-15 logo refresh; `brand/` |

## 2026-09-07

| Prototype | Version | Status | What it shows | Related |
|---|---|---|---|---|
| [card-readability-exercises](2026-09-07-card-readability-exercises.html) | v0.2 | **C chosen**; reminder ramp awaiting confirmation | Today's library card rebuilt from the shipped code, then three exercises over the same nine items: A Tidy (same bones, one meta line, bigger serif, chips demoted to hover), B One voice (Medium-literal, one family, borderless), C Uniform frame (A's type in one 176px silhouette). Opens on C. v0.2 adds "Reminders on the card": one top-left glass chip that escalates far → near → day-before → due, with live Snooze / Dismiss on rollover. Phone strip for the iOS read. Deep links: `#v=today\|a\|b\|c&hover=1&box=1&shot=grid\|phone\|ramp`. Renders: `…-today`, `…-a-tidy`, `…-a-tidy-hover`, `…-b-one-voice`, `…-c-uniform-frame`, `…-c-reminder-ramp`, `…-c-reminder-ramp-hover.png`. | DESIGN.md §Components (card anatomy, reminder chip); ui-changes 2026-08-30 card system, 2026-09-06 reminders |
| [composer-remind-me](2026-09-07-composer-remind-me.html) | v0.3 | **decided** (web chip row always offered · iOS composer as shown · share sheet as shown); spec next | Reminders from the capture surfaces. v0.1 showed three options (bell beside the pin / "Remind me" offer in the input-chip row / phrase recognised in the note). v0.2 merged 2 and 3: the chip row is the reminder's one home on every surface, a recognised phrase fills the same chip, × is the only remove control; added the **live recognizer** (strong / weak intent lexicon × time grammar → set / set-default-tomorrow / offer / nothing, consumed-or-kept rule), the iOS composer and the share sheet. v0.3, Will's round 2: the "Remind me" chip is **always offered** (present under the empty editor, expands to the right into presets); the recognizer only tints and pre-fills; a reminder is recorded as an **importance signal for the email digest**. Deep links `#shot=s1\|live\|s3\|s4\|s5`, `#shot=live&sample=N&attach=1`. Render: `2026-09-07-composer-remind-me.png`. | `UnifiedInputPanel.tsx`; `CaptureComposerView.swift`; `ShareComposeView.swift`; specs/2026-09-06-reminders-design.md §iOS; ui-changes 2026-09-06 reminders |
| [ios-share-tutorial-swipe](2026-09-07-ios-share-tutorial-swipe.html) | v0.1 | shipped (iOS plan 13, TestFlight build 9) | Post-sign-in share-sheet tutorial as a three-panel swipe carousel. Renders: `…-panel1/2/3.png`. | ui-changes 2026-09-07 iOS share tutorial carousel; plans/2026-09-06-ios-plan-13-screenshot-import.md |

## 2026-09-06

| Prototype | Version | Status | What it shows | Related |
|---|---|---|---|---|
| [ios-screenshot-import](2026-09-06-ios-screenshot-import.html) | v0.1 | awaiting Will | Importing up to 50 recent screenshots at onboarding and from Settings on iOS: first look at both entry points and the review step. | specs/2026-09-06-screenshot-import-design.md; plans/2026-09-06-ios-plan-13-screenshot-import.md |

## 2026-08-30

| Prototype | Version | Status | What it shows | Related |
|---|---|---|---|---|
| [card-type-gallery-neue-montreal](2026-08-30-card-type-gallery-neue-montreal.html) | v0.1 | reference · shipped (web cards 2026-08-30) | Per-type card gallery restyled as the Neue Montreal type study: flat spectrum fields, voice-note player hero, document page glyph, chips grammar, proposed link flavors. Lineage: pass 3 of the 08-29 gallery. DESIGN.md names it the card reference implementation (where they disagree, DESIGN.md wins). | DESIGN.md; ui-changes 2026-08-30 web library cards |
| [detail-panel-surface-neue-montreal](2026-08-30-detail-panel-surface-neue-montreal.html) | v0.1 | reference · shipped (web panel 2026-08-30) | The detail panel as one flowing surface with a Details drawer and in-panel player, in the Neue Montreal study. Lineage: pass 3 of the 08-29 panel. | DESIGN.md; ui-changes 2026-08-30 web detail panel |
| [mutations-first-look](2026-08-30-mutations-first-look.html) | v0.1 | published for feedback | First look at "mutations" (re-shaping a saved object). Also published unlisted at `gostash.it/prototypes-for-feedback/mutations`. | specs/2026-08-30-mutations-mini-spec.md |

## 2026-08-29

| Prototype | Version | Status | What it shows | Related |
|---|---|---|---|---|
| [card-type-gallery](2026-08-29-card-type-gallery.html) | v0.1 | superseded by 2026-08-30-card-type-gallery-neue-montreal | Card type gallery, refinement pass 2 (serif titles, gradient fields). | ui-changes 2026-08-29 landing cards |
| [detail-panel-surface](2026-08-29-detail-panel-surface.html) | v0.1 | superseded by 2026-08-30-detail-panel-surface-neue-montreal | Detail panel as one surface, pass 2. | — |
| [ios-ask-conversations](2026-08-29-ios-ask-conversations.html) | v0.1 | shipped (iOS 2026-08-29) | Ask conversations screen and chat sessions on iOS, porting the web 08-27/28 work. | ui-changes 2026-08-29 iOS chat sessions |

## 2026-08-27

| Prototype | Version | Status | What it shows | Related |
|---|---|---|---|---|
| [chat-workspace](2026-08-27-chat-workspace.html) | v0.1 | shipped (web 2026-08-27/28) | Chat sessions workspace, simplified: sessions, retrieval-only mode, conversations view, focus sources. | ui-changes 2026-08-27 chat sessions |
