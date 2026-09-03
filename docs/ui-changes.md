# UI changes — cross-platform log

Purpose: every meaningful web-UI/product-behavior change lands here as a dated
entry so the agents building the **iOS** (`ios/`) and **macOS** clients can
mirror behavior and data contracts without reverse-engineering the web code.
Newest entries first. Write for implementers on another platform: contracts
first, visuals second, with pointers to specs and source.

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
- **Panel title shows in full**: `EditItemTitleSection` is now an
  auto-growing single-value textarea (Enter blurs/saves, newlines flattened)
  instead of a one-line `<Input>` that clipped long titles at the panel edge.
  Same DESIGN.md inline-editable styling. iOS: the detail-sheet title should
  likewise wrap, not truncate.
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
