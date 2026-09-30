# DESIGN.md — the Stash design system

This file is the single source of truth for how Stash looks and feels, on every
surface: the **web app** (`src/`), the **marketing homepage** (`src/pages/Landing.tsx`),
the **Chrome extension** (`extension/`), the **iOS app** (`ios/`, tokens live in
`StashDesign.swift`), the **iOS share sheet** (`ios/StashShareExtension/`), and the
**macOS menubar app** (separate repo). Agents and humans: read this before any UI
work; when a change alters a token or rule, edit this file in the same branch.
Behavioral contracts still go in `docs/ui-changes.md` — this file is *how things
look*, that one is *what changed and when*.

Reference implementations (interactive HTML, open from the repo):
- Cards: `docs/superpowers/prototypes/2026-08-30-card-type-gallery-neue-montreal.html`
- Detail panel: `docs/superpowers/prototypes/2026-08-30-detail-panel-surface-neue-montreal.html`

Where those comps and this file disagree, **this file wins** (2026-08-30
revisions after live review: serif card titles, full-bleed screenshots, violet
document tint, deeper purple-biased page gradient).

---

## Philosophy

1. **Grey chrome; color is information.** Every surface that isn't information
   is neutral grey — shadows, page wash, chips, dividers. Color appears only
   where it encodes something: an object's *type* (the spectrum tints), an
   *interactive* element (violet), a *state* (public = violet switch,
   destructive = red). If a color isn't telling the user something, remove it.
2. **The object is the hero.** Cards and panels present what the user saved,
   not our UI around it. The title is the AI's (or the user's) reading of the
   object — never a filename, never a platform slogan. The user's own words
   (annotations) always get the violet-bar treatment and italic voice.
3. **Flat, not gradient.** Type fields are single flat tints (plus optional
   paper grain as *texture*). Saturation lives in small functional accents —
   a play button, waveform bars — never washed across a surface.
4. **Lively, not cute.** No emoji anywhere in product UI, ever — including
   toasts, empty states, and notifications. Iconography is Lucide (see below).
   Motion is purposeful and brief; `prefers-reduced-motion` is always honored.
5. **One UI family.** PP Neue Montreal for all UI and content text, with
   weight as hierarchy — including card titles (Montreal medium, see below).
   *2026-09-13 (housekeeping mirror, plan 14): card titles moved off the
   single-serif treatment onto Montreal medium after a live `/design/cards`
   review; PP Editorial New has no remaining call site but stays defined in
   both `StashType`/CSS for a possible future serif moment.* *2026-09-30 (iOS
   plan 16): the face stays bundled, but `StashType.editorialTitle()` is
   deprecated; a future serif moment gets a proper role then.*
6. **Enrichment answers "why did I save this?"** before the user asks. Cards
   answer at a glance (type tint, title, one or two fact chips); the panel
   answers in full (summary, transcript, dotted facts).

## Typography

**Family: PP Neue Montreal** (Pangram Pangram), served locally.
Web files: `src/assets/fonts/PPNeueMontreal-{Book,Medium,Semibold,BookItalic}.woff2`
(+ `.woff`). Tailwind: `font-montreal` (the `body` default). iOS: bundle the same
weights in the app *and* share-extension targets (an appex cannot read the host
bundle); fall back to SF Pro only if the face fails to load.

| Role | Weight | Size / line | Tracking | Notes |
|---|---|---|---|---|
| Object title (card) | 500 | 20 / tight | −0.014em | 2-line clamp — Montreal medium (2026-09-13, plan 14; iOS `.stashFont(.cardTitle)`); superseded the prior PP Editorial New treatment |
| Object title (panel) | 500 | 28 / 1.2 | −0.02em | inline-editable |
| Display header (marketing, empty states) | 600 | 32–40 / 1.12 | −0.022em | |
| Body / description | 400 | 13.5–14.5 / 1.5–1.6 | 0 | muted color |
| User annotation | 400 italic | 13.5–14 | 0 | violet left bar, 2px |
| Micro-label (section headers) | 600 | 11 caps | +0.11em | `muted` — web should adopt (it still renders `faint`; see Contrast) |
| Chip | 500 | 11 | 0 | mono variant: ui-monospace 10–11.5 |
| Kicker / eyebrow | 600 | 11 caps | +0.10em | |
| Date / meta | 400 | 12 | 0 | `muted` — web should adopt (it still renders `faint`; see Contrast) |

This table is the **web** scale (desktop, pointer). *2026-09-30 (iOS plan 16): the
`faint` → `muted` change for micro-labels and dates is the contrast fix below. The web
still renders `faint` there and should adopt it; iOS migrates in plan 16's surface
passes.*

