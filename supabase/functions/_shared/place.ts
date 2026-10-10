// supabase/functions/_shared/place.ts
//
// Places (docs/ui-changes.md 2026-10-10 "Map-based shares"): the structured facts a saved
// address stands for — where it is, when it is open, how to reach it — kept by the capture
// pipeline in `attributes.place` (v1) for every client. This module is pure: it reads map
// provider URLs and the Apple Maps place page; the fetches, the map render and the writes
// live in placeEnrichment.ts. Web mirror of the types: src/types/itemAttributes.ts imports
// them from here.

import type { ObjectFacts } from './objectFacts.ts';

/** `ocr`: an address read from a picture's own text and geocoded (round 2) */
export type PlaceProviderKind = 'apple-maps' | 'google-maps' | 'page' | 'ocr';
export type PlaceGeo = { latitude: number; longitude: number };
/** `open`/`close` are "HH:MM" in the place's own day; `next_day` marks a close past midnight */
export type PlaceHoursRange = { open: string; close: string; next_day?: boolean };
/** `days` are 0 = Sunday … 6 = Saturday */
export type PlaceHours = Array<{ days: number[]; ranges: PlaceHoursRange[] }>;
export type PlaceAddress = {
  lines?: string[];
  street?: string;
  locality?: string;
  region?: string;
  region_code?: string;
  postal_code?: string;
  country?: string;
  country_code?: string;
};
export type PlaceAttributes = {
  version: 1;
  name?: string;
  address?: PlaceAddress;
  geo?: PlaceGeo;
  /** IANA zone, when the provider states it; without it clients show the hours but never "open now" */
  timezone?: string;
  phone?: string;
  website?: string;
  menu_url?: string;
  hours?: PlaceHours;
  rating?: { score: number; max: number; count?: number; source?: string };
  price_range?: { level: number; max: number };
  category?: string;
  provider: { kind: PlaceProviderKind; place_id?: string; url: string };
  /** The rendered map Stash stored as the save's picture (items.file_path points at it too) */
  map?: { file_path: string; provider: 'mapbox'; style: string; zoom: number; rendered_at: string };
  evidence: { source_url: string; observed_at: string; method: 'map-page' | 'map-url' | 'json-ld' | 'ocr-geocode'; extraction_version: 'place-v1' };
};

export const PLACE_EXTRACTION_VERSION = 'place-v1' as const;

const parseUrl = (url: string | null | undefined): URL | null => {
  if (!url) return null;
  try {
    const parsed = new URL(url);
    return ['http:', 'https:'].includes(parsed.protocol) ? parsed : null;
  } catch {
    return null;
  }
};

const clean = (value: unknown, limit = 300): string | undefined => {
  if (typeof value !== 'string') return undefined;
  const text = value.replace(/\s+/g, ' ').trim();
  return text && text.length <= limit ? text : undefined;
};

const compact = <T extends object>(value: T): T =>
  Object.fromEntries(Object.entries(value).filter(([, v]) => v !== undefined)) as T;

const coordinateFrom = (text: string | null | undefined): PlaceGeo | undefined => {
  if (!text) return undefined;
  const match = text.trim().match(/^(-?\d{1,2}(?:\.\d+)?),\s*(-?\d{1,3}(?:\.\d+)?)$/);
  if (!match) return undefined;
  return geoFrom(Number(match[1]), Number(match[2]));
};

const geoFrom = (latitude: number, longitude: number): PlaceGeo | undefined =>
  Number.isFinite(latitude) && Number.isFinite(longitude) && Math.abs(latitude) <= 90 && Math.abs(longitude) <= 180 && (latitude !== 0 || longitude !== 0)
    ? { latitude: Number(latitude.toFixed(6)), longitude: Number(longitude.toFixed(6)) }
    : undefined;

