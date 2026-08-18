/**
 * Extensible per-item attribute blob, stored in items.attributes (jsonb).
 *
 * Attributes are structured facts *about* an item that aren't its content —
 * location today; anything later (weather, device, mood…) without another
 * migration. Keep leaf values JSON-scalar so the blob stays queryable with
 * plain jsonb operators (GIN-indexed) and embeddable for AI search.
 *
 * Type aliases (not interfaces) on purpose: aliases get implicit index
 * signatures, so these stay assignable to the generated Json insert types.
 */

/** How a location was collected — widen as collectors are added */
export type LocationSource = 'browser-geolocation' | 'photo-exif' | 'manual';

export type CapturedLocation = {
  /** Display string, e.g. "Saratoga Springs, New York" — always present */
  label: string;
  /** Coordinates for map views; absent for sources that only know a place name */
  latitude?: number;
  longitude?: number;
  /** GPS accuracy radius in meters, when the source reports one */
  accuracy_m?: number;
  city?: string;
  region?: string;
  country?: string;
  source: LocationSource;
  /** ISO timestamp of when the fix was taken (not when the item was saved) */
  captured_at?: string;
};

/**
 * What kind of thing a link points at — classified once at save (URL rules
 * today; enrichment can refine later). Cards pick their renderer by flavor.
 */
export type LinkFlavor = 'article' | 'video' | 'repo' | 'book' | 'social' | 'generic';

export type LinkAttributes = {
  flavor: LinkFlavor;
  /** Filled by future enrichment passes (oEmbed, source APIs) */
  author?: string;
  duration_s?: number;
  stars?: number;
  read_time_min?: number;
};

export type MediaAttributes = {
  /** From chip-time local analysis (HTMLMediaElement metadata) */
  duration_s?: number;
  /** Original filename — titles are AI-derived; the filename is metadata */
  file_name?: string;
};

export type ItemAttributes = {
  location?: CapturedLocation;
  link?: LinkAttributes;
  media?: MediaAttributes;
};
