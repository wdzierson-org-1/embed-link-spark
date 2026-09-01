import React, { useEffect, useRef, useState } from 'react';
import { Expand, FileText, Github, Image as ImageIcon, Link2, Pause, Play } from 'lucide-react';
import { SUPABASE_URL } from '@/integrations/supabase/client';
import { domainOfUrl } from '@/utils/linkFlavor';
import {
  HERO_STANDARD,
  HERO_TALL,
  SpectrumField,
  formatBadgeColor,
  formatDurationChip,
  isSpreadsheetExt,
  waveformHeights,
} from '@/components/cards/CardBits';

/**
 * Object-zone renderers for the card system. Portrait media is contained on a
 * blurred self-backdrop (never center-cropped); landscape imagery covers the
 * standard hero; metadata-poor links get a favicon plate instead of a broken
 * or decorative image.
 */

/** Chooses cover vs contained-on-blur from the image's real aspect ratio */
export const AspectAwareImage = ({
  src,
  alt,
  onError,
}: {
  src: string;
  alt: string;
  onError?: () => void;
}) => {
  const [isPortrait, setIsPortrait] = useState(false);

  const handleLoad = (event: React.SyntheticEvent<HTMLImageElement>) => {
    const img = event.currentTarget;
    if (img.naturalHeight > img.naturalWidth * 1.05) setIsPortrait(true);
  };

  if (isPortrait) {
    return (
      <div className={`relative ${HERO_TALL} overflow-hidden rounded-t-2xl bg-gray-900`}>
        <img src={src} alt="" aria-hidden className="absolute inset-0 h-full w-full scale-125 object-cover opacity-40 blur-xl" />
        <img src={src} alt={alt} className="relative mx-auto h-full object-contain" loading="lazy" decoding="async" onError={onError} />
      </div>
    );
  }

  return (
    <div className={`${HERO_STANDARD} overflow-hidden rounded-t-2xl`}>
      <img
        src={src}
        alt={alt}
        className="h-full w-full object-cover"
        loading="lazy"
        decoding="async"
        onLoad={handleLoad}
        onError={onError}
      />
    </div>
  );
};

interface LinkCoverProps {
  imageSource: string;
  alt: string;
  /** Portrait-first treatments (short-form video, book covers) */
  tall?: boolean;
  playOverlay?: boolean;
  domainPill?: string;
  onFailed: () => void;
}

/**
 * Link preview image with the storage/proxy fallback chain: external URLs that
 * fail to hotlink retry once through the image-proxy edge function, then hand
 * control back so the hero can fall back to the favicon plate.
 */
export const LinkCover = ({ imageSource, alt, tall, playOverlay, domainPill, onFailed }: LinkCoverProps) => {
  const [src, setSrc] = useState(imageSource);
  const [triedProxy, setTriedProxy] = useState(imageSource.includes('/functions/v1/image-proxy'));

  const handleError = () => {
    if (!triedProxy) {
      setTriedProxy(true);
      setSrc(`${SUPABASE_URL}/functions/v1/image-proxy?url=${encodeURIComponent(imageSource)}`);
      return;
    }
    onFailed();
  };

  const overlays = (
    <>
      {playOverlay && (
        <span className="absolute left-1/2 top-1/2 grid h-12 w-12 -translate-x-1/2 -translate-y-1/2 place-items-center rounded-full bg-black/50 backdrop-blur">
          <Play className="h-5 w-5 fill-white text-white" />
        </span>
      )}
      {domainPill && (
        <span className="absolute bottom-2 left-1/2 -translate-x-1/2 rounded-full bg-black/60 px-2.5 py-1 text-[11px] font-medium text-white backdrop-blur">
          {domainPill}
        </span>
      )}
    </>
  );

  if (tall) {
    return (
      <div className={`relative ${HERO_TALL} overflow-hidden rounded-t-2xl bg-gray-900`}>
        <img src={src} alt="" aria-hidden className="absolute inset-0 h-full w-full scale-125 object-cover opacity-40 blur-xl" referrerPolicy="no-referrer" />
        <img
          src={src}
          alt={alt}
          className="relative mx-auto h-full object-contain"
          loading="lazy"
          decoding="async"
          referrerPolicy="no-referrer"
          onError={handleError}
        />
        {overlays}
      </div>
    );
  }

  return (
    <div className={`relative ${HERO_STANDARD} overflow-hidden rounded-t-2xl`}>
      <img
        src={src}
        alt={alt}
        className="h-full w-full object-cover"
        loading="lazy"
        decoding="async"
        referrerPolicy="no-referrer"
        onError={handleError}
      />
      {overlays}
    </div>
  );
};

