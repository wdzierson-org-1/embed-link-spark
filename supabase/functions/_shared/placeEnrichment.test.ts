import { beforeEach, describe, expect, it, vi } from 'vitest';
import { isPlaceCandidate, runPlaceStep } from './placeEnrichment.ts';

const shortLink = 'https://maps.apple/p/7mJUJoBjKam4Ns';
const resolvedApple = 'https://maps.apple.com/place?address=55%20Phila%20St%2C%20Saratoga%20Springs%2C%20NY%20%2012866%2C%20United%20States&coordinate=43.080499,-73.783109&name=Solevo%20Kitchen%20+%20Social&place-id=I6DF1454FE08462BE&map=explore';
const applePage = `<html><body><a class="sc-unified-action-row-item" href="https://www.yelp.com/biz/solevo?x=1#menu_photos"><div class="sc-unified-action-row-title">Menu</div></a>
<script>var d = {"value":[{"entity":{"type":"BUSINESS","telephone":"+15184507094","url":"http://www.solevokitchenandsocial.com","name":[{"locale":"en-US","stringValue":"Solevo Kitchen + Social"}]}}],"hours":{"calendar":[{"daysIndex":[1,2,3,4],"timeRanges":[{"from":57600,"to":75600}]}]},"placeInfo":{"center":{"lat":43.0804988,"lng":-73.7831086},"timezone":{"identifier":"America/New_York"}}};</script></body></html>`;

type Row = { id: string; user_id: string; type: string; url: string; title: string; file_path: string | null; page_body?: string | null; attributes: Record<string, unknown> };

const makeDb = (row: Row, options: { rpcAnswer?: boolean } = {}) => {
  const calls = { rpc: [] as Array<[string, Record<string, unknown>]>, uploads: [] as string[], removed: [] as string[], patches: [] as Record<string, unknown>[] };
  const db = {
    from: () => ({ select: () => ({ eq: () => ({ single: async () => ({ data: structuredClone(row), error: null }) }) }) }),
    rpc: vi.fn(async (name: string, args: Record<string, unknown>) => {
      calls.rpc.push([name, args]);
      if (name === 'set_item_place') {
        const ok = options.rpcAnswer ?? true;
        if (ok) row.attributes = { ...row.attributes, place: args.place };
        return { data: ok, error: null };
      }
      if (name === 'apply_enrichment_patch') {
        calls.patches.push(args.patch as Record<string, unknown>);
        Object.assign(row, args.patch);
        return { data: true, error: null };
      }
      return { data: null, error: null };
    }),
    storage: { from: () => ({
      upload: async (path: string) => { calls.uploads.push(path); return { error: null }; },
      remove: async (paths: string[]) => { calls.removed.push(...paths); return { error: null }; },
    }) },
  };
  return { db, calls };
};

const htmlResponse = (url: string, body: string) => ({ ok: true, url, headers: { get: () => 'text/html; charset=utf-8' }, text: async () => body, arrayBuffer: async () => new ArrayBuffer(0) });
const pngResponse = () => ({ ok: true, url: '', headers: { get: () => 'image/png' }, text: async () => '', arrayBuffer: async () => new Uint8Array([137, 80, 78, 71]).buffer });

const fetcher = vi.fn(async (input: string | URL | Request) => {
  const url = String(input);
  if (url === shortLink) return htmlResponse(resolvedApple, applePage) as unknown as Response;
  if (url.startsWith('https://api.mapbox.com/')) return pngResponse() as unknown as Response;
  throw new Error(`unexpected fetch ${url}`);
});

const baseRow = (): Row => ({ id: 'item-1', user_id: 'owner-1', type: 'link', url: shortLink, title: 'Apple Maps', file_path: null, attributes: { link: { flavor: 'generic' } } });

