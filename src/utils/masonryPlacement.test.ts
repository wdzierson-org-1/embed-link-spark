import { describe, expect, it } from 'vitest';
import { masonryPlacement } from './masonryPlacement';

describe('masonry recency order', () => {
  it('assigns successive rows left to right instead of picking the shortest column', () => {
    const result = masonryPlacement([400, 100, 250, 150, 200, 120], 3);
    expect(result.map(card => card.column)).toEqual([1, 2, 3, 1, 2, 3]);
    expect(result.map(card => card.start)).toEqual([1, 1, 1, 425, 125, 275]);
  });

  it('repacks at two or one column while preserving source order and gaps', () => {
    expect(masonryPlacement([100, 200, 300], 2).map(({ column, start }) => [column, start]))
      .toEqual([[1, 1], [2, 1], [1, 125]]);
    expect(masonryPlacement([100, 200, 300], 1).map(card => card.start)).toEqual([1, 125, 349]);
  });

  it('repositions only the following cards in the column when enrichment changes height', () => {
    const before = masonryPlacement([100, 200, 300, 400], 2);
    const after = masonryPlacement([180, 200, 300, 400], 2);
    expect(after[2].start - before[2].start).toBe(80);
    expect(after[3]).toEqual(before[3]);
  });
});