/** Which map provider a saved address belongs to, if any */
export const mapProviderOf = (url: string | null | undefined): Exclude<PlaceProviderKind, 'page'> | null => {
  const parsed = parseUrl(url);
  if (!parsed) return null;
  const host = parsed.hostname.toLowerCase().replace(/^www\./, '');
  if (host === 'maps.apple' || host === 'maps.apple.com' || host.endsWith('.maps.apple.com')) return 'apple-maps';
  if (host === 'maps.app.goo.gl' || host === 'maps.google.com' || host.endsWith('.maps.google.com')) return 'google-maps';
  if (host === 'goo.gl' && parsed.pathname.startsWith('/maps')) return 'google-maps';
  if (/^google\.[a-z.]+$/.test(host) && parsed.pathname.startsWith('/maps')) return 'google-maps';
  return null;
};

/** The provider's own name as a page title ("Apple Maps", "Google Maps"): never a save's title */
export const isProviderTitle = (title: string | null | undefined): boolean =>
  /^(apple maps|google maps|maps)(\s*[-–—|·:].*)?$/i.test((title ?? '').trim());

export type PlaceUrlFacts = { name?: string; address?: string; geo?: PlaceGeo; placeId?: string };

/**
 * A query value as written: Apple encodes spaces as %20 and keeps a literal "+" (as in
 * "Solevo Kitchen + Social"), which URLSearchParams would read as a space.
 */
const rawParam = (parsed: URL, ...keys: string[]): string | undefined => {
  for (const pair of parsed.search.replace(/^\?/, '').split('&')) {
    const at = pair.indexOf('=');
    const key = at < 0 ? pair : pair.slice(0, at);
    if (!keys.includes(key)) continue;
    try {
      return decodeURIComponent(at < 0 ? '' : pair.slice(at + 1));
    } catch {
      return undefined;
    }
  }
  return undefined;
};

/** maps.apple.com/place?…: the resolved form of an Apple Maps share carries the facts in its query */
export const parseAppleMapsUrl = (url: string | null | undefined): PlaceUrlFacts => {
  const parsed = parseUrl(url);
  if (!parsed || mapProviderOf(url) !== 'apple-maps') return {};
  return compact({
    name: clean(rawParam(parsed, 'name', 'q'), 200),
    address: clean(rawParam(parsed, 'address')),
    geo: coordinateFrom(rawParam(parsed, 'coordinate', 'll', 'sll')),
    placeId: clean(rawParam(parsed, 'place-id', 'auid'), 80),
  });
};

const decodeSegment = (segment: string): string | undefined => {
  try {
    return clean(decodeURIComponent(segment.replace(/\+/g, ' ')), 200);
  } catch {
    return undefined;
  }
};

/** google.com/maps/place|search|dir/…/@lat,lng,…/data=…!3dLAT!4dLNG, maps?q=lat,lng, and friends */
export const parseGoogleMapsUrl = (url: string | null | undefined): PlaceUrlFacts => {
  const parsed = parseUrl(url);
  if (!parsed || mapProviderOf(url) !== 'google-maps') return {};
  const segments = parsed.pathname.split('/').filter(Boolean);
  const data = segments.find((segment) => segment.startsWith('data=')) ?? '';
  let geo: PlaceGeo | undefined;
  // The place's own point (!3d lat !4d lng) beats the viewport centre after the @
  const point = data.match(/!3d(-?\d+(?:\.\d+)?)!4d(-?\d+(?:\.\d+)?)/);
  if (point) geo = geoFrom(Number(point[1]), Number(point[2]));
  if (!geo) {
    const pairs = [...data.matchAll(/!1d(-?\d+(?:\.\d+)?)!2d(-?\d+(?:\.\d+)?)/g)];
    const last = pairs[pairs.length - 1];
    if (last) geo = geoFrom(Number(last[2]), Number(last[1]));
  }
  if (!geo) {
    const at = segments.find((segment) => segment.startsWith('@'))?.match(/^@(-?\d+(?:\.\d+)?),(-?\d+(?:\.\d+)?)/);
    if (at) geo = geoFrom(Number(at[1]), Number(at[2]));
  }
  const q = parsed.searchParams;
  if (!geo) geo = coordinateFrom(q.get('q')) ?? coordinateFrom(q.get('ll')) ?? coordinateFrom(q.get('center')) ?? coordinateFrom(q.get('destination'));
  let name: string | undefined;
  let address: string | undefined;
  if (segments[0] === 'maps') {
    const mode = segments[1];
    if ((mode === 'place' || mode === 'search') && segments[2] && !segments[2].startsWith('@')) name = decodeSegment(segments[2]);
    if (mode === 'dir') {
      // Stops are the segments between /dir/ and the viewport; flags like am=t and data= are not stops
      const stops = segments.slice(2).filter((segment) => !segment.startsWith('@') && !segment.includes('='));
      const destination = stops[stops.length - 1];
      if (destination) address = decodeSegment(destination);
    }
  }
  if (!name) {
    const query = q.get('q') ?? q.get('query') ?? q.get('destination');
    if (query && !coordinateFrom(query)) name = clean(query, 200);
  }
  return compact({ name, address, geo });
};

