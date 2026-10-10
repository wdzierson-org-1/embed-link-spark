import { describe, expect, it } from 'vitest';
import {
  buildPlace, extractAppleMarkdown, extractApplePlacePage, isProviderTitle, mapProviderOf, mapboxStaticUrl, parseAppleMapsUrl, parseGoogleMapsUrl, placeSearchText, readPlace,
} from './place.ts';

const resolvedApple = 'https://maps.apple.com/place?address=55%20Phila%20St,%20Saratoga%20Springs,%20NY%20%2012866,%20United%20States&coordinate=43.080499,-73.783109&name=Solevo%20Kitchen%20+%20Social&place-id=I6DF1454FE08462BE&map=explore';

// The shapes the Apple Maps place page embeds for its own UI (observed 2026-10-10), kept small
const applePage = `<html><body>
<a target="_blank" rel="nofollow" href="tel:+15184507094" class="sc-unified-action-row-item" role="button" id="axUnifiedActionRowItem-Call" aria-label="Call"><div class="sc-icon"></div><div class="sc-unified-action-row-title mw-dir-label">Call</div></a>
<a target="_blank" rel="nofollow" href="http://www.solevokitchenandsocial.com" class="sc-unified-action-row-item" role="button"><div class="sc-unified-action-row-title mw-dir-label">Website</div></a>
<a class="sc-unified-action-row-item" href="https://www.yelp.com/biz/solevo-kitchen-and-social-saratoga-springs-2?utm_campaign=action_link_view_menu_photos&amp;utm_source=apple#menu_photos" target="_blank" rel="nofollow"><div class="sc-icon"></div><div class="sc-unified-action-row-title mw-dir-label">Menu</div></a>
<script>window.__data = {"value":[{"entity":{"type":"BUSINESS","telephone":"+15184507094","url":"http://www.solevokitchenandsocial.com","name":[{"locale":"en-US","stringValue":"Solevo Kitchen + Social"}],"localizedCategory":[{"level":1,"localizedName":[{"locale":"en","stringValue":"Dining"}],"categoryId":"dining"},{"level":2,"localizedName":[{"locale":"en","stringValue":"Italian Cuisine"}],"categoryId":"italian"}]}}],
"ratings":[{"rating":{"ratingType":"USER_RATING","score":4.1,"maxScore":5,"numRatingsUsedForScore":295,"ratingsFormatted":"295"}},{"rating":{"ratingType":"PRICE_RANGE","score":3,"maxScore":4,"currencySymbol":"$"}}],
"hours":{"hoursType":"NORMAL","calendar":[{"days":["SUNDAY"],"daysIndex":[0],"timeRanges":[{"from":46800,"to":72000}],"hours":[[{"hours":13,"minutes":0},{"hours":20,"minutes":0}]]},{"days":["MONDAY","THURSDAY"],"daysIndex":[1,2,3,4],"timeRanges":[{"from":57600,"to":75600}]},{"days":["FRIDAY"],"daysIndex":[5],"timeRanges":[{"from":57600,"to":79200}]},{"days":["SATURDAY"],"daysIndex":[6],"timeRanges":[{"from":46800,"to":93600}]}]},
"addressObject":{"shortAddress":"55 Phila St, Saratoga Springs","formattedAddressLines":["55 Phila St","Saratoga Springs, NY  12866","United States"],"address":{"structuredAddress":{"country":"United States","countryCode":"US","administrativeArea":"New York","administrativeAreaCode":"NY","locality":"Saratoga Springs","postCode":"12866","thoroughfare":"Phila St","subThoroughfare":"55","fullThoroughfare":"55 Phila St"}}},
"placeInfo":{"center":{"lat":43.0804988,"lng":-73.7831086},"timezone":{"identifier":"America/New_York"}}};</script></body></html>`;

