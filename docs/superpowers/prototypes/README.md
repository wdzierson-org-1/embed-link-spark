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

## 2026-09-07

| Prototype | Version | Status | What it shows | Related |
|---|---|---|---|---|
| [card-readability-exercises](2026-09-07-card-readability-exercises.html) | v0.2 | **C chosen**; reminder ramp awaiting confirmation | Today's library card rebuilt from the shipped code, then three exercises over the same nine items: A Tidy (same bones, one meta line, bigger serif, chips demoted to hover), B One voice (Medium-literal, one family, borderless), C Uniform frame (A's type in one 176px silhouette). Opens on C. v0.2 adds "Reminders on the card": one top-left glass chip that escalates far → near → day-before → due, with live Snooze / Dismiss on rollover. Phone strip for the iOS read. Deep links: `#v=today\|a\|b\|c&hover=1&box=1&shot=grid\|phone\|ramp`. Renders: `…-today`, `…-a-tidy`, `…-a-tidy-hover`, `…-b-one-voice`, `…-c-uniform-frame`, `…-c-reminder-ramp`, `…-c-reminder-ramp-hover.png`. | DESIGN.md §Components (card anatomy, reminder chip); ui-changes 2026-08-30 card system, 2026-09-06 reminders |
| [composer-remind-me](2026-09-07-composer-remind-me.html) | v0.1 | awaiting pick (recommended 1 + 3) | Three optional ways to set a reminder from the web capture box, each at rest / mid-interaction / set: 1 a bell beside the location pin with the presets popover; 2 a "Remind me" offer in the input-chip row that unfolds into presets in place; 3 the phrase "remind me in 3 days" recognised in the note as a tinted token with a confirm line. Ends with the C card each produces. Render: `2026-09-07-composer-remind-me.png`. | `UnifiedInputPanel.tsx`; specs/2026-09-06-reminders-design.md; ui-changes 2026-09-06 reminders |
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
