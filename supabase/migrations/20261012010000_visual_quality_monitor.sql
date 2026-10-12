-- Hosted visual monitoring. Service-only records; private synthetic saves use
-- normal authenticated capture. Model findings never modify user items.
create table public.hosted_visual_config (
 singleton boolean primary key default true check(singleton),
 monitor_user_id uuid not null unique references auth.users(id),
 created_at timestamptz not null default now()
);
create table public.hosted_visual_baselines (
 id text not null check(id ~ '^[a-z0-9-]{1,80}$'), version integer not null check(version>0),
 title text not null check(length(title)<=300), source_url text not null check(public.hosted_quality_url_eligible(source_url)),
 image_path text not null check(image_path ~ '^[a-z0-9-]+/v[0-9]+\.(png|jpeg|jpg|webp)$'),
 sha256 text not null check(sha256 ~ '^[0-9a-f]{64}$'), description text not null check(length(description) between 1 and 2000),
 provenance jsonb not null check(octet_length(provenance::text)<=4000), reviewed_at timestamptz not null default now(),
 enabled boolean not null default false, primary key(id,version)
);
create unique index hosted_visual_one_enabled_baseline on public.hosted_visual_baselines(id) where enabled;
create function public.hosted_visual_immutable_reference() returns trigger
language plpgsql set search_path=public as $$ begin
 if (to_jsonb(new)-'enabled') is distinct from (to_jsonb(old)-'enabled') then
 raise check_violation using message='Create a new reviewed baseline version'; end if; return new;
end $$;
create trigger hosted_visual_immutable_reference before update on public.hosted_visual_baselines
 for each row execute function public.hosted_visual_immutable_reference();
create table public.hosted_visual_jobs (
 id uuid primary key default gen_random_uuid(), kind text not null check(kind in ('sample','canary')),
 dedupe_key text not null unique, owner_id uuid not null, item_id uuid,
 checked_url text not null check(public.hosted_quality_url_eligible(checked_url)),
 fixture_id text, fixture_version integer, foreign key(fixture_id,fixture_version) references hosted_visual_baselines(id,version),
 report_detail_allowed boolean not null default false,
 status text not null default 'queued' check(status in ('queued','running','waiting','completed','failed')),
 available_at timestamptz not null default now(), created_at timestamptz not null default now(), completed_at timestamptz,
 attempts integer not null default 0, lease_token uuid, fence bigint not null default 0, lease_expires_at timestamptz,
 model_calls integer not null default 0 check(model_calls between 0 and 2), last_error text,
 inspection jsonb check(inspection is null or octet_length(inspection::text)<=24000),
 cleanup_file_path text, cleaned_item_at timestamptz, cleaned_media_at timestamptz,
 check(kind<>'canary' or (fixture_id is not null and fixture_version is not null))
);
create index hosted_visual_queue on public.hosted_visual_jobs(available_at,created_at) where status in ('queued','waiting','running');
create index hosted_visual_item on public.hosted_visual_jobs(item_id);
create table public.hosted_visual_model_calls (
 id bigint generated always as identity primary key, job_id uuid references hosted_visual_jobs(id) on delete set null,
 reserved_at timestamptz not null default now()
);
create table public.hosted_visual_dispatch_receipts (dedupe_key text primary key,created_at timestamptz not null default now());
create index hosted_visual_model_budget on public.hosted_visual_model_calls(reserved_at);

do $$ declare t text; begin
 foreach t in array array['hosted_visual_config','hosted_visual_baselines','hosted_visual_jobs','hosted_visual_model_calls','hosted_visual_dispatch_receipts'] loop
 execute format('alter table public.%I enable row level security',t);
 execute format('revoke all on public.%I from public,anon,authenticated',t);
 execute format('grant all on public.%I to service_role',t);
 end loop;
end $$;
grant usage,select on sequence public.hosted_visual_model_calls_id_seq to service_role;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
 values('quality-reference-images','quality-reference-images',false,5242880,array['image/png','image/jpeg','image/webp'])
 on conflict(id) do nothing;

