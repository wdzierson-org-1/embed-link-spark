import { useEffect, useState } from 'react';
import { useReducedMotion } from './motion';

/**
 * The loading screen's decrypt cycle (DESIGN-v2 §8): a line arrives as cipher that settles left to
 * right behind a spot head, holds while it's read, scrambles back out right to left, and the next
 * line decrypts. Each app load starts one line further on, so the screen greets you differently
 * every time. A frame is a pure function of elapsed time; the hook only ticks it.
 */

export const LOADING_LINES = [
  'opening your stash',
  'the door creaks open…',
  'saving made simple',
  'hello again',
  'hey, you <3',
  'you’re my favorite… shhh',
  'dusting off your finds',
  'right where you left it',
  'remembering so you don’t have to',
  'psst. it’s all still here',
  'fetching your shiny things',
  'fluffing the pillows',
] as const;

const CIPHER = 'abcdefghijklmnopqrstuvwxyz0123456789#%&*+=<>/\\|{}[]~^░▒▓';
const GLYPH_MS = 55;
export const HOLD_MS = 1800;
export const OUT_MS = 280;

/** Long lines take longer to settle, within reason */
export const decryptMs = (length: number): number => Math.min(1200, 420 + length * 22);

const lineSpan = (text: string): number => decryptMs(Array.from(text).length) + HOLD_MS + OUT_MS;

// Deterministic jitter, so a frame at a given time is always the same frame
const hash = (a: number, b: number, c = 0): number => {
  let h = (a * 374761393 + b * 668265263 + c * 1442695041 + 0x2545f491) | 0;
  h = Math.imul(h ^ (h >>> 13), 1274126177);
  return ((h ^ (h >>> 16)) >>> 0) / 4294967296;
};

export interface CycleCell {
  ch: string;
  settled: boolean;
  /** The cell being decoded right now: the spot block sweeping the line */
  head: boolean;
}

export interface CycleFrame {
  index: number;
  cells: CycleCell[];
}

const lineFrame = (text: string, line: number, pass: number, t: number): CycleCell[] => {
  const chars = Array.from(text);
  const n = chars.length;
  const decrypt = decryptMs(n);
  const outStart = decrypt + HOLD_MS;
  const tick = Math.floor(t / GLYPH_MS);
  let headPlaced = t >= decrypt;
  return chars.map((ch, i) => {
    if (ch === ' ') return { ch, settled: true, head: false };
    const settleAt = (i / n) * decrypt * 0.72 + hash(line, i, pass) * decrypt * 0.28;
    const unsettleAt = outStart + ((n - 1 - i) / n) * OUT_MS * 0.8 + hash(i, line, pass + 7) * OUT_MS * 0.2;
    const settled = t >= settleAt && t < unsettleAt;
    if (settled) return { ch, settled, head: false };
    const head = !headPlaced;
    headPlaced = true;
    return { ch: CIPHER[Math.floor(hash(i, tick, line) * CIPHER.length)], settled, head };
  });
};

/** The frame `elapsed` ms into a cycle that starts at line `start` */
export const cycleFrame = (lines: readonly string[], start: number, elapsed: number): CycleFrame => {
  const total = lines.reduce((sum, line) => sum + lineSpan(line), 0);
  let t = Math.max(0, elapsed);
  const laps = Math.floor(t / total);
  t -= laps * total;
  for (let k = 0; ; k++) {
    const index = (start + k) % lines.length;
    const span = lineSpan(lines[index]);
    if (t < span) return { index, cells: lineFrame(lines[index], index, laps * lines.length + k, t) };
    t -= span;
  }
};

/** The line, plainly: reduced motion, and screen readers */
export const settledFrame = (lines: readonly string[], index: number): CycleFrame => ({
  index,
  cells: Array.from(lines[index]).map((ch) => ({ ch, settled: true, head: false })),
});

const LINE_KEY = 'stash_loading_line';

/** Which line this load opens on; advances the pointer so the next load greets differently */
export const takeLoadingLine = (count: number = LOADING_LINES.length): number => {
  try {
    const stored = Number.parseInt(localStorage.getItem(LINE_KEY) ?? '0', 10);
    const index = Number.isFinite(stored) && stored >= 0 ? stored % count : 0;
    localStorage.setItem(LINE_KEY, String((index + 1) % count));
    return index;
  } catch {
    return 0;
  }
};

/** Ticks the cycle about 30 times a second; under reduced motion (live), the first line, still */
export function useDecryptCycle(lines: readonly string[], start: number): CycleFrame {
  const reduced = useReducedMotion();
  const [frame, setFrame] = useState<CycleFrame>(() =>
    reduced ? settledFrame(lines, start) : cycleFrame(lines, start, 0),
  );

  useEffect(() => {
    if (reduced) {
      setFrame(settledFrame(lines, start));
      return;
    }
    if (typeof requestAnimationFrame === 'undefined') return;
    const t0 = performance.now();
    let raf = 0;
    let lastTick = -1;
    const loop = (now: number) => {
      const elapsed = now - t0;
      const tick = Math.floor(elapsed / 33);
      if (tick !== lastTick) {
        lastTick = tick;
        setFrame(cycleFrame(lines, start, elapsed));
      }
      raf = requestAnimationFrame(loop);
    };
    raf = requestAnimationFrame(loop);
    return () => cancelAnimationFrame(raf);
  }, [lines, start, reduced]);

  return frame;
}