**iOS type roles (Dynamic Type).** *2026-09-30 (iOS plan 16).* iOS sets every piece
of text with a **role** — `.stashFont(.reading)` — never a raw point size. Each role is
a Neue Montreal face at Apple's default (Large) size for its text style, scaled with
that style by `Font.custom(_:size:relativeTo:)`, so it follows the user's text size.
Reading text is 17 pt, as in Apple's own apps (the old 14 pt body was why the detail
sheet read small).

| Role (`.stashFont(…)`) | Face | Large | xxxLarge | AX3 | Text style | Where |
|---|---|---|---|---|---|---|
| `display` | Semibold | 32 | 37 | 48 | `.largeTitle` | marketing, empty states · −0.022em |
| `panelTitle` | Medium | 28 | 34 | 47 | `.title` | the detail sheet's title · −0.02em |
| `screenTitle` | Medium | 22 | 27 | 41 | `.title2` | a screen's own title (Ask's "Chat with your Stash") |
| `cardTitle` | Medium | 20 | 26 | 41 | `.title3` | card titles · −0.014em |
| `reading` · `readingMedium` · `readingSemibold` · `readingItalic` | Book · Medium · Semibold · Book Italic | 17 | 22 | 37 | `.body` | detail description, notes, summary, transcript; chat bubbles and the Ask composer; the Add editor; the share-sheet note; search fields; markdown headings (Semibold); the user's own words (Italic) |
| `secondary` · `secondaryMedium` · `secondaryItalic` | Book · Medium · Book Italic | 15 | 20 | 32 | `.subheadline` | card descriptions, previews and notes; settings secondary lines; conversation previews; list-row titles and pill tabs (Medium) |
| `meta` · `metaMedium` | Book · Medium | 13 | 17 | 29 | `.footnote` | dates, facts, footers, status lines |
| `chip` | Medium | 12 | 17 | 29 | `.caption` | chips, badges |
| `microLabel` · `kicker` | Semibold | 12 | 17 | 29 | `.caption` | section labels / eyebrows, caps, +0.11em / +0.10em — `.stashMicroLabel()` / `.stashKicker()` apply face, caps, tracking and colour in one call |
| `textButton` | Book | 17 | 22 | 37 | `.body` | the keyboard Cancel (`StashCancelButton`) and other plain text buttons |
| `textButtonProminent` | Medium | 17 | 22 | 37 | `.body` | the one primary text action on a screen (the share sheet's Save, a Done); filled-button labels |
| `inlineButton` | Medium | 15 | 20 | 32 | `.subheadline` | inline text actions in content ("Retry", "Copy link") — never smaller |
| `mono(<style>)` | SF Mono | the style's | | | any | format/size chips, file names, URLs, timers |
| `custom(<face>, size:)` | any | `size` | | | nearest to `size` (or `relativeTo:`) | the escape hatch — prefer a named role |

- **How it scales.** The xxxLarge/AX3 columns are measured (iOS 17.0 and 26.5 alike):
  iOS scales custom fonts with `UIFontMetrics`, a slightly flatter curve than its own
  SF text styles at the top end (SF body is 23 / 40 there), rounded to whole points.
  That is the platform's behaviour for custom faces, and Xcode's Dynamic Type audit
  passes it.
- **Bold Text.** SwiftUI does not embolden bundled faces when Bold Text is on (measured:
  identical glyphs and widths under `legibilityWeight == .bold`, while SF text goes bold).
  `.stashFont` reads `legibilityWeight` and draws the next heavier face — Book → Medium,
  Medium → Semibold; Semibold and Book Italic have no heavier bundled face and stay —
  live, the moment the setting changes, with no rebuild of the view tree. Inside a
  `Text` concatenation, where a modifier can't reach one run, use
  `StashType.Role.<role>.font(legibilityWeight)` with the view's own
  `@Environment(\.legibilityWeight)`. SF text (system styles, `mono`, glyphs) follows
  Bold Text by itself.
- **Decorative art is the one fixed size.** `StashType.decorative(<face>, size:)` never
  scales and never follows Bold Text — for miniature illustrations and plates that draw
  text or glyphs at a set scale, and the view must be `accessibilityHidden(true)`.
  Anything a person reads to use the app takes a role, and is never below **11 pt** at
  the default size (`.caption2`, the HIG floor): smaller is decorative + hidden.
- **Tracking** stays in points: `.stashTracking(<em>, role: <role>)` — the table's em
  value times the role's Large size (`.stashTracking(-0.014, role: .cardTitle)`) — so it
  tightens in em terms as text grows, as Apple's own tracking does.
- **Leading grows with the text.** Extra line spacing is `.stashLeading(<em>, role:)`:
  `em` × the role's size, scaled with the role's text style (a `@ScaledMetric`), so
  `.stashLeading(0.55, role: .reading)` is 9.35 pt at Large and 20.35 pt at AX3.
  `em` is the gap on top of the face's own line height, so CSS `line-height: 1.55` is
  0.55. Never a fixed `lineSpacing(…)`: the old `14 * 0.55` shrank to 0.2 em at AX3.
- **Markdown and TipTap text** (measured, iOS 17.0 and 26.5): put the role on the `Text`
  that draws the `AttributedString` — `Text(attributed).stashFont(.reading)` — and its
  inline runs resolve against that face by themselves: `**strong**` (TipTap bold, TipTap
  headings) is Semibold, `*emphasis*` (TipTap italic) is Book Italic, `` `code` `` is the
  system monospaced face, at regular weight and under Bold Text (where the rest goes
  Medium). No helper needed. **A role applied outside a view whose `Text` sets its own
  font is dead** — the inner font wins — so a markdown heading passes its role into the
  function that builds
  the `Text` (`inlineText(text, role: .readingSemibold)`), never
  `inlineText(text).stashFont(.readingSemibold)`. Known limits (no face bundled):
  `***both***` draws Book Italic, and under Bold Text emphasis stays Book Italic inside
  Medium text.
- The web keeps its desktop scale (the table above); these roles are iOS-only.

**Exceptions:** marketing pages (homepage, pricing) may use Tobias as the
display face, with PP Editorial New *Ultralight Italic* for single accent
words inside display headlines. PP Mori is retired everywhere. PP Editorial
New's upright weight is no longer used anywhere on product surfaces as of
2026-09-13 (see card title row above) — don't reintroduce it without updating
this file.

## Color

Neutrals (chrome):

| Token | Value | Use |
|---|---|---|
| `ink` | `#22262f` | primary text |
| `muted` | `#646b76` | descriptions, secondary text, and informational meta — dates, facts, section labels, placeholders |
| `faint` | `#959ba6` | decorative and disabled only — hairline art, a disabled glyph, the idle send circle; never text a person reads (2.79:1) |
| hairline | `rgba(0,0,0,.07)` | section rules, borders |
| dotted rule | `rgba(0,0,0,.18)` | facts-row separators only |
| chip bg | `rgba(20,22,30,.05)` | neutral chips, icon tiles |
| page wash | grey base `#f7f7f9` + faint spectrum tint (see `src/index.css`) | app background |

**Page wash gradient** (the only sanctioned gradient; page backdrops, splash, and the app icon — see Logo):
`linear-gradient(-45deg, #667eea, #764ba2, #9d5fd8, #c2418f, #4facfe, #38bdf8)` — web `.animated-gradient`
(400% canvas, 15s ease drift; static under reduced motion). iOS: `StashColor.gradientStops` in the same
order, drawn bottom-leading → top-trailing over a 2× canvas with a 40pt blur so no stop banding shows;
drift optional, palette mandatory.

Intent colors:

| Token | Value | Use |
|---|---|---|
| `violet-600` | `#6d5bd0` | interactive: links, active pills, switches-on, focus |
| `violet-700` | `#5d49cb` | violet **text** on a type tint or a violet tint (session pill, due chip), where violet-600 text falls under AA |
| `violet-300` | `#b6a8ef` | focus rings, annotation bar |
| destructive | `#c93a3a` | delete, irreversible |
| `success` | `#2f9e63` | confirmation icons/labels (e.g. "Saved to Stash") |

**`success`** — *2026-09-04 (plan 11): new token, first legitimate need for a green —* web should
adopt for its own confirmation states. iOS `StashColor.success`; used on the share sheet's
"Saved to Stash" outcome icon and Ask's saved-chip "Saved to your stash" caption (both previously
a bare `.green`/system color with no token). The "will sync" (queued/offline) outcome icon uses
`violet-600`, not a new color — it's an active/in-progress state, not a distinct intent.

