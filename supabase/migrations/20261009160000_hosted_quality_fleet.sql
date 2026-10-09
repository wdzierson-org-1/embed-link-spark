-- Bounded fleet reviews. Schedules and leases remain owned by Stash infrastructure.
-- No item writes, user annotations, credentials, or cross-user recommendation data.
create function public.hosted_quality_url_eligible(value text) returns boolean
language sql immutable set search_path=public as $$
 select coalesce(length(value)<=2000 and value ~ '^https://[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+(/|$)'
 and value !~ '[[:space:]\\]' and value !~* '^https://([0-9.]+|[^/]*\.(local|internal|localhost|invalid|test|onion|arpa))(/|$)'
 -- Reject fragments and encoded parameter names conservatively before model sampling.
 and value !~ '#' and value !~ '[?&][^=&]*%[^=&]*='
 and value !~* '[?&](access[_-]?token|refresh[_-]?token|id[_-]?token|token|key|api[_-]?key|code|password|pass|secret|signature|sig|session(id|_id)?|auth(orization)?|jwt|x-amz-[^=]*|x-goog-[^=]*)=',false);
$$;
create or replace function public.enqueue_hosted_quality_jobs(scope_user_ids uuid[],include_research boolean default false) returns jsonb
language plpgsql security definer set search_path=public,extensions as $$
declare sampled jsonb; snapshot jsonb; k text; bucket text; inserted integer:=0; n integer;
begin
  if coalesce(cardinality(scope_user_ids),0) not between 1 and 20 then raise exception 'Invalid scope'; end if;
  -- Serialize snapshot/report creation with item deletion so a stale read cannot recreate a purged copy.
  perform pg_advisory_xact_lock(620260109::bigint);
  with reviewed as (
    select x->>'id' id,max(j.created_at) reviewed_at from hosted_quality_jobs j
    cross join lateral jsonb_array_elements(j.input->'items') x group by x->>'id'
  ), eligible as (
    select i.id,i.created_at,q.status,r.reviewed_at from items i left join enrichment_quality q on q.item_id=i.id
    left join reviewed r on r.id=i.id::text
    where i.user_id=any(scope_user_ids) and i.type='link' and hosted_quality_url_eligible(i.url)
  ), recent as (
    select id,row_number() over(order by reviewed_at nulls first,created_at desc,id) sample_rank from eligible
    where created_at>=now()-interval '24 hours'
  ), picks as (
    select id,0 priority from recent where sample_rank<=2
    union all
    (select id,1 priority from eligible where created_at<now()-interval '24 hours' and status in ('partial','blocked')
      order by reviewed_at nulls first,created_at,id limit 1)
    union all select id,2 priority from recent where sample_rank=3
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
    'window_end',now(),'items',sampled,'sampling','least_recently_reviewed_2_recent_plus_1_unresolved_or_recent_not_population_error_rate');
  foreach k in array array['audit','research'] loop
    if k='research' and not include_research then continue; end if;
    if jsonb_array_length(sampled)=0 then continue; end if;
    bucket:=case when k='audit' then to_char(now() at time zone 'UTC','YYYY-MM-DD"T"HH24')
      else to_char(now() at time zone 'America/New_York','YYYY-MM-DD') end;
    insert into hosted_quality_jobs(kind,dedupe_key,input,input_hash)
      values(k,'hosted-v1:'||k||':'||bucket,snapshot,encode(digest(snapshot::text,'sha256'),'hex')) on conflict(dedupe_key) do nothing;
    get diagnostics n=row_count; inserted:=inserted+n;
  end loop;
  return jsonb_build_object('enqueued',inserted,'sampled_items',jsonb_array_length(sampled));
end $$;


