# Annotation on the item panel — exploration

**Date:** 2026-10-10 · **Status:** exploration; one affordance built (timestamped notes) ·
**Scope:** the web item panel first; iOS mirrors (plan 17).

Will (2026-10-10): "next, we will look to support annotation options on the media/pages/images
(etc.) on the detail panel from the user. let's start to explore controls that will allow for
this." He picked **timestamped notes on media** as the first thing to build; this note lays out
the rest so the next picks are cheap.

## 1. What annotation is, here

ETHOS: single-object capture, the person's own words in `content`, the machine's in the other
lanes. An annotation is the person's mark **on a specific place in the object** — a moment in a
recording, a passage of the page text, a region of a picture, a page of a PDF — kept with the
save and findable. Three rules follow:

1. **Annotations live with the note, not in a side system.** Wherever possible they are plain
   text inside `content` that any client renders, with the web making them live. That is why
   timestamps are `[1:42]` and not a table.
2. **The object is never altered.** A drawing on a picture is a layer; a highlight is a pointer
   into `page_body`; the original stays what Stash captured.
3. **One control grammar.** Every stage already has a cell row top-right (full size, full screen).
   Annotation controls join that row on the stage, and the **notes rule** (the `notes` section
   head) is where "add this to my note" actions appear.

## 2. The four candidates

| | Where it acts | The control | What is stored | Status |
|---|---|---|---|---|
| **Timestamped notes** | audio, video, YouTube | `+ note at 1:42` on the notes rule while a player reports time; `[1:42]` markers in the note seek the player | `[m:ss]` / `[h:mm:ss]` plain text in `content` | **Built** (2026-10-10) |
| **Text highlights** | original content, transcript, summary | select text → a small spot cell `highlight` (and `quote into note`); highlights listed under the tab and shown on the text | `attributes.annotations[]` of `{ kind: 'highlight', tab, quote, prefix, suffix, created_at }` — anchored by quote + context, not offsets, so a re-enrichment doesn't break them; `quote into note` writes a `> quote` block into `content` | proposed |
| **Image markup** | photos, screenshots, link covers | `draw` cell → a canvas layer over the picture: pen, box, arrow, a label; `done` saves | a transparent PNG layer uploaded beside the original (`attributes.annotations[]` `{ kind: 'layer', file_path, width, height }`); the hero shows original + layer | proposed |
| **Page comments** | the PDF reader, slides | `comment on page 3` on the notes rule (like `+ note at`) → `[p.3]` marker; markers jump the reader to the page | `[p.N]` plain text in `content`, same mechanism as timestamps | proposed, cheapest next |

**Recommended order:** page comments (reuses the timestamp machinery almost line for line; the
reader already exists), then text highlights (highest value for Ask: a highlight is the best
possible retrieval signal — index highlights with a boost), then image markup (needs an upload
path for the layer and a renderer on cards).

## 3. The control row, drawn

```
┌ stage ──────────────────────────────────────────────── [⤢][⛶] ┐    ← today: full size, full screen
│                                                                │
│                     (picture / player / pages)                 │
│                                                                │
└──────────────────────────────────────────────── [✎ draw]  ─────┘    ← image markup joins the row
notes ───────────────────────────────── [+ note at 1:42] [⤢]          ← today: timestamped note
                                         [comment on page 3]          ← page comments, same slot
summary  original content  transcript                    [⤢]
  …selected text…  ┌───────────────────────┐
                   │ highlight · quote into note │                      ← text highlights: a floating cell pair
                   └───────────────────────┘
```

Machine voice for every label (DESIGN-v2 §10); the spot colour only on the one thing just made
(a fresh highlight flashes spot, then settles to the fill).

## 4. Data contract sketch (`attributes.annotations`)

```json
{
  "annotations": [
    { "id": "ann_8f2", "kind": "highlight", "tab": "original", "quote": "machine-native intelligence", "prefix": "building ", "suffix": " infrastructure", "created_at": "2026-10-10T14:02:11Z" },
    { "id": "ann_9a1", "kind": "layer", "file_path": "u/ann_9a1.png", "width": 1200, "height": 800, "created_at": "…" }
  ]
}
```

- Whole-blob writes preserve unknown keys (the attributes rule in CLAUDE.md).
- Timestamps and page markers stay in `content`; they are the person's words.
- Highlights are included in the search index (`enrichmentSearchText`) with a boost; layers are
  not indexed.
- Sharing: the shared page shows highlights and layers read-only; markers are plain text there.

## 5. Open questions for Will

1. Page comments next, or text highlights first?
2. Should a highlight also become a sticky quote on the card (the public sticky-note slip, but
   private)?
3. Image markup: pen only, or boxes/arrows/labels too? (Pen only ships in a day; the full kit is
   a week.)
4. Do annotations count toward "the person's own words" for Ask (indexed with notes), or stay
   out of retrieval?
