import { siteHomeTarget } from './SiteHome';

describe('siteHomeTarget', () => {
  it('reloads into the static homepage from anywhere in the app, in production', () => {
    expect(siteHomeTarget({ dev: false, bootPath: '/auth' })).toBe('/');
    expect(siteHomeTarget({ dev: false, bootPath: '/home' })).toBe('/');
  });

  it('never loops: booted at "/" in production means the static site is missing, so it stays', () => {
    expect(siteHomeTarget({ dev: false, bootPath: '/' })).toBeNull();
  });

  it('opens the published copy in dev, where vite serves the app at "/"', () => {
    expect(siteHomeTarget({ dev: true, bootPath: '/' })).toBe('/site/home.html');
  });
});
