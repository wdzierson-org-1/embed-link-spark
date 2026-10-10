// Reading a save's place (attributes.place, docs/ui-changes.md 2026-10-10 "Map-based shares")
// for the location section: hours as people read them, an honest open/closed line only when
// the provider gave the zone, and the addresses a cell opens.
import type { PlaceAttributes, PlaceHours, PlaceHoursRange } from '../../supabase/functions/_shared/place';

const DAY_SHORT = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

const minutesOf = (hhmm: string): number => {
  const [h, m] = hhmm.split(':').map(Number);
  return (Number.isFinite(h) ? h : 0) * 60 + (Number.isFinite(m) ? m : 0);
};

/** "16:00" → "4:00 PM"; the suffix can be left off when the range's other end carries it */
export const formatClock = (hhmm: string, withSuffix = true): string => {
  const total = minutesOf(hhmm);
  const h = Math.floor(total / 60) % 24;
  const m = total % 60;
  const hour = h % 12 === 0 ? 12 : h % 12;
  const suffix = h >= 12 ? 'PM' : 'AM';
  return `${hour}:${String(m).padStart(2, '0')}${withSuffix ? ` ${suffix}` : ''}`;
};

export const formatRange = (range: PlaceHoursRange): string => {
  const sameHalf = Math.floor(minutesOf(range.open) / 60) >= 12 === Math.floor(minutesOf(range.close) / 60) >= 12 && !range.next_day;
  return `${formatClock(range.open, !sameHalf)}–${formatClock(range.close)}`;
};

/** Days as a person reads them: "Mon–Thu", "Sat, Sun", "Mon" */
export const formatDays = (days: number[]): string => {
  const sorted = [...new Set(days)].filter((d) => d >= 0 && d <= 6).sort((a, b) => ((a + 6) % 7) - ((b + 6) % 7));
  if (!sorted.length) return '';
  const runs: number[][] = [];
  for (const day of sorted) {
    const run = runs[runs.length - 1];
    if (run && ((run[run.length - 1] + 1) % 7) === day) run.push(day);
    else runs.push([day]);
  }
  return runs.map((run) => (run.length >= 3 ? `${DAY_SHORT[run[0]]}–${DAY_SHORT[run[run.length - 1]]}` : run.map((d) => DAY_SHORT[d]).join(', '))).join(', ');
};

export interface HoursRow { label: string; value: string; days: number[] }

/** The week, Monday first, one row per group of days that share hours */
export const hoursRows = (hours: PlaceHours | undefined): HoursRow[] => {
  if (!hours?.length) return [];
  return hours
    .filter((entry) => entry.days.length)
    .map((entry) => ({ label: formatDays(entry.days), value: entry.ranges.length ? entry.ranges.map(formatRange).join(', ') : 'Closed', days: entry.days }))
    .sort((a, b) => ((Math.min(...a.days) + 6) % 7) - ((Math.min(...b.days) + 6) % 7));
};

/** The day (0 = Sunday) and the minute of the day where the place is, or null without a zone */
export const placeLocalNow = (timezone: string | undefined, now = new Date()): { day: number; minutes: number } | null => {
  if (!timezone) return null;
  try {
    const parts = new Intl.DateTimeFormat('en-US', { timeZone: timezone, weekday: 'short', hour: 'numeric', minute: 'numeric', hour12: false }).formatToParts(now);
    const weekday = parts.find((part) => part.type === 'weekday')?.value ?? '';
    const hour = Number(parts.find((part) => part.type === 'hour')?.value ?? NaN) % 24;
    const minute = Number(parts.find((part) => part.type === 'minute')?.value ?? NaN);
    const day = DAY_SHORT.indexOf(weekday);
    if (day < 0 || !Number.isFinite(hour) || !Number.isFinite(minute)) return null;
    return { day, minutes: hour * 60 + minute };
  } catch {
    return null;
  }
};

export type OpenState =
  | { kind: 'open'; closes: string }
  | { kind: 'closed'; opens?: { day: number; at: string; daysAhead: number } };

