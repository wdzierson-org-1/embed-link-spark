import React, { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState } from 'react';

/**
 * The media clock (docs/ui-changes.md 2026-10-10, timestamped notes): whichever player is on the
 * panel reports where it is and how to seek; the notes head offers `+ note at 1:42`, and a
 * `[1:42]` marker in the notes seeks the player. One player at a time; without a provider the
 * clock is inert.
 */
export const SEEK_EVENT = 'stash:seek';

interface MediaClock {
  /** Playback position in seconds, or null when no player is reporting */
  seconds: number | null;
  report: (seconds: number | null) => void;
  registerSeek: (seek: ((seconds: number) => void) | null) => void;
  seek: (seconds: number) => void;
  canSeek: boolean;
}

const inert: MediaClock = { seconds: null, report: () => {}, registerSeek: () => {}, seek: () => {}, canSeek: false };
const MediaClockContext = createContext<MediaClock>(inert);

export const MediaClockProvider = ({ children }: { children: React.ReactNode }) => {
  const [seconds, setSeconds] = useState<number | null>(null);
  const seekRef = useRef<((seconds: number) => void) | null>(null);
  const [canSeek, setCanSeek] = useState(false);

  const report = useCallback((next: number | null) => setSeconds(next), []);
  const registerSeek = useCallback((seek: ((seconds: number) => void) | null) => {
    seekRef.current = seek;
    setCanSeek(Boolean(seek));
  }, []);
  const seek = useCallback((target: number) => seekRef.current?.(target), []);

  // A marker clicked in the notes editor dispatches the seek on the window
  useEffect(() => {
    const onSeek = (event: Event) => {
      const target = (event as CustomEvent<{ seconds: number }>).detail?.seconds;
      if (typeof target === 'number') seek(target);
    };
    window.addEventListener(SEEK_EVENT, onSeek);
    return () => window.removeEventListener(SEEK_EVENT, onSeek);
  }, [seek]);

  const value = useMemo<MediaClock>(() => ({ seconds, report, registerSeek, seek, canSeek }), [seconds, report, registerSeek, seek, canSeek]);
  return <MediaClockContext.Provider value={value}>{children}</MediaClockContext.Provider>;
};

export const useMediaClock = (): MediaClock => useContext(MediaClockContext);

/** A native <audio>/<video> element reports its time and takes seeks for as long as it is mounted */
export const useMediaElementClock = (ref: React.RefObject<HTMLMediaElement>) => {
  const { report, registerSeek } = useMediaClock();
  useEffect(() => {
    const element = ref.current;
    if (!element) return;
    const onTime = () => report(element.currentTime);
    element.addEventListener('timeupdate', onTime);
    element.addEventListener('seeked', onTime);
    element.addEventListener('loadedmetadata', onTime);
    registerSeek((seconds) => {
      element.currentTime = seconds;
      void element.play().catch(() => {});
    });
    report(element.currentTime);
    return () => {
      element.removeEventListener('timeupdate', onTime);
      element.removeEventListener('seeked', onTime);
      element.removeEventListener('loadedmetadata', onTime);
      registerSeek(null);
      report(null);
    };
  }, [ref, report, registerSeek]);
};

/** What a `[1:42]` marker does when clicked */
export const dispatchSeek = (seconds: number) => {
  window.dispatchEvent(new CustomEvent(SEEK_EVENT, { detail: { seconds } }));
};
