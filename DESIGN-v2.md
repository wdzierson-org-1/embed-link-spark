# DESIGN-v2.md — Stash, "clean objects, DIY machinery"

The design system for the **next** Stash: the direction set by the October 2026 homepage
prototype, written down so other agents can carry it into the **web app** first and the
**iOS app** after. Read it before any redesign work on those surfaces.

**Status (2026-10-06): target, not live.** `DESIGN.md` is still the source of truth for the
surfaces as they ship today. A surface moves to this file when its redesign starts. When every
surface has moved, this file replaces `DESIGN.md`, and the old one is archived. Until then, don't
mix the two systems on one screen.

**Reference implementation:** `docs/superpowers/prototypes/2026-10-06-stashe-homepage.html` and
its folder (`style.css`, `js/*`, plus the `extension.html`, `mcp.html` and `iphone.html` pages).
Its `NOTES.md` records every decision round by round. Where the prototype and this file disagree,
this file wins; fix the prototype or note the exception here.

---

## 0. The rules, short

1. **Two voices.** The person's things are *clean objects*: white, soft corners, PP Neue
   Montreal, real images. What Stash does for them is the *machine*: black tags, square windows,
   Departure Mono, ASCII, dither, decrypting text. Never swap them.
2. **Print logic.** Paper, black ink, **one** spot colour per screen. Everything else is grey.
3. **The machine shows its work.** Enrichment is visible as it happens (scan, resolve, decrypt,
   leader lines), then gets out of the way. Machinery never decorates a calm screen.
4. **Real objects first.** Show the save itself: the og:image, the photo, the screenshot. If
   there's none, Stash draws a placeholder for the *kind* of thing it is. Never stock imagery
   in product UI.
5. **Square machine, soft objects.** Radius 0 for tags, windows, buttons and stages; 14 px
   for object cards.
6. **Type as structure.** Big, tight Montreal headlines; Departure Mono only at 11 px multiples
   and only for short machine strings.
7. **One moment of motion per screen**, answering something the person did or something Stash
   is doing. Reduced motion always gets a meaningful still.
8. **Honest states.** A state that isn't real says so ("prototype: not sent", "coming soon in
   the beta"). Errors say what happened and what to do.
9. **Plain words.** Sentence case, active verbs, short declaratives. No emoji in product UI.
10. **Tokens only.** Use the values here. A genuinely new token gets added here, with one line of
    rationale, in the same branch.

## 1. Brand

**Name:** Stash. The product verb is *save*; "stash it" is the extension's name and an
acceptable casual verb. Never "Stashe" (a retired same-day rename).

**Promise:** *Save it fast. Find it when you need it.* Stash takes anything (a link, a
screenshot, a TikTok, a paper) and gathers its background: what it is, what it says, who made
it, where you were. Then it can be found by meaning and used anywhere, including inside your AI.

**Wordmark and symbol:** the ST4SH kit (`docs/superpowers/prototypes/2026-10-06-stashe-homepage/logo/`).
- **The wordmark** reads "Stash" and is set as **ST4SH**, with the custom A/4 glyph.
- **The symbol** is the A/4 on its own.
- Both are single-colour SVGs that take `currentColor`, exposed in the prototype as a sprite
  (`#st4sh-wordmark` with viewBox `30 30 3095.4 730`, `#st4sh-symbol` with viewBox `0 0 724 764`).

Usage:
- **Colour:** ink on paper or white; ink on the spot colour; white on ink. Never on a photo
  without a solid backing, never outlined, gradient-filled or re-coloured beyond these.
- **Sizing:** the wordmark is `height: var(--wm)` with width `--wm × 4.24`. It's 13 px in the nav,
  20 px in the footer, 12–15 px inside app chrome, and never below 11 px tall. Below that, use the
  symbol.
- **Clear space:** at least the height of the "S" on every side.
- **The symbol stands in for Stash wherever Stash acts:** the share-sheet icon, the extension
  button, tool-call rows ("Searched Stash"), and the app icon.