**Type spectrum** — flat tints at ~11–12% alpha over white for fields/chips,
with one saturated accent per type for controls. Color encodes the object's
type; these are the only decorative-adjacent colors allowed:

| Type | Field tint (rgba) | Accent / text |
|---|---|---|
| voice note | `84,88,178` @ .11–.12 | `#544eba` (play, waveform), text `#45408c` |
| recording / audio file | `126,74,158` @ .10–.11 | `#8b4a9e`, text `#703c77` |
| document (pdf/office) | `150,70,190` @ .10–.11 | text `#7d3f9e` |
| screenshot | `52,132,201` @ .08–.12 | text `#22689c` |
| repo | plate `#0d1117` | mono `#e6edf3`, owner `#8b7bd8` |
| social post | `70,100,180` @ .07 | quote in ink |

Photos, videos, and link covers use real imagery — no field, no tint.

**Gate strip** (lapsed-account capture lock, Add tab + share sheet): background
`#fff7e6`, border `#f3d9a4` (1px), text `#7a4b00`, `lock.fill`/lock glyph in the
same text color, radius 12px. *2026-09-03 (plan 9): new token — web should
adopt for its own gate messaging.*

**Contrast.** *2026-09-30 (iOS plan 16; WCAG 2.2 AA; web can adopt it as is).* Text a
person reads meets **4.5:1** on the background it actually sits on (3:1 once it is
large: 24 pt, or 18.7 pt bold). A control's only glyph, and any other graphic that
carries meaning, meets **3:1**. Disabled controls and pure decoration are exempt.
(WCAG's "large" is 18 pt / 14 pt bold in print points, i.e. 24 / 18.66 CSS px; on iOS
we read CSS px as points — both are ≈ 1/160 in on a device — so the thresholds are 24 pt
and 18.7 pt bold. That is deliberately stricter than Apple's own guidance, which allows
3:1 from 18 pt or at any bold weight.)

