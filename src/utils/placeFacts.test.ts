import { addressLines, directionsUrl, formatDays, formatPhone, formatRange, hoursRows, openInLabel, openLabel, openState, priceLabel, providerName, ratingLabel } from './placeFacts';
import type { PlaceAttributes, PlaceHours } from '../../supabase/functions/_shared/place';

const hours: PlaceHours = [
  { days: [0], ranges: [{ open: '13:00', close: '20:00' }] },
  { days: [1, 2, 3, 4], ranges: [{ open: '16:00', close: '21:00' }] },
  { days: [5], ranges: [{ open: '16:00', close: '22:00' }] },
  { days: [6], ranges: [{ open: '13:00', close: '02:00', next_day: true }] },
];

const place: PlaceAttributes = {
  version: 1, name: 'Solevo Kitchen + Social', geo: { latitude: 43.080499, longitude: -73.783109 }, timezone: 'America/New_York', hours,
  address: { lines: ['55 Phila St', 'Saratoga Springs, NY 12866', 'United States'] },
  provider: { kind: 'apple-maps', url: 'https://maps.apple.com/place?x' },
  evidence: { source_url: 'https://maps.apple/p/x', observed_at: '2026-10-10T12:00:00Z', method: 'map-page', extraction_version: 'place-v1' },
};

// Saratoga is UTC−4 in October: 18:30 UTC is 2:30 PM there
const atLocal = (iso: string) => new Date(iso);

describe('hours as people read them', () => {
  it('groups days and formats ranges', () => {
    expect(formatDays([1, 2, 3, 4])).toBe('Mon–Thu');
    expect(formatDays([6, 0])).toBe('Sat, Sun');
    expect(formatDays([5])).toBe('Fri');
    expect(formatRange({ open: '16:00', close: '21:00' })).toBe('4:00–9:00 PM');
    expect(formatRange({ open: '09:00', close: '17:00' })).toBe('9:00 AM–5:00 PM');
    expect(formatRange({ open: '13:00', close: '02:00', next_day: true })).toBe('1:00 PM–2:00 AM');
    expect(hoursRows(hours).map((row) => `${row.label} ${row.value}`)).toEqual(['Mon–Thu 4:00–9:00 PM', 'Fri 4:00–10:00 PM', 'Sat 1:00 PM–2:00 AM', 'Sun 1:00–8:00 PM']);
    expect(hoursRows(undefined)).toEqual([]);
  });

  it('says open or closed only in the place’s own zone', () => {
    // Friday 2026-10-16 18:30 UTC = 2:30 PM in New York: opens at 4
    expect(openState(hours, 'America/New_York', atLocal('2026-10-16T18:30:00Z'))).toEqual({ kind: 'closed', opens: { day: 5, at: '16:00', daysAhead: 0 } });
    // Friday 9 PM local: open until 10
    expect(openState(hours, 'America/New_York', atLocal('2026-10-17T01:00:00Z'))).toEqual({ kind: 'open', closes: '22:00' });
    // Sunday 1 AM local: still inside Saturday's late range
    expect(openState(hours, 'America/New_York', atLocal('2026-10-18T05:00:00Z'))).toEqual({ kind: 'open', closes: '02:00' });
    // Sunday 9 PM local: closed, opens Monday
    expect(openState(hours, 'America/New_York', atLocal('2026-10-19T01:00:00Z'))).toEqual({ kind: 'closed', opens: { day: 1, at: '16:00', daysAhead: 1 } });
    expect(openState(hours, undefined)).toBeNull();
    expect(openState(hours, 'Not/AZone')).toBeNull();
  });

  it('writes the machine line', () => {
    expect(openLabel({ kind: 'open', closes: '22:00' })).toBe('open · closes 10:00 PM');
    expect(openLabel({ kind: 'closed', opens: { day: 5, at: '16:00', daysAhead: 0 } })).toBe('closed · opens 4:00 PM');
    expect(openLabel({ kind: 'closed', opens: { day: 1, at: '16:00', daysAhead: 1 } })).toBe('closed · opens tomorrow 4:00 PM');
    expect(openLabel({ kind: 'closed', opens: { day: 1, at: '16:00', daysAhead: 3 } })).toBe('closed · opens Mon 4:00 PM');
    expect(openLabel({ kind: 'closed' })).toBe('closed');
  });
});

describe('addresses and labels', () => {
  it('keeps the provider’s lines, or builds them', () => {
    expect(addressLines(place)).toEqual(['55 Phila St', 'Saratoga Springs, NY 12866', 'United States']);
    expect(addressLines({ ...place, address: { street: '55 Phila St', locality: 'Saratoga Springs', region: 'New York', region_code: 'NY', postal_code: '12866', country: 'United States' } })).toEqual(['55 Phila St', 'Saratoga Springs, NY 12866', 'United States']);
    expect(addressLines({ ...place, address: undefined })).toEqual([]);
  });

  it('opens directions in the provider the save came from', () => {
    expect(directionsUrl(place)).toBe('https://maps.apple.com/?daddr=43.080499%2C-73.783109&q=Solevo%20Kitchen%20%2B%20Social');
    expect(directionsUrl({ ...place, provider: { kind: 'google-maps', url: 'x' } })).toBe('https://www.google.com/maps/dir/?api=1&destination=43.080499%2C-73.783109');
    expect(directionsUrl({ ...place, geo: undefined })).toBeUndefined();
  });

  it('names the source and the map a place opens in, for a picture-read place too', () => {
    expect(providerName(place)).toBe('Apple Maps');
    expect(openInLabel(place)).toBe('apple maps');
    const fromPicture = { ...place, provider: { kind: 'ocr' as const, url: 'https://www.google.com/maps/search/?api=1&query=1%2C2' } };
    expect(providerName(fromPicture)).toBe('the picture’s text');
    expect(openInLabel(fromPicture)).toBe('google maps');
    expect(directionsUrl(fromPicture)).toBe('https://www.google.com/maps/dir/?api=1&destination=43.080499%2C-73.783109');
    expect(providerName({ ...place, provider: { kind: 'page', url: 'https://www.yelp.com/biz/x' } })).toBe('yelp.com');
  });

  it('formats phones, ratings and prices', () => {
    expect(formatPhone('+15184507094')).toBe('(518) 450-7094');
    expect(formatPhone('+33 1 42 96 12 34')).toBe('+33 1 42 96 12 34');
    expect(ratingLabel({ score: 4.1, max: 5, count: 295, source: 'yelp' })).toBe('4.1 / 5 · 295 reviews · yelp');
    expect(priceLabel({ level: 3, max: 4 })).toBe('$$$');
  });
});
