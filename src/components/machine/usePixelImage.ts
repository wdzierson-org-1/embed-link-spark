import { useCallback, useEffect, useLayoutEffect, useRef, useState } from 'react';
import { useReducedMotion } from './motion';
import { READING_BLOCK, RESOLVE_OUT, UNRESOLVE, fitImageRect, lensAt, planOnLoad, type PixelPlan, type Point } from './resolve';
import { subscribeStep } from './stepTicker';

/**
 * The picture half of Resolve (resolve.ts): a canvas laid over a hero <img> while the picture is
 * unresolved. Reading, it holds at 12 px blocks while a square lens of finer blocks steps across
 * it in rows; once Stash is done it sharpens 8 → 5 → 3 → 1 and the canvas goes, leaving the real
 * <img>. A picture that lands while the person watches resolves in from 26 px blocks. Draws on
 * the shared beat, only while on screen; never starts under reduced motion. The frame must be the
 * <img>'s positioned offset parent; the canvas draws the image where object-fit puts it. Call
 * `onLoad` from the <img> that will stay (React fires it for cache hits too).
 */

/** Nested squares around the lens centre: half-size as a fraction of the lens, and their block */
const lensRings = (block: number): Array<[number, number]> => [
  [1, Math.max(2, Math.round(block / 2))],
  [0.62, Math.max(2, Math.round(block / 4))],
  [0.34, 1],
];

const createPainter = (canvas: HTMLCanvasElement, frame: HTMLElement, img: HTMLImageElement) => {
  const ctx = canvas.getContext('2d');
  const small = document.createElement('canvas');
  const sctx = small.getContext('2d');
  if (!ctx || !sctx) throw new Error('no 2d canvas');
  let width = 0;
  let height = 0;
  let dpr = 1;

  const level = (block: number, box: { x: number; y: number; w: number; h: number }, image: { x: number; y: number; w: number; h: number }) => {
    if (block <= 1) {
      ctx.save();
      ctx.beginPath();
      ctx.rect(box.x * dpr, box.y * dpr, box.w * dpr, box.h * dpr);
      ctx.clip();
      ctx.imageSmoothingEnabled = true;
      ctx.imageSmoothingQuality = 'high';
      ctx.drawImage(img, image.x * dpr, image.y * dpr, image.w * dpr, image.h * dpr);
      ctx.restore();
      return;
    }
    const cols = Math.max(1, Math.ceil(width / block));
    const rows = Math.max(1, Math.ceil(height / block));
    if (small.width !== cols || small.height !== rows) {
      small.width = cols;
      small.height = rows;
    } else {
      sctx.clearRect(0, 0, cols, rows);
    }
    sctx.save();
    sctx.beginPath();
    sctx.rect(box.x / block, box.y / block, box.w / block, box.h / block);
    sctx.clip();
    sctx.imageSmoothingEnabled = true;
    sctx.imageSmoothingQuality = 'high';
    sctx.drawImage(img, image.x / block, image.y / block, image.w / block, image.h / block);
    sctx.restore();
    ctx.imageSmoothingEnabled = false;
    ctx.drawImage(small, 0, 0, cols, rows, 0, 0, cols * block * dpr, rows * block * dpr);
  };

  return (block: number, lens: Point | null) => {
    width = frame.clientWidth;
    height = frame.clientHeight;
    dpr = Math.min(window.devicePixelRatio || 1, 2);
    const cw = Math.max(1, Math.round(width * dpr));
    const ch = Math.max(1, Math.round(height * dpr));
    if (canvas.width !== cw || canvas.height !== ch) {
      canvas.width = cw;
      canvas.height = ch;
    }
    // Layout boxes (offset*), not screen boxes, so a card mid-transform still lines up
    const box = { x: img.offsetLeft, y: img.offsetTop, w: img.offsetWidth, h: img.offsetHeight };
    const style = getComputedStyle(img);
    const fit = fitImageRect(style.objectFit, style.objectPosition, { w: img.naturalWidth, h: img.naturalHeight }, box);
    const image = { x: box.x + fit.x, y: box.y + fit.y, w: fit.w, h: fit.h };

    ctx.clearRect(0, 0, canvas.width, canvas.height);
    level(block, box, image);
    if (!lens || block <= 1) return;
    const half = Math.min(width, height) * 0.3;
    for (const [k, ringBlock] of lensRings(block)) {
      const r = Math.round((half * k) / block) * block;
      ctx.save();
      ctx.beginPath();
      ctx.rect((lens.x - r) * dpr, (lens.y - r) * dpr, 2 * r * dpr, 2 * r * dpr);
      ctx.clip();
      level(ringBlock, box, image);
      ctx.restore();
    }
  };
};