describe('mapProviderOf', () => {
  it('knows Apple Maps and Google Maps addresses, short links included', () => {
    expect(mapProviderOf('https://maps.apple/p/7mJUJoBjKam4Ns')).toBe('apple-maps');
    expect(mapProviderOf(resolvedApple)).toBe('apple-maps');
    expect(mapProviderOf('https://maps.app.goo.gl/abc123')).toBe('google-maps');
    expect(mapProviderOf('https://www.google.com/maps/place/Solevo/@43.08,-73.78,17z')).toBe('google-maps');
    expect(mapProviderOf('https://maps.google.com/?q=43.08,-73.78')).toBe('google-maps');
    expect(mapProviderOf('https://goo.gl/maps/xyz')).toBe('google-maps');
    expect(mapProviderOf('https://www.google.com/search?q=maps')).toBeNull();
    expect(mapProviderOf('https://www.yelp.com/biz/solevo')).toBeNull();
    expect(mapProviderOf('not a url')).toBeNull();
  });
});

describe('parseAppleMapsUrl', () => {
  it('reads the name, address, coordinates and place id from the resolved place URL', () => {
    expect(parseAppleMapsUrl(resolvedApple)).toEqual({
      name: 'Solevo Kitchen + Social',
      address: '55 Phila St, Saratoga Springs, NY 12866, United States',
      geo: { latitude: 43.080499, longitude: -73.783109 },
      placeId: 'I6DF1454FE08462BE',
    });
    expect(parseAppleMapsUrl('https://maps.apple.com/?q=Coffee&ll=40.7,-74.0')).toEqual({ name: 'Coffee', geo: { latitude: 40.7, longitude: -74 } });
    expect(parseAppleMapsUrl('https://maps.apple/p/7mJUJoBjKam4Ns')).toEqual({});
  });
});

describe('parseGoogleMapsUrl', () => {
  it('prefers the place point over the viewport, and reads directions destinations', () => {
    expect(parseGoogleMapsUrl('https://www.google.com/maps/place/Solevo+Kitchen+%2B+Social/@43.0812,-73.79,17z/data=!3m1!4b1!4m6!3m5!1s0x1:0x2!8m2!3d43.080499!4d-73.783109!16s')).toEqual({
      name: 'Solevo Kitchen + Social',
      geo: { latitude: 43.080499, longitude: -73.783109 },
    });
    expect(parseGoogleMapsUrl('https://www.google.com/maps/dir/55.7087302,12.5598047/Classensgade+4,+2100+K%C3%B8benhavn/@55.7031433,12.5535989,14z/am=t/data=!4m10!4m9!1m1!4e1!1m5!1m1!1s0x465253a47aa2c931:0x78c34f69926eae75!2m2!1d12.5803367!2d55.6963299!3e3?hl=en')).toEqual({
      address: 'Classensgade 4, 2100 København',
      geo: { latitude: 55.69633, longitude: 12.580337 },
    });
    expect(parseGoogleMapsUrl('https://www.google.com/maps/search/pizza/@40.7,-74.0,15z')).toEqual({ name: 'pizza', geo: { latitude: 40.7, longitude: -74 } });
    expect(parseGoogleMapsUrl('https://maps.google.com/?q=40.7128,-74.0060')).toEqual({ geo: { latitude: 40.7128, longitude: -74.006 } });
    expect(parseGoogleMapsUrl('https://maps.app.goo.gl/abc123')).toEqual({});
  });
});

describe('extractApplePlacePage', () => {
  it('reads hours, phone, website, menu, ratings, category, address and the centre', () => {
    const page = extractApplePlacePage(applePage);
    expect(page).toMatchObject({
      name: 'Solevo Kitchen + Social',
      geo: { latitude: 43.080499, longitude: -73.783109 },
      timezone: 'America/New_York',
      phone: '+15184507094',
      website: 'http://www.solevokitchenandsocial.com/',
      menu_url: 'https://www.yelp.com/biz/solevo-kitchen-and-social-saratoga-springs-2?utm_campaign=action_link_view_menu_photos&utm_source=apple#menu_photos',
      category: 'Italian Cuisine',
      rating: { score: 4.1, max: 5, count: 295, source: 'yelp' },
      price_range: { level: 3, max: 4 },
      address: { lines: ['55 Phila St', 'Saratoga Springs, NY 12866', 'United States'], street: '55 Phila St', locality: 'Saratoga Springs', region: 'New York', region_code: 'NY', postal_code: '12866', country: 'United States', country_code: 'US' },
    });
    expect(page.hours).toEqual([
      { days: [0], ranges: [{ open: '13:00', close: '20:00' }] },
      { days: [1, 2, 3, 4], ranges: [{ open: '16:00', close: '21:00' }] },
      { days: [5], ranges: [{ open: '16:00', close: '22:00' }] },
      { days: [6], ranges: [{ open: '13:00', close: '02:00', next_day: true }] },
    ]);
  });

  it('finds nothing in a page without the place structures', () => {
    expect(extractApplePlacePage('<html><body><h1>Apple Maps</h1></body></html>')).toEqual({});
  });
});

