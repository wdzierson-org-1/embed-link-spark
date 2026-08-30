import { describe, expect, it } from 'vitest';
import {
  capTitle,
  fileBasename,
  isPlaceholderTitle,
  isStorageTimestampName,
  isUuidObjectName,
} from './titlePolicy';

describe('isPlaceholderTitle', () => {
  it('treats empty/missing titles as placeholders', () => {
    expect(isPlaceholderTitle('', 'uid/1724900000000.m4a')).toBe(true);
    expect(isPlaceholderTitle('   ', null)).toBe(true);
    expect(isPlaceholderTitle(null, undefined)).toBe(true);
    expect(isPlaceholderTitle(undefined, 'uid/file.pdf')).toBe(true);
  });

  it('treats UUID object names as placeholders (Voice Memos share)', () => {
    expect(isPlaceholderTitle('72322570-a4bc-4515-935c-ff384090f068.m4a', null)).toBe(true);
    expect(isPlaceholderTitle('72322570-A4BC-4515-935C-FF384090F068.M4A', null)).toBe(true);
  });

  it('treats storage timestamp names as placeholders', () => {
    expect(isPlaceholderTitle('1724900000000.webm', null)).toBe(true);
    expect(isPlaceholderTitle('1724900000.mp3', null)).toBe(true);
  });

  it('treats extension-suffixed titles as placeholders', () => {
    expect(isPlaceholderTitle('Recording.m4a', null)).toBe(true);
    expect(isPlaceholderTitle('Q3 planning deck.pptx', null)).toBe(true);
    expect(isPlaceholderTitle('scan_2026-08-12.pdf', null)).toBe(true);
    expect(isPlaceholderTitle('holiday clip.3gp', null)).toBe(true);
  });

  it('treats a title equal to the file basename as a placeholder even without an extension', () => {
    expect(isPlaceholderTitle('exported_audio', 'uid/exported_audio')).toBe(true);
  });

  it('keeps real user titles', () => {
    expect(isPlaceholderTitle('Grocery run ideas for the party', 'uid/1724900000000.m4a')).toBe(false);
    expect(isPlaceholderTitle('Meeting notes v2.1', 'uid/notes.docx')).toBe(false);
    expect(isPlaceholderTitle('Why I love the Q3 plan', null)).toBe(false);
  });
});

describe('isStorageTimestampName / isUuidObjectName', () => {
  it('matches only the generated shapes', () => {
    expect(isStorageTimestampName('1724900000000.webm')).toBe(true);
    expect(isStorageTimestampName('my-audio.webm')).toBe(false);
    expect(isUuidObjectName('72322570-a4bc-4515-935c-ff384090f068.m4a')).toBe(true);
    expect(isUuidObjectName('interview-with-sam.m4a')).toBe(false);
  });
});

describe('fileBasename', () => {
  it('returns the last path segment', () => {
    expect(fileBasename('uid/folder/file.m4a')).toBe('file.m4a');
    expect(fileBasename('file.m4a')).toBe('file.m4a');
    expect(fileBasename(null)).toBeNull();
    expect(fileBasename(undefined)).toBeNull();
  });
});

describe('capTitle', () => {
  it('trims and strips wrapping quotes', () => {
    expect(capTitle('  "Planning the kitchen remodel"  ')).toBe('Planning the kitchen remodel');
    expect(capTitle("'Quoted title'")).toBe('Quoted title');
  });

  it('caps long titles at 90 chars with an ellipsis', () => {
    const long = 'a'.repeat(120);
    const capped = capTitle(long);
    expect(capped.length).toBe(91); // 90 chars + ellipsis
    expect(capped.endsWith('…')).toBe(true);
  });

  it('leaves short titles alone', () => {
    expect(capTitle('Short title')).toBe('Short title');
  });
});
