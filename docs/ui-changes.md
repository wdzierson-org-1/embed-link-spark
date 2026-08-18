# UI changes — cross-platform log

Purpose: every meaningful web-UI/product-behavior change lands here as a dated
entry so the agents building the **iOS** (`ios/`) and **macOS** clients can
mirror behavior and data contracts without reverse-engineering the web code.
Newest entries first. Write for implementers on another platform: contracts
first, visuals second, with pointers to specs and source.

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