// The capture step's markdown of the same page (Firecrawl), trimmed to the lines that matter
const appleMarkdown = `A

# Apple Maps

# Solevo Kitchen + Social

Italian Cuisine · [Saratoga Springs, NY](https://maps.apple.com/place?auid=1513877882049639045&lsp=9902)

[Directions](https://maps.apple.com/directions?destination=Solevo%20Kitchen%20%2B%20Social&mode=driving) [Call](tel:+15184507094) [Website](http://www.solevokitchenandsocial.com/) [Menu](https://www.yelp.com/biz/solevo-kitchen-and-social-saratoga-springs-2?utm_campaign=action_link_view_menu_photos&utm_medium=feed_v2&utm_source=apple#menu_photos)

HOURS

Closed

YELP

(295)

4.1

ACCEPTS

COST

$$$$

[Yelp](https://maps.apple.com/place?address=55%20Phila%20St,%20Saratoga%20Springs,%20NY%20%2012866,%20United%20States&coordinate=43.080499,-73.783109&name=Solevo%20Kitchen%20+%20Social&place-id=I6DF1454FE08462BE&map=explore#)

## Ratings & Reviews
`;

describe('extractAppleMarkdown', () => {
  it('reads the place from the links and action row the capture kept', () => {
    const page = extractAppleMarkdown(appleMarkdown);
    expect(page).toMatchObject({
      name: 'Solevo Kitchen + Social',
      geo: { latitude: 43.080499, longitude: -73.783109 },
      address: { lines: ['55 Phila St, Saratoga Springs, NY 12866, United States'] },
      phone: '+15184507094',
      website: 'http://www.solevokitchenandsocial.com/',
      menu_url: 'https://www.yelp.com/biz/solevo-kitchen-and-social-saratoga-springs-2?utm_campaign=action_link_view_menu_photos&utm_medium=feed_v2&utm_source=apple#menu_photos',
      category: 'Italian Cuisine',
      rating: { score: 4.1, max: 5, count: 295, source: 'yelp' },
      urlFacts: { placeId: 'I6DF1454FE08462BE' },
    });
    expect(page).not.toHaveProperty('hours');
  });

  it('is the fallback when the page itself is out of reach, and yields to the page when both exist', () => {
    const fromMarkdown = buildPlace({ url: 'https://maps.apple/p/7mJUJoBjKam4Ns', markdown: appleMarkdown, observedAt: '2026-10-10T12:00:00Z' });
    expect(fromMarkdown).toMatchObject({ name: 'Solevo Kitchen + Social', geo: { latitude: 43.080499 }, phone: '+15184507094', provider: { kind: 'apple-maps', place_id: 'I6DF1454FE08462BE', url: expect.stringContaining('https://maps.apple.com/place?address=') }, evidence: { method: 'map-page' } });
    expect(fromMarkdown).not.toHaveProperty('hours');
    const both = buildPlace({ url: 'https://maps.apple/p/7mJUJoBjKam4Ns', resolvedUrl: resolvedApple, html: applePage, markdown: appleMarkdown });
    expect(both?.hours).toHaveLength(4);
    expect(both?.timezone).toBe('America/New_York');
    expect(both?.address?.street).toBe('55 Phila St');
  });
});

