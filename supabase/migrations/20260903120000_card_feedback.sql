-- Card feedback (ui-changes.md 2026-09-03): a beta tester flags a card whose
-- enrichment or rendering looks wrong. One row per report; `issues` holds the
-- checked codes (contract: src/utils/cardFeedback.ts), `snapshot` freezes what
-- the card showed at the time so the report stays meaningful after the item
-- is re-enriched or deleted. Users write/read their own rows; review happens
-- with the service role (scripts/card-feedback-report.ts).

CREATE TABLE IF NOT EXISTS public.card_feedback (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  item_id uuid REFERENCES public.items(id) ON DELETE SET NULL,
  issues text[] NOT NULL CHECK (cardinality(issues) > 0),
  note text,
  client text NOT NULL DEFAULT 'web',      -- 'web' | 'ios' | 'extension' | 'macos'
  snapshot jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS card_feedback_created_at_idx ON public.card_feedback (created_at DESC);

ALTER TABLE public.card_feedback ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can create their own card feedback"
  ON public.card_feedback FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can view their own card feedback"
  ON public.card_feedback FOR SELECT
  USING (auth.uid() = user_id);
