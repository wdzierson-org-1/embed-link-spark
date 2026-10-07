import React, { useEffect, useRef } from 'react';
import { cn } from '@/lib/utils';

/**
 * The surface the library sits on (DESIGN-v2 §7, "Paper with tooth"): the homepage hero's sheet,
 * quieter. A fine 4 px dot grid like a cutting mat (`.v2-mat`, a CSS tile), two stippled spheres
 * lit from the top right (ordered dither, as the homepage's js/liquid.js), and grain over the lot
 * (`.v2-grain`) so the paper isn't flat. Fixed to the viewport, so cards scroll over a still
 * surface, like objects on a desk. Ink only, so lime and violet share it; static, so reduced
 * motion has nothing to still. The parent needs `isolate` so this paints under its content.
 *
 * Cost: only the stipple is drawn, cell by cell inside the spheres' reach, once per viewport size;
 * the drawing is cached, so the library reuses what the loading screen drew, and a phone's
 * toolbar sliding (a small height change) doesn't redraw it.
 */

const BAYER4 = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5];
/** Extra height drawn below the viewport, so a phone toolbar sliding away reveals no seam */
const SLACK = 160;

const hash2 = (x: number, y: number): number => {
  let h = (x * 374761393 + y * 668265263) | 0;
  h = Math.imul(h ^ (h >>> 13), 1274126177);
  return ((h ^ (h >>> 16)) >>> 0) / 4294967296;
};

const clamp = (value: number, lo: number, hi: number) => Math.min(hi, Math.max(lo, value));
const smoothstep = (a: number, b: number, value: number) => {
  const k = clamp((value - a) / (b - a), 0, 1);
  return k * k * (3 - 2 * k);
};

interface Sphere {
  x: number;
  y: number;
  r: number;
}

/** Spheres that frame the page from its corners, mostly off-canvas, clear of the reading column */
export const backdropSpheres = (w: number, h: number): Sphere[] =>
  w < 700
    ? [{ x: w * 1.04, y: h * 0.06, r: w * 0.42 }, { x: -w * 0.06, y: h * 0.94, r: w * 0.38 }]
    : [
        { x: w + Math.min(120, w * 0.06), y: h * 0.1, r: Math.min(420, w * 0.27) },
        { x: -Math.min(90, w * 0.05), y: h * 0.9, r: Math.min(360, w * 0.23) },
      ];

/** The columns a row of cells must visit: where it crosses each sphere's reach (1.5 r), merged */
export const stippleSpans = (y: number, spheres: Sphere[], width: number): Array<[number, number]> => {
  const spans: Array<[number, number]> = [];
  for (const s of spheres) {
    const reach = 1.5 * s.r;
    const dy = y - s.y;
    if (Math.abs(dy) > reach) continue;
    const half = Math.sqrt(reach * reach - dy * dy);
    const from = Math.max(0, s.x - half);
    const to = Math.min(width, s.x + half);
    if (to > from) spans.push([from, to]);
  }
  spans.sort((a, b) => a[0] - b[0]);
  const merged: Array<[number, number]> = [];
  for (const span of spans) {
    const last = merged[merged.length - 1];
    if (last && span[0] <= last[1]) last[1] = Math.max(last[1], span[1]);
    else merged.push([...span] as [number, number]);
  }
  return merged;
};

// One drawing, shared: the loading screen draws it, the library mounts and copies it
let cache: { key: string; canvas: HTMLCanvasElement } | null = null;

const render = (w: number, h: number, dpr: number): HTMLCanvasElement => {
  const key = `${w}x${h}@${dpr}`;
  if (cache?.key === key) return cache.canvas;
  const out = document.createElement('canvas');
  const drawnH = h + SLACK;
  out.width = Math.round(w * dpr);
  out.height = Math.round(drawnH * dpr);
  const g = out.getContext('2d');
  if (!g) throw new Error('no 2d canvas');
  g.setTransform(dpr, 0, 0, dpr, 0, 0);

  // Stippled spheres: dense on the shadow side, thinning to dust past the rim
  const spheres = backdropSpheres(w, h);
  const cell = 3;
  g.fillStyle = 'rgba(0,0,0,0.16)';
  for (let y = 0; y < drawnH; y += cell) {
    const j = (y / cell) | 0;
    for (const [from, to] of stippleSpans(y, spheres, w)) {
      for (let x = Math.floor(from / cell) * cell; x < to; x += cell) {
        let density = 0;
        for (const s of spheres) {
          const dx = (x - s.x) / s.r;
          const dy = (y - s.y) / s.r;
          const r = Math.sqrt(dx * dx + dy * dy);
          if (r > 1.5) continue;
          const body = 1 - smoothstep(0.8, 1.0, r);
          const shade = clamp(0.45 - 0.55 * dx + 0.65 * dy, 0, 1);
          const dust = 0.06 * (1 - smoothstep(1.0, 1.5, r));
          density = Math.max(density, body * (0.06 + 0.94 * shade) + dust);
        }
        if (density < 0.02) continue;
        const i = (x / cell) | 0;
        const threshold = (BAYER4[(j & 3) * 4 + (i & 3)] + 0.5) / 16 + (hash2(i, j) - 0.5) * 0.3;
        if (density > threshold) g.fillRect(x, y, 1.5, 1.5);
      }
    }
  }
  cache = { key, canvas: out };
  return out;
};

const paint = (canvas: HTMLCanvasElement): { w: number; h: number } => {
  const w = window.innerWidth;
  const h = window.innerHeight;
  // Retina where it's cheap; a big display falls back to 1x rather than a 60 MB background
  const dpr = w * h * 4 > 8e6 ? 1 : Math.min(window.devicePixelRatio || 1, 2);
  const drawing = render(w, h, dpr);
  canvas.width = drawing.width;
  canvas.height = drawing.height;
  canvas.style.width = `${w}px`;
  canvas.style.height = `${h + SLACK}px`;
  const g = canvas.getContext('2d');
  g?.drawImage(drawing, 0, 0);
  return { w, h };
};

export const PaperBackdrop = ({ className }: { className?: string }) => {
  const canvasRef = useRef<HTMLCanvasElement>(null);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas || !canvas.getContext) return;
    let drawn: { w: number; h: number };
    try {
      drawn = paint(canvas);
    } catch {
      return; // no 2D canvas (tests, very old browsers): the paper keeps its dots and grain
    }
    let timer = 0;
    const onResize = () => {
      // A phone's toolbar sliding changes the height a little: the slack drawn below covers it
      if (window.innerWidth === drawn.w && Math.abs(window.innerHeight - drawn.h) <= SLACK) return;
      window.clearTimeout(timer);
      timer = window.setTimeout(() => {
        try {
          drawn = paint(canvas);
        } catch {
          /* keep the last drawing */
        }
      }, 150);
    };
    window.addEventListener('resize', onResize);
    return () => {
      window.removeEventListener('resize', onResize);
      window.clearTimeout(timer);
    };
  }, []);

  return (
    <div aria-hidden className={cn('v2-mat pointer-events-none fixed inset-0 -z-10 overflow-hidden', className)}>
      <canvas ref={canvasRef} className="absolute left-0 top-0" />
      <div className="v2-grain absolute inset-0" />
    </div>
  );
};
