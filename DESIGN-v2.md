# DESIGN-v2.md — Stash, "clean objects, DIY machinery"

The design system of reference for Stash. It started as the direction of the October 2026
homepage prototype; on 2026-10-06 the **web app** was redesigned on it, and this file now records
every app decision so the **iOS app** (and the share extension) can follow from the same page.
Read it before any UI work on any surface.

**Status (2026-10-07): the reference.** Will, 2026-10-06: "this should become our design.md of
reference." A second pass on 2026-10-07 added the way in (sign in / sign up), the decrypting
loading screen, the paper's texture, the code voice (JetBrains Mono) and Resolve, which replaced
the scan bar. Where surfaces stand:

| Surface | System | Where |
|---|---|---|
| Web app: library, composer, Ask, item detail, settings, conversations, public feed, discover, admin, and the way in (sign in, sign up, choose a new password) | **v2 (this file)** | `src/`, scoped by `<html data-ui="v2">` (§13) |
| The marketing site, live since 2026-10-07: the homepage (`/`), `/extension`, `/connect` (MCP), `/iphone`, `/contact`, `/terms` and `/privacy` | **v2** | designed in `docs/superpowers/prototypes/2026-10-06-stashe-homepage*`; published to `public/` by `scripts/publish-site.mjs` (§12.13) |
| Pricing, legal and agent (OAuth) consent pages in `src/` | v1 until their redesign | `DESIGN.md` |
| iOS app and share extension | **v2 simulator candidate** (2026-10-07) | `StashDesign.swift`; `docs/ios-design-v2-handoff.md` |
| Chrome extension | v1 until its restyle | `DESIGN.md` |

`DESIGN.md` (v1) stays only as the record of the surfaces that haven't moved, and for the
platform rules v2 builds on: iOS type roles and Dynamic Type, the 44 pt control rules and the
contrast method. Don't mix the two systems on one screen.

**Reference implementations:**
- **The app:** the web app itself (`src/`; the component map is in §13). `/design/cards` (dev
  only) shows the real card in every state, including "A save arriving", the enrichment moment
  looping on a real card.
- **The marketing pages:** `docs/superpowers/prototypes/2026-10-06-stashe-homepage.html` and its
  folder (`style.css`, `js/*`, `extension.html`, `mcp.html`, `iphone.html`, `contact.html`, `terms.html`, `privacy.html`). Its `NOTES.md`
  records every decision round by round.

Where an implementation and this file disagree, this file wins; fix the implementation or note
the exception here. Known exception: the homepage prototype's object card (`.scard`) still has
14 px corners and its enrichment windows (`.node`) 6 px, from before the app's near-square
decision (§5). They follow in the prototype's next round.

---

## 0. The rules, short

1. **Two voices.** The person's things are *clean objects*: white, near-square, PP Neue
   Montreal, real images. What Stash does for them is the *machine*: black tags, square windows,
   Departure Mono, ASCII, dither, decrypting text, a turning cursor. Never swap them.
2. **Print logic.** Paper, black ink, **one** spot colour per screen. Everything else is grey.
3. **The machine shows its work.** Enrichment is visible as it happens (the turning cursor, the
   picture resolving from pixels, the decrypt), then gets out of the way. Machinery never decorates
   a calm screen.
4. **Real objects first.** Show the save itself: the og:image, the photo, the screenshot. If
   there's none, Stash draws a placeholder for the *kind* of thing it is. Never stock imagery
   in product UI.
