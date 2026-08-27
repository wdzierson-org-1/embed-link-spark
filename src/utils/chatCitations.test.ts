import { bakeCitationLinks, extractLinkedItemIds, itemIdFromHref } from './chatCitations';

const sources = [
  { id: 'aaa-111', n: 1 },
  { id: 'ccc-333', n: 3 },
];

describe('bakeCitationLinks', () => {
  it('rewrites linked titles to item links', () => {
    expect(bakeCitationLinks('See [My Note](#3) for details.', sources)).toBe(
      'See [My Note](#item=ccc-333) for details.'
    );
  });

  it('wraps bare bracket markers as bracketed links', () => {
    expect(bakeCitationLinks('Feed at 8am [1].', sources)).toBe(
      'Feed at 8am [[1]](#item=aaa-111).'
    );
  });

  it('handles both forms together and leaves unknown numbers alone', () => {
    const input = '[My Note](#3) says X [1], and [7] is unknown.';
    expect(bakeCitationLinks(input, sources)).toBe(
      '[My Note](#item=ccc-333) says X [[1]](#item=aaa-111), and [7] is unknown.'
    );
  });

  it('is a no-op without citation numbers', () => {
    expect(bakeCitationLinks('Plain [1] text.', [{ id: 'x' }])).toBe('Plain [1] text.');
  });

  it('does not double-bake already-baked content', () => {
    const baked = bakeCitationLinks('Feed at 8am [1].', sources);
    expect(bakeCitationLinks(baked, sources)).toBe(baked);
  });
});

describe('extractLinkedItemIds', () => {
  it('collects ids from baked links', () => {
    const baked = '[My Note](#item=ccc-333) and [[1]](#item=aaa-111).';
    expect([...extractLinkedItemIds(baked)].sort()).toEqual(['aaa-111', 'ccc-333']);
  });
});

describe('itemIdFromHref', () => {
  it('extracts the id from item hrefs and rejects others', () => {
    expect(itemIdFromHref('#item=abc-123')).toBe('abc-123');
    expect(itemIdFromHref('#3')).toBeNull();
    expect(itemIdFromHref('https://example.com')).toBeNull();
    expect(itemIdFromHref(undefined)).toBeNull();
  });
});
