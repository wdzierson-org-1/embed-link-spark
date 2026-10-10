import { findTimestamps, formatTimestamp, parseTimestamp, timestampMarker } from './timestamps';

describe('timestamps', () => {
  it('formats seconds as m:ss, or h:mm:ss past an hour', () => {
    expect(formatTimestamp(0)).toBe('0:00');
    expect(formatTimestamp(102.7)).toBe('1:42');
    expect(formatTimestamp(3723)).toBe('1:02:03');
    expect(timestampMarker(65)).toBe('[1:05]');
  });

  it('parses what it formats, and refuses what is not a time', () => {
    expect(parseTimestamp('1:42')).toBe(102);
    expect(parseTimestamp('1:02:03')).toBe(3723);
    expect(parseTimestamp('0:00')).toBe(0);
    expect(parseTimestamp('1:60')).toBeNull();
    expect(parseTimestamp('abc')).toBeNull();
  });

  it('finds every marker in a note with its position', () => {
    const text = 'Intro [0:12] then the good part [1:42:05], and [x:yy] is not one.';
    expect(findTimestamps(text)).toEqual([
      { index: 6, length: 6, seconds: 12 },
      { index: 32, length: 9, seconds: 6125 },
    ]);
  });
});
