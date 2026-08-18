-- Extensible per-item attribute blob; first tenant is capture location.
-- Location is a first-class item attribute: full structure (coordinates for
-- future map views + place components + collection source) lives at
-- attributes.location, so new collectors (photo EXIF, manual entry, share
-- extension) and new attribute kinds need no further migrations.
ALTER TABLE public.items ADD COLUMN IF NOT EXISTS attributes jsonb NOT NULL DEFAULT '{}'::jsonb;

-- Fold the short-lived posted_from column (added earlier today, never
-- deployed to users, zero rows at migration time) into the blob, then retire
-- it so the blob is the single source of truth
UPDATE public.items
SET attributes = jsonb_set(
  attributes,
  '{location}',
  jsonb_build_object('label', posted_from, 'source', 'browser-geolocation'),
  true
)
WHERE posted_from IS NOT NULL;

ALTER TABLE public.items DROP COLUMN IF EXISTS posted_from;

-- One GIN index over the whole blob keeps containment/path queries fast
-- (e.g. attributes @> '{"location": {"city": "Brooklyn"}}') without
-- committing to per-key expression indexes yet
CREATE INDEX IF NOT EXISTS items_attributes_gin ON public.items USING gin (attributes);

COMMENT ON COLUMN public.items.attributes IS
  'Extensible per-item attributes (jsonb). Known keys: location {label, latitude, longitude, accuracy_m, city, region, country, source, captured_at}. See src/types/itemAttributes.ts.';
