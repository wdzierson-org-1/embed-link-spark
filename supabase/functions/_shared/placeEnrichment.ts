// supabase/functions/_shared/placeEnrichment.ts
//
// The place step of the capture pipeline (scrape-page-content): follow the saved address the
// way a browser would, read what the provider's page says about the place, keep it as
// attributes.place through a leaf compare-and-swap (set_item_place), render the map Stash
// shows as the save's picture, and give a provider-titled save ("Apple Maps") the place's
// name. Every client gets the same result, whichever one saved the link.

import { ENRICHMENT_COLUMNS, applyCandidate } from './enrichmentStore.ts';
import { isPlaceholderMetadata } from './enrichmentQuality.ts';
import { readObjectFacts } from './objectFacts.ts';
import { buildPlace, isProviderTitle, mapProviderOf, mapboxStaticUrl, readPlace, type PlaceAttributes, type PlaceGeo } from './place.ts';

const BROWSER_UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15';
const PAGE_CAP_BYTES = 1_500_000;
const MAP_CAP_BYTES = 6_000_000;
export const MAP_STYLE = 'mapbox/light-v11';
export const MAP_ZOOM = 15;

export type PlaceStepEnv = {
  mapboxToken?: string;
  fetcher?: typeof fetch;
  now?: () => Date;
};

export type PlaceStepResult = { place: PlaceAttributes; map?: string } | { skipped: string };

type Fetcher = typeof fetch;
type ItemRow = {
  id: string; user_id: string; type: string; url: string | null; title: string | null; file_path: string | null;
  attributes?: Record<string, unknown> | null;
};

/** A saved address, followed as a browser follows it (map short links refuse other clients) */
export async function resolvePlacePage(url: string, fetcher: Fetcher = fetch): Promise<{ resolvedUrl: string; html?: string }> {
  try {
    const response = await fetcher(url, {
      headers: { 'User-Agent': BROWSER_UA, Accept: 'text/html,application/xhtml+xml,*/*;q=0.8', 'Accept-Language': 'en-US,en;q=0.9' },
      redirect: 'follow',
      signal: AbortSignal.timeout(12_000),
    });
    const resolvedUrl = response.url || url;
    if (!response.ok) return { resolvedUrl };
    if (!/text\/html/i.test(response.headers.get('content-type') ?? '')) return { resolvedUrl };
    const html = (await response.text()).slice(0, PAGE_CAP_BYTES);
    return { resolvedUrl, html };
  } catch (error) {
    console.warn('place: the address could not be followed', url, error instanceof Error ? error.message : error);
    return { resolvedUrl: url };
  }
}

/** Renders the map and stores it next to the save's other previews; null when it could not */
// deno-lint-ignore no-explicit-any
export async function renderMapSnapshot(db: any, userId: string, itemId: string, geo: PlaceGeo, token: string, fetcher: Fetcher = fetch): Promise<string | null> {
  try {
    const response = await fetcher(mapboxStaticUrl(geo, { token, zoom: MAP_ZOOM, style: MAP_STYLE }), { signal: AbortSignal.timeout(15_000) });
    if (!response.ok) {
      // The token never goes to the log; the status is enough to diagnose
      console.warn('place: map render refused', response.status);
      return null;
    }
    const bytes = new Uint8Array(await response.arrayBuffer());
    if (!bytes.length || bytes.length > MAP_CAP_BYTES) return null;
    const path = `${userId}/previews/map_${itemId}.png`;
    const { error } = await db.storage.from('stash-media').upload(path, bytes, { contentType: 'image/png', upsert: true });
    if (error) {
      console.error('place: storing the map failed', error);
      return null;
    }
    return path;
  } catch (error) {
    console.warn('place: map render failed', error instanceof Error ? error.message : error);
    return null;
  }
}

const sameSpot = (a?: PlaceGeo, b?: PlaceGeo): boolean =>
  !!a && !!b && Math.abs(a.latitude - b.latitude) < 1e-5 && Math.abs(a.longitude - b.longitude) < 1e-5;

