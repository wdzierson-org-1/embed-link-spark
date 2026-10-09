-- Additive hosted audits/research. This queue never claims repair jobs or writes items.
create extension if not exists pgcrypto with schema extensions;

create table public.hosted_quality_jobs (
  id uuid primary key default gen_random_uuid(),
  kind text not null check(kind in ('audit','research')),
  dedupe_key text not null unique,
  input jsonb not null check(jsonb_typeof(input)='object' and octet_length(input::text)<=250000),
  input_hash text not null,
  status text not null default 'queued' check(status in ('queued','running','completed','failed')),
  available_at timestamptz not null default now(), attempts integer not null default 0,
  lease_token uuid, fence bigint not null default 0, lease_expires_at timestamptz, deadline_at timestamptz,
  model_calls integer not null default 0, last_error text, created_at timestamptz not null default now(), completed_at timestamptz
);
create index hosted_quality_due on public.hosted_quality_jobs(status,available_at,lease_expires_at);
create table public.hosted_quality_results (
  job_id uuid primary key references public.hosted_quality_jobs(id) on delete cascade,
  fence bigint not null, lease_token uuid not null, result jsonb not null, usage jsonb not null default '{}',
  payload_hash text not null, created_at timestamptz not null default now(),
  check(octet_length(result::text)<=128000 and result->>'schema_version'='1')
);
create table public.hosted_quality_reports (
  id uuid primary key default gen_random_uuid(), recipient text not null, report_day date not null,
  version text not null default 'hosted-v1', payload jsonb not null, created_at timestamptz not null default now(),
  unique(recipient,report_day,version)
);
create table public.hosted_quality_outbox (
  id uuid primary key default gen_random_uuid(), report_id uuid not null unique references public.hosted_quality_reports(id) on delete cascade,
  status text not null default 'queued' check(status in ('queued','sending','accepted','failed','uncertain')),
  idempotency_key text not null unique, lease_token uuid, lease_expires_at timestamptz,
  attempts integer not null default 0, next_attempt_at timestamptz not null default now(),
  first_attempt_at timestamptz, accepted_at timestamptz, provider_id text, last_error text
);
do $$ declare t text; begin
  foreach t in array array['hosted_quality_jobs','hosted_quality_results','hosted_quality_reports','hosted_quality_outbox'] loop
    execute format('alter table public.%I enable row level security',t);
    execute format('revoke all on public.%I from public,anon,authenticated',t);
    execute format('grant all on public.%I to service_role',t);
  end loop;
end $$;