create function public.enqueue_hosted_visual_jobs(detail_user_ids uuid[] default '{}') returns jsonb
language plpgsql security definer set search_path=public as $$
declare monitor uuid; fixture hosted_visual_baselines; chosen items; bucket text; inserted integer:=0; n integer;
begin
 if coalesce(cardinality(detail_user_ids),0)>20 then raise exception 'Invalid detail scope'; end if;
 perform pg_advisory_xact_lock(620260109::bigint);
 select monitor_user_id into monitor from hosted_visual_config where singleton;
 if monitor is null then return jsonb_build_object('enqueued',0,'reason','monitor_not_configured'); end if;
 bucket:=to_char(now() at time zone 'UTC','YYYY-MM-DD"T"HH24');
 select b.* into fixture from hosted_visual_baselines b left join lateral
 (select max(created_at) checked from hosted_visual_jobs j where j.kind='canary' and j.fixture_id=b.id) r on true
 where b.enabled order by r.checked nulls first,b.id limit 1;
 if fixture.id is not null then
 with receipt as (insert into hosted_visual_dispatch_receipts(dedupe_key) values('visual-v1:canary:'||bucket) on conflict do nothing returning dedupe_key)
 insert into hosted_visual_jobs(kind,dedupe_key,owner_id,checked_url,fixture_id,fixture_version,report_detail_allowed)
 select 'canary',dedupe_key,monitor,fixture.source_url,fixture.id,fixture.version,true from receipt;
 get diagnostics n=row_count; inserted:=inserted+n;
 end if;
 -- Rotate accounts first, then uninspected/recent links. Exclude unready new saves.
 select i.* into chosen from items i
 left join lateral(select max(created_at) checked from hosted_visual_jobs j where j.kind='sample' and j.owner_id=i.user_id) u on true
 left join lateral(select max(created_at) checked from hosted_visual_jobs j where j.kind='sample' and j.item_id=i.id) r on true
 where i.user_id<>monitor and i.type='link' and hosted_quality_url_eligible(i.url)
 and i.created_at<now()-interval '2 minutes'
 and (i.attributes->'enrichment'->>'status' is distinct from 'pending' or i.created_at<now()-interval '20 minutes')
 order by u.checked nulls first,r.checked nulls first,i.created_at desc,i.id limit 1;
 if chosen.id is not null then
 select * into fixture from hosted_visual_baselines where enabled and source_url=chosen.url order by reviewed_at desc limit 1;
 with receipt as (insert into hosted_visual_dispatch_receipts(dedupe_key) values('visual-v1:sample:'||bucket) on conflict do nothing returning dedupe_key)
 insert into hosted_visual_jobs(kind,dedupe_key,owner_id,item_id,checked_url,fixture_id,fixture_version,report_detail_allowed)
 select 'sample',dedupe_key,chosen.user_id,chosen.id,chosen.url,fixture.id,fixture.version,chosen.user_id=any(coalesce(detail_user_ids,'{}'::uuid[])) from receipt;
 get diagnostics n=row_count; inserted:=inserted+n;
 end if;
 return jsonb_build_object('enqueued',inserted);
end $$;

