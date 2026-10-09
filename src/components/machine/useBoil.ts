import { useEffect, useState } from 'react';
import { useReducedMotion } from './motion';
import { READING_BOUND_MS } from './resolve';
import { subscribeStep } from './stepTicker';

const SETTLE_BEATS = 3;

/**
 * The drawn half of Resolve (resolve.ts): how unsettled a placeholder glyph, waveform or page
 * should be this beat. 1 while Stash reads, for READING_BOUND_MS at most (the kind tag keeps
 * saying Stash is reading); when it stops, it settles over three beats to 0 and the clock lets
 * go. 0 under reduced motion, including when it's switched on mid-settle.
 */
export const useBoil = (reading: boolean): { amount: number; beat: number } => {
  const reduced = useReducedMotion();
  const [beat, setBeat] = useState(0);
  const [settleLeft, setSettleLeft] = useState(0);

  // The boil is bounded: a reading that runs long settles anyway
  const [expired, setExpired] = useState(false);
  useEffect(() => {
    if (!reading) {
      setExpired(false);
      return;
    }
    const timer = window.setTimeout(() => setExpired(true), READING_BOUND_MS);
    return () => window.clearTimeout(timer);
  }, [reading]);
  const boiling = reading && !expired;

  // Start the settle in the same render that sees the boil end (adjusting state on a prop
  // change), so no frame shows the glyph sharp before it steps down
  const [wasBoiling, setWasBoiling] = useState(boiling);
  if (wasBoiling !== boiling) {
    setWasBoiling(boiling);
    setSettleLeft(boiling ? 0 : SETTLE_BEATS);
  }

  const active = !reduced && (boiling || settleLeft > 0);
  useEffect(() => {
    if (!active) return;
    return subscribeStep((step) => {
      setBeat(step);
      if (!boiling) setSettleLeft((left) => Math.max(0, left - 1));
    });
  }, [active, boiling]);

  const amount = reduced ? 0 : boiling ? 1 : settleLeft / (SETTLE_BEATS + 1);
  return { amount, beat };
};
