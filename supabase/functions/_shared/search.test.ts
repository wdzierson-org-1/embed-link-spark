import { describe, expect, it, vi } from 'vitest';
import { SEARCH_DEFAULT_LIMIT, SEARCH_MAX_LIMIT, coerceSearchTypes, normalizeSearchRequest, searchItems } from './search';

describe('coerceSearchTypes', () => {
  it('keeps valid storage types and drops junk', () => {
    expect(coerceSearchTypes(['link', 'audio'])).toEqual(['link', 'audio']);
    expect(coerceSearchTypes(['bogus', 7, null])).toBeNull();
    expect(coerceSearchTypes(undefined)).toBeNull();
    expect(coerceSearchTypes([])).toBeNull();
  });

  it("maps the model's vocabulary onto storage types instead of failing the RPC", () => {
    // 2026-09-14: gpt-5-mini sent types:["note"] → 'invalid input value for enum item_type'
    expect(coerceSearchTypes(['note'])).toEqual(['text', 'audio']);
    expect(coerceSearchTypes(['Notes', 'photo', 'pdf'])).toEqual(['text', 'audio', 'image', 'document']);
    expect(coerceSearchTypes(['voice memo', 'file', 'text'])).toEqual(['audio', 'document', 'text']);
  });
});

const doc = (text: string) =>
  JSON.stringify({ type: 'doc', content: [{ type: 'paragraph', content: [{ type: 'text', text }] }] });

const hit = (overrides: Record<string, unknown>) => ({
  item_id: 'id-1', item_title: 'T', item_type: 'link', item_url: null, item_created_at: '2026-09-13T00:00:00Z',
  item_description: 'desc', content_chunk: 'chunk', score: 0.04, item_flavor: null, item_content: null,
  ...overrides,
});

describe('searchItems — notes surface in results', () => {
  it('query mode: exposes the user note as plain text, separate from the snippet', async () => {
    const rpc = vi.fn().mockResolvedValue({
      data: [
        hit({ item_id: 'a', item_content: doc('potential investor for Stash'), content_chunk: 'a group of investors including Norwest' }),
        hit({ item_id: 'b', item_content: null }),
        hit({ item_id: 'c', item_content: 'plain words' }),
      ],
      error: null,
    });
    const results = await searchItems(
      normalizeSearchRequest({ query: 'potential investors' }),
      { supabaseAdmin: { rpc }, userId: 'u', embed: async () => [0.1] },
    );
    expect(results.map((r) => r.notes)).toEqual(['potential investor for Stash', null, 'plain words']);
    expect(results[0].snippet).toBe('a group of investors including Norwest');
  });

  it('filter mode: loads content and exposes it as notes', async () => {
    const rows = [{ id: 'a', title: 'T', type: 'text', url: null, created_at: '2026-09-13T00:00:00Z', description: null, content: doc('Band my mom liked') }];
    const builder: Record<string, unknown> = {};
    for (const m of ['select', 'eq', 'neq', 'order', 'limit', 'in', 'gte', 'lte']) builder[m] = vi.fn(() => builder);
    (builder as { then: unknown }).then = (resolve: (v: unknown) => void) => resolve({ data: rows, error: null });
    const from = vi.fn(() => builder);
    const results = await searchItems(
      normalizeSearchRequest({}),
      { supabaseAdmin: { from }, userId: 'u', embed: async () => [] },
    );
    expect((builder.select as ReturnType<typeof vi.fn>).mock.calls[0][0]).toContain('content');
    expect(results[0].notes).toBe('Band my mom liked');
  });
});

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