create function public.claim_hosted_visual_job() returns jsonb
language plpgsql security definer set search_path=public as $$
declare j hosted_visual_jobs; b hosted_visual_baselines;
begin
 -- Recover a successful capture whose process died before registration.
 update hosted_visual_jobs recovery set item_id=c.item_id from capture_receipts c,items i,hosted_visual_baselines refbase,hosted_visual_config conf
 where recovery.kind='canary' and recovery.item_id is null and recovery.owner_id=conf.monitor_user_id
 and c.capture_id=recovery.id and c.user_id=recovery.owner_id and c.status='done' and c.item_id=i.id
 and i.user_id=recovery.owner_id and i.is_public=false and i.type='link' and refbase.id=recovery.fixture_id and refbase.version=recovery.fixture_version and i.url=refbase.source_url;
 -- Dead executions remain visible as failed, never as a visual pass.
 update hosted_visual_jobs set status='failed',last_error='job_expired',completed_at=now(),lease_expires_at=null
 where status in ('queued','waiting','running') and created_at<now()-interval '30 minutes';
 select * into j from hosted_visual_jobs where created_at>=now()-interval '30 minutes' and available_at<=now()
 and (status in ('queued','waiting') or (status='running' and lease_expires_at<=now()))
 order by created_at,id for update skip locked limit 1;
 if not found then return null; end if;
 update hosted_visual_jobs set status='running',attempts=attempts+1,lease_token=gen_random_uuid(),fence=fence+1,
 lease_expires_at=now()+interval '120 seconds' where id=j.id returning * into j;
 select * into b from hosted_visual_baselines where id=j.fixture_id and version=j.fixture_version;
 return to_jsonb(j)||jsonb_build_object('fixture',case when b.id is null then null else jsonb_build_object('id',b.id,'url',b.source_url) end,
 'reference',case when b.id is null then null else jsonb_build_object('id',b.id,'version',b.version,'image_path',b.image_path,'sha256',b.sha256,'description',b.description) end);
end $$;
create function public.register_hosted_visual_capture(job_id uuid,token uuid,expected_fence bigint,item_id uuid) returns boolean
language plpgsql security definer set search_path=public as $$
declare n integer;
begin
 update hosted_visual_jobs j set item_id=register_hosted_visual_capture.item_id,status='waiting',available_at=now()+interval '2 minutes',lease_expires_at=null
 where j.id=job_id and j.kind='canary' and j.status='running' and j.lease_token=token and j.fence=expected_fence and j.lease_expires_at>now()
 and (j.item_id is null or j.item_id=register_hosted_visual_capture.item_id)
 and exists(select 1 from items i join capture_receipts c on c.item_id=i.id
 join hosted_visual_baselines b on b.id=j.fixture_id and b.version=j.fixture_version
 join hosted_visual_config conf on conf.monitor_user_id=i.user_id
 where i.id=register_hosted_visual_capture.item_id and i.user_id=j.owner_id and i.is_public=false and i.type='link' and i.url=b.source_url
 and c.user_id=j.owner_id and c.capture_id=j.id and c.status='done');
 get diagnostics n=row_count; return n=1;
end $$;
create function public.defer_hosted_visual_job(job_id uuid,token uuid,expected_fence bigint,reason text) returns boolean
language plpgsql security definer set search_path=public as $$
declare n integer; begin
 update hosted_visual_jobs set status='waiting',available_at=now()+interval '2 minutes',lease_expires_at=null,last_error=left(reason,100)
 where id=job_id and status='running' and lease_token=token and fence=expected_fence and lease_expires_at>now();
 get diagnostics n=row_count; return n=1;
end $$;
create function public.authorize_hosted_visual_model(job_id uuid,token uuid,expected_fence bigint) returns boolean
language plpgsql security definer set search_path=public as $$
declare j hosted_visual_jobs; begin
 perform pg_advisory_xact_lock(620260112::bigint);
 select * into j from hosted_visual_jobs where id=job_id for update;
 if not found or j.status<>'running' or j.lease_token is distinct from token or j.fence<>expected_fence or j.lease_expires_at<=now() or j.model_calls>=2 then return false; end if;
 if (select count(*) from hosted_visual_model_calls where reserved_at>=date_trunc('hour',now()))>=4
 or (select count(*) from hosted_visual_model_calls where reserved_at>=date_trunc('day',now() at time zone 'UTC') at time zone 'UTC')>=48 then return false; end if;
 insert into hosted_visual_model_calls(job_id) values(j.id);
 update hosted_visual_jobs set model_calls=model_calls+1 where id=j.id;
 return true;
