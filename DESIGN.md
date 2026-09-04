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
5. **One UI family; the serif belongs to the objects.** PP Neue Montreal for
   all UI and content text, with weight as hierarchy. The single serif moment
   is the **card title** — PP Editorial New marks "this is a saved object" in
   the library grid. Nothing else is serif on product surfaces.
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
| Object title (card) | **PP Editorial New** 400 | 20 / tight | 0 | 2-line clamp — the one serif role |
| Object title (panel) | 500 | 28 / 1.2 | −0.02em | inline-editable |
| Display header (marketing, empty states) | 600 | 32–40 / 1.12 | −0.022em | |
| Body / description | 400 | 13.5–14.5 / 1.5–1.6 | 0 | muted color |
| User annotation | 400 italic | 13.5–14 | 0 | violet left bar, 2px |
| Micro-label (section headers) | 600 | 11 caps | +0.11em | `faint` color |
| Chip | 500 | 11 | 0 | mono variant: ui-monospace 10–11.5 |
| Kicker / eyebrow | 600 | 11 caps | +0.10em | |
| Date / meta | 400 | 12 | 0 | `faint` |

**Exceptions:** card titles use upright **PP Editorial New** (see table);
marketing pages (homepage, pricing) may use Tobias as the display face, with
PP Editorial New *Ultralight Italic* for single accent words inside display
headlines. PP Mori is retired everywhere; don't introduce Editorial in any
other product role.

## Color

Neutrals (chrome):

| Token | Value | Use |
|---|---|---|
| `ink` | `#22262f` | primary text |
| `muted` | `#646b76` | descriptions, secondary text |
| `faint` | `#959ba6` | meta, labels, icons at rest |
| hairline | `rgba(0,0,0,.07)` | section rules, borders |
| dotted rule | `rgba(0,0,0,.18)` | facts-row separators only |
| chip bg | `rgba(20,22,30,.05)` | neutral chips, icon tiles |
| page wash | grey base `#f7f7f9` + faint spectrum tint (see `src/index.css`) | app background |

**Page wash gradient** (the only sanctioned gradient; page backdrops + splash):
`linear-gradient(-45deg, #667eea, #764ba2, #9d5fd8, #c2418f, #4facfe, #38bdf8)` — web `.animated-gradient`
(400% canvas, 15s ease drift; static under reduced motion). iOS: `StashColor.gradientStops` in the same
order, drawn bottom-leading → top-trailing over a 2× canvas with a 40pt blur so no stop banding shows;
drift optional, palette mandatory.

Intent colors:

| Token | Value | Use |
|---|---|---|
| `violet-600` | `#6d5bd0` | interactive: links, active pills, switches-on, focus |
| `violet-300` | `#b6a8ef` | focus rings, annotation bar |
| destructive | `#c93a3a` | delete, irreversible |

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
  (`#6d5bd0`) focus ring — stroke @ .5, 6px halo @ .08, `0 24px 48px -20px`
  drop @ .35 — plus a 2px lift and 1.006 scale, spring transition (stiffness
  320, damping 28, mass 0.7). *2026-09-03 (plan 9): iOS harvest —
  `web src/components/UnifiedInputPanel.tsx`'s shell animation is the source
  of truth for the recipe's shape/timing; its `rgba(139,92,246,…)` is a
  legacy pre-token literal (Tailwind violet-500) that predates this file's
  `violet-600` token — read the ring's color as `violet-600` at those three
  alphas, and web should migrate its literal to the token in a follow-up.*

## Iconography

**Lucide only**, 2px stroke, `currentColor`, round caps/joins. Typical sizes:
11–13px in chips, 14–16px standalone. On iOS, SF Symbols may stand in where a
1:1 analog exists (lock, globe, play); otherwise ship the Lucide asset. Never
emoji, never mixed icon sets on one surface.

**Brand elements are flat.** No gradients in buttons, icons, favicons, or
marks — flat iconography on flat color (the favicon and the iOS app icon are
the stitched second-S in ink `#22262f` on white, all five glyph paths). The
splash gradient lives only in page washes.

*2026-09-03: iOS app icon exception revoked (Will) — icon now matches the
favicon.*

## Components

**Card anatomy** (top to bottom): hero → kicker (links: domain or author
handle) → title (PP Editorial New 400 · 20/tight, 2-line clamp) → description
(muted, clamp 3) → annotation (violet bar, italic) → chips → footer (date
left; overflow `more-horizontal` right).

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
  failure, both targets).*
- **Chrome extension** (restyle upcoming): plain-CSS the tokens above; no
  build step means copying values, so cite this file's section in a comment
  next to each token block.

## For agents

Read this file before building or changing UI on any surface. Match existing
rules exactly; don't introduce fonts, colors, icon sets, or radii not listed
here. If the work genuinely needs a new token, add it to this file in the same
branch with one line of rationale. Log behavior/contract changes in
`docs/ui-changes.md` as usual.
