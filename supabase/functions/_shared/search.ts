// supabase/functions/_shared/search.ts
//
// Canonical retrieval core (docs/PLATFORM_API.md → POST /search-items). Two
// callers: the search-items HTTP shell and the mcp function's search_stash
// tool. Keeping one implementation is what makes MCP "a thin wrapper over the
// retrieval stack that already exists".
//
//   • query mode  — hybrid semantic+keyword search via hybrid_search_content,
//                   optional structured filters, one result per item,
//                   relevance-ordered.
//   • filter mode — no/empty query: newest-first listing under the same
//                   filters (type, date range, tags).
//
// No imports on purpose: normalizeSearchRequest is unit-tested under vitest.

export const ITEM_TYPES = ['text', 'link', 'image', 'audio', 'video', 'document'] as const;
export type ItemType = typeof ITEM_TYPES[number];
export const SNIPPET_CHARS = 280;
export const SEARCH_DEFAULT_LIMIT = 20;
export const SEARCH_MAX_LIMIT = 50;

export interface SearchRequest {
  query: string;
  types: ItemType[];
  tags: string[];
  after: string | null;
  before: string | null;
  limit: number;
}

export interface SearchResult {
  id: string;
  title: string | null;
  type: string;
  url: string | null;
  created_at: string;
  description: string | null;
  snippet: string | null;
  score: number | null;
}

// Structural stand-in for a supabase-js service-role client so this module
// stays import-free. The shells pass a real client.
// deno-lint-ignore no-explicit-any
export type SupabaseAdminLike = any;

export interface SearchDeps {
  supabaseAdmin: SupabaseAdminLike;
  userId: string;
  embed: (text: string) => Promise<number[]>;
}

const parseTimestamp = (value: unknown): string | null => {
  if (typeof value !== 'string' || !value.trim()) return null;
  const parsed = new Date(value);
  return isNaN(parsed.getTime()) ? null : parsed.toISOString();
};

export function normalizeSearchRequest(body: unknown): SearchRequest {
  const b = (typeof body === 'object' && body !== null && !Array.isArray(body) ? body : {}) as Record<string, unknown>;
  const query = typeof b.query === 'string' ? b.query.trim() : '';
  const types = Array.isArray(b.types)
    ? b.types.filter((t): t is ItemType => typeof t === 'string' && (ITEM_TYPES as readonly string[]).includes(t))
    : [];
  const tags = Array.isArray(b.tags)
    ? b.tags.filter((t): t is string => typeof t === 'string' && t.trim().length > 0).map((t) => t.trim().toLowerCase())
    : [];
  const rawLimit = Math.trunc(Number(b.limit) || SEARCH_DEFAULT_LIMIT);
  const limit = Math.min(Math.max(rawLimit, 1), SEARCH_MAX_LIMIT);
  return { query, types, tags, after: parseTimestamp(b.after), before: parseTimestamp(b.before), limit };
}

export const openAiEmbedder = (apiKey: string) => async (text: string): Promise<number[]> => {
  const response = await fetch('https://api.openai.com/v1/embeddings', {
    method: 'POST',
    headers: { 'Authorization': `Bearer ${apiKey}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ model: 'text-embedding-3-small', input: text }),
  });
  if (!response.ok) throw new Error(`Embedding request failed: ${response.status}`);
  const data = await response.json();
  return data.data[0].embedding;
};

export async function searchItems(req: SearchRequest, deps: SearchDeps): Promise<SearchResult[]> {
  const { supabaseAdmin, userId } = deps;
  const { query, types, tags, after, before, limit } = req;

  if (query) {
    const queryEmbedding = await deps.embed(query);
    const { data, error } = await supabaseAdmin.rpc('hybrid_search_content', {
      query_text: query,
      query_embedding: JSON.stringify(queryEmbedding),
      target_user_id: userId,
      match_count: Math.min(limit * 2, SEARCH_MAX_LIMIT),
      filter_types: types.length ? types : null,
      after_ts: after,
      before_ts: before,
      filter_tags: tags.length ? tags : null,
    });
    if (error) throw error;

    // Hits arrive relevance-ordered with up to 2 chunks per item; keep the
    // best-scored row per item and surface its chunk as the snippet.
    const seen = new Set<string>();
    const results: SearchResult[] = [];
    for (const hit of data ?? []) {
      if (seen.has(hit.item_id)) continue;
      seen.add(hit.item_id);
      results.push({
        id: hit.item_id,
        title: hit.item_title,
        type: hit.item_type,
        url: hit.item_url,
        created_at: hit.item_created_at,
        description: hit.item_description,
        snippet: hit.content_chunk ? hit.content_chunk.slice(0, SNIPPET_CHARS) : null,
        score: hit.score,
      });
      if (results.length >= limit) break;
    }
    return results;
  }

  // Filter-only mode: newest first under the same filters.
  let itemIds: string[] | null = null;
  if (tags.length) {
    const { data: tagRows, error: tagError } = await supabaseAdmin
      .from('tags').select('id').eq('user_id', userId).in('name', tags);
    if (tagError) throw tagError;
    const tagIds = (tagRows ?? []).map((t: { id: string }) => t.id);
    if (!tagIds.length) return [];
    const { data: itRows, error: itError } = await supabaseAdmin
      .from('item_tags').select('item_id').in('tag_id', tagIds);
    if (itError) throw itError;
    itemIds = [...new Set((itRows ?? []).map((r: { item_id: string }) => r.item_id))];
    if (!itemIds.length) return [];
  }

  let listQuery = supabaseAdmin
    .from('items')
    .select('id, title, type, url, created_at, description')
    .eq('user_id', userId)
    .neq('type', 'collection')
    .order('created_at', { ascending: false })
    .limit(limit);
  if (types.length) listQuery = listQuery.in('type', types);
  if (after) listQuery = listQuery.gte('created_at', after);
  if (before) listQuery = listQuery.lte('created_at', before);
  if (itemIds) listQuery = listQuery.in('id', itemIds);

  const { data, error } = await listQuery;
  if (error) throw error;

  return (data ?? []).map((item: {
    id: string; title: string | null; type: string; url: string | null;
    created_at: string; description: string | null;
  }) => ({
    id: item.id,
    title: item.title,
    type: item.type,
    url: item.url,
    created_at: item.created_at,
    description: item.description,
    snippet: item.description ? item.description.slice(0, SNIPPET_CHARS) : null,
    score: null,
  }));
}