describe('buildPlace', () => {
  it('combines the short link, its resolved address and the page into one envelope', () => {
    const place = buildPlace({ url: 'https://maps.apple/p/7mJUJoBjKam4Ns', resolvedUrl: resolvedApple, html: applePage, observedAt: '2026-10-10T12:00:00.000Z' });
    expect(place).toMatchObject({
      version: 1,
      name: 'Solevo Kitchen + Social',
      geo: { latitude: 43.080499, longitude: -73.783109 },
      phone: '+15184507094',
      provider: { kind: 'apple-maps', place_id: 'I6DF1454FE08462BE', url: resolvedApple },
      evidence: { source_url: 'https://maps.apple/p/7mJUJoBjKam4Ns', observed_at: '2026-10-10T12:00:00.000Z', method: 'map-page', extraction_version: 'place-v1' },
    });
    expect(place?.hours).toHaveLength(4);
    expect(readPlace(place)).toEqual(place);
  });

  it('builds from a Google Maps URL alone when there is no page to read', () => {
    const place = buildPlace({ url: 'https://www.google.com/maps/place/Blue+Bottle/@37.78,-122.4,17z/data=!8m2!3d37.782!4d-122.406' });
    expect(place).toMatchObject({ name: 'Blue Bottle', geo: { latitude: 37.782, longitude: -122.406 }, provider: { kind: 'google-maps' }, evidence: { method: 'map-url' } });
    expect(place).not.toHaveProperty('hours');
  });

  it('builds from publisher facts for a listing page with coordinates', () => {
    const place = buildPlace({
      url: 'https://www.yelp.com/biz/solevo',
      objectFacts: { version: 1, beta: true, kind: 'place', name: 'Solevo Kitchen + Social', place: { address: { street_address: '55 Phila St', locality: 'Saratoga Springs', region: 'NY', postal_code: '12866', country: 'US' }, geo: { latitude: 43.0805, longitude: -73.7831 }, cuisine: ['Italian'], price_range: '$$$' },
        evidence: { source_url: 'https://www.yelp.com/biz/solevo', observed_at: '2026-10-10T12:00:00Z', method: 'json-ld', extraction_version: 'object-facts-v1', schema_type: 'Restaurant' } },
    });
    expect(place).toMatchObject({ name: 'Solevo Kitchen + Social', category: 'Italian', price_range: { level: 3, max: 4 }, address: { street: '55 Phila St', locality: 'Saratoga Springs' }, provider: { kind: 'page' }, evidence: { method: 'json-ld' } });
  });

  it('is nothing for an ordinary page', () => {
    expect(buildPlace({ url: 'https://example.com/article' })).toBeUndefined();
    expect(buildPlace({ url: 'https://maps.apple/p/7mJUJoBjKam4Ns' })).toBeUndefined();
  });
});

describe('helpers', () => {
  it('names the provider titles a save must not keep', () => {
    expect(isProviderTitle('Apple Maps')).toBe(true);
    expect(isProviderTitle('Google Maps')).toBe(true);
    expect(isProviderTitle('Apple Maps - Solevo')).toBe(true);
    expect(isProviderTitle('Solevo Kitchen + Social')).toBe(false);
  });

  it('builds the Mapbox request with an ink pin, retina size and attribution left on', () => {
    const url = mapboxStaticUrl({ latitude: 43.080499, longitude: -73.783109 }, { token: 'pk.test' });
    expect(url).toBe('https://api.mapbox.com/styles/v1/mapbox/light-v11/static/pin-l+1a1a1a(-73.783109,43.080499)/-73.783109,43.080499,15,0/1200x630@2x?access_token=pk.test');
    expect(mapboxStaticUrl({ latitude: 1, longitude: 2 }, { token: 't', width: 4000, height: 10 })).toContain('/1280x10@2x?');
  });

  it('makes search text from the place’s own facts', () => {
    const place = buildPlace({ url: 'https://maps.apple/p/x', resolvedUrl: resolvedApple, html: applePage })!;
    expect(placeSearchText(place)).toBe('Solevo Kitchen + Social · 55 Phila St · Saratoga Springs, NY 12866 · United States · Saratoga Springs · New York · Italian Cuisine · +15184507094 · solevokitchenandsocial.com');
  });
});
