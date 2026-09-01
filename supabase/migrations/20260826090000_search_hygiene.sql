-- Search hygiene pass (retrieval overhaul phase 1):
--   1. items.fts gains summary + url (summary landed a day after the fts column
--      and was never folded in; url makes host/slug keywords findable).
--   2. hybrid_search_content: deterministic FTS top-30 (the old CTE applied
--      LIMIT without ORDER BY), a per-item cap of 2 vector chunks so one item
--      can't crowd out the result list, and created_at in the result shape.
--   3. Lock hybrid_search_content to service_role. It is SECURITY DEFINER with
--      a caller-supplied target_user_id (tenancy is enforced by the edge
--      functions, which pass a verified auth user id), so the default PUBLIC
--      EXECUTE grant let any API-key holder read any user's chunks via RPC.
--   4. Drop legacy search_similar_content (zero callers since RRF landed).
--   5. increment_tag_usage: tenancy guard (authenticated callers may only touch
--      their own namespace; service-role edge functions pass through).

-- 1. Rebuild the generated fts column (expressions can't be altered in place).
--    Dropping the column drops idx_items_fts with it.
ALTER TABLE public.items DROP COLUMN IF EXISTS fts;
ALTER TABLE public.items
  ADD COLUMN fts tsvector
  GENERATED ALWAYS AS (
    to_tsvector('english',
      coalesce(title, '') || ' ' ||
      coalesce(description, '') || ' ' ||
      coalesce(supplemental_note, '') || ' ' ||
      coalesce(url, '') || ' ' ||
      left(coalesce(summary, ''), 50000) || ' ' ||
      left(coalesce(content, ''), 50000) || ' ' ||
      left(coalesce(page_body, ''), 50000)
    )
  ) STORED;

CREATE INDEX IF NOT EXISTS idx_items_fts ON public.items USING gin(fts);

-- 2+3. Recreate the search RPC (return type changes, so drop first) and scope
--      its EXECUTE grant to service_role only.
DROP FUNCTION IF EXISTS public.hybrid_search_content(text, vector, uuid, int, int);

CREATE FUNCTION public.hybrid_search_content(
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
  item_created_at timestamptz,
  score double precision
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
WITH vector_candidates AS (
  SELECT e.item_id, e.content_chunk,
         e.embedding <=> query_embedding AS dist
  FROM embeddings e
  JOIN items i ON i.id = e.item_id
  WHERE i.user_id = target_user_id
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
    FROM items i, websearch_to_tsquery('english', query_text) q
    WHERE i.user_id = target_user_id AND i.fts @@ q
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
  JOIN items i ON i.id = f.item_id
  WHERE NOT EXISTS (SELECT 1 FROM vector_hits v WHERE v.item_id = f.item_id)
)
SELECT s.item_id, s.content_chunk, i.title AS item_title, i.type AS item_type,
       i.url AS item_url, i.created_at AS item_created_at, s.score
FROM (
  SELECT item_id, content_chunk, score FROM scored_chunks
  UNION ALL
  SELECT item_id, content_chunk, score FROM fts_only
) s
JOIN items i ON i.id = s.item_id
ORDER BY s.score DESC
LIMIT match_count;
$$;

REVOKE EXECUTE ON FUNCTION public.hybrid_search_content(text, vector, uuid, int, int)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.hybrid_search_content(text, vector, uuid, int, int)
  TO service_role;

-- 4. Legacy pure-vector RPC, superseded 2026-08-09, no remaining callers.
DROP FUNCTION IF EXISTS public.search_similar_content(vector, double precision, integer, uuid);

-- 5. Tenancy guard on the tag upsert RPC. Web (useTags) and iOS (ItemEditor)
--    call it with the user's own session; add-url calls it as service_role
--    (auth.uid() is NULL there). Anon-key callers are cut off entirely.
CREATE OR REPLACE FUNCTION public.increment_tag_usage(
  tag_name TEXT,
  user_uuid UUID
) RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  tag_id UUID;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() IS DISTINCT FROM user_uuid THEN
    RAISE EXCEPTION 'increment_tag_usage: user_uuid does not match the authenticated user';
  END IF;

  SELECT id INTO tag_id
  FROM public.tags
  WHERE name = LOWER(tag_name) AND user_id = user_uuid;

  IF tag_id IS NOT NULL THEN
    UPDATE public.tags
    SET usage_count = usage_count + 1,
        updated_at = now()
    WHERE id = tag_id;
  ELSE
    INSERT INTO public.tags (name, user_id, usage_count)
    VALUES (LOWER(tag_name), user_uuid, 1)
    RETURNING id INTO tag_id;
  END IF;

  RETURN tag_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.increment_tag_usage(text, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.increment_tag_usage(text, uuid) TO authenticated, service_role;