// ---- the Apple Maps place page ---------------------------------------------------------------

/** Reads one JSON value (object or array) starting at `start`, respecting strings */
const readJsonValue = (text: string, start: number, cap = 200_000): string | undefined => {
  const open = text[start];
  if (open !== '{' && open !== '[') return undefined;
  let depth = 0;
  let inString = false;
  for (let i = start; i < text.length && i - start < cap; i++) {
    const ch = text[i];
    if (inString) {
      if (ch === '\\') i++;
      else if (ch === '"') inString = false;
      continue;
    }
    if (ch === '"') inString = true;
    else if (ch === '{' || ch === '[') depth++;
    else if (ch === '}' || ch === ']') {
      depth--;
      if (depth === 0) return text.slice(start, i + 1);
    }
  }
  return undefined;
};

const jsonAfter = (text: string, key: string): unknown => {
  let from = 0;
  while (from < text.length) {
    const at = text.indexOf(key, from);
    if (at < 0) return undefined;
    const start = at + key.length;
    const raw = readJsonValue(text, start);
    if (raw) {
      try {
        return JSON.parse(raw);
      } catch {
        /* keep looking */
      }
    }
    from = start;
  }
  return undefined;
};

const record = (value: unknown): Record<string, unknown> | undefined =>
  value && typeof value === 'object' && !Array.isArray(value) ? (value as Record<string, unknown>) : undefined;

const localized = (value: unknown): string | undefined => {
  const first = Array.isArray(value) ? record(value[0]) : record(value);
  return clean(first?.stringValue, 200);
};

const clock = (seconds: number): string => {
  const inDay = ((seconds % 86_400) + 86_400) % 86_400;
  const h = Math.floor(inDay / 3600);
  const m = Math.floor((inDay % 3600) / 60);
  return `${String(h).padStart(2, '0')}:${String(m).padStart(2, '0')}`;
};

const hoursFromCalendar = (calendar: unknown): PlaceHours | undefined => {
  if (!Array.isArray(calendar)) return undefined;
  const hours: PlaceHours = [];
  for (const entry of calendar.slice(0, 14)) {
    const row = record(entry);
    const days = Array.isArray(row?.daysIndex) ? row!.daysIndex.filter((d): d is number => Number.isInteger(d) && d >= 0 && d <= 6) : [];
    const ranges = (Array.isArray(row?.timeRanges) ? row!.timeRanges : [])
      .map((range) => record(range))
      .filter((range): range is Record<string, unknown> => !!range && typeof range.from === 'number' && typeof range.to === 'number')
      .slice(0, 6)
      .map((range) => {
        const from = range.from as number;
        const to = range.to as number;
        return compact({ open: clock(from), close: clock(to), next_day: to >= 86_400 || to <= from ? true : undefined });
      });
    if (days.length && ranges.length) hours.push({ days, ranges });
  }
  return hours.length ? hours : undefined;
};

