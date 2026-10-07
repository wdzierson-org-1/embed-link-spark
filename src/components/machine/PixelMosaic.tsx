import React, { useEffect, useRef } from 'react';
import { cn } from '@/lib/utils';
import { useReducedMotion } from './motion';
import { noise3 } from './resolve';
import { subscribeStep } from './stepTicker';

/**
 * A picture that hasn't arrived (DESIGN-v2 §8, "Resolve"): a mosaic of 8 px blocks in the paper's
 * four greys, each block re-rolling every few beats at its own phase, so the field shimmers like
 * a signal not yet locked. Replaces the scan bar on skeleton cards and the document preview. A
 * canvas one pixel per block, scaled up crisp; still under reduced motion.
 */
const LEVELS = [
  [0xd5, 0xd8, 0xd1],
  [0xdf, 0xe1, 0xdb],
  [0xe6, 0xe8, 0xe2],
  [0xec, 0xed, 0xe9],
];

export const PixelMosaic = ({ className, block = 8 }: { className?: string; block?: number }) => {
  const ref = useRef<HTMLCanvasElement>(null);
  const reduced = useReducedMotion();

  useEffect(() => {
    const canvas = ref.current;
    if (!canvas?.getContext) return;
    const paint = (beat: number) => {
      const cols = Math.max(1, Math.ceil(canvas.clientWidth / block));
      const rows = Math.max(1, Math.ceil(canvas.clientHeight / block));
      if (canvas.width !== cols || canvas.height !== rows) {
        canvas.width = cols;
        canvas.height = rows;
      }
      const ctx = canvas.getContext('2d');
      if (!ctx) return;
      const image = ctx.createImageData(cols, rows);
      for (let y = 0; y < rows; y++) {
        for (let x = 0; x < cols; x++) {
          const phase = Math.floor(noise3(x, y, 77) * 6);
          const [r, g, b] = LEVELS[Math.floor(noise3(x, y, Math.floor((beat + phase) / 6)) * LEVELS.length)];
          const at = (y * cols + x) * 4;
          image.data[at] = r;
          image.data[at + 1] = g;
          image.data[at + 2] = b;
          image.data[at + 3] = 255;
        }
      }
      ctx.putImageData(image, 0, 0);
    };
    try {
      paint(0);
    } catch {
      return;
    }
    if (reduced) return;
    // A library's worth of pictures still loading below the fold shouldn't cost a paint a beat
    let visible = true;
    const observer =
      typeof IntersectionObserver !== 'undefined'
        ? new IntersectionObserver(([entry]) => {
            visible = entry?.isIntersecting ?? true;
          })
        : null;
    observer?.observe(canvas);
    const unsubscribe = subscribeStep((beat) => {
      if (!visible) return;
      try {
        paint(beat);
      } catch {
        /* a canvas that can't paint stays as it was */
      }
    });
    return () => {
      unsubscribe();
      observer?.disconnect();
    };
  }, [block, reduced]);

  return <canvas ref={ref} aria-hidden className={cn('block h-full w-full [image-rendering:pixelated]', className)} />;
};