- **Meta text is `muted`.** Dates, facts, footers, section labels, the autosave line,
  placeholders. No separate meta grey: a lighter grey that still passed on the chip wash
  and the type tints would be indistinguishable from `muted`. The trade-off is that
  descriptions and meta now share a colour; hierarchy comes from size (15 vs 13), weight
  and position.
- **`faint` is decorative/disabled only**, including for glyphs: an enabled control's
  only glyph (a search clear ×, a chevron) is `muted` or `ink`.
- **Violet text** is `violet-600` on white, paper, the page wash and the chip wash, and
  `violet-700` on a type tint or a violet tint. Violet glyphs and fills stay violet-600
  everywhere (3:1).
- **Nothing but `ink` sits directly on the gradient wash.** Measured behind the Add-tab
  header and the View-tab search row, the wash takes violet-600 to 2.8–3.3:1 and `muted`
  to 3.0–3.4:1. Text over it sits on paper (cards, the search pill, a
  `StashCancelButton(onWash: true)` capsule — opaque paper, so its violet-600 word is
  5.18:1 over any wash).
- **A wash or tint stacked on a non-white surface needs its own check.** The table's
  tint rows are over white; stacking darkens. A chip wash on `#f2f2f7` takes `muted` to
  4.36 ✗ and violet-600 to 4.20 ✗; a voice tint @.12 over the page wash takes `muted` to
  4.26 ✗; a violet tint @.12 over the page wash, `muted` to 4.30 ✗. Use `ink` or
  `violet-700` there, or put the text on paper.
- **Placeholders are `muted`.** The system placeholder colour is 1.7:1. A custom
  placeholder `Text` takes `.foregroundStyle(StashColor.muted)`; a `TextField` takes
  `prompt: Text("…").foregroundStyle(StashColor.muted)` (honoured on iOS 17.0 and 26.5,
  verified).
- **`success` (`#2f9e63`, 3.39:1) is for icons and fills.** A confirmation caption is
  `ink`/`muted` text beside the success glyph.