-- Inputs deliberately exclude user annotations/content, credentials, storage URLs and arbitrary attributes.
-- The configured UUID allowlist is supplied only by the cron-authenticated backend.
create function public.enqueue_hosted_quality_jobs(scope_user_ids uuid[],include_research boolean default false) returns jsonb
language plpgsql security definer set search_path=public,extensions as $$
declare sampled jsonb; snapshot jsonb; k text; bucket text; inserted integer:=0; n integer;
begin
  if coalesce(cardinality(scope_user_ids),0) not between 1 and 20 then raise exception 'Invalid scope'; end if;
  -- Serialize snapshot/report creation with item deletion so a stale read cannot recreate a purged copy.
  perform pg_advisory_xact_lock(620260109::bigint);
  with eligible as (
    select i.id,i.created_at,q.status from items i left join enrichment_quality q on q.item_id=i.id
    where i.user_id=any(scope_user_ids) and i.type='link'
      and i.url ~ '^https://[^/@:]+(\.[^/@:]+)+(/|$)' and length(i.url)<=2000
      and i.url !~* '^https://([0-9.]+|[^/]*\.(local|internal|localhost))(/|$)'
      and i.url !~* '[?&](access_token|token|key|code|password|signature|x-amz-[^=]*)='
  ), picks as (
    (select id,0 priority from eligible where created_at>=now()-interval '24 hours' order by created_at desc,id limit 2)
    union all
    (select id,1 priority from eligible where created_at<now()-interval '24 hours' and status in ('partial','blocked') order by created_at,id limit 1)
    union all
    (select id,2 priority from eligible where created_at>=now()-interval '24 hours' order by created_at desc,id offset 2 limit 1)
  ), chosen as (select id from picks order by priority,id limit 3)
  select coalesce(jsonb_agg(x.payload),'[]') into sampled from (
    select jsonb_build_object('id',i.id,'type',i.type,'url',i.url,'title',left(i.title,400),
      'description',left(i.description,1200),'summary',left(i.summary,3000),
      'page_body',left(i.page_body,6000),'source_truncated',length(coalesce(i.page_body,''))>6000,
      'quality',jsonb_build_object('status',q.status,'reasons',q.reasons,'evaluated_at',q.evaluated_at),
      'recent_attempts',coalesce((select jsonb_agg(a.payload) from (
        select jsonb_build_object('strategy',a.strategy,'outcome',a.outcome,'reasons',a.reasons,'created_at',a.created_at) payload
        from enrichment_attempts a where a.item_id=i.id order by a.created_at desc limit 3
      ) a),'[]')) payload
    from items i join chosen c on c.id=i.id left join enrichment_quality q on q.item_id=i.id
    order by i.created_at desc,i.id
  ) x;
  snapshot:=jsonb_build_object('schema_version',1,'scope','configured_users','window_start',now()-interval '24 hours',
    'window_end',now(),'items',sampled,'sampling','2_latest_24h_plus_1_older_unresolved_or_3rd_recent_not_population_error_rate');
  foreach k in array array['audit','research'] loop
    if k='research' and not include_research then continue; end if;
    if k='audit' and jsonb_array_length(sampled)=0 then continue; end if;
    bucket:=case when k='audit' then to_char(now() at time zone 'UTC','YYYY-MM-DD"T"HH24')
      else to_char(now() at time zone 'America/New_York','YYYY-MM-DD') end;
    insert into hosted_quality_jobs(kind,dedupe_key,input,input_hash)
      values(k,'hosted-v1:'||k||':'||bucket,snapshot,encode(digest(snapshot::text,'sha256'),'hex')) on conflict(dedupe_key) do nothing;
    get diagnostics n=row_count; inserted:=inserted+n;
  end loop;
  return jsonb_build_object('enqueued',inserted,'sampled_items',jsonb_array_length(sampled));
end $$;

create function public.claim_hosted_quality_job() returns jsonb
language plpgsql security definer set search_path=public as $$
declare j hosted_quality_jobs;
begin
  update hosted_quality_jobs set status='failed',last_error='lease_expired_after_max_attempts'
    where status='running' and (lease_expires_at<=now() or deadline_at<=now()) and attempts>=3;
  select * into j from hosted_quality_jobs
    where attempts<3 and ((status='queued' and available_at<=now()) or
      (status='running' and (lease_expires_at<=now() or deadline_at<=now()) and available_at<=now()))
    order by created_at,id for update skip locked limit 1;
  if not found then return null; end if;
  update hosted_quality_jobs set status='running',attempts=attempts+1,fence=fence+1,lease_token=gen_random_uuid(),
    lease_expires_at=now()+interval '60 seconds',deadline_at=now()+interval '90 seconds',model_calls=0
    where id=j.id returning * into j;
  return jsonb_build_object('id',j.id,'kind',j.kind,'input',j.input,'input_hash',j.input_hash,
    'lease_token',j.lease_token,'fence',j.fence,'lease_expires_at',j.lease_expires_at,'deadline_at',j.deadline_at,
    'budget',jsonb_build_object('max_turns',6,'run_seconds',90));
end $$;

create function public.hosted_quality_job_context(target_id uuid,token uuid,expected_fence bigint) returns jsonb
language sql security definer set search_path=public as $$
  select jsonb_build_object('id',id,'kind',kind,'input',input) from hosted_quality_jobs
    where id=target_id and lease_token=token and fence=expected_fence;
$$;
create function public.heartbeat_hosted_quality_job(target_id uuid,token uuid,expected_fence bigint) returns jsonb
language plpgsql security definer set search_path=public as $$
declare expires timestamptz;
begin
  update hosted_quality_jobs set lease_expires_at=least(deadline_at,now()+interval '60 seconds')
    where id=target_id and status='running' and lease_token=token and fence=expected_fence
      and lease_expires_at>now() and deadline_at>now() returning lease_expires_at into expires;
  if not found then return jsonb_build_object('ok',false,'error','lease_lost'); end if;
  return jsonb_build_object('ok',true,'lease_expires_at',expires);
