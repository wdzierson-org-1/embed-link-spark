-- MCP server (spec: docs/superpowers/specs/2026-09-05-mcp-server-design.md).
--
-- agent_grants: one row per (user, OAuth client) the user approved on
-- /oauth/consent. The mcp function refuses any token whose client has no
-- active row. Owner may read/insert/update (consent page, Settings revoke);
-- no delete — history stays. Service role bypasses RLS.
--
-- agent_access_log: one row per tool call, user-readable (Settings →
-- Connected agents → Activity) and the rate-limit ledger. Written by the mcp
-- function with the service role.
--
-- is_agent_token() + RESTRICTIVE policies: a Supabase OAuth access token is a
-- full user JWT. Without this fence an agent token could read every table
-- through PostgREST. Restrictive policies AND with the existing permissive
-- ones, so normal sessions are unaffected and agent tokens get zero rows —
-- "copies are unsupported by architecture".

CREATE TABLE IF NOT EXISTS public.agent_grants (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  client_id    text NOT NULL,
  client_name  text NOT NULL,
  client_uri   text,
  scopes       text[] NOT NULL DEFAULT '{read}',
  created_at   timestamptz NOT NULL DEFAULT now(),
  last_used_at timestamptz,
  revoked_at   timestamptz,
  UNIQUE (user_id, client_id)
);

CREATE INDEX IF NOT EXISTS idx_agent_grants_user ON public.agent_grants (user_id, created_at DESC);

ALTER TABLE public.agent_grants ENABLE ROW LEVEL SECURITY;

CREATE POLICY "owner reads own grants" ON public.agent_grants
  FOR SELECT TO authenticated USING (user_id = auth.uid());
CREATE POLICY "owner creates own grants" ON public.agent_grants
  FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());
CREATE POLICY "owner updates own grants" ON public.agent_grants
  FOR UPDATE TO authenticated USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

CREATE TABLE IF NOT EXISTS public.agent_access_log (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      uuid NOT NULL,
  grant_id     uuid NOT NULL REFERENCES public.agent_grants(id) ON DELETE CASCADE,
  client_id    text NOT NULL,
  tool         text NOT NULL,
  query        text,
  filters      jsonb,
  item_id      uuid,
  item_title   text,
  result_count int,
  created_at   timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_agent_access_log_user_time ON public.agent_access_log (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_agent_access_log_grant_time ON public.agent_access_log (grant_id, created_at DESC);

ALTER TABLE public.agent_access_log ENABLE ROW LEVEL SECURITY;

CREATE POLICY "owner reads own agent activity" ON public.agent_access_log
  FOR SELECT TO authenticated USING (user_id = auth.uid());

CREATE OR REPLACE FUNCTION public.is_agent_token() RETURNS boolean
  LANGUAGE sql STABLE
  SET search_path = public
AS $$
  SELECT coalesce(auth.jwt() ->> 'client_id', '') <> ''
$$;

-- The fence. One restrictive policy per user-data table.
DO $$
DECLARE
  t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'items', 'embeddings', 'tags', 'item_tags', 'item_attachments',
    'conversations', 'messages', 'comments', 'card_feedback', 'chat_feedback',
    'sms_conversations', 'user_follows', 'user_phone_numbers',
    'user_preferences', 'user_profiles', 'agent_grants', 'agent_access_log'
  ] LOOP
    EXECUTE format(
      'DROP POLICY IF EXISTS "agent tokens: no direct access" ON public.%I', t);
    EXECUTE format(
      'CREATE POLICY "agent tokens: no direct access" ON public.%I AS RESTRICTIVE FOR ALL TO authenticated USING (NOT public.is_agent_token()) WITH CHECK (NOT public.is_agent_token())', t);
  END LOOP;
END $$;

DROP POLICY IF EXISTS "agent tokens: no storage access" ON storage.objects;
CREATE POLICY "agent tokens: no storage access" ON storage.objects
  AS RESTRICTIVE FOR ALL TO authenticated
  USING (NOT public.is_agent_token()) WITH CHECK (NOT public.is_agent_token());
