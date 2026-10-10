-- Round 2 of places (docs/ui-changes.md 2026-10-10 "Map-based shares"): a picture whose own text
-- carries a street address gets the same attributes.place lane once the address is confirmed on
-- the map — provider.kind 'ocr', evidence.method 'ocr-geocode', evidence.source_url the picture's
-- storage path. Same leaf compare-and-swap; images were already admitted, only the vocabulary
-- widens.
create or replace function public.set_item_place(target_id uuid, expected_url text, expected_place jsonb, place jsonb) returns boolean
language plpgsql security definer set search_path=public as $$
declare current_item public.items;
begin
  if jsonb_typeof(place) is distinct from 'object' or octet_length(place::text) > 16000
    or place->'version' is distinct from '1'::jsonb
    or jsonb_typeof(place->'provider') is distinct from 'object'
    or coalesce(place#>>'{provider,kind}', '') not in ('apple-maps', 'google-maps', 'page', 'ocr')
    or jsonb_typeof(place->'evidence') is distinct from 'object'
    or coalesce(place#>>'{evidence,method}', '') not in ('map-page', 'map-url', 'json-ld', 'ocr-geocode')
    or place#>>'{evidence,extraction_version}' is distinct from 'place-v1'
    or coalesce(place#>>'{evidence,observed_at}', '') !~ '^\d{4}-\d{2}-\d{2}T' then return false; end if;
  select * into current_item from public.items where id = target_id
    and (user_id = auth.uid() or auth.role() = 'service_role') for update;
  if not found or current_item.type not in ('link', 'image')
    or (current_item.type = 'link' and (current_item.url is distinct from expected_url or place#>>'{evidence,source_url}' is distinct from expected_url))
    or (current_item.type = 'image' and place#>>'{evidence,source_url}' is distinct from ('stash-media:' || coalesce(current_item.file_path, '')))
    or current_item.attributes#>'{enrichment,protected_fields,place}' = 'true'::jsonb
    or coalesce(current_item.attributes->'place', 'null'::jsonb) is distinct from coalesce(expected_place, 'null'::jsonb)
    then return false; end if;
  update public.items set attributes = jsonb_set(coalesce(attributes, '{}'::jsonb), '{place}', place, true) where id = target_id;
  insert into public.enrichment_jobs(item_id, next_run_at) values (target_id, now() + interval '2 minutes')
    on conflict (item_id) do update set next_run_at = now() + interval '2 minutes', revision = enrichment_jobs.revision + 1;
  return true;
end $$;
