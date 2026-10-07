import { useEffect, useRef, useState } from 'react';
import { prefersReducedMotion } from './motion';

/**
 * Decrypt (DESIGN-v2 §8): a value that arrives live comes in as scrambled glyphs that settle
 * left to right, 260–1100 ms by length: the machine handing a finding over to a clean reading.
 * Only for values arriving while the person watches; static text never scrambles, and reduced
 * motion shows the final text at once. Returns the string to render this frame.
 */
const SCRAMBLE = 'abcdefghijklmnopqrstuvwxyz0123456789#%&*+=<>/\\|{}[]';

export function useDecrypt(text: string, play: boolean): { display: string; scrambling: boolean } {
  const [display, setDisplay] = useState(text);
  const [scrambling, setScrambling] = useState(false);
  const playedForRef = useRef<string | null>(null);

  useEffect(() => {
    if (!play || prefersReducedMotion() || typeof requestAnimationFrame === 'undefined' || !text) {
      setDisplay(text);
      setScrambling(false);
      return;
    }
    // One decrypt per arriving value: a re-render with the same text doesn't replay it
    if (playedForRef.current === text) {
      setDisplay(text);
      return;
    }
    playedForRef.current = text;

    // Iterate by code point, not UTF-16 unit, so an emoji is one character that settles once
    const chars = Array.from(text);
    const total = Math.min(1100, 260 + chars.length * 7);
    const revealAt = chars.map((_, i) => (i / Math.max(1, chars.length)) * total * 0.7 + Math.random() * total * 0.3);
    const start = performance.now();
    let raf = 0;
    setScrambling(true);
    const tick = (now: number) => {
      const elapsed = now - start;
      let out = '';
      let done = true;
      for (let i = 0; i < chars.length; i++) {
        const ch = chars[i];
        if (ch === ' ' || elapsed >= revealAt[i]) out += ch;
        else {
          done = false;
          out += SCRAMBLE[(Math.random() * SCRAMBLE.length) | 0];
        }
      }
      setDisplay(out);
      if (done) setScrambling(false);
      else raf = requestAnimationFrame(tick);
    };
    raf = requestAnimationFrame(tick);
    return () => {
      cancelAnimationFrame(raf);
      setScrambling(false);
    };
  }, [text, play]);

  return { display: play ? display : text, scrambling: play && scrambling };
}