end $$;
create function public.complete_hosted_visual_job(job_id uuid,token uuid,expected_fence bigint,inspection jsonb,error_text text default null) returns boolean
language plpgsql security definer set search_path=public as $$
declare n integer; c jsonb; begin
 if inspection is not null then
 if inspection->>'schema_version' is distinct from '1' or jsonb_typeof(inspection->'checks') is distinct from 'array' or octet_length(inspection::text)>24000 then return false; end if;
 if jsonb_array_length(inspection->'checks') not between 1 and 2 then return false; end if;
 for c in select * from jsonb_array_elements(inspection->'checks') loop
 if c->>'surface' is null or c->>'surface' not in ('card','detail') or c->>'outcome' is null or c->>'outcome' not in
 ('exact_match','match','mismatch','missing_image','unavailable','unsupported','inconclusive') then return false; end if;
 end loop;
 elsif error_text is null then return false; end if;
 update hosted_visual_jobs set status=case when complete_hosted_visual_job.inspection is null then 'failed' else 'completed' end,
 inspection=complete_hosted_visual_job.inspection,last_error=left(error_text,100),completed_at=now(),lease_expires_at=null
 where id=job_id and status='running' and lease_token=token and fence=expected_fence and lease_expires_at>now();
 get diagnostics n=row_count; return n=1;
end $$;

create function public.list_hosted_visual_cleanup() returns jsonb
language sql security definer set search_path=public as $$
 select coalesce(jsonb_agg(to_jsonb(x)),'[]') from (
 select j.id job_id,j.owner_id,j.item_id,coalesce(j.cleanup_file_path,i.file_path) file_path,false is_public,true settled
 from hosted_visual_jobs j join hosted_visual_config conf on conf.monitor_user_id=j.owner_id
 left join items i on i.id=j.item_id
 where j.kind='canary' and j.status in ('completed','failed') and j.item_id is not null and j.cleaned_media_at is null
 and (j.cleaned_item_at is not null or (i.user_id=j.owner_id and i.is_public=false and
 (i.attributes->'enrichment'->>'status' is distinct from 'pending' or j.created_at<now()-interval '30 minutes')))
 order by j.created_at limit 3) x;
$$;
create function public.purge_hosted_visual_canary(job_id uuid,expected_file_path text) returns boolean
language plpgsql security definer set search_path=public as $$
declare j hosted_visual_jobs; i items; begin
 perform pg_advisory_xact_lock(620260109::bigint);
 select * into j from hosted_visual_jobs where id=job_id for update;
 if not found or j.kind<>'canary' or j.status not in ('completed','failed')
 or not exists(select 1 from hosted_visual_config where monitor_user_id=j.owner_id) then return false; end if;
 if j.cleaned_item_at is not null then return j.cleanup_file_path is not distinct from expected_file_path; end if;
 select * into i from items where id=j.item_id for update;
 if not found or i.user_id<>j.owner_id or i.is_public is distinct from false or i.file_path is distinct from expected_file_path
 or (i.attributes->'enrichment'->>'status'='pending' and j.created_at>=now()-interval '30 minutes') then return false; end if;
 if not exists(select 1 from capture_receipts c join hosted_visual_baselines b on b.id=j.fixture_id and b.version=j.fixture_version
 where c.capture_id=j.id and c.user_id=j.owner_id and c.item_id=i.id and c.status='done' and i.url=b.source_url) then return false; end if;
 update hosted_visual_jobs set cleanup_file_path=i.file_path,cleaned_item_at=now() where id=j.id;
 delete from items where id=i.id;
 return true;
end $$;
create function public.hosted_visual_preview_referenced(preview_path text) returns boolean
language sql security definer set search_path=public as $$
 select exists(select 1 from items where file_path=preview_path or attributes->'media'->'preview'->>'file_path'=preview_path)
 or exists(select 1 from hosted_visual_baselines where image_path=preview_path);
$$;
create function public.finish_hosted_visual_cleanup(job_id uuid,expected_file_path text) returns boolean
language plpgsql security definer set search_path=public as $$
declare n integer; begin
 update hosted_visual_jobs set cleaned_media_at=now() where id=job_id and kind='canary' and cleaned_item_at is not null
 and cleanup_file_path is not distinct from expected_file_path;
 get diagnostics n=row_count; return n=1;
