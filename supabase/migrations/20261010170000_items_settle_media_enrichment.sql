-- An audio/video save is enriched by the transcribe-audio job, which runs for minutes after
-- add-file answers. add-file therefore leaves attributes.enrichment.status = 'pending' for
-- those types (docs/ui-changes.md 2026-10-10 "One capture pipeline"), and the status settles
-- here, from the transcript's own state: 'done' → complete, 'failed' → partial. Living in the
-- row rather than in the job means every writer of the transcript (the job, its sweep, a
-- rebuild) settles the card the same way, whatever version of the function is deployed.
create or replace function public.items_settle_media_enrichment()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  prev_state text := old.attributes->'media'->'transcript'->>'status';
  next_state text := new.attributes->'media'->'transcript'->>'status';
begin
  if new.type not in ('audio', 'video') then return new; end if;
  if next_state is not distinct from prev_state then return new; end if;
  if next_state not in ('done', 'failed') then return new; end if;
  if coalesce(new.attributes->'enrichment'->>'status', 'pending') <> 'pending' then return new; end if;
  new.attributes := jsonb_set(
    coalesce(new.attributes, '{}'::jsonb),
    '{enrichment}',
    coalesce(new.attributes->'enrichment', '{}'::jsonb)
      || jsonb_build_object('status', case when next_state = 'done' then 'complete' else 'partial' end, 'updated_at', now())
  );
  return new;
end;
$$;

drop trigger if exists items_settle_media_enrichment on public.items;
create trigger items_settle_media_enrichment
  before update of attributes on public.items
  for each row execute function public.items_settle_media_enrichment();
