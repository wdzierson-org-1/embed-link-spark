# Capture panel upgrade — always-open, rich slash-command editor, location tagging

**Date:** 2026-08-11
**Status:** Implemented (this doc records the decisions; written during an autonomous session, so design choices below were made without interactive review — flag anything you'd like changed)

## What changed

### 1. Minimize removed
The capture panel is always expanded. Removed: the chevron minimize button, the
collapsed "Add something" state, the `stash_input_ui_collapsed` cookie, the
Safari-collapsed-by-default heuristic, and the auto-collapse after submit.
`UnifiedInputPanel` no longer takes `isInputUICollapsed` / `onToggleInputUI` /
`onUserToggleInputUI` / `onInputFocusChange` props. The stale cookie in existing
browsers is simply ignored.

### 2. Activation treatment
The shell (`input-panel-shell`) is now a framer-motion div. When active
(editor focused, or holding any text/chips), it lifts ~2px, scales to 1.006,
and takes a violet ring + soft halo (animated `boxShadow`, spring 320/28).
Resting state keeps a hairline border-shadow. No layout shift — everything is
shadow/transform based.

### 3. Slash commands in the capture box
The plain `Textarea` was replaced by `CaptureEditor`
(`src/components/capture/CaptureEditor.tsx`) — the same Novel/Tiptap stack the
edit sheet's notes tab uses (`createEditorExtensions`, `EditorCommandMenu`,
`EditorBubbleMenu`), so `/` opens the identical command menu: to-do list,
headings, bullet/numbered lists, quote, code, inline image upload. The
slash-command image upload already works pre-save (it only needs `userId`).

Capture-specific behavior, preserved from the old textarea:
- **URL detection → link chips**: the panel mirrors the doc as plain text on
  every update and runs the same `detectUrl` chip sync.
- **Enter submits** only while the note is a single plain paragraph with no
  hard breaks (i.e. what the old single-line rule allowed). Inside lists,
  code blocks, or multi-paragraph notes, Enter belongs to the editor.
  Shift+Enter still makes a line break. Slash-menu navigation always wins.
- **Escape** clears the note (or blurs when empty). When the slash menu is
  open, Escape just closes the menu.
- **Pasted images** are routed to the chip pipeline (vision analysis, separate
  item) exactly as before — inline images are available via `/image`.
- **File drops** anywhere on the panel still become chips; the editor declines
  file drops so the dropzone handles them.
- **Paste-anywhere-on-page** still lands in the capture box.

**Storage format:** at submit the doc has chip URLs stripped
(`stripUrlsFromDoc`). If what remains is plain paragraphs, it's saved as plain
text — byte-for-byte parity with the old behavior. If it has any structure
(lists, marks, headings, images), a text note stores the Novel JSON string —
the same format `EditItemContentEditor` already writes to `items.content`, so
the edit sheet round-trips it natively. For a single-link save, the note
flattens to plain text in the link's `description` (unchanged contract).
Collections store rich JSON when rich, plain when plain.

`contentProcessor` now pipes text-note content through
`extractPlainTextFromNovelContent` for the fallback title, AI title/description
prompts, and embeddings, so JSON never leaks into those.

Also fixed: the Tiptap `Placeholder` extension never rendered anywhere because
the required CSS was missing — added `.ProseMirror .is-empty::before` to
`index.css`, which turns placeholders on in the capture box *and* the edit
sheet notes tab.

