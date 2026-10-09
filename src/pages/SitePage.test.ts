import { sitePageTarget } from './SitePage';

describe('sitePageTarget', () => {
  it('reloads into the static page from anywhere in the app, in production', () => {
    expect(sitePageTarget({ dev: false, bootPath: '/auth', page: 'privacy' })).toBe('/privacy');
    expect(sitePageTarget({ dev: false, bootPath: '/home', page: 'terms' })).toBe('/terms');
    expect(sitePageTarget({ dev: false, bootPath: '/', page: 'contact' })).toBe('/contact');
  });

  it('never loops: booted at the page in production means the static file is missing, so it stays', () => {
    expect(sitePageTarget({ dev: false, bootPath: '/privacy', page: 'privacy' })).toBeNull();
    expect(sitePageTarget({ dev: false, bootPath: '/terms', page: 'terms' })).toBeNull();
  });

  it('opens the published copy in dev, where vite serves the app at every path', () => {
    expect(sitePageTarget({ dev: true, bootPath: '/privacy', page: 'privacy' })).toBe('/privacy/index.html');
  });
});
