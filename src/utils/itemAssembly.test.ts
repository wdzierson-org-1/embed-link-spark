import { describe, expect, it } from 'vitest';
import {
  ASSEMBLY_WINDOW_MS,
  isAssembling,
  isPlaceholderImageTitle,
  itemAgeMs,
  landedPieces,
  missingPieces,
} from './itemAssembly';

const NOW = Date.parse('2026-08-26T12:00:00Z');
const secondsAgo = (s: number) => new Date(NOW - s * 1000).toISOString();

const image = (over: Record<string, unknown> = {}) => ({
  id: 'i1',
  type: 'image',
  title: '1756200000000.jpg',
  description: null,
  file_path: 'user-1/1756200000000.jpg',
  created_at: secondsAgo(5),
  ...over,
});

describe('isPlaceholderImageTitle', () => {
  it('treats empty, storage-basename, and filename-looking titles as placeholders', () => {
    expect(isPlaceholderImageTitle('', 'u/a.jpg')).toBe(true);
    expect(isPlaceholderImageTitle('1756200000000.jpg', 'u/1756200000000.jpg')).toBe(true);
    expect(isPlaceholderImageTitle('CleanShot 2026-08-11.png', 'u/175620.jpg')).toBe(true);
    expect(isPlaceholderImageTitle('Screenshot of a booking form', 'u/a.jpg')).toBe(false);
  });
});

describe('missingPieces', () => {
  it('expects description + AI title for fresh images', () => {
    expect(missingPieces(image())).toEqual(['description', 'title']);
    expect(
      missingPieces(image({ description: 'A dog.', title: 'Image of a dog' })),
    ).toEqual([]);
  });

  it('expects description for audio/video', () => {
    expect(missingPieces({ id: 'a', type: 'audio', description: null })).toEqual(['description']);
    expect(missingPieces({ id: 'a', type: 'video', description: 'Clip.' })).toEqual([]);
  });

  it('expects summary only for PDFs (summary present = done contract)', () => {
    expect(
      missingPieces({ id: 'd', type: 'document', mime_type: 'application/pdf', summary: null }),
    ).toEqual(['summary']);
    expect(
      missingPieces({ id: 'd', type: 'document', mime_type: 'application/pdf', summary: 'Done.' }),
    ).toEqual([]);
    expect(
      missingPieces({ id: 'd', type: 'document', mime_type: 'text/csv', summary: null }),
    ).toEqual([]);
  });

  it('never promises pieces for links and notes', () => {
    expect(missingPieces({ id: 'l', type: 'link', description: null })).toEqual([]);
    expect(missingPieces({ id: 't', type: 'text', description: null })).toEqual([]);
  });
});

describe('isAssembling', () => {
  it('is true only inside the age window with pieces missing', () => {
    expect(isAssembling(image(), NOW)).toBe(true);
    expect(isAssembling(image({ created_at: secondsAgo(ASSEMBLY_WINDOW_MS / 1000 + 5) }), NOW)).toBe(false);
    expect(isAssembling(image({ description: 'A dog.', title: 'Image of a dog' }), NOW)).toBe(false);
  });

  it('treats missing created_at as not assembling', () => {
    expect(isAssembling(image({ created_at: null }), NOW)).toBe(false);
    expect(itemAgeMs(image({ created_at: null }), NOW)).toBe(Number.POSITIVE_INFINITY);
  });
});

describe('landedPieces', () => {
  it('detects description, summary, title, and preview arrivals', () => {
    const prev = { id: 'x', title: 'a.jpg', description: null, summary: null, file_path: null };
    const next = {
      id: 'x',
      title: 'Image of a dog',
      description: 'A dog.',
      summary: 'Long summary',
      file_path: 'u/preview.jpg',
    };
    expect(landedPieces(prev, next)).toEqual(['description', 'summary', 'title', 'preview']);
  });

  it('reports nothing when fields are unchanged or emptied', () => {
    const item = { id: 'x', title: 'T', description: 'D', summary: null, file_path: 'u/a.jpg' };
    expect(landedPieces(item, { ...item })).toEqual([]);
    expect(landedPieces(item, { ...item, description: null })).toEqual([]);
    expect(landedPieces(item, { ...item, title: '' })).toEqual([]);
  });
});
