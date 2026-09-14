import { describe, expect, it } from 'vitest';
import { formatDiarizedTranscript } from './transcript';

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
