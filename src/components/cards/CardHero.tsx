import React, { useEffect, useRef, useState } from 'react';
import { Expand, Pause, Play } from 'lucide-react';
import { SUPABASE_URL } from '@/integrations/supabase/client';
import { domainOfUrl } from '@/utils/linkFlavor';
import { useSubjectCrop } from '@/components/cards/useSubjectCrop';
import { PixelGlyph, type GlyphName } from '@/components/machine/PixelGlyph';
import { Tag } from '@/components/machine/Machine';
import { PixelMosaic } from '@/components/machine/PixelMosaic';
import { boiledHeights, boiledWidth } from '@/components/machine/resolve';
import { useBoil } from '@/components/machine/useBoil';
import { usePixelImage } from '@/components/machine/usePixelImage';
import {
  HERO_EDGE,
  HERO_STANDARD,
  HERO_TALL,
  MediaField,
  formatDurationChip,
  isSpreadsheetExt,
  waveformHeights,
} from '@/components/cards/CardBits';

/**
 * Object-zone renderers for the card system (DESIGN-v2: "real objects first"). Portrait media
 * is contained on a blurred copy of itself (never center-cropped); landscape imagery covers the
 * standard hero; a save without a picture gets a placeholder drawn for the kind of thing it is,
 * in the machine voice: a pixel glyph on a dotted field and a black label naming the source.
 *
 * Cover crops are subject-aware (useSubjectCrop): the image is sampled once on load and the
 * crop window slides to keep the detected subject in view. Images load `crossOrigin="anonymous"`
 * for that read; every source we render here (storage bucket, image-proxy) allows it.
 *
 * While Stash reads a save its picture is unresolved (DESIGN-v2 §8, "Resolve"): photos and
 * covers go to pixel blocks with a reading lens (usePixelImage), drawn placeholders, waveforms
 * and pages boil (useBoil), and each resolves when Stash is done.
 */

interface ResolveProps {
  /** Stash is reading this save right now */
  reading?: boolean;
  /** The picture landed while the person watches: resolve it in from coarse blocks */
  arriving?: boolean;
}

/** The canvas usePixelImage paints; after the <img> in the DOM, so overlays later still sit on top */
const PixelCanvas = ({ canvasRef }: { canvasRef: React.RefObject<HTMLCanvasElement> }) => (
  <canvas ref={canvasRef} aria-hidden className="pointer-events-none absolute inset-0 h-full w-full" />
);

/** Under a picture still downloading: the mosaic, so the frame never sits empty and grey */
const PictureNotYet = ({ loaded }: { loaded: boolean }) => (loaded ? null : <PixelMosaic className="absolute inset-0" />);

/** Chooses cover vs contained-on-blur from the image's real aspect ratio */
export const AspectAwareImage = ({
  src,
  alt,
  onError,
  reading = false,
  arriving = false,
}: {
  src: string;
  alt: string;
  onError?: () => void;
} & ResolveProps) => {
  const [isPortrait, setIsPortrait] = useState(false);
  const crop = useSubjectCrop();
  const tallFrameRef = useRef<HTMLDivElement>(null);
  const imgRef = useRef<HTMLImageElement>(null);
  const pixel = usePixelImage({ frameRef: isPortrait ? tallFrameRef : crop.frameRef, imgRef, reading, arriving });

  const handleLoad = (event: React.SyntheticEvent<HTMLImageElement>) => {
    const img = event.currentTarget;
    if (img.naturalHeight > img.naturalWidth * 1.05) {
      // The portrait <img> that replaces this one starts the resolve when it loads
      setIsPortrait(true);
      return;
    }
    crop.onLoad(event);
    pixel.onLoad();
  };

  if (isPortrait) {
    return (
      <div ref={tallFrameRef} className={`relative ${HERO_TALL} overflow-hidden bg-ink ${HERO_EDGE}`}>
        <img src={src} alt="" aria-hidden className="absolute inset-0 h-full w-full scale-125 object-cover opacity-40 blur-xl" />
        <PictureNotYet loaded={pixel.loaded} />
        <img
          ref={imgRef}
          src={src}
          alt={alt}
          className="relative mx-auto h-full object-contain"
          style={pixel.active ? { opacity: 0 } : undefined}
          loading="lazy"
          decoding="async"
          onLoad={pixel.onLoad}
          onError={onError}
        />
        {pixel.active && <PixelCanvas canvasRef={pixel.canvasRef} />}
      </div>
    );
  }

  return (
    <div ref={crop.frameRef} className={`relative ${HERO_STANDARD} overflow-hidden bg-fill ${HERO_EDGE}`}>
      <PictureNotYet loaded={pixel.loaded} />
      <img
        ref={imgRef}
        src={src}
        alt={alt}
        className="relative h-full w-full object-cover"
        style={pixel.active ? { ...crop.style, opacity: 0 } : crop.style}
        loading="lazy"
        decoding="async"
        crossOrigin="anonymous"
        onLoad={handleLoad}
        onError={onError}
      />
      {pixel.active && <PixelCanvas canvasRef={pixel.canvasRef} />}
    </div>
  );
};

