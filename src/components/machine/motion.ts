import { useEffect, useState } from 'react';

const QUERY = '(prefers-reduced-motion: reduce)';

/** True when the person asked for less motion; every machine effect has a still (DESIGN-v2 §8) */
export const prefersReducedMotion = (): boolean => {
  try {
    return typeof window !== 'undefined' && Boolean(window.matchMedia?.(QUERY).matches);
  } catch {
    return false;
  }
};

/**
 * The same preference, live: it changes when the person flips the setting with the app open, so
 * an effect running when they ask for less motion stops (and settles to its still) right away,
 * and one that hasn't started never starts.
 */
export const useReducedMotion = (): boolean => {
  const [reduced, setReduced] = useState(prefersReducedMotion);

  useEffect(() => {
    let query: MediaQueryList | undefined;
    try {
      query = window.matchMedia?.(QUERY);
    } catch {
      return;
    }
    if (!query) return;
    const onChange = () => setReduced(query.matches);
    onChange();
    if (query.addEventListener) query.addEventListener('change', onChange);
    else query.addListener?.(onChange);
    return () => {
      if (query.removeEventListener) query.removeEventListener('change', onChange);
      else query.removeListener?.(onChange);
    };
  }, []);

  return reduced;
};