describe('runPlaceStep', () => {
  beforeEach(() => { fetcher.mockClear(); });

  it('follows the share link, keeps the place, renders the map and names the save after the place', async () => {
    const row = baseRow();
    const { db, calls } = makeDb(row);
    const result = await runPlaceStep(db, 'item-1', shortLink, { mapboxToken: 'pk.test', fetcher, now: () => new Date('2026-10-10T12:00:00Z') });
    expect('place' in result && result.place).toMatchObject({
      name: 'Solevo Kitchen + Social', phone: '+15184507094', timezone: 'America/New_York',
      geo: { latitude: 43.080499, longitude: -73.783109 },
      hours: [{ days: [1, 2, 3, 4], ranges: [{ open: '16:00', close: '21:00' }] }],
      menu_url: 'https://www.yelp.com/biz/solevo?x=1#menu_photos',
      map: { file_path: 'owner-1/previews/map_item-1.png', provider: 'mapbox', zoom: 15, rendered_at: '2026-10-10T12:00:00.000Z' },
      provider: { kind: 'apple-maps', place_id: 'I6DF1454FE08462BE' },
    });
    expect(calls.uploads).toEqual(['owner-1/previews/map_item-1.png']);
    expect(calls.rpc.find(([name]) => name === 'set_item_place')?.[1]).toMatchObject({ target_id: 'item-1', expected_url: shortLink, expected_place: null });
    expect(calls.patches).toEqual([{ file_path: 'owner-1/previews/map_item-1.png', title: 'Solevo Kitchen + Social' }]);
    // The map request carried the token; the page request looked like a browser
    const mapCall = fetcher.mock.calls.find(([input]) => String(input).startsWith('https://api.mapbox.com/'));
    expect(String(mapCall?.[0])).toContain('access_token=pk.test');
    const pageCall = fetcher.mock.calls.find(([input]) => String(input) === shortLink);
    expect((pageCall?.[1] as RequestInit).headers).toMatchObject({ 'User-Agent': expect.stringContaining('Safari') });
  });

  it('keeps the facts without a map when no token is configured', async () => {
    const row = baseRow();
    const { db, calls } = makeDb(row);
    const result = await runPlaceStep(db, 'item-1', shortLink, { fetcher });
    expect('place' in result && result.place.name).toBe('Solevo Kitchen + Social');
    expect('place' in result && result.place).not.toHaveProperty('map');
    expect(calls.uploads).toEqual([]);
    expect(calls.patches).toEqual([{ title: 'Solevo Kitchen + Social' }]);
  });

  it('never replaces a picture the person uploaded, and keeps their title', async () => {
    const row = { ...baseRow(), title: 'Dinner on Friday', file_path: 'owner-1/1760000000000.jpg', attributes: { enrichment: { protected_fields: { title: true } } } };
    const { db, calls } = makeDb(row);
    await runPlaceStep(db, 'item-1', shortLink, { mapboxToken: 'pk.test', fetcher });
    expect(calls.uploads).toEqual([]);
    expect(calls.patches).toEqual([]);
  });

  it('replaces a provider preview Stash fetched itself with the map', async () => {
    const row = { ...baseRow(), file_path: 'owner-1/previews/preview_123.png' };
    const { db, calls } = makeDb(row);
    await runPlaceStep(db, 'item-1', shortLink, { mapboxToken: 'pk.test', fetcher });
    expect(calls.patches[0]).toMatchObject({ file_path: 'owner-1/previews/map_item-1.png' });
  });

  it('reuses a map already rendered for the same spot', async () => {
    const row = baseRow();
    row.attributes.place = { version: 1, geo: { latitude: 43.080499, longitude: -73.783109 }, map: { file_path: 'owner-1/previews/map_item-1.png', provider: 'mapbox', style: 'mapbox/light-v11', zoom: 15, rendered_at: '2026-10-09T00:00:00.000Z' }, provider: { kind: 'apple-maps', url: resolvedApple }, evidence: { source_url: shortLink, observed_at: '2026-10-09T00:00:00.000Z', method: 'map-page', extraction_version: 'place-v1' } };
    row.file_path = 'owner-1/previews/map_item-1.png';
    const { db, calls } = makeDb(row);
    const result = await runPlaceStep(db, 'item-1', shortLink, { mapboxToken: 'pk.test', fetcher });
    expect(calls.uploads).toEqual([]);
    expect('place' in result && result.place.map?.rendered_at).toBe('2026-10-09T00:00:00.000Z');
    expect(calls.rpc.find(([name]) => name === 'set_item_place')?.[1].expected_place).toMatchObject({ version: 1 });
  });

  it('discards its map and stands down when the leaf write loses the race', async () => {
    const row = baseRow();
    const { db, calls } = makeDb(row, { rpcAnswer: false });
    const result = await runPlaceStep(db, 'item-1', shortLink, { mapboxToken: 'pk.test', fetcher });
    expect(result).toEqual({ skipped: 'item_changed' });
    expect(calls.removed).toEqual(['owner-1/previews/map_item-1.png']);
    expect(calls.patches).toEqual([]);
  });

  it('is not a place for an ordinary link, before any fetch', async () => {
    const row = { ...baseRow(), url: 'https://example.com/article' };
    const { db } = makeDb(row);
    expect(await runPlaceStep(db, 'item-1', row.url, { mapboxToken: 'pk.test', fetcher })).toEqual({ skipped: 'not_a_place' });
    expect(fetcher).not.toHaveBeenCalled();
    expect(isPlaceCandidate(row.url, row.attributes)).toBe(false);
    expect(isPlaceCandidate(shortLink, {})).toBe(true);
  });

  it('reaches the page through Firecrawl when the provider refuses the function’s own address', async () => {
    const row = baseRow();
    const refusing = vi.fn(async (input: string | URL | Request, init?: RequestInit) => {
      const url = String(input);
      if (url === shortLink) return ({ ok: false, status: 404, url, headers: { get: () => 'text/html' }, text: async () => '' }) as unknown as Response;
      if (url === 'https://api.firecrawl.dev/v2/scrape') {
        expect(JSON.parse(String(init?.body))).toMatchObject({ url: shortLink, formats: ['rawHtml'] });
        expect((init?.headers as Record<string, string>).Authorization).toBe('Bearer fc-test');
        return ({ ok: true, status: 200, url, headers: { get: () => 'application/json' }, json: async () => ({ data: { rawHtml: applePage, metadata: { url: resolvedApple } } }) }) as unknown as Response;
      }
      if (url.startsWith('https://api.mapbox.com/')) return pngResponse() as unknown as Response;
      throw new Error(`unexpected fetch ${url}`);
    });
    const { db, calls } = makeDb(row);
    const result = await runPlaceStep(db, 'item-1', shortLink, { mapboxToken: 'pk.test', firecrawlKey: 'fc-test', fetcher: refusing });
    expect('place' in result && result.place).toMatchObject({ name: 'Solevo Kitchen + Social', hours: [{ days: [1, 2, 3, 4] }], provider: { url: resolvedApple }, evidence: { method: 'map-page' } });
    expect(calls.uploads).toHaveLength(1);
  });

  it('treats Apple’s "unsupported" shell as no page and asks Firecrawl for the real one', async () => {
    const row = baseRow();
    const shell = (url: string) => ({ ok: true, status: 200, url, headers: { get: () => 'text/html' }, text: async () => '<html><body>Unsupported browser</body></html>' }) as unknown as Response;
    const crawling = vi.fn(async (input: string | URL | Request) => {
      const url = String(input);
      if (url === shortLink) return shell('https://maps.apple.com/unsupported');
      if (url === 'https://api.firecrawl.dev/v2/scrape') return ({ ok: true, status: 200, url, headers: { get: () => 'application/json' }, json: async () => ({ data: { rawHtml: applePage, metadata: { url: resolvedApple } } }) }) as unknown as Response;
      if (url.startsWith('https://api.mapbox.com/')) return pngResponse() as unknown as Response;
      throw new Error(`unexpected fetch ${url}`);
    });
    const { db } = makeDb(row);
    const result = await runPlaceStep(db, 'item-1', shortLink, { mapboxToken: 'pk.test', firecrawlKey: 'fc-test', fetcher: crawling });
    expect('place' in result && result.place).toMatchObject({ hours: [{ days: [1, 2, 3, 4] }], timezone: 'America/New_York', provider: { url: resolvedApple } });
  });

  it('falls back to the captured markdown when neither the page nor Firecrawl can be reached', async () => {
    const row = { ...baseRow(), page_body: `# Solevo Kitchen + Social\n\nItalian Cuisine · [Saratoga Springs, NY](https://maps.apple.com/place?auid=1)\n\n[Call](tel:+15184507094) [Website](http://www.solevokitchenandsocial.com/)\n\n[Yelp](https://maps.apple.com/place?address=55%20Phila%20St,%20Saratoga%20Springs,%20NY&coordinate=43.080499,-73.783109&name=Solevo%20Kitchen%20+%20Social&place-id=I6DF1454FE08462BE&map=explore#)\n` };
    const refusing = vi.fn(async (input: string | URL | Request) => String(input).startsWith('https://api.mapbox.com/') ? pngResponse() as unknown as Response : ({ ok: false, status: 404, url: String(input), headers: { get: () => 'text/html' }, text: async () => '' }) as unknown as Response);
    const { db, calls } = makeDb(row);
    const result = await runPlaceStep(db, 'item-1', shortLink, { mapboxToken: 'pk.test', fetcher: refusing });
    expect('place' in result && result.place).toMatchObject({ name: 'Solevo Kitchen + Social', phone: '+15184507094', category: 'Italian Cuisine', geo: { latitude: 43.080499, longitude: -73.783109 }, provider: { kind: 'apple-maps', place_id: 'I6DF1454FE08462BE' }, evidence: { method: 'map-page' } });
    expect(calls.patches[0]).toEqual({ file_path: 'owner-1/previews/map_item-1.png', title: 'Solevo Kitchen + Social' });
  });

  it('says what it saw when nothing could be found', async () => {
    const row = baseRow();
    const refusing = vi.fn(async (input: string | URL | Request) => ({ ok: false, status: 404, url: String(input), headers: { get: () => 'text/html' }, text: async () => '' }) as unknown as Response);
    const { db } = makeDb(row);
    expect(await runPlaceStep(db, 'item-1', shortLink, { fetcher: refusing })).toEqual({ skipped: 'nothing_found', detail: { resolved: shortLink, status: 404, via: 'direct', html: 0, markdown: 0 } });
  });

  it('keeps going from the URL when the provider refuses the page', async () => {
    const row = { ...baseRow(), url: 'https://www.google.com/maps/place/Blue+Bottle/@37.78,-122.4,17z/data=!8m2!3d37.782!4d-122.406' };
    const refusing = vi.fn(async (input: string | URL | Request) => String(input).startsWith('https://api.mapbox.com/') ? pngResponse() as unknown as Response : ({ ok: false, status: 429, url: String(input), headers: { get: () => 'text/html' }, text: async () => '' }) as unknown as Response);
    const { db, calls } = makeDb(row);
    const result = await runPlaceStep(db, 'item-1', row.url, { mapboxToken: 'pk.test', fetcher: refusing });
    expect('place' in result && result.place).toMatchObject({ name: 'Blue Bottle', provider: { kind: 'google-maps' }, evidence: { method: 'map-url' } });
    expect(calls.uploads).toHaveLength(1);
  });
});