/** The square ink play mark laid over video stills */
const PlayMark = ({ size = 'md' }: { size?: 'md' | 'lg' }) => (
  <span
    aria-hidden
    className={`absolute left-1/2 top-1/2 grid -translate-x-1/2 -translate-y-1/2 place-items-center bg-ink text-white ${
      size === 'lg' ? 'h-12 w-12' : 'h-11 w-11'
    }`}
  >
    <Play className="ml-0.5 h-[18px] w-[18px] fill-current" />
  </span>
);

interface LinkCoverProps extends ResolveProps {
  imageSource: string;
  alt: string;
  /** Portrait-first treatments (short-form video, book covers) */
  tall?: boolean;
  playOverlay?: boolean;
  onFailed: () => void;
}

/**
 * Link preview image with the storage/proxy fallback chain: external URLs that fail to
 * hotlink retry once through the image-proxy edge function, then hand control back so the
 * hero can fall back to the placeholder.
 */
export const LinkCover = ({ imageSource, alt, tall, playOverlay, onFailed, reading = false, arriving = false }: LinkCoverProps) => {
  const [src, setSrc] = useState(imageSource);
  const [triedProxy, setTriedProxy] = useState(imageSource.includes('/functions/v1/image-proxy'));
  const crop = useSubjectCrop();
  const tallFrameRef = useRef<HTMLDivElement>(null);
  const imgRef = useRef<HTMLImageElement>(null);
  const pixel = usePixelImage({ frameRef: tall ? tallFrameRef : crop.frameRef, imgRef, reading, arriving });

  const handleError = () => {
    if (!triedProxy) {
      setTriedProxy(true);
      setSrc(`${SUPABASE_URL}/functions/v1/image-proxy?url=${encodeURIComponent(imageSource)}`);
      return;
    }
    onFailed();
  };

  if (tall) {
    return (
      <div ref={tallFrameRef} className={`relative ${HERO_TALL} overflow-hidden bg-ink ${HERO_EDGE}`}>
        <img src={src} alt="" aria-hidden className="absolute inset-0 h-full w-full scale-125 object-cover opacity-40 blur-xl" referrerPolicy="no-referrer" />
        <PictureNotYet loaded={pixel.loaded} />
        <img
          ref={imgRef}
          src={src}
          alt={alt}
          className="relative mx-auto h-full object-contain"
          style={pixel.active ? { opacity: 0 } : undefined}
          loading="lazy"
          decoding="async"
          referrerPolicy="no-referrer"
          onLoad={pixel.onLoad}
          onError={handleError}
        />
        {pixel.active && <PixelCanvas canvasRef={pixel.canvasRef} />}
        {playOverlay && <PlayMark size="lg" />}
      </div>
    );
  }

  return (
    <div ref={crop.frameRef} className={`relative ${HERO_STANDARD} overflow-hidden bg-fill ${HERO_EDGE}`}>
      <PictureNotYet loaded={pixel.loaded} />
      <img
        ref={imgRef}
        src={src}
        alt={alt}
        className="relative h-full w-full object-cover"
        style={pixel.active ? { ...crop.style, opacity: 0 } : crop.style}
        loading="lazy"
        decoding="async"
        crossOrigin="anonymous"
        referrerPolicy="no-referrer"
        onLoad={(event) => {
          crop.onLoad(event);
          pixel.onLoad();
        }}
        onError={handleError}
      />
      {pixel.active && <PixelCanvas canvasRef={pixel.canvasRef} />}
      {playOverlay && <PlayMark />}
    </div>
  );
};

