-- Bounded live retrieval belongs to the existing hosted quality queue. It never mutates saved items.
alter table public.hosted_quality_jobs
  add column investigation_attempts integer not null default 0 check(investigation_attempts between 0 and 3),
  add column investigation_token uuid,
  add column investigation_started_at timestamptz;

create table public.hosted_quality_evidence (
  job_id uuid primary key references public.hosted_quality_jobs(id) on delete cascade,
  fence bigint not null,
  attempt_token uuid not null,
  observation jsonb not null check(jsonb_typeof(observation)='object' and observation->>'schema_version'='1' and octet_length(observation::text)<=32000),
  created_at timestamptz not null default now()
);
alter table public.hosted_quality_evidence enable row level security;
revoke all on public.hosted_quality_evidence from public,anon,authenticated;
grant all on public.hosted_quality_evidence to service_role;

create function public.hosted_quality_investigation_item(snapshot jsonb) returns jsonb
language sql immutable set search_path=public as $$
  select item from jsonb_array_elements(coalesce(snapshot->'items','[]'::jsonb)) with ordinality as sampled(item,position)
    order by case when item->'quality'->>'status' in ('partial','blocked') then 0
      when nullif(btrim(item->>'page_body'),'') is null then 1 else 2 end,position limit 1;
$$;

create function public.reserve_hosted_quality_investigation(target_id uuid,token uuid,expected_fence bigint) returns jsonb
language plpgsql security definer set search_path=public as $$
declare j hosted_quality_jobs; evidence hosted_quality_evidence; item jsonb; attempt uuid;
begin
  select * into j from hosted_quality_jobs where id=target_id for update;
  if not found or j.status<>'running' or j.lease_token is distinct from token or j.fence<>expected_fence
    or j.lease_expires_at<=now() or j.deadline_at<=now() then return jsonb_build_object('ok',false,'error','lease_lost'); end if;
  if j.kind<>'research' then return jsonb_build_object('ok',false,'error','unsupported_job_kind'); end if;
  select * into evidence from hosted_quality_evidence where job_id=target_id;
  if found then return jsonb_build_object('ok',true,'cached',true,'observation',evidence.observation); end if;
  if j.investigation_started_at>now()-interval '30 seconds' then return jsonb_build_object('ok',false,'error','investigation_busy'); end if;
  if j.investigation_attempts>=3 then return jsonb_build_object('ok',false,'error','retrieval_budget_exhausted'); end if;
  item:=hosted_quality_investigation_item(j.input);
  if item is null then return jsonb_build_object('ok',false,'error','no_investigation_item'); end if;
  attempt:=gen_random_uuid();
  update hosted_quality_jobs set investigation_attempts=investigation_attempts+1,investigation_token=attempt,investigation_started_at=now() where id=target_id;
  return jsonb_build_object('ok',true,'item',item,'attempt_token',attempt);
end $$;

create function public.finish_hosted_quality_investigation(target_id uuid,token uuid,expected_fence bigint,attempt_token uuid,observation_payload jsonb) returns jsonb
language plpgsql security definer set search_path=public as $$
declare j hosted_quality_jobs; evidence hosted_quality_evidence; item jsonb;
begin
  select * into j from hosted_quality_jobs where id=target_id for update;
  if not found or j.status<>'running' or j.lease_token is distinct from token or j.fence<>expected_fence
    or j.lease_expires_at<=now() or j.deadline_at<=now() then return jsonb_build_object('ok',false,'error','lease_lost'); end if;
  if j.kind<>'research' then return jsonb_build_object('ok',false,'error','unsupported_job_kind'); end if;
  select * into evidence from hosted_quality_evidence where job_id=target_id;
  if found then
    if evidence.attempt_token=finish_hosted_quality_investigation.attempt_token and evidence.observation=observation_payload then
      return jsonb_build_object('ok',true,'observation',evidence.observation,'idempotent',true);
    end if;
    return jsonb_build_object('ok',false,'error','observation_conflict');
  end if;
  if j.investigation_token is null or attempt_token is null or j.investigation_token is distinct from attempt_token then
    return jsonb_build_object('ok',false,'error','investigation_lost');
  end if;
  item:=hosted_quality_investigation_item(j.input);
  if item is null or observation_payload->>'item_id' is distinct from item->>'id' or observation_payload->>'url' is distinct from item->>'url' then
    return jsonb_build_object('ok',false,'error','observation_out_of_scope');
  end if;
  if jsonb_typeof(observation_payload) is distinct from 'object' or observation_payload->>'schema_version' is distinct from '1'
    or octet_length(observation_payload::text)>32000 or jsonb_typeof(observation_payload->'text') is distinct from 'string'
    or length(observation_payload->>'text')>6000 then return jsonb_build_object('ok',false,'error','invalid_observation'); end if;
  insert into hosted_quality_evidence(job_id,fence,attempt_token,observation) values(target_id,expected_fence,attempt_token,observation_payload);
  return jsonb_build_object('ok',true,'observation',observation_payload);
