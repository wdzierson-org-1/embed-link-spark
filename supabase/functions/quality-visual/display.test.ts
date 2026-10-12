import { describe, expect, it } from 'vitest';
import { createClient } from '@supabase/supabase-js';
import { embedSourceFor } from '../../../src/utils/embeds';
import { resolveVisualSurfaces, type VisualItem } from './display';

const base = 'https://project.supabase.co';
const item: VisualItem = { id: 'item', user_id: 'owner', type: 'link', url: 'https://example.com/article' };

describe('resolveVisualSurfaces', () => {
  it('checks the actual card proxy and direct detail image separately', () => {
    const image = 'https://cdn.example.com/cover.jpg?width=1024&name=hello%20world';
    expect(resolveVisualSurfaces({ ...item, file_path: image }, base)).toEqual([
      { surface: 'card', mode: 'image', source_url: image, display_url: `${base}/functions/v1/image-proxy?url=${encodeURIComponent(image)}` },
      { surface: 'detail', mode: 'image', source_url: image, display_url: image },
    ]);
  });

  it('matches the storage SDK encoding for existing paths, including Unicode and escaped bytes', () => {
    const path = 'owner/previews/a café %20 picture.jpg';
    const expected = createClient(base, 'public-test-key').storage.from('stash-media').getPublicUrl(path).data.publicUrl;
    expect(resolveVisualSurfaces({ ...item, file_path: path }, `${base}/`)).toEqual([
      { surface: 'card', mode: 'image', source_url: expected, display_url: expected },
      { surface: 'detail', mode: 'image', source_url: expected, display_url: expected },
    ]);
  });

  it('does not misreport a repository plate as a missing image', () => {
    const surfaces = resolveVisualSurfaces({ ...item, file_path: 'owner/cover.jpg', attributes: { link: { flavor: 'repo' } } }, base);
    expect(surfaces[0]).toEqual({ surface: 'card', mode: 'generated', reason: 'repository_plate' });
    expect(surfaces[1]).toMatchObject({ surface: 'detail', mode: 'image' });
  });

  it.each([
    'https://youtu.be/jNQXAC9IVRw',
    'https://www.youtube.com/shorts/dQw4w9WgXcQ',
    'https://www.youtube.com/live/jNQXAC9IVRw',
    'https://player.vimeo.com/video/123456789',
    'https://www.loom.com/share/0123456789abcdef0123456789abcdef',
    'https://www.tiktok.com/@scout2015/video/6718335390845095173',
    'https://www.instagram.com/reels/C1a2B3c4D5e/',
    'https://docs.google.com/presentation/d/1AbCdEfG/edit#slide=id.p',
    'https://www.figma.com/slides/abc123/Deck?node-id=1',
  ])('uses the same detail embed as the web UI for %s', url => {
    const value = { ...item, url, file_path: 'owner/cover.jpg' };
    expect(resolveVisualSurfaces(value, base)[1]).toEqual({
      surface: 'detail', mode: 'embed', source_url: url,
      display_url: embedSourceFor(value)?.src, reason: 'embedded_content',
    });
    expect(resolveVisualSurfaces(value, base)[0].mode).toBe('image');
  });

  it('uses the same canonical URL precedence as the web UI', () => {
    const value = { ...item, url: 'https://www.tiktok.com/t/short/', attributes: {
      link: { canonical_url: 'https://youtu.be/jNQXAC9IVRw' },
      enrichment: { evidence: { canonical_url: 'https://vimeo.com/123456789' } },
    } };
    expect(resolveVisualSurfaces(value, base)[1]).toMatchObject({ mode: 'embed', display_url: embedSourceFor(value)?.src });
    delete value.attributes.link.canonical_url;
    expect(resolveVisualSurfaces(value, base)[1]).toMatchObject({ mode: 'embed', display_url: embedSourceFor(value)?.src });
  });

  it('keeps an ordinary article image even if its text contains a YouTube video', () => {
    const value = { ...item, url: 'https://community.openai.com/t/decisions-api/1403877', file_path: 'owner/cover.jpeg', attributes: { link: { flavor: 'video' } } };
    expect(resolveVisualSurfaces(value, base).map(s => s.mode)).toEqual(['image', 'image']);
  });

  it('distinguishes missing images from intentionally unsupported object types', () => {
    expect(resolveVisualSurfaces(item, base)).toEqual([
      { surface: 'card', mode: 'missing', reason: 'no_preview_image' },
      { surface: 'detail', mode: 'missing', reason: 'no_preview_image' },
    ]);
    for (const type of ['image', 'document', 'video', 'audio', 'text', 'collection']) {
      expect(resolveVisualSurfaces({ ...item, type }, base)).toEqual([
        { surface: 'card', mode: 'unsupported', reason: 'object_type_not_monitored' },
        { surface: 'detail', mode: 'unsupported', reason: 'object_type_not_monitored' },
      ]);
    }
  });

  it('does not claim a cover appears on a card whose link URL is absent', () => {
    const surfaces = resolveVisualSurfaces({ ...item, url: null, file_path: 'owner/cover.jpg' }, base);
    expect(surfaces[0]).toEqual({ surface: 'card', mode: 'missing', reason: 'link_url_missing' });
    expect(surfaces[1].mode).toBe('image');
  });
});