-- One account per hourly audit: accounts never share a model context. The least
-- recently sampled eligible account goes first; model-call budgets do not scale
-- with the number of users. The detail allowlist affects email only.
create function public.enqueue_hosted_quality_jobs_all_users(include_research boolean default false,detail_user_ids uuid[] default '{}') returns jsonb
language plpgsql security definer set search_path=public,extensions as $$
declare chosen uuid; result jsonb; hour_key text; day_key text; new_ids uuid[];
begin
 if coalesce(cardinality(detail_user_ids),0)>20 then raise exception 'Invalid detail scope'; end if;
 perform pg_advisory_xact_lock(620260109::bigint);
 hour_key:='hosted-v1:audit:'||to_char(now() at time zone 'UTC','YYYY-MM-DD"T"HH24');
 day_key:='hosted-v1:research:'||to_char(now() at time zone 'America/New_York','YYYY-MM-DD');
 if exists(select 1 from hosted_quality_jobs where dedupe_key=hour_key)
   and (not include_research or exists(select 1 from hosted_quality_jobs where dedupe_key=day_key)) then
   return jsonb_build_object('enqueued',0,'scope','all_users_rotating'); end if;
 with reviewed as (
   select i.user_id,max(j.created_at) reviewed_at from hosted_quality_jobs j
   cross join lateral jsonb_array_elements(j.input->'items') x join items i on i.id::text=x->>'id'
   group by i.user_id
 ), eligible as (
   select distinct i.user_id from items i left join enrichment_quality q on q.item_id=i.id
   where i.user_id is not null and i.type='link' and hosted_quality_url_eligible(i.url)
   and (i.created_at>=now()-interval '24 hours' or q.status in ('partial','blocked'))
 )
 select e.user_id into chosen from eligible e left join reviewed r on r.user_id=e.user_id
 order by r.reviewed_at nulls first,e.user_id limit 1;
 if chosen is null then return jsonb_build_object('enqueued',0,'sampled_items',0,'scope','all_users_rotating'); end if;
 select coalesce(array_agg(id),'{}') into new_ids from hosted_quality_jobs where dedupe_key in (hour_key,day_key);
 result:=enqueue_hosted_quality_jobs(array[chosen],include_research);
 update hosted_quality_jobs set input=input||jsonb_build_object('scope','all_users_rotating',
   'report_detail_allowed',chosen=any(coalesce(detail_user_ids,'{}'::uuid[])))
 where dedupe_key in (hour_key,day_key) and not(id=any(new_ids));
 update hosted_quality_jobs set input_hash=encode(digest(input::text,'sha256'),'hex')
 where dedupe_key in (hour_key,day_key) and not(id=any(new_ids));
 return result||jsonb_build_object('scope','all_users_rotating');
end $$;

-- Actual save cohort counts, separate from biased agent samples. Missing quality
-- telemetry stays unknown. Attempt metrics have their own time-window denominator.
create function public.hosted_quality_pipeline_metrics(window_start timestamptz,window_end timestamptz) returns jsonb
language plpgsql security definer set search_path=public as $$
declare payload jsonb; grouped jsonb;
begin
 if window_start is null or window_end is null or window_end<=window_start or window_end-window_start>interval '7 days' then raise exception 'Invalid metrics window'; end if;
 select jsonb_build_object('scope','all_users','saved_items',count(*),'assessed',count(q.item_id),
 'ready',count(*) filter(where q.status='ready'),'partial',count(*) filter(where q.status='partial'),
 'blocked',count(*) filter(where q.status='blocked'),'unsupported',count(*) filter(where q.status='unsupported'),
 'unassessed',count(*) filter(where q.item_id is null)) into payload
 from items i left join enrichment_quality q on q.item_id=i.id where i.created_at>=window_start and i.created_at<window_end;
 select coalesce(jsonb_agg(to_jsonb(g) order by g.saved desc,g.type),'[]') into grouped from (
 select i.type,count(*) saved,count(*) filter(where q.status='partial') partial,count(*) filter(where q.status='blocked') blocked,
 count(*) filter(where q.item_id is null) unassessed from items i left join enrichment_quality q on q.item_id=i.id
 where i.created_at>=window_start and i.created_at<window_end group by i.type) g;
 payload:=payload||jsonb_build_object('by_type',grouped);
 select coalesce(jsonb_agg(to_jsonb(g)),'[]') into grouped from (
 select left(lower(regexp_replace(substring(i.url from '^https?://([^/?#]+)'),'^.*@','')),200) source,
 count(*) saved,count(*) filter(where q.status='partial') partial,count(*) filter(where q.status='blocked') blocked,
 count(*) filter(where q.item_id is null) unassessed from items i left join enrichment_quality q on q.item_id=i.id
 where i.created_at>=window_start and i.created_at<window_end and i.type='link' and i.url ~ '^https?://'
 group by 1 having count(*) filter(where q.status in ('partial','blocked') or q.item_id is null)>0
 order by count(*) filter(where q.status in ('partial','blocked') or q.item_id is null) desc,1 limit 10) g;
 payload:=payload||jsonb_build_object('by_source',grouped);
 select coalesce(jsonb_agg(to_jsonb(g) order by g.attempts desc,g.strategy),'[]') into grouped from (
 select strategy,count(*) attempts,count(*) filter(where outcome='failed') failed,count(*) filter(where outcome='improved') improved,
 round(avg(elapsed_ms)) avg_ms,count(cost_usd) cost_known,sum(cost_usd) cost_usd
 from enrichment_attempts where created_at>=window_start and created_at<window_end group by strategy) g;
 return payload||jsonb_build_object('strategies',grouped);
