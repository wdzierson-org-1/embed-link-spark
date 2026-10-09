-- Delivery accounting survives removal of private reports. No item IDs, quotes,
-- summaries, source URLs or provider payloads belong in this table.
create table public.hosted_quality_delivery_receipts (
  recipient text not null, report_day date not null, version text not null,
  idempotency_key text not null, first_attempt_at timestamptz not null default now(), accepted_at timestamptz,
  primary key(recipient,report_day,version)
);
alter table public.hosted_quality_delivery_receipts enable row level security;
revoke all on public.hosted_quality_delivery_receipts from public,anon,authenticated;
grant all on public.hosted_quality_delivery_receipts to service_role;

-- Preserve any send that may already have reached the provider before this migration.
insert into public.hosted_quality_delivery_receipts(recipient,report_day,version,idempotency_key,first_attempt_at,accepted_at)
  select lower(btrim(r.recipient)),r.report_day,r.version,o.idempotency_key,coalesce(o.first_attempt_at,now()),
    case when o.status='accepted' then coalesce(o.accepted_at,o.first_attempt_at,now()) else o.accepted_at end
  from public.hosted_quality_outbox o join public.hosted_quality_reports r on r.id=o.report_id
  where o.first_attempt_at is not null or o.attempts>0 or o.status in ('sending','accepted','uncertain')
  order by o.first_attempt_at nulls last
  on conflict(recipient,report_day,version) do nothing;

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

create or replace function public.claim_hosted_quality_email() returns jsonb
language plpgsql security definer set search_path=public as $$
declare o hosted_quality_outbox; r hosted_quality_reports;
begin
  -- The receipt commits atomically with the send claim, before the network call.
  -- Item deletion uses this same lock and can erase payloads without erasing delivery history.
  perform pg_advisory_xact_lock(620260109::bigint);
  update hosted_quality_outbox set status='uncertain',last_error='delivery_window_expired'
    where status in ('queued','sending') and first_attempt_at<now()-interval '23 hours';
  select b.* into o from hosted_quality_outbox b join hosted_quality_reports p on p.id=b.report_id
    left join hosted_quality_delivery_receipts d on d.recipient=lower(btrim(p.recipient)) and d.report_day=p.report_day and d.version=p.version
    where b.attempts<5 and b.next_attempt_at<=now()
      and (b.status='queued' or (b.status='sending' and b.lease_expires_at<=now()))
      and (d.recipient is null or (d.idempotency_key=b.idempotency_key and d.accepted_at is null))
    order by b.next_attempt_at,b.id for update of b skip locked limit 1;
  if not found then return null; end if;
  select * into r from hosted_quality_reports where id=o.report_id;
  insert into hosted_quality_delivery_receipts(recipient,report_day,version,idempotency_key,first_attempt_at)
    values(lower(btrim(r.recipient)),r.report_day,r.version,o.idempotency_key,coalesce(o.first_attempt_at,now()))
    on conflict(recipient,report_day,version) do nothing;
  update hosted_quality_outbox set status='sending',lease_token=gen_random_uuid(),lease_expires_at=now()+interval '60 seconds',
    attempts=attempts+1,first_attempt_at=coalesce(first_attempt_at,now()) where id=o.id returning * into o;
  return jsonb_build_object('id',o.id,'lease_token',o.lease_token,'idempotency_key',o.idempotency_key,'recipient',r.recipient,'payload',r.payload);
end $$;

create or replace function public.finish_hosted_quality_email(target_id uuid,token uuid,accepted boolean,provider_message_id text default null,failure_reason text default null) returns boolean
language plpgsql security definer set search_path=public as $$
declare rid uuid; sent_key text;
begin
  update hosted_quality_outbox set status=case when accepted then 'accepted' when attempts>=5 then 'failed' else 'queued' end,
    accepted_at=case when accepted then now() else null end,provider_id=left(provider_message_id,200),last_error=left(failure_reason,500),
    next_attempt_at=now()+interval '5 minutes',lease_expires_at=null
    where id=target_id and status='sending' and lease_token=token and lease_expires_at>now()
    returning report_id,idempotency_key into rid,sent_key;
  if not found then return false; end if;
  if accepted then
    update hosted_quality_delivery_receipts d set accepted_at=coalesce(d.accepted_at,now()) from hosted_quality_reports r
      where r.id=rid and d.recipient=lower(btrim(r.recipient)) and d.report_day=r.report_day and d.version=r.version and d.idempotency_key=sent_key;
  end if;
  return true;
end $$;

create or replace function public.prune_hosted_quality_data() returns jsonb
language plpgsql security definer set search_path=public as $$
declare jobs integer; reports integer; receipts integer;
begin
  delete from hosted_quality_reports where created_at<now()-interval '35 days'; get diagnostics reports=row_count;
  delete from hosted_quality_jobs where created_at<now()-interval '35 days'; get diagnostics jobs=row_count;
  delete from hosted_quality_delivery_receipts where first_attempt_at<now()-interval '35 days'; get diagnostics receipts=row_count;
  return jsonb_build_object('jobs_removed',jobs,'reports_removed',reports,'receipts_removed',receipts);
end $$;
-- CREATE OR REPLACE preserves the existing service-only RPC grants.