### 4. Location pin
A `MapPin` toggle sits between Attach and Send. Toggling it on asks the
browser for position and reverse-geocodes via BigDataCloud's free key-less
client endpoint (`useCaptureLocation`); a small preview ("posted from
Brooklyn, New York") fades in next to the pin. On save, the panel appends a
`posted from <place>` line:
- text note: appended as a final line (paragraph node when the note is rich)
- single link: appended to the note text stored in `description`
- single media: appended to `content`
- collection: appended to the collection note

Only the friendly place name is stored — never coordinates. Denied/failed
lookups toast and switch the pin back off. A submit that races a pending
lookup waits at most 2.5s, then posts without the line. The label caches for
5 minutes.

**Data model (2026-08-11, third pass — location as a first-class attribute):**
`items.attributes jsonb not null default '{}'` with a GIN index
(`items_attributes_gin`) — migration `20260811130000_items_attributes_blob`,
applied to prod. This superseded the short-lived `posted_from text` column
(`20260811120000`, zero rows, dropped in the same day). Location lives at
`attributes.location`:

```json
{ "label": "Saratoga Springs, New York",
  "latitude": 43.08, "longitude": -73.78, "accuracy_m": 25,
  "city": "Saratoga Springs", "region": "New York", "country": "United States",
  "source": "browser-geolocation", "captured_at": "2026-08-11T…" }
```

Coordinates make future map views possible; `source` keeps collection
flexible (`browser-geolocation` today; `photo-exif` is a natural next
collector since chip analysis already runs exifr; `manual` for typed places).
TS shape: `src/types/itemAttributes.ts`. Search paths: the GIN index covers
jsonb containment/path queries for traditional filters; the "posted from …"
line in content already flows into embeddings for AI search. If map queries
get hot, promote lat/lng to generated columns or PostGIS — no client change
needed. The visible line remains the display source.

**Placeholder-duplication fix (second pass):** tiptap's Placeholder marks
empty *containers* (task list, task item) as `is-empty` along the whole anchor
chain, so the broad `.is-empty::before` CSS rendered the hint two or three
times after `/to-do` ("text repeated" bug). CSS is now scoped to
`p`/`h1–h6`, and the shared placeholder function only puts the main hint on
the doc's first node (`pos === 0`), so a fresh to-do row is just a checkbox
with a quiet cursor.

## Same-day follow-ups (location surfacing + title hygiene)

- **Collection title bug**: `processCollection` sent the raw note (Novel JSON
  for rich captures) as `userText` to `analyze-collection`, and the model
  echoed it into the title. Now the plain text goes to the AI, every collection
  title passes through `sanitizeItemTitle` (`src/utils/itemTitle.ts`) so editor
  markup can never become a title, and the no-AI fallback derives from the
  note's first line. The one affected prod row was repaired in place.
  `processCollection` also now writes `attributes` (it has its own insert path
  and was missed when the blob landed).
- **Location on cards**: `attributes` added to the dashboard list projection;
  card footer shows a pin + label next to the date when
  `attributes.location` exists.
- **Location editing**: `EditItemLocationSection` in the edit sheet's
  title/description card — click to edit, Enter/blur saves, clearing removes
  the location. Hand-typed places save as `{label, source: 'manual'}` and drop
  stale coordinates. Saves go straight through `saveItem` (no autosave
  machinery, no embedding churn).

## Files
- `src/components/capture/CaptureEditor.tsx` — new
- `src/hooks/useCaptureLocation.ts` — new
- `src/utils/captureDoc.ts` (+ tests) — new doc helpers
- `src/components/UnifiedInputPanel.tsx` — rewired (chip/metadata logic untouched)
- `src/pages/Index.tsx` — collapse plumbing removed
- `src/components/editor/EditorExtensions.ts` — optional placeholder override
- `src/utils/contentProcessor.ts` — plain-text extraction for AI/title/embeddings
- `src/index.css` — placeholder CSS

## Verification
- 111/111 vitest tests pass (16 new for doc helpers, 6 new panel tests for
  rich-note JSON, plain-note parity, minimize removal, and location tagging)
- `tsc --noEmit` clean, `vite build` clean, eslint clean on changed files
  (pre-existing `any` warnings in untouched code aside)
- Not browser-verified in this session (dashboard requires login) — worth a
  quick manual pass: slash menu opens, Enter still quick-saves a one-liner,
  task list Enter adds items, pin prompt + preview, saved rich note opens
  correctly in the edit sheet.
