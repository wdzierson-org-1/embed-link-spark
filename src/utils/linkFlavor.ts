import type { LinkFlavor } from '@/types/itemAttributes';

/**
 * Classify a link by URL alone — cheap, synchronous, done once at save time
 * and stored in attributes.link.flavor. Cards switch renderers on it; future
 * enrichment (oEmbed, source APIs) can refine the same blob with author,
 * duration, stars, read time.
 */

// github.com/<first-segment> paths that are product pages, not repos
const GITHUB_NON_REPO_ROOTS = new Set([
  'features', 'pricing', 'topics', 'collections', 'orgs', 'settings',
  'marketplace', 'sponsors', 'about', 'blog', 'explore', 'trending',
  'issues', 'pulls', 'notifications', 'search', 'login', 'join', 'apps',
  'enterprise', 'customer-stories', 'readme', 'new', 'codespaces',
]);

const VIDEO_HOSTS = ['tiktok.com', 'youtube.com', 'youtu.be', 'vimeo.com', 'twitch.tv', 'loom.com'];
const SOCIAL_HOSTS = ['twitter.com', 'x.com', 'threads.net', 'bsky.app'];
const ARTICLE_HOSTS = ['medium.com', 'substack.com', 'dev.to', 'nytimes.com', 'theatlantic.com', 'newyorker.com', 'wired.com'];
const BOOK_HOSTS = ['bookshop.org', 'goodreads.com'];

export const classifyLinkFlavor = (url: string): LinkFlavor => {
  let parsed: URL;
  try {
    parsed = new URL(url);
  } catch {
    return 'generic';
  }

  const host = parsed.hostname.toLowerCase().replace(/^www\./, '');
  const segments = parsed.pathname.split('/').filter(Boolean);
  const hostMatches = (candidates: string[]) =>
    candidates.some((candidate) => host === candidate || host.endsWith(`.${candidate}`));

  if (host === 'github.com' || host === 'gitlab.com') {
    if (segments.length >= 2 && !GITHUB_NON_REPO_ROOTS.has(segments[0])) return 'repo';
    return 'generic';
  }

  if (hostMatches(VIDEO_HOSTS)) return 'video';
  if (host.endsWith('instagram.com') && segments[0] && ['reel', 'reels', 'tv'].includes(segments[0])) return 'video';

  if (hostMatches(BOOK_HOSTS)) return 'book';
  if (host.startsWith('amazon.') || host.includes('.amazon.')) {
    if (parsed.pathname.includes('/dp/') || parsed.pathname.includes('/gp/product/')) return 'book';
    return 'generic';
  }

  if (hostMatches(SOCIAL_HOSTS)) return 'social';
  if (hostMatches(ARTICLE_HOSTS)) return 'article';

  return 'generic';
};

export const domainOfUrl = (url?: string | null): string => {
  if (!url) return '';
  try {
    return new URL(url).hostname.replace(/^www\./, '');
  } catch {
    return '';
  }
};