**App icon:** the symbol in `#F3F2EE` on a `#171B1A` charcoal tile, filling about 55% of the
tile's height. This is the only place charcoal appears; everywhere else, black is `#000`.

**Open brand decisions** (from the prototype's open questions; don't resolve them in code):
- The domain shown publicly: `gostash.it` (live today, and the MCP URL), `st4sh.app` (in the kit),
  or `stashe.it` (bought).
- Pangram Pangram's logo licence for a PP Mori-based wordmark.
- Lime or violet as *the* spot colour.
- Updated logo files Will has but which haven't reached the repo.

When the updated assets land, they replace the sprite in one place (`js/site.js` in the prototype)
and this section.

## 2. The idea: two voices

| | Human voice: *clean objects* | Machine voice: *DIY machinery* |
|---|---|---|
| What | Anything that is the person's: saves, photos, their notes, their questions | Anything Stash does: reading, labelling, summarising, connecting, status |
| Type | PP Neue Montreal | Departure Mono (11 px grid) |
| Shape | White surfaces, 14 px corners, soft shadow | Square; 1 px ink borders; black bars and tags |
| Colour | Ink on white or paper | Ink, white, and the spot colour |
| Texture | None; real images | Dot grids, crop marks, ASCII, halftone, stipple, pixels |
| Motion | Settles: fades, lifts and resizes, briefly | Works: scans, decrypts, prints in steps, draws lines |
| Examples | Object card, the composer, a note, a chat bubble | Kind tags, enrichment windows, "find it by", status lines, the pool, placeholders |

The page reads like a printed sheet on which the machine has marked up the person's things.
Crop marks frame stages; tags label objects; leader lines tie findings to the thing they
describe.

## 3. Colour

### Core tokens

| Token | Value | Use |
|---|---|---|
| `--paper` | `#F3F4F1` | Page background (light) |
| `--white` | `#FFFFFF` | Object surfaces, windows' bodies, inputs |
| `--ink` | `#000000` | Text, rules, tags, window bars, primary buttons. True black, not a tinted near-black |
| `--muted` | `#5C6159` | Secondary text (5.8:1 on paper) |
| `--line` | `#D5D8D1` | Hairlines between sections, card borders |
| `--line-soft` | `#E5E7E2` | Inner dividers |
| `--dot` | `rgba(0,0,0,.13)` | The 16 px dot grid on stages |

### The spot colour (one per screen)

| Token | Lime (default) | Violet (alternative) | Use |
|---|---|---|---|
| `--spot` | `#A3F53B` | `#6D5BD0` | Hero fields, the closing band, "find it by" bars, focus rings, the scan bar, "make into" bodies, selection |
| `--on-spot` | `#000000` | `#FFFFFF` | Text and marks on `--spot` |
| `--spot-ink` | `#1F4A38` | `#5D49CB` | Spot-family text on light surfaces, where needed |
| `--ascii` | `#000000` | `#FFFFFF` | Glyphs and dots drawn on a spot field |
| `--spot-on-ink` | `#A3F53B` | `#C9BFFF` | Spot-family accents on black: a tag's kind label, "✓ saved" |

The spot is a *field* colour, not a decoration. It marks the one thing on a screen that is Stash
at work or the one action that matters. Two spot colours never appear on one screen.

### Functional colours

| Token | Value | Use |
|---|---|---|
| `--ok` | `#2E9E52` | Saved/landed (extension badge, success check) |
| `--error` | `#A1281C` | Error text and marks (6.7:1 on paper) |
| `--focus` | `--ink` (2 px, 3 px offset); `--on-spot` on spot fields | Keyboard focus |

Platform blues (`#007AFF`, `#2F6FEC`) appear only inside *drawings of other apps* (iOS sheets,
Chrome menus), never as Stash UI.

### Effect palettes (machine moments only)

The hero ripple tints ASCII glyphs in concentric bands. With **lime**: `#FF2BD6`, `#7A3CFF`,
`#00B4FF`, `#FF5A1F`. With **violet**: `#C8FF3D`, `#00E5FF`, `#FF4FD8`, `#FFD400`. Neon lives
only inside glyphs, never as fills, text or gradients.

