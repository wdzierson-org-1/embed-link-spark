-- Reviewable proposal intake. This does not execute, evaluate or promote a playbook.
-- Source-bearing proposals and decision notes retain the existing 35-day job
-- lifetime. Deleting a sampled item removes its job, result, proposals and notes.
create table public.hosted_quality_proposals (
 id uuid primary key default gen_random_uuid(),
 job_id uuid not null references public.hosted_quality_results(job_id) on delete cascade,
 proposal_index integer not null check(proposal_index between 0 and 4),
 title text not null check(length(btrim(title)) between 1 and 200),
 rationale text not null check(length(btrim(rationale)) between 1 and 2000),
 evidence_urls jsonb not null check(jsonb_typeof(evidence_urls)='array' and jsonb_array_length(evidence_urls) between 1 and 5),
 source_item_ids uuid[] not null check(cardinality(source_item_ids) between 1 and 15),
 status text not null default 'new' check(status in ('new','needs_evidence','planned','dismissed')),
 revision bigint not null default 0 check(revision>=0),
 created_at timestamptz not null default now(), reviewed_at timestamptz,
 unique(job_id,proposal_index)
);
create index hosted_quality_proposals_queue on public.hosted_quality_proposals(status,created_at desc,id);
create table public.hosted_quality_proposal_reviews (
 id uuid primary key default gen_random_uuid(),
 proposal_id uuid not null references public.hosted_quality_proposals(id) on delete cascade,
 actor_id uuid not null, request_id uuid not null,
 from_status text not null check(from_status in ('new','needs_evidence','planned','dismissed')),
 to_status text not null check(to_status in ('new','needs_evidence','planned','dismissed')),
 note text not null check(length(btrim(note)) between 1 and 2000),
 revision bigint not null check(revision>0), created_at timestamptz not null default now(),
 unique(proposal_id,request_id), unique(proposal_id,revision)
);
do $$ declare t text; begin
 foreach t in array array['hosted_quality_proposals','hosted_quality_proposal_reviews'] loop
  execute format('alter table public.%I enable row level security',t);
  execute format('revoke all on public.%I from public,anon,authenticated',t);
  execute format('grant all on public.%I to service_role',t);
 end loop;
end $$;

