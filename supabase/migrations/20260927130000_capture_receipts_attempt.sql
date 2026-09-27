-- capture_receipts.attempt_id — fences each capture attempt (follow-up to
-- 20260927120000, contract: docs/PLATFORM_API.md → "POST /capture").
--
-- The `capture` function stamps a fresh attempt_id on every reservation and
-- every takeover of a stale pending receipt, and filters its heartbeat,
-- finalize and release writes by it. An attempt that stalled and was taken
-- over therefore can no longer overwrite or delete its successor's receipt:
-- its writes match zero rows, and if it finishes anyway it deletes the
-- duplicate item it created and answers 409. Null only on rows written before
-- this column existed.

ALTER TABLE public.capture_receipts ADD COLUMN IF NOT EXISTS attempt_id uuid;