### Contrast (checked)

Ink on paper is 19:1. Muted on paper is 5.8:1, muted on white 6.4:1. Ink on lime is 15.7:1, white
on violet 5.2:1. Lime on black is 15.7:1, `#C9BFFF` on black 12.4:1. Error on paper is 6.7:1. Never
put lime text on white or paper (1.2:1), and never put the muted colour on the spot.

### Dark appearance (proposed, not yet prototyped)

Print logic inverted: page `#000`, objects `#121412` with `#2A2E28` hairlines, text `#F3F4F1`,
muted `#A3A89F`, and the spot unchanged (lime on black is 15.7:1). Window bars stay black, so they
take a 1 px `#2A2E28` border. Prototype this before building it.

## 4. Typography

**Families:**
- **PP Neue Montreal** (Pangram Pangram; already the product's face under v1): Book 400, Book Italic,
  Medium 500 and Semibold 600, from `src/assets/fonts/PPNeueMontreal-*.woff2`. It carries every human
  word.
- **Departure Mono** (Helena Zhang, SIL OFL 1.1, vendored with its licence at
  `docs/superpowers/prototypes/2026-10-06-stashe-homepage/fonts/`) is the machine voice. It's drawn
  on an 11 px grid, so set it **only at 11, 16.5 or 22 px** (1×, 1.5×, 2×), with `letter-spacing: 0`.
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

### Product scale (web app and iOS; proposed from the prototype's object sizes)

| Role | Size / line height | Weight | Tracking | iOS text style it scales with |
|---|---|---|---|---|
| Screen title | 28 / 1.1 | 500 | -0.03em | `.largeTitle` |
| Section title | 20 / 1.2 | 500 | -0.02em | `.title3` |
| Object title | 18 / 1.2 | 500 | -0.018em | `.headline` |
| Body | 15 / 1.45 | 400 | -0.005em | `.body` |
| Body small | 14 / 1.42 | 400 | 0 | `.subheadline` |
| Label | 13 / 1.3 | 500 | 0 | `.footnote` |
| Machine | 11 / 1.45 (Departure Mono) | 400 | 0 | `.caption2`, never below 11 |

Rules:
- **Headlines are short declaratives,** set tight, with no accent colour or italic on a single word.
- **Weight is hierarchy** (400 / 500); 600 is for rare emphasis in dense UI.
- **Line length:** body text at most about 70 characters; leads at most about 36em.
- **Machine strings are lowercase, terse and one line:** `| reading the page…`, `found it, gathering
  the background…`, `✓ saved`, `link: medium.com`. Never paragraphs.
- **Capitals** only where a machine label is meant to shout: the section eyebrow tag
  ("STASH ENRICHES YOUR ITEMS AUTOMATICALLY") via `text-transform`, never typed in caps in the source.
- **Numbers** use `tabular-nums` wherever they change (prices, counts, timers).

## 5. Layout, space, shape

**Grid:**
- Marketing pages: 12 columns, 24 px gaps, max width 1360 px, gutter `clamp(20px, 4vw, 56px)`.
  Section padding is `clamp(80px, 9vw, 140px)` top and `clamp(96px, 10vw, 160px)` bottom.
- App screens: the same gutter and a 1200 px max for reading views; library grids fill the width.

**Spacing scale (4 px base):** 2, 4, 6, 8, 12, 16, 20, 24, 32, 40, 48, 64, 80, 96, 128.

**Radii:**

| Value | Where |
|---|---|
| 0 | Machine: tags, windows, buttons, inputs inside machine windows, stages, nav tabs, tiles |
| 6 px | Enrichment windows (nodes), the one softened machine element |
| 12 px | The composer (the person's input) |
| 14 px | Object cards and object sheets |
| 50% | Avatars and the iOS app icon mask only |

No pills in Stash's own UI.

**Elevation:**
- **Objects** lift: `0 1px 2px rgba(20,22,18,.05), 0 22px 44px -26px rgba(20,22,18,.32)`.
- **Machine elements** are flat: a 1 px ink border, no shadow.
- **Drawings of devices or browsers** get one long soft shadow, `0 30px 60px -36px rgba(0,0,0,.45)`.

**Stages** are where machinery is shown: a 16 px dot grid (`--dot`), bracketed by crop marks (14 px
L-shapes, 1 px ink, 10 px outside the corners). They frame demos, illustrations, empty states, and
the item-detail canvas.

## 6. Components

Each one is named after its prototype selector, so its implementation can be found.

- **Buttons** (`.btn`): square, 48 px tall (44 px minimum on touch), 22 px side padding, Montreal
  500 16 px.
  - *Ink:* black with white text, `#262626` on hover.
  - *Line:* transparent with a 1 px inset `currentColor` border.
  - On a spot field the ink button stays ink.
  - Labels say what happens ("Get Stash", "Notify me", "Download …").
- **Tags** (`.tag`): black, white Departure Mono at 11 px, padding `4px 6px 3px`. These are the
  machine's labels: an object's kind (`repo`, `tiktok`, `pdf`), status, eyebrows. Variants:
  - *Outlined* (`.tag.soon`): transparent, with a 1 px ink inset, for "coming soon" states.
  - *Kind:value* (`.drop-tag`): the kind in `--spot-on-ink`, then the value in white.
- **Windows** (`.win`, `.win-bar`): a 1 px ink border, a 22 px black bar holding a Departure Mono
  title (and an optional right-hand label), and a white body. Machine output always lives in a window.
- **Object card** (`.scard`): white, 14 px radius, object shadow, 300 px at its marketing size.
  - *Media:* 196 px tall, with the image as cover and a kind tag top-left.
  - *Title:* object-title type, the AI's reading (never a filename).
  - *Description:* muted, two lines.
  - *Meta row:* Departure Mono, the source on the left and one fact on the right.
  - *While reading:* a checker with the scan bar, a `| reading…` spinner in the title, and dotted
    skeleton lines.
- **Enrichment windows** (`.node`): 252 px; one finding each, with the label in the bar and the
  value in Montreal 14 / 1.38. A value decrypts in when it arrives live. Three variants:
  - *Fact* (black bar).
  - *Find it by* (`.is-find`, 300 px): a spot-coloured bar labelled "search", holding the phrases
    a person would search for.
  - *Make into* (`.is-make`, 330 px, **beta**): a black bar with an outlined "beta" label and a
    spot-coloured body holding square black buttons, one per transformation: "flashcards",
    "a study guide", "a to-do list", "a shopping list", "an itinerary", "a setup checklist"…
    Choose them per kind of save, two or three at a time. Until a transformation ships, pressing
    one says so (`flashcards: coming soon in the beta`).
- **Leader lines:** 1.3 px ink, rounded caps and joins, with 12 px rounded elbows (an S-curve when
  the drop is under 26 px). A 2.6 px ink dot marks where a line starts on the object; while it
  draws, a 4 px spot "spark" travels along it.
- **Composer** (`.composer`): white, 12 px radius, 58 px tall.
  - *Parts:* a "+" attach control, the field, and a 42 px square ink send button with an
    up-arrow (aria-label "Send").
  - *When focused* it lifts (scale 1.025) and gains a 5 px spot ring.
  - *Instructions* appear above it as text lines that rise and fade, never as tooltips.
- **Placeholders** (`.ph`): when a save has no image, or its image is slower than **0.75 s**, the
  media area becomes a spot field with a dot grid. It holds a 14×14 pixel glyph for the kind
  (page, article, video, repo, book, social, place) and a black label with the site's favicon and
  domain. A text document shows a page made from its own first lines. A late real image
  pixel-resolves over the placeholder after it has been up at least 0.55 s.
- **Status lines** (`.try-line.is-status`): Departure Mono, muted, with a `|/-\` spinner. They
  report what's actually happening (`found it, gathering the background…`, then
  `Gathered in 3.2 s`).
- **Toasts** (`.br-toast`, `.hero-toast`): black machine tags that slide in and leave on their
  own (`✓ saved link: medium.com`).
- **Navigation** (`.nav`): white paper tabs, 34 px tall, butted together with 3 px gaps. The
  wordmark tab sits left, sections in the middle, sign-in plus an ink "Get Stash" on the right.
- **Footer** (`.foot`): on the closing spot band, a 1 px rule, then four columns: brand,
  **set up** (extension, MCP), **iphone app** (with the notify form) and **company**. Column heads
  are lowercase Departure Mono.
- **Notify form** (`.notify`): a square white input butted to an ink button. It validates in
  place, and confirms honestly.
- **"more >>"** (`.more`): a black Departure Mono tag link at the foot of a teaser; it turns spot
  on hover.
- **Chat windows** (Ask, MCP demos):
  - *The person's message:* a soft grey bubble.
  - *Tool steps:* a row with the Stash symbol, "Searched Stash", and the call in Departure Mono
    on its own line.
  - *The answer:* the AI's own type. In Stash's own Ask UI that's Montreal; drawings of other
    assistants keep their look.
  - *Citations:* small object cards.

## 7. Imagery and texture

- **Real objects, real images:** og:images (GitHub's social card for a repo, a Medium cover), the
  person's photos, and screenshots at their real aspect.
  - Cropping: GitHub cards from the left, where the repo name is; most others centred; portrait
    video frames around 70% down, where the creator and caption are.
- **Placeholders by kind:** see Components. Never a grey box, never a broken image.
- **Machine texture** goes behind or around objects, never on them:
  - the hero's **ASCII pool** (a FLIP fluid drawn in glyphs);
  - **stipple** spheres (an ordered dither) on hero fields;
  - **halftone** (FBM-sized dots) on closing bands and demo panels, knocked out around words;
  - **pixel tiles** (18×18, 4 px pixels) for saves in flight;
  - **pixel reveal** for memories that sharpen on hover.

  At most one texture per section.
- **Illustrations of devices and apps** (iPhone, Chrome, Claude, Cursor) are drawn in CSS and kept
  accurate to the real app. Stash appears inside them only as itself: the symbol in the share
  sheet, the extension button, a connected tool.
- **Licences:**
  - Photos: Unsplash.
  - Logos of other products: LobeHub (MIT) or Simple Icons (CC0), trademarks of their owners.
  - Illustrative people, creators and businesses only; record them in the prototype's `NOTES.md`.

## 8. Motion

| Token | Value | Use |
|---|---|---|
| `--ease` | `cubic-bezier(.22, 1, .36, 1)` | Objects settling, sheets, lifts |
| `--pop` | `cubic-bezier(.34, 1.56, .64, 1)` | Windows and badges arriving |
| Steps | `steps(3–7, end)` | Machine motion: printing in, sinking, glyph swaps |
| Fast | 120–200 ms | Presses, hovers |
| Base | 300–550 ms | Sheets, cards, windows |
| Slow | 650–1100 ms | Decrypting, leaders drawing, resolves |

Signature effects (names match the prototype):
- **Decrypt** (`S.decrypt`): scrambled glyphs settle left to right, 260–1100 ms by length. For
  values arriving live; never on static text.
- **Pixel resolve:** block sizes 26 → 18 → 12 → 8 → 5 → 3 → 1 at 95 ms each, for an image that
  has just arrived.
- **Scan bar:** a solid 8 px spot bar with a 1 px ink edge sweeping the media every 1.4 s while
  Stash reads.
- **Print-in:** `clip-path` revealing top to bottom in 3–4 steps, for tags, tiles and buttons
  appearing.
- **Leaders with a spark:** 260–520 ms with an ease-out cubic.
- **Ambient fields** (pool, halftone drift) run only while on screen and pause when hidden.

Budget: one orchestrated moment per screen. In the app, that is enrichment arriving on the object
the person just saved, not idle decoration. **Reduced motion** shows each sequence's most
explanatory final frame (the saved state, the finished answer) and nothing loops.

## 9. Icons

- **UI icons:** Lucide on the web (stroke 2, 16–20 px) and SF Symbols on iOS, at the weight of
  the adjacent text. Monochrome `currentColor`.
- **Machine glyphs:** 14×14 pixel bitmaps drawn as crisp SVG runs (`shape-rendering: crispEdges`),
  for placeholders and tiny machine marks.
- **The Stash symbol** wherever Stash itself acts.
- **Platform glyphs** (the iOS share icon, Chrome's puzzle piece) only when the copy refers to
  that platform control, set inline at text size ("Share to Stash from any [share] button").

## 10. Voice and copy

- **Human voice:** sentence case, active, specific, short.
  - Headlines are two beats: "Save it fast. Find it when you need it." "One tap. Saved."
  - Body copy explains what happens, from the person's side ("Stash reads it in the background").
- **Machine voice:** lowercase, present tense, no punctuation beyond `…`, `:` and `>>`.
  - Findings read as `kind: value`.
  - A chain reads as `link: medium.com/… >> article about memory >> 2 minute read`.
- **Words:**
  - Use: *save* (not "capture" or "clip"); *your stash*; *find it by*; *make into*; *the
    background* (what Stash gathers); *ask*.
  - Avoid: "AI-powered", "magic", "supercharge", "seamless", exclamation marks, and emoji in
    product UI.
- **States:**
  - *Empty states* invite an action.
  - *Errors* name the problem and the next step ("That file is 3.4 MB. Try one under 2 MB.").
  - *Betas and stubs* say so plainly.
- **Prices:** "$4.99 a month". There's no trial copy unless there is a trial.

## 11. Accessibility

- **Contrast:** as in section 3. Spot fields carry ink (lime) or white (violet) text only.
- **Focus:** always visible. A 2 px ink outline with a 3 px offset, or `--on-spot` on spot fields.
- **Targets:** at least 44 px on touch. Machine tags that act as links get padding up to 32 px.
- **Departure Mono:** never for anything longer than a line, and never below 11 px.
- **Motion:** honour `prefers-reduced-motion` (see section 8). Ambient animation pauses off screen.
- **Drawings:** demos and drawings carry a `role="img"` with an `aria-label` describing what they
  show. Decorative canvases are `aria-hidden`.
- **Live regions** announce enrichment status (`aria-live="polite"` on status lines and the
  object card).

## 12. Surfaces

**Web app (first).**
- *Library:* object cards on paper, in a masonry or uniform grid. Each card shows its media (or
  placeholder), kind tag, title, two-line description and a meta row.
- *Saving:* the composer is the one input. A new save lands as a card in its reading state, and its
  findings decrypt in.
- *Item detail:* the object card large on a dotted stage, with the enrichment windows around it on
  leader lines: facts on the sides, "find it by" and "make into" (beta) below. Summary,
  transcript and page text sit in white sheets below the stage.
- *Ask:* a chat window whose tool steps run in the machine voice and whose answers cite object cards.
- *Settings:* plain white sheets, Montreal, ink controls. Connected agents show as a list of
  windows with their activity in Departure Mono.
- *Tokens:* go in CSS variables (block below) mapped into Tailwind's theme. Retire the violet
  identity utilities as each screen moves.

**iOS app (second), and the share extension.**
- *Share extension:* matches the prototype's save panel: the wordmark, a `saving` / `saved` tag (the
  spot when saved), a thumbnail, the title, a machine-voice sub-line, and "Add a note".
- *Library and detail:* follow the web app. Windows become full-width rows on small screens, with
  leaders replaced by a tree (`├─` / `└─` in Departure Mono, as the prototype's narrow layout does).
- *Type:* bundle Departure Mono beside Neue Montreal in both targets. Map the product scale onto
  Dynamic Type via the iOS text styles above.
- *Tokens:* `StashDesign.swift` gets v2 values from this file.

**Chrome extension.**
- Toolbar badge: the green check (`--ok`) when a save lands, a red mark when it fails.
- On-page feedback, if any, is a black toast.
- The install page is `extension.html` in the prototype.

**Marketing and help pages** follow the prototype exactly: homepage, `extension.html`,
`mcp.html`, `iphone.html`.

## 13. Implementation

```css
:root {
  --paper: #f3f4f1; --white: #ffffff; --ink: #000000; --muted: #5c6159;
  --line: #d5d8d1; --line-soft: #e5e7e2; --dot: rgba(0, 0, 0, .13);
  --spot: #a3f53b; --on-spot: #000000; --spot-ink: #1f4a38; --ascii: #000000; --spot-on-ink: #a3f53b;
  --ok: #2e9e52; --error: #a1281c;
  --sans: "PP Neue Montreal", "Helvetica Neue", Arial, sans-serif;
  --pixel: "Departure Mono", ui-monospace, "SF Mono", Menlo, monospace;
  --ease: cubic-bezier(.22, 1, .36, 1); --pop: cubic-bezier(.34, 1.56, .64, 1);
  --gutter: clamp(20px, 4vw, 56px); --max: 1360px;
  --r-object: 14px; --r-input: 12px; --r-window: 6px;
  --shadow-object: 0 1px 2px rgba(20, 22, 18, .05), 0 22px 44px -26px rgba(20, 22, 18, .32);
}
[data-spot="violet"] { --spot: #6d5bd0; --on-spot: #ffffff; --spot-ink: #5d49cb; --ascii: #ffffff; --spot-on-ink: #c9bfff; }
```

- **Tailwind:** expose these as `colors.{paper,ink,muted,line,spot,…}`,
  `fontFamily.{sans,pixel}`, `borderRadius.{object,input,window}` and `boxShadow.object`. Don't
  hard-code hex values in components.
- **SwiftUI:** `StashColor.paper/ink/muted/line/spot/onSpot`,
  `StashFont.montreal(role)` / `.pixel(size: 11 | 16.5 | 22)`, `StashRadius.object/input/window`.
- **Reference modules** in the prototype:
  - `js/enrich.js`: object card, placeholders, windows, leaders, make into, the live composer.
  - `js/liquid.js`: the pool, texture, drops and band.
  - `js/halftone.js`: halftone, knockouts, the calm footer.
  - `js/browser.js` and `js/ask.js`: Chrome and chat drawings.
  - `js/phone.js`: the iPhone film.
  - `js/site.js`: sprite, nav, footer.
  - `js/page.js`: decrypt, timelines, fit, chat helpers.

## 14. Do and don't

**Do:**
- Put the person's object in the middle and the machine around it.
- Use one spot colour, as a field.
- Square up anything Stash says.
- Let enrichment visibly arrive, then settle.
- Draw a placeholder for the kind of thing it is.
- Write the honest state.

**Don't:**
- Round machine elements, or square off objects.
- Set paragraphs in Departure Mono.
- Use a second accent colour, gradients on surfaces, or neon outside glyphs.
- Use tinted near-black, stock photos in product UI, or emoji.
- Loop animation on a calm screen.
- Show a fake success.
- Use pills, or drop shadows on windows.

## 15. Moving from DESIGN.md (v1)

| v1 | v2 |
|---|---|
| Grey chrome, violet = interactive | Paper and ink; the spot marks Stash at work and the one key action |
| Type-tinted card fields (the spectrum tints) | Real images, or a spot-field placeholder with a kind glyph; the kind is a black tag |
| Montreal everywhere | Montreal for human words, Departure Mono for the machine |
| Soft rounded controls, pills | Square buttons, tags and windows; only objects are soft |
| Gradient page wash | Flat paper; texture only in machine moments |
| Annotations: violet bar, italic | The person's notes stay italic Montreal on white; the bar becomes ink |

Behaviour contracts (what a screen does) are unchanged by this file. Log behaviour changes in
`docs/ui-changes.md` as before.
