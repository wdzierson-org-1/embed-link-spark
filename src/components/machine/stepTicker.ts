/**
 * One stepped clock for the reading effects (DESIGN-v2 §8, "Resolve"): every pixel lens, boiling
 * glyph, jittering waveform and mosaic advances on the same 110 ms beat. Stepped, like the
 * spinner, so the machinery reads as machinery, and a page of reading cards costs one timer.
 *
 * It runs whenever something is subscribed and stops when nothing is. Reduced motion is the
 * subscribers' call (useReducedMotion, live): they don't subscribe, and they unsubscribe (and
 * settle to their stills) when the preference changes. A clock that refused to start would
 * strand a subscriber mid-effect.
 */
export const STEP_MS = 110;

let step = 0;
let timer: ReturnType<typeof setInterval> | undefined;
const listeners = new Set<(step: number) => void>();

export const subscribeStep = (listener: (step: number) => void): (() => void) => {
  listeners.add(listener);
  if (!timer) {
    timer = setInterval(() => {
      step += 1;
      listeners.forEach((notify) => notify(step));
    }, STEP_MS);
  }
  return () => {
    listeners.delete(listener);
    if (listeners.size === 0 && timer) {
      clearInterval(timer);
      timer = undefined;
    }
  };
};