/** GitHub/GitLab repos: the repo path IS the imagery, set like a terminal line */
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
    <div className={`flex min-h-[120px] flex-col justify-end gap-2 bg-ink px-5 pb-5 pt-12 text-white ${HERO_EDGE}`}>
      <p className="flex min-w-0 items-baseline gap-[1ch] font-pixel text-pixel-md">
        <span aria-hidden className="text-spot-on-ink">&gt;</span>
        {owner && repo ? (
          <span className="truncate">
            {owner}
            <span className="text-white/45">/</span>
            {repo}
          </span>
        ) : (
          <span className="truncate">{domainOfUrl(url)}</span>
        )}
      </p>
      {description && <p className="line-clamp-2 text-[13px] leading-snug text-white/65">{description}</p>}
    </div>
  );
};

/**
 * A save with no picture of its own (or whose picture failed): Stash draws one for the kind of
 * thing it is (DESIGN-v2 "Placeholders"): a 14×14 pixel glyph on the dotted field, and a black
 * label with the domain. Says honestly that the preview is limited. No favicon here: fetching
 * one per card would send the domains of the person's saves to a third party on every load.
 * While Stash reads, the glyph boils (a picture may yet come); it settles when Stash is done.
 */
export const LinkPlaceholder = ({ url, glyph, reading = false }: { url: string; glyph: GlyphName; reading?: boolean }) => {
  const domain = domainOfUrl(url);
  const boil = useBoil(reading);

  return (
    <MediaField className={`${HERO_STANDARD} flex flex-col items-center justify-center gap-3 text-ink`}>
      <PixelGlyph name={glyph} className="h-12 w-12" boil={boil} />
      <span className="inline-flex max-w-[86%] items-center bg-ink px-1.5 pb-[3px] pt-1 font-pixel text-pixel leading-none text-white">
        <span className="truncate">{domain || 'link'}</span>
      </span>
      {/* Only once Stash has finished looking: while it reads, a picture may still come */}
      {!reading && <span className="font-pixel text-pixel text-muted-foreground">preview limited, saved anyway</span>}
    </MediaField>
  );
};

/* ── audio: the player IS the hero ─────────────────────────────────────── */

/**
 * Audio hero: a square ink play button and the waveform in ink on the dotted field. Voice
 * notes get the full-height player; long recordings compress. Waveform bars are deterministic
 * from the item id until real amplitudes are sampled; played bars are solid, unplayed at .25.
 * While Stash transcribes, the bars jitter like a level meter listening, then settle.
 */
export const PlayerHero = ({
  itemId,
  src,
  kind,
  durationS,
  reading = false,
}: {
  itemId: string;
  src: string;
  kind: 'voice_note' | 'recording';
  durationS?: number | null;
  reading?: boolean;
}) => {
  const boil = useBoil(reading);
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
  const heights = boiledHeights(waveformHeights(itemId, 28), boil.amount, boil.beat);
  const progress = duration > 0 ? currentTime / duration : 0;
  const timeLabel =
    formatDurationChip(isPlaying || currentTime > 0 ? currentTime : duration) ?? '0:00';

  return (
    <MediaField dots={false} className={`flex items-center gap-4 px-5 ${voice ? 'h-[116px]' : 'h-24'}`}>
      <audio ref={audioRef} src={src} preload="metadata" />
      <button
        type="button"
        onClick={togglePlay}
        aria-label={isPlaying ? 'Pause' : 'Play'}
        className={`relative z-[1] grid flex-none place-items-center bg-ink text-white transition-transform active:translate-y-px ${
          voice ? 'h-11 w-11' : 'h-10 w-10'
        }`}
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
            className="min-w-[2px] flex-1 bg-ink"
            style={{
              height: `${height}%`,
              opacity: index / heights.length < progress ? 1 : 0.25,
            }}
          />
        ))}
      </div>
      <span className="relative z-[1] font-pixel text-pixel tabular-nums text-ink">{timeLabel}</span>
    </MediaField>
  );
};

