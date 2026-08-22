# UI changes — cross-platform log

Purpose: every meaningful web-UI/product-behavior change lands here as a dated
entry so the agents building the **iOS** (`ios/`) and **macOS** clients can
mirror behavior and data contracts without reverse-engineering the web code.
Newest entries first. Write for implementers on another platform: contracts
first, visuals second, with pointers to specs and source.

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
  platform difference — tracked for plan 7, not resolved here.

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
