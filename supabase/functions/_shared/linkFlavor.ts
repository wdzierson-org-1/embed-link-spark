/**
 * Classify a link by URL alone — cheap, synchronous, done once at save time
 * and stored in attributes.link.flavor. Cards switch renderers on it; future
 * enrichment (oEmbed, source APIs) can refine the same blob with author,
 * duration, stars, read time.
 *
 * Ported verbatim from src/utils/linkFlavor.ts:1-54 (host lists + rules
 * byte-faithful) — only the type import is replaced with a local declaration
 * so this module has no dependency on the web app's src tree.
 */

export type LinkFlavor = 'article' | 'video' | 'repo' | 'book' | 'social' | 'generic';

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