/* ── documents: a page on the dotted field ─────────────────────────────── */

/**
 * Document hero (DESIGN-v2 `.ph-doc`): a white page, turned a little on the dotted field (its
 * format is the card's kind tag). A real rendered first page can slot into the page later
 * without changing the card. While Stash reads the PDF, the page's lines flicker as if being
 * read off it, then settle.
 */
const DOC_LINES = [100, 84, 100, 62, 100, 76, 100];

export const DocumentHero = ({ ext, reading = false }: { ext?: string | null; reading?: boolean }) => {
  const spreadsheet = isSpreadsheetExt(ext);
  const boil = useBoil(reading);
  const line = (width: number, index: number) => (
    <span key={index} className="block h-1 bg-[#dcded8]" style={{ width: `${boiledWidth(width, index, boil.amount, boil.beat)}%` }} />
  );

  return (
    <MediaField className={`${HERO_STANDARD} flex items-end justify-center`}>
      <div className="relative -mb-6 flex h-[148px] w-[112px] -rotate-[2.5deg] flex-col gap-[6px] bg-white px-3 py-3.5 shadow-[0_1px_0_rgba(0,0,0,0.08),0_16px_30px_-12px_rgba(0,0,0,0.45)]">
        <span className="mb-1 block h-[6px] w-[70%] bg-ink/80" />
        {spreadsheet
          ? [0, 1, 2, 3].map((row) => (
              <span key={row} className="flex gap-1">
                {[0, 1, 2].map((col) => line(100, row * 3 + col))}
              </span>
            ))
          : DOC_LINES.map((width, index) => line(width, index))}
      </div>
    </MediaField>
  );
};

/* ── video uploads: poster frame, not native chrome ────────────────────── */

/**
 * Video hero at rest: first frame (preload=metadata), the square play mark, duration as a
 * black tag; no native controls until playback starts.
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
    <div className={`relative ${HERO_STANDARD} w-full overflow-hidden bg-ink ${HERO_EDGE}`}>
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
          <button
            type="button"
            onClick={handlePlay}
            aria-label="Play"
            className="absolute left-1/2 top-1/2 grid h-12 w-12 -translate-x-1/2 -translate-y-1/2 place-items-center bg-ink text-white transition-colors hover:bg-ink-soft"
          >
            <Play className="ml-0.5 h-[18px] w-[18px] fill-current" />
          </button>
          {duration && (
            <Tag className="pointer-events-none absolute bottom-2.5 right-2.5 tabular-nums">{duration}</Tag>
          )}
        </>
      )}
      {onExpand && (
        <div className="absolute right-2.5 top-2.5 opacity-0 transition-opacity duration-200 group-hover:opacity-100">
          <button
            type="button"
            onClick={(event) => {
              event.stopPropagation();
              onExpand();
            }}
            aria-label="Expand video"
            className="grid h-8 w-8 place-items-center bg-ink text-white hover:bg-ink-soft"
          >
            <Expand className="h-4 w-4" />
          </button>
        </div>
      )}
    </div>
  );
};

/** Imageless media (an image whose file is missing): the placeholder, named by its file */
export const FilePlate = ({
  fileName,
  factsLine,
  kind,
}: {
  fileName?: string | null;
  factsLine?: string | null;
  kind: 'document' | 'image';
}) => (
  <MediaField className={`${HERO_STANDARD} flex flex-col items-center justify-center gap-3 text-ink`}>
    <PixelGlyph name={kind === 'image' ? 'photo' : 'page'} className="h-12 w-12" />
    <span className="inline-flex max-w-[86%] items-center bg-ink px-1.5 pb-[3px] pt-1 font-pixel text-pixel leading-none text-white">
      <span className="truncate">{fileName || (kind === 'image' ? 'image' : 'document')}</span>
    </span>
    {factsLine && <span className="font-pixel text-pixel text-muted-foreground">{factsLine.toLowerCase()}</span>}
  </MediaField>
);