/** GitHub/GitLab repos: the repo path IS the imagery */
export const RepoPlate = ({ url, description }: { url: string; description?: string }) => {
  const segments = (() => {
    try {
      return new URL(url).pathname.split('/').filter(Boolean);
    } catch {
      return [] as string[];
    }
  })();
  const owner = segments[0];
  const repo = segments[1];

  return (
    <div className="rounded-t-2xl bg-[#0d1117] p-5">
      <p className="flex items-center gap-2 font-mono text-sm text-white/90">
        <Github className="h-4 w-4 flex-none" />
        {owner && repo ? (
          <span className="truncate">
            {owner}
            <span className="text-white/40">/</span>
            <span className="font-semibold">{repo}</span>
          </span>
        ) : (
          <span className="truncate">{domainOfUrl(url)}</span>
        )}
      </p>
      {description && <p className="mt-2 line-clamp-2 text-[13px] leading-snug text-white/60">{description}</p>}
    </div>
  );
};

/** Metadata-poor links: favicon-style plate, honest and never broken */
export const FaviconPlate = ({ url }: { url: string }) => {
  const domain = domainOfUrl(url);
  const letter = domain.replace(/^./, (c) => c.toUpperCase()).charAt(0) || '?';

  return (
    <div className="flex items-center gap-3 rounded-t-2xl border-b border-black/5 bg-gradient-to-b from-gray-50 to-gray-100/60 p-5">
      <span className="grid h-12 w-12 flex-none place-items-center rounded-2xl bg-violet-100 text-lg font-bold text-violet-600 shadow-sm">
        {letter}
      </span>
      <div className="min-w-0">
        <p className="truncate text-[13px] font-medium text-foreground/80">{domain || 'link'}</p>
        <p className="text-[11px] text-muted-foreground">preview limited · saved anyway</p>
      </div>
    </div>
  );
};

/* ── audio: the player IS the hero (DESIGN.md per-type hero rules) ─────── */

const PLAYER_ACCENTS = {
  voice_note: { circle: '#544eba', circleShadow: '0 2px 10px rgba(84,78,186,0.35)', bar: 'rgba(84,78,186,0.72)', time: '#45408c' },
  recording: { circle: '#8b4a9e', circleShadow: '0 2px 10px rgba(139,74,158,0.3)', bar: 'rgba(139,74,158,0.65)', time: '#703c77' },
} as const;

/**
 * Audio hero: functional play/pause on the type's flat spectrum field.
 * Voice notes get the full-height player; long recordings compress. Waveform
 * bars are deterministic from the item id until real amplitudes are sampled;
 * played bars run at full accent, unplayed at .26.
 */
