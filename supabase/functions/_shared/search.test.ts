import { describe, expect, it } from 'vitest';
import { SEARCH_DEFAULT_LIMIT, SEARCH_MAX_LIMIT, normalizeSearchRequest } from './search';

describe('normalizeSearchRequest', () => {
  it('returns defaults for empty or non-object bodies', () => {
    const expected = { query: '', types: [], tags: [], after: null, before: null, limit: SEARCH_DEFAULT_LIMIT };
    expect(normalizeSearchRequest({})).toEqual(expected);
    expect(normalizeSearchRequest(null)).toEqual(expected);
    expect(normalizeSearchRequest([1, 2])).toEqual(expected);
    expect(normalizeSearchRequest('x')).toEqual(expected);
  });

  it('trims the query, keeps only known types, lowercases and trims tags', () => {
    const req = normalizeSearchRequest({ query: '  tacos ', types: ['link', 'bogus', 'audio'], tags: [' Food ', '', 7] });
    expect(req.query).toBe('tacos');
    expect(req.types).toEqual(['link', 'audio']);
    expect(req.tags).toEqual(['food']);
  });

  it('clamps and truncates limit', () => {
    expect(normalizeSearchRequest({ limit: 999 }).limit).toBe(SEARCH_MAX_LIMIT);
    expect(normalizeSearchRequest({ limit: 0 }).limit).toBe(SEARCH_DEFAULT_LIMIT);
    expect(normalizeSearchRequest({ limit: -4 }).limit).toBe(1);
    expect(normalizeSearchRequest({ limit: 3.9 }).limit).toBe(3);
    expect(normalizeSearchRequest({ limit: 'abc' }).limit).toBe(SEARCH_DEFAULT_LIMIT);
  });

  it('normalizes timestamps to ISO and drops invalid ones', () => {
    const req = normalizeSearchRequest({ after: '2026-08-01', before: 'not a date' });
    expect(req.after).toBe('2026-08-01T00:00:00.000Z');
    expect(req.before).toBeNull();
  });
});
