import React, { useEffect, useMemo, useRef, useState } from 'react';
import { Download, Pause, Play } from 'lucide-react';
import { waveformHeights } from '@/components/cards/CardBits';
import { formatClock } from '@/utils/itemFacts';

/**
 * The panel's media player (DESIGN.md "Player"): flat type-tint field, solid
 * accent play/pause circle with real playback, deterministic waveform bars
 * (from the item id — there is no analysis pass), tabular-numeral times, and
 * a speed pill cycling 1× → 1.5× → 2×. Standalone on purpose — the card
 * MediaPlayer is a different surface and stays untouched.
 */

const RATES = [1, 1.5, 2];
const BAR_COUNT = 34;

const PALETTES = {
  voice: {
    field: 'rgba(84,88,178,.11)',
    ring: 'rgba(84,88,178,.06)',
    accent: '#544eba',
    accentShadow: 'rgba(84,78,186,.35)',
    bar: 'rgba(84,78,186,.72)',
    text: '#45408c',
    pillBorder: 'rgba(84,78,186,.35)',
  },
  warm: {
    field: 'rgba(126,74,158,.10)',
    ring: 'rgba(126,74,158,.06)',
    accent: '#8b4a9e',
    accentShadow: 'rgba(139,74,158,.3)',
    bar: 'rgba(139,74,158,.65)',
    text: '#703c77',
    pillBorder: 'rgba(139,74,158,.4)',
  },
} as const;

interface EditItemPlayerStripProps {
  src: string;
  itemId: string;
  variant: keyof typeof PALETTES;
  /** attributes.media.duration_s — used until the element reports metadata */
  durationHint?: number;
  downloadUrl?: string;
}

const EditItemPlayerStrip = ({
  src,
  itemId,
  variant,
  durationHint,
  downloadUrl,
}: EditItemPlayerStripProps) => {
  const palette = PALETTES[variant];
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
      <style>{'@keyframes stash-barpulse{0%,100%{opacity:.26}50%{opacity:.44}}'}</style>
      <audio ref={audioRef} src={src} preload="metadata" />
      <div
        className="flex items-center gap-3.5 rounded-[14px] px-[18px] py-4"
        style={{ background: palette.field, boxShadow: `inset 0 0 0 1px ${palette.ring}` }}
      >
        <button
          onClick={togglePlay}
          aria-label={isPlaying ? 'Pause' : 'Play'}
          className="grid h-11 w-11 flex-none place-items-center rounded-full text-white"
          style={{ background: palette.accent, boxShadow: `0 2px 10px ${palette.accentShadow}` }}
        >
          {isPlaying ? (
            <Pause className="h-4 w-4 fill-current" />
          ) : (
            <Play className="ml-0.5 h-4 w-4 fill-current" />
          )}
        </button>
        <span
          className="text-[11.5px] font-semibold tabular-nums"
          style={{ color: palette.text }}
        >
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
              className="flex-1 rounded-[2px] motion-reduce:!animate-none"
              style={{
                height: `${height.toFixed(0)}%`,
                background: palette.bar,
                opacity: i <= playedTo ? 1 : 0.26,
                animation:
                  isPlaying && i > playedTo
                    ? 'stash-barpulse 1.4s ease-in-out infinite'
                    : undefined,
              }}
            />
          ))}
        </div>
        <span
          className="text-[11.5px] font-semibold tabular-nums"
          style={{ color: palette.text }}
        >
          {formatClock(totalSeconds) || '--:--'}
        </span>
        <button
          onClick={cycleRate}
          aria-label="Playback speed"
          className="rounded-full border px-2 py-0.5 text-[11px] font-bold transition-colors hover:bg-black/[0.04]"
          style={{ color: palette.text, borderColor: palette.pillBorder }}
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
          className="inline-flex items-center gap-1.5 text-xs text-[#959ba6] transition-colors hover:text-[#6d5bd0]"
        >
          <Download className="h-[13px] w-[13px]" />
          Download original
        </a>
      </div>
    </div>
  );
};

export default EditItemPlayerStrip;