-- Project already accepted result proposals without changing the Hermes contract.
-- Historical malformed proposals are skipped, never treated as approved evidence.
-- The exact job/ordinal key prevents completion retries from duplicating intake.
create function public.intake_hosted_quality_proposals(target_job_id uuid) returns integer
language plpgsql security definer set search_path=public as $$
declare j hosted_quality_jobs; r hosted_quality_results; entry record; p jsonb; ids uuid[]; inserted integer:=0; n integer;
begin
 select * into j from hosted_quality_jobs where id=target_job_id;
 if not found or j.created_at<now()-interval '35 days' then return 0; end if;
 if jsonb_typeof(j.input->'items') is distinct from 'array' then return 0; end if;
 select * into r from hosted_quality_results where job_id=target_job_id;
 if not found or jsonb_typeof(r.result->'proposals') is distinct from 'array' then return 0; end if;
 for entry in select value,ordinality from jsonb_array_elements(r.result->'proposals') with ordinality limit 5 loop
  p:=entry.value;
  if jsonb_typeof(p) is distinct from 'object' or jsonb_typeof(p->'title') is distinct from 'string'
   or jsonb_typeof(p->'rationale') is distinct from 'string' or jsonb_typeof(p->'evidence_urls') is distinct from 'array' then continue; end if;
  if length(btrim(p->>'title')) not between 1 and 200 or length(btrim(p->>'rationale')) not between 1 and 2000
   or jsonb_array_length(p->'evidence_urls') not between 1 and 5 then continue; end if;
  if exists(select 1 from jsonb_array_elements(p->'evidence_urls') u
   where jsonb_typeof(u) is distinct from 'string' or not hosted_quality_url_eligible(u#>>'{}')
    or not exists(select 1 from jsonb_array_elements(coalesce(j.input->'items','[]')) s where s->>'url'=u#>>'{}')) then continue; end if;
  select array_agg(distinct i.id order by i.id) into ids from jsonb_array_elements(coalesce(j.input->'items','[]')) s
   join items i on i.id::text=s->>'id'
   where p->'evidence_urls' @> jsonb_build_array(s->>'url');
  if coalesce(cardinality(ids),0) not between 1 and 15 then continue; end if;
  insert into hosted_quality_proposals(job_id,proposal_index,title,rationale,evidence_urls,source_item_ids,created_at)
   values(j.id,entry.ordinality-1,p->>'title',p->>'rationale',p->'evidence_urls',ids,r.created_at)
   on conflict(job_id,proposal_index) do nothing;
  get diagnostics n=row_count; inserted:=inserted+n;
 end loop;
 return inserted;
end $$;
create function public.intake_hosted_quality_result_proposals() returns trigger
language plpgsql security definer set search_path=public as $$
begin
 perform intake_hosted_quality_proposals(new.job_id);
 return new;
end $$;
create trigger intake_hosted_quality_result_proposals after insert on public.hosted_quality_results
 for each row execute function public.intake_hosted_quality_result_proposals();
-- Read only the retained job corpus, under the same lock used by item deletion.
do $$ declare j record; begin
 perform pg_advisory_xact_lock(620260109::bigint);
 for j in select id from hosted_quality_jobs where created_at>=now()-interval '35 days' loop
  perform intake_hosted_quality_proposals(j.id);
 end loop;
end $$;

-- The edge function authenticates the JWT and supplies its user ID. A caller
-- cannot reach this service-only RPC directly or supply another actor via UI.
create function public.review_hosted_quality_proposal(actor_user_id uuid,target_id uuid,expected_revision bigint,
 new_status text,review_note text,request_id uuid) returns jsonb
language plpgsql security definer set search_path=public as $$
declare p hosted_quality_proposals; previous hosted_quality_proposal_reviews; reviewed timestamptz:=now();
begin
 if actor_user_id is null or not exists(select 1 from admin_users where user_id=actor_user_id) then
  raise exception 'Not an admin' using errcode='42501'; end if;
 review_note:=btrim(review_note);
 if target_id is null or expected_revision is null or expected_revision<0 or request_id is null
  or new_status is null or new_status not in ('new','needs_evidence','planned','dismissed')
  or review_note is null or length(review_note) not between 1 and 2000 then
  raise exception 'Invalid proposal review' using errcode='22023'; end if;
 select * into p from hosted_quality_proposals where id=target_id for update;
 if not found then return jsonb_build_object('ok',false,'error','not_found'); end if;
 select * into previous from hosted_quality_proposal_reviews v where v.proposal_id=target_id and v.request_id=review_hosted_quality_proposal.request_id;
 if found then
  if previous.actor_id=actor_user_id and previous.revision=expected_revision+1 and previous.to_status=new_status and previous.note=review_note then
   return jsonb_build_object('ok',true,'id',p.id,'revision',p.revision,'status',p.status,'reviewed_at',p.reviewed_at,'idempotent',true);
  end if;
  return jsonb_build_object('ok',false,'error','request_conflict');
 end if;
 if p.revision<>expected_revision then return jsonb_build_object('ok',false,'error','version_conflict','revision',p.revision,'status',p.status); end if;
 insert into hosted_quality_proposal_reviews(proposal_id,actor_id,request_id,from_status,to_status,note,revision,created_at)
  values(p.id,actor_user_id,request_id,p.status,new_status,review_note,p.revision+1,reviewed);
 update hosted_quality_proposals set status=new_status,revision=p.revision+1,reviewed_at=reviewed where id=p.id;
 return jsonb_build_object('ok',true,'id',p.id,'revision',p.revision+1,'status',new_status,'reviewed_at',reviewed,'idempotent',false);
end $$;

create function public.admin_enrichment_quality(actor_user_id uuid,lookback_hours integer default 24,
 proposal_status text default null,proposal_limit integer default 50) returns jsonb
language plpgsql security definer set search_path=public as $$
declare start_at timestamptz; end_at timestamptz:=now(); daily jsonb; jobs jsonb; delivery jsonb; counts jsonb; proposals jsonb; incomplete jsonb;
begin
 if actor_user_id is null or not exists(select 1 from admin_users where user_id=actor_user_id) then
  raise exception 'Not an admin' using errcode='42501'; end if;
 if lookback_hours is null or lookback_hours not in (24,168) or proposal_limit is null or proposal_limit not between 1 and 50
  or (proposal_status is not null and proposal_status not in ('new','needs_evidence','planned','dismissed')) then
  raise exception 'Invalid quality dashboard filter' using errcode='22023'; end if;
 start_at:=end_at-make_interval(hours=>lookback_hours);
 -- These are present quality states grouped by the save's New York date, not
 -- historical measurements of what that save's state was on previous days.
 with days as (
  select generate_series((start_at at time zone 'America/New_York')::date::timestamp,
   (end_at at time zone 'America/New_York')::date::timestamp,interval '1 day')::date as day
 ), cohort as (
  select (i.created_at at time zone 'America/New_York')::date as day,i.id,q.item_id,q.status
  from items i left join enrichment_quality q on q.item_id=i.id where i.created_at>=start_at and i.created_at<end_at
 ), rows as (
  select d.day,count(c.id) saved_items,count(c.item_id) assessed,
   count(*) filter(where c.status='ready') ready,count(*) filter(where c.status='partial') partial,
   count(*) filter(where c.status='blocked') blocked,count(*) filter(where c.status='unsupported') unsupported,
   count(c.id) filter(where c.item_id is null) unassessed
  from days d left join cohort c on c.day=d.day group by d.day
 ) select coalesce(jsonb_agg(to_jsonb(rows) order by day),'[]') into daily from rows;
 select jsonb_build_object('total',count(*),'completed',count(*) filter(where status='completed'),
  'failed',count(*) filter(where status='failed'),'pending',count(*) filter(where status in ('queued','running')),
  'last_completed_at',max(completed_at),'error_counts',coalesce((select jsonb_agg(to_jsonb(e) order by e.count desc,e.reason) from (
   select case when last_error ~ '^[a-z0-9_]{1,80}$' then last_error else 'other_error' end reason,count(*) count
   from hosted_quality_jobs where created_at>=start_at and created_at<end_at and status='failed' and last_error is not null
   group by 1 order by 2 desc,1 limit 10) e),'[]')) into jobs
  from hosted_quality_jobs where created_at>=start_at and created_at<end_at;
 -- Item deletion removes report/outbox payloads, but minimal delivery receipts
 -- remain to prevent duplicate email. A receipt can prove provider acceptance;
 -- without accepted_at its delivery is uncertain, never known failed or unsent.
 select jsonb_build_object('status',d.status,'accepted_at',d.accepted_at,'report_day',d.report_day,'last_error',d.last_error)
  into delivery from (
   select o.status,o.accepted_at,r.report_day,r.created_at recorded_at,0 priority,
    case when o.last_error ~ '^[a-z0-9_]{1,80}$' then o.last_error when o.last_error is not null then 'other_error' else null end last_error
   from hosted_quality_outbox o join hosted_quality_reports r on r.id=o.report_id
   union all
   select case when accepted_at is not null then 'accepted' else 'uncertain' end,accepted_at,report_day,first_attempt_at,1,
    case when accepted_at is null then 'report_payload_removed' else null end
   from hosted_quality_delivery_receipts
  ) d order by d.report_day desc,(d.accepted_at is not null) desc,d.priority,d.recorded_at desc limit 1;
 select jsonb_build_object('total',count(*),'new',count(*) filter(where status='new'),'needs_evidence',count(*) filter(where status='needs_evidence'),
  'planned',count(*) filter(where status='planned'),'dismissed',count(*) filter(where status='dismissed')) into counts from hosted_quality_proposals;
 select coalesce(jsonb_agg(to_jsonb(p) order by p.created_at desc,p.id),'[]') into proposals from (
  select p.id,p.job_id,j.kind,p.title,p.rationale,p.evidence_urls,p.source_item_ids,p.status,p.revision,p.created_at,p.reviewed_at,
   coalesce((select jsonb_agg(to_jsonb(v) order by v.revision desc) from (
    select id,actor_id,from_status,to_status,note,revision,created_at from hosted_quality_proposal_reviews
     where proposal_id=p.id order by revision desc limit 3) v),'[]') reviews
  from hosted_quality_proposals p join hosted_quality_jobs j on j.id=p.job_id
  where proposal_status is null or p.status=proposal_status order by p.created_at desc,p.id limit proposal_limit
 ) p;
 select coalesce(jsonb_agg(to_jsonb(i) order by i.created_at desc,i.item_id),'[]') into incomplete from (
  select i.id item_id,i.user_id,i.type,left(i.title,400) title,i.created_at,
   case when hosted_quality_url_eligible(i.url) then lower(substring(i.url from '^https://([^/?#]+)')) else null end source,
   case when hosted_quality_url_eligible(i.url) then i.url else null end url,
   coalesce(q.status,'unassessed') status,coalesce(q.reasons,'{}'::text[]) reasons,q.evaluated_at,
   coalesce((select jsonb_agg(to_jsonb(a) order by a.created_at desc) from (
    select strategy,outcome,reasons,created_at,elapsed_ms from enrichment_attempts where item_id=i.id order by created_at desc limit 5) a),'[]') attempts
  from items i left join enrichment_quality q on q.item_id=i.id
  where i.created_at>=start_at and i.created_at<end_at and (q.item_id is null or q.status in ('partial','blocked'))
  order by i.created_at desc,i.id limit 30
 ) i;
 return jsonb_build_object('window_start',start_at,'window_end',end_at,'lookback_hours',lookback_hours,
  'pipeline',hosted_quality_pipeline_metrics(start_at,end_at),'daily',daily,'jobs',jobs,'delivery',delivery,
  'proposal_counts',counts,'proposals',proposals,'incomplete_items',incomplete);
end $$;

revoke all on function public.intake_hosted_quality_proposals(uuid) from public,anon,authenticated;
revoke all on function public.intake_hosted_quality_result_proposals() from public,anon,authenticated;
revoke all on function public.review_hosted_quality_proposal(uuid,uuid,bigint,text,text,uuid) from public,anon,authenticated;
revoke all on function public.admin_enrichment_quality(uuid,integer,text,integer) from public,anon,authenticated;
grant execute on function public.intake_hosted_quality_proposals(uuid) to service_role;
grant execute on function public.review_hosted_quality_proposal(uuid,uuid,bigint,text,text,uuid) to service_role;
grant execute on function public.admin_enrichment_quality(uuid,integer,text,integer) to service_role;
