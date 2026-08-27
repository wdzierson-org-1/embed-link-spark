-- Chat sessions (spec: docs/superpowers/specs/2026-08-27-chat-sessions-design.md).
-- Conversations become time-gap sessions — a client convention; the DB only
-- guarantees last_message_at stays accurate (trigger) and serves the list RPC.

ALTER TABLE public.conversations ADD COLUMN IF NOT EXISTS last_message_at timestamptz;

UPDATE public.conversations c
  SET last_message_at = COALESCE(
    (SELECT max(m.created_at) FROM public.messages m WHERE m.conversation_id = c.id),
    c.created_at)
  WHERE c.last_message_at IS NULL;

ALTER TABLE public.conversations ALTER COLUMN last_message_at SET DEFAULT now();
-- New sessions are created with title NULL and auto-titled after the first
-- exchange; make sure the column allows it (no-op if already nullable).
ALTER TABLE public.conversations ALTER COLUMN title DROP NOT NULL;

CREATE INDEX IF NOT EXISTS idx_conversations_user_last
  ON public.conversations (user_id, last_message_at DESC);

-- The trigger (not client writes) keeps ordering correct no matter which
-- client persists a message. SECURITY DEFINER so the owner-bypass covers the
-- parent-row update; the row being touched was already RLS-validated by the
-- message INSERT.
CREATE OR REPLACE FUNCTION public.touch_conversation_last_message()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.conversations
    SET last_message_at = NEW.created_at
    WHERE id = NEW.conversation_id;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_messages_touch_conversation ON public.messages;
CREATE TRIGGER trg_messages_touch_conversation
  AFTER INSERT ON public.messages
  FOR EACH ROW EXECUTE FUNCTION public.touch_conversation_last_message();

-- Conversations list: one round-trip for the view. SECURITY INVOKER — runs
-- under the caller's JWT, so the owner-scoped RLS on conversations/messages
-- does the tenant scoping (deliberately unlike hybrid_search_content).
CREATE OR REPLACE FUNCTION public.list_conversations()
RETURNS TABLE (
  id uuid,
  title text,
  last_message_at timestamptz,
  message_count bigint,
  preview text
)
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT c.id, c.title, c.last_message_at,
         (SELECT count(*) FROM messages m WHERE m.conversation_id = c.id) AS message_count,
         (SELECT left(m.content, 140) FROM messages m
            WHERE m.conversation_id = c.id AND m.role = 'assistant'
            ORDER BY m.created_at DESC LIMIT 1) AS preview
  FROM conversations c
  WHERE c.user_id = auth.uid()
  ORDER BY c.last_message_at DESC NULLS LAST
$$;

REVOKE EXECUTE ON FUNCTION public.list_conversations() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_conversations() TO authenticated, service_role;
