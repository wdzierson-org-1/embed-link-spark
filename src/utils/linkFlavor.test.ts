import { classifyLinkFlavor, domainOfUrl } from './linkFlavor';

describe('classifyLinkFlavor', () => {
  it('classifies repos, not GitHub product pages', () => {
    expect(classifyLinkFlavor('https://github.com/pmndrs/zustand')).toBe('repo');
    expect(classifyLinkFlavor('https://gitlab.com/gitlab-org/gitlab')).toBe('repo');
    expect(classifyLinkFlavor('https://github.com/features/copilot')).toBe('generic');
    expect(classifyLinkFlavor('https://github.com/pricing')).toBe('generic');
  });

  it('classifies short-form and long-form video hosts', () => {
    expect(classifyLinkFlavor('https://www.tiktok.com/@tokyoeats/video/7241')).toBe('video');
    expect(classifyLinkFlavor('https://youtu.be/MPTNHrq_4LU')).toBe('video');
    expect(classifyLinkFlavor('https://www.youtube.com/watch?v=abc')).toBe('video');
    expect(classifyLinkFlavor('https://www.instagram.com/reel/xyz/')).toBe('video');
    expect(classifyLinkFlavor('https://www.instagram.com/someuser/')).toBe('generic');
  });

  it('classifies books', () => {
    expect(classifyLinkFlavor('https://bookshop.org/p/books/the-extended-mind')).toBe('book');
    expect(classifyLinkFlavor('https://www.amazon.com/dp/B08XYZ')).toBe('book');
    expect(classifyLinkFlavor('https://www.amazon.com/gp/help/customer')).toBe('generic');
  });

  it('classifies social posts and known article hosts', () => {
    expect(classifyLinkFlavor('https://x.com/someone/status/123')).toBe('social');
    expect(classifyLinkFlavor('https://bsky.app/profile/a.bsky.social/post/xyz')).toBe('social');
    expect(classifyLinkFlavor('https://medium.com/@kenji/five-days-in-tokyo')).toBe('article');
    expect(classifyLinkFlavor('https://stratechery.substack.com/p/some-post')).toBe('article');
  });

  it('falls back to generic', () => {
    expect(classifyLinkFlavor('https://example.com/whatever')).toBe('generic');
    expect(classifyLinkFlavor('not a url')).toBe('generic');
  });
});

describe('domainOfUrl', () => {
  it('strips www and handles bad input', () => {
    expect(domainOfUrl('https://www.jean-georges.com/menus')).toBe('jean-georges.com');
    expect(domainOfUrl('nope')).toBe('');
    expect(domainOfUrl(undefined)).toBe('');
  });
});
