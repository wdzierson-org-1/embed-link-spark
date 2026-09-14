-- Ask Stash / search: surface and boost the user's own notes.
--
-- Diagnosis (2026-09-14): a note like "potential investor for Stash" on a
-- long LinkedIn link IS indexed (fts + embeddings chunk 0), but search
-- results carry one snippet = the best-matching chunk, so a page-body chunk
-- wins the slot and the model never sees the note. Two changes:
--
--   1. hybrid_search_content v4 returns `item_content` (raw notes; callers
--      render it as plain text) so every result can show the note as its own
--      line, independent of the snippet.
--   2. A third RRF ranking over the notes alone (`notes_weight`, default 1.5)
--      so an item whose note matches the query outranks items that merely
--      mention the words somewhere in their captured text. Notes are the
--      user's words about why they saved the thing — the strongest signal
--      (docs/ETHOS.md).
--
-- `notes_plain_text` extracts the words from Novel/TipTap JSON documents so
-- the JSON scaffolding ("type", "doc", "paragraph", "content", "text") never
-- becomes a lexeme. Plain-text and HTML-ish notes pass through unchanged.
-- Signature grows (new trailing arg), so the old one is dropped first and the
-- grants re-applied. Result columns are appended last; all callers select by
-- name.

CREATE OR REPLACE FUNCTION public.notes_plain_text(content text)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
STRICT
AS $$
DECLARE
  parsed jsonb;
