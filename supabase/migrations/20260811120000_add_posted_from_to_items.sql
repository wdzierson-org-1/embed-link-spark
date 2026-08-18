-- Structured location for the capture panel's pin toggle.
-- Only the friendly place name is stored (never coordinates), and only when
-- the user opted in for that post. The human-visible "posted from …" line in
-- the note text remains the display source; this column exists so location is
-- queryable (filters, maps, interest graphs) without parsing note text.
ALTER TABLE public.items ADD COLUMN IF NOT EXISTS posted_from text;

COMMENT ON COLUMN public.items.posted_from IS
  'Friendly place name ("Brooklyn, New York") captured when the user enables the location pin at capture time; null when the pin was off';