/** Whether the place is open at this moment in its own zone; null when that cannot be known */
export const openState = (hours: PlaceHours | undefined, timezone: string | undefined, now = new Date()): OpenState | null => {
  const local = placeLocalNow(timezone, now);
  if (!local || !hours?.length) return null;
  const rangesOn = (day: number): PlaceHoursRange[] => hours.filter((entry) => entry.days.includes(day)).flatMap((entry) => entry.ranges);
  const { day, minutes } = local;
  // Still inside a range that began yesterday and runs past midnight
  for (const range of rangesOn((day + 6) % 7)) {
    if (range.next_day && minutes < minutesOf(range.close)) return { kind: 'open', closes: range.close };
  }
  for (const range of rangesOn(day)) {
    const open = minutesOf(range.open);
    const close = range.next_day ? 24 * 60 + minutesOf(range.close) : minutesOf(range.close);
    if (minutes >= open && minutes < close) return { kind: 'open', closes: range.close };
  }
  for (let ahead = 0; ahead < 7; ahead++) {
    const candidate = (day + ahead) % 7;
    const next = rangesOn(candidate)
      .map((range) => minutesOf(range.open))
      .filter((open) => ahead > 0 || open > minutes)
      .sort((a, b) => a - b)[0];
    if (next !== undefined) {
      const at = `${String(Math.floor(next / 60)).padStart(2, '0')}:${String(next % 60).padStart(2, '0')}`;
      return { kind: 'closed', opens: { day: candidate, at, daysAhead: ahead } };
    }
  }
  return { kind: 'closed' };
};

/** The machine line: "open · closes 9:00 PM", "closed · opens Fri 4:00 PM" */
export const openLabel = (state: OpenState): string => {
  if (state.kind === 'open') return `open · closes ${formatClock(state.closes)}`;
  if (!state.opens) return 'closed';
  const when = state.opens.daysAhead === 0 ? '' : state.opens.daysAhead === 1 ? 'tomorrow ' : `${DAY_SHORT[state.opens.day]} `;
  return `closed · opens ${when}${formatClock(state.opens.at)}`;
};

/** Where the facts came from, for the footnote */
export const providerName = (place: PlaceAttributes): string =>
  place.provider.kind === 'apple-maps' ? 'Apple Maps'
    : place.provider.kind === 'google-maps' ? 'Google Maps'
      : place.provider.kind === 'ocr' ? 'the picture’s text'
        : hostOf(place.provider.url) ?? 'the page';

/** Where "open in …" leads: the provider's map, or Google Maps for a place read from a picture */
export const openInLabel = (place: PlaceAttributes): string =>
  place.provider.kind === 'apple-maps' ? 'apple maps'
    : place.provider.kind === 'google-maps' || place.provider.kind === 'ocr' ? 'google maps'
      : hostOf(place.provider.url) ?? 'the page';

export const hostOf = (url: string | undefined): string | undefined => {
  try {
    return url ? new URL(url).hostname.replace(/^www\./, '') : undefined;
  } catch {
    return undefined;
  }
};

/** The lines of the address as the provider wrote them, or built from its parts */
export const addressLines = (place: PlaceAttributes): string[] => {
  const address = place.address;
  if (!address) return [];
  if (address.lines?.length) return address.lines;
  const cityLine = [address.locality, [address.region_code ?? address.region, address.postal_code].filter(Boolean).join(' ')].filter(Boolean).join(', ');
  return [address.street, cityLine, address.country].filter((line): line is string => !!line);
};

/** Turn-by-turn in the provider the save came from (Apple Maps, else Google Maps) */
export const directionsUrl = (place: PlaceAttributes): string | undefined => {
  const geo = place.geo;
  if (!geo) return undefined;
  const point = `${geo.latitude},${geo.longitude}`;
  return place.provider.kind === 'apple-maps'
    ? `https://maps.apple.com/?daddr=${encodeURIComponent(point)}${place.name ? `&q=${encodeURIComponent(place.name)}` : ''}`
    : `https://www.google.com/maps/dir/?api=1&destination=${encodeURIComponent(point)}`;
};

export const telHref = (phone: string): string => `tel:${phone.replace(/[^+\d]/g, '')}`;

/** +15184507094 → (518) 450-7094; anything else as written */
export const formatPhone = (phone: string): string => {
  const us = phone.replace(/[^+\d]/g, '').match(/^\+?1(\d{3})(\d{3})(\d{4})$/);
  return us ? `(${us[1]}) ${us[2]}-${us[3]}` : phone;
};

export const ratingLabel = (rating: NonNullable<PlaceAttributes['rating']>): string =>
  [`${rating.score} / ${rating.max}`, rating.count !== undefined ? `${rating.count.toLocaleString()} reviews` : '', rating.source ?? '']
    .filter(Boolean)
    .join(' · ');

export const priceLabel = (price: NonNullable<PlaceAttributes['price_range']>): string => '$'.repeat(Math.max(1, Math.min(price.level, price.max)));
