-- Pictures inside a note are described and kept in attributes.note_images (docs/ui-changes.md
-- 2026-10-10 "Images in notes are read"; supabase/functions/_shared/noteImages.ts):
--   { version: 1, images: [{ src, description, text?, analyzed_at }] }
-- Written only by analyze-note-images, through this leaf compare-and-swap, like place and
-- object_facts: the caller says what it read (`expected`) and what it wants (`next`, null to
-- clear); the leaf is written only when nothing else moved it meanwhile. Other keys of the
-- attributes blob are untouched.
create or replace function public.set_item_note_images(target_id uuid, expected jsonb, next jsonb) returns boolean
language plpgsql security definer set search_path=public as $$
declare current_item public.items;
begin
  if next is not null and (
    jsonb_typeof(next) is distinct from 'object' or octet_length(next::text) > 64000
    or next->'version' is distinct from '1'::jsonb
    or jsonb_typeof(next->'images') is distinct from 'array'
  ) then return false; end if;
  select * into current_item from public.items where id = target_id
    and (user_id = auth.uid() or auth.role() = 'service_role') for update;
  if not found
    or coalesce(current_item.attributes->'note_images', 'null'::jsonb) is distinct from coalesce(expected, 'null'::jsonb)
    then return false; end if;
  if next is null then
    update public.items set attributes = coalesce(attributes, '{}'::jsonb) - 'note_images' where id = target_id;
  else
    update public.items set attributes = jsonb_set(coalesce(attributes, '{}'::jsonb), '{note_images}', next, true) where id = target_id;
  end if;
  return true;
end $$;

revoke all on function public.set_item_note_images(uuid, jsonb, jsonb) from public, anon;
grant execute on function public.set_item_note_images(uuid, jsonb, jsonb) to authenticated, service_role;
