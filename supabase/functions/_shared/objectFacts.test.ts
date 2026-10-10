import { describe, expect, it } from 'vitest';
import { extractObjectFacts, readObjectFacts, objectFactsSearchText } from './objectFacts.ts';

const url = 'https://shop.example/jackets/alpine';
const observedAt = '2026-10-10T14:00:00.000Z';
const html = (nodes: unknown, head = '') => `${head}<script type="application/ld+json">${JSON.stringify(nodes)}</script>`;
const product = { '@type': 'Product', name: 'Alpine Jacket', url, sku: 'ALPINE', brand: { '@type': 'Brand', name: 'Mountain Goods' }, material: 'Wool', offers: { '@type': 'Offer', price: '748.00', priceCurrency: 'USD', availability: 'https://schema.org/InStock' } };
const facts = (nodes: unknown, source = url, head = '') => extractObjectFacts({ url: source, html: html(nodes, head), observedAt });

describe('source-bound typed object facts', () => {
  it('extracts product facts with observation evidence and preserves exact decimal price', () => {
    expect(facts(product)).toEqual({ version: 1, beta: true, kind: 'product', name: 'Alpine Jacket', product: { brand: 'Mountain Goods', sku: 'ALPINE', material: 'Wool', offer: { price: '748.00', currency: 'USD', availability: 'InStock' } }, evidence: { source_url: url, observed_at: observedAt, method: 'json-ld', extraction_version: 'object-facts-v1', schema_type: 'Product' } });
  });
  it('ignores recommendations and unsupported publisher fields', () => {
    const result = facts({ '@graph': [{ ...product, name: 'Recommended Coat', url: 'https://shop.example/coats/red', sku: 'WRONG' }, { ...product, aggregateRating: { ratingValue: 5 }, userTaste: 'luxury' }] });
    expect(result?.product?.sku).toBe('ALPINE');
    expect(JSON.stringify(result)).not.toMatch(/Recommended|WRONG|ratingValue|userTaste/);
  });
  it('chooses a selected variant over the canonical parent and a conflicting sibling', () => {
    const selected = `${url}?variant=navy-xl`;
    const result = facts({ '@graph': [{ '@type': 'ProductGroup', name: 'Alpine Jacket', url, hasVariant: [{ ...product, url: `${url}?variant=red-xl`, sku: 'RED', color: 'Red', size: 'XL', offers: { price: '500', priceCurrency: 'USD' } }, { ...product, url: selected, sku: 'NAVY-XL', color: 'Navy', size: 'XL' }] }] }, selected, `<link rel="canonical" href="${url}">`);
    expect(result?.product).toMatchObject({ sku: 'NAVY-XL', color: 'Navy', size: 'XL', selected_variant: { id: 'NAVY-XL', color: 'Navy', size: 'XL' }, offer: { price: '748.00' } });
  });
  it('does not assign a canonical offer to an unverified selected variant', () => {
    const result = facts(product, `${url}?variant=navy-xl`, `<link rel="canonical" href="${url}">`);
    expect(result?.product).toMatchObject({ sku: 'ALPINE', material: 'Wool' });
    expect(result?.product?.offer).toBeUndefined();
    expect(result?.product?.selected_variant).toBeUndefined();
  });
  it('does not substitute a different variant with the same title or local graph id', () => {
    expect(facts({ ...product, '@id': '#product', url: `${url}?variant=red-xl` }, `${url}?variant=navy-xl`, `<title>Alpine Jacket</title><link rel="canonical" href="${url}">`)).toBeUndefined();
  });
  it('rejects an explicitly canonical offer on an otherwise selected variant', () => {
    const selected = `${url}?variant=navy-xl`;
    expect(facts({ ...product, url: selected, offers: { url, price: '500', priceCurrency: 'USD' } }, selected, `<link rel="canonical" href="${url}">`)?.product?.offer).toBeUndefined();
  });
  it('ignores a conflicting offer and rejects ambiguous prices', () => {
    expect(facts({ ...product, offers: { url: 'https://shop.example/other', price: '10', priceCurrency: 'USD' } })?.product?.offer).toBeUndefined();
    expect(facts({ ...product, offers: [{ price: '10', priceCurrency: 'USD' }, { price: '20', priceCurrency: 'USD' }] })?.product?.offer).toBeUndefined();
  });
  it('does not present an aggregate low price as this product price', () => {
    expect(facts({ ...product, offers: { '@type': 'AggregateOffer', lowPrice: '10', highPrice: '100', priceCurrency: 'USD' } })?.product?.offer).toBeUndefined();
  });
  it('extracts only the page-associated business, including valid coordinates', () => {
    const restaurantUrl = 'https://dining.example/locations/west-village';
    const result = facts({ '@type': 'Restaurant', url: restaurantUrl, name: 'Village Cafe', address: { '@type': 'PostalAddress', streetAddress: '1 Main Street', addressLocality: 'New York', addressRegion: 'NY', postalCode: '10014', addressCountry: { '@type': 'Country', name: 'US' } }, geo: { '@type': 'GeoCoordinates', latitude: '40.735', longitude: -74.005 }, servesCuisine: ['Italian', 'Seafood'], priceRange: '$$' }, restaurantUrl);
    expect(result).toMatchObject({ kind: 'place', name: 'Village Cafe', place: { address: { street_address: '1 Main Street', locality: 'New York', region: 'NY', postal_code: '10014', country: 'US' }, geo: { latitude: 40.735, longitude: -74.005 }, cuisine: ['Italian', 'Seafood'], price_range: '$$' } });
  });
  it('rejects multiple unmatched businesses and a sole unrelated business', () => {
    expect(facts([{ '@type': 'Restaurant', name: 'A' }, { '@type': 'Restaurant', name: 'B' }])).toBeUndefined();
    expect(facts({ '@type': 'Restaurant', name: 'A', url: 'https://dining.example/unrelated' })).toBeUndefined();
  });
  it('resolves a page mainEntity reference without taking a recommendation', () => {
    expect(facts({ '@graph': [{ '@type': 'WebPage', url, mainEntity: { '@id': '#main' } }, { ...product, url: undefined, '@id': '#main' }, { ...product, url: undefined, '@id': '#related', sku: 'WRONG' }] })?.product?.sku).toBe('ALPINE');
  });
  it.each([[91, 0], [0, -181], ['', ''], [null, null], ['Infinity', 0], [true, 1]])('omits invalid geo %s,%s', (latitude, longitude) => {
    expect(facts({ '@type': 'Place', url, name: 'Place', geo: { latitude, longitude } })?.place?.geo).toBeUndefined();
  });
  it.each([['-5', 'USD'], ['12,00', 'EUR'], ['10000000000', 'USD'], ['12', '$'], [true, 'USD']])('omits invalid price/currency %s %s', (price, priceCurrency) => {
    expect(facts({ ...product, offers: { price, priceCurrency } })?.product?.offer).toBeUndefined();
  });
  it('rejects ambiguous same-page products and malformed/oversized inputs without throwing', () => {
    expect(facts([product, { ...product, sku: 'OTHER' }])).toBeUndefined();
    expect(extractObjectFacts({ url, html: '<script type="application/ld+json">not json</script>', observedAt })).toBeUndefined();
    expect(extractObjectFacts({ url: 'javascript:alert(1)', html: html(product), observedAt })).toBeUndefined();
    expect(extractObjectFacts({ url, html: ' '.repeat(1_500_001) + html(product), observedAt })).toBeUndefined();
  });
});

describe('stored object fact boundary', () => {
  it('reads a bounded source-matched envelope and discards unmodeled data', () => {
    const extracted = facts(product)!;
    expect(readObjectFacts({ ...extracted, extra: 'not part of the schema' }, url)).toEqual(extracted);
    expect(readObjectFacts(extracted, 'https://shop.example/unrelated')).toBeUndefined();
    expect(readObjectFacts({ ...extracted, version: 20 }, url)).toBeUndefined();
    expect(readObjectFacts({ ...extracted, evidence: { ...extracted.evidence, observed_at: 'invalid' } }, url)).toBeUndefined();
  });
  it('produces concise deterministic searchable facts without evidence internals', () => {
    const result = objectFactsSearchText(facts(product)!);
    expect(result).toContain('Mountain Goods');
    expect(result).toContain('748.00 USD');
    expect(result).not.toContain('2026-10-10');
    expect(result).not.toContain('json-ld');
  });
});