export const PlayerHero = ({
  itemId,
  src,
  kind,
  durationS,
}: {
  itemId: string;
  src: string;
  kind: 'voice_note' | 'recording';
  durationS?: number | null;
}) => {
  const [isPlaying, setIsPlaying] = useState(false);
  const [currentTime, setCurrentTime] = useState(0);
  const [duration, setDuration] = useState(durationS ?? 0);
  const audioRef = useRef<HTMLAudioElement>(null);

  useEffect(() => {
    const audio = audioRef.current;
    if (!audio) return;

    const updateTime = () => setCurrentTime(audio.currentTime);
    const updateDuration = () => {
      if (Number.isFinite(audio.duration)) setDuration(audio.duration);
    };
    const handleEnded = () => {
      setIsPlaying(false);
      setCurrentTime(0);
    };

    audio.addEventListener('timeupdate', updateTime);
    audio.addEventListener('loadedmetadata', updateDuration);
    audio.addEventListener('ended', handleEnded);
    return () => {
      audio.removeEventListener('timeupdate', updateTime);
      audio.removeEventListener('loadedmetadata', updateDuration);
      audio.removeEventListener('ended', handleEnded);
    };
  }, []);

  const togglePlay = (event: React.MouseEvent) => {
    // The hero sits inside the card's click-to-edit zone
    event.stopPropagation();
    const audio = audioRef.current;
    if (!audio) return;
    if (isPlaying) {
      audio.pause();
    } else {
      audio.play();
    }
    setIsPlaying(!isPlaying);
  };

  const voice = kind === 'voice_note';
  const accents = PLAYER_ACCENTS[kind];
  const heights = waveformHeights(itemId);
  const progress = duration > 0 ? currentTime / duration : 0;
  const timeLabel =
    formatDurationChip(isPlaying || currentTime > 0 ? currentTime : duration) ?? '0:00';

  return (
    <SpectrumField
      tint={voice ? 'voice' : 'audio'}
      className={`flex items-center gap-3.5 px-5 ${voice ? 'h-[116px]' : 'h-24'}`}
    >
      <audio ref={audioRef} src={src} preload="metadata" />
      <button
        type="button"
        onClick={togglePlay}
        aria-label={isPlaying ? 'Pause' : 'Play'}
        className={`relative z-[1] grid flex-none place-items-center rounded-full text-white ${
          voice ? 'h-[46px] w-[46px]' : 'h-10 w-10'
        }`}
        style={{ background: accents.circle, boxShadow: accents.circleShadow }}
      >
        {isPlaying ? (
          <Pause className="h-4 w-4 fill-current" />
        ) : (
          <Play className="ml-0.5 h-4 w-4 fill-current" />
        )}
      </button>
      <div className="relative z-[1] flex h-11 flex-1 items-center gap-[3px]" aria-hidden>
        {heights.map((height, index) => (
          <span
            key={index}
            className="min-w-[2px] flex-1 rounded-[2px]"
            style={{
              height: `${height}%`,
              background: accents.bar,
              opacity: index / heights.length < progress ? 1 : 0.26,
            }}
          />
        ))}
      </div>
      <span
        className="relative z-[1] text-[11px] font-semibold tabular-nums"
        style={{ color: accents.time }}
      >
        {timeLabel}
      </span>
    </SpectrumField>
  );
};

/* ── documents: page glyph floating on the document field ──────────────── */

/**
 * Document hero: white first-page glyph (CSS) on the document spectrum
 * field, format badge tinted by kind. A real rendered first page can slot
 * into the glyph later without changing the card.
 */
export const DocumentHero = ({ ext }: { ext?: string | null }) => {
  const spreadsheet = isSpreadsheetExt(ext);
  const line = (extra: React.CSSProperties = {}) => (
    <span className="block h-[3px] rounded-[2px]" style={{ background: 'rgba(34,38,47,0.14)', ...extra }} />
  );

  return (
    <SpectrumField tint="doc" className={`${HERO_STANDARD} grid place-items-center`}>
      <div
        className="relative z-[1] flex h-[132px] w-[104px] flex-col gap-[5px] rounded-md bg-white px-3 py-3.5"
        style={{ boxShadow: '0 10px 26px rgba(120,60,160,0.2), 0 1px 2px rgba(0,0,0,0.08)' }}
      >
        <span
          className="absolute right-0 top-0 h-[18px] w-[18px] rounded-tr-md"
          style={{
            background: 'linear-gradient(225deg, transparent 50%, rgba(120,60,160,0.14) 50%)',
            borderRadius: '0 6px 0 6px',
          }}
        />
        <span
          className="mb-[3px] block h-[6px] w-[70%] rounded-[2px]"
          style={{ background: 'rgba(34,38,47,0.3)' }}
        />
        {spreadsheet ? (
          <>
            {[0, 1, 2].map((row) => (
              <span key={row} className="flex gap-1">
                {line({ flex: 1 })}
                {line({ flex: 1 })}
                {line({ flex: 1 })}
              </span>
            ))}
          </>
        ) : (
          <>
            {line()}
            {line()}
            {line({ width: '55%' })}
            {line()}
            {line()}
            {line({ width: '55%' })}
          </>
        )}
      </div>
      {ext && (
        <span
          className="absolute bottom-3.5 right-4 z-[2] rounded-[7px] bg-white px-[7px] py-[3px] text-[10px] font-bold tracking-[0.06em]"
          style={{ color: formatBadgeColor(ext), boxShadow: '0 2px 8px rgba(120,60,160,0.18)' }}
        >
          {ext}
        </span>
      )}
    </SpectrumField>
  );
};

