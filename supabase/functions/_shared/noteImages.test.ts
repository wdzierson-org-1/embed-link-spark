// @vitest-environment node
import { describe, expect, it } from 'vitest';
import { noteImageSources, noteImagesSearchText, readNoteImages, reconcileNoteImages } from './noteImages.ts';

const doc = (content: unknown[]) => JSON.stringify({ type: 'doc', content });
const image = (src: string) => ({ type: 'image', attrs: { src, alt: null, title: null } });
const para = (text: string) => ({ type: 'paragraph', content: [{ type: 'text', text }] });

describe('noteImageSources', () => {
  it('lists the pictures of a note in order, each once, web addresses only', () => {
    const content = doc([
      image('https://x.supabase.co/storage/v1/object/public/stash-media/u/notes/a.png'),
      para('image + text using / command'),
      { type: 'bulletList', content: [{ type: 'listItem', content: [image('https://x.supabase.co/b.jpg')] }] },
      image('https://x.supabase.co/storage/v1/object/public/stash-media/u/notes/a.png'),
      image('data:image/png;base64,AAAA'),
    ]);
    expect(noteImageSources(content)).toEqual([
      'https://x.supabase.co/storage/v1/object/public/stash-media/u/notes/a.png',
      'https://x.supabase.co/b.jpg',
    ]);
  });

  it('reads no pictures from plain text, HTML, broken JSON or a note without any', () => {
    expect(noteImageSources('just words')).toEqual([]);
    expect(noteImageSources('<p>words <img src="https://x/y.png"></p>')).toEqual([]);
    expect(noteImageSources('{not json')).toEqual([]);
    expect(noteImageSources(doc([para('words')]))).toEqual([]);
    expect(noteImageSources(null)).toEqual([]);
  });
});

describe('readNoteImages / noteImagesSearchText', () => {
  it('reads a well-formed leaf and renders it as lines for the index', () => {
    const leaf = readNoteImages({
      note_images: {
        version: 1,
        images: [
          { src: 'https://x/a.png', description: 'A blood test report with a table of markers.', text: 'RBC 4.7 10^6/uL', analyzed_at: '2026-10-10T00:00:00Z' },
          { src: 'https://x/b.png', description: 'The InsideTracker logo.', analyzed_at: '2026-10-10T00:00:00Z' },
          { src: 'https://x/c.png', description: 42 },
        ],
      },
    });
    expect(leaf?.images.map((i) => i.src)).toEqual(['https://x/a.png', 'https://x/b.png']);
    expect(noteImagesSearchText(leaf)).toBe(
      'A blood test report with a table of markers.\nText in the image: RBC 4.7 10^6/uL\n\nThe InsideTracker logo.',
    );
  });

  it('treats a missing, old or malformed leaf as no pictures', () => {
    expect(readNoteImages(undefined)).toBeNull();
    expect(readNoteImages({ note_images: { version: 2, images: [] } })).toBeNull();
    expect(readNoteImages({ note_images: [] })).toBeNull();
    expect(noteImagesSearchText(null)).toBe('');
    expect(noteImagesSearchText({ version: 1, images: [] })).toBe('');
  });
});

describe('reconcileNoteImages', () => {
  it('keeps described pictures still in the note, drops removed ones, names the new ones', () => {
    const current = {
      version: 1 as const,
      images: [
        { src: 'https://x/a.png', description: 'A', analyzed_at: 't' },
        { src: 'https://x/gone.png', description: 'Gone', analyzed_at: 't' },
      ],
    };
    expect(reconcileNoteImages(current, ['https://x/new.png', 'https://x/a.png'])).toEqual({
      kept: [{ src: 'https://x/a.png', description: 'A', analyzed_at: 't' }],
      missing: ['https://x/new.png'],
    });
    expect(reconcileNoteImages(null, ['https://x/a.png'])).toEqual({ kept: [], missing: ['https://x/a.png'] });
    expect(reconcileNoteImages(current, [])).toEqual({ kept: [], missing: [] });
  });
});
