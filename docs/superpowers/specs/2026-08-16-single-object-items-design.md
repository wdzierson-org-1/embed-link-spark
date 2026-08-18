# Single-object items — collections retired

**Date:** 2026-08-16 · **Status:** implemented — capture behavior AND the card
system (foundation + all types wired into ContentItem; /design/cards keeps the
mock gallery plus a "wired" section rendering the real components)

## Implemented foundation (same day)

- Link notes live in `content` (annotation), never mixed into `description`
- `attributes.link = { flavor }` classified at save via `classifyLinkFlavor`
  (repo/video/book/social/article/generic; URL rules, unit-tested);
  `attributes.media = { duration_s, file_name }` from chip-time analysis
- "posted from" text lines retired — location is structured-only
- Cards: type-aware heroes (repo plate, contained portrait for video/book
  flavors, og cover with proxy fallback, favicon plate for metadata-poor
  links, video player + duration chip, document/image file plates, no hero
  for text/audio), domain kicker on links, annotation bar from content,
  metadata chips (mono filename, type · size, duration), masonry columns grid

## Point of view

Stash saves *objects* — links, pics, voice notes, meeting recordings, repos,
articles — and extracts as much metadata as it can. Capture the bare minimum,
the app fills in the rest, and everything is findable again fast (increasingly
by *where you were*: "I was at that cafe on Bleecker when I heard about this
book"). We are not a foldering system; organizing at capture time is the thing
we're eliminating.

Therefore: **one object = one item = one card = one embedding.** No more
collections. The old model also demoted attached objects to second-class
citizens (no own embeddings/tags/cards — folded into the parent's single
vector), which fought findability directly. Usage agreed: 14 of 523 items
(2.7%) were collections; 73% are links.

## Capture behavior (implemented)

- 0 chips → text note. 1 chip → that object. **N chips → N individual items.**
- The note (and its "posted from" line) rides on the **first** object; media
  notes go to `content` as before (rich Novel JSON allowed).
- A multi-object save shows a polite toast: "Saved as N items — Stash keeps
  one object per item; your note went with the first one."
- Content-model fix riding along: chip-time transcripts now land in
  `page_body` (source material), not `content` (user notes). Embeddings still
  include them, and rich-JSON notes are plain-texted before embedding.
- `attributes` (location) applies to every item in a batch.

## Legacy

Existing collection items stay: they render with the attachment-strip card
and keep their edit-sheet Attachments section. Nothing new is ever created
with `type='collection'` (`processCollection`, `analyze-collection`, and
`item_attachments` become legacy-only surfaces). If grouping returns someday,
it returns as boards/views *referencing* items — never as a container item.

## Card system (proposed — /design/cards gallery)

Shared anatomy: object zone → object's own title (editorial serif) → the
user's annotation (violet bar, when present) → extracted-metadata chips →
date · location pin · type. Per-type treatments shown in the gallery:

- **Link · article** — og image, `domain · author · read time` kicker
- **Link · book** — portrait cover contained on blurred self-backdrop; the
  location-recall showcase
- **Link · short-form video** — contained portrait thumb, play, `0:42 · @author`
- **Link · GitHub repo** — dark repo plate: mono path, language, stars, freshness
- **Image** — aspect-aware (portrait contained, never center-cropped)
- **Audio · voice note** — player bar + waveform + transcript excerpt
- **Video · meeting recording** — thumb + duration + decision summary + speakers
- **Document · PDF** — file plate (name/pages/size) + AI title + excerpt
- **Text note** — the words are the object; no decorative hero

Metadata chips that need new extraction when we wire this: video
duration/author (oEmbed), GitHub stars/language (API), read-time estimate,
audio duration, page counts. Aspect-aware framing and the annotation
treatment are pure frontend and can ship first.
