-- A persistent assessment/repair queue, source scorecards, and held-out retrieval evaluations.
-- Internal tables are service-role only. No saved content is made public by these diagnostics.
create table public.enrichment_quality (
  item_id uuid primary key references public.items(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  source_key text not null, source text not null, kind text not null, quality_version text not null,
  status text not null check (status in ('ready','partial','blocked','unsupported')),
  score integer not null check (score between 0 and 100), reasons text[] not null default '{}',
  content_usable boolean not null, card_usable boolean not null,
  index_state text not null check (index_state in ('present','missing','unknown')),
  evidence jsonb not null default '{}', evaluated_at timestamptz not null default now(),
  first_ready_at timestamptz
);
create index on public.enrichment_quality(source_key, evaluated_at);
create table public.enrichment_jobs (
  item_id uuid primary key references public.items(id) on delete cascade,
  next_run_at timestamptz not null default now(), revision bigint not null default 1,
  lease_token uuid, leased_until timestamptz, attempts integer not null default 0,
  quality_version text, provider_state jsonb not null default '{}', last_error text,
  updated_at timestamptz not null default now()
);
create index on public.enrichment_jobs(next_run_at, leased_until);
create table public.enrichment_attempts (
  id uuid primary key default gen_random_uuid(),
  item_id uuid not null references public.items(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  source_key text not null, quality_version text not null, strategy text not null,
  outcome text not null check (outcome in ('assessed','improved','unchanged','failed','deferred')),
  before_score integer, after_score integer, reasons text[] not null default '{}',
  elapsed_ms integer not null default 0, cost_usd numeric, created_at timestamptz not null default now()
);
create index on public.enrichment_attempts(source_key, created_at);
create table public.enrichment_revisions (
  id uuid primary key default gen_random_uuid(), item_id uuid not null references public.items(id) on delete cascade,
  before_values jsonb not null, after_values jsonb not null, strategy text not null, created_at timestamptz not null default now()
);
create table public.enrichment_sources (
  source_key text primary key, cadence text not null default 'hourly' check(cadence in ('hourly','daily')),
  healthy_streak integer not null default 0, next_review_at timestamptz not null default now(),
  metrics jsonb not null default '{}', updated_at timestamptz not null default now()
);
create table public.enrichment_eval_cases (
  id uuid primary key default gen_random_uuid(), user_id uuid not null references auth.users(id) on delete cascade,
  item_id uuid not null references public.items(id) on delete cascade, query text not null,
  expect_in_top integer not null default 5 check(expect_in_top between 1 and 50),
  verified boolean not null default false, enabled boolean not null default true,
  created_at timestamptz not null default now()
);
create table public.enrichment_eval_results (
  id uuid primary key default gen_random_uuid(), case_id uuid not null references public.enrichment_eval_cases(id) on delete cascade,
  run_day date not null default (now() at time zone 'UTC')::date, quality_version text not null,
  rank integer, passed boolean, error text, result_ids uuid[], created_at timestamptz not null default now(),
  unique(case_id, run_day, quality_version)
);
-- Review candidates arise from observed failures, not self-generated positive labels.
create table public.enrichment_review_candidates (
  item_id uuid primary key references public.items(id) on delete cascade,
  source_key text not null, reasons text[] not null, occurrences integer not null default 1,
  first_seen_at timestamptz not null default now(), last_seen_at timestamptz not null default now(),
  resolved_at timestamptz
);
do $$ declare t text; begin
  foreach t in array array['enrichment_quality','enrichment_jobs','enrichment_attempts','enrichment_revisions','enrichment_sources','enrichment_eval_cases','enrichment_eval_results','enrichment_review_candidates'] loop
    execute format('alter table public.%I enable row level security',t);
    execute format('revoke all on public.%I from anon, authenticated',t);
    execute format('grant all on public.%I to service_role',t);
  end loop;
end $$;

-- Client edits become field locks. Subsequent server re-enrichment preserves these fields.
create function public.protect_enrichment_edits() returns trigger language plpgsql set search_path=public as $$
declare k text; protected jsonb;
begin
  protected := coalesce(old.attributes->'enrichment'->'protected_fields','{}'::jsonb);
  if auth.role() = 'authenticated' then
    foreach k in array array['title','description','summary','page_body','file_path'] loop
      if to_jsonb(new)->k is distinct from to_jsonb(old)->k then protected := protected || jsonb_build_object(k,true); end if;
    end loop;
  end if;
  if protected <> '{}'::jsonb then
    new.attributes := jsonb_set(coalesce(new.attributes,'{}'::jsonb),'{enrichment}',
      coalesce(new.attributes->'enrichment','{}'::jsonb) || jsonb_build_object('protected_fields',protected));
  end if;
  return new;
end $$;
create trigger protect_enrichment_edits before update on public.items for each row execute function public.protect_enrichment_edits();

create function public.enqueue_enrichment_assessment() returns trigger language plpgsql security definer set search_path=public as $$
begin
  if current_setting('stash.enrichment_worker',true) = 'on' then return new; end if;
  if tg_op = 'UPDATE' and
    row(new.title,new.description,new.summary,new.page_body,new.content,new.supplemental_note,new.url,new.file_path,new.mime_type,new.attributes->'media',new.attributes->'enrichment'->'evidence')
    is not distinct from
    row(old.title,old.description,old.summary,old.page_body,old.content,old.supplemental_note,old.url,old.file_path,old.mime_type,old.attributes->'media',old.attributes->'enrichment'->'evidence') then return new; end if;
  insert into public.enrichment_jobs(item_id,next_run_at) values(new.id,now()+interval '2 minutes')
  on conflict(item_id) do update set next_run_at=now()+interval '2 minutes', revision=enrichment_jobs.revision+1,
    attempts=0, provider_state='{}', last_error=null, updated_at=now();
  return new;
end $$;
create trigger enqueue_enrichment_assessment after insert or update on public.items for each row execute function public.enqueue_enrichment_assessment();

create function public.enqueue_enrichment_feedback() returns trigger language plpgsql security definer set search_path=public as $$
begin
  if new.item_id is not null then
    insert into public.enrichment_jobs(item_id) values(new.item_id)
    on conflict(item_id) do update set next_run_at=now(), revision=enrichment_jobs.revision+1, attempts=0, updated_at=now();
  end if;
  return new;
end $$;
create trigger enqueue_enrichment_feedback after insert on public.card_feedback for each row execute function public.enqueue_enrichment_feedback();

create function public.claim_enrichment_jobs(batch_size integer, worker_version text)
returns setof public.enrichment_jobs language plpgsql security definer set search_path=public as $$
begin
  return query with due as (
    select j.item_id from enrichment_jobs j
    where (j.next_run_at <= now() or j.quality_version is distinct from worker_version)
      and (j.leased_until is null or j.leased_until < now())
    order by j.next_run_at, j.item_id for update skip locked limit greatest(1,least(batch_size,25))
  ) update enrichment_jobs j set lease_token=gen_random_uuid(), leased_until=now()+interval '10 minutes',
    attempts=case when j.quality_version is distinct from worker_version then 0 else j.attempts end,
    provider_state=case when j.quality_version is distinct from worker_version then '{}'::jsonb else j.provider_state end,
    quality_version=worker_version, updated_at=now()
    from due where j.item_id=due.item_id returning j.*;
end $$;

create function public.finish_enrichment_job(target_id uuid, token uuid, expected_revision bigint,
  delay_hours double precision, spent_attempt boolean, next_provider_state jsonb default '{}', failure text default null)
returns boolean language plpgsql security definer set search_path=public as $$
declare n integer;
begin
  update enrichment_jobs set
    next_run_at=case when revision=expected_revision then now()+make_interval(secs=>greatest(60,least(delay_hours*3600,604800))) else next_run_at end,
    attempts=case when revision=expected_revision and spent_attempt then attempts+1 else attempts end,
    provider_state=case when revision=expected_revision then next_provider_state else provider_state end,
    last_error=left(failure,500), lease_token=null, leased_until=null, updated_at=now()
  where item_id=target_id and lease_token=token;
  get diagnostics n=row_count; return n=1;
end $$;

-- Compare source fields under a row lock. User notes are never patchable. Keep a reversible history.
create function public.apply_enrichment_patch(target_id uuid, token uuid, expected jsonb, patch jsonb,
  strategy_name text, evidence_patch jsonb default '{}') returns boolean
language plpgsql security definer set search_path=public as $$
declare i public.items; k text; clean_patch jsonb := '{}'; before_patch jsonb := '{}'; attrs jsonb;
begin
  select * into i from items where id=target_id for update;
  if not found then return false; end if;
  if token is not null and not exists(select 1 from enrichment_jobs where item_id=target_id and lease_token=token and leased_until>now()) then return false; end if;
  for k in select jsonb_object_keys(expected) loop
    if to_jsonb(i)->k is distinct from expected->k then return false; end if;
  end loop;
  for k in select jsonb_object_keys(patch) loop
    if k not in ('title','description','summary','page_body','file_path') then raise exception 'Unmanaged enrichment field'; end if;
    if jsonb_typeof(patch->k) not in ('string','null') then raise exception 'Invalid enrichment value'; end if;
    if coalesce((i.attributes->'enrichment'->'protected_fields'->>k)::boolean,false) then continue; end if;
    if to_jsonb(i)->k is distinct from patch->k then
      clean_patch := clean_patch || jsonb_build_object(k,patch->k); before_patch := before_patch || jsonb_build_object(k,to_jsonb(i)->k);
    end if;
  end loop;
  attrs := coalesce(i.attributes,'{}'::jsonb);
  if evidence_patch <> '{}'::jsonb and not coalesce((i.attributes->'enrichment'->'protected_fields'->>'page_body')::boolean,false) then
    attrs := jsonb_set(attrs,'{enrichment}',coalesce(attrs->'enrichment','{}'::jsonb) ||
      jsonb_build_object('evidence',coalesce(attrs->'enrichment'->'evidence','{}'::jsonb)||evidence_patch));
  end if;
  if clean_patch = '{}'::jsonb and attrs = coalesce(i.attributes,'{}'::jsonb) then return true; end if;
  if token is not null then perform set_config('stash.enrichment_worker','on',true); end if;
  update items set title=case when clean_patch?'title' then clean_patch->>'title' else title end,
    description=case when clean_patch?'description' then clean_patch->>'description' else description end,
    summary=case when clean_patch?'summary' then clean_patch->>'summary' else summary end,
    page_body=case when clean_patch?'page_body' then clean_patch->>'page_body' else page_body end,
    file_path=case when clean_patch?'file_path' then clean_patch->>'file_path' else file_path end, attributes=attrs
    where id=target_id;
  insert into enrichment_revisions(item_id,before_values,after_values,strategy)
    values(target_id,before_patch||jsonb_build_object('attributes',i.attributes),clean_patch||jsonb_build_object('attributes',attrs),strategy_name);
  return true;
end $$;

-- Existing callers set status; preserve evidence/protected fields written by the new loop.
create or replace function public.set_item_enrichment(target_id uuid,next_status text) returns void
language plpgsql security invoker set search_path=public as $$
begin
  if next_status not in ('pending','complete','partial') then raise exception 'Invalid enrichment status'; end if;
  update items set attributes=jsonb_set(coalesce(attributes,'{}'::jsonb),'{enrichment}',
    coalesce(attributes->'enrichment','{}'::jsonb)||jsonb_build_object('status',next_status,'updated_at',now()))
    where id=target_id and (user_id=auth.uid() or auth.role()='service_role');
end $$;

create function public.enrichment_source_metrics() returns jsonb language sql stable security definer set search_path=public as $$
with q as (
  select source_key, count(*) assessed, count(*) filter(where status='ready') ready,
    count(*) filter(where status='blocked') blocked, count(*) filter(where status='unsupported') unsupported,
    count(*) filter(where content_usable) content_usable, count(*) filter(where card_usable) card_usable,
    count(*) filter(where index_state='present') indexed
  from enrichment_quality where evaluated_at>now()-interval '7 days' group by source_key
), a as (
  select source_key, count(*) filter(where outcome<>'assessed') attempts,
    count(*) filter(where outcome='failed') failures, count(distinct item_id) filter(where outcome='improved') recovered,
    percentile_cont(0.95) within group(order by elapsed_ms) filter(where outcome<>'assessed') p95_ms,
    sum(cost_usd) cost_usd from enrichment_attempts where created_at>now()-interval '7 days' group by source_key
)
select coalesce(jsonb_agg(to_jsonb(q)||jsonb_build_object('attempts',coalesce(a.attempts,0),'failures',coalesce(a.failures,0),
  'recovered',coalesce(a.recovered,0),'p95_ms',a.p95_ms,'cost_usd',a.cost_usd,
  'cadence',coalesce(s.cadence,'hourly'),'next_review_at',s.next_review_at) order by q.source_key),'[]'::jsonb)
from q left join a using(source_key) left join enrichment_sources s using(source_key);
$$;
-- All worker RPCs are internal even when called through PostgREST.
revoke all on function public.claim_enrichment_jobs(integer,text) from public,anon,authenticated;
revoke all on function public.finish_enrichment_job(uuid,uuid,bigint,double precision,boolean,jsonb,text) from public,anon,authenticated;
revoke all on function public.apply_enrichment_patch(uuid,uuid,jsonb,jsonb,text,jsonb) from public,anon,authenticated;
revoke all on function public.enrichment_source_metrics() from public,anon,authenticated;
grant execute on function public.claim_enrichment_jobs(integer,text) to service_role;
grant execute on function public.finish_enrichment_job(uuid,uuid,bigint,double precision,boolean,jsonb,text) to service_role;
grant execute on function public.apply_enrichment_patch(uuid,uuid,jsonb,jsonb,text,jsonb) to service_role;
grant execute on function public.enrichment_source_metrics() to service_role;

-- Audit the existing library, including nonempty-but-useless captures and saves older than 30 days.
-- This migration schedules assessment only; the bounded worker makes any subsequent repairs.
insert into public.enrichment_jobs(item_id) select id from public.items on conflict do nothing;

create table public.enrichment_index_state (
  item_id uuid primary key references public.items(id) on delete cascade,
  fingerprint text not null, chunks integer not null, updated_at timestamptz not null default now()
);
alter table public.enrichment_index_state enable row level security;
revoke all on public.enrichment_index_state from anon,authenticated;
grant all on public.enrichment_index_state to service_role;
create function public.replace_item_embeddings(target_id uuid, expected jsonb, chunks jsonb, fingerprint text)
returns boolean language plpgsql security definer set search_path=public,extensions as $$
declare i public.items; k text;
begin
  select * into i from items where id=target_id for update;
  if not found then return false; end if;
  for k in select jsonb_object_keys(expected) loop
    if to_jsonb(i)->k is distinct from expected->k then return false; end if;
  end loop;
  if jsonb_typeof(chunks)<>'array' or jsonb_array_length(chunks)>500 then raise exception 'Invalid chunks'; end if;
  delete from embeddings where item_id=target_id;
  insert into embeddings(item_id,content_chunk,chunk_index,embedding)
    select target_id,c->>'text',(ord-1)::integer,(c->>'embedding')::vector
    from jsonb_array_elements(chunks) with ordinality as v(c,ord);
  insert into enrichment_index_state(item_id,fingerprint,chunks) values(target_id,fingerprint,jsonb_array_length(chunks))
    on conflict(item_id) do update set fingerprint=excluded.fingerprint,chunks=excluded.chunks,updated_at=now();
  return true;
end $$;
revoke all on function public.replace_item_embeddings(uuid,jsonb,jsonb,text) from public,anon,authenticated;
grant execute on function public.replace_item_embeddings(uuid,jsonb,jsonb,text) to service_role;

-- Global lease prevents overlapping invocations; atomic daily allowances bound provider work.
create table public.enrichment_control (
  singleton boolean primary key default true check(singleton), run_token uuid, leased_until timestamptz,
  budget_day date not null default current_date, repairs_used integer not null default 0
);
insert into public.enrichment_control(singleton) values(true);
alter table public.enrichment_control enable row level security;
revoke all on public.enrichment_control from anon,authenticated;
grant all on public.enrichment_control to service_role;
create function public.begin_enrichment_run() returns uuid language plpgsql security definer set search_path=public as $$
declare t uuid;
begin
  update enrichment_control set run_token=gen_random_uuid(),leased_until=now()+interval '5 minutes'
  where singleton and (leased_until is null or leased_until<now()) returning run_token into t;
  return t;
end $$;
create function public.reserve_enrichment_repair(token uuid,daily_limit integer) returns boolean
language plpgsql security definer set search_path=public as $$
declare n integer;
begin
  update enrichment_control set repairs_used=case when budget_day=current_date then repairs_used+1 else 1 end,budget_day=current_date
  where singleton and run_token=token and leased_until>now() and daily_limit>0
    and (budget_day<>current_date or repairs_used<least(daily_limit,500));
  get diagnostics n=row_count; return n=1;
end $$;
create function public.end_enrichment_run(token uuid) returns void language sql security definer set search_path=public as $$
  update enrichment_control set run_token=null,leased_until=null where singleton and run_token=token;
$$;
revoke all on function public.begin_enrichment_run() from public,anon,authenticated;
revoke all on function public.reserve_enrichment_repair(uuid,integer) from public,anon,authenticated;
revoke all on function public.end_enrichment_run(uuid) from public,anon,authenticated;
grant execute on function public.begin_enrichment_run() to service_role;
grant execute on function public.reserve_enrichment_repair(uuid,integer) to service_role;
grant execute on function public.end_enrichment_run(uuid) to service_role;

-- Only human-verified, owner-matched cases become evaluation labels. A generated query is not ground truth.
create function public.pending_enrichment_evals(worker_version text,batch_size integer)
returns setof public.enrichment_eval_cases language sql stable security definer set search_path=public as $$
  select c.* from enrichment_eval_cases c join items i on i.id=c.item_id and i.user_id=c.user_id
  where c.verified and c.enabled and not exists(select 1 from enrichment_eval_results r where r.case_id=c.id
    and r.run_day=(now() at time zone 'UTC')::date and r.quality_version=worker_version)
  order by c.created_at,c.id limit greatest(0,least(batch_size,10));
$$;
revoke all on function public.pending_enrichment_evals(text,integer) from public,anon,authenticated;
grant execute on function public.pending_enrichment_evals(text,integer) to service_role;
