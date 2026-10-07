import React, { useEffect, useMemo, useRef, useState } from 'react';
import { Download, Pause, Play } from 'lucide-react';
import { waveformHeights } from '@/components/cards/CardBits';
import { formatClock } from '@/utils/itemFacts';

/**
 * The panel's media player (DESIGN-v2): a square ink play button with real playback,
 * deterministic waveform bars in ink (from the item id; there is no analysis pass), times in
 * Departure Mono, and a square speed control cycling 1× → 1.5× → 2×. Standalone on purpose —
 * the card MediaPlayer is a different surface and stays untouched.
 */

const RATES = [1, 1.5, 2];
const BAR_COUNT = 40;

/** Kept for callers: v2 has one player look; voice and recordings differ by tag, not colour */
const VARIANTS = ['voice', 'warm'] as const;

interface EditItemPlayerStripProps {
  src: string;
  itemId: string;
  variant: (typeof VARIANTS)[number];
  /** attributes.media.duration_s — used until the element reports metadata */
  durationHint?: number;
  downloadUrl?: string;
}

const EditItemPlayerStrip = ({
  src,
  itemId,
  durationHint,
  downloadUrl,
}: EditItemPlayerStripProps) => {
  const audioRef = useRef<HTMLAudioElement>(null);
  const [isPlaying, setIsPlaying] = useState(false);
  const [currentTime, setCurrentTime] = useState(0);
  const [duration, setDuration] = useState(0);
  const [rateIndex, setRateIndex] = useState(0);

  // Deterministic waveform from the item id — same identity as the card hero
  const barHeights = useMemo(() => waveformHeights(itemId, BAR_COUNT), [itemId]);

  useEffect(() => {
    const audio = audioRef.current;
    if (!audio) return;

    const updateTime = () => setCurrentTime(audio.currentTime);
    const updateDuration = () => {
      if (Number.isFinite(audio.duration)) setDuration(audio.duration);
    };
    const handleEnded = () => setIsPlaying(false);

    audio.addEventListener('timeupdate', updateTime);
    audio.addEventListener('loadedmetadata', updateDuration);
    audio.addEventListener('durationchange', updateDuration);
    audio.addEventListener('ended', handleEnded);
    return () => {
      audio.removeEventListener('timeupdate', updateTime);
      audio.removeEventListener('loadedmetadata', updateDuration);
      audio.removeEventListener('durationchange', updateDuration);
      audio.removeEventListener('ended', handleEnded);
    };
  }, []);

  // Reset playback state when the source changes (panel reused across items)
  useEffect(() => {
    setIsPlaying(false);
    setCurrentTime(0);
    setDuration(0);
  }, [src]);

  const togglePlay = () => {
    const audio = audioRef.current;
    if (!audio) return;
    if (isPlaying) {
      audio.pause();
    } else {
      audio.playbackRate = RATES[rateIndex];
      void audio.play();
    }
    setIsPlaying(!isPlaying);
  };

  const cycleRate = () => {
    const next = (rateIndex + 1) % RATES.length;
    setRateIndex(next);
    if (audioRef.current) audioRef.current.playbackRate = RATES[next];
  };

  const totalSeconds = duration || durationHint || 0;

  const seekToFraction = (event: React.MouseEvent<HTMLDivElement>) => {
    const audio = audioRef.current;
    if (!audio || !totalSeconds) return;
    const rect = event.currentTarget.getBoundingClientRect();
    const fraction = Math.min(Math.max((event.clientX - rect.left) / rect.width, 0), 1);
    audio.currentTime = fraction * totalSeconds;
    setCurrentTime(fraction * totalSeconds);
  };

  const playedTo = totalSeconds > 0 ? (currentTime / totalSeconds) * (BAR_COUNT - 1) : -1;

  return (
    <div className="mt-6">
      <audio ref={audioRef} src={src} preload="metadata" />
      <div className="flex items-center gap-3.5 border border-line bg-fill px-4 py-3.5">
        <button
          onClick={togglePlay}
          aria-label={isPlaying ? 'Pause' : 'Play'}
          className="grid h-11 w-11 flex-none place-items-center bg-ink text-white transition-colors hover:bg-ink-soft"
        >
          {isPlaying ? (
            <Pause className="h-4 w-4 fill-current" />
          ) : (
            <Play className="ml-0.5 h-4 w-4 fill-current" />
          )}
        </button>
        <span className="font-pixel text-pixel tabular-nums text-ink">
          {formatClock(currentTime) || '0:00'}
        </span>
        <div
          className="flex h-[38px] flex-1 cursor-pointer items-center gap-[3px]"
          onClick={seekToFraction}
          role="presentation"
        >
          {barHeights.map((height, i) => (
            <i
              key={i}
              className="flex-1 bg-ink"
              style={{
                height: `${height.toFixed(0)}%`,
                opacity: i <= playedTo ? 1 : 0.25,
              }}
            />
          ))}
        </div>
        <span className="font-pixel text-pixel tabular-nums text-muted-foreground">
          {formatClock(totalSeconds) || '--:--'}
        </span>
        <button
          onClick={cycleRate}
          aria-label="Playback speed"
          className="h-7 min-w-[38px] border border-ink px-1.5 font-pixel text-pixel leading-none text-ink transition-colors hover:bg-ink hover:text-white"
        >
          {RATES[rateIndex]}×
        </button>
      </div>
      <div className="mt-2 flex gap-4">
        <a
          href={downloadUrl || src}
          download
          target="_blank"
          rel="noreferrer"
          className="inline-flex items-center gap-1.5 font-pixel text-pixel text-muted-foreground underline-offset-2 transition-colors hover:text-ink hover:underline"
        >
          <Download className="h-3 w-3" />
          download original
        </a>
      </div>
    </div>
  );
};

export default EditItemPlayerStrip;
