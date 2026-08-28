-- Conversations list v2: search + pagination for the "Earlier conversations"
-- view. Signature and return shape change (search/page params, total_count),
-- so drop and recreate. Still SECURITY INVOKER — RLS does the tenant scoping.

DROP FUNCTION IF EXISTS public.list_conversations();

CREATE FUNCTION public.list_conversations(
  search_text text DEFAULT NULL,
  page_limit int DEFAULT 25,
  page_offset int DEFAULT 0
)
RETURNS TABLE (
  id uuid,
  title text,
  last_message_at timestamptz,
  message_count bigint,
  preview text,
  total_count bigint
)
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  WITH filtered AS (
    SELECT c.id, c.title, c.last_message_at
    FROM conversations c
    WHERE c.user_id = auth.uid()
      AND (
        search_text IS NULL OR btrim(search_text) = ''
        OR c.title ILIKE '%' || search_text || '%'
        OR EXISTS (
          SELECT 1 FROM messages m
          WHERE m.conversation_id = c.id
            AND m.content ILIKE '%' || search_text || '%'
        )
      )
  )
  SELECT f.id, f.title, f.last_message_at,
         (SELECT count(*) FROM messages m WHERE m.conversation_id = f.id) AS message_count,
         (SELECT left(m.content, 140) FROM messages m
            WHERE m.conversation_id = f.id AND m.role = 'assistant'
            ORDER BY m.created_at DESC LIMIT 1) AS preview,
         (SELECT count(*) FROM filtered) AS total_count
  FROM filtered f
  ORDER BY f.last_message_at DESC NULLS LAST
  LIMIT LEAST(GREATEST(page_limit, 1), 100)
  OFFSET GREATEST(page_offset, 0)
$$;

REVOKE EXECUTE ON FUNCTION public.list_conversations(text, int, int) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_conversations(text, int, int) TO authenticated, service_role;
