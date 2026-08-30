-- Inbound intent gate, WhatsApp/SMS state (spec: docs/superpowers/specs/
-- 2026-08-29-ask-retrieval-reliability-and-intent-gate-spec.md, G2/G3).
--
-- One short-lived row per user+channel holding either an unresolved
-- "save it or answer it?" question (kind='confirm', payload carries the
-- original message) or an undo/switch handle after an auto-action
-- (kind='undo', payload carries item_id + original text). The webhook
-- treats rows older than 15 minutes as expired. Service-role only
-- (RLS on, no policies).

CREATE TABLE IF NOT EXISTS public.pending_intents (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  channel text NOT NULL,             -- 'whatsapp' | 'sms'
  phone_number text NOT NULL,
  kind text NOT NULL CHECK (kind IN ('confirm', 'undo')),
  payload jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, channel)
);

ALTER TABLE public.pending_intents ENABLE ROW LEVEL SECURITY;
