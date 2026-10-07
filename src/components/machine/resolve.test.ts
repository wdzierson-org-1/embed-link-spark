import { GLYPHS } from './glyphs';
import {
  READING_BLOCK,
  RESOLVE_IN,
  boiledGlyphRows,
  boiledHeights,
  boiledWidth,
  fitImageRect,
  lensAt,
  planOnLoad,
} from './resolve';

describe('planOnLoad', () => {
  it('shows a settled picture as it is', () => {
    expect(planOnLoad({ reading: false, arriving: false })).toBeNull();
  });

  it('holds a picture Stash is reading at the reading block, with the lens', () => {
    expect(planOnLoad({ reading: true, arriving: false })).toEqual({ queue: [READING_BLOCK], hold: true });
  });

  it('resolves an arriving picture all the way in, coarse to sharp', () => {
    expect(planOnLoad({ reading: false, arriving: true })).toEqual({ queue: [...RESOLVE_IN], hold: false });
    expect(RESOLVE_IN.at(-1)).toBe(1);
  });

  it('resolves an arriving picture only as far as reading while Stash is still at work', () => {
    expect(planOnLoad({ reading: true, arriving: true })).toEqual({ queue: [26, 18, READING_BLOCK], hold: true });
  });
});

describe('lensAt', () => {
  const w = 400;
  const h = 230;

  it('stays on the picture and on the block grid', () => {
    for (let beat = 0; beat < 200; beat++) {
      const { x, y } = lensAt(beat, w, h);
      expect(x).toBeGreaterThanOrEqual(0);
      expect(x).toBeLessThanOrEqual(w);
      expect(y).toBeGreaterThan(0);
      expect(y).toBeLessThan(h);
      expect(x % READING_BLOCK).toBe(0);
      expect(y % READING_BLOCK).toBe(0);
    }
  });

  it('reads a row left to right, two blocks a beat, then drops to the next row', () => {
    const first = lensAt(0, w, h);
    const second = lensAt(1, w, h);
    expect(second.x - first.x).toBe(2 * READING_BLOCK);
    expect(second.y).toBe(first.y);
    let beat = 1;
    while (lensAt(beat, w, h).y === first.y) beat++;
    expect(lensAt(beat, w, h).y).toBeGreaterThan(first.y);
    expect(lensAt(beat, w, h).x).toBe(first.x);
  });
});

describe('fitImageRect', () => {
  const box = { w: 400, h: 200 };

  it('covers: fills the box, cropping by object-position', () => {
    const wide = { w: 1600, h: 400 }; // scaled to 800 × 200
    expect(fitImageRect('cover', '50% 50%', wide, box)).toEqual({ x: -200, y: 0, w: 800, h: 200 });
    expect(fitImageRect('cover', '0% 50%', wide, box).x).toBe(0);
    expect(fitImageRect('cover', '100% 50%', wide, box).x).toBe(-400);
  });

  it('contains: fits inside, centred', () => {
    const tall = { w: 300, h: 600 }; // scaled to 100 × 200
    expect(fitImageRect('contain', '50% 50%', tall, box)).toEqual({ x: 150, y: 0, w: 100, h: 200 });
  });

  it('reads keywords and pixel offsets', () => {
    const wide = { w: 1600, h: 400 };
    expect(fitImageRect('cover', 'right center', wide, box).x).toBe(-400);
    expect(fitImageRect('cover', '-120px 0px', wide, box).x).toBe(-120);
  });

  it('fills the box when the image has no size yet', () => {
    expect(fitImageRect('cover', '50% 50%', { w: 0, h: 0 }, box)).toEqual({ x: 0, y: 0, w: 400, h: 200 });
  });
});

describe('boiling', () => {
  it('a still glyph is the glyph exactly', () => {
    expect(boiledGlyphRows(GLYPHS.page, 0, 7)).toEqual([...GLYPHS.page]);
  });

  it('a boiling glyph differs from beat to beat, but the same beat boils the same way', () => {
    const a = boiledGlyphRows(GLYPHS.page, 1, 3);
    expect(a).not.toEqual([...GLYPHS.page]);
    expect(boiledGlyphRows(GLYPHS.page, 1, 3)).toEqual(a);
    expect(boiledGlyphRows(GLYPHS.page, 1, 4)).not.toEqual(a);
    expect(a.every((row) => row.length === 14)).toBe(true);
  });

  it('waveform bars and page lines settle to their own values at 0', () => {
    expect(boiledHeights([20, 60, 90], 0, 5)).toEqual([20, 60, 90]);
    expect(boiledHeights([20, 60, 90], 1, 5)).not.toEqual([20, 60, 90]);
    expect(boiledWidth(84, 2, 0, 5)).toBe(84);
    expect(boiledWidth(84, 2, 1, 5)).toBeLessThan(84);
  });
});
