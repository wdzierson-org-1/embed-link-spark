import React from 'react';

/**
 * Shared pieces of the single-object card system. Anatomy on every card:
 * object zone → object's own title (serif) → user's annotation (violet bar) →
 * extracted-metadata chips → footer (date · location pin · type badge).
 */

/** The two hero heights in the system — nothing else */
export const HERO_STANDARD = 'h-40'; // 10rem — landscape imagery, plates
export const HERO_TALL = 'h-56'; // 14rem — portrait media, contained

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
