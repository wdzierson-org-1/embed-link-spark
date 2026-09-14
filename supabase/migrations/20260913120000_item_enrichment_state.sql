-- Merge only the enrichment key, preserving concurrently edited location/media.
create or replace function public.set_item_enrichment(target_id uuid, next_status text)
returns void
language plpgsql
security invoker
set search_path = public
as $$
begin
  if next_status not in ('pending', 'complete', 'partial') then
    raise exception 'Invalid enrichment status';
  end if;
  update public.items
  set attributes = jsonb_set(coalesce(attributes, '{}'::jsonb), '{enrichment}',
    jsonb_build_object('status', next_status, 'updated_at', now()))
  where id = target_id and (user_id = auth.uid() or auth.role() = 'service_role');
end;
$$;
revoke all on function public.set_item_enrichment(uuid, text) from public, anon;
grant execute on function public.set_item_enrichment(uuid, text) to authenticated, service_role;