end $$;
create function public.quality_authorize_model(target_id uuid,token uuid,expected_fence bigint) returns jsonb
language plpgsql security definer set search_path=public as $$
declare j hosted_quality_jobs;
begin
  select * into j from hosted_quality_jobs where id=target_id for update;
  if not found or j.status<>'running' or j.lease_token is distinct from token or j.fence<>expected_fence
    or j.lease_expires_at<=now() or j.deadline_at<=now() then return jsonb_build_object('ok',false,'error','lease_lost'); end if;
  if j.model_calls>=6 then return jsonb_build_object('ok',false,'error','model_budget_exhausted'); end if;
  update hosted_quality_jobs set model_calls=model_calls+1 where id=target_id;
  return jsonb_build_object('ok',true,'remaining_calls',5-j.model_calls);
end $$;

create function public.complete_hosted_quality_job(target_id uuid,token uuid,expected_fence bigint,result_payload jsonb,usage_payload jsonb default '{}') returns jsonb
language plpgsql security definer set search_path=public,extensions as $$
declare j hosted_quality_jobs; r hosted_quality_results; h text;
begin
  if jsonb_typeof(result_payload)<>'object' or result_payload->>'schema_version' is distinct from '1'
    or octet_length(result_payload::text)>128000 or jsonb_typeof(usage_payload)<>'object' then raise exception 'Invalid result'; end if;
  h:=encode(digest(jsonb_build_object('result',result_payload,'usage',usage_payload)::text,'sha256'),'hex');
  select * into j from hosted_quality_jobs where id=target_id for update;
  select * into r from hosted_quality_results where job_id=target_id;
  if found then
    if r.lease_token=token and r.fence=expected_fence and r.payload_hash=h then
      return jsonb_build_object('ok',true,'status','completed','idempotent',true);
    end if;
    return jsonb_build_object('ok',false,'error','completion_conflict');
  end if;
  if j.id is null or j.status<>'running' or j.lease_token is distinct from token or j.fence<>expected_fence
    or j.lease_expires_at<=now() or j.deadline_at<=now() then return jsonb_build_object('ok',false,'error','lease_lost'); end if;
  insert into hosted_quality_results(job_id,fence,lease_token,result,usage,payload_hash)
    values(target_id,expected_fence,token,result_payload,usage_payload,h);
  update hosted_quality_jobs set status='completed',completed_at=now() where id=target_id;
  return jsonb_build_object('ok',true,'status','completed','idempotent',false);
end $$;
create function public.fail_hosted_quality_job(target_id uuid,token uuid,expected_fence bigint,failure_reason text) returns jsonb
language plpgsql security definer set search_path=public as $$
declare state text;
begin
  update hosted_quality_jobs set status=case when attempts>=3 then 'failed' else 'queued' end,
    available_at=now()+make_interval(secs=>least(3600,60*power(2,attempts)::integer)),last_error=left(failure_reason,500),lease_expires_at=null
    where id=target_id and status='running' and lease_token=token and fence=expected_fence
      and lease_expires_at>now() and deadline_at>now() returning status into state;
  if not found then return jsonb_build_object('ok',false,'error','lease_lost'); end if;
  return jsonb_build_object('ok',true,'status',state);
end $$;

-- Immutable prior-local-day report; provider delivery is a separate durable operation.
create function public.prepare_hosted_quality_report(report_recipient text) returns uuid
language plpgsql security definer set search_path=public as $$
declare d date:=(now() at time zone 'America/New_York')::date-1; rid uuid; payload jsonb; start_at timestamptz; end_at timestamptz;
begin
  if report_recipient is null or length(report_recipient)>254 or report_recipient !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then raise exception 'Invalid recipient'; end if;
  if (now() at time zone 'America/New_York')::time<time '09:00' then return null; end if;
  perform pg_advisory_xact_lock(620260109::bigint);
  start_at:=d::timestamp at time zone 'America/New_York'; end_at:=(d+1)::timestamp at time zone 'America/New_York';
  select jsonb_build_object('report_day',d,'timezone','America/New_York','window_start',start_at,'window_end',end_at,
    'job_count',count(*),'completed',count(*) filter(where j.status='completed'),'failed',count(*) filter(where j.status='failed'),
    'pending',count(*) filter(where j.status in ('queued','running')),
    'results',coalesce(jsonb_agg(jsonb_build_object('job_id',j.id,'kind',j.kind,'item_ids',jsonb_path_query_array(j.input,'$.items[*].id'),'summary',r.result->'summary',
      'findings',r.result->'findings','proposals',r.result->'proposals','uncertainties',r.result->'uncertainties','usage',r.usage))
      filter(where r.job_id is not null),'[]')) into payload
    from hosted_quality_jobs j left join hosted_quality_results r on r.job_id=j.id where j.created_at>=start_at and j.created_at<end_at;
  insert into hosted_quality_reports(recipient,report_day,payload) values(report_recipient,d,payload)
    on conflict(recipient,report_day,version) do nothing returning id into rid;
  if rid is null then select id into rid from hosted_quality_reports where recipient=report_recipient and report_day=d and version='hosted-v1'; end if;
  insert into hosted_quality_outbox(report_id,idempotency_key) values(rid,'hosted-quality/'||rid::text) on conflict(report_id) do nothing;
  return rid;
