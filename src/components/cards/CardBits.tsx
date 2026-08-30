import React from 'react';
import type { ItemAttributes } from '@/types/itemAttributes';

/**
 * Shared pieces of the single-object card system (DESIGN.md). Anatomy on
 * every card: hero → kicker → title (500) → description → annotation (violet
 * bar) → chips (type chip first, always visible) → footer (date · location
 * pin · overflow).
 */

/** The two hero heights in the system — nothing else */
export const HERO_STANDARD = 'h-40'; // 10rem — landscape imagery, plates
export const HERO_TALL = 'h-56'; // 14rem — portrait media, contained

/* ── type spectrum (DESIGN.md) — flat tints for fields, tint+text for chips ── */

export type SpectrumTint = 'voice' | 'audio' | 'doc' | 'shot' | 'social';

const FIELD_TINTS: Record<SpectrumTint, string> = {
  voice: 'rgba(84,88,178,0.12)',
  audio: 'rgba(126,74,158,0.11)',
  doc: 'rgba(205,90,105,0.11)',
  shot: 'rgba(52,132,201,0.11)',
  social: 'rgba(70,100,180,0.07)',
};

const CHIP_TINTS: Record<SpectrumTint, { background: string; color: string }> = {
  voice: { background: 'rgba(84,88,178,0.12)', color: '#45408c' },
  audio: { background: 'rgba(139,74,158,0.12)', color: '#7d3d84' },
  doc: { background: 'rgba(205,90,105,0.12)', color: '#a33d52' },
  shot: { background: 'rgba(52,132,201,0.12)', color: '#22689c' },
  social: { background: 'rgba(70,100,180,0.1)', color: '#3a4f8c' },
};

/** Subtle paper grain laid over spectrum fields — texture, not gradient */
const FIELD_GRAIN =
  "url(\"data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' width='120' height='120'><filter id='n'><feTurbulence type='fractalNoise' baseFrequency='.9' numOctaves='2'/><feColorMatrix values='0 0 0 0 1 0 0 0 0 1 0 0 0 0 1 0 0 0 .05 0'/></filter><rect width='120' height='120' filter='url(%23n)'/></svg>\")";

/**
 * Flat spectrum field for imageless media heroes: one quiet tint per type
 * plus grain and a bottom inset hairline. Saturation belongs to the accents
 * (play circle, waveform), never washed across the surface.
 */
export const SpectrumField = ({
  tint,
  className = '',
  children,
}: {
  tint: SpectrumTint;
  className?: string;
  children?: React.ReactNode;
}) => (
  <div
    className={`relative flex-none overflow-hidden rounded-t-2xl ${className}`}
    style={{ background: FIELD_TINTS[tint], boxShadow: 'inset 0 -1px 0 rgba(0,0,0,0.04)' }}
  >
    <div
      aria-hidden
      className="pointer-events-none absolute inset-0 opacity-[0.35] mix-blend-overlay"
      style={{ backgroundImage: FIELD_GRAIN }}
    />
    {children}
  </div>
);

/** Always-visible tinted type chip — the color IS the type */
export const TypeChip = ({
  tint,
  icon,
  children,
}: {
  tint: SpectrumTint;
  icon?: React.ReactNode;
  children: React.ReactNode;
}) => (
  <span
    className="inline-flex max-w-full items-center gap-1.5 truncate rounded-full px-2 py-0.5 text-[11px] font-medium"
    style={CHIP_TINTS[tint]}
  >
    {icon}
    <span className="truncate">{children}</span>
  </span>
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
      return '#a33d52';
  }
};

export const isSpreadsheetExt = (ext?: string | null): boolean =>
  ext === 'XLSX' || ext === 'XLS' || ext === 'CSV';

export const MetaChip = ({
  icon,
  mono,
  children,
}: {
  icon?: React.ReactNode;
  mono?: boolean;
  children: React.ReactNode;
}) => (
  <span
    className={`inline-flex max-w-full items-center gap-1 truncate rounded-full bg-black/[0.04] px-2 py-0.5 text-[11px] font-medium text-foreground/60 ${
      mono ? 'font-mono text-[10px]' : ''
    }`}
  >
    {icon}
    <span className="truncate">{children}</span>
  </span>
);

/** The user's words — always visually distinct from extracted text */
export const CardAnnotation = ({ children }: { children: React.ReactNode }) => (
  <p className="border-l-2 border-violet-300 pl-3 text-[13.5px] leading-snug text-foreground/75 line-clamp-2">
    {children}
  </p>
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
