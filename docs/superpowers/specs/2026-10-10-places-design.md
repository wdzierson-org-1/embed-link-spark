# Places: map-based shares, the map as the picture, the location section

**Date:** 2026-10-10 · **Status:** round 1 (map links) and round 2 (pictures with an address)
built; the map render and the geocoder wait on `MAPBOX_ACCESS_TOKEN` · **Owner:** web +
pipeline; iOS mirrors (plan 17, round 4)

## The ask

Will: "let's enrich map-based shares (or local information screenshots, images with addresses,
etc.) to show an embedded map as the image for the card as opposed to the icon we currently
show. it can be a rendered image of the location on the map or a live map plugin (image may be
better and more mobile compatible). for business listings … let's also add the open/closing
hours, phone number, and link to the menu if available … a new 'location details' section,
similar to the item details section at the bottom of the details screen."

Decisions (AskUserQuestion, 2026-10-10): **Mapbox static images** for the map; business facts
from **the share's own page** (no Yelp/Google lookups); **map links first**, then screenshots
and photos with addresses "as soon as #1 has been tested"; the object-intelligence facts UI is
prototyped first (separate page).

## What the data already gives us

An Apple Maps share (`https://maps.apple/p/<id>`) answers 404 to curl but, followed with a
browser user agent, resolves to `maps.apple.com/place?address=…&coordinate=lat,lng&name=…
&place-id=…`. The place page's HTML embeds the facts its own UI renders: `placeInfo.center`
and `timezone`, the business `entity` (telephone, url, localized categories), `rating`
objects (Yelp score/count, price level 1–4), the hours `calendar` (`daysIndex`, `timeRanges`
in seconds from midnight), `structuredAddress`, and the action row's Menu / Website / Call
anchors. Google Maps URLs carry the point in `!3d…!4d…` (or `@lat,lng`, `q=`) and the name
in the path. Listing pages (Yelp, OpenTable…) give address and coordinates through JSON-LD,
which Codex's `object_facts.place` already captures.

So business facts need no provider; only the map picture does (and, for images, a geocoder).

## Contract

`attributes.place` v1 — see `supabase/functions/_shared/place.ts` and the 2026-10-10 entry in
`docs/ui-changes.md`. Written only by the pipeline through `set_item_place` (leaf
compare-and-swap, migration `20261010180000`). `items.file_path` points at the rendered map
when one was made; `place.map` records it. The lane never replaces a person's own picture or
a protected title.

## Pipeline (round 1)

`scrape-page-content` → after the body step, under a fresh snapshot → `runPlaceStep`
(`_shared/placeEnrichment.ts`):

1. candidate? a map-provider address (`mapProviderOf`) or publisher facts with coordinates;
2. follow the address as a browser (`resolvePlacePage`, 12 s, ≤ 1.5 MB);
3. `buildPlace` from the saved URL, the resolved URL, the Apple page, the publisher facts;
4. render the map (`renderMapSnapshot`: `mapbox/light-v11`, `pin-l+1a1a1a`, 1200×630 @2x,
   attribution kept) when `MAPBOX_ACCESS_TOKEN` is set and the picture is Stash's to replace;
5. `set_item_place` (expected = the lane as read); on loss, discard the map and stand down;
6. `apply_enrichment_patch` for `file_path` (the map) and `title` (the place name over
   "Apple Maps" / a placeholder), under the fresh snapshot.

Never fatal to the scrape. Place facts join `enrichmentSearchText`.

## Web (round 1)

- `edit/LocationDetailsSection` on the panel and the shared page, above the details drawer.
- `utils/placeFacts`: hours rows (Monday first, `Mon–Thu 4:00–9:00 PM`), `openState` in the
  place's zone (null without one — then today's hours, never a claim), directions in the
  provider the save came from, phone formatting, labels.
- `kindLabel` reads `place` for a link with the lane; the publisher-facts section stands down.

## Round 2 — pictures with an address (built the same day)

`add-file` → after `analyze-image` → `runImagePlaceStep`: candidates from the OCR text and the
vision description (`extractAddressCandidates`: US "number street-word [, City, ST ZIP]" on
one line or across two, European "Street 4, 2100 City"; `extractPhone`, `extractWebsite`),
confirmed with Mapbox Geocoding v6 (`types=address`, `autocomplete=false`, `limit=1`; only
`exact` / `high` `match_code.confidence`), then the lane with `provider.kind: 'ocr'`,
`evidence.method: 'ocr-geocode'`, `evidence.source_url: 'stash-media:<file_path>'`, and the
map in `place.map` only — the photo stays the picture, the section shows the map. Migration
`20261010190000` widens `set_item_place`. Without the token the step keeps nothing and
reports the candidates it would have looked up.

## Later

- A live map on the panel stage (Mapbox GL or MapKit JS embed), like the YouTube player.
- Yelp / Google Places lookups for listings whose page gives no hours.
- Object-intelligence facts and next-action cells (prototype first).