export function usePixelImage({
  frameRef,
  imgRef,
  reading,
  arriving,
}: {
  frameRef: React.RefObject<HTMLElement>;
  imgRef: React.RefObject<HTMLImageElement>;
  reading: boolean;
  arriving: boolean;
}) {
  // Live: switched on mid-effect, the picture shows sharp at once (below); before, it never starts
  const reduced = useReducedMotion();
  // Until the picture has loaded, the frame shows the mosaic (a picture not yet arrived)
  const [hasLoaded, setHasLoaded] = useState(false);
  // While active the canvas is mounted over the <img>, which hides; inactive, only the <img>
  const [active, setActive] = useState(false);
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const plan = useRef<PixelPlan & { block: number; beat: number }>({ queue: [], hold: false, block: 1, beat: 0 });
  const loaded = useRef(false);
  const readingRef = useRef(reading);
  const arrivingRef = useRef(arriving);
  arrivingRef.current = arriving;

  const begin = useCallback((next: PixelPlan) => {
    plan.current = { ...plan.current, queue: [...next.queue], hold: next.hold };
    setActive(true);
  }, []);

  const onLoad = useCallback(() => {
    if (loaded.current) return;
    loaded.current = true;
    setHasLoaded(true);
    if (reduced) return;
    const next = planOnLoad({ reading: readingRef.current, arriving: arrivingRef.current });
    if (next) begin(next);
  }, [begin, reduced]);

  // Stash starting or finishing: back to the lens, or on to sharp
  useEffect(() => {
    const was = readingRef.current;
    readingRef.current = reading;
    if (reduced || !loaded.current || was === reading) return;
    if (reading) {
      begin(active ? { queue: [READING_BLOCK], hold: true } : { queue: [...UNRESOLVE], hold: true });
    } else {
      plan.current.queue = RESOLVE_OUT.filter((block) => block < plan.current.block);
      plan.current.hold = false;
    }
  }, [reading, reduced, active, begin]);

  // Less motion, asked for while the canvas is up: hand back the real, sharp <img> now
  useEffect(() => {
    if (reduced && active) setActive(false);
  }, [reduced, active]);

  // Layout effect: the first frame paints before the browser shows the hidden <img>'s empty box
  useLayoutEffect(() => {
    if (!active) return;
    const canvas = canvasRef.current;
    const frame = frameRef.current;
    const img = imgRef.current;
    if (!canvas || !frame || !img) {
      setActive(false);
      return;
    }
    let paint: ReturnType<typeof createPainter>;
    try {
      paint = createPainter(canvas, frame, img);
    } catch {
      setActive(false);
      return;
    }
    let visible = true;

    const tick = () => {
      const p = plan.current;
      if (p.queue.length) {
        p.block = p.queue.shift() as number;
      } else if (!p.hold) {
        if (p.block <= 1) {
          setActive(false);
          return;
        }
        p.queue = RESOLVE_OUT.filter((block) => block < p.block);
        p.block = p.queue.shift() ?? 1;
      }
      p.beat += 1;
      if (!visible) return;
      const lens = p.hold && p.queue.length === 0 ? lensAt(p.beat, frame.clientWidth, frame.clientHeight, p.block) : null;
      paint(p.block, lens);
    };

    try {
      tick();
    } catch {
      setActive(false);
      return;
    }
    // Watch visibility only once a frame has painted, so a failed first paint leaves nothing behind
    const observer =
      typeof IntersectionObserver !== 'undefined'
        ? new IntersectionObserver(([entry]) => {
            visible = entry?.isIntersecting ?? true;
          })
        : null;
    observer?.observe(frame);
    const unsubscribe = subscribeStep(() => {
      try {
        tick();
      } catch {
        setActive(false);
      }
    });
    return () => {
      unsubscribe();
      observer?.disconnect();
    };
  }, [active, frameRef, imgRef]);

  return { active, loaded: hasLoaded, canvasRef, onLoad };
}