BEGIN
  IF left(ltrim(content), 1) <> '{' THEN
    RETURN content;
  END IF;
  BEGIN
    parsed := content::jsonb;
  EXCEPTION WHEN others THEN
    RETURN content;
  END;
  IF parsed->>'type' <> 'doc' OR jsonb_typeof(parsed->'content') <> 'array' THEN
    RETURN content;
  END IF;
  RETURN (
    SELECT string_agg(t #>> '{}', ' ')
    FROM jsonb_path_query(parsed, 'strict $.**.text') AS t
  );
END;
$$;

DROP FUNCTION IF EXISTS public.hybrid_search_content(text, vector, uuid, int, int, item_type[], timestamptz, timestamptz, text[], double precision);

CREATE FUNCTION public.hybrid_search_content(
  query_text text,
  query_embedding vector(1536),
  target_user_id uuid,
  match_count int DEFAULT 12,
  rrf_k int DEFAULT 50,
  filter_types item_type[] DEFAULT NULL,
  after_ts timestamptz DEFAULT NULL,
  before_ts timestamptz DEFAULT NULL,
  filter_tags text[] DEFAULT NULL,
  recency_weight double precision DEFAULT 0.3,
  notes_weight double precision DEFAULT 1.5
)
RETURNS TABLE (
  item_id uuid,
  content_chunk text,
  item_title text,
  item_type item_type,
  item_url text,
  item_created_at timestamptz,
  score double precision,
  item_description text,
  item_flavor text,
  item_content text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
WITH filtered_items AS (
  SELECT i.id, i.title, i.type, i.url, i.description, i.content, i.created_at, i.fts,
         i.attributes->'link'->>'flavor' AS flavor,
         public.notes_plain_text(i.content) AS notes
  FROM items i
  WHERE i.user_id = target_user_id
    AND (filter_types IS NULL OR i.type = ANY(filter_types))
    AND (after_ts IS NULL OR i.created_at >= after_ts)
    AND (before_ts IS NULL OR i.created_at <= before_ts)
    AND (filter_tags IS NULL OR EXISTS (
      SELECT 1 FROM item_tags it
      JOIN tags t ON t.id = it.tag_id
      WHERE it.item_id = i.id AND t.name = ANY(filter_tags)
    ))
),
vector_candidates AS (
  SELECT e.item_id, e.content_chunk,
         e.embedding <=> query_embedding AS dist
  FROM embeddings e
  JOIN filtered_items i ON i.id = e.item_id
  ORDER BY dist
  LIMIT 60
),
vector_hits AS (
  -- Cap each item at 2 chunks before ranking so a single long item can't
  -- occupy most of the fused result list.
  SELECT c.item_id, c.content_chunk,
         row_number() OVER (ORDER BY c.dist) AS rank
  FROM (
    SELECT item_id, content_chunk, dist,
           row_number() OVER (PARTITION BY item_id ORDER BY dist) AS item_rank
    FROM vector_candidates
  ) c
  WHERE c.item_rank <= 2
  ORDER BY c.dist
  LIMIT 30
),
fts_hits AS (
  SELECT f.item_id, f.rank
  FROM (
    SELECT i.id AS item_id,
           row_number() OVER (ORDER BY ts_rank_cd(i.fts, q) DESC) AS rank
    FROM filtered_items i, websearch_to_tsquery('english', query_text) q
    WHERE i.fts @@ q
    ORDER BY ts_rank_cd(i.fts, q) DESC
    LIMIT 30
  ) f
),
-- Keyword ranking over the user's notes alone. A note is short and written
-- by the user, so a match here is the strongest relevance signal we have.
notes_hits AS (
  SELECT n.item_id, n.rank
  FROM (
    SELECT i.id AS item_id,
           row_number() OVER (ORDER BY ts_rank_cd(nv, q) DESC) AS rank
    FROM filtered_items i,
         websearch_to_tsquery('english', query_text) q,
         to_tsvector('english', left(coalesce(i.notes, ''), 50000)) nv
    WHERE i.notes IS NOT NULL AND nv @@ q
    ORDER BY ts_rank_cd(nv, q) DESC
    LIMIT 30
  ) n
),
scored_chunks AS (
  SELECT v.item_id, v.content_chunk,
         (1.0 / (rrf_k + v.rank))
         + coalesce((SELECT 1.0 / (rrf_k + f.rank) FROM fts_hits f WHERE f.item_id = v.item_id), 0)
         + coalesce((SELECT notes_weight / (rrf_k + n.rank) FROM notes_hits n WHERE n.item_id = v.item_id), 0)
         AS score
  FROM vector_hits v
),
fts_only AS (
  SELECT f.item_id,
         coalesce(
           (SELECT e.content_chunk FROM embeddings e
            WHERE e.item_id = f.item_id ORDER BY e.chunk_index LIMIT 1),
           left(concat_ws(' ', i.title, i.description, i.notes), 1200)
         ) AS content_chunk,
         ((1.0 / (rrf_k + f.rank))
          + coalesce((SELECT notes_weight / (rrf_k + n.rank) FROM notes_hits n WHERE n.item_id = f.item_id), 0)
         )::double precision AS score
  FROM fts_hits f
  JOIN filtered_items i ON i.id = f.item_id
  WHERE NOT EXISTS (SELECT 1 FROM vector_hits v WHERE v.item_id = f.item_id)
)
SELECT s.item_id, s.content_chunk, i.title AS item_title, i.type AS item_type,
       i.url AS item_url, i.created_at AS item_created_at,
       (s.score
        + recency_weight / (rrf_k + GREATEST(extract(epoch FROM (now() - i.created_at)) / 86400.0, 0))
       )::double precision AS score,
       i.description AS item_description,
       i.flavor AS item_flavor,
       i.content AS item_content
FROM (
  SELECT item_id, content_chunk, score FROM scored_chunks
  UNION ALL
  SELECT item_id, content_chunk, score FROM fts_only
) s
JOIN filtered_items i ON i.id = s.item_id
ORDER BY score DESC
LIMIT match_count;
$$;

REVOKE EXECUTE ON FUNCTION public.hybrid_search_content(text, vector, uuid, int, int, item_type[], timestamptz, timestamptz, text[], double precision, double precision)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.hybrid_search_content(text, vector, uuid, int, int, item_type[], timestamptz, timestamptz, text[], double precision, double precision)
  TO service_role;
