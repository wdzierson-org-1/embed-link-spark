import { useEffect } from 'react';
import Landing from '@/pages/Landing';

/**
 * gostash.it/ is the static marketing site (scripts/publish-site.mjs, placed at / by
 * scripts/place-site-home.mjs), so the app never draws "/" itself: an in-app link or redirect to
 * "/" (the wordmark, signing out, an anonymous visitor bounced from /home) reloads into it. In dev
 * the published copy is served from public/ at /site/home.html.
 *
 * If the app was booted at "/" in production, the server handed it the page the static site should
 * have answered with; reloading would loop, so it shows the old landing page instead.
 */
const BOOT_PATH = typeof window === 'undefined' ? '/' : window.location.pathname;

export const siteHomeTarget = ({ dev, bootPath }: { dev: boolean; bootPath: string }): string | null => {
  if (dev) return '/site/home.html';
  return bootPath === '/' ? null : '/';
};

const SiteHome = () => {
  const target = siteHomeTarget({ dev: import.meta.env.DEV, bootPath: BOOT_PATH });

  useEffect(() => {
    if (target) window.location.replace(target);
  }, [target]);

  return target ? null : <Landing />;
};

export default SiteHome;
