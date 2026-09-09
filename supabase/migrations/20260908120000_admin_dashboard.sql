-- Temporary admin dashboard
-- (spec: docs/superpowers/specs/2026-09-08-admin-dashboard-design.md).
--
-- admin_users: who may open /admin and call the admin-stats function. Only
-- your own row is readable (the web app uses that to show the menu item);
-- nobody but the service role can write.
--
-- KILL SWITCH for the whole feature, once there are enough members:
--   DELETE FROM public.admin_users;
-- The menu item disappears and every admin endpoint returns 403.
--
-- admin_user_stats(): per-user sign-in + saving stats from auth.users,
-- auth.audit_log_entries, user_profiles and items. SECURITY DEFINER because
-- the auth schema is never exposed through PostgREST; EXECUTE is granted to
-- the service role only, so the edge function (which checks admin_users) is
-- the sole caller.

CREATE TABLE IF NOT EXISTS public.admin_users (
  user_id    uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.admin_users ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "admins read their own row" ON public.admin_users;
CREATE POLICY "admins read their own row" ON public.admin_users
  FOR SELECT TO authenticated USING (user_id = auth.uid());

-- Same agent-token fence as every other table (20260905120000).
DROP POLICY IF EXISTS "agent tokens: no direct access" ON public.admin_users;
CREATE POLICY "agent tokens: no direct access" ON public.admin_users
  AS RESTRICTIVE FOR ALL TO authenticated
  USING (NOT public.is_agent_token()) WITH CHECK (NOT public.is_agent_token());

INSERT INTO public.admin_users (user_id)
  SELECT id FROM auth.users WHERE email = 'will@dzierson.com'
  ON CONFLICT DO NOTHING;

CREATE OR REPLACE FUNCTION public.admin_user_stats()
RETURNS TABLE (
  user_id         uuid,
  email           text,
  username        text,
  display_name    text,
  is_anonymous    boolean,
  created_at      timestamptz,
  last_sign_in_at timestamptz,
  total_logins    bigint,
  active_days     bigint,
  last_active_at  timestamptz,
  item_count      bigint,
  items_last_7d   bigint,
  last_item_at    timestamptz,
  items_by_type   jsonb
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH auth_events AS (
    -- Explicit sign-ins plus token refreshes: sessions persist for weeks, so
    -- a refresh is the honest "the app was open today" signal.
    SELECT (e.payload->>'actor_id')::uuid AS actor_id,
           e.payload->>'action'           AS action,
           e.created_at                   AS at
      FROM auth.audit_log_entries e
     WHERE e.payload->>'action' IN ('login', 'token_refreshed')
       AND e.payload->>'actor_id' ~ '^[0-9a-fA-F-]{36}$'
  ),
  activity AS (
    SELECT ae.actor_id,
           count(*) FILTER (WHERE ae.action = 'login')          AS total_logins,
           count(DISTINCT (ae.at AT TIME ZONE 'UTC')::date)     AS active_days,
           max(ae.at)                                           AS last_active_at
      FROM auth_events ae
     GROUP BY ae.actor_id
  ),
  per_type AS (
    SELECT i.user_id                       AS owner_id,
           i.type::text                    AS item_type,
           count(*)                        AS n,
           count(*) FILTER (WHERE i.created_at >= now() - interval '7 days') AS n_7d,
           max(i.created_at)               AS last_at
      FROM public.items i
     GROUP BY i.user_id, i.type
  ),
  item_stats AS (
    SELECT pt.owner_id,
           sum(pt.n)::bigint                    AS item_count,
           sum(pt.n_7d)::bigint                 AS items_last_7d,
           max(pt.last_at)                      AS last_item_at,
           jsonb_object_agg(pt.item_type, pt.n) AS items_by_type
      FROM per_type pt
     GROUP BY pt.owner_id
  )
  SELECT u.id,
         u.email::text,
         p.username,
         p.display_name,
         coalesce(u.is_anonymous, false),
         u.created_at,
         u.last_sign_in_at,
         coalesce(a.total_logins, 0),
         coalesce(a.active_days, 0),
         a.last_active_at,
         coalesce(s.item_count, 0),
         coalesce(s.items_last_7d, 0),
         s.last_item_at,
         coalesce(s.items_by_type, '{}'::jsonb)
    FROM auth.users u
    LEFT JOIN public.user_profiles p ON p.id = u.id
    LEFT JOIN activity a ON a.actor_id = u.id
    LEFT JOIN item_stats s ON s.owner_id = u.id
   ORDER BY u.created_at DESC
$$;

REVOKE ALL ON FUNCTION public.admin_user_stats() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_user_stats() TO service_role;
