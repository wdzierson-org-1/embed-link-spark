/**
 * Resolve (DESIGN-v2 §8): while Stash reads a save, its picture is unresolved, and when Stash is
 * done it resolves. A photo or cover holds at coarse pixel blocks while a lens of finer blocks
 * steps across it in rows, then sharpens 8 → 5 → 3 → 1. A drawn placeholder's glyph boils, a
 * voice note's waveform jitters, a document's lines flicker, and each settles. A picture that
 * lands while the person watches resolves in from 26 px blocks, as on the homepage's enrichment
 * card (js/enrich.js). These are the pure parts; usePixelImage and useBoil run them.
 */

/** Block sizes (CSS px) a picture steps through when it lands, coarse to sharp */
export const RESOLVE_IN = [26, 18, 12, 8, 5, 3, 1] as const;
/** The coarse block a picture holds while Stash reads it */
export const READING_BLOCK = 12;
/** From reading to sharp, once Stash is done */
export const RESOLVE_OUT = [8, 5, 3, 1] as const;
/** From sharp back to reading, if Stash starts on the save again */
export const UNRESOLVE = [3, 5, 8, READING_BLOCK] as const;

export interface PixelPlan {
  /** Block sizes still to step through, one per beat */
  queue: number[];
  /** Hold at the last block with the reading lens once the queue empties */
  hold: boolean;
}

/** What a picture does once it has loaded: null means it simply shows, sharp */
export const planOnLoad = ({ reading, arriving }: { reading: boolean; arriving: boolean }): PixelPlan | null => {
  if (arriving) return reading ? { queue: [26, 18, READING_BLOCK], hold: true } : { queue: [...RESOLVE_IN], hold: false };
  if (reading) return { queue: [READING_BLOCK], hold: true };
  return null;
};

export interface Point {
  x: number;
  y: number;
}

/**
 * The reading lens's centre at a beat: two blocks per beat along a row, three rows down the
 * picture, then round again, like an eye reading lines. Snapped to the block grid, so it moves
 * in whole blocks.
 */
export const lensAt = (beat: number, w: number, h: number, block: number = READING_BLOCK): Point => {
  const rows = [0.3, 0.52, 0.74];
  const left = w * 0.12;
  const right = w * 0.88;
  const stride = block * 2;
  const perRow = Math.max(1, Math.floor((right - left) / stride) + 1);
  const loop = perRow * rows.length;
  const i = ((beat % loop) + loop) % loop;
  const snap = (value: number) => Math.round(value / block) * block;
  return { x: snap(left + (i % perRow) * stride), y: snap(h * rows[Math.floor(i / perRow)]) };
};

export interface Rect {
  x: number;
  y: number;
  w: number;
  h: number;
}

const positionKeyword: Record<string, string> = { left: '0%', top: '0%', center: '50%', right: '100%', bottom: '100%' };

/** One object-position component as an offset into the free space (box minus drawn image) */
const positionOffset = (token: string | undefined, free: number): number => {
  const value = positionKeyword[token ?? ''] ?? token ?? '50%';
  // `+ 0` folds a -0 (0 % of a negative free space) into 0
  if (value.endsWith('%')) return (free * Number.parseFloat(value)) / 100 + 0;
  if (value.endsWith('px')) return Number.parseFloat(value) + 0;
  return free / 2 + 0;
};

/**
 * Where `object-fit` / `object-position` draw an image inside its box (box-relative CSS px), so a
 * canvas laid over the <img> paints exactly what the <img> would. Handles cover, contain and
 * fill, the fits the heroes use.
 */
export const fitImageRect = (fit: string, position: string, natural: { w: number; h: number }, box: { w: number; h: number }): Rect => {
  if (!natural.w || !natural.h) return { x: 0, y: 0, w: box.w, h: box.h };
  if (fit !== 'cover' && fit !== 'contain') return { x: 0, y: 0, w: box.w, h: box.h };
  const scale = fit === 'cover' ? Math.max(box.w / natural.w, box.h / natural.h) : Math.min(box.w / natural.w, box.h / natural.h);
  const w = natural.w * scale;
  const h = natural.h * scale;
  const [px, py] = position.trim().split(/\s+/);
  return { x: positionOffset(px, box.w - w), y: positionOffset(py ?? '50%', box.h - h), w, h };
};

/** 0..1, fixed for its inputs: the same beat always boils the same way */
export const noise3 = (a: number, b: number, c: number): number => {
  let h = (a * 374761393 + b * 668265263 + c * 1442695041 + 0x2545f491) | 0;
  h = Math.imul(h ^ (h >>> 13), 1274126177);
  return ((h ^ (h >>> 16)) >>> 0) / 4294967296;
};

/**
 * A 14×14 glyph mid-boil: at `amount` 1, about a third of its ink drops out and a halo of the
 * cells beside it flickers on, new every beat; at 0 it is the glyph exactly.
 */
export const boiledGlyphRows = (rows: readonly string[], amount: number, beat: number): string[] => {
  if (amount <= 0) return [...rows];
  const ink = (x: number, y: number) => rows[y]?.[x] === '#';
  return rows.map((row, y) =>
    Array.from(row, (cell, x) => {
      if (cell === '#') return noise3(x, y, beat) < 0.32 * amount ? '.' : '#';
      const nearInk = ink(x - 1, y) || ink(x + 1, y) || ink(x, y - 1) || ink(x, y + 1);
      return nearInk && noise3(x + 31, y + 17, beat) < 0.16 * amount ? '#' : '.';
    }).join(''),
  );
};

/** Waveform bars mid-boil: each height pulled toward a fresh random level by `amount` */
export const boiledHeights = (heights: readonly number[], amount: number, beat: number): number[] =>
  amount <= 0 ? [...heights] : heights.map((height, i) => height + (12 + noise3(i, beat, 3) * 88 - height) * amount);

/** A document line mid-boil: its width cut back by up to 70 % at `amount` 1 */
export const boiledWidth = (width: number, index: number, amount: number, beat: number): number =>
  amount <= 0 ? width : width * (1 - amount * 0.7 * noise3(index, beat, 9));