/* ── video uploads: poster frame, not native chrome ────────────────────── */

/**
 * Video hero at rest: first frame (preload=metadata), centered play badge,
 * duration on a bottom scrim — no native controls until playback starts.
 */
export const VideoPosterHero = ({
  src,
  durationS,
  onExpand,
}: {
  src: string;
  durationS?: number | null;
  onExpand?: () => void;
}) => {
  const [started, setStarted] = useState(false);
  const videoRef = useRef<HTMLVideoElement>(null);
  const duration = formatDurationChip(durationS);

  const handlePlay = (event: React.MouseEvent) => {
    event.stopPropagation();
    setStarted(true);
    videoRef.current?.play();
  };

  return (
    <div className={`relative ${HERO_STANDARD} w-full overflow-hidden rounded-t-2xl bg-black`}>
      <video
        ref={videoRef}
        src={src}
        className="h-full w-full object-cover"
        preload="metadata"
        playsInline
        controls={started}
        onEnded={() => setStarted(false)}
      >
        Your browser does not support the video tag.
      </video>
      {!started && (
        <>
          <div
            className="pointer-events-none absolute inset-x-0 bottom-0 h-[56%]"
            style={{ background: 'linear-gradient(to top, rgba(12,13,18,0.55), transparent)' }}
          />
          <button
            type="button"
            onClick={handlePlay}
            aria-label="Play"
            className="absolute left-1/2 top-1/2 grid h-[52px] w-[52px] -translate-x-1/2 -translate-y-1/2 place-items-center rounded-full bg-white/90 shadow-[0_4px_16px_rgba(0,0,0,0.25)]"
          >
            <Play className="ml-0.5 h-[18px] w-[18px] fill-current text-foreground" />
          </button>
          {duration && (
            <span className="pointer-events-none absolute bottom-2.5 right-2.5 rounded-full bg-black/70 px-2 py-0.5 text-[11px] font-semibold tabular-nums text-white">
              {duration}
            </span>
          )}
        </>
      )}
      {onExpand && (
        <div className="absolute right-2 top-2 opacity-0 transition-opacity duration-200 group-hover:opacity-100">
          <button
            type="button"
            onClick={(event) => {
              event.stopPropagation();
              onExpand();
            }}
            aria-label="Expand video"
            className="grid h-8 w-8 place-items-center rounded-full bg-black/50 text-white hover:bg-black/70"
          >
            <Expand className="h-4 w-4" />
          </button>
        </div>
      )}
    </div>
  );
};

/** Documents and imageless media: a file plate instead of a decorative hero */
export const FilePlate = ({
  fileName,
  factsLine,
  kind,
}: {
  fileName?: string | null;
  factsLine?: string | null;
  kind: 'document' | 'image';
}) => {
  const Icon = kind === 'image' ? ImageIcon : FileText;
  const tint = kind === 'image' ? 'bg-violet-50 text-violet-500' : 'bg-red-50 text-red-500';

  return (
    <div className="flex items-center gap-3 rounded-t-2xl border-b border-black/5 bg-gray-50/80 p-4">
      <span className={`grid h-11 w-11 flex-none place-items-center rounded-xl ${tint}`}>
        <Icon className="h-5 w-5" />
      </span>
      <div className="min-w-0">
        {fileName ? (
          <p className="truncate font-mono text-[12px] text-foreground/70">{fileName}</p>
        ) : (
          <p className="flex items-center gap-1 text-[13px] font-medium text-foreground/70">
            <Link2 className="hidden" />
            {kind === 'image' ? 'Image' : 'Document'}
          </p>
        )}
        {factsLine && <p className="text-[11px] text-muted-foreground">{factsLine}</p>}
      </div>
    </div>
  );
};