end $$;
create function public.claim_hosted_quality_email() returns jsonb
language plpgsql security definer set search_path=public as $$
declare o hosted_quality_outbox; r hosted_quality_reports;
begin
  -- Outside the provider's 24h dedupe window, do not blindly resend an uncertain acceptance.
  update hosted_quality_outbox set status='uncertain',last_error='delivery_window_expired'
    where status in ('queued','sending') and first_attempt_at<now()-interval '23 hours';
  select * into o from hosted_quality_outbox where attempts<5 and next_attempt_at<=now()
    and (status='queued' or (status='sending' and lease_expires_at<=now())) order by next_attempt_at,id for update skip locked limit 1;
  if not found then return null; end if;
  update hosted_quality_outbox set status='sending',lease_token=gen_random_uuid(),lease_expires_at=now()+interval '60 seconds',
    attempts=attempts+1,first_attempt_at=coalesce(first_attempt_at,now()) where id=o.id returning * into o;
  select * into r from hosted_quality_reports where id=o.report_id;
  return jsonb_build_object('id',o.id,'lease_token',o.lease_token,'idempotency_key',o.idempotency_key,'recipient',r.recipient,'payload',r.payload);
end $$;
create function public.finish_hosted_quality_email(target_id uuid,token uuid,accepted boolean,provider_message_id text default null,failure_reason text default null) returns boolean
language plpgsql security definer set search_path=public as $$
declare n integer;
begin
  update hosted_quality_outbox set status=case when accepted then 'accepted' when attempts>=5 then 'failed' else 'queued' end,
    accepted_at=case when accepted then now() else null end,provider_id=left(provider_message_id,200),last_error=left(failure_reason,500),
    next_attempt_at=now()+interval '5 minutes',lease_expires_at=null
    where id=target_id and status='sending' and lease_token=token and lease_expires_at>now();
  get diagnostics n=row_count; return n=1;
end $$;

create function public.prune_hosted_quality_data() returns jsonb
language plpgsql security definer set search_path=public as $$
declare jobs integer; reports integer;
begin
  delete from hosted_quality_reports where created_at<now()-interval '35 days'; get diagnostics reports=row_count;
  delete from hosted_quality_jobs where created_at<now()-interval '35 days'; get diagnostics jobs=row_count;
  return jsonb_build_object('jobs_removed',jobs,'reports_removed',reports);
end $$;
create function public.purge_deleted_item_hosted_quality() returns trigger
language plpgsql security definer set search_path=public as $$
begin
  perform pg_advisory_xact_lock(620260109::bigint);
  delete from hosted_quality_reports r where exists (
    select 1 from jsonb_array_elements(coalesce(r.payload->'results','[]')) entry
    where entry->'item_ids' @> jsonb_build_array(old.id::text)
      or entry->'findings' @> jsonb_build_array(jsonb_build_object('item_id',old.id::text))
      or exists(select 1 from hosted_quality_jobs j where j.id::text=entry->>'job_id'
        and j.input->'items' @> jsonb_build_array(jsonb_build_object('id',old.id::text)))
  );
  delete from hosted_quality_jobs where input->'items' @> jsonb_build_array(jsonb_build_object('id',old.id::text));
  return old;
end $$;
create trigger purge_deleted_item_hosted_quality before delete on public.items
  for each row execute function public.purge_deleted_item_hosted_quality();

do $$ declare f record; begin
  for f in select p.oid::regprocedure sig from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and (p.proname like '%hosted_quality%' or p.proname='quality_authorize_model') loop
    execute format('revoke all on function %s from public,anon,authenticated',f.sig);
    execute format('grant execute on function %s to service_role',f.sig);
  end loop;
end $$;
