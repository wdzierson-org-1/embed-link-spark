-- Track background re-scrape attempts for links whose content couldn't be
-- fetched at save time (blocked sites). A pg_cron job invokes the
-- retry-pending-scrapes edge function on a schedule; these columns let it
-- back off per item and give up after enough failures.

ALTER TABLE public.items
  ADD COLUMN IF NOT EXISTS scrape_attempts int NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS last_scrape_attempt timestamptz;

CREATE INDEX IF NOT EXISTS idx_items_pending_scrape ON public.items (created_at)
  WHERE type = 'link' AND (page_body IS NULL OR page_body = '') AND scrape_attempts < 5;