end $$;
create function public.prune_hosted_visual_data() returns jsonb
language plpgsql security definer set search_path=public as $$
declare n integer; begin
 -- Keep pending cleanup registrations until storage deletion succeeds.
 delete from hosted_visual_jobs where created_at<now()-interval '35 days' and (kind='sample' or item_id is null or cleaned_media_at is not null);
 get diagnostics n=row_count;
 delete from hosted_visual_model_calls where reserved_at<now()-interval '35 days';
 delete from hosted_visual_dispatch_receipts where created_at<now()-interval '35 days';
 return jsonb_build_object('jobs_removed',n);
end $$;

create function public.hosted_visual_report(window_start timestamptz,window_end timestamptz) returns jsonb
language plpgsql security definer set search_path=public as $$
declare counts jsonb; surfaces jsonb; canaries jsonb; findings jsonb; private_count integer;
begin
 if window_end<=window_start or window_end-window_start>interval '7 days' then raise exception 'Invalid visual window'; end if;
 select jsonb_build_object('jobs',count(*),'completed',count(*) filter(where status='completed'),'failed',count(*) filter(where status='failed'),
 'pending',count(*) filter(where status in ('queued','running','waiting'))) into counts from hosted_visual_jobs where created_at>=window_start and created_at<window_end;
 select jsonb_build_object('checks',count(*),'exact_match',count(*) filter(where c->>'outcome'='exact_match'),'match',count(*) filter(where c->>'outcome'='match'),
 'mismatch',count(*) filter(where c->>'outcome'='mismatch'),'missing_image',count(*) filter(where c->>'outcome'='missing_image'),
 'unavailable',count(*) filter(where c->>'outcome'='unavailable'),'unsupported',count(*) filter(where c->>'outcome'='unsupported'),
 'inconclusive',count(*) filter(where c->>'outcome'='inconclusive')) into surfaces from hosted_visual_jobs j
 cross join lateral jsonb_array_elements(coalesce(j.inspection->'checks','[]')) c where j.created_at>=window_start and j.created_at<window_end;
 select coalesce(jsonb_agg(to_jsonb(x)),'[]') into canaries from (
 select j.fixture_id,max(b.title) title,max(b.source_url) url,count(*) runs,count(*) filter(where j.status='completed') completed,
 count(*) filter(where j.status='failed') failed,(array_agg(coalesce(j.last_error,(select c->>'outcome' from jsonb_array_elements(coalesce(j.inspection->'checks','[]')) c
 order by case c->>'outcome' when 'mismatch' then 0 when 'missing_image' then 1 when 'unavailable' then 2 when 'inconclusive' then 3 when 'unsupported' then 4 when 'match' then 5 else 6 end limit 1),j.status) order by j.created_at desc))[1] last_outcome,
 max(coalesce(j.completed_at,j.created_at)) last_checked_at from hosted_visual_jobs j
 join hosted_visual_baselines b on b.id=j.fixture_id and b.version=j.fixture_version
 where j.kind='canary' and j.created_at>=window_start and j.created_at<window_end group by j.fixture_id) x;
 select count(*) into private_count from hosted_visual_jobs j cross join lateral jsonb_array_elements(coalesce(j.inspection->'checks','[]')) c
 where j.created_at>=window_start and j.created_at<window_end and not j.report_detail_allowed and j.kind='sample';
 select coalesce(jsonb_agg(x.finding order by x.created_at,x.id),'[]') into findings from (
 select j.created_at,j.id,jsonb_strip_nulls(jsonb_build_object('kind',j.kind,'item_id',case when j.kind='sample' then j.item_id end,'fixture_id',j.fixture_id,
 'url',j.checked_url,'surface',c->>'surface','outcome',c->>'outcome','reason',c->>'reason',
 'summary',c->'comparison'->>'summary','checked_at',j.inspection->>'checked_at','display_url',c->>'display_url',
 'reference_id',c->'reference'->>'id','reference_version',c->'reference'->'version')) finding
 from hosted_visual_jobs j left join items i on i.id=j.item_id left join hosted_visual_baselines b on b.id=j.fixture_id and b.version=j.fixture_version
 cross join lateral jsonb_array_elements(coalesce(j.inspection->'checks','[]')) c
 where j.created_at>=window_start and j.created_at<window_end and (j.report_detail_allowed or j.kind='canary')
 order by j.created_at desc limit 100) x;
 return jsonb_build_object('window_start',window_start,'window_end',window_end,'counts',counts||surfaces,'canaries',canaries,'findings',findings,'private_findings',private_count,
 'limits',jsonb_build_array('One rotating real-save sample and one live canary per UTC hour; not a population accuracy rate.',
 'Initial coverage: link card and detail image delivery bytes. Browser layout, cropping, video playback, iframe contents and other object types are not evaluated.',
 'Proxy checks use the normal delivery URL with redirects disabled. Unsupported destinations and provider failures remain unknown.',
 'Fixed reviewed baseline bytes are compared exactly or with a vision model; source-only judgments have no known-good reference.',
 'At most 2 vision calls per job, 4 per UTC hour and 48 per UTC day. Limits and failed calls remain visible as inconclusive.',
 'Canary images are temporary; their reported delivery URLs may expire after cleanup. Reference hashes and versions remain recorded.'));
