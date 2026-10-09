/** A YouTube video id is always eleven characters of this alphabet. */
export const YOUTUBE_ID_PATTERN = /^[A-Za-z0-9_-]{11}$/;

/**
 * The video id in a YouTube address (`watch?v=`, `youtu.be/`, `/shorts/`, `/embed/`, `/live/`),
 * or null — including while the address is still being typed and the id is incomplete. Before
 * 2026-10-09 any partial id counted, so the composer's chip fetched a thumbnail for every
 * keystroke of the id and the console filled with 404s.
 */
export const getYouTubeVideoId = (url: string): string | null => {
  let parsed: URL;
  try {
    parsed = new URL(url);
  } catch {
    return null;
  }
  const host = parsed.hostname.toLowerCase();
  if (!host.includes('youtube.com') && !host.includes('youtu.be')) return null;

  let candidate: string | null = null;
  if (host.includes('youtu.be')) {
    candidate = parsed.pathname.split('/').filter(Boolean)[0] || null;
  } else {
    candidate = parsed.searchParams.get('v');
    if (!candidate) {
      const segments = parsed.pathname.split('/').filter(Boolean);
      const markerIndex = segments.findIndex((segment) => ['embed', 'shorts', 'live'].includes(segment));
      if (markerIndex !== -1 && segments[markerIndex + 1]) candidate = segments[markerIndex + 1];
    }
  }
  return candidate && YOUTUBE_ID_PATTERN.test(candidate) ? candidate : null;
};
