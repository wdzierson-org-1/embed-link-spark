// @vitest-environment node
import { describe, expect, it } from 'vitest';
import { noteImageSources as serverSources } from '../../supabase/functions/_shared/noteImages';
import { noteImageSources, noteNeedsPictureAnalysis } from './noteImages';

const doc = (content: unknown[]) => JSON.stringify({ type: 'doc', content });
const image = (src: string) => ({ type: 'image', attrs: { src } });

const cases: Array<[string, string | null]> = [
  ['two pictures, one twice, one inline', doc([image('https://x/a.png'), { type: 'paragraph', content: [{ type: 'text', text: 'w' }] }, image('https://x/b.png'), image('https://x/a.png'), image('data:image/png;base64,AA')])],
  ['nested in a list', doc([{ type: 'bulletList', content: [{ type: 'listItem', content: [image(' https://x/c.png ')] }] }])],
  ['no pictures', doc([{ type: 'paragraph', content: [{ type: 'text', text: 'w' }] }])],
  ['plain text', 'just words'],
  ['html', '<p><img src="https://x/y.png"></p>'],
  ['broken json', '{nope'],
  ['null', null],
];

describe('noteImageSources parity (web vs platform)', () => {
  it.each(cases)('%s', (_name, content) => {
    expect(noteImageSources(content)).toEqual(serverSources(content));
  });

  it('reads the pictures of a note', () => {
    expect(noteImageSources(cases[0][1])).toEqual(['https://x/a.png', 'https://x/b.png']);
  });
});

describe('noteNeedsPictureAnalysis', () => {
  it('is true for a note with pictures, or one whose pictures were described before', () => {
    expect(noteNeedsPictureAnalysis({ content: doc([image('https://x/a.png')]), attributes: {} })).toBe(true);
    expect(noteNeedsPictureAnalysis({ content: 'words', attributes: { note_images: { version: 1, images: [] } } })).toBe(true);
    expect(noteNeedsPictureAnalysis({ content: 'words', attributes: {} })).toBe(false);
    expect(noteNeedsPictureAnalysis(null)).toBe(false);
  });
});
