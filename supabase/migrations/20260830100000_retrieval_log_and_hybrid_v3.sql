-- Retrieval reliability (spec: docs/superpowers/specs/
-- 2026-08-29-ask-retrieval-reliability-and-intent-gate-spec.md), R2 + R6.
--
-- R6: retrieval_log — every search_stash / browse_catalog call the Ask agent
-- makes, so retrieval quality is observable and goldens replayable. Written
-- by edge functions with the service role; no client access (RLS on, no
-- policies — service role bypasses).
--
-- R2: hybrid_search_content v3 — adds item_flavor (attributes->link->>flavor)
-- to the result shape, appended last so existing callers are unaffected (all
-- callers select by name). Lets the caller treat "video" as type=video OR a
-- link that IS a video, instead of a hard type miss.

CREATE TABLE IF NOT EXISTS public.retrieval_log (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  tool text NOT NULL,                -- 'search_stash' | 'browse_catalog'
  query text,
  filters jsonb,                     -- {types, after, before, tags} as sent
  result_ids uuid[],                 -- item ids surfaced, in rank order
  result_count int,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_retrieval_log_user_time
  ON public.retrieval_log (user_id, created_at DESC);

ALTER TABLE public.retrieval_log ENABLE ROW LEVEL SECURITY;

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
  recency_weight double precision DEFAULT 0.3
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
  item_flavor text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
WITH filtered_items AS (
  SELECT i.id, i.title, i.type, i.url, i.description, i.content, i.created_at, i.fts,
         i.attributes->'link'->>'flavor' AS flavor
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
scored_chunks AS (
  SELECT v.item_id, v.content_chunk,
         (1.0 / (rrf_k + v.rank))
         + coalesce((SELECT 1.0 / (rrf_k + f.rank) FROM fts_hits f WHERE f.item_id = v.item_id), 0)
         AS score
  FROM vector_hits v
),
fts_only AS (
  SELECT f.item_id,
         coalesce(
           (SELECT e.content_chunk FROM embeddings e
            WHERE e.item_id = f.item_id ORDER BY e.chunk_index LIMIT 1),
           left(concat_ws(' ', i.title, i.description, i.content), 1200)
         ) AS content_chunk,
         (1.0 / (rrf_k + f.rank))::double precision AS score
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
       i.flavor AS item_flavor
FROM (
  SELECT item_id, content_chunk, score FROM scored_chunks
  UNION ALL
  SELECT item_id, content_chunk, score FROM fts_only
) s
JOIN filtered_items i ON i.id = s.item_id
ORDER BY score DESC
LIMIT match_count;
$$;

REVOKE EXECUTE ON FUNCTION public.hybrid_search_content(text, vector, uuid, int, int, item_type[], timestamptz, timestamptz, text[], double precision)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.hybrid_search_content(text, vector, uuid, int, int, item_type[], timestamptz, timestamptz, text[], double precision)
  TO service_role;
