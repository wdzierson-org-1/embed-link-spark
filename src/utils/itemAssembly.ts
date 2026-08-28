// Which enrichment pieces a fresh item is still waiting on, and which pieces
// just landed between two feed snapshots. Drives the assembling card state
// (dimmed pulsing card + "Gathering more info…" chip) and the piece-reveal
// animations as realtime delivers server-side enrichment.
//
// Honest by design (ETHOS: never fake enrichment): a piece is only "expected"
// when the pipeline reliably delivers it for that type, and the assembling
// state stops claiming work after ASSEMBLY_WINDOW_MS no matter what.
//
// Note: the feed query doesn't select page_body, so transcripts/OCR/scrapes
// are observed indirectly (description/summary land in the same updates).

import type { ItemAttributes } from '@/types/itemAttributes';
import { isPdfDocument } from '@/utils/documentProcessing';

export type AssemblyPiece = 'title' | 'description' | 'summary' | 'preview';

export interface AssemblySnapshot {
  id: string;
  type?: string;
  title?: string | null;
  description?: string | null;
  summary?: string | null;
  file_path?: string | null;
  mime_type?: string | null;
  created_at?: string | null;
  attributes?: ItemAttributes | null;
}

/** Enrichment cascades (vision, transcription, scrape rescue) can genuinely run this long. */
export const ASSEMBLY_WINDOW_MS = 2.5 * 60 * 1000;

/** How long a landed piece keeps its reveal animation class. */
export const REVEAL_TTL_MS = 6000;

const hasText = (value: unknown): boolean =>
  typeof value === 'string' && value.trim().length > 0;

// Mirrors the server-side guard in analyze-image: a title that is still a
// filename (or empty) is a placeholder the AI title will replace.
const IMAGE_FILENAME_RE = /\.(png|jpe?g|jfif|gif|webp|avif|svg|bmp|ico|tiff?|heic|heif)$/i;

export const isPlaceholderImageTitle = (
  title: string | null | undefined,
  filePath: string | null | undefined,
): boolean => {
  const t = (title ?? '').trim();
  if (!t) return true;
  if (filePath && t === (filePath.split('/').pop() ?? '')) return true;
  return IMAGE_FILENAME_RE.test(t);
};

export const itemAgeMs = (item: AssemblySnapshot, nowMs: number): number => {
  const created = item.created_at ? Date.parse(item.created_at) : NaN;
  return Number.isNaN(created) ? Number.POSITIVE_INFINITY : nowMs - created;
};

/** Pieces the pipeline still owes this item — empty when the card is complete. */
export const missingPieces = (item: AssemblySnapshot): AssemblyPiece[] => {
  switch (item.type) {
    case 'image': {
      const missing: AssemblyPiece[] = [];
      if (!hasText(item.description)) missing.push('description');
      if (isPlaceholderImageTitle(item.title, item.file_path)) missing.push('title');
      return missing;
    }
    case 'audio':
    case 'video':
      return hasText(item.description) ? [] : ['description'];
    case 'document':
      // Same contract as isDocumentProcessing: summary present = extraction done
      return isPdfDocument(item) && !hasText(item.summary) ? ['summary'] : [];
    default:
      // Links/notes enrich opportunistically (deep scrape may fail honestly);
      // reveals still fire for whatever lands, but we never promise it.
      return [];
  }
};

export const isAssembling = (item: AssemblySnapshot, nowMs: number): boolean =>
  itemAgeMs(item, nowMs) < ASSEMBLY_WINDOW_MS && missingPieces(item).length > 0;

/** Pieces that landed between two snapshots of the same item. */
export const landedPieces = (
  prev: AssemblySnapshot,
  next: AssemblySnapshot,
): AssemblyPiece[] => {
  const landed: AssemblyPiece[] = [];
  if (!hasText(prev.description) && hasText(next.description)) landed.push('description');
  if (!hasText(prev.summary) && hasText(next.summary)) landed.push('summary');
  // Any title change counts: filename → "Image of X", quick link title → real one
  if (hasText(next.title) && (prev.title ?? '') !== (next.title ?? '')) landed.push('title');
  // Links gain file_path when their preview image gets stored
  if (!hasText(prev.file_path) && hasText(next.file_path)) landed.push('preview');
  return landed;
};