end $$;

create or replace function public.hosted_quality_job_context(target_id uuid,token uuid,expected_fence bigint) returns jsonb
language sql security definer set search_path=public as $$
  select jsonb_build_object('id',j.id,'kind',j.kind,'input',j.input,'observation',e.observation)
    from hosted_quality_jobs j left join hosted_quality_evidence e on e.job_id=j.id
    where j.id=target_id and j.lease_token=token and j.fence=expected_fence;
$$;

revoke all on function public.hosted_quality_investigation_item(jsonb) from public,anon,authenticated;
revoke all on function public.reserve_hosted_quality_investigation(uuid,uuid,bigint) from public,anon,authenticated;
revoke all on function public.finish_hosted_quality_investigation(uuid,uuid,bigint,uuid,jsonb) from public,anon,authenticated;
grant execute on function public.hosted_quality_investigation_item(jsonb) to service_role;
grant execute on function public.reserve_hosted_quality_investigation(uuid,uuid,bigint) to service_role;
grant execute on function public.finish_hosted_quality_investigation(uuid,uuid,bigint,uuid,jsonb) to service_role;

-- Keep the daily report useful without copying fetched source bodies into email payloads.
create function public.hosted_quality_report_results(window_start timestamptz,window_end timestamptz) returns jsonb
language sql security definer set search_path=public as $$
  select coalesce(jsonb_agg(jsonb_build_object('job_id',j.id,'kind',j.kind,
    'item_ids',jsonb_path_query_array(j.input,'$.items[*].id'),
    'summary',coalesce(r.result->'summary',to_jsonb('Live retrieval recorded; model analysis did not complete.'::text)),
    'findings',r.result->'findings','proposals',r.result->'proposals','uncertainties',r.result->'uncertainties','usage',r.usage,
    'retrieval',case when e.job_id is null then null
      when e.observation->'attempts' @> '[{"reason":"unsafe_url"}]'::jsonb then
        (e.observation-'text'-'title'-'url')||jsonb_build_object('url','[redacted unsafe URL]')
      else e.observation-'text'-'title' end)
    order by j.created_at,j.id),'[]'::jsonb)
  from hosted_quality_jobs j left join hosted_quality_results r on r.job_id=j.id
    left join hosted_quality_evidence e on e.job_id=j.id
  where j.created_at>=window_start and j.created_at<window_end and (r.job_id is not null or e.job_id is not null);
$$;
revoke all on function public.hosted_quality_report_results(timestamptz,timestamptz) from public,anon,authenticated;
grant execute on function public.hosted_quality_report_results(timestamptz,timestamptz) to service_role;

create or replace function public.prepare_hosted_quality_report(report_recipient text) returns uuid
language plpgsql security definer set search_path=public as $$
declare d date:=(now() at time zone 'America/New_York')::date-1; rid uuid; payload jsonb; start_at timestamptz; end_at timestamptz;
begin
  report_recipient:=lower(btrim(report_recipient));
  if report_recipient is null or length(report_recipient)>254 or report_recipient !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then raise exception 'Invalid recipient'; end if;
  if (now() at time zone 'America/New_York')::time<time '09:00' then return null; end if;
  perform pg_advisory_xact_lock(620260109::bigint);
  if exists(select 1 from hosted_quality_delivery_receipts where recipient=report_recipient and report_day=d and version='hosted-v1') then
    -- Existing outbox retries may continue with their original payload/key. A purged
    -- report must never be recreated and sent under a new key for the same day.
    select id into rid from hosted_quality_reports where lower(btrim(recipient))=report_recipient and report_day=d and version='hosted-v1';
    return rid;
  end if;
  start_at:=d::timestamp at time zone 'America/New_York'; end_at:=(d+1)::timestamp at time zone 'America/New_York';
  select jsonb_build_object('report_day',d,'timezone','America/New_York','window_start',start_at,'window_end',end_at,
    'job_count',count(*),'completed',count(*) filter(where j.status='completed'),'failed',count(*) filter(where j.status='failed'),
    'pending',count(*) filter(where j.status in ('queued','running')),
    'results',hosted_quality_report_results(start_at,end_at)) into payload
    from hosted_quality_jobs j where j.created_at>=start_at and j.created_at<end_at;
  insert into hosted_quality_reports(recipient,report_day,payload) values(report_recipient,d,payload)
    on conflict(recipient,report_day,version) do nothing returning id into rid;
  if rid is null then select id into rid from hosted_quality_reports where recipient=report_recipient and report_day=d and version='hosted-v1'; end if;
  insert into hosted_quality_outbox(report_id,idempotency_key) values(rid,'hosted-quality/'||rid::text) on conflict(report_id) do nothing;
  return rid;
end $$;

-- Replaced functions retain service-only grants. Existing job deletion/35-day retention cascades to evidence.