end $$;

create function public.purge_deleted_item_hosted_visual() returns trigger
language plpgsql security definer set search_path=public as $$ begin
 perform pg_advisory_xact_lock(620260109::bigint);
 delete from hosted_quality_reports r where r.payload->'visual'->'findings' @> jsonb_build_array(jsonb_build_object('item_id',old.id::text));
 delete from hosted_visual_jobs where kind='sample' and item_id=old.id;
 return old;
end $$;
create trigger purge_deleted_item_hosted_visual before delete on public.items for each row execute function public.purge_deleted_item_hosted_visual();

-- Run outside the Hermes wake/request so slow retrieval never delays reporting.
select cron.schedule('hosted-visual-monitor','2-57/5 * * * *',$job$
 select net.http_post(url:='https://uqqsgmwkvslaomzxptnp.supabase.co/functions/v1/quality-visual',
 headers:=jsonb_build_object('Content-Type','application/json','x-cron-secret',
 (select decrypted_secret from vault.decrypted_secrets where name='cron_secret' limit 1)),body:='{}'::jsonb,timeout_milliseconds:=120000);
$job$);
-- Activate only after the worker, credentials and reviewed fixtures are verified.
select cron.alter_job((select jobid from cron.job where jobname='hosted-visual-monitor'),active:=false);

