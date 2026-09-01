import "https://deno.land/x/xhr@0.1.0/mod.ts";
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { authenticateUser } from '../_shared/auth.ts';

// Canonical search surface for every retrieval consumer (web toolbar, chat
// tool-calling, MCP, iOS/Siri). Two modes:
//   • query mode  — hybrid semantic+keyword search via hybrid_search_content,
//                   with optional structured filters, deduped to one result
//                   per item, relevance-ordered.
//   • filter mode — no/empty query: newest-first listing under the same
//                   filters (type, date range, tags).
// Request:  { query?, types?, tags?, after?, before?, limit? }
// Response: { results: [{ id, title, type, url, created_at, description, snippet, score }] }

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

const ITEM_TYPES = ['text', 'link', 'image', 'audio', 'video', 'document'] as const;
const SNIPPET_CHARS = 280;
const DEFAULT_LIMIT = 20;
const MAX_LIMIT = 50;

interface SearchRequest {
  query?: string;
  types?: string[];
  tags?: string[];
  after?: string;
  before?: string;
  limit?: number;
}

interface SearchResult {
  id: string;
  title: string | null;
  type: string;
  url: string | null;
  created_at: string;
  description: string | null;
  snippet: string | null;
  score: number | null;
}

const generateQueryEmbedding = async (text: string, openAIApiKey: string): Promise<number[]> => {
  const response = await fetch('https://api.openai.com/v1/embeddings', {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${openAIApiKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ model: 'text-embedding-3-small', input: text }),
  });
  if (!response.ok) {
    throw new Error(`Embedding request failed: ${response.status}`);
  }
  const data = await response.json();
  return data.data[0].embedding;
};

const parseTimestamp = (value: unknown): string | null => {
  if (typeof value !== 'string' || !value.trim()) return null;
  const parsed = new Date(value);
  return isNaN(parsed.getTime()) ? null : parsed.toISOString();
};

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    const { user, supabaseAdmin } = await authenticateUser(req.headers.get('Authorization'));
    const body: SearchRequest = await req.json().catch(() => ({}));

    const query = typeof body.query === 'string' ? body.query.trim() : '';
    const types = Array.isArray(body.types)
      ? body.types.filter((t): t is string => ITEM_TYPES.includes(t as typeof ITEM_TYPES[number]))
      : [];
    const tags = Array.isArray(body.tags)
      ? body.tags.filter((t): t is string => typeof t === 'string' && t.trim().length > 0)
          .map((t) => t.trim().toLowerCase())
      : [];
    const after = parseTimestamp(body.after);
    const before = parseTimestamp(body.before);
    const limit = Math.min(Math.max(Math.trunc(Number(body.limit) || DEFAULT_LIMIT), 1), MAX_LIMIT);

    let results: SearchResult[] = [];

    if (query) {
      const openAIApiKey = Deno.env.get('OPENAI_API_KEY');
      if (!openAIApiKey) {
        throw new Error('OPENAI_API_KEY not configured');
      }
      const queryEmbedding = await generateQueryEmbedding(query, openAIApiKey);

      const { data, error } = await supabaseAdmin.rpc('hybrid_search_content', {
        query_text: query,
        query_embedding: JSON.stringify(queryEmbedding),
        target_user_id: user.id,
        match_count: Math.min(limit * 2, MAX_LIMIT),
        filter_types: types.length ? types : null,
        after_ts: after,
        before_ts: before,
        filter_tags: tags.length ? tags : null,
      });
      if (error) throw error;

      // Hits arrive relevance-ordered with up to 2 chunks per item; keep the
      // best-scored row per item and surface its chunk as the snippet.
      const seen = new Set<string>();
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
    } else {
      // Filter-only mode: newest first under the same filters.
      let itemIds: string[] | null = null;
      if (tags.length) {
        const { data: tagRows, error: tagError } = await supabaseAdmin
          .from('tags')
          .select('id')
          .eq('user_id', user.id)
          .in('name', tags);
        if (tagError) throw tagError;
        const tagIds = (tagRows ?? []).map((t: { id: string }) => t.id);
        if (!tagIds.length) {
          return new Response(JSON.stringify({ results: [] }), {
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
          });
        }
        const { data: itRows, error: itError } = await supabaseAdmin
          .from('item_tags')
          .select('item_id')
          .in('tag_id', tagIds);
        if (itError) throw itError;
        itemIds = [...new Set((itRows ?? []).map((r: { item_id: string }) => r.item_id))];
        if (!itemIds.length) {
          return new Response(JSON.stringify({ results: [] }), {
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
          });
        }
      }

      let listQuery = supabaseAdmin
        .from('items')
        .select('id, title, type, url, created_at, description')
        .eq('user_id', user.id)
        .neq('type', 'collection')
        .order('created_at', { ascending: false })
        .limit(limit);
      if (types.length) listQuery = listQuery.in('type', types);
      if (after) listQuery = listQuery.gte('created_at', after);
      if (before) listQuery = listQuery.lte('created_at', before);
      if (itemIds) listQuery = listQuery.in('id', itemIds);

      const { data, error } = await listQuery;
      if (error) throw error;

      results = (data ?? []).map((item: {
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

    return new Response(JSON.stringify({ results }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  } catch (error) {
    console.error('Error in search-items:', error);
    const message = error instanceof Error ? error.message : 'Unknown error';
    const status = message.includes('Authentication') || message.includes('authorization') ? 401 : 500;
    return new Response(JSON.stringify({ error: message }), {
      status,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
});