/** A picture Stash fetched itself (a provider preview or an earlier map) may give way to the map; a person's upload never does */
const pictureIsReplaceable = (filePath: string | null | undefined): boolean =>
  !filePath || /\/previews\/(preview_|map_)/.test(filePath);

/** Whether this save could be a place at all — cheap enough to decide before any I/O */
export const isPlaceCandidate = (url: string | null | undefined, attributes: Record<string, unknown> | null | undefined): boolean =>
  !!mapProviderOf(url) || !!readObjectFacts(attributes?.object_facts, url ?? '')?.place?.geo;

// deno-lint-ignore no-explicit-any
export async function runPlaceStep(db: any, itemId: string, url: string, env: PlaceStepEnv = {}): Promise<PlaceStepResult> {
  const fetcher = env.fetcher ?? fetch;
  const nowIso = () => (env.now?.() ?? new Date()).toISOString();
  const { data: item, error } = await db.from('items').select(ENRICHMENT_COLUMNS).eq('id', itemId).single();
  if (error || !item) return { skipped: 'item_missing' };
  const row = item as ItemRow;
  const provider = mapProviderOf(url);
  const objectFacts = readObjectFacts(row.attributes?.object_facts, url);
  if (!provider && !objectFacts?.place?.geo) return { skipped: 'not_a_place' };

  const existing = readPlace(row.attributes?.place);
  const resolved = provider ? await resolvePlacePage(url, fetcher) : { resolvedUrl: url };
  const place = buildPlace({ url, resolvedUrl: resolved.resolvedUrl, html: resolved.html, objectFacts, observedAt: nowIso() });
  if (!place) return { skipped: 'nothing_found' };

  // A map already rendered for the same spot is kept; otherwise one is rendered when the
  // token allows and the save's picture is Stash's own to replace (never a person's upload)
  const keepMap = existing?.map && sameSpot(existing.geo, place.geo) ? existing.map : undefined;
  let mapPath = keepMap?.file_path;
  if (!mapPath && place.geo && env.mapboxToken && pictureIsReplaceable(row.file_path)) {
    mapPath = (await renderMapSnapshot(db, row.user_id, itemId, place.geo, env.mapboxToken, fetcher)) ?? undefined;
  }
  if (keepMap) place.map = keepMap;
  else if (mapPath) place.map = { file_path: mapPath, provider: 'mapbox', style: MAP_STYLE, zoom: MAP_ZOOM, rendered_at: nowIso() };

  const { data: written, error: rpcError } = await db.rpc('set_item_place', {
    target_id: itemId, expected_url: url, expected_place: existing ?? null, place,
  });
  if (rpcError) throw rpcError;
  if (written !== true) {
    if (mapPath && !keepMap) await db.storage.from('stash-media').remove([mapPath]);
    return { skipped: 'item_changed' };
  }

  // The picture and the title go through the usual patch, under a fresh snapshot: the lane
  // write above changed attributes, which the snapshot compares too
  const { data: fresh } = await db.from('items').select(ENRICHMENT_COLUMNS).eq('id', itemId).single();
  if (fresh) {
    const current = fresh as ItemRow;
    const patch: Record<string, string> = {};
    if (mapPath && current.file_path !== mapPath && pictureIsReplaceable(current.file_path)) patch.file_path = mapPath;
    const protectedFields = (current.attributes?.enrichment as { protected_fields?: { title?: boolean } } | undefined)?.protected_fields;
    if (place.name && protectedFields?.title !== true && (isProviderTitle(current.title) || isPlaceholderMetadata(current.title, url))) patch.title = place.name;
    if (Object.keys(patch).length) {
      const applied = await applyCandidate(db, current, patch, 'place-map');
      if (!applied) console.warn('place: the picture and title patch lost the snapshot race', itemId);
    }
  }
  return { place, map: mapPath };
}
