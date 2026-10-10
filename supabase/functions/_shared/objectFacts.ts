import { decodeHtmlEntities } from './textHygiene.ts';

export type ObjectFacts = {
  version: 1;
  beta: true;
  kind: 'product' | 'place';
  name?: string;
  product?: {
    brand?: string; sku?: string; mpn?: string; color?: string; size?: string; material?: string;
    selected_variant?: { id?: string; color?: string; size?: string };
    offer?: { price: string; currency: string; availability?: string };
  };
  place?: {
    address?: { street_address?: string; locality?: string; region?: string; postal_code?: string; country?: string };
    geo?: { latitude: number; longitude: number };
    cuisine?: string[];
    price_range?: string;
  };
  evidence: {
    source_url: string; observed_at: string; method: 'json-ld'; extraction_version: 'object-facts-v1';
    schema_type: string; node_id?: string;
  };
}

type Node = Record<string, unknown>;
const record = (v: unknown): Node | undefined => v && typeof v === 'object' && !Array.isArray(v) ? v as Node : undefined;
const list = (v: unknown): unknown[] => Array.isArray(v) ? v.slice(0, 40) : v == null ? [] : [v];
const text = (v: unknown, limit = 180): string | undefined => {
  if (typeof v !== 'string' || v.length > 2048) return;
  const s = decodeHtmlEntities(v).replace(/<[^>]*>/g, ' ').replace(/[\u0000-\u001f\u007f]/g, ' ').replace(/\s+/g, ' ').trim();
  return s && s.length <= limit ? s : undefined;
};
const scalar = (v: unknown): string | undefined => text(typeof v === 'number' && Number.isFinite(v) ? String(v) : v);
const name = (v: unknown) => text(record(v)?.name ?? v);
const types = (n: Node) => list(n['@type']).filter((v): v is string => typeof v === 'string').map(v => v.replace(/^https?:\/\/schema\.org\//, ''));
const productTypes = new Set(['Product', 'ProductGroup']);
const placeTypes = new Set(['Place', 'LocalBusiness', 'Restaurant', 'CafeOrCoffeeShop', 'BarOrPub', 'FoodEstablishment', 'Bakery', 'Brewery', 'Winery', 'Store', 'ClothingStore', 'JewelryStore', 'BookStore', 'GroceryStore', 'ShoppingCenter', 'Hotel', 'LodgingBusiness', 'Resort', 'Museum', 'Park', 'TouristAttraction', 'EventVenue', 'SportsActivityLocation', 'HealthAndBeautyBusiness', 'ProfessionalService']);
const tracking = /^(?:utm_[a-z0-9_]+|gclid|dclid|fbclid|msclkid|mc_cid|mc_eid)$/i;
const availabilityValues = new Set(['BackOrder', 'Discontinued', 'InStock', 'InStoreOnly', 'LimitedAvailability', 'MadeToOrder', 'OnlineOnly', 'OutOfStock', 'PreOrder', 'PreSale', 'Reserved', 'SoldOut']);
function compact<T extends object>(value: T): T {
  return Object.fromEntries(Object.entries(value).filter(([, v]) => v !== undefined)) as T;
}
function attr(tag: string, key: string): string | undefined {
  const match = tag.match(new RegExp(`\\b${key}\\s*=\\s*(?:"([^"]*)"|'([^']*)')`, 'i'));
  return match ? decodeHtmlEntities(match[1] ?? match[2]) : undefined;
}

/** Bounded, deterministic facts from this page's own structured object. No fetching or inference. */
export function extractObjectFacts(input: { url: string; html: string; observedAt?: string }): ObjectFacts | undefined {
  let source: URL;
  try { source = new URL(input.url); } catch { return; }
  if (!['https:', 'http:'].includes(source.protocol) || source.username || source.password || input.url.length > 4096) return;
  const absolute = (v: unknown): string | undefined => {
    if (typeof v !== 'string' || !v.trim() || v.length > 4096) return;
    try { const u = new URL(decodeHtmlEntities(v), source); return ['https:', 'http:'].includes(u.protocol) && !u.username && !u.password ? u.href : undefined; } catch { return; }
  };
  // As in pagePreview: retain variant, access and unknown query parameters.
  // Canonical identity may bind a base product, but never proves its variant price.
  const identity = (v: unknown): string | undefined => {
    const value = absolute(v); if (!value) return;
    const u = new URL(value); u.hash = '';
    for (const key of [...u.searchParams.keys()]) if (tracking.test(key)) u.searchParams.delete(key);
    u.searchParams.sort(); return u.href;
  };
  const original = identity(input.url)!;
  const sourceIdentity = new URL(original);
  const hasSelection = sourceIdentity.search.length > 0;
  const html = input.html.slice(0, 1_500_000);
  const pageIdentities = new Set([original]);
  for (const tag of (html.match(/<link\b[^>]*>/gi) || []).slice(0, 50)) {
    const canonical = identity(attr(tag, 'href'));
    if (attr(tag, 'rel')?.toLowerCase() === 'canonical' && canonical && new URL(canonical).origin === source.origin) pageIdentities.add(canonical);
  }
  const nodes: Node[] = [];
  const visit = (v: unknown, depth = 0) => {
    if (depth > 6 || nodes.length >= 160) return;
    if (Array.isArray(v)) { v.slice(0, 40).forEach(n => visit(n, depth + 1)); return; }
    const node = record(v); if (!node) return;
    nodes.push(node);
    for (const key of ['@graph', 'mainEntity', 'hasVariant']) visit(node[key], depth + 1);
  };
  let scripts = 0;
  for (const match of html.matchAll(/<script\b[^>]*type\s*=\s*["']application\/ld\+json["'][^>]*>([\s\S]*?)<\/script>/gi)) {
    if (++scripts > 32) break;
    if (match[1].length > 256_000) continue;
    try { visit(JSON.parse(match[1])); } catch { /* Invalid publisher metadata is optional. */ }
  }
  const mainEntities = new Set<unknown>();
  const mainIds = new Set<string>();
  for (const node of nodes) {
    if (!types(node).some(t => ['WebPage', 'ItemPage'].includes(t))) continue;
    if (![node.url, node['@id']].some(v => { const id = identity(v); return id && pageIdentities.has(id); })) continue;
    for (const main of list(node.mainEntity)) {
      mainEntities.add(main);
      const id = absolute(record(main)?.['@id'] ?? main); if (id) mainIds.add(id);
    }
  }
  const pageTitle = text(html.match(/<h1\b[^>]*>([\s\S]*?)<\/h1>/i)?.[1] ?? html.match(/<title\b[^>]*>([^<]*)<\/title>/i)?.[1]);
  const titleIdentity = (v: string) => v.toLowerCase().split(/\s[|—]\s/)[0].replace(/[^\p{L}\p{N}]+/gu, ' ').trim();
  const candidates = nodes.flatMap(node => {
    const schemaType = types(node).find(t => productTypes.has(t) || placeTypes.has(t)); if (!schemaType) return [];
    const urls = list(node.url).map(identity).filter((v): v is string => !!v);
    // An explicit different object or variant cannot be rescued by a graph id or matching name.
    if (urls.some(v => !pageIdentities.has(v))) return [];
    const exact = urls.includes(original);
    const bound = urls.some(v => pageIdentities.has(v));
    const main = mainEntities.has(node) || !!(absolute(node['@id']) && mainIds.has(absolute(node['@id'])!));
    const named = !urls.length && pageTitle && name(node.name) && titleIdentity(name(node.name)!) === titleIdentity(pageTitle);
    const score = exact ? 4 : main ? 3 : bound ? 2 : named ? 1 : 0;
    return score ? [{ node, schemaType, score, exact }] : [];
  });
  const highest = Math.max(0, ...candidates.map(c => c.score));
  const selected = candidates.filter(c => c.score === highest);
  if (selected.length !== 1) return;
  const { node, schemaType, exact } = selected[0];
  const observed = input.observedAt === undefined ? new Date() : new Date(input.observedAt);
  if (!Number.isFinite(observed.getTime())) return;
  const evidence: ObjectFacts['evidence'] = compact({ source_url: source.href, observed_at: observed.toISOString(), method: 'json-ld', extraction_version: 'object-facts-v1', schema_type: schemaType, node_id: absolute(node['@id']) });
  if (productTypes.has(schemaType)) {
    const variantVerified = hasSelection && exact && schemaType === 'Product';
    const product: NonNullable<ObjectFacts['product']> = compact({ brand: name(node.brand), sku: scalar(node.sku), mpn: scalar(node.mpn), material: text(node.material), color: !hasSelection || variantVerified ? text(node.color) : undefined, size: !hasSelection || variantVerified ? name(node.size) : undefined });
    if (variantVerified) {
      const variant = compact({ id: scalar(node.sku) ?? scalar(node.productID), color: product.color, size: product.size });
      if (Object.keys(variant).length) product.selected_variant = variant;
    }
    const offers = list(node.offers).flatMap(v => {
      const offer = record(v); if (!offer || types(offer).some(t => t !== 'Offer')) return [];
      const offerUrl = identity(offer.url);
      if (offerUrl && !pageIdentities.has(offerUrl)) return [];
      if (hasSelection && ((offerUrl && offerUrl !== original) || (!variantVerified && offerUrl !== original))) return [];
      const price = scalar(offer.price), currency = text(offer.priceCurrency);
      if (!price || !/^\d{1,9}(?:\.\d{1,6})?$/.test(price) || Number(price) > 1_000_000_000 || !currency || !/^[A-Z]{3}$/.test(currency)) return [];
      const rawAvailability = text(offer.availability)?.replace(/^https?:\/\/schema\.org\//, '');
      return [compact({ price, currency, availability: rawAvailability && availabilityValues.has(rawAvailability) ? rawAvailability : undefined })];
    });
    if (offers.length === 1) product.offer = offers[0];
    return compact<ObjectFacts>({ version: 1, beta: true, kind: 'product', name: name(node.name), product, evidence });
  }
  const place: NonNullable<ObjectFacts['place']> = {};
  const address = record(node.address);
  if (address) {
    const fields = compact({ street_address: text(address.streetAddress, 300), locality: text(address.addressLocality), region: text(address.addressRegion), postal_code: scalar(address.postalCode), country: name(address.addressCountry) });
    if (Object.keys(fields).length) place.address = fields;
  }
  const geo = record(node.geo);
  const coordinate = (v: unknown) => typeof v === 'number' || (typeof v === 'string' && /^-?\d{1,3}(?:\.\d+)?$/.test(v)) ? Number(v) : NaN;
  if (geo) {
    const latitude = coordinate(geo.latitude), longitude = coordinate(geo.longitude);
    if (Number.isFinite(latitude) && Math.abs(latitude) <= 90 && Number.isFinite(longitude) && Math.abs(longitude) <= 180) place.geo = { latitude, longitude };
  }
  const cuisine = [...new Set(list(node.servesCuisine).map(v => text(v, 80)).filter((v): v is string => !!v))].slice(0, 10);
  if (cuisine.length) place.cuisine = cuisine;
  const priceRange = text(node.priceRange, 80); if (priceRange) place.price_range = priceRange;
  return compact<ObjectFacts>({ version: 1, beta: true, kind: 'place', name: name(node.name), place, evidence });
}

/** Validate an additive API/stored envelope, binding it to the current item URL. */
export function readObjectFacts(value: unknown, sourceUrl: string): ObjectFacts | undefined {
  const root = record(value), evidence = record(root?.evidence);
  if (!root || root.version !== 1 || root.beta !== true || !evidence || evidence.method !== 'json-ld' || evidence.extraction_version !== 'object-facts-v1') return;
  let source: URL, expected: URL;
  try { source = new URL(String(evidence.source_url)); expected = new URL(sourceUrl); } catch { return; }
  if (!['https:', 'http:'].includes(source.protocol) || source.username || source.password || source.href.length > 4096) return;
  source.hash = ''; expected.hash = ''; source.searchParams.sort(); expected.searchParams.sort();
  if (source.href !== expected.href) return;
  if (typeof evidence.observed_at !== 'string' || evidence.observed_at.length > 40) return;
  const observed = new Date(evidence.observed_at);
  if (!Number.isFinite(observed.getTime())) return;
  const schemaType = text(evidence.schema_type);
  if (!schemaType || !(root.kind === 'product' ? productTypes : root.kind === 'place' ? placeTypes : new Set()).has(schemaType)) return;
  // Reuse the deterministic field bounds/allowlist. This is validation of an
  // existing envelope, not a claim that arbitrary caller facts were extracted.
  const node: Node = { '@type': schemaType, url: sourceUrl, name: text(root.name) };
  if (root.kind === 'product') {
    const p = record(root.product); if (!p) return;
    for (const k of ['brand', 'sku', 'mpn', 'color', 'size', 'material']) node[k] = text(p[k]);
    const offer = record(p.offer);
    if (offer) node.offers = { '@type': 'Offer', price: scalar(offer.price), priceCurrency: text(offer.currency), availability: text(offer.availability) };
  } else {
    const p = record(root.place); if (!p) return;
    const a = record(p.address);
    if (a) node.address = { streetAddress: text(a.street_address, 300), addressLocality: text(a.locality), addressRegion: text(a.region), postalCode: text(a.postal_code), addressCountry: text(a.country) };
    const geo = record(p.geo);
    if (geo) node.geo = { latitude: scalar(geo.latitude), longitude: scalar(geo.longitude) };
    node.servesCuisine = list(p.cuisine).map(v => text(v, 80)); node.priceRange = text(p.price_range, 80);
  }
  // Bound serialization before interpreting it. Only selected scalar fields
  // enter this node; nested field values must also remain small.
  let serialized: string;
  try { serialized = JSON.stringify(node); } catch { return; }
  if (serialized.length > 16_000) return;
  const sanitized = extractObjectFacts({ url: sourceUrl, html: `<script type="application/ld+json">${serialized.replace(/</g, '\\u003c')}</script>`, observedAt: observed.toISOString() });
  if (!sanitized) return;
  const nodeId = text(evidence.node_id, 4096);
  if (nodeId) {
    try { const id = new URL(nodeId); if (['https:', 'http:'].includes(id.protocol) && !id.username && !id.password) sanitized.evidence.node_id = id.href; } catch { /* Optional evidence id. */ }
  }
  if (sanitized.product) {
    const raw = record(record(root.product)?.selected_variant);
    // No variant selection may be manufactured by the validation adapter.
    delete sanitized.product.selected_variant;
    if (raw && source.search) {
      const variant = compact({ id: scalar(raw.id), color: text(raw.color), size: text(raw.size) });
      if (Object.keys(variant).length) sanitized.product.selected_variant = variant;
    }
  }
  return sanitized;
}

/** Useful source facts for later indexing; omit internal evidence and timestamps. */
export function objectFactsSearchText(value: ObjectFacts): string {
  const p = value.product, place = value.place;
  const parts = [value.name, p?.brand, p?.sku, p?.mpn, p?.color, p?.size, p?.material,
    p?.offer ? `${p.offer.price} ${p.offer.currency}` : undefined,
    ...Object.values(place?.address ?? {}), ...(place?.cuisine ?? []), place?.price_range];
  return [...new Set(parts.filter((part): part is string => typeof part === 'string' && !!part))].join(' · ').slice(0, 2000);
}
