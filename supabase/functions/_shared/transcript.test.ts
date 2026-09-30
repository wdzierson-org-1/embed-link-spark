import { describe, expect, it } from 'vitest';
import { formatDiarizedTranscript, transcriptProgressColumns } from './transcript';

describe('speaker transcript', () => {
  it('groups adjacent segments from one voice and separates speaker turns with timestamps', () => {
    expect(formatDiarizedTranscript({ segments: [
      { speaker: 'A', start: 0, text: 'Hello.' },
      { speaker: 'A', start: 1, text: 'How are you?' },
      { speaker: 'B', start: 65, text: 'Good, thanks.' },
      { speaker: 'A', start: 70, text: 'Great.' },
    ] })).toBe('**Speaker A · 0:00**\n\nHello. How are you?\n\n**Speaker B · 1:05**\n\nGood, thanks.\n\n**Speaker A · 1:10**\n\nGreat.');
  });
  it('preserves text without inventing speakers if segments are absent', () => {
    expect(formatDiarizedTranscript({ text: 'Plain transcript.' })).toBe('Plain transcript.');
    expect(formatDiarizedTranscript({ segments: [] })).toBe('');
  });
});

describe('transcriptProgressColumns', () => {
  it('writes the transcript once there is text', () => {
    expect(transcriptProgressColumns('hello there', 200_000)).toEqual({ page_body: 'hello there' });
  });

  it('caps a long transcript', () => {
    expect(transcriptProgressColumns('abcdef', 3)).toEqual({ page_body: 'abc' });
  });

  // The bug: a retry that finds no speech must not erase the previous transcript.
  it('writes NOTHING when the run has produced no text yet', () => {
    expect(transcriptProgressColumns('', 200_000)).toEqual({});
  });

  it('writes nothing for whitespace-only output', () => {
    expect(transcriptProgressColumns('   \n  ', 200_000)).toEqual({});
  });

  it('never yields a null page_body, which would clear the column', () => {
    for (const empty of ['', '   ', '\n']) {
      expect(Object.prototype.hasOwnProperty.call(transcriptProgressColumns(empty, 10), 'page_body')).toBe(false);
    }
  });
});
