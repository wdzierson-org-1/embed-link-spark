import { useSyncExternalStore } from 'react';
import { prefersReducedMotion } from './motion';

/**
 * The machine's spinner: a terminal `| / - \` cursor turning in front of a status line, as on
 * the share sheet in the homepage film ("| reading the cover…"). One shared ticker drives
 * every spinner on screen, so fifty enriching cards turn in step and cost one interval. Under
 * reduced motion the cursor holds still at `|` and the words carry the state.
 */
export const SPINNER_FRAMES = ['|', '/', '-', '\\'] as const;
const FRAME_MS = 130;

let frame = 0;
let timer: ReturnType<typeof setInterval> | undefined;
const listeners = new Set<() => void>();

const subscribe = (listener: () => void) => {
  listeners.add(listener);
  if (!timer && !prefersReducedMotion()) {
    timer = setInterval(() => {
      frame = (frame + 1) % SPINNER_FRAMES.length;
      listeners.forEach((notify) => notify());
    }, FRAME_MS);
  }
  return () => {
    listeners.delete(listener);
    if (listeners.size === 0 && timer) {
      clearInterval(timer);
      timer = undefined;
    }
  };
};

const getFrame = () => frame;
const getServerFrame = () => 0;

export const useSpinnerFrame = (): string => SPINNER_FRAMES[useSyncExternalStore(subscribe, getFrame, getServerFrame)];
