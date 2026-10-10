import type { ObjectFacts } from '../../supabase/functions/_shared/objectFacts';

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
export type LocationSource = 'browser-geolocation' | 'device-geolocation' | 'photo-exif' | 'manual';

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

/**
 * What enrichment knows about how `page_body` was captured (written by the server through
 * `apply_enrichment_patch`'s evidence merge). `transcript: true` is the one flag every client
 * reads for "this page_body is a transcript" — set by `scrape-page-content` for YouTube
 * (Firecrawl, spec 2026-09-05) and by the maintenance loop's social adapter (Supadata).
 */
export type EnrichmentEvidence = {
  transcript?: boolean;
  transcript_source?: string;
  capture_kind?: string;
  duration_s?: number;
  author?: string;
  /** The social adapter's own marks (TikTok/Instagram captions, Supadata visual notes) */
  caption?: boolean;
  canonical_url?: string;
  visual?: boolean;
  visual_text?: string;
};

/**
 * Media subtype — written by enrichment when it can tell (DESIGN.md's
 * per-type hero rules key off this). Cards fall back to heuristics
 * (duration for audio, title prefix for screenshots) when absent.
 */
export type MediaKind = 'voice_note' | 'recording' | 'music' | 'screenshot' | 'video';

export type TranscriptStatus = 'pending' | 'processing' | 'done' | 'failed';

export type TranscriptError =
  | 'download_failed'
  | 'no_audio_track'
  | 'unsupported_container'
  | 'transcription_failed'
  | 'no_speech';

/**
 * Progress of the server-side transcription job for audio/video
 * (`transcribe-audio`, spec 2026-09-09). The transcript itself lives in
 * `page_body` and fills in chunk by chunk; this is only the status clients
 * render while it runs or when it fails.
 */
export type TranscriptState = {
  status: TranscriptStatus;
  /** e.g. "openai:gpt-4o-transcribe" once a chunk has succeeded */
  source?: string;
  chunks_total?: number;
  chunks_done?: number;
  attempts?: number;
  updated_at?: string;
  error?: TranscriptError;
};

export type MediaAttributes = {
  /** From chip-time local analysis (HTMLMediaElement metadata) */
  duration_s?: number;
  /** Original filename — titles are AI-derived; the filename is metadata */
  file_name?: string;
  kind?: MediaKind;
  transcript?: TranscriptState;
};

export type ItemAttributes = {
  /** Publisher structured facts, with source evidence; separate from the capture location. */
  object_facts?: ObjectFacts;
  enrichment?: { status: 'pending' | 'complete' | 'partial'; updated_at: string; evidence?: EnrichmentEvidence };
  location?: CapturedLocation;
  link?: LinkAttributes;
  media?: MediaAttributes;
};
