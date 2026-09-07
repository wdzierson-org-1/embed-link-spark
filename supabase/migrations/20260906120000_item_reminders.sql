-- Explicit reminders (spec: docs/superpowers/specs/2026-09-06-reminders-design.md).
-- "Due" and "expired" are derived from remind_at + reminder_cleared_at with a
-- 24h window; nothing here stores a due flag.
ALTER TABLE public.items
  ADD COLUMN IF NOT EXISTS remind_at timestamptz,
  ADD COLUMN IF NOT EXISTS reminder_cleared_at timestamptz,
  ADD COLUMN IF NOT EXISTS reminder_notified_at timestamptz;

COMMENT ON COLUMN public.items.remind_at IS
  'User-set "bring this back" time. Due for 24h from this instant unless cleared.';
COMMENT ON COLUMN public.items.reminder_cleared_at IS
  'Set by user dismissal, or by reminders_expire() 24h after remind_at. Null = still active.';
COMMENT ON COLUMN public.items.reminder_notified_at IS
  'When the reminder digest email included this item. Idempotency for the daily job.';

CREATE INDEX IF NOT EXISTS items_reminder_active
  ON public.items (user_id, remind_at)
  WHERE remind_at IS NOT NULL AND reminder_cleared_at IS NULL;

ALTER TABLE public.user_preferences
  ADD COLUMN IF NOT EXISTS reminder_emails boolean NOT NULL DEFAULT true;

-- Hygiene for the daily job: make expiry explicit in the data. Clients never
-- depend on this; they derive expiry from the 24h window themselves.
CREATE OR REPLACE FUNCTION public.reminders_expire()
RETURNS integer
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  WITH done AS (
    UPDATE public.items
       SET reminder_cleared_at = remind_at + interval '24 hours'
     WHERE remind_at IS NOT NULL
       AND reminder_cleared_at IS NULL
       AND remind_at + interval '24 hours' <= now()
    RETURNING 1
  )
  SELECT count(*)::integer FROM done;
$$;

REVOKE EXECUTE ON FUNCTION public.reminders_expire() FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.reminders_expire() TO service_role;