const decodeEntities = (value: string): string =>
  value.replace(/&amp;/g, '&').replace(/&#x27;|&#39;/g, "'").replace(/&quot;/g, '"').replace(/&lt;/g, '<').replace(/&gt;/g, '>');

const webAddress = (value: string | undefined): string | undefined => {
  if (!value) return undefined;
  const parsed = parseUrl(decodeEntities(value));
  return parsed && parsed.href.length <= 2048 ? parsed.href : undefined;
};

export type ApplePlacePage = {
  name?: string;
  geo?: PlaceGeo;
  timezone?: string;
  phone?: string;
  website?: string;
  menu_url?: string;
  category?: string;
  rating?: PlaceAttributes['rating'];
  price_range?: PlaceAttributes['price_range'];
  hours?: PlaceHours;
  address?: PlaceAddress;
};

/** The facts the Apple Maps place page embeds for its own UI: hours, phone, website, menu, ratings, address */
export const extractApplePlacePage = (html: string): ApplePlacePage => {
  const text = html.slice(0, 1_500_000);
  const out: ApplePlacePage = {};

  const placeInfo = record(jsonAfter(text, '"placeInfo":'));
  const center = record(placeInfo?.center);
  if (center && typeof center.lat === 'number' && typeof center.lng === 'number') out.geo = geoFrom(center.lat, center.lng);
  const timezone = clean(record(placeInfo?.timezone)?.identifier, 64);
  if (timezone && /^[A-Za-z_]+\/[A-Za-z_\/+-]+$/.test(timezone)) out.timezone = timezone;

  const entity = record(jsonAfter(text, '"entity":'));
  if (entity) {
    out.name = localized(entity.name);
    out.phone = clean(entity.telephone, 40);
    out.website = webAddress(clean(entity.url, 2048));
    const categories = Array.isArray(entity.localizedCategory) ? entity.localizedCategory.map(record).filter(Boolean) : [];
    const deepest = categories.sort((a, b) => Number(b!.level ?? 0) - Number(a!.level ?? 0))[0];
    out.category = localized(deepest?.localizedName);
  }

  for (const match of text.matchAll(/"rating":\{"ratingType":"(USER_RATING|PRICE_RANGE)","score":(\d+(?:\.\d+)?),"maxScore":(\d+)(?:,"numRatingsUsedForScore":(\d+))?/g)) {
    const score = Number(match[2]);
    const max = Number(match[3]);
    if (match[1] === 'USER_RATING' && !out.rating) out.rating = compact({ score, max, count: match[4] ? Number(match[4]) : undefined, source: 'yelp' });
    if (match[1] === 'PRICE_RANGE' && !out.price_range) out.price_range = { level: score, max };
  }

  out.hours = hoursFromCalendar(jsonAfter(text, '"calendar":'));

  const structured = record(jsonAfter(text, '"structuredAddress":'));
  const lines = jsonAfter(text, '"formattedAddressLines":');
  if (structured || Array.isArray(lines)) {
    out.address = compact({
      lines: Array.isArray(lines) ? lines.map((line) => clean(line, 120)).filter((line): line is string => !!line).slice(0, 4) : undefined,
      street: clean(structured?.fullThoroughfare, 160) ?? ([clean(structured?.subThoroughfare, 20), clean(structured?.thoroughfare, 120)].filter(Boolean).join(' ') || undefined),
      locality: clean(structured?.locality, 80),
      region: clean(structured?.administrativeArea, 80),
      region_code: clean(structured?.administrativeAreaCode, 12),
      postal_code: clean(structured?.postCode, 20),
      country: clean(structured?.country, 80),
      country_code: clean(structured?.countryCode, 4),
    });
  }

  // The action row: Call · Website · Menu — the menu link only lives here
  for (const anchor of text.matchAll(/<a\b([^>]*)>([\s\S]*?)<\/a>/gi)) {
    if (!/sc-unified-action-row-item/.test(anchor[1])) continue;
    const href = anchor[1].match(/\bhref\s*=\s*"([^"]+)"/i)?.[1];
    const title = anchor[2].match(/sc-unified-action-row-title[^>]*>\s*([^<]+?)\s*</i)?.[1]?.trim().toLowerCase();
    if (!href || !title) continue;
    if (title === 'menu' && !out.menu_url) out.menu_url = webAddress(href);
    if (title === 'website' && !out.website) out.website = webAddress(href);
    if (title === 'call' && !out.phone && href.startsWith('tel:')) out.phone = clean(decodeURIComponent(href.slice(4)), 40);
  }
  return compact(out);
};

/**
 * The Apple Maps place page as the capture step keeps it (Firecrawl's markdown): its links carry
 * the resolved place address (coordinate, name, address, place id), the action row
 * (`[Call](tel:…) [Website](…) [Menu](…)`), the category line and the Yelp score. Hours and
 * the time zone only live in the page's HTML, so this is the fallback when that is out of reach.
 */
export type AppleMarkdownPage = ApplePlacePage & { urlFacts?: PlaceUrlFacts; placeUrl?: string };

export const extractAppleMarkdown = (markdown: string): AppleMarkdownPage => {
  const text = markdown.slice(0, 400_000);
  const out: AppleMarkdownPage = {};
  for (const match of text.matchAll(/https:\/\/maps\.apple\.com\/place\?[^\s)\]"']+/g)) {
    const candidate = match[0].replace(/&amp;/g, '&').replace(/#$/, '');
    const facts = parseAppleMapsUrl(candidate);
    if (facts.geo) {
      out.urlFacts = facts;
      out.placeUrl = candidate;
      out.geo = facts.geo;
      out.name = facts.name;
      if (facts.address) out.address = { lines: [facts.address] };
      break;
    }
  }
  const action = (label: string): string | undefined =>
    text.match(new RegExp(`\\[${label}\\]\\(([^)\\s]+)\\)`, 'i'))?.[1];
  const tel = action('Call');
  if (tel?.startsWith('tel:')) out.phone = clean(decodeURIComponent(tel.slice(4)), 40);
  out.website = webAddress(action('Website'));
  out.menu_url = webAddress(action('Menu'));
  // "Italian Cuisine · [Saratoga Springs, NY](…)" under the name
  const category = text.match(/^([^\n\[\]·]{2,60}) · \[/m)?.[1]?.trim();
  if (category && !/^https?:/.test(category)) out.category = clean(category, 80);
  const yelp = text.match(/\nYELP\s*\n+\((\d[\d,]*)\)\s*\n+(\d(?:\.\d)?)\s*\n/);
  if (yelp) out.rating = { score: Number(yelp[2]), max: 5, count: Number(yelp[1].replace(/,/g, '')), source: 'yelp' };
  return compact(out);
};

const priceLevelFrom = (range: string | undefined): PlaceAttributes['price_range'] | undefined => {
  const symbols = range?.trim().match(/^([$€£¥])\1{0,3}$/);
  return symbols ? { level: range!.trim().length, max: 4 } : undefined;
};

export type BuildPlaceInput = {
  /** The saved address */
  url: string;
  /** Where the saved address led once followed (the share short link's target) */
  resolvedUrl?: string;
  html?: string;
  /** The page as the capture step kept it (markdown), when the HTML was out of reach */
  markdown?: string;
  objectFacts?: ObjectFacts;
  observedAt?: string;
};

/** Everything the save's own URL, page and publisher facts say about the place, or nothing */
export const buildPlace = (input: BuildPlaceInput): PlaceAttributes | undefined => {
  const provider: PlaceProviderKind | null = mapProviderOf(input.resolvedUrl) ?? mapProviderOf(input.url) ?? (input.objectFacts?.place ? 'page' : null);
  if (!provider) return undefined;
  const fromMarkdown = provider === 'apple-maps' && input.markdown ? extractAppleMarkdown(input.markdown) : undefined;
  const fromUrl: PlaceUrlFacts = provider === 'apple-maps'
    ? { ...(fromMarkdown?.urlFacts ?? {}), ...parseAppleMapsUrl(input.url), ...parseAppleMapsUrl(input.resolvedUrl) }
    : provider === 'google-maps'
      ? { ...parseGoogleMapsUrl(input.url), ...parseGoogleMapsUrl(input.resolvedUrl) }
      : {};
  const fromHtml = provider === 'apple-maps' && input.html ? extractApplePlacePage(input.html) : undefined;
  // The HTML's facts win; the markdown fills what it did not reach
  const { urlFacts: _urlFacts, placeUrl: linkedPlaceUrl, ...markdownFacts } = fromMarkdown ?? {};
  const page: ApplePlacePage | undefined = fromHtml || fromMarkdown ? { ...markdownFacts, ...compact(fromHtml ?? {}) } : undefined;
  const facts = input.objectFacts?.place;
  const factsAddress: PlaceAddress | undefined = facts?.address
    ? compact({ street: facts.address.street_address, locality: facts.address.locality, region: facts.address.region, postal_code: facts.address.postal_code, country: facts.address.country })
    : undefined;
  const name = page?.name ?? fromUrl.name ?? clean(input.objectFacts?.name, 200);
  const geo = page?.geo ?? fromUrl.geo ?? facts?.geo;
  const address = page?.address ?? (fromUrl.address ? { lines: [fromUrl.address] } : factsAddress);
  if (!name && !geo && !address) return undefined;
  const observed = input.observedAt ? new Date(input.observedAt) : new Date();
  // The provider's own place address: the resolved one when it names the place (Apple sends
  // some clients to maps.apple.com/unsupported), else the one the page linked to itself
  const resolvedNamesPlace = mapProviderOf(input.resolvedUrl) && (provider !== 'apple-maps' || Object.keys(parseAppleMapsUrl(input.resolvedUrl)).length > 0);
  const providerUrl = (resolvedNamesPlace && parseUrl(input.resolvedUrl)?.href) || (linkedPlaceUrl && parseUrl(linkedPlaceUrl)?.href) || parseUrl(input.url)?.href || input.url;
  return compact({
    version: 1 as const,
    name,
    address,
    geo,
    timezone: page?.timezone,
    phone: page?.phone,
    website: page?.website,
    menu_url: page?.menu_url,
    hours: page?.hours,
    rating: page?.rating,
    price_range: page?.price_range ?? priceLevelFrom(facts?.price_range),
    category: page?.category ?? facts?.cuisine?.[0],
    provider: compact({ kind: provider, place_id: fromUrl.placeId, url: providerUrl }),
    evidence: {
      source_url: input.url,
      observed_at: (Number.isFinite(observed.getTime()) ? observed : new Date()).toISOString(),
      method: (fromHtml && Object.keys(fromHtml).length) || (fromMarkdown && Object.keys(fromMarkdown).length) ? 'map-page' : provider === 'page' ? 'json-ld' : 'map-url',
      extraction_version: PLACE_EXTRACTION_VERSION,
    },
  });
};

export type MapboxStaticOptions = { token: string; zoom?: number; width?: number; height?: number; style?: string };

/** A Mapbox Static Images request: the light style with an ink pin at the place (attribution kept) */
export const mapboxStaticUrl = (geo: PlaceGeo, options: MapboxStaticOptions): string => {
  const { token, zoom = 15, width = 1200, height = 630, style = 'mapbox/light-v11' } = options;
  const lng = geo.longitude.toFixed(6);
  const lat = geo.latitude.toFixed(6);
  const size = `${Math.min(1280, Math.max(1, Math.round(width)))}x${Math.min(1280, Math.max(1, Math.round(height)))}@2x`;
  return `https://api.mapbox.com/styles/v1/${style}/static/pin-l+1a1a1a(${lng},${lat})/${lng},${lat},${zoom},0/${size}?access_token=${encodeURIComponent(token)}`;
};

/** A stored envelope, if it is one of ours */
export const readPlace = (value: unknown): PlaceAttributes | undefined => {
  const root = record(value);
  const provider = record(root?.provider);
  const evidence = record(root?.evidence);
  if (!root || root.version !== 1 || !provider || !evidence || evidence.extraction_version !== PLACE_EXTRACTION_VERSION) return undefined;
  if (!['apple-maps', 'google-maps', 'page', 'ocr'].includes(String(provider.kind))) return undefined;
  return root as unknown as PlaceAttributes;
};

// ---- addresses in a picture's own text (round 2) ----------------------------------------------

const STREET_WORDS = 'Street|St|Avenue|Ave|Road|Rd|Boulevard|Blvd|Drive|Dr|Lane|Ln|Way|Court|Ct|Place|Pl|Highway|Hwy|Parkway|Pkwy|Square|Sq|Terrace|Ter|Circle|Cir|Trail|Trl|Broadway|Alley|Route|Rte|Turnpike|Tpke';
// "55 Phila St", "1600 Pennsylvania Ave NW Suite 200", "5th Ave" — the number, the name (words,
// or an ordinal; never a bare number or a clock's "PM", which listing screenshots put right
// before the address: "Closes 6 PM 107 Charles St"), the street word, a unit
// The house number never starts with 0 and never follows another number (a phone's groups)
const STREET_LINE = new RegExp(`(?<!\\d[\\s.-])(?<![\\d:])\\b([1-9]\\d{0,5}[A-Za-z]?)\\s+((?:(?:[A-Z][A-Za-z.'’-]*|\\d{1,3}(?:st|nd|rd|th))\\s+){0,4}?(?:${STREET_WORDS})\\.?)(?:\\s+(?:N|S|E|W|NE|NW|SE|SW))?(?:,?\\s*(?:#|Suite|Ste\\.?|Apt\\.?|Unit|Fl\\.?|Floor)\\s*[\\w-]+)?`, 'g');
// "Saratoga Springs, NY 12866" / "Brooklyn, NY" / "Washington, DC 20500-0003"
const CITY_STATE = /([A-Z][A-Za-z.'’-]+(?:\s[A-Z][A-Za-z.'’-]+){0,3}),\s*([A-Z]{2})(?:\s+(\d{5}(?:-\d{4})?))?/;
// European order: "Classensgade 4, 2100 København" / "Rue de Rivoli 12, 75001 Paris" — the
// street is words (never digits, so a phone's groups cannot pose as one), then the number,
// the postcode and a capitalised town
const EURO_LINE = /\b([A-ZÆØÅÄÖÜ][a-zæøåäöüß.'’-]{2,40}(?:\s[A-Za-zæøåäöüß.'’-]{1,30}){0,3})\s+(\d{1,4}[A-Za-z]?),?\s+(\d{4,5})\s+([A-ZÆØÅÄÖÜ][\wæøåäöüß .'’-]{2,40})\b/g;

export type AddressCandidate = { text: string; line: number; complete: boolean };

/** Street addresses a picture's text seems to carry, best first; never more than three */
export const extractAddressCandidates = (text: string | null | undefined): AddressCandidate[] => {
  if (!text) return [];
  const lines = text.replace(/\r/g, '').split('\n').map((line) => line.replace(/\s+/g, ' ').trim());
  const found: AddressCandidate[] = [];
  const push = (candidate: AddressCandidate) => {
    const key = candidate.text.toLowerCase();
    if (!found.some((entry) => entry.text.toLowerCase() === key)) found.push(candidate);
  };
  lines.forEach((line, index) => {
    for (const match of line.matchAll(STREET_LINE)) {
      const street = match[0].trim();
      const after = line.slice((match.index ?? 0) + match[0].length);
      const sameLine = after.match(CITY_STATE);
      const nextLine = !sameLine && lines[index + 1] ? lines[index + 1].match(CITY_STATE) : null;
      const cityPart = sameLine ?? nextLine;
      const city = cityPart ? `${cityPart[1]}, ${cityPart[2]}${cityPart[3] ? ` ${cityPart[3]}` : ''}` : '';
      push({ text: city ? `${street}, ${city}` : street, line: index, complete: Boolean(city) });
    }
    for (const match of line.matchAll(EURO_LINE)) {
      push({ text: `${match[1]} ${match[2]}, ${match[3]} ${match[4]}`.trim(), line: index, complete: true });
    }
  });
  return found.sort((a, b) => Number(b.complete) - Number(a.complete) || a.line - b.line).slice(0, 3);
};

/** The first phone number written in the text, digits and a leading + only */
export const extractPhone = (text: string | null | undefined): string | undefined => {
  const match = text?.match(/(?:\+\d{1,2}[\s.-]?)?\(?\d{3}\)?[\s.-]?\d{3}[\s.-]?\d{4}\b/);
  if (!match) return undefined;
  const digits = match[0].replace(/[^+\d]/g, '');
  return digits.length >= 10 ? (digits.startsWith('+') ? digits : digits.length === 10 ? `+1${digits}` : `+${digits}`) : undefined;
};

/** The first web address written in the text */
export const extractWebsite = (text: string | null | undefined): string | undefined => {
  const match = text?.match(/\b(?:https?:\/\/)?(?:www\.)?([a-z0-9-]+(?:\.[a-z0-9-]+)*\.(?:com|net|org|co|io|us|uk|ca|de|fr|dk|nl|es|it|restaurant|cafe|bar|nyc|me|shop))\b(\/[^\s]*)?/i);
  if (!match) return undefined;
  const host = match[1].toLowerCase();
  if (/^(instagram|facebook|tiktok|twitter|x|youtube|yelp|google|apple|gmail|icloud)\./.test(host)) return undefined;
  return webAddress(`https://${host}${match[2] ?? ''}`);
};

export type Geocoded = {
  geo: PlaceGeo;
  full_address?: string;
  confidence?: string;
  feature_type?: string;
  context?: { street?: string; postcode?: string; locality?: string; region?: string; region_code?: string; country?: string; country_code?: string };
};

/** A Mapbox Geocoding v6 forward request for one address, exact matches only */
export const mapboxGeocodeUrl = (query: string, token: string): string =>
  `https://api.mapbox.com/search/geocode/v6/forward?q=${encodeURIComponent(query)}&limit=1&autocomplete=false&types=address&access_token=${encodeURIComponent(token)}`;

/** The one feature a geocode answer carries, when it is a confident address */
export const readGeocode = (payload: unknown): Geocoded | undefined => {
  const feature = record((record(payload)?.features as unknown[] | undefined)?.[0]);
  const geometry = record(feature?.geometry);
  const properties = record(feature?.properties);
  const coords = Array.isArray(geometry?.coordinates) ? geometry!.coordinates : [];
  const geo = typeof coords[1] === 'number' && typeof coords[0] === 'number' ? geoFrom(coords[1], coords[0]) : undefined;
  if (!geo || !properties) return undefined;
  const confidence = clean(record(properties.match_code)?.confidence, 20);
  const featureType = clean(properties.feature_type, 40);
  if (featureType !== 'address' || !confidence || !['exact', 'high'].includes(confidence)) return undefined;
  const context = record(properties.context) ?? {};
  const name = (key: string, field = 'name') => clean(record(context[key])?.[field], 120);
  return compact({
    geo,
    full_address: clean(properties.full_address, 300),
    confidence,
    feature_type: featureType,
    context: compact({
      street: name('street'), postcode: name('postcode'), locality: name('place'), region: name('region'), region_code: name('region', 'region_code'),
      country: name('country'), country_code: name('country', 'country_code'),
    }),
  });
};

export type OcrPlaceInput = {
  filePath: string;
  candidate: AddressCandidate;
  geocoded: Geocoded;
  phone?: string;
  website?: string;
  observedAt?: string;
};

/** The place a picture's text names, once its address is confirmed on the map */
export const buildOcrPlace = (input: OcrPlaceInput): PlaceAttributes => {
  const observed = input.observedAt ? new Date(input.observedAt) : new Date();
  const g = input.geocoded;
  const lines = [g.full_address ?? input.candidate.text];
  const point = `${g.geo.latitude},${g.geo.longitude}`;
  return compact({
    version: 1 as const,
    address: compact({
      lines,
      street: g.context?.street ? input.candidate.text.split(',')[0] : undefined,
      locality: g.context?.locality,
      region: g.context?.region,
      region_code: g.context?.region_code,
      postal_code: g.context?.postcode,
      country: g.context?.country,
      country_code: g.context?.country_code?.toUpperCase(),
    }),
    geo: g.geo,
    phone: input.phone,
    website: input.website,
    provider: { kind: 'ocr' as const, url: `https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(point)}` },
    evidence: {
      source_url: `stash-media:${input.filePath}`,
      observed_at: (Number.isFinite(observed.getTime()) ? observed : new Date()).toISOString(),
      method: 'ocr-geocode' as const,
      extraction_version: PLACE_EXTRACTION_VERSION,
    },
  });
};

/** The facts worth finding the save by */
export const placeSearchText = (place: PlaceAttributes): string => {
  const host = parseUrl(place.website)?.hostname.replace(/^www\./, '');
  const parts = [place.name, ...(place.address?.lines ?? []), place.address?.street, place.address?.locality, place.address?.region, place.category, place.phone, host];
  return [...new Set(parts.filter((part): part is string => typeof part === 'string' && !!part))].join(' · ').slice(0, 1000);
};
