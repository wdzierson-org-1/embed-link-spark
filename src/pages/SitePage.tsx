import { useEffect } from 'react';

/**
 * Contact, terms and privacy are static pages of the marketing site (scripts/publish-site.mjs
 * writes them to public/<page>/index.html, which the server answers with before the app's
 * catch-all), so the app never draws them itself: an in-app link to "/privacy" reloads into the
 * static page. In dev the published copy is served from public/ at /<page>/index.html.
 *
 * If the app was booted at one of these paths in production, the server handed it the page the
 * static site should have answered with; reloading would loop, so it says so instead.
 */
export const SITE_PAGES = { contact: '/contact', terms: '/terms', privacy: '/privacy' } as const;
export type SitePageName = keyof typeof SITE_PAGES;

const BOOT_PATH = typeof window === 'undefined' ? '/' : window.location.pathname;

export const sitePageTarget = ({ dev, bootPath, page }: { dev: boolean; bootPath: string; page: SitePageName }): string | null => {
  const url = SITE_PAGES[page];
  if (dev) return `${url}/index.html`;
  return bootPath === url ? null : url;
};

const SitePage = ({ page }: { page: SitePageName }) => {
  const target = sitePageTarget({ dev: import.meta.env.DEV, bootPath: BOOT_PATH, page });

  useEffect(() => {
    if (target) window.location.replace(target);
  }, [target]);

  if (target) return null;
  return (
    <main className="flex min-h-screen items-center justify-center p-6 font-montreal text-muted-foreground">
      <p>
        This page didn’t load. Email <a href="mailto:hello@gostash.it" className="underline">hello@gostash.it</a> and we’ll send it to you.
      </p>
    </main>
  );
};

export default SitePage;
