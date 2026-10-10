import { getYouTubeVideoId } from '@/utils/youtube';

/**
 * Playable embeds for links (DESIGN-v2 §12.8; docs/ui-changes.md 2026-10-10): the providers whose
 * players may be framed, and the frame address for a saved URL. Anything else keeps its picture.
 * A `clock` provider can report playback time and seek (timestamped notes).
 */
export type EmbedProvider = 'youtube' | 'vimeo' | 'loom' | 'tiktok' | 'instagram' | 'google-slides' | 'figma';

export interface Embed {
  provider: EmbedProvider;
  src: string;
  /** Width over height of the player */
  aspect: number;
  /** A phone-shaped player (TikTok, Reels, Shorts) sits centred at phone width */
  portrait: boolean;
  /** For the frame's title and the machine's tooltips */
  label: string;
  clock?: 'youtube';
}

const LANDSCAPE = 16 / 9;
const PORTRAIT = 9 / 16;

const parse = (url: string): URL | null => {
  try {
    return new URL(url);
  } catch {
    return null;
  }
};

const hostOf = (parsed: URL): string => parsed.hostname.toLowerCase().replace(/^www\./, '');
const segmentsOf = (parsed: URL): string[] => parsed.pathname.split('/').filter(Boolean);

export const embedFor = (url: string | null | undefined): Embed | null => {
  if (!url) return null;
  const parsed = parse(url);
  if (!parsed) return null;
  const host = hostOf(parsed);
  const segments = segmentsOf(parsed);

  const youtubeId = getYouTubeVideoId(url);
  if (youtubeId) {
    const short = /(^|\.)youtube\.com$/.test(host) && segments[0] === 'shorts';
    return {
      provider: 'youtube',
      src: `https://www.youtube-nocookie.com/embed/${youtubeId}?rel=0&enablejsapi=1`,
      aspect: short ? PORTRAIT : LANDSCAPE,
      portrait: short,
      label: 'YouTube video',
      clock: 'youtube',
    };
  }

  if (host === 'vimeo.com' || host === 'player.vimeo.com') {
    const id = segments.find((segment) => /^\d{6,}$/.test(segment));
    if (id) return { provider: 'vimeo', src: `https://player.vimeo.com/video/${id}`, aspect: LANDSCAPE, portrait: false, label: 'Vimeo video' };
    return null;
  }

  if (host === 'loom.com') {
    if ((segments[0] === 'share' || segments[0] === 'embed') && /^[a-f0-9]{20,}$/i.test(segments[1] ?? '')) {
      return { provider: 'loom', src: `https://www.loom.com/embed/${segments[1]}`, aspect: LANDSCAPE, portrait: false, label: 'Loom video' };
    }
    return null;
  }

  if (host === 'tiktok.com' || host.endsWith('.tiktok.com')) {
    // Only the long form carries the video id; vm.tiktok.com / tiktok.com/t/ short links don't
    const at = segments.findIndex((segment) => segment === 'video');
    const id = at >= 0 ? segments[at + 1] : undefined;
    if (id && /^\d{10,}$/.test(id)) {
      return { provider: 'tiktok', src: `https://www.tiktok.com/embed/v2/${id}`, aspect: PORTRAIT, portrait: true, label: 'TikTok video' };
    }
    return null;
  }

  if (host === 'instagram.com') {
    const kind = segments[0];
    const code = segments[1];
    if (kind && code && ['reel', 'reels', 'p', 'tv'].includes(kind) && /^[A-Za-z0-9_-]{5,}$/.test(code)) {
      const path = kind === 'reels' ? 'reel' : kind;
      return {
        provider: 'instagram',
        src: `https://www.instagram.com/${path}/${code}/embed/`,
        aspect: PORTRAIT,
        portrait: true,
        label: path === 'p' ? 'Instagram post' : 'Instagram reel',
      };
    }
    return null;
  }

  if (host === 'docs.google.com' && segments[0] === 'presentation' && segments[1] === 'd' && segments[2]) {
    return {
      provider: 'google-slides',
      src: `https://docs.google.com/presentation/d/${segments[2]}/embed?start=false&loop=false`,
      aspect: LANDSCAPE,
      portrait: false,
      label: 'Google Slides deck',
    };
  }

  if (host === 'figma.com' && ['file', 'design', 'proto', 'slides', 'board', 'deck'].includes(segments[0] ?? '')) {
    return {
      provider: 'figma',
      src: `https://www.figma.com/embed?embed_host=stash&url=${encodeURIComponent(url)}`,
      aspect: LANDSCAPE,
      portrait: false,
      label: segments[0] === 'slides' || segments[0] === 'deck' ? 'Figma slides' : 'Figma file',
    };
  }

  return null;
};
