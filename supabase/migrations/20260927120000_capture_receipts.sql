-- Idempotent capture (iOS plan 15, contract: docs/PLATFORM_API.md → "POST /capture").
--
-- capture_receipts: one row per (user, client-generated capture_id) that has
-- reached the `capture` edge function. The function inserts a `pending` row
-- before forwarding to add-note / add-url / add-file, flips it to `done` with
-- the created item_id afterwards, and deletes it when the downstream call
-- fails — so a retry of the same capture_id, from any process at any time,
-- returns the first item instead of creating a second one. A `pending` row
-- whose updated_at is older than 120 s belongs to a dead attempt and may be
-- taken over (live attempts re-stamp updated_at every 30 s).
--
-- The function runs with the caller's JWT (no service role), so the owner
-- policies below are what it relies on. item_id is nulled when the user
-- deletes the item (a later retry then answers `{ item: null, duplicate: true }`);
-- rows go with the account.

CREATE TABLE IF NOT EXISTS public.capture_receipts (
  user_id    uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  capture_id uuid NOT NULL,
  item_id    uuid REFERENCES public.items(id) ON DELETE SET NULL,
  status     text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'done')),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, capture_id)
);

-- ON DELETE SET NULL from items scans by item_id.
CREATE INDEX IF NOT EXISTS capture_receipts_item_id_idx
  ON public.capture_receipts (item_id) WHERE item_id IS NOT NULL;

ALTER TABLE public.capture_receipts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "owner reads own capture receipts" ON public.capture_receipts;
CREATE POLICY "owner reads own capture receipts" ON public.capture_receipts
  FOR SELECT TO authenticated USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "owner creates own capture receipts" ON public.capture_receipts;
CREATE POLICY "owner creates own capture receipts" ON public.capture_receipts
  FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "owner updates own capture receipts" ON public.capture_receipts;
CREATE POLICY "owner updates own capture receipts" ON public.capture_receipts
  FOR UPDATE TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "owner deletes own capture receipts" ON public.capture_receipts;
CREATE POLICY "owner deletes own capture receipts" ON public.capture_receipts
  FOR DELETE TO authenticated USING (auth.uid() = user_id);

-- Same agent-token fence as every other user-data table (20260905120000).
DROP POLICY IF EXISTS "agent tokens: no direct access" ON public.capture_receipts;
CREATE POLICY "agent tokens: no direct access" ON public.capture_receipts
  AS RESTRICTIVE FOR ALL TO authenticated
  USING (NOT public.is_agent_token()) WITH CHECK (NOT public.is_agent_token());
