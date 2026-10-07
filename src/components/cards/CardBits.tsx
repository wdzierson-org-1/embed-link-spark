import React from 'react';
import type { ItemAttributes } from '@/types/itemAttributes';

/**
 * Shared pieces of the single-object card system (DESIGN-v2 §6, "Object card"). Anatomy on
 * every card: media (or a placeholder) with its kind as a black tag → title (Montreal 500) →
 * description (muted) → the person's note (italic, ink bar) → meta row in Departure Mono
 * (source and one fact · date · reminder · place · overflow).
 */

/** The two hero heights in the system — nothing else */
export const HERO_STANDARD = 'h-40'; // 10rem — landscape imagery, plates
export const HERO_TALL = 'h-56'; // 14rem — portrait media, contained

/** The media's top edge inside a card's 1 px border and 2 px corners */
export const HERO_EDGE = 'rounded-t-[1px]';

/**
 * The field an imageless hero sits on: soft fill with the 6 px placeholder dots, a hairline
 * under it. v2 has no per-type tints: the kind is told by the tag and the glyph, not colour.
 */
export const MediaField = ({
  className = '',
  dots = true,
  children,
}: {
  className?: string;
  /** Placeholders get the dots; a player draws its own marks (the waveform) on plain fill */
  dots?: boolean;
  children?: React.ReactNode;
}) => (
  <div className={`${dots ? 'v2-dots-fine' : ''} relative flex-none overflow-hidden border-b border-line bg-fill ${HERO_EDGE} ${className}`}>
    {children}
  </div>
);

/* ── media subtype helpers ─────────────────────────────────────────────── */

/**
 * Voice note vs long recording: enrichment's attributes.media.kind wins;
 * without it, under ten minutes reads as a voice note.
 */
export const audioSubtype = (attributes?: ItemAttributes): 'voice_note' | 'recording' => {
  const kind = attributes?.media?.kind;
  if (kind === 'voice_note' || kind === 'recording') return kind;
  const duration = attributes?.media?.duration_s;
  return typeof duration === 'number' && duration >= 600 ? 'recording' : 'voice_note';
};

/** Screenshot subtype: enrichment's kind, or the vision title's own words */
export const isScreenshotItem = (item: { title?: string; attributes?: ItemAttributes }): boolean =>
  item.attributes?.media?.kind === 'screenshot' || Boolean(item.title?.startsWith('Screenshot of'));

/**
 * Deterministic waveform bar heights (percent, 24–100) from an item id —
 * stable identity per item until real amplitudes are sampled.
 */
export const waveformHeights = (seed: string, bars = 20): number[] => {
  let hash = 2166136261;
  for (let i = 0; i < seed.length; i++) {
    hash ^= seed.charCodeAt(i);
    hash = Math.imul(hash, 16777619);
  }
  const heights: number[] = [];
  for (let i = 0; i < bars; i++) {
    hash ^= hash << 13;
    hash ^= hash >>> 17;
    hash ^= hash << 5;
    heights.push(24 + (Math.abs(hash) % 77));
  }
  return heights;
};

/** Format-badge text color by document kind: pdf red, sheet green, deck orange, doc blue */
export const formatBadgeColor = (ext?: string | null): string => {
  switch (ext) {
    case 'XLSX':
    case 'XLS':
    case 'CSV':
      return '#1d6f42';
    case 'PPTX':
    case 'PPT':
      return '#c43e1c';
    case 'DOCX':
    case 'DOC':
      return '#2b579a';
    default:
      return '#7d3f9e';
  }
};

export const isSpreadsheetExt = (ext?: string | null): boolean =>
  ext === 'XLSX' || ext === 'XLS' || ext === 'CSV';

/** A fact in the machine voice: square, soft fill, Departure Mono (the admin member grid) */
export const MetaChip = ({
  icon,
  children,
}: {
  icon?: React.ReactNode;
  mono?: boolean;
  children: React.ReactNode;
}) => (
  <span className="inline-flex max-w-full items-center gap-1 truncate bg-fill px-1.5 pb-[3px] pt-1 font-pixel text-pixel leading-none text-muted-foreground">
    {icon}
    <span className="truncate">{children}</span>
  </span>
);

export const formatDurationChip = (seconds?: number | null): string | null => {
  if (typeof seconds !== 'number' || !Number.isFinite(seconds) || seconds <= 0) return null;
  const total = Math.round(seconds);
  const minutes = Math.floor(total / 60);
  const rest = total % 60;
  if (minutes >= 60) {
    const hours = Math.floor(minutes / 60);
    return `${hours}:${String(minutes % 60).padStart(2, '0')}:${String(rest).padStart(2, '0')}`;
  }
  return `${minutes}:${String(rest).padStart(2, '0')}`;
};

export const formatFileSizeChip = (bytes?: number | null): string | null => {
  if (typeof bytes !== 'number' || !Number.isFinite(bytes) || bytes <= 0) return null;
  const sizes = ['B', 'KB', 'MB', 'GB'];
  const index = Math.min(sizes.length - 1, Math.floor(Math.log(bytes) / Math.log(1024)));
  return `${(bytes / Math.pow(1024, index)).toFixed(index === 0 ? 0 : 1)} ${sizes[index]}`;
};

export const mimeExtensionLabel = (mimeType?: string | null): string | null => {
  if (!mimeType) return null;
  if (mimeType === 'audio/mp4') return 'M4A';
  const subtype = mimeType.split('/')[1];
  if (!subtype) return null;
  const cleaned = subtype.split('+')[0].split('.').pop() ?? subtype;
  const known: Record<string, string> = {
    jpeg: 'JPG',
    'svg+xml': 'SVG',
    quicktime: 'MOV',
    'x-m4a': 'M4A',
    mp4: 'MP4',
    mpeg: 'MP3',
    'vnd.openxmlformats-officedocument.presentationml.presentation': 'PPTX',
    'vnd.openxmlformats-officedocument.wordprocessingml.document': 'DOCX',
    'vnd.openxmlformats-officedocument.spreadsheetml.sheet': 'XLSX',
    'vnd.ms-powerpoint': 'PPT',
    'vnd.ms-excel': 'XLS',
    msword: 'DOC',
  };
  return known[subtype] ?? known[cleaned] ?? cleaned.toUpperCase().slice(0, 5);
};