-- Preserve existing report/sampling behavior; exclude synthetic accounts.
CREATE OR REPLACE FUNCTION public.enqueue_hosted_quality_jobs(scope_user_ids uuid[], include_research boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
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
    and not exists(select 1 from hosted_visual_config c where c.monitor_user_id=i.user_id)
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
end $function$
;

-- Preserve existing report/sampling behavior; exclude synthetic accounts.
CREATE OR REPLACE FUNCTION public.enqueue_hosted_quality_jobs_all_users(include_research boolean DEFAULT false, detail_user_ids uuid[] DEFAULT '{}'::uuid[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
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
    and not exists(select 1 from hosted_visual_config c where c.monitor_user_id=i.user_id)
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
end $function$
;

-- Preserve existing report/sampling behavior; exclude synthetic accounts.
CREATE OR REPLACE FUNCTION public.hosted_quality_pipeline_metrics(window_start timestamp with time zone, window_end timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare payload jsonb; grouped jsonb;
begin
 if window_start is null or window_end is null or window_end<=window_start or window_end-window_start>interval '7 days' then raise exception 'Invalid metrics window'; end if;
 select jsonb_build_object('scope','all_users','saved_items',count(*),'assessed',count(q.item_id),
 'ready',count(*) filter(where q.status='ready'),'partial',count(*) filter(where q.status='partial'),
 'blocked',count(*) filter(where q.status='blocked'),'unsupported',count(*) filter(where q.status='unsupported'),
 'unassessed',count(*) filter(where q.item_id is null)) into payload
 from items i left join enrichment_quality q on q.item_id=i.id where not exists(select 1 from hosted_visual_config c where c.monitor_user_id=i.user_id) and i.created_at>=window_start and i.created_at<window_end;
 select coalesce(jsonb_agg(to_jsonb(g) order by g.saved desc,g.type),'[]') into grouped from (
 select i.type,count(*) saved,count(*) filter(where q.status='partial') partial,count(*) filter(where q.status='blocked') blocked,
 count(*) filter(where q.item_id is null) unassessed from items i left join enrichment_quality q on q.item_id=i.id
 where not exists(select 1 from hosted_visual_config c where c.monitor_user_id=i.user_id) and i.created_at>=window_start and i.created_at<window_end group by i.type) g;
 payload:=payload||jsonb_build_object('by_type',grouped);
 select coalesce(jsonb_agg(to_jsonb(g)),'[]') into grouped from (
 select left(lower(regexp_replace(substring(i.url from '^https?://([^/?#]+)'),'^.*@','')),200) source,
 count(*) saved,count(*) filter(where q.status='partial') partial,count(*) filter(where q.status='blocked') blocked,
 count(*) filter(where q.item_id is null) unassessed from items i left join enrichment_quality q on q.item_id=i.id
 where not exists(select 1 from hosted_visual_config c where c.monitor_user_id=i.user_id) and i.created_at>=window_start and i.created_at<window_end and i.type='link' and i.url ~ '^https?://'
 group by 1 having count(*) filter(where q.status in ('partial','blocked') or q.item_id is null)>0
 order by count(*) filter(where q.status in ('partial','blocked') or q.item_id is null) desc,1 limit 10) g;
 payload:=payload||jsonb_build_object('by_source',grouped);
 select coalesce(jsonb_agg(to_jsonb(g) order by g.attempts desc,g.strategy),'[]') into grouped from (
 select strategy,count(*) attempts,count(*) filter(where outcome='failed') failed,count(*) filter(where outcome='improved') improved,
 round(avg(elapsed_ms)) avg_ms,count(cost_usd) cost_known,sum(cost_usd) cost_usd
 from enrichment_attempts where not exists(select 1 from items i join hosted_visual_config c on c.monitor_user_id=i.user_id where i.id=enrichment_attempts.item_id) and created_at>=window_start and created_at<window_end group by strategy) g;
 return payload||jsonb_build_object('strategies',grouped);
end $function$
;

-- Preserve existing report/sampling behavior; exclude synthetic accounts.
CREATE OR REPLACE FUNCTION public.prepare_hosted_quality_report(report_recipient text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
    'visual',hosted_visual_report(start_at,end_at),
    'results',hosted_quality_report_results(start_at,end_at)) into payload
    from hosted_quality_jobs j where j.created_at>=start_at and j.created_at<end_at;
  insert into hosted_quality_reports(recipient,report_day,payload) values(report_recipient,d,payload)
    on conflict(recipient,report_day,version) do nothing returning id into rid;
  if rid is null then select id into rid from hosted_quality_reports where recipient=report_recipient and report_day=d and version='hosted-v1'; end if;
  insert into hosted_quality_outbox(report_id,idempotency_key) values(rid,'hosted-quality/'||rid::text) on conflict(report_id) do nothing;
  return rid;
end $function$
;

-- Operational data/functions are never a client API.
do $$ declare f record; begin
 for f in select p.oid::regprocedure sig from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='public' and p.proname like '%hosted_visual%' loop
 execute format('revoke all on function %s from public,anon,authenticated',f.sig);
 execute format('grant execute on function %s to service_role',f.sig);
 end loop;
end $$;