5. **Square machine, near-square objects.** Radius 0 for tags, windows, buttons, inputs and
   stages; **2 px** for objects: cards, the composer, chips, images. (Will, 2026-10-06: "cards can be
   a little retro feeling with near perfect corners".)
6. **Type as structure.** Big, tight Montreal for titles; Departure Mono only at 11 px multiples
   and only for short machine strings: every label on a card is pixel type, every title is
   Montreal. A literal string someone reads character by character (a URL, a command, a handle,
   code) is the code voice, JetBrains Mono.
7. **One moment of motion per screen**, answering something the person did or something Stash
   is doing. The app's one idle loop is the composer's block cursor (§8). Reduced motion always
   gets a meaningful still.
8. **Honest states.** A state that isn't real says so ("prototype: not sent", "coming soon in
   the beta"). Errors say what happened and what to do. Never claim a step the client can't see.
9. **Plain words.** Sentence case, active verbs, short declaratives. No emoji in product UI.
10. **Tokens only.** Use the values here. A genuinely new token gets added here, with one line of
    rationale, in the same branch.
11. **A little terminal, a little whimsy.** Where the machine speaks it may borrow from a terminal:
    a cursor that turns or blinks, `├─` trees, `>` prompts, `activity.log` windows, numbered menus,
    a dithered scrim, a hard print shadow. Always in service of saying what's true; never on the
    person's own words.

## 1. Brand

**Name:** Stash. The product verb is *save*; "stash it" is the extension's name and an
acceptable casual verb. Never "Stashe" (a retired same-day rename).

**Promise:** *Save it fast. Find it when you need it.* Stash takes anything (a link, a
screenshot, a TikTok, a paper) and gathers its background: what it is, what it says, who made
it, where you were. Then it can be found by meaning and used anywhere, including inside your AI.

**Wordmark and symbol:** the ST4SH kit (`docs/superpowers/prototypes/2026-10-06-stashe-homepage/logo/`).
- **The wordmark** reads "Stash" and is set as **ST4SH**, with the custom A/4 glyph.
- **The symbol** is the A/4 on its own.
- Both are single-colour SVGs that take `currentColor`: in the prototype a sprite
  (`#st4sh-wordmark`, viewBox `30 30 3095.4 730`; `#st4sh-symbol`, viewBox `0 0 724 764`); in the
  app `St4shWordmark` and `St4shSymbol` (`src/components/brand/St4sh.tsx`, copied path for path).

Usage:
- **Colour:** ink on paper or white; ink on the spot colour; white on ink. Never on a photo
  without a solid backing, never outlined, gradient-filled or re-coloured beyond these. The
  symbol may take `--spot-on-ink` on black (the app's Ask bar and window bars).
- **Sizing:** the wordmark is `height: var(--wm)` with width `--wm × 4.24`. It's 13 px in the
  homepage nav, **14 px in the app header tab**, 20 px in the footer, 12–15 px inside app chrome, and
  never below 11 px tall. Below that, use the symbol.
- **Clear space:** at least the height of the "S" on every side.
- **The symbol stands in for Stash wherever Stash acts:** the share-sheet icon, the extension
  button, the Ask bar and window, each answer's tool step, the item panel's window bar, the
  loading screen, and the app icon.

**App icon:** the symbol in `#F3F2EE` on a `#171B1A` charcoal tile, filling about 55% of the
tile's height. This is the only place charcoal appears; everywhere else, black is `#000`.

**Open brand decisions** (from the prototype's open questions; don't resolve them in code):
- The domain shown publicly: `gostash.it` (live today, and the MCP URL), `st4sh.app` (in the kit),
  or `stashe.it` (bought).
- ~~Pangram Pangram's logo licence for a PP Mori-based wordmark.~~ **Cleared** (Will, 2026-10-07):
  ST4SH ships on the site and in the app.
- Lime or violet as *the* spot colour. The app does both: `?spot=violet` (or `?spot=lime`) on any
  app URL switches it and is remembered, so the two can be compared on real data.
- Updated logo files Will has but which haven't reached the repo.

When the updated assets land, they replace the sprite (`js/site.js`), `St4sh.tsx` and this
section together.

## 2. The idea: two voices

| | Human voice: *clean objects* | Machine voice: *DIY machinery* |
|---|---|---|
| What | Anything that is the person's: saves, photos, their notes, their questions | Anything Stash does: reading, labelling, summarising, connecting, status |
| Type | PP Neue Montreal | Departure Mono (11 px grid); JetBrains Mono for literal strings |
| Shape | White surfaces, 2 px corners, a hairline edge | Square; 1 px ink borders; black bars and tags |
| Colour | Ink on white or paper | Ink, white, and the spot colour |
| Texture | None; real images | Dot grids, crop marks, ASCII, halftone, stipple, pixels, dither |
| Motion | Settles: fades, lifts, prints in | Works: turns, decrypts, resolves from pixels, prints in steps |
| Examples | Object card, the composer, a note, your question in Ask | Kind tags, status lines, window bars, trees, the reading lens, placeholders, logs |

The page reads like a printed sheet on which the machine has marked up the person's things.
Crop marks frame stages; tags label objects; status lines report what's happening.

## 3. Colour

### Core tokens

| Token | Value | Use |
|---|---|---|
| `--paper` | `#F3F4F1` | Page background (light) |
| `--white` | `#FFFFFF` | Object surfaces, windows' bodies, inputs |
| `--ink` | `#000000` | Text, rules, tags, window bars, primary buttons. True black, not a tinted near-black |
| `--ink-soft` | `#262626` | Hover on ink (buttons, bars, the Ask bar). *New 2026-10-06: the prototype's ink hover, named* |
| `--muted` (web: `--ink-muted`) | `#5C6159` | Secondary text (5.8:1 on paper, 6.4:1 on white, 5.4:1 on fill) |
| `--line` | `#D5D8D1` | Hairlines, card and input edges at rest |
| `--line-soft` | `#E5E7E2` | Inner dividers (a card's meta rule, list rows) |
| `--fill` | `#ECEDE9` | Soft fills: the audio player's field, your message in Ask, hovered rows, inline code, disabled inputs. *New 2026-10-06: the prototype used four near-identical greys for these; one token* |
| `--dot` | `rgba(0,0,0,.13)` | The 16 px dot grid on stages |

### The spot colour (one per screen)

| Token | Lime (default) | Violet (alternative) | Use |
|---|---|---|---|
| `--spot` | `#A3F53B` | `#6D5BD0` | Fields and rings: see "Where the spot goes" |
| `--on-spot` | `#000000` | `#FFFFFF` | Text and marks on `--spot` |
| `--spot-ink` | `#1F4A38` | `#5D49CB` | Spot-family text on light surfaces, where needed |
| `--ascii` | `#000000` | `#FFFFFF` | Glyphs and dots drawn on a spot field |
| `--spot-on-ink` | `#A3F53B` | `#C9BFFF` | Spot-family marks on black: a tag's kind label, `✓`, the symbol on a bar, the open settings index number, a check on an ink box |

The spot is a *field* colour, not a decoration. It marks the one thing on a screen that is Stash
at work or the one action that matters. Two spot colours never appear on one screen.

**Where the spot goes in the app** (and nowhere else):
- The **composer's ring** while you're saving (70% while focused and empty, full once it holds
  something), and the 3 px focus ring on every text input the person types into.
- The **decrypt head** on the loading screen: the one cell being decoded. (A card being read
  uses no spot: its picture stays unresolved instead, §8.)
- A card's **arrival**: one spot ring that fades.
- **Lit states:** the switch knob when on, the `active`/`trial` plan tag, Ask's "showing N sources"
  when focused, the saved-note flash, the drop veil, and the trial banner when it's urgent.
- **Text selection** (`::selection`).
- `--spot-on-ink` marks on black (the list above).

### Functional colours

| Token | Value | Use |
|---|---|---|
| `--ok` | `#2E9E52` | Saved/landed (extension badge, success check) |
| `--error` | `#A1281C` | Error text and marks, destructive buttons and edges (6.7:1 on paper, 7.4:1 white on it) |
| `--focus` | `--ink` (2 px); the spot ring on inputs; `--on-spot` on spot fields | Keyboard focus |

Platform blues (`#007AFF`, `#2F6FEC`) appear only inside *drawings of other apps* (iOS sheets,
Chrome menus), never as Stash UI.

### Effect palettes (machine moments only)

The hero ripple tints ASCII glyphs in concentric bands. With **lime**: `#FF2BD6`, `#7A3CFF`,
`#00B4FF`, `#FF5A1F`. With **violet**: `#C8FF3D`, `#00E5FF`, `#FF4FD8`, `#FFD400`. Neon lives
only inside glyphs, never as fills, text or gradients.

### Contrast (checked)

Ink on paper is 19:1. Muted on paper is 5.8:1, on white 6.4:1, on fill 5.4:1. Ink on lime is
15.7:1, white on violet 5.2:1. Lime on black is 15.7:1, `#C9BFFF` on black 12.4:1. Error on paper
is 6.7:1, white on error 7.4:1. Never put lime text on white or paper (1.2:1), and never put the
muted colour on the spot. A spot ring is never the only focus cue: the input's edge turns ink
too (the ring is 1.2:1 against white; the ink edge carries the 3:1).

### Dark appearance (proposed, not yet prototyped)

Print logic inverted: page `#000`, objects `#121412` with `#2A2E28` hairlines, text `#F3F4F1`,
muted `#A3A89F`, and the spot unchanged (lime on black is 15.7:1). Window bars stay black, so they
take a 1 px `#2A2E28` border. Prototype this before building it.

## 4. Typography

**Families:**
- **PP Neue Montreal** (Pangram Pangram): Book 400, Book Italic, Medium 500 and Semibold 600, from
  `src/assets/fonts/PPNeueMontreal-*.woff2`. It carries every human word: titles, descriptions,
  notes, questions and answers, buttons.
- **Departure Mono** (Helena Zhang, SIL OFL 1.1; `src/assets/fonts/DepartureMono-Regular.woff2` with
  its licence) is the machine voice. It's a pixel font drawn on an 11 px grid, so set it **only at
  11, 16.5 or 22 px** (1×, 1.5×, 2×), with `letter-spacing: 0` and `font-display: block` (so a
  status line never flashes in a fallback mono of another width).
- **JetBrains Mono** (JetBrains, SIL OFL 1.1; Regular 400 and Medium 500 from
  `src/assets/fonts/JetBrainsMono-*.woff2` with its licence; Tailwind `font-code`) is the **code
  voice**: a literal string someone reads or copies character by character (a URL, a command, a
  handle, a phone number, a file name, code in a note) and the cipher of the loading screen's
  decrypt and the sign-in prompts. Unlike Departure Mono it's drawn for any size, so it takes the
  sizes text around it needs (12.5–17 px in the app), with `font-variant-ligatures: none` where a
  string will be copied, and `font-display: swap` (the loading screen must never be blank). Added
  2026-10-07 (Will: "let's do something cool looking", with the font attached).
- Nothing else. No serif, except inside drawings of other products (Medium's Georgia, Claude's
  answer serif).

### Marketing scale (homepage and pages; clamp so it is fluid)

| Role | Size / line height | Weight | Tracking |
|---|---|---|---|
| Hero | `clamp(50px, 8vw, 128px) / .88` | 500 | -0.055em |
| Closing | `clamp(60px, 12.6vw, 214px) / .84` | 500 | -0.062em |
| Section | `clamp(40px, 5.8vw, 92px) / .94` | 500 | -0.05em |
| Page title | `clamp(44px, 6vw, 96px) / .92` | 500 | -0.05em |
| Statement | `clamp(30px, 4.5vw, 70px) / 1.03` | 500 | -0.042em |
| Lead | `clamp(18px, 1.45vw, 21px) / 1.42` | 400 | -0.012em |
| Body | `17px / 1.5` | 400 | -0.005em |

### Product scale (web app and iOS; in use since 2026-10-06)

| Role | Size / line height | Weight | Tracking | Tailwind | Where in the app | iOS text style |
|---|---|---|---|---|---|---|
| Page title | `clamp(36px, 4.6vw, 60px) / .94` | 500 | -0.045em | (inline) | Settings; empty library ("Save your first thing.", 28–40) | `.largeTitle` |
| Screen title | 28 / 1.1 | 500 | -0.03em | `text-screen-title` | the item panel's title (1.12, inline-editable), Conversations | `.largeTitle` |
| Section title | 20 / 1.2 | 500 | -0.02em | `text-section-title` | settings sheets, dialogs, "Connected", "Activity" | `.title3` |
| Object title | 18 / 1.2 | 500 | -0.018em | `text-object-title` | card titles (2-line clamp) | `.headline` |
| Body | 15 / 1.45 | 400 | -0.005em | `text-body` | descriptions in panels and settings, Ask messages, inputs, the panel's reading text (1.6) | `.body` |
| Body small | 14 / 1.42 | 400 | 0 | `text-sm` | card descriptions (3-line clamp), card notes (italic), menus | `.subheadline` |
| Label | 13 / 1.3 | 500 | 0 | `text-label` | form labels, small actions ("Start new chat", "+ Add a note") | `.footnote` |
| Machine | 11 / 1.45 (Departure Mono) | 400 | 0 | `font-pixel text-pixel` | every tag, status line, meta row, date, window bar, tree label, hint | `.caption2`, never below 11 |
| Machine, large | 16.5 / 1.3 (Departure Mono) | 400 | 0 | `text-pixel-md` | `> owner/repo` on a repo plate, the turning cursor inside a button | `.callout` |
| Code | 12.5–17 / 1.45 (JetBrains Mono) | 400 | 0 | `font-code text-[…]` | the MCP address (15), a phone number (15), the username (14), the public feed address (13.5), the panel's URL strip and `claude mcp add …` (12.5), code in notes (13), the sign-in prompts (13), the loading line (15; 17 from `sm`) | `.callout` / `.footnote`, monospaced |

Rules:
- **Titles are short declaratives,** set tight, with no accent colour or italic on a single word.
- **Weight is hierarchy** (400 / 500); 600 is for rare emphasis in dense UI.
- **Line length:** body text at most about 70 characters; leads at most about 36em.
- **Machine strings are lowercase, terse and one line:** `| gathering more info…`, `✓ filled in`,
  `m4a · 82.3 kb · 0:03`, `answers from your 59 saves`. Never paragraphs. A long sentence the
  machine needs to say ("Site blocks previews — got the gist; full details after saving") is
  Montreal at 13 px instead.
- **Capitals** only where a machine label is meant to shout (an eyebrow tag via `text-transform`),
  never typed in caps in the source. Proper nouns inside machine strings keep their case
  (`posted from Brooklyn, New York`, an email address).
- **Numbers** use `tabular-nums` wherever they change (prices, counts, timers).

## 5. Layout, space, shape

**Grid:**
- Marketing pages: 12 columns, 24 px gaps, max width 1360 px, gutter `clamp(20px, 4vw, 56px)`.
  Section padding is `clamp(80px, 9vw, 140px)` top and `clamp(96px, 10vw, 160px)` bottom.
- App screens: Tailwind's `container` (centred, 16 px side padding, 1400 px max) for every
  screen, so the header's tabs, the composer, the toolbar and the grid share one left edge. The
  library is a 3-column masonry (2 at `md`, 1 on phones; 2 when Ask is docked) with 24 px gutters.
  Reading views cap their text column: settings content at 780 px, conversations at 768 px, the
  item panel at 800 px.

**Spacing scale (4 px base):** 2, 4, 6, 8, 12, 16, 20, 24, 32, 40, 48, 64, 80, 96, 128.

**Radii:**

| Value | Where |
|---|---|
| 0 | Machine: tags, windows and their bars, buttons, inputs, menus, tabs, dialogs, sheets, stages, controls inside objects (a card's play button, a chip's remove) |
| **2 px** (`rounded-object`) | **Objects:** cards, the composer, composer chips, citation cards, images shown as objects, the person's message in Ask. *Was 14 px (cards) and 12 px (composer); Will, 2026-10-06* |
| 1 px | A card's media, inside its 1 px border and 2 px corner (`rounded-t-[1px]`) |
| 50% | Avatars on the public feed and the iOS app icon mask only |

The homepage's 6 px enrichment windows become 0 in the app: once objects are near-square, a
machine window rounder than an object reads wrong.

No pills in Stash's own UI.

**Elevation:**
- **Objects rest** on the paper: a 1 px `--line` edge and `0 1px 0 rgba(20,22,18,.04), 0 10px 24px
  -18px rgba(20,22,18,.28)` (Tailwind `shadow-object`).
- **Objects lift when you point at them** (the retro beat): they move 2 px up and left, the edge
  turns ink and a hard print shadow appears, `4px 4px 0 0 #000` (`shadow-print`), in 150 ms
  `--ease`. The title underlines. Reduced motion keeps the edge and shadow, not the move.
- **Machine elements sit flat:** a 1 px ink border, no shadow.
- **A window that floats over the page** casts the hard print shadow, the only shadow a window gets:
  dialogs, the floating Ask window (`shadow-print`, 4 px); menus, popovers, the recent-searches
  window, the composer's slash menu and formatting bubble, sticky notes, the Ask bar
  (`shadow-print-sm`, 2 px).
- **Docked panels** (the item sheet, Ask pinned as a sidebar) are flat with an ink edge.
- **The scrim** behind sheets and dialogs is dithered paper, the way a classic desktop greyed out
  what was behind a window: paper at 55% with a 4 px grid of 0.9 px ink dots at 30%.
- **Drawings of devices or browsers** get one long soft shadow, `0 30px 60px -36px rgba(0,0,0,.45)`
  (`shadow-drawing`).

**Stages** are where machinery is shown: a 16 px dot grid (`--dot`), bracketed by crop marks (14 px
L-shapes, 1 px ink, 10 px outside the corners). They frame demos, empty states, the item panel's
media and the dev specimens.

## 6. Components

Named after the app's components (and the prototype's selectors where they came from), so the
implementation can be found. App specifics are in §12.

- **Buttons** (`.btn`, shadcn `Button` under v2): square, Montreal 500.
  - *Ink:* black with white text, `--ink-soft` on hover. The primary action.
  - *Line:* transparent with a 1 px ink border; `rgba(0,0,0,.06)` on hover.
  - *Destructive:* `--error` with white text; "Delete item" in the panel is error-coloured text
    that fills on hover.
  - Sizes: 48 px marketing; in the app 40–44 px for primary actions, 28–36 px inside objects and
    windows. On touch the target is at least 44 px whatever the drawing.
  - Labels say what happens ("Save changes", "Revoke access", "Get Premium"). On a spot field the ink
    button stays ink.
- **Tags** (`.tag`, `Tag`): black, white Departure Mono at 11 px, padding `4px 6px 3px`. These are
  the machine's labels: an object's kind (`repo`, `voice note`, `pdf`), status, eyebrows.
  Variants: *outline* (`.tag.soon`, a 1 px ink inset, for "coming soon" and "free"), *white*
  (ink-edged white, `public` on a card), *spot* (a lit state: `active`), *kind:value*
  (`.drop-tag`, the kind in `--spot-on-ink`, then the value in white). shadcn `Badge` renders as a tag under v2.
- **Windows** (`.win`, `MachineWindow`): a 1 px ink border, a black bar holding a Departure Mono
  title (and an optional right-hand label), and a white body. Machine output always lives in one.
  Bars are 22 px for small windows (the slash menu, recent searches, `activity.log`, an agent), 36 px
  for the Ask window and 44 px for the item panel, where they hold 28–32 px controls.
- **Status lines** (`.try-line.is-status`, `StatusLine`): Departure Mono, muted, one line,
  `role="status"`. Three tones: *busy* leads with the turning cursor `| / - \` and ends in `…`;
  *done* leads with `✓`; *idle* is just the words. They report what's actually happening; §10 lists
  every one the app says.
- **The cursor** (`Spinner`): `| / - \`, one frame every 130 ms, from one shared ticker so every
  cursor on screen turns in step. It's the share sheet's "saving" cursor from the homepage film.
  `aria-hidden`; under reduced motion it holds still at `|`.
- **Trees** (`.v2-tree`): facts listed the way a terminal lists them, `├─` per row and `└─` on the
  last, the glyph in Departure Mono ink, the label in Departure Mono muted, the value in Montreal 14
  (filenames and codes stay Departure Mono). The item panel's Details, the plan's facts.
- **Machine strips:** an address or value the person might copy, set in Departure Mono inside a
  1 px ink box, with square ink-edged action cells (copy, open) butted on the right: a link's URL,
  the public-feed address, the MCP address (16.5 px, with an ink `copy` cap).
- **Object card** (`.scard`, `ContentItem`): see §12.3. White, 2 px corners, hairline edge.
- **Placeholders** (`.ph`, `LinkPlaceholder`, `FilePlate`, `DocumentHero`): when a save has no
  image, the media area becomes a dotted field holding a 14×14 pixel glyph for the kind (page,
  article, video, repo, book, social, place; and in the app photo, voice, recording, note, profile) and a
  black label with the site's domain. (The homepage's label adds the favicon its enrichment
  stream returns. The app's library doesn't fetch favicons: a request per card would send the
  domains of the person's saves to a third party on every load.)**In the library the field is `--fill` with
  6 px dots, not the spot:** a screen of saves can hold many placeholders, and the spot is for the
  one thing Stash is doing. The homepage's single demo card keeps the spot field. A document shows a
  white page turned -2.5° on the field.
- **Enrichment windows** (`.node`) on the homepage: 252 px; one finding each, with the label in the
  bar and the value in Montreal 14 / 1.38. A value decrypts in when it arrives live. Variants:
  *fact* (black bar), *find it by* (`.is-find`, spot bar), *make into* (`.is-make`, **beta**, spot
  body with square black buttons; until a transformation ships, pressing one says so). The app
  doesn't show findings as windows yet (§16).
- **Leader lines** (homepage): 1.3 px ink, rounded caps and joins, 12 px rounded elbows; a 2.6 px ink
  dot where a line starts; while it draws, a 4 px spot "spark" travels along it.
- **Composer** (`.composer`, `UnifiedInputPanel`): see §12.5.
- **Inputs** (shadcn `Input`/`Textarea` under v2, the search fields, Ask's field): white, square,
  a 1 px `--line` edge at rest; focused, the edge turns ink and a 3 px spot ring appears.
  Placeholders are muted at full strength (6.4:1).
- **Switches:** a 40×22 px square track with a 1 px ink edge and a 14 px square knob. Off: white
  track, ink knob. On: ink track, the knob lit in the spot, like an indicator light.
- **Checkboxes:** 18 px squares, 1 px ink; checked is ink with the check in `--spot-on-ink`.
- **Tabs:** paper tabs (`.nav`): white, 34 px, butted with 3 px gaps, the open one ink. Inside a
  section head they shrink to Departure Mono lowercase (the item panel's summary/original tabs).
- **Menus** (dropdowns, the slash menu, selects, popovers): square windows with an ink edge and the
  2 px print shadow. Rows are Montreal 14; the focused row inverts to ink, like a terminal's cursor
  line. Menu labels are Departure Mono.
- **Tooltips:** black tags in Departure Mono. Keep them to a few words.
- **Toasts** (`.br-toast`, shadcn toast under v2): ink, square, flat; the title Montreal 14/500, the
  description Montreal 13 at 80%; errors in `--error`. They leave on their own.
- **Dialogs:** white windows, 1 px ink, square, the 4 px print shadow, over the dithered scrim. Title
  Montreal 20/500; the destructive action in `--error`.
- **Navigation** (`.nav`): white paper tabs, 34–36 px tall, butted together with 3 px gaps.
- **Footer** (`.foot`, marketing): on the closing spot band, a 1 px rule, then four columns: brand,
  **set up** (extension, MCP), **iphone app** (with the notify form) and **company**. Column heads
  are lowercase Departure Mono.
- **Notify form** (`.notify`): a square white input butted to an ink button. It validates in
  place, and confirms honestly.
- **"more >>"** (`.more`): a black Departure Mono tag link at the foot of a teaser; it turns spot
  on hover.

## 7. Imagery and texture

- **Real objects, real images:** og:images (GitHub's social card for a repo, a Medium cover), the
  person's photos, and screenshots at their real aspect.
  - Cropping is subject-aware (the crop slides to the detected subject); GitHub cards from the
    left, where the repo name is; portrait media is contained on a blurred copy of itself over ink,
    never centre-cropped.
- **Placeholders by kind:** see Components. Never a grey box, never a broken image.
- **Paper with tooth** (`PaperBackdrop`): the library, the loading screen and the way in sit on
  the homepage hero's sheet, quieter. A 1 px dot every 4 px at 5.5% ink (a cutting mat, `.v2-mat`,
  a CSS tile), two stippled spheres lit from the top right framing the page from its corners
  (ordered 4×4 Bayer dither at 16% ink, as `js/liquid.js`), and grain over the lot (`.v2-grain`,
  an SVG turbulence tile at 12%). Fixed to the viewport, so the cards scroll over a still surface,
  like objects on a desk; ink only, so lime and violet share it. Only the stipple is drawn (2–9 ms,
  inside the spheres' reach), once per viewport width, with 160 px of slack below so a phone's
  toolbar sliding needs no redraw; the drawing is cached, so the library reuses the loading
  screen's. Forms (Settings) stay flat.(Will, 2026-10-07: "add a little bit of noise to the grid page background … it's pretty
  flat right now.")
- **Machine texture** goes behind or around objects, never on them:
  - the hero's **ASCII pool**, **stipple** spheres, **halftone** bands (marketing);
  - the **16 px dot grid** on stages and empty states, the **6 px dots** on placeholder fields;
  - the **mosaic** under a picture that hasn't arrived (`PixelMosaic`: 8 px blocks in the paper's
    four greys, each re-rolling every few beats, so the field shimmers like a signal not yet
    locked);
  - the **dithered scrim** behind sheets and dialogs;
  - **pixels** for a picture Stash is still reading (§8, Resolve); **pixel tiles** for saves in
    flight and **pixel reveal** for memories that sharpen (marketing).

  At most one texture per section.
- **Illustrations of devices and apps** (iPhone, Chrome, Claude, Cursor) are drawn in CSS and kept
  accurate to the real app. Stash appears inside them only as itself.
- **Licences:** photos from Unsplash; logos of other products from LobeHub (MIT) or Simple Icons
  (CC0), trademarks of their owners; illustrative people and businesses only, recorded in the
  prototype's `NOTES.md`.

## 8. Motion

| Token | Value | Use |
|---|---|---|
| `--ease` | `cubic-bezier(.22, 1, .36, 1)` (Tailwind `ease-v2`) | Objects settling, sheets, lifts |
| `--pop` | `cubic-bezier(.34, 1.56, .64, 1)` (`ease-pop`) | Windows and badges arriving |
| Steps | `steps(3–7, end)` | Machine motion: printing in, sinking, glyph swaps |
| Fast | 120–200 ms | Presses, hovers, the card lift (150 ms), the item panel in (200) and out (150) |
| Base | 300–550 ms | Cards, windows, dialogs |
| Slow | 650–1100 ms | Decrypting, leaders drawing, resolves |

Signature effects:
- **The turning cursor** (`Spinner`): `| / - \` at 130 ms a frame. The busy state everywhere: a
  card being read, a save in flight, an upload, the panel saving, Ask searching. From the
  homepage film's share sheet (`| reading the cover…`).
- **The block cursor** (`.v2-caret`): a solid ink block that blinks on 1.06 s steps. It waits at the
  end of the composer's prompt while the composer isn't focused (the focused caret takes over),
  and wakes after "Ask Stash" when you point at the Ask bar. **The composer's is the app's one idle
  loop**, allowed because it is the invitation to save. A thin bar cursor follows Ask's answer while
  it streams.
- **Decrypt** (`useDecrypt`, `S.decrypt`): scrambled glyphs settle left to right, 260–1100 ms by
  length, muted until they settle. For values arriving live (a card's title landing, the sign-in
  prompt); never on static text.
- **The decrypt cycle** (`decryptCycle.ts`), the loading screen's line in the code voice: cipher
  settles left to right behind a **spot head** (the cell being decoded, on the spot field), 420 ms
  plus 22 ms a character (1.2 s at most); the line holds 1.8 s behind the block cursor; it
  scrambles out right to left in 280 ms, and the next line decrypts. Each app load opens one line
  further on (`localStorage.stash_loading_line`). Frames are a pure function of time.
- **Resolve** (`resolve.ts`), the reading state, which replaced the scan bar on 2026-10-07 (Will:
  "green scan line feels a little phoned in. i like the pixel to visible effect you used on the
  homepage"). While Stash reads a save its picture is unresolved; when Stash is done it resolves.
  - **A photo or cover** (`usePixelImage`, a canvas over the `<img>`, matching its object-fit and
    subject crop) holds at **12 px blocks** while a square **reading lens** of finer blocks (6, 3,
    then sharp at the centre) steps two blocks a beat along three rows, like an eye reading lines.
    Done, it sharpens **8 → 5 → 3 → 1** and the canvas goes. A picture that **lands** while the
    person watches resolves in from **26 → 18 → 12** (then the lens, if Stash is still reading) or
    all the way to 1.
  - **Drawn heroes boil** (`useBoil`): a placeholder's pixel glyph drops about a third of its ink
    and flickers a halo of neighbouring cells; a voice note's waveform jitters like a level meter
    listening; a document's lines flicker as if being read off the page. Each settles over three
    beats when Stash is done.
  - **A picture that hasn't downloaded** shows the mosaic (§7) until it has.
  - Everything steps on **one shared 110 ms beat** (`stepTicker`), like the spinner, so a page of
    reading cards costs one timer; canvases off screen don't paint.
- **Print-in** (`.v2-print-in`): `clip-path` revealing top to bottom in 4 steps over 240 ms, for
  tags, descriptions, pictures and small windows appearing.
- **Arrival** (`.v2-arrive`): a new card prints in (300 ms, 5 steps), then one spot ring fades off
  it over 1.2 s.
- **Pixel resolve** (marketing, `js/enrich.js`): block sizes 26 → 18 → 12 → 8 → 5 → 3 → 1 at 95 ms
  each; the app's Resolve steps the same sizes on its 110 ms beat.
- **Leaders with a spark** (marketing): 260–520 ms with an ease-out cubic.
- **Ambient fields** (pool, halftone drift) run only while on screen and pause when hidden.

Budget: one orchestrated moment per screen. In the app, that's enrichment arriving on the object
the person just saved, not idle decoration. **Reduced motion** shows each sequence's most
explanatory still: the cursor stops at `|`; pictures show sharp, glyphs, waveforms and the mosaic
hold still (the status line still says Stash is reading); decrypting text appears settled; the
loading screen shows its line plainly, without cycling; nothing prints in or blinks; and a hovered
card keeps its edge and shadow without moving. The preference is read **live**
(`useReducedMotion`): switched on with the app open, a running effect settles to its still at
once, and the shared beat never strands one mid-effect.

## 9. Icons

- **UI icons:** Lucide on the web (stroke 2, 14–20 px) and SF Symbols on iOS, at the weight of
  the adjacent text. Monochrome `currentColor`. Arrows for "open" are `ArrowUpRight`; send is
  `ArrowUp`.
- **Machine glyphs:** 14×14 pixel bitmaps drawn as crisp SVG runs (`shape-rendering: crispEdges`),
  for placeholders and tiny machine marks (`PixelGlyph`).
- **The Stash symbol** wherever Stash itself acts.
- **Platform glyphs** (the iOS share icon, Chrome's puzzle piece) only when the copy refers to
  that platform control, set inline at text size.

## 10. Voice and copy

- **Human voice:** sentence case, active, specific, short.
  - Headlines are two beats: "Save it fast. Find it when you need it." "One tap. Saved." In the
    app: "Save your first thing." "Nothing matches that."
  - Body copy explains what happens, from the person's side ("Stash reads it and gathers the
    background").
- **Machine voice:** lowercase, present tense, no punctuation beyond `…`, `:`, `·` and `>>`.
  - Findings read as `kind: value`. Facts chain with ` · `: `m4a · 82.3 kb · 0:03`.
- **Words:**
  - Use: *save* (not "capture" or "clip"); *your stash*; *saves* (for counts: "59 saves"); *find
    it by*; *make into*; *the background*; *ask*.
  - Avoid: "AI-powered", "magic", "supercharge", "seamless", exclamation marks, and emoji in
    product UI.
- **States:**
  - *Empty states* invite an action.
  - *Errors* name the problem and the next step.
  - *Betas and stubs* say so plainly.
  - *Busy states* say only what the client actually knows.
- **Prices:** "$4.99 a month". There's no trial copy unless there is a trial (there is: "Start the
  7-day free trial").

**What the app's machine says** (the full set; add new ones here):

| Where | Busy | Done / idle |
|---|---|---|
| A card being read (link, note, anything else) | `| gathering more info…` | `✓ filled in` (2.2 s); `some info unavailable` if it gave up |
| … an image | `| reading the picture…` | same |
| … audio or video | `| transcribing…` | same |
| … a PDF still extracting | `| reading the pdf…` (10 minutes at most) | same |
| A save in flight (the optimistic card) | `| saving…` | (it becomes the real card) |
| The library toolbar | `59 saves · | reading 2…` | `59 saves`; with pins, the tabs `all · 59` `pinned · 3` |
| A link with no picture | | `preview limited, saved anyway` (only once Stash has finished looking) |
| A LinkedIn profile with no picture | | `profile preview unavailable` (local silhouette, once Stash has finished looking) |
| Composer chips | `| fetching more details…`, `| reading the link…`, `| analyzing…`, `| uploading…`, `| uploading · 45%` | `posted from Brooklyn, New York`, `finding your location…` |
| The composer | | `type / for commands` (only while it's focused); the drop veil says `drop to save` |
| Ask | `| searching your stash…` (before the first word), `| writing the answer…` (streaming) | `✓ searched your stash · 3 saves`, `answers from your 59 saves`, `also from`, `⌖ show 3 sources` / `showing` |
| The item panel | `| saving…`, `| loading the editor…`, `| summarizing…`, `| transcribing… part 2 of 4` | `✓ saved 9:41 pm`, `changes save automatically`, `type / for formatting`, `download original`; the address strip's `copy address` / `copied`, `edit address` / `save address`, `enter saves · esc cancels`, `✕ that doesn't look like a web address`; a failed summary: `couldn't summarize this. try again` or `nothing captured to summarize yet` (error tone); an edited summary: `saving the summary…`, `couldn't save the summary. try again`; the address strip's `cancel`; the share cell `share` / `shared · anyone with the link` and its window `✓ link copied · anyone with it can view`, `anyone with the link can view`, `not on your feed · read only`, `copy link`, `✕ couldn't update the link. try again` |
| The shared page (§12.15) | `opening the save…` | `from @will’s stash`; a dead link: "This link no longer works." |
| Settings | `| loading your settings…`, `| checking your plan…`, `| checking for agents…` | `signed in as …`, `connected 3 days ago · last used 1 hour ago`, `activity.log` |
| The loading screen | `> opening your stash`, then eleven more, decrypting in the code voice (§12.10) | |
| The way in (§12.14) | `| signing in…`, `| creating your stash…`, `| sending…`, `| updating…`, `| checking your reset link…` | prompts `> knock knock. who’s there?`, `> new here? pull up a chair.`, `> happens to the best of us.`, `> a link is on its way to you.`; field errors `✕ that username is taken. try another.` |

## 11. Accessibility

- **Contrast:** as in section 3. Spot fields carry ink (lime) or white (violet) text only.
- **Focus:** always visible: a 2 px ink ring on controls, and on inputs the ink edge plus the spot
  ring; `--on-spot` on spot fields.
- **Targets:** at least 44 px on touch. On the web, WCAG's 24 px floor for small controls inside
  objects (a card's menu, a chip's remove, the due reminder's ×).
- **Departure Mono:** never for anything longer than a line, and never below 11 px.
- **Motion:** honour `prefers-reduced-motion` (see section 8). Ambient animation pauses off screen.
- **Status lines are live regions** (`role="status"`, `aria-live="polite"`); the turning cursor
  and decorative glyphs are `aria-hidden`; a card that's being read is `aria-busy`.
- **Drawings:** demos and drawings carry a `role="img"` with an `aria-label` describing what they
  show. Decorative canvases are `aria-hidden` (the backdrop, the mosaic, the resolve canvas; the
  `<img>` under it keeps its alt).
- **Scrambles are hidden:** a decrypting line is `aria-hidden`, and screen readers get the plain
  words (the loading screen is one status, "Opening your stash"; a sign-in prompt has an `sr-only`
  copy).
- **Names:** every icon-only control has an `aria-label` ("Pin open as a sidebar", "Remove
  reminder", "Copy feed address").

## 12. Surfaces

### 12.1 The web app (the reference for iOS)

The redesign kept the app's layout and behaviour and changed how it looks and speaks. Behaviour
contracts are unchanged except where §12 says otherwise; `docs/ui-changes.md` (2026-10-06) lists
every visible change and copy change for the other platforms.

### 12.2 Page and header

- **Page:** paper with tooth (§7, `PaperBackdrop`), fixed behind the library. The v1 gradient wash
  and paper-texture image are gone.
- **Header** (`HeaderSection`): no bar and no shadow; a 68 px row on the paper. Left: the ST4SH
  wordmark (14 px) on a white paper tab (36 px tall), then the date in the machine voice,
  `tue oct 6 2026`. Right: the account as a 36 px ink square with your initial; open, it turns
  spot. Its menu is a machine menu: your email in Departure Mono, then Settings, Discover, Admin
  (admins), Preview public feed, and Sign out below a rule.

### 12.3 The library card

Anatomy, top to bottom (`ContentItem`, `ContentItemHeader`, `ContentItemContent`,
`ContentItemFooter`, `cards/*`):
1. **Media** (or a placeholder; notes have none), 160 px; portrait media and short-video or book
   covers 224 px. Its **kind** is a black tag 10 px from the top-left (`kindLabel`: `article`,
   `video`, `repo`, `book`, `post`, `link`, `photo`, `screenshot`, `voice note`, `recording`, `pdf`
   and other formats, `spreadsheet`, `note`, `multi-part`). States sit top-right: a white tag
   `public`, black tags `due` and `pinned` (pins are the owner's: never on a public view).
2. **Title**, Montreal 18/500, 2 lines, ink: the AI's or the person's reading of the object, never
   a filename.
3. **Status line** under the title while Stash works on the card (§12.4).
4. **Description**, Montreal 14/1.42 muted, 3 lines.
5. **The person's note**, italic Montreal 14 at 80% ink on a 2 px ink bar, 5 lines, editable in
   place (`CardInlineNote`). An empty note shows "+ Add a note" on hover. A saved note flashes the
   spot once and shows a black `✓ saved` tag.
6. **Meta row** in Departure Mono 11 muted, under a `--line-soft` rule: on the left the **source**
   (the link's domain in ink, opening the link; or `m4a · 82.3 kb`; or `note`) and **one fact**
   (`0:03`, `2 min read`), then the reminder (`in 3d` with a clock; due is a black tag with a 24 px ×)
   and the place (pin + name); on the right the **date** (`oct 3`; with the year when it isn't this
   year) and the 24 px menu, which inverts to ink when open. The menu (2026-10-09): `Pin this` /
   `Unpin` · `Share to feed` / `Unshare from feed` (un-sharing also clears the sticky note, as the
   panel does) · `Resurface in…` ▸ `1 day · 3 days · 5 days` and `Don't resurface` · a rule ·
   `Delete this` in error red, which asks first in an app dialog (§6): "Delete this item?",
   "“{title}” and everything Stash knows about it will be removed. This can't be undone.", Cancel
   and a red Delete. "Report a problem" is gone. A visitor to a public feed gets only Comments.

Shell: white, 1 px `--line`, 2 px corners, `shadow-object`; hovered, the lift (§5). Body padding
20 px. No chips row: v1's format, size and duration chips now live in the meta row.

Heroes by kind:

| Kind | Hero |
|---|---|
| Photo, screenshot | The image, cover-cropped to its subject; portrait contained on its blurred self over ink |
| Link with a picture | The og:image, cover-cropped; video and book links use the tall contained treatment with a 44–48 px ink square play mark |
| Repo link | An ink plate: `> owner/repo` in Departure Mono 16.5 (the `>` in `--spot-on-ink`) and the description in Montreal 13 at 65% white |
| Link without a picture | The placeholder: the kind's pixel glyph (48 px) on the dotted fill, a black label with the domain, and, once Stash has finished looking, `preview limited, saved anyway`. While Stash reads, the glyph boils (§8) |
| A picture still downloading | The mosaic (§7), until it arrives |
| Voice note, recording | The player on plain fill: an ink square play button (44 px; 40 for recordings), 28 ink waveform bars (played solid, unplayed at 25%), the time in Departure Mono. 116 px tall for voice notes, 96 px for recordings |
| Video file | The first frame on ink, a 48 px ink square play button, the duration as a black tag bottom-right. It **plays in place**: the frame grows to the video's own shape (up to 420 px), the native controls appear (full screen is theirs), and a 32 px white square close button with an ink edge and the 2 px print shadow sits top-right, visible on any picture, bringing the poster back. No custom lightbox: a `fixed` overlay inside a card is pinned to the card by its hover lift and flickers (2026-10-07) |
| Document | A white page turned -2.5°, rising from the bottom of the dotted fill |
| Image whose file is missing | The photo glyph and the filename as a black label |
| Note, multi-part | No hero: the note is the object |

Public sticky notes (shared items) are slips of white paper pinned over the card's top-left:
1 px ink, the 2 px print shadow, italic Montreal 13, turned a few degrees. v1's yellow Post-it is
retired.

### 12.4 Enrichment on a card: "gathering more info"

When a save is still being read (the same `enrichmentState` contract as v1: an explicit
`attributes.enrichment.status`, or the pieces a kind reliably gets, for 2.5 minutes at most):
- **The cursor line** sits under the title, or in its place if there's no title yet:
  `| gathering more info…`, or `| reading the picture…` / `| transcribing…` / `| reading the pdf…`
  for the kinds where the waiting piece is known. This is the share sheet's cursor (Will,
  2026-10-06: "let's use this for the 'gathering more info' animation on the card").
- **The picture is unresolved** (§8, Resolve): a photo or cover holds at 12 px blocks under the
  reading lens; a drawn placeholder's glyph boils; a voice note's waveform jitters; a document's
  lines flicker.
- **Dotted lines** (`··········` in Departure Mono, `#B9BDB5`) hold the description's place
  where one is expected.
- **Nothing dims.** v1 faded the whole card to 50%; v2 keeps full contrast and lets the machine
  marks say it.
- **As pieces land** (the grid diffs each realtime snapshot): the title **decrypts** in, the
  description **prints in**, and a picture **resolves in** from 26 px blocks (drawn heroes print
  in).
- **When the last piece lands**, the picture sharpens (8 → 5 → 3 → 1), and the line reads
  `✓ filled in` for 2.2 s and goes. If Stash gave up, it says `some info unavailable` and stays.A PDF counts as being read for 10 minutes at
  most (`isReadingDocument`): extraction that fails writes nothing, and the card must not claim
  work forever.
- **The toolbar** says it too: `59 saves · | reading 2…`.
- **A save in flight** (before the row exists) is the same card with the mosaic hero, the kind tag,
  `| saving…` and dotted lines. v1's rotating messages ("Transcribing…", "Almost done…") are
  retired: they claimed steps the client couldn't see.
- **A new card arrives** printing in, with one spot ring fading off it.

`/design/cards` (dev) loops the whole sequence on a real card: arrive (the glyph boils) → title
decrypts → description → the picture lands (mosaic, then 26 → 18 → 12 and the lens reading for
3.6 s) → it sharpens with `✓ filled in`. `/design/loading` (dev) shows the loading screen.

### 12.5 The composer

(`UnifiedInputPanel`, `CaptureEditor`, `InputChip`, `editor/*`)
- **Shell:** white, 2 px corners, full container width. At rest a 1 px `--line` edge and a soft
  shadow. Focused and empty: a 1 px ink edge and a 6 px spot ring at 70%; holding something, the
  ring at full strength and a deeper shadow; it lifts 2 px (scale 1.004, spring 320/28/0.7).
- **The prompt:** "Paste a link, drop a file, or type a note" in muted Montreal 16, followed by the
  blinking ink block cursor while the editor isn't focused.
- **Bottom row:** a 40 px square attach button (white, line edge, ink on hover) and the hint
  `type / for commands`, which prints in only while the composer is focused (Will, 2026-10-07:
  "wait until the box is focused"); at rest the composer is just the field and its cursor. On the
  rightthe place label in Departure Mono (`posted from Brooklyn,
  New York`), a 40 px square location toggle (ink when on) and the send button, a 42 px ink square
  with an up arrow, at 25% until there's something to save, turning the cursor while it sends.
- **Chips:** small objects (white, 2 px, line edge): a 40 px thumbnail or icon tile, the title in
  Montreal 14/500, the description in 13 muted, facts in Departure Mono, status lines with the
  cursor, a 24 px square remove; large uploads draw a 3 px ink progress bar along the bottom.
- **Drop veil:** the spot at 30% with a dashed 1.5 px ink edge and a black tag, `drop to save`.
- **Slash menu:** a window with a 22 px bar (`commands`, `↑↓ ⏎`), rows with 32 px square icon
  tiles; the selected row inverts to ink. **Formatting bubble:** a square ink-edged strip; active
  marks invert to ink.
- Links inside the editor are ink, underlined. Code is JetBrains Mono on fill.

### 12.6 The library toolbar

`59 saves` in ink Departure Mono, then the reading count while any card is being read. Once
anything is pinned the count becomes two tabs, `all · 59` and `pinned · 3` (Departure Mono 11
cells on white; the open one inverts to ink), the reading count beside them: `all` keeps the normal
order (pins don't float), `pinned` lists pins newest-pinned first, and the tabs go when the last pin
is removed (2026-10-09). On the right, a 40 px square search field (white, line edge; focused, ink edge and spot ring). Its
recent searches open as a small window (`recent searches`, with `clear` in the bar); rows invert to
ink on hover.

### 12.7 Ask Stash

(`ChatMole`, `ChatMessageSources`, `ChatMessageFeedback`, `ConversationsView`)
- **The Ask bar** (minimized), bottom-left: a 44 px ink bar with the 2 px print shadow, holding the
  symbol in `--spot-on-ink`, "Ask Stash" in Montreal 15/500 (a block cursor wakes after it on
  hover), an outlined `⌘K` key, and a mic cell after a hairline that fills with the spot on hover.
- **The window** (floating, 384×560): 1 px ink, square, the 4 px print shadow. **Docked**
  ("Pin open as a sidebar"): full height on the left, flat, an ink right edge; the library reflows
  beside it.
- **Bar** (36 px, ink): the symbol and `ask stash`; on the right 28 px controls that invert on
  hover (pin / restore, minimize).
- **Under the bar:** the conversation's title in Montreal 15/500 ("Ask Stash" until there is one)
  and `answers from your 59 saves`.
- **Empty thread:** a small dotted stage: "Ask anything about what you've saved — answers cite the
  cards they came from." and `⌘K opens this from anywhere`.
- **Your message:** a soft fill block, 2 px corners, Montreal 15, right-aligned, 86% wide at most.
- **Each answer** opens with its **tool step** (the symbol and a status line: `| searching your
  stash…` before the first word, `| writing the answer…` while it streams, then `✓ searched your
  stash · 3 saves`), then the answer in Montreal 15/1.5 ink with a thin bar cursor following the
  stream. Inline citations are ink, underlined at 40% (100% and a spot ground on hover); they open
  the save. Sources not linked in the text follow as small object cards under `also from` (kind
  tag, title, domain; hover lifts them onto the 2 px print shadow). Then a row: `⌖ show 3 sources`
  (an outlined machine button; when the grid is focused on them it reads `showing` on the spot),
  read aloud, and thumbs up / down, all 28 px squares.
- **Input:** a 40 px square field ("Ask your stash…", focused: ink edge and spot ring), a 40 px
  square mic, and a 40 px ink send. Under it, "Start new chat · Earlier conversations".
- **Listening:** the input row becomes a spot strip with an ink mic button, ink bars and the
  interim words in italic, and `listening · tap the mic to ask · esc to cancel`.
- **Conversations** (replaces the grid): a "← Back to your stash" paper tab, the screen title,
  a 40 px search; each day's group under a Departure Mono head on an ink rule; rows are object
  cards (title Montreal 15/500, preview 14 muted, date and count in Departure Mono) that lift on
  hover; paging in Departure Mono with square ink-edged buttons.
- **When citations focus the grid:** a black tag over the grid, `showing 3 cards from this answer`,
  with a `clear` cell that lights with the spot on hover.

### 12.8 The item panel (the side sheet)

(`EditItemSheet`, `EditItemDetailsTab`, `edit/*`, `EditItem*Section`)
- An 800 px sheet from the right: white, an ink left edge, no shadow, over the dithered scrim.
- **Window bar** (44 px, ink; `edit/ItemWindowBar`): the symbol, the kind as a white tag, the
  source (domain) and `saved oct 6 2026` at 60% white; at the right end the **share cell** (32 px,
  `edit/ShareControl`; tooltip `share`, and in the spot colour once shared, `shared · anyone with
  the link`) and the close button (32 px), both inverting on hover. One click on share mints the
  link, copies it and opens the **share window** under the cell (a small window: `share` in its
  bar; `✓ link copied · anyone with it can view`; the address in the code voice with a copy cell;
  `not on your feed · read only`; **Stop sharing** in error red). The link is unlisted and separate
  from the public feed (§12.15). (Will, 2026-10-09.)
- **The address leads** (links): the source address strip is the first thing in the body, above
  the title (Will, 2026-10-09: "move the address for the object above the title").
- **Title:** screen title 28/1.12, inline-editable (hover: fill; editing: white, ink edge, spot ring).
  **Description:** Montreal 15/1.5 muted, editable the same way.
- **Media** on a dotted stage with crop marks: an image as an object (2 px, line edge,
  `shadow-object`), with 36 px square replace and remove controls on hover. The picture stage is
  **448 px tall before the picture arrives and after** (its 384 px cap plus padding), so nothing
  below it moves while the picture loads; until it has, the stage shows the mosaic of a picture
  not yet here, and a picture that fails to load takes the stage with it (`edit/EditItemImageStage`;
  nothing stores an image's size, so the stage reserves its full height). (Will, 2026-10-08: "the
  photo sort of lazy loads and the content jumps".)A **video** is shown as
  a video on the same stage: an object (2 px, line edge, `shadow-object`, ink behind its letterbox) at
  its own shape up to 420 px tall, with the native controls, and `download original` under it (Will,
  2026-10-07: "the detail panel should show the video"). Audio uses the **player strip**: plain fill
  with a line edge, a 44 px ink play button, 40 ink bars, times in Departure Mono, a 28 px square
  speed control (`1×`, `1.5×`, `2×`) and `download original` (`edit/EditItemMediaZone`).
- **Source address:** the machine strip: favicon and the whole address in JetBrains Mono 12.5 as
  one link, then 40 px cells: **copy** (tooltip `copy address`; after a click the cell shows a
  check and says `copied` for two seconds), **edit** (`edit address`; the strip becomes a field in
  the code voice, the same cell turns spot with a check and reads `save address`, `enter saves ·
  esc cancels` under it; Enter or the cell saves and the cell turns back to edit; a red **×** cell
  (`cancel`) to its left leaves the edit and keeps the old address), and **open**.
  A bare host gets `https://`; anything that isn't a web address is refused with
  `✕ that doesn't look like a web address` and nothing is saved. Saving writes `url`; the items
  trigger queues the quality loop to reassess the save. (Will, 2026-10-08.)
- **Notes:** an empty note is **one line of body text**, "Add a note…" (muted, in the person's
  voice as on the card; fill on hover). A click mounts the editor focused, inline in the title's
  field treatment (white, ink edge, spot ring while focused); leaving it empty collapses it back to
  the line and writes nothing. A note that exists shows the editor at once, plain, taking the ring
  on focus. The slash hint is the machine line under it, `type / for formatting`, **only while the
  editor is focused**; the full-screen editor carries the same line in its footer. (Will,
  2026-10-07, on the old "Press '/' for commands or start typing…": "it says the same thing beneath
  the input box"; 2026-10-09: "one line of normal text, hover light grey, click to edit with the
  bright green border".) Links are ink, underlined at 40%; code is JetBrains Mono on fill.
- **Summary**, editable in place like the title (2026-10-09): plain at rest, fill on hover, a click
  gives an auto-growing field with the ink edge and spot ring; leaving it saves `summary` (an
  emptied field clears it) and re-indexes the save, with `saving the summary…` and, on failure,
  `couldn't save the summary. try again` under it; Esc abandons the edit and leaves the panel (and a
  full-size view) open. Original content and transcripts are read-only.
- **Summary tab without a summary** (older saves, captions, and saves whose summary step failed):
  "No summary yet for this link." and an ink **Generate summary** button. It summarizes the text
  Stash captured (the Original tab) with the ingestion prompt (gpt-4o-mini, at most ~250 words,
  no preamble), saves it to the item's `summary` so every device and Ask see it, and re-indexes the
  item. `| summarizing…` runs 2–7 s; a failure is an error line beside the button, which stays to
  retry. It's offered only when at least 50 characters were captured (the server's floor); under
  that the tab says "Too little text was captured to summarize. It's all under Original Content."
- **Sections**, in order (2026-10-09, Will: "move source above notes"): the **source** first, then
  **notes**, **details** and **sharing**. Notes, details and sharing open with a lowercase Departure
  Mono label on a 1 px ink rule. The source section has **no label**: its tabs row sits on the left
  of the rule in Departure Mono (`summary | original content` for links and documents, `transcript`
  for audio and video; the open tab is ink), and a 24 px **full-size** cell sits on the right, which
  opens the active tab full size (`edit/MaximizedSource`: the window chrome the notes' maximize
  uses, an ink bar naming the tab, a minimize control, a reading column; Esc or minimize returns).
  Empty source tabs are small dotted stages.
- **Details:** open by default (Will, 2026-10-07: "leave the details expanded by default"), the
  facts as a tree; a new item opens it again. Collapsed, the head shows the common facts inline
  (`m4a · 82.3 kb · 0:03`). Only an upload lists an original file: a link's stored cover isn't one.
- **Sharing:** a 36 px square tile (ink with a globe when public, fill with a lock when private),
  "On your public feed" / "Private" in Montreal 14/500, the v2 switch; when public, the feed address
  as a machine strip with a copy cell.
- **Footer:** an ink rule; "Delete item" in error red on the left (it fills on hover); the save
  status line on the right.

### 12.9 Settings

(`pages/Settings`, `settings/*`, `PhoneNumberSetup`, `SubscriptionSettings`)
- "Settings" as a page title, and `signed in as you@example.com` in the machine voice.
- **The index** (248 px, sticky): the sections numbered like a terminal menu, `01`–`05` in
  Departure Mono, the name in Montreal 15/500 and a one-line hint in Departure Mono; separated by
  hairlines under an ink top rule; the open one inverted to ink with its number in
  `--spot-on-ink`. On phones it becomes a row of paper tabs. Sections can be linked:
  `/settings#agents`.
- **Order:** Your information · Connected agents · Phone & WhatsApp · Subscription · Tags.
- **Sections are plain white sheets** (2 px, line edge), titles 20/500, descriptions 15 muted,
  form labels 13/500, 40 px square inputs, one ink primary button.
- **Your information:** the profile form; the username in JetBrains Mono on fill (it can't change);
  the public feed as a machine strip with copy and open cells; reminder emails with the switch;
  "Delete account" in a sheet with an error edge.
- **Connected agents:** the MCP address as the big strip (JetBrains Mono 15) with an ink `copy`
  cap; set-up lines for Claude, Claude Code and other agents, commands in JetBrains Mono;each connected agent as a window (`● connected` in the bar,
  its history in Departure Mono, a square "Revoke"); and `activity.log`, a window listing every
  search and read with Departure Mono times.
- **Phone & WhatsApp:** numbers in JetBrains Mono 15 with `verified` / `pending` tags; the
  WhatsApp steps numbered in 24 px ink squares.
- **Subscription:** the plan name and price ("$4.99 a month"), its state as a tag (`active` and
  `trial` on the spot, `free` outlined), facts as a tree, one primary action, a square refresh, and
  what Premium includes with 20 px square checks.
- **Tags:** the tags you made before (cards don't show them any more), as tags with counts.

### 12.10 Dialogs, menus, toasts, empty and loading

- Dialogs, menus, tooltips and toasts follow §6 everywhere in the app.
- **Empty library:** a dotted stage with crop marks: "Save your first thing." and what happens
  next. **No results:** `0 saves match “x”`, "Nothing matches that." and a hint.
- **Loading** (`LoadingInterstitial`): the library's paper, the symbol, and one terminal line in
  the code voice (15 px; 17 from `sm`), a `>` prompt and the decrypt cycle (§8), ending on the
  block cursor. Will, 2026-10-07: "a decrypting code animation where the letters scramble to reveal
  the message … cheeky little messages." The twelve lines, in order: `opening your stash` · `the
  door creaks open…` · `saving made simple` · `hello again` · `hey, you <3` · `you’re my favorite…
  shhh` · `dusting off your finds` · `right where you left it` · `remembering so you don’t have to` ·
  `psst. it’s all still here` · `fetching your shiny things` · `fluffing the pillows`. Each load
  opens on the next; a long load cycles on through them.
- **Trial banner:** a square strip with an ink edge: a black tag (`trial · 5 days left`,
  `trial ended`), the sentence, an ink "Get Premium" / "Add payment method". When it's urgent
  (under two days, or paused) the strip takes the spot field. Minimized, a one-line Departure Mono
  strip.

### 12.11 iOS (next), and the share extension

The web app is the reference; parity means the same states, words and hierarchy, with native
controls. In SwiftUI terms:
- **Tokens** from §3 and §13 into `StashDesign.swift` (`StashColor.paper/ink/inkSoft/muted/line/
  lineSoft/fill/spot/onSpot/spotOnInk/error`). Bundle Departure Mono and JetBrains Mono beside Neue
  Montreal in both targets; Departure Mono stays at 11 / 16.5 / 22 pt at the default size and
  scales with `.caption2` / `.callout`; JetBrains Mono follows the text style of what's around it.
- **Cards:** the §12.3 anatomy at the phone's 2-column width (object title 18 pt `.headline`, 2 pt
  corners, 1 pt `line` edge; no hover, so no lift: a press darkens the edge to ink). The kind tag,
  the meta row and the status line come across as they are.
- **"Gathering more info":** the same cursor line (`| / - \` at 130 ms from one shared timer, a
  `TimelineView` or a single `ObservableObject` ticker), Resolve on the hero (§8: the picture at
  12 pt blocks under the reading lens, a boiling glyph, a jittering waveform; one 110 ms beat),
  decrypt on arrival, the picture sharpening with `✓ filled in`. Under Reduce Motion: a still `|`,
  a sharp picture, a still glyph, no scramble.
- **Loading:** the decrypt cycle over the same twelve lines (§12.10).
- **Share extension:** the prototype's save panel: the wordmark, a `saving` / `saved` tag (the spot
  when saved), a thumbnail, the title, the cursor sub-line (`| reading the cover…`, then the
  finding), and "Add a note".
- **Ask:** the window becomes the full screen with the same bar, tool steps, answer, citation cards
  and input row.
- **Item detail:** the panel becomes a sheet; the 44 pt window bar, sections on ink rules, the
  Details tree.
- **Settings:** the numbered index becomes the list; each section a pushed screen of white sheets.
- Controls keep the v1 iOS rules (`DESIGN.md` › Controls (iOS)): 44 pt targets, Dynamic Type roles,
  VoiceOver names.

### 12.12 Chrome extension

- Toolbar badge: the green check (`--ok`) when a save lands, a red mark when it fails.
- On-page feedback, if any, is a black toast.
- The install page is `extension.html` in the prototype.

### 12.13 Marketing and help pages

Live since 2026-10-07. The prototype is the one source: the homepage and its pages are designed
and reviewed in `docs/superpowers/prototypes/2026-10-06-stashe-homepage*`, and
`npm run publish:site` (`scripts/publish-site.mjs`) turns them into static files in `public/`. Never
edit the published files by hand. The build's post-step (`scripts/place-site-home.mjs`) makes the
homepage `dist/index.html`, so it answers `/`, and moves the app shell to `dist/app.html`, which
`vercel.json` rewrites every other route to. Inside the app, a link to `/` reloads into the site
(`SiteHome`).

| URL | Page | Source |
|---|---|---|
| `/` | the homepage | `2026-10-06-stashe-homepage.html` |
| `/extension` | Stash it for Chrome | `extension.html` (its version and size are the stamps `extension/scripts/publish-hosted-zip.sh` rewrites) |
| `/connect` | connect your AI (MCP); `/mcp` itself is the MCP server | `mcp.html` |
| `/iphone` | Stash for iPhone | `iphone.html` |
| `/contact` | write to us: one address, the usual reasons with their subjects filled in | `contact.html` |
| `/terms` | the terms of service, word for word, with a contents window | `terms.html` |
| `/privacy` | the privacy policy, word for word, with a contents window | `privacy.html` |
| `/site/…` | the pages' CSS, scripts, images and fonts | the prototype folder, plus Montreal and the landing covers from `src/assets` |

What publishing changes, and checks: absolute asset paths; real titles, descriptions, icons and the
social card (`og-v2.jpg`, rendered from `brand/og-src.html` by `scripts/render-og.mjs`); no
design-history comments; no review panel; the pages on clean URLs; both "Get Stash" buttons open
sign-up (the nav's **Sign in** opens `/auth`); and, because no list sits behind "Notify me" yet, an
honest beta line in its place ("It's in beta now. Want to try it? Email us"). Every rewrite asserts
its anchor, and the output is scanned for prototype leftovers, so a prototype change that moves
something fails the publish loudly instead of shipping (`scripts/publish-site.test.ts` checks what's
committed).

### 12.14 The way in: sign in, sign up, a new password

(`pages/Auth`, `pages/ResetPassword`, `auth/AuthShell`; v2 since 2026-10-07. Will: "we need a
redesigned sign in/sign up page and for it to be connected to the sign in button from the
homepage.")
- **Page:** paper with tooth (§7), the ST4SH wordmark on its white tab top-left (home), and at the
  foot `save it fast. find it when you need it.` with `privacy` and `terms` in the machine voice.
- **One floating window,** 420 px, centred: 1 px ink, square, the 4 px print shadow, printing in.
  Its 28 px ink bar names the page's address in the code voice: `stash://sign-in`,
  `stash://sign-up`, `stash://reset`, `stash://new-password`.
- **Inside:** the person's line as a screen title ("Welcome back.", "Start your stash.", "Forgot
  your password?", "Check your email.", "Choose a new password.") and under it the machine's
  prompt in JetBrains Mono 13, `> knock knock. who’s there?`, which decrypts in and waits behind
  the block cursor. Then square paper tabs, `Sign in` / `Sign up` (the open one ink).
- **Fields:** Montreal labels (13/500) over 44 px square white fields (ink edge and spot ring on
  focus); placeholders are examples, never the label again (`you@example.com`, `At least 8
  characters`). For password managers the email is the login on both forms
  (`autocomplete="username"`, with `current-password` / `new-password`); the @handle is
  `autocomplete="off"`, so it's never saved as the login.The username field is JetBrains Mono after an `@`, and under it the address it
  makes: `gostash.it/feed/you`. Errors are machine lines under the field (`✕ that username is
  taken. try another.`), wrapping, tied to the field with `aria-describedby`.
- **One ink button,** full width, its label left and an arrow right; at work it shows the turning
  cursor and `signing in…` / `creating your stash…` / `sending…` / `updating…`. Quiet actions are
  machine-voice text: `forgot password?` beside the password label, `back to sign in`.
- Behaviour is unchanged (the anonymous-session guard, `returnTo` / `commentItem`, `mode=reset` and
  `mode=signup` deep links, the username and phone checks, the reset rate-limit message).

### 12.15 The shared page

(`pages/SharedItem`, `/s/<token>`; the contract is in docs/ui-changes.md 2026-10-09.) A save's
unlisted, read-only address for anyone holding the link; separate from the public feed.
- **The paper** (§7) under everything, as in the library.
- **Header**, 68 px: the wordmark on its white tile at the left (to gostash.it), then `from
  @will’s stash` in the machine voice; **Get Stash** (an ink button, Montreal 13/500) at the right.
  The page is also how people meet Stash, so the chrome stays quiet and the object is the point.
- **The object** sits on the marketing 12-column grid (§5: max 1360 px, 24 px gaps), columns 3–10
  from `lg`, full width below: a white surface with an ink edge and the print shadow, carrying the
  panel's own parts (§12.8) with nothing editable: the window bar (no cells), the address strip
  (copy and open only), the title (28/1.12), the description, the media (the player strip, the
  video, the picture stage without controls, the document preview), the source tabs on their rule
  (`summary | original content`, or `transcript`, no full-size cell), **notes** as read-only rich
  text when there are any, and the details facts. A note shows its text as the object. No
  comments, no sharing section, no footer.
- **Loading:** `| opening the save…`. **A dead or mistyped link:** the same shell and "This link no
  longer works." / "Whoever shared it stopped sharing, or the address was mistyped." with Get Stash.
- The document title is `<title> · Stash`. Link previews (OG tags) are a follow-up.

## 13. Implementation

### Web

**Tokens** live in `src/index.css`. The raw palette is always defined; the app routes opt in with
`<html data-ui="v2">`, which re-points shadcn's semantic variables at it (paper background, ink
foreground and primary, fill for muted/secondary/accent, `--ink-muted` for `muted-foreground`, line
for borders and inputs, error for destructive, ink for rings, and `--radius: 2px`, so shadcn's
`md`/`sm` radii clamp to 0). `src/components/DesignScope.tsx` sets the flag on the routes
`isV2Route` names (`src/utils/designScope.ts`: `/home`, `/settings`, `/discover`, `/feed/*`,
`/admin*`, `/design/*`, `/auth`, `/reset-password`) and the spotfrom `?spot=` / `localStorage.stash_spot`. Because the flag is
on `<html>`, Radix portals (sheets, menus, dialogs, toasts) are inside the scope.

```css
:root {
  --paper: #f3f4f1; --paper-rgb: 243 244 241; --white: #ffffff;
  --ink: #000000; --ink-rgb: 0 0 0; --ink-soft: #262626; --ink-muted: #5c6159;
  --line: #d5d8d1; --line-soft: #e5e7e2; --fill: #ecede9; --dot: rgba(0, 0, 0, .13);
  --spot: #a3f53b; --spot-rgb: 163 245 59; --on-spot: #000000; --spot-ink: #1f4a38; --spot-on-ink: #a3f53b;
  --ok: #2e9e52; --error: #a1281c;
  --ease: cubic-bezier(.22, 1, .36, 1); --pop: cubic-bezier(.34, 1.56, .64, 1);
}
[data-spot="violet"] { --spot: #6d5bd0; --spot-rgb: 109 91 208; --on-spot: #ffffff; --spot-ink: #5d49cb; --spot-on-ink: #c9bfff; }
```

`--muted` belongs to shadcn on the web (an HSL triple), so v2's muted is `--ink-muted` there.

**Tailwind** (`tailwind.config.ts`):
- Colours `paper`, `ink` (`DEFAULT`, `soft`, `muted`), `line` (`DEFAULT`, `soft`), `fill`, `spot`
  (`DEFAULT` with alpha, `on`, `ink`, `on-ink`), `ok`, `error`.
- `font-pixel` and `font-code`; sizes `text-pixel` / `-md` / `-lg`, `text-screen-title`,
  `text-section-title`, `text-object-title`, `text-body`, `text-label`.
- `rounded-object`; shadows `shadow-object`, `shadow-print`, `shadow-print-sm`, `shadow-drawing`;
  easings `ease-v2`, `ease-pop`.
- **The `v2:` variant** (`[data-ui="v2"] &`) styles shared shadcn primitives (`ui/*`) for the app
  only, so marketing pages that use the same components keep v1. A `v2:` rule is more specific
  than a plain class, so **a caller overriding a v2-styled primitive prefixes the override with
  `v2:` too** (`v2:bg-fill` on a disabled `Input`, `v2:focus-visible:ring-0` on a `Textarea`
  that draws its own ring).
- `paper`, `ink` and `spot` are channel variables (`--paper-rgb`, `--ink-rgb`, `--spot-rgb`), so
  opacity modifiers (`text-ink/80`, `bg-paper/80`, `bg-spot/30`) compile; the other colours are plain
  variables and take no modifier.
- Machine animations fill `backwards`, never `both`: a held end value would keep a clip (cutting
  off the hover shadow) or a transparent box-shadow after the animation ends. Under reduced motion
  the blink keyframes are redefined as still, which stills the cursors Tailwind applies through
  variants too.
- `cn()` (`src/lib/utils.ts`) extends tailwind-merge with these sizes, shadows and the radius;
  without that, `text-pixel` reads as a colour and gets dropped next to `text-white`.
- **The library stays live without refetching itself.** `useItems` re-reads only the rows a
  realtime event names (one `in(id)` read per 400 ms burst; a delete just drops the row; anything
  unexpected falls back to the full refetch), and the item panel shows the open card's live row
  (`Index`), adopting a title or description that lands while it's open into fields the person
  hasn't typed in (`useEditItemState`). The grid's tag fetch sends no ids: at 841 saves the id
  list made a 31 KB URL and every fetch came back 400 (2026-10-08).

**Machine pieces** (`src/components/machine/`): `Spinner` and `useSpinnerFrame` (the shared
ticker), `StatusLine`, `Tag`, `MachineWindow`, `CropMarks`, `PixelGlyph` (data in `glyphs.ts`;
`boil` while reading), `useDecrypt`, `decryptCycle` (the loading screen), `PaperBackdrop`,
`PixelMosaic`, Resolve's pure parts in `resolve.ts` with `usePixelImage` and `useBoil`,
`stepTicker` (the 110 ms beat) and `motion.ts` (`prefersReducedMotion`, and `useReducedMotion`,
which every running effect uses, live). The way in:
`src/components/auth/AuthShell.tsx`. CSS: `.v2-dots`, `.v2-dots-fine`, `.v2-mat`, `.v2-grain`, `.v2-caret`,
`.v2-caret-bar`, `.v2-print-in`, `.v2-arrive`, `.v2-fresh`, `.v2-tree` / `.v2-tree-row`,
`.v2-decrypting` (`.v2-checker` and `.v2-scan` retired 2026-10-07). Brand:
`src/components/brand/St4sh.tsx`.

Don't hard-code hex values in components; the few literal values left (the skeleton dots
`#B9BDB5`, the mosaic's four greys between `--line` and `--fill`, the scrim) are documented here.

### SwiftUI

`StashColor.paper/ink/inkSoft/muted/line/lineSoft/fill/spot/onSpot/spotOnInk/ok/error`,
`StashFont.montreal(role)` / `.pixel(size: 11 | 16.5 | 22)` / `.code(role)`,`StashRadius.object` (2) / `.machine`
(0), `StashShadow.object` / `.print`. One shared cursor ticker for every status line.

### Reference modules in the homepage prototype

- `js/enrich.js`: object card, placeholders, windows, leaders, make into, the live composer.
- `js/liquid.js`: the pool, texture, drops and band.
- `js/halftone.js`: halftone, knockouts, the calm footer.
- `js/browser.js` and `js/ask.js`: Chrome and chat drawings.
- `js/phone.js`: the iPhone film (the share sheet's cursor).
- `js/site.js`: sprite, nav, footer.
- `js/page.js`: decrypt, timelines, fit, chat helpers, the `[data-spin]` cursor.
- `js/pixel.js`: the pixel image and its lens, which the app's Resolve follows.

## 14. Do and don't

**Do:**
- Put the person's object in the middle and the machine around it.
- Use one spot colour, as a field or a ring.
- Square up anything Stash says.
- Let enrichment visibly arrive (the cursor, the resolve, the decrypt), then settle.
- Draw a placeholder for the kind of thing it is.
- Write the honest state, in the machine's words.

**Don't:**
- Round machine elements, or give objects more than 2 px.
- Set paragraphs in Departure Mono, or set it at sizes off its 11 px grid.
- Use a second accent colour, gradients on surfaces, or neon outside glyphs.
- Use tinted near-black, stock photos in product UI, or emoji.
- Loop animation on a calm screen (the composer's waiting cursor is the one exception).
- Dim content to say it's busy, or rotate guesses about what's happening.
- Show a fake success.
- Use pills, or soft drop shadows on windows (a floating window gets the hard print shadow, nothing
  else does).

## 15. Moving from DESIGN.md (v1)

| v1 | v2 |
|---|---|
| Grey chrome, violet = interactive | Paper and ink; the spot marks Stash at work and the one key action |
| Type-tinted card fields (the spectrum tints) | Real images, or a placeholder with a kind glyph; the kind is a black tag |
| Montreal everywhere | Montreal for human words, Departure Mono for the machine |
| 16 px cards, 6–12 px composer, pills | 2 px objects, square everything else |
| Soft card shadow, hover lift with a deeper shadow | A quiet resting shadow; hover lifts onto a hard 4 px print shadow with an ink edge |
| Gradient page wash, paper texture | Paper with tooth behind the library (dots, stipple, grain); otherwise texture only in machine moments |
| Annotations: violet bar, italic | The person's notes stay italic Montreal; the bar becomes ink |
| "Gathering more information…" pill, card dimmed to 50% | The cursor line `| gathering more info…`, the picture unresolved until Stash is done, no dimming |
| Rotating skeleton messages | One honest `| saving…` |
| Kicker (domain) above the title; chips row | The domain and facts in the meta row |
| Yellow Post-it sticky notes | Paper slips with an ink edge and the print shadow |
| Violet focus rings, `#b6a8ef` | An ink edge plus the 3 px spot ring on inputs; 2 px ink rings on controls |
| Rounded pill tabs, violet switches | Square paper tabs; the square switch with a lit knob |
| Uppercase grey micro-labels over hairlines | Lowercase Departure Mono labels over ink rules |
| Dotted-rule fact rows | The `├─` tree |
| Five horizontal settings tabs | A numbered index beside white sheets |
| Black-to-gray gradient Ask pill; rounded chat panel | The ink Ask bar; a square window with an ink bar |

Behaviour contracts (what a screen does) are unchanged by this file. Log behaviour changes in
`docs/ui-changes.md` as before.

## 16. Open decisions and next steps

- **Brand:** the public domain, lime or violet, and the updated logo files (§1). (The PP Mori
  logo licence is cleared.)
- **iOS:** the v2 port is on main as a simulator candidate (2026-10-07,
  `docs/ios-design-v2-handoff.md`). Still to follow from the web: Resolve (the pixel reading
  state, §8) and the arriving card's decrypt; the native splash has its own decrypt.
- **Still v1 in `src/`:** pricing, legal, and the agent-consent screen (`/oauth/consent`). The
  homepage and its pages went live from the prototype on 2026-10-07 (§12.13); the old `Landing`
  page only renders if the static site is ever missing.
- **"Notify me" for the iPhone app** needs a list behind it (a small table and function, or a
  Resend audience) before the form comes back; until then the site says "Email us".
- **Unverified claims on the live site** (Will chose to ship them as written, 2026-10-07): TikTok
  transcripts and on-screen text in the scripted examples; the ChatGPT developer-mode, Claude Code
  `/mcp` and Cursor first-use steps on `/connect`; what the iOS beta does on `/iphone`.
- **Texture on the other card grids** (Discover, public feeds): the library has it; decide whether
  they should, and whether Settings stays flat.
- **Findings on the item panel:** the homepage shows findings as windows on leader lines (*what it
  is*, *mentions*, *find it by*, *make into*). The app's panel keeps its sections for now; showing
  findings as windows needs the enrichment data surfaced per finding, which the feed doesn't carry
  yet.
- **Dark appearance:** proposed in §3, not prototyped.
- **The homepage prototype** moves its `.scard` to 2 px and `.node` to 0 in its next round.
