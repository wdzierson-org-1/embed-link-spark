# Stash — product ethos & architectural compass

This document is the **why** behind Stash, for every agent and person working on
any surface — web (`src/`), iOS (`ios/`), macOS, widgets, extensions, and
whatever comes next. When a design or implementation decision isn't spelled out
elsewhere, decide the way this document points. When a big decision *changes*
this document, change the document in the same commit.

The three-document system:
- **`docs/ETHOS.md`** (this file) — the compass. Why the product behaves the way
  it does; the standing architectural bets.
- **`docs/ui-changes.md`** — the cross-platform change log. Every meaningful
  UI/product-behavior change gets a dated entry, written contracts-first for
  implementers on the *other* platforms. Newest first.
- **`docs/PLATFORM_API.md`** — the wire contract. What every client calls; the
  server owns the intelligence.

## The core promise: lowest-friction capture

Stash is about how fast you can get something *in*. One thought, one link, one
photo, one voice memo — captured in a single gesture, with zero decisions beyond
"save this." Every decision we ask for at capture time (what to name it, how to
group it, where to file it) is friction, and friction kills capture. The user's
job ends at the moment of capture; everything after is ours.

Consequences:
- **One object at a time.** The input box accepts a single object per save.
  We do not bundle, and we never create container items ("collections" are
  retired — legacy ones render read-only, nothing creates new ones). Grouping
  at capture forces a second decision (what to upload *and* how to group), so
  it's out. A capture that arrives with several objects becomes several items,
  each a first-class citizen with its own card, embedding, and metadata.
- **No foldering, no organizing ritual.** Findability comes from enrichment and
  search, not from user-maintained structure. If grouping ever returns, it
  returns as boards/views *referencing* items — never as a container item that
  demotes its contents.
- **Capture surfaces multiply; the decision count doesn't.** Share sheets,
  widgets, Siri, SMS/WhatsApp, chat composers — every new surface should hit
  the same bar: get the object in with at most one tap/utterance beyond the
  content itself.

## Enrichment is the magic — and it lives behind the platform API

The user captures the bare minimum; the system fills in the rest: titles,
descriptions, page scrapes, transcripts, OCR, summaries, link flavor,
embeddings, location labels. This is the product's second half and it must feel
like magic, not like a form the user forgot to fill out.

Consequences:
- **Enrichment is a service today, and may become on-device eventually.** That
  is an explicit architectural bet: clients stay thin and call the platform's
  capture endpoints (`add-note` / `add-url` / `add-file`); enrichment runs
  *behind* those endpoints. Because clients never orchestrate enrichment
  themselves, its location (server today, on-device someday) can change without
  rewriting the clients.
- **Capture returns fast; enrichment lands async.** Endpoints respond in ~1s
  and enrich after the response; realtime delivers the upgrades. No client ever
  blocks a save on a model call.
- **The endpoints are the canonical write path for every non-web client** (and
  for web's own chat/API paths). Client-side inserts are a web-dashboard legacy
  pattern, not the direction.
- **Never fake enrichment.** Chips, badges, and metadata render only when the
  data exists. An honest "preview limited · saved anyway" beats a decorative
  placeholder.

## Objects, not documents-about-objects

An item *is* the thing saved — the link, the photo, the voice note — plus
structured facts about it. The card shows the object first (its image, its
plate, its player), then the object's own text, then the user's annotation
(always visually distinct from extracted text), then metadata. Structured facts
live in `items.attributes` (location, link flavor, media metadata — extensible
without migrations); user words live in `content`; captured source material
lives in `page_body`; AI text lives in `description`/`summary`. Keep those
lanes clean on every platform.

Location is the model case for capture-side metadata: **opt-in, one tap,
structured-only** ("where was I when I saved this" powers recall later), and
never stored as text pasted into the user's note.

## Working agreements (all platforms)

- Read `docs/ui-changes.md` before building or changing any capture or
  rendering behavior; write an entry there when you change one.
- Parity means matching *behavior and data contracts*, not pixel-cloning.
  Platform-native affordances (share sheets, widgets, CLGeocoder vs a web
  geocoder) are encouraged as long as the contracts hold.
- Cross-platform divergences that can't be avoided get flagged in
  `ui-changes.md` and resolved by a product decision — not silently shipped.

*Established 2026-08-22 from Will's direction; single-object model adopted
2026-08-16 (see `docs/superpowers/specs/2026-08-16-single-object-items-design.md`).*
