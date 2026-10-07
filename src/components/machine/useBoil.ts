import { useEffect, useState } from 'react';
import { useReducedMotion } from './motion';
import { subscribeStep } from './stepTicker';

const SETTLE_BEATS = 3;

/**
 * The drawn half of Resolve (resolve.ts): how unsettled a placeholder glyph, waveform or page
 * should be this beat. 1 while Stash reads; when it stops, it settles over three beats to 0 and
 * the clock lets go. 0 under reduced motion, including when it's switched on mid-settle (the
 * status line still says Stash is reading).
 */
export const useBoil = (reading: boolean): { amount: number; beat: number } => {
  const reduced = useReducedMotion();
  const [beat, setBeat] = useState(0);
  const [settleLeft, setSettleLeft] = useState(0);

  // Start the settle in the same render that sees reading end (adjusting state on a prop
  // change), so no frame shows the glyph sharp before it steps down
  const [wasReading, setWasReading] = useState(reading);
  if (wasReading !== reading) {
    setWasReading(reading);
    setSettleLeft(reading ? 0 : SETTLE_BEATS);
  }

  const active = !reduced && (reading || settleLeft > 0);
  useEffect(() => {
    if (!active) return;
    return subscribeStep((step) => {
      setBeat(step);
      if (!reading) setSettleLeft((left) => Math.max(0, left - 1));
    });
  }, [active, reading]);

  const amount = reduced ? 0 : reading ? 1 : settleLeft / (SETTLE_BEATS + 1);
  return { amount, beat };
};
