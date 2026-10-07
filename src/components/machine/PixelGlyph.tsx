import React from 'react';
import { GLYPHS, GLYPH_PATHS, pathFor, type GlyphName } from './glyphs';
import { boiledGlyphRows } from './resolve';

export type { GlyphName } from './glyphs';

/**
 * A 14×14 machine glyph (see `glyphs.ts`), drawn crisp in currentColor. Pass `boil` (from
 * useBoil) while Stash reads the thing it stands for: its pixels drop out and flicker around it
 * until reading ends and it settles.
 */
export const PixelGlyph = ({
  name,
  className = 'h-14 w-14',
  boil,
}: {
  name: GlyphName;
  className?: string;
  boil?: { amount: number; beat: number };
}) => {
  const d =
    boil && boil.amount > 0
      ? pathFor(boiledGlyphRows(GLYPHS[name] ?? GLYPHS.page, boil.amount, boil.beat))
      : GLYPH_PATHS[name] ?? GLYPH_PATHS.page;
  return (
    <svg viewBox="0 0 14 14" shapeRendering="crispEdges" aria-hidden className={`fill-current ${className}`}>
      <path d={d} />
    </svg>
  );
};