| Background | ink | muted | faint | violet-600 | violet-700 | system placeholder |
|---|---|---|---|---|---|---|
| white: paper, cards, sheets | 15.15 | 5.38 | 2.79 ✗ | 5.18 | 6.40 | 1.73 ✗ |
| page wash `#f7f7f9` | 14.16 | 5.02 | 2.61 ✗ | 4.84 | 5.98 | 1.72 ✗ |
| iOS `secondarySystemBackground` `#f2f2f7` (Ask's answer bubble, empty state, restore banner) | 13.58 | 4.82 | 2.50 ✗ | 4.64 | 5.74 | 1.71 ✗ |
| chip bg `rgba(20,22,30,.05)` | 13.69 | 4.86 | 2.53 ✗ | 4.68 | 5.79 | 1.71 ✗ |
| voice field @.12 | 12.78 | 4.54 | 2.36 ✗ | 4.37 ✗ | 5.40 | 1.69 ✗ |
| recording/audio field @.11 | 12.94 | 4.59 | 2.39 ✗ | 4.42 ✗ | 5.47 | 1.69 ✗ |
| document field @.11 | 13.00 | 4.61 | 2.40 ✗ | 4.44 ✗ | 5.49 | 1.69 ✗ |
| screenshot field @.12 | 13.16 | 4.67 | 2.43 ✗ | 4.497 ✗ | 5.56 | 1.70 ✗ |
| social field @.07 | 13.79 | 4.89 | 2.54 ✗ | 4.71 | 5.83 | 1.71 ✗ |
| violet tint @.12 (session pill, active circle) | 12.92 | 4.58 | 2.38 ✗ | 4.41 ✗ | 5.46 | 1.69 ✗ |
| violet tint @.10 (due chip) | 13.27 | 4.71 | 2.45 ✗ | 4.54 | 5.61 | 1.70 ✗ |
| gradient wash, Add header (measured `#d8c7e4`) | 9.53 | 3.38 ✗ | 1.76 ✗ | 3.26 ✗ | 4.03 ✗ | 1.61 ✗ |
| gradient wash, View search row (measured `#d0b7de`) | 8.30 | 2.95 ✗ | 1.53 ✗ | 2.84 ✗ | 3.51 ✗ | 1.57 ✗ |
| opaque paper capsule on the wash (`StashCancelButton(onWash: true)`) | 15.15 | 5.38 | 2.79 ✗ | 5.18 | 6.40 | 1.73 ✗ |

Tint rows use each range's upper alpha (the darker end), over white. The type spectrum's
own text colours clear their fields comfortably (voice 7.49, audio 6.89, document 5.86,
screenshot 5.17), as do white on violet-600 (5.18), destructive on white (5.06) and the
gate strip (6.95). `success` is 3.04 on `#f2f2f7` — a glyph there, never text.

**Color scheme: light-only.** *2026-09-03 (plan 9):* Stash renders in the
light palette above only — no dark-mode stylesheet or trait variant on any
surface. iOS pins `.preferredColorScheme(.light)` on the root scene
regardless of system appearance; web ships no dark stylesheet to toggle.

## Space, radius, elevation

- Radius: **16px** cards & fields · **12–14px** inputs, inner tiles, media
  blocks · **999px** pills/chips. Sheet/panel: 20px.
- **`--card-gap: 18px`** — the gap between hero bottom and card body top, for
  *every* hero type, no per-type exceptions. Card body side padding 24px;
  cards without a hero take 22px top padding.
- **Library gutter: 24px/24pt** between cards (web's masonry/masonry-rows
  `gap-6`; iOS `LibraryView`'s grid spacing, plan 14 — was 14pt). Cards are
  natural height, no forced row-equalization; a phone's single column needs
  no masonry redistribution (web's multi-column masonry-rows algorithm is a
  desktop/iPad-only concern).
- Card shadow: `0 1px 2px rgba(20,22,30,.05), 0 8px 24px rgba(30,33,44,.08)`;
  hover: `0 2px 4px rgba(20,22,30,.06), 0 14px 36px rgba(30,33,44,.13)` with a
  2px lift. Sheet shadow: `0 2px 6px rgba(20,22,30,.05), 0 24px 70px rgba(30,33,44,.16)`.
- Panel section grammar: uppercase micro-label over a hairline rule — never a
  nested card/box. Dotted rules appear *only* between facts rows.
- **Composer card** (Add tab / homepage capture panel): radius **6px**,
  `white/90` background + backdrop blur. Idle shadow
  `0 0 0 1px rgba(0,0,0,.05), 0 10px 30px -18px rgba(0,0,0,.3)`. *iOS:*
  radius 12 / y 8 / `black@.14` + 1pt `black@.05` hairline — tempered because
  SwiftUI shadows have no spread; do not "correct" the alpha to `.3`. While
  composing (focused or has content), a three-layer **violet-600**
  (`#6d5bd0`) focus ring — 1px stroke @ .5, 6px halo @ .08, `0 24px 48px -20px`
  drop @ .35 — plus a 2px lift and 1.006 scale, spring transition (stiffness
  320, damping 28, mass 0.7). *2026-09-03 (plan 9): iOS harvest —
  `web src/components/UnifiedInputPanel.tsx`'s shell animation is the source
  of truth for the recipe's shape/timing; its `rgba(139,92,246,…)` is a
  legacy pre-token literal (Tailwind violet-500) that predates this file's
  `violet-600` token — read the ring's color as `violet-600` at those three
  alphas, and web should migrate its literal to the token in a follow-up.*
  *2026-09-04 (plan 10): the ring's stroke layer is 1px, not 1.5px — see the
  rule below; halo and shadow layers are unchanged.*
  *2026-09-04 (plan 10, feedback round 2): composer card ≤ 2/3 of the
  container height on iOS (people mostly capture via the share sheet; the
  in-app composer is the secondary path) — web panel unaffected.*
- **Strokes are 1px, always** — buttons, inputs, rings, tiles. Emphasis comes
  from color, not weight, never from a heavier stroke. (Bars/fills like the
  library card's annotation bar are fills, not strokes, and are exempt.)
  *2026-09-04 (plan 10): web should follow — it currently has a 1.5px
  composer ring stroke and 2px input focus rings that both violate this.*

## Iconography

**Lucide only**, 2px stroke, `currentColor`, round caps/joins. Typical sizes:
11–13px in chips, 14–16px standalone. On iOS, SF Symbols may stand in where a
1:1 analog exists (lock, globe, play); otherwise ship the Lucide asset. Never
emoji, never mixed icon sets on one surface.

**Logo.** The wordmark is the five letters "Stash" from
`brand/stash-wordmark.svg` (no strokes, no tagline), always one flat colour via
`currentColor` / template rendering: ink `#22262f` on app surfaces,
`text-gray-900` in the web header, `#666666` on the landing nav. Shipped heights:
web header + auth 24px, pricing/legal/landing 20px; iOS header 20pt, sign-in
28pt, splash 40pt; extension sign-in 26px. Never set the name in type instead.

**The app icon is a white S on the purple→blue wash:** the wordmark's first S
(`brand/stash-s.svg`) in white `#ffffff` at 62% of the tile, centred on the
purple→blue stops of the page-wash gradient (`#764ba2 → #9d5fd8 → #667eea →
#4facfe`, bottom-left → top-right) — the one brand mark that sits on a gradient
(the "Stash" wordmark itself stays ink). `brand/icon-src.html` is the source;
`node brand/build.mjs` regenerates the favicon set, PWA icons, extension icons,
iOS AppIcon and the onboarding tile. Square where the OS masks (iOS, touch/PWA),
20% radius with transparent corners where it doesn't (favicon, extension). Every
other brand element stays flat: no gradients in buttons, chips, or marks.

*2026-09-15: icon moved from the flat stitched second-S on white to the first S
on the wash, and the wordmark replaced with the "Stash" lettering (Will);
the 2026-09-03 "icon matches the favicon" note is superseded — they still match,
both are now the S on the wash.*

*2026-09-30 (iOS plan 16): the S went from ink `#22262f` to white `#ffffff` on
every icon the build writes — iOS app + share extension, onboarding tile, favicon
set, PWA/touch icons, Chrome extension (Will). The wash and the 62% scale are
unchanged. White measures 3.4:1 or better against the wash under every part of
the S (WCAG's graphical-object floor is 3:1); keep it above that if the wash
stops ever change. The macOS menubar icon lives in `stash-mac` and does not
follow until that repo re-runs the source at `#size=1024`.*

## Components

**Card anatomy** (top to bottom): hero → kicker (links: domain or author
handle) → title (Montreal medium 500 · 20/tight · −0.014em, 2-line clamp) →
description (muted, clamp 3) → note (see below) → chips → footer (date ·
reminder chip · location pin left; overflow `more-horizontal` right).

**Card note** (2026-09-13, plan 14 — supersedes the old read-only "annotation"
row): the card's `content` field, editable in place. An empty note shows an
"Add a note" affordance (muted text + `plus` glyph) occupying the old chip
area. An existing note is tappable, 5-line clamp, with a straight square-ended
**2pt violet-600 fill** along its left edge (a fill, not a stroke — the 1px
stroke rule doesn't apply here) and only its **right** corners rounded on the
hover/press surface. Tapping either opens a compact rich-document editor:
edits patch `items.content` — the same TipTap document the detail sheet's
Notes editor reads/writes — never flattened to plain text. Explicit Save/
Cancel; Return inserts a line (no separate hard-break gesture needed once
Enter no longer submits). A confirmed save washes the note with violet-300 at
25% opacity fading to 0 over 450ms, plus a brief checkmark + "Saved" caption
(~2s); both are static (no fade animation) under reduced motion. A failed
save keeps the draft and shows an inline error instead.

*iOS (2026-09-27, plan 15): the card is ONE tap target that opens the detail
sheet — no in-card controls. The note renders read-only (same violet fill bar,
5-line clamp, right-rounded surface; nothing at all when empty — no "Add a
note"), and is written in the detail sheet's Notes editor. The link kicker is
a plain label (the sheet's URL bar opens the link). Web keeps the inline
editor above. Supersedes plan 14's iOS card-note sheet.*

**Cover crops are subject-aware.** A hero that `cover`-crops an image centres
the crop on the detected subject, not the frame: sample the image (≤64px),
take the border-ring median as the background, bound everything that differs
from it, and slide the crop so that box is centred (web `useSubjectCrop`;
algorithm in `src/utils/heroFocal.ts`). Portrait media keeps the contained
treatment; nothing changes when the subject fills the frame.

Per-type hero:

| Type | Hero |
|---|---|
| voice note | player on voice field: solid play circle, waveform, duration (height 116) |
| recording | compressed player on audio field (height 96) |
| video (upload or link) | poster frame + centered play badge + duration on scrim — no native `<video controls>` chrome |
| photo | full-bleed image (h-40; tall h-56 with blurred self-backdrop for portrait) |
| screenshot | full-bleed image, same as photo — the tinted screenshot chip carries the identity |
| document | first-page thumbnail floating on document field + format badge |
| article/product/recipe/place link | cover image (+ price pill for product) |
| social | pull-quote (500) + avatar/handle on social field |
| repo | dark plate: `owner/repo` mono + stars/language/freshness |
| note | no hero — the text is the hero |

**Chips grammar**, in order, nothing else: tinted type chip (always visible —
replaces any hover-only type badge) → format·size (mono) → one salient fact
(duration / pages / read-time / price-date). **No tag UI on cards or panel** —
tags are retired; themes will handle grouping.

**Reminder chip** (footer, after the date; both platforms): scheduled = clock
icon + relative time in the muted meta style; due = bell + "Due" in
violet-600 on a 10 % violet field with an always-visible × ("Remove
reminder", ≥24 px hit area on the web, 44 pt on iOS; the "Due" text itself is
`violet-700` on iOS, see Contrast). Due cards also carry a violet-600 "Due" pill in
the hero-corner badge zone next to "Processing…" / "PUBLICLY SHARED". Neither
belongs in the chips row.

**Player** (card hero and panel strip share it): flat type-tint field, solid
accent play/pause circle, waveform bars in accent at .72 (unplayed .26),
tabular-numeral times, speed pill (1× → 1.5× → 2×).

**Detail panel**: one surface, flow layout (no rail). Order: eyebrow (type
chip + source) → title → description → annotation → media → URL bar (both
platforms render it after media, before the content tabs) → content tabs
(Notes/Transcript/Summary/Original per type) → **Details drawer** (collapsed by
default; summary shows format · size · duration inline; expands to dotted
key-value rows incl. original filename and location) → Sharing → footer
(Delete left, autosave right).

**Sharing row states**: private = grey lock tile, switch off. Public = violet
globe tile, violet switch, feed-link chip (`gostash.it/feed/{username}`) with
copy-confirm, and the un-share warning inline. Un-sharing an item with a sticky
note confirms first.

**Switches**: 40×24, knob 20, violet-600 when on. **Focus**: 2px `violet-300`
ring. **Inline-editable text** (panel title/description): no input chrome at
rest; violet wash on hover; wash + ring on focus.

**Controls (iOS)** — *2026-09-30 (iOS plan 16), Apple HIG + WCAG 2.2.*

- **44 × 44 pt targets.** Every tappable element takes touches across at least 44 × 44 pt,
  whatever it looks like. A smaller visual keeps its size and position, and its target
  grows around it without moving layout — an overhang. It is built into `CircleIcon`,
  `CircleSubmitIcon`, `PillTabs` and `StashCancelButton`; a custom control gets it from
  `.buttonStyle(.stashPlain)` (`.plain` with the target on the label), or by hand from
  `.stashMinimumHitTarget()` **on the label, inside `label:`** — on the `Button` it is a
  44 pt dead zone that swallows taps and activates nothing. It matters even though SwiftUI
  hit-tests a touch with a radius: over anything else tappable, such as a card, a row or a
  sheet, an exact hit on that surface wins, so a small control only gets the taps its own
  shape covers. Two targets closer than 44 pt (centre to centre) overlap, and the later one
  wins. An overhang is lost wherever an ancestor clips — past a `ScrollView`'s edge, inside
  `.clipped()` / `.clipShape` — so keep a small control's centre ≥ 22 pt inside such an
  edge. (The web keeps WCAG's 24 px floor, e.g. the reminder chip's ×.)
- **Icon chrome stays put.** Circle buttons and other glyph-only controls keep fixed glyph
  and circle sizes at every text size, like the system's bar buttons. They name
  themselves with `.stashIconControl("<name>", systemImage: "<glyph>")`, which gives
  VoiceOver the label and, at accessibility sizes, shows the name and glyph in the Large
  Content Viewer on a long press. A control that toggles a state (the location pin, the
  public globe) passes `isOn:` too, so VoiceOver hears a toggle that is "On" or "Off", not
  a colour.
- **One keyboard Cancel.** `StashCancelButton` is the only Cancel shown while a field has
  the keyboard (Ask, the Add tab, the View-tab search): the `textButton` role, violet-600,
  and ⌘. on a hardware keyboard (plain Esc stays with the focused field). Its 44 pt target
  overhangs the word, so it appears without moving anything — no height to reserve: a
  `StashHeader` changes by under 1 pt (32 → 32.67 pt at Large, measured), and beside a
  42 pt search pill the row keeps the pill's height (the word lays out 20.67 pt tall).
  The word never breaks or truncates (it is one line at full width,
  and claims its width before a flexible neighbour). Over the gradient wash it is
  `StashCancelButton(onWash: true)`, an opaque paper capsule whose vertical padding is
  drawn, not laid out (see Contrast). What it does is the caller's action; the VoiceOver
  hint defaults to "Hides the keyboard", and a Cancel that also clears something (the
  View-tab search) passes its own `hint:`.
- **Pill tabs are segmented chrome.** Labels (`secondaryMedium`) grow with Dynamic Type
  up to xxxLarge and stop there. At accessibility sizes a long press shows a tab's label
  in the Large Content Viewer, as with `UISegmentedControl`. Content-sized tabs that
  outgrow the width scroll sideways, never truncate. The selected tab carries VoiceOver's
  Selected trait.
- **Text grows; containers follow.** Anything holding text uses `minHeight`, never a
  fixed height. Screens that can overflow at large sizes scroll. At accessibility sizes a
  row that can't fit reflows (an `HStack` becomes a `VStack`) instead of truncating what
  the user needs to read: titles, names, errors and actions wrap.
- **Every icon-only control has a VoiceOver label.** Decorative images are
  `accessibilityHidden`. State that is only visual — which tab is selected, whether a
  toggle is on — is also given to VoiceOver (the Selected trait; a toggle's On/Off value).

## Motion

- Card hover: shadow + 2px lift, 200ms. Drawer/chevron: 180ms. Feed-link chip:
  180ms fade/slide-in.
- Playing state: unplayed waveform bars pulse opacity (1.4s loop).
- Every animation has a `prefers-reduced-motion` guard (including
  `.animated-gradient`, guarded in `src/index.css`). Perpetual ambient
  animation is sanctioned on exactly three web surfaces: the homepage hero,
  the library page wash, and the sign-in page wash — nowhere else on web.
  *2026-09-03 (plan 8): reconciled with iOS — the animated page wash also
  plays on iOS's sign-in, Add-tab composer, View-tab library, launch splash,
  and share-sheet compose screens (`AnimatedGradient`/`GradientBackdrop` in
  `StashDesign.swift`), static under `accessibilityReduceMotion` the same
  way web's version is static under `prefers-reduced-motion`.*
  *2026-09-04 (plan 10, task 1): iOS renders the blurred sweep to a static
  image once per size (deterministic across GPUs); only the pan animates.*
  *2026-09-04 (plan 10, feedback round 2, task 1 hitch fix): that per-size
  render is two-tier — an instant plain (unblurred) gradient paints the first
  frame synchronously, the blurred version renders on a background queue and
  fades in OVER the plain tier (~0.35s, hard swap under reduced motion) once
  ready — the plain tier stays fully opaque underneath throughout rather than
  dimming out in lockstep (a true crossfade), which used to produce a visible
  mid-fade lightening dip — so the blur's cost never lands on the first
  frame's main thread.*
  *2026-09-27 (plan 15, task 4): the share-sheet compose screen no longer
  shows the gradient (Will, 2026-09-27) — it sits on plain paper
  (`StashColor.paper`), and its header carries extra top/leading inset so the
  wordmark clears iOS 26's larger sheet corners. The iOS wash stays on
  sign-in, the Add-tab composer, the View-tab library and the launch splash.*
- The loading interstitial (`LoadingInterstitial.tsx`) is a quiet arc
  spinner: hairline grey track, violet-600 rounded-cap arc, 0.9s spin, on the
  plain grey wash. It shows for a split second — nothing on it should demand
  attention (no copy, no gradients, no mark animation).

## Voice & copy

Active voice, sentence case, plain verbs ("Save changes", not "Submit").
Buttons say what happens; an action keeps its name through the flow. Errors say
what went wrong and what to do next — no apology, no vagueness. Empty states
invite an action. Never filler ("Here is…", "Certainly…") in AI-generated
titles/descriptions — enrichment prompts enforce this (`NO_PREAMBLE_RULES`).

## Per-surface notes

- **Web app**: tokens land through Tailwind utilities + `src/index.css`. The
  violet identity is currently hard-coded in utilities; when touching a
  component, prefer these documented values over inventing new ones.
- **Homepage**: follows everything here; Tobias display hero + ambient
  gradient are its two sanctioned exceptions.
- **iOS (app + share sheet)**: `StashDesign.swift` mirrors these tokens —
  when it disagrees with this file, this file wins and both get fixed in the
  same change. Bundle PP Neue Montreal in both targets. SF Symbols per the
  iconography rule. The share sheet is the same design language, not a
  simplified one. *2026-09-03: `StashDesign`/`StashType` re-derived so token
  values and the typography scale now match this file verbatim (plan 7); the
  share extension renders Neue Montreal too (SF Pro fallback only on load
  failure, both targets).* *2026-09-30 (plan 16): text is set with roles
  (`.stashFont(…)`, Typography › iOS type roles) and controls follow Components ›
  Controls (iOS). The pre-plan-16 `StashType` helpers are deprecated and their
  build warnings are the migration list. A DEBUG build launched with
  `--uitest-type-specimen` shows every role, the shared controls and the contrast
  cases on one screen; `A11yFoundationUITests` measures it, and
  `A11yScreenshotSupport.swift` shoots any screen at Large, xxxLarge, AX3 and Bold Text
  (`--uitest-bold-text` sets the window scene's Bold Text trait, so it reaches every tab
  and sheet — all but iOS 17's tab bar labels, which follow only the real setting; check
  each Bold Text shot differs from its Large one).*
- **Chrome extension** (restyle upcoming): plain-CSS the tokens above; no
  build step means copying values, so cite this file's section in a comment
  next to each token block.

## For agents

Read this file before building or changing UI on any surface. Match existing
rules exactly; don't introduce fonts, colors, icon sets, or radii not listed
here. If the work genuinely needs a new token, add it to this file in the same
branch with one line of rationale. Log behavior/contract changes in
`docs/ui-changes.md` as usual.
