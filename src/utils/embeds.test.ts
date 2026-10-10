import { embedFor, embedSourceFor } from './embeds';

describe('embedSourceFor', () => {
  it('plays a share short link from the canonical address add-url resolved', () => {
    const saved = { url: 'https://www.tiktok.com/t/ZPLrLoSvK/', attributes: { link: { flavor: 'video' as const, canonical_url: 'https://www.tiktok.com/@geodesaurus/video/7681109031196364045' } } };
    expect(embedSourceFor(saved)?.src).toBe('https://www.tiktok.com/embed/v2/7681109031196364045');
    expect(embedSourceFor({ url: 'https://www.tiktok.com/t/ZPLrLoSvK/', attributes: { link: { flavor: 'video' as const } } })).toBeNull();
    // Enrichment's evidence carries the same fact for saves that never passed through add-url
    expect(
      embedSourceFor({
        url: 'https://www.tiktok.com/t/ZPLrNFtXt/',
        attributes: { link: { flavor: 'video' as const }, enrichment: { status: 'complete' as const, updated_at: 'x', evidence: { canonical_url: 'https://www.tiktok.com/@theronanfarrow/video/7693569444299246861' } } },
      })?.src,
    ).toBe('https://www.tiktok.com/embed/v2/7693569444299246861');
    expect(embedSourceFor({ url: 'https://www.youtube.com/watch?v=jNQXAC9IVRw', attributes: null })?.provider).toBe('youtube');
  });
});

describe('embedFor', () => {
  it('frames YouTube through the no-cookie player, with the time API on', () => {
    const embed = embedFor('https://www.youtube.com/watch?v=jNQXAC9IVRw&t=4s');
    expect(embed).toMatchObject({ provider: 'youtube', portrait: false, clock: 'youtube' });
    expect(embed?.src).toBe('https://www.youtube-nocookie.com/embed/jNQXAC9IVRw?rel=0&enablejsapi=1');
    expect(embedFor('https://youtu.be/s4skNgV8nJM?si=abc')?.src).toContain('/embed/s4skNgV8nJM');
    expect(embedFor('https://www.youtube.com/shorts/dQw4w9WgXcQ')).toMatchObject({ provider: 'youtube', portrait: true });
  });

  it('knows Vimeo and Loom', () => {
    expect(embedFor('https://vimeo.com/123456789')?.src).toBe('https://player.vimeo.com/video/123456789');
    expect(embedFor('https://www.loom.com/share/0123456789abcdef0123456789abcdef')?.src).toBe('https://www.loom.com/embed/0123456789abcdef0123456789abcdef');
    expect(embedFor('https://www.loom.com/')).toBeNull();
  });

  it('frames TikTok videos by id, never the short links that hide it', () => {
    expect(embedFor('https://www.tiktok.com/@scout2015/video/6718335390845095173')).toMatchObject({
      provider: 'tiktok',
      portrait: true,
      src: 'https://www.tiktok.com/embed/v2/6718335390845095173',
    });
    expect(embedFor('https://vm.tiktok.com/ZMabc123/')).toBeNull();
    expect(embedFor('https://www.tiktok.com/t/ZTabc123/')).toBeNull();
    expect(embedFor('https://www.tiktok.com/@scout2015')).toBeNull();
  });

  it('frames Instagram reels and posts through the embed path', () => {
    expect(embedFor('https://www.instagram.com/reel/C1a2B3c4D5e/?igsh=x')?.src).toBe('https://www.instagram.com/reel/C1a2B3c4D5e/embed/');
    expect(embedFor('https://www.instagram.com/reels/C1a2B3c4D5e/')?.src).toBe('https://www.instagram.com/reel/C1a2B3c4D5e/embed/');
    expect(embedFor('https://www.instagram.com/p/C1a2B3c4D5e/')).toMatchObject({ label: 'Instagram post', portrait: true });
    expect(embedFor('https://www.instagram.com/someone/')).toBeNull();
  });

  it('frames web slide decks: Google Slides and Figma', () => {
    expect(embedFor('https://docs.google.com/presentation/d/1AbCdEfG/edit#slide=id.p')?.src).toBe(
      'https://docs.google.com/presentation/d/1AbCdEfG/embed?start=false&loop=false',
    );
    expect(embedFor('https://www.figma.com/slides/abc123/Deck?node-id=1')?.src).toContain('figma.com/embed?embed_host=stash&url=');
    expect(embedFor('https://www.figma.com/')).toBeNull();
  });

  it('has no frame for ordinary links, broken addresses or nothing', () => {
    expect(embedFor('https://example.com/article')).toBeNull();
    expect(embedFor('not a url')).toBeNull();
    expect(embedFor(null)).toBeNull();
  });
});
