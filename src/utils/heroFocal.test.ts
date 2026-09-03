import { describe, expect, it } from 'vitest';
import { analyzeSubject, coverObjectPosition } from './heroFocal';

/** Build an RGBA buffer of `w`×`h` filled with `bg`, then paint `rects` in `fg` */
const paint = (
  w: number,
  h: number,
  bg: [number, number, number],
  rects: Array<{ x0: number; y0: number; x1: number; y1: number }>,
  fg: [number, number, number] = [40, 30, 20]
): Uint8ClampedArray => {
  const data = new Uint8ClampedArray(w * h * 4);
  for (let y = 0; y < h; y += 1) {
    for (let x = 0; x < w; x += 1) {
      const inside = rects.some((r) => x >= r.x0 && x < r.x1 && y >= r.y0 && y < r.y1);
      const [r, g, b] = inside ? fg : bg;
      const i = (y * w + x) * 4;
      data[i] = r; data[i + 1] = g; data[i + 2] = b; data[i + 3] = 255;
    }
  }
  return data;
};

describe('analyzeSubject', () => {
  it('finds a product sitting low on a flat white background (the Farfetch glasses case)', () => {
    // 48×64 portrait, subject spans x 5..43, y 42..56
    const data = paint(48, 64, [255, 255, 255], [{ x0: 5, y0: 42, x1: 43, y1: 56 }]);
    const a = analyzeSubject(data, 48, 64);
    expect(a.flatBackground).toBe(true);
    expect(a.background).toEqual([255, 255, 255]);
    expect(a.bounds).toEqual({ x0: 5 / 48, y0: 42 / 64, x1: 43 / 48, y1: 56 / 64 });
    expect(a.focal.x).toBeCloseTo(24 / 48, 5);
    expect(a.focal.y).toBeCloseTo(49 / 64, 5);
  });

  it('reports the centre and no bounds when the image is one flat colour', () => {
    const a = analyzeSubject(paint(20, 10, [200, 200, 200], []), 20, 10);
    expect(a.flatBackground).toBe(true);
    expect(a.bounds).toBeNull();
    expect(a.focal).toEqual({ x: 0.5, y: 0.5 });
  });

  it('treats a busy photo as not flat and keeps the focal point near the centre', () => {
    const w = 32, h = 32;
    const data = new Uint8ClampedArray(w * h * 4);
    let seed = 7;
    for (let i = 0; i < data.length; i += 4) {
      seed = (seed * 1103515245 + 12345) & 0x7fffffff;
      data[i] = seed & 255; data[i + 1] = (seed >> 8) & 255; data[i + 2] = (seed >> 16) & 255; data[i + 3] = 255;
    }
    const a = analyzeSubject(data, w, h);
    expect(a.flatBackground).toBe(false);
    expect(a.focal.x).toBeGreaterThan(0.4);
    expect(a.focal.x).toBeLessThan(0.6);
    expect(a.focal.y).toBeGreaterThan(0.4);
    expect(a.focal.y).toBeLessThan(0.6);
  });

  it('ignores faint noise close to the background colour', () => {
    const data = paint(30, 30, [250, 250, 250], [{ x0: 20, y0: 20, x1: 28, y1: 28 }]);
    // sprinkle near-white specks that must not count as subject
    for (const [x, y] of [[1, 1], [2, 28], [28, 1]]) {
      const i = (y * 30 + x) * 4;
      data[i] = 240; data[i + 1] = 240; data[i + 2] = 240;
    }
    const a = analyzeSubject(data, 30, 30);
    expect(a.bounds).toEqual({ x0: 20 / 30, y0: 20 / 30, x1: 28 / 30, y1: 28 / 30 });
  });
});

describe('coverObjectPosition', () => {
  it('returns the CSS percentages that put the focal point at the centre of the cropped window', () => {
    // Portrait 1000×1334 into a 360×160 frame: width fits, height is cropped
    const pos = coverObjectPosition({ x: 0.51, y: 0.77 }, 1000, 1334, 360, 160);
    expect(pos.x).toBe(50); // width is not cropped, so x is irrelevant → centre
    // window height fraction ≈ 0.333; p = (0.77 - 0.1667) / (1 - 0.333) ≈ 0.905
    expect(pos.y).toBeCloseTo(90.5, 0);
  });

  it('clamps to the image edges', () => {
    expect(coverObjectPosition({ x: 0.5, y: 0.98 }, 1000, 1334, 360, 160).y).toBe(100);
    expect(coverObjectPosition({ x: 0.5, y: 0.02 }, 1000, 1334, 360, 160).y).toBe(0);
  });

  it('handles the other axis for panoramas', () => {
    // 3000×500 into 360×160: height fits, width is cropped; subject far right
    const pos = coverObjectPosition({ x: 0.9, y: 0.5 }, 3000, 500, 360, 160);
    expect(pos.y).toBe(50);
    expect(pos.x).toBeGreaterThan(90);
  });

  it('is a plain centre when the aspect ratios match or inputs are degenerate', () => {
    expect(coverObjectPosition({ x: 0.2, y: 0.9 }, 360, 160, 360, 160)).toEqual({ x: 50, y: 50 });
    expect(coverObjectPosition({ x: 0.2, y: 0.9 }, 0, 0, 360, 160)).toEqual({ x: 50, y: 50 });
  });
});
