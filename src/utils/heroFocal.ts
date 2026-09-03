/**
 * Subject-aware hero crops (ui-changes.md 2026-09-03).
 *
 * A card hero is a landscape window (h-40) over whatever image the source
 * gave us; `object-fit: cover` crops it around the centre. Product shots and
 * portrait images often keep their subject well off-centre on a flat
 * background (Farfetch: glasses in the bottom third of a white 3:4 image), so
 * the centre crop shows a blank band and the object vanishes from the card.
 *
 * This is the cheapest general fix that needs no model and no server work:
 * once the image has loaded, sample it into a ≤64px thumbnail on a canvas,
 * take the border ring's median colour as the background, find the bounding
 * box of everything that differs from it, and slide the crop window so that
 * box is centred. Photos without a flat background degrade gracefully — their
 * "subject" is the whole frame, so the focal point stays at the centre.
 *
 * iOS mirrors the same three steps (downsample → border-median background →
 * subject bounds) with CoreGraphics; the numbers below are the contract.
 */

export type Rgb = [number, number, number];

export interface SubjectAnalysis {
  /** Median colour of the outer pixel ring */
  background: Rgb;
  /** ≥80% of the ring is within BACKGROUND_TOLERANCE of that colour */
  flatBackground: boolean;
  /** Subject bounding box as fractions of width/height; null when nothing stands out */
  bounds: { x0: number; y0: number; x1: number; y1: number } | null;
  /** Point to centre the crop on, as fractions (0.5/0.5 = plain centre) */
  focal: { x: number; y: number };
}

/** Longest side of the analysis thumbnail; enough for a bounding box, cheap to read */
export const ANALYSIS_SIZE = 64;
/** Sum of |ΔR|+|ΔG|+|ΔB| under which a ring pixel still counts as background */
const BACKGROUND_TOLERANCE = 30;
/** Sum of |ΔR|+|ΔG|+|ΔB| over which a pixel counts as subject (JPEG noise stays below) */
const SUBJECT_THRESHOLD = 60;
const FLAT_RING_SHARE = 0.8;

const median = (values: number[]): number => {
  const sorted = [...values].sort((a, b) => a - b);
  return sorted[Math.floor(sorted.length / 2)] ?? 0;
};

/**
 * Analyse an RGBA buffer (as returned by `getImageData`). Works at any size;
 * callers downsample first so this stays a few thousand pixels.
 */
export const analyzeSubject = (data: Uint8ClampedArray, width: number, height: number): SubjectAnalysis => {
  const centre: SubjectAnalysis = { background: [0, 0, 0], flatBackground: false, bounds: null, focal: { x: 0.5, y: 0.5 } };
  if (width < 2 || height < 2 || data.length < width * height * 4) return centre;

  const at = (x: number, y: number): Rgb => {
    const i = (y * width + x) * 4;
    return [data[i], data[i + 1], data[i + 2]];
  };

  const ring: Rgb[] = [];
  for (let x = 0; x < width; x += 1) ring.push(at(x, 0), at(x, height - 1));
  for (let y = 1; y < height - 1; y += 1) ring.push(at(0, y), at(width - 1, y));
  const background: Rgb = [median(ring.map((p) => p[0])), median(ring.map((p) => p[1])), median(ring.map((p) => p[2]))];
  const distance = (p: Rgb) =>
    Math.abs(p[0] - background[0]) + Math.abs(p[1] - background[1]) + Math.abs(p[2] - background[2]);

  const flatShare = ring.filter((p) => distance(p) < BACKGROUND_TOLERANCE).length / ring.length;
  const flatBackground = flatShare >= FLAT_RING_SHARE;

  let x0 = width, y0 = height, x1 = -1, y1 = -1;
  for (let y = 0; y < height; y += 1) {
    for (let x = 0; x < width; x += 1) {
      if (distance(at(x, y)) > SUBJECT_THRESHOLD) {
        if (x < x0) x0 = x;
        if (x > x1) x1 = x;
        if (y < y0) y0 = y;
        if (y > y1) y1 = y;
      }
    }
  }
  if (x1 < 0) return { ...centre, background, flatBackground };

  const bounds = { x0: x0 / width, y0: y0 / height, x1: (x1 + 1) / width, y1: (y1 + 1) / height };
  return {
    background,
    flatBackground,
    bounds,
    focal: { x: (bounds.x0 + bounds.x1) / 2, y: (bounds.y0 + bounds.y1) / 2 },
  };
};

const clampPercent = (value: number) => Math.min(100, Math.max(0, value * 100));

/**
 * CSS `object-position` percentages that place `focal` at the centre of the
 * window `object-fit: cover` shows for an `imgW`×`imgH` image in a
 * `frameW`×`frameH` box. Only the cropped axis moves; the other stays at 50%.
 * Percent positioning aligns the image's p% line with the frame's p% line, so
 * for a window covering fraction `win` of the axis the top edge sits at
 * p·(1−win); solving p·(1−win) + win/2 = focal gives the value below.
 */
export const coverObjectPosition = (
  focal: { x: number; y: number },
  imgW: number,
  imgH: number,
  frameW: number,
  frameH: number
): { x: number; y: number } => {
  if (!(imgW > 0 && imgH > 0 && frameW > 0 && frameH > 0)) return { x: 50, y: 50 };
  const scale = Math.max(frameW / imgW, frameH / imgH);
  const winW = frameW / (imgW * scale);
  const winH = frameH / (imgH * scale);
  const solve = (f: number, win: number) => (win >= 0.999 ? 50 : clampPercent((f - win / 2) / (1 - win)));
  return { x: solve(focal.x, winW), y: solve(focal.y, winH) };
};

const cache = new Map<string, SubjectAnalysis | null>();

/**
 * Analyse a loaded `<img>`. Returns null (and caches the null) when the pixels
 * are unreadable — a cross-origin source without CORS headers taints the
 * canvas — so the caller keeps the default centre crop. Sources we serve
 * ourselves (storage bucket, image-proxy) send `Access-Control-Allow-Origin: *`,
 * so the element must be loaded with `crossOrigin="anonymous"` for this to work.
 */
export const analyzeImageElement = (img: HTMLImageElement): SubjectAnalysis | null => {
  const key = img.currentSrc || img.src;
  if (cache.has(key)) return cache.get(key) ?? null;
  let result: SubjectAnalysis | null = null;
  try {
    const { naturalWidth: w, naturalHeight: h } = img;
    if (w > 0 && h > 0) {
      const k = Math.max(w, h) / ANALYSIS_SIZE;
      const tw = Math.max(2, Math.round(w / k));
      const th = Math.max(2, Math.round(h / k));
      const canvas = document.createElement('canvas');
      canvas.width = tw;
      canvas.height = th;
      const ctx = canvas.getContext('2d', { willReadFrequently: true });
      if (ctx) {
        ctx.drawImage(img, 0, 0, tw, th);
        result = analyzeSubject(ctx.getImageData(0, 0, tw, th).data, tw, th);
      }
    }
  } catch {
    result = null;
  }
  cache.set(key, result);
  return result;
};
