-- Hybrid retrieval: full-text search + HNSW vector index + RRF-fused search RPC,
-- plus realtime on items (replaces client-side polling).

-- 1. Full-text search over the item's own text fields. Long fields are capped so
--    a giant PDF extraction can never overflow the 1MB tsvector limit (which
--    would make every update to that row fail).
ALTER TABLE public.items
  ADD COLUMN IF NOT EXISTS fts tsvector
  GENERATED ALWAYS AS (
    to_tsvector('english',
      coalesce(title, '') || ' ' ||
      coalesce(description, '') || ' ' ||
      coalesce(supplemental_note, '') || ' ' ||
      left(coalesce(content, ''), 50000) || ' ' ||
      left(coalesce(page_body, ''), 50000)
    )
  ) STORED;

CREATE INDEX IF NOT EXISTS idx_items_fts ON public.items USING gin(fts);

-- 2. HNSW vector index (better recall than ivfflat with no probes tuning)
DROP INDEX IF EXISTS embeddings_vector_idx;
CREATE INDEX IF NOT EXISTS idx_embeddings_hnsw ON public.embeddings
  USING hnsw (embedding vector_cosine_ops);

-- 3. Hybrid search: reciprocal-rank fusion of vector chunk hits and full-text
--    item hits. Items found only by keyword surface their first chunk (or a
--    field excerpt) so everything returns in one shape.
CREATE OR REPLACE FUNCTION hybrid_search_content(
  query_text text,
  query_embedding vector(1536),
  target_user_id uuid,
  match_count int DEFAULT 12,
  rrf_k int DEFAULT 50
)
RETURNS TABLE (
  item_id uuid,
  content_chunk text,
  item_title text,
  item_type item_type,
  item_url text,
  score double precision
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
WITH vector_hits AS (
  SELECT e.item_id, e.content_chunk,
         row_number() OVER (ORDER BY e.embedding <=> query_embedding) AS rank
  FROM embeddings e
  JOIN items i ON i.id = e.item_id
  WHERE i.user_id = target_user_id
  ORDER BY e.embedding <=> query_embedding
  LIMIT 30
),
fts_hits AS (
  SELECT i.id AS item_id,
         row_number() OVER (ORDER BY ts_rank_cd(i.fts, q) DESC) AS rank
  FROM items i, websearch_to_tsquery('english', query_text) q
  WHERE i.user_id = target_user_id AND i.fts @@ q
  LIMIT 30
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
  JOIN items i ON i.id = f.item_id
  WHERE NOT EXISTS (SELECT 1 FROM vector_hits v WHERE v.item_id = f.item_id)
)
SELECT s.item_id, s.content_chunk, i.title AS item_title, i.type AS item_type, i.url AS item_url, s.score
FROM (
  SELECT item_id, content_chunk, score FROM scored_chunks
  UNION ALL
  SELECT item_id, content_chunk, score FROM fts_only
) s
JOIN items i ON i.id = s.item_id
ORDER BY s.score DESC
LIMIT match_count;
$$;

-- 4. Realtime change feed on items (replaces per-card polling in the client)
DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.items;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;