end $$;
create function public.hosted_quality_report_results_internal(window_start timestamptz,window_end timestamptz) returns jsonb
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

create or replace function public.hosted_quality_report_results(window_start timestamptz,window_end timestamptz) returns jsonb
language sql security definer set search_path=public as $$
 select coalesce(jsonb_agg(case when j.input->>'scope'='all_users_rotating' and j.input->>'report_detail_allowed' is distinct from 'true' then
 jsonb_build_object('job_id',entry->'job_id','kind',entry->'kind','item_ids',entry->'item_ids','redacted',true,
 'summary','Fleet review completed; private source details retained in Stash infrastructure.',
 'findings','[]'::jsonb,'proposals','[]'::jsonb,'uncertainties','[]'::jsonb,'usage',entry->'usage',
 'proposal_count',jsonb_array_length(coalesce(nullif(entry->'proposals','null'::jsonb),'[]'::jsonb)),
 'finding_counts',coalesce((select jsonb_agg(to_jsonb(g)) from (
   select f->>'category' category,f->>'severity' severity,count(*) count from jsonb_array_elements(coalesce(nullif(entry->'findings','null'::jsonb),'[]'::jsonb)) f group by 1,2) g),'[]'::jsonb),
 'retrieval',case when entry->'retrieval' is null or entry->'retrieval'='null'::jsonb then null else
 jsonb_build_object('outcome',entry->'retrieval'->'outcome','item_id','[private item]', 'url','[private source omitted]',
 'captured_at',entry->'retrieval'->'captured_at','attempts',entry->'retrieval'->'attempts',
 'limitations',jsonb_build_array('Private source details omitted from email.')) end)
 else entry end order by j.created_at,j.id),'[]'::jsonb)
 from jsonb_array_elements(hosted_quality_report_results_internal(window_start,window_end)) entry
 join hosted_quality_jobs j on j.id::text=entry->>'job_id';
$$;
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
    'pipeline',hosted_quality_pipeline_metrics(start_at,end_at),
    'results',hosted_quality_report_results(start_at,end_at)) into payload
    from hosted_quality_jobs j where j.created_at>=start_at and j.created_at<end_at;
  insert into hosted_quality_reports(recipient,report_day,payload) values(report_recipient,d,payload)
    on conflict(recipient,report_day,version) do nothing returning id into rid;
  if rid is null then select id into rid from hosted_quality_reports where recipient=report_recipient and report_day=d and version='hosted-v1'; end if;
  insert into hosted_quality_outbox(report_id,idempotency_key) values(rid,'hosted-quality/'||rid::text) on conflict(report_id) do nothing;
  return rid;
end $$;


-- Validate the append-only strategy evidence at the database boundary too.
create function public.hosted_quality_valid_attempts(value jsonb) returns boolean
language plpgsql immutable set search_path=public as $$
declare a jsonb;
begin
 if jsonb_typeof(value) is distinct from 'array' then return false; end if;
 if jsonb_array_length(value) not between 1 and 3 then return false; end if;
 for a in select * from jsonb_array_elements(value) loop
  if jsonb_typeof(a) is distinct from 'object' or a->>'strategy' is null or a->>'strategy' not in ('firecrawl_rendered','jina_reader','medium_public_feed')
   or a->>'outcome' is null or a->>'outcome' not in ('retrieved','blocked','unavailable','mismatch')
   or coalesce(a->>'reason','') !~ '^[a-z0-9_]{1,80}$'
   or jsonb_typeof(a->'duration_ms') is distinct from 'number' then return false; end if;
  if (a->>'duration_ms')::numeric not between 0 and 30000 or trunc((a->>'duration_ms')::numeric)<>(a->>'duration_ms')::numeric then return false; end if;
 end loop;
 return true;
end $$;
create or replace function public.finish_hosted_quality_investigation(target_id uuid,token uuid,expected_fence bigint,attempt_token uuid,observation_payload jsonb) returns jsonb
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
    or length(observation_payload->>'text')>6000 or not hosted_quality_valid_attempts(observation_payload->'attempts') then return jsonb_build_object('ok',false,'error','invalid_observation'); end if;
  insert into hosted_quality_evidence(job_id,fence,attempt_token,observation) values(target_id,expected_fence,attempt_token,observation_payload);
  return jsonb_build_object('ok',true,'observation',observation_payload);
end $$;

-- Helpers and aggregate reports are operational data, never a client data API.
do $$ declare f record; begin
 for f in select p.oid::regprocedure sig from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='public' and (p.proname like '%hosted_quality%' or p.proname='quality_authorize_model') loop
 execute format('revoke all on function %s from public,anon,authenticated',f.sig);
 execute format('grant execute on function %s to service_role',f.sig);
 end loop;
end $$;
