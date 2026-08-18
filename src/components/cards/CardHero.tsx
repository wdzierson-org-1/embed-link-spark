import React, { useState } from 'react';
import { FileText, Github, Image as ImageIcon, Link2, Play } from 'lucide-react';
import { SUPABASE_URL } from '@/integrations/supabase/client';
import { domainOfUrl } from '@/utils/linkFlavor';
import { HERO_STANDARD, HERO_TALL } from '@/components/cards/CardBits';

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
