-- Object-specific extraction has its own bounded hosted queue. It never resets repair attempts.
create table public.object_intelligence_jobs (
  item_id uuid primary key references public.items(id) on delete cascade,
  revision bigint not null default 1,
  status text not null default 'queued' check(status in ('queued','processing','complete','no_evidence','protected','unsupported','failed')),
  next_run_at timestamptz not null default now()+interval '2 minutes',
  lease_token uuid, leased_until timestamptz, leased_revision bigint, run_token uuid,
  attempts integer not null default 0 check(attempts between 0 and 3),
  model_calls_total integer not null default 0, failure_count integer not null default 0 check(failure_count between 0 and 5),
  last_status text not null default 'queued', last_error text, last_source_hash text,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create index object_intelligence_jobs_due on public.object_intelligence_jobs(next_run_at,leased_until)
  where status in ('queued','processing');
create table public.object_intelligence_control (
  singleton boolean primary key default true check(singleton),
  run_token uuid, leased_until timestamptz, run_calls integer not null default 0,
  budget_day date not null default (now() at time zone 'UTC')::date, daily_calls integer not null default 0,
  budget_hour timestamptz not null default date_trunc('hour',now()), hourly_calls integer not null default 0
);
insert into public.object_intelligence_control(singleton) values(true);
alter table public.object_intelligence_jobs enable row level security;
alter table public.object_intelligence_control enable row level security;
revoke all on public.object_intelligence_jobs,public.object_intelligence_control from public,anon,authenticated;
grant all on public.object_intelligence_jobs,public.object_intelligence_control to service_role;

-- Capture type is separate from semantic classification. Future archive fields, if present, also exclude work.
create function public.object_intelligence_item_eligible(i public.items) returns boolean
language sql immutable set search_path=public,pg_temp as $$
  select i.type::text in ('text','link','image','audio','video','document')
    and coalesce(to_jsonb(i)->>'archived_at','')='' and coalesce(to_jsonb(i)->>'deleted_at','')=''
    and coalesce(to_jsonb(i)->>'is_archived','false')<>'true';
$$;
create function public.object_intelligence_source_fields(i public.items) returns jsonb
language sql immutable set search_path=public,pg_temp as $$
  select jsonb_build_object('type',i.type,'url',i.url,'page_body',i.page_body,'content',i.content,
    'file_path',i.file_path,'mime_type',i.mime_type,'object_facts',i.attributes->'object_facts',
    'link_author',i.attributes#>'{link,author}','link_canonical_url',i.attributes#>'{link,canonical_url}',
    'author',i.attributes#>'{enrichment,evidence,author}','creator',i.attributes#>'{enrichment,evidence,creator}',
    'caption',i.attributes#>'{enrichment,evidence,caption}','canonical_url',i.attributes#>'{enrichment,evidence,canonical_url}',
    'transcript',i.attributes#>'{enrichment,evidence,transcript}','transcript_source',i.attributes#>'{enrichment,evidence,transcript_source}',
    'language',i.attributes#>'{enrichment,evidence,language}','duration_s',i.attributes#>'{enrichment,evidence,duration_s}',
    'visual',i.attributes#>'{enrichment,evidence,visual}','visual_text',i.attributes#>'{enrichment,evidence,visual_text}',
    'transcript_status',i.attributes#>'{media,transcript,status}',
    'protected',i.attributes#>'{enrichment,protected_fields,object_intelligence}');
$$;
create function public.enqueue_object_intelligence() returns trigger
language plpgsql security definer set search_path=public,pg_temp as $$
begin
  if not object_intelligence_item_eligible(new) then
    delete from object_intelligence_jobs where item_id=new.id;
    return new;
  end if;
  if tg_op='UPDATE' and object_intelligence_item_eligible(old)
    and object_intelligence_source_fields(new) is not distinct from object_intelligence_source_fields(old) then return new; end if;
  insert into object_intelligence_jobs(item_id) values(new.id)
  on conflict(item_id) do update set revision=object_intelligence_jobs.revision+1,status='queued',
    next_run_at=now()+interval '2 minutes',attempts=0,failure_count=0,last_status='queued',last_error=null,
    lease_token=null,leased_until=null,leased_revision=null,run_token=null,updated_at=now();
  return new;
end $$;
create trigger enqueue_object_intelligence after insert or update on public.items
  for each row execute function public.enqueue_object_intelligence();

create function public.begin_object_intelligence_run() returns uuid
language plpgsql security definer set search_path=public,pg_temp as $$
declare result uuid;
begin
  update object_intelligence_control set run_token=gen_random_uuid(),leased_until=now()+interval '5 minutes',run_calls=0
    where singleton and (leased_until is null or leased_until<=now()) returning run_token into result;
  return result;
end $$;
create function public.claim_object_intelligence_jobs(run_token uuid,batch_size integer default 10)
returns setof public.object_intelligence_jobs language plpgsql security definer set search_path=public,pg_temp as $$
begin
  perform 1 from object_intelligence_control c where c.singleton and c.run_token=$1 and c.leased_until>now() for update;
  if not found then return; end if;
  -- Count abandoned work too; repeated crashes cannot leave an immortal paid retry loop.
  update object_intelligence_jobs set failure_count=least(failure_count+1,5),
    status=case when failure_count+1>=5 then 'failed' else 'queued' end,
    last_status=case when failure_count+1>=5 then 'failed' else 'retry' end,last_error='lease_expired',
    lease_token=null,leased_until=null,leased_revision=null,run_token=null,updated_at=now()
    where status='processing' and leased_until<=now();
  return query with due as (
    select j.item_id from object_intelligence_jobs j join items i on i.id=j.item_id
    where j.status in ('queued','processing') and j.next_run_at<=now()
      and (j.leased_until is null or j.leased_until<=now()) and object_intelligence_item_eligible(i)
    order by j.next_run_at,j.item_id for update of j skip locked limit greatest(0,least(coalesce(batch_size,10),10))
  ) update object_intelligence_jobs j set status='processing',lease_token=gen_random_uuid(),leased_until=now()+interval '5 minutes',
      leased_revision=j.revision,run_token=$1,updated_at=now()
    from due where j.item_id=due.item_id returning j.*;
end $$;
-- Reservations precede every provider call. A crash may spend an allowance, but cannot double the budget.
create function public.reserve_object_intelligence_call(run_token uuid,target_id uuid,token uuid,
  daily_limit integer default 200,hourly_limit integer default 24) returns boolean
language plpgsql security definer set search_path=public,pg_temp as $$
declare c public.object_intelligence_control; j public.object_intelligence_jobs;
  utc_day date:=(now() at time zone 'UTC')::date; current_hour timestamptz:=date_trunc('hour',now());
begin
  select * into c from object_intelligence_control where singleton for update;
  if c.run_token is distinct from $1 or c.leased_until is null or c.leased_until<=now() or c.run_calls>=2
    or coalesce(daily_limit,0)<=0 or coalesce(hourly_limit,0)<=0
    or (c.budget_day=utc_day and c.daily_calls>=least(daily_limit,500))
    or (c.budget_hour=current_hour and c.hourly_calls>=least(hourly_limit,24)) then return false; end if;
  select * into j from object_intelligence_jobs where item_id=target_id for update;
  if not found or j.lease_token is distinct from token or j.run_token is distinct from $1 or j.leased_until is null or j.leased_until<=now()
    or j.leased_revision is distinct from j.revision or j.status<>'processing' or j.attempts>=3 then return false; end if;
  update object_intelligence_control set run_calls=run_calls+1,
    daily_calls=case when budget_day=utc_day then daily_calls+1 else 1 end,budget_day=utc_day,
    hourly_calls=case when budget_hour=current_hour then hourly_calls+1 else 1 end,budget_hour=current_hour where singleton;
  update object_intelligence_jobs set attempts=attempts+1,model_calls_total=model_calls_total+1,updated_at=now() where item_id=target_id;
  return true;
end $$;
create function public.commit_object_intelligence(target_id uuid,token uuid,expected jsonb,intelligence jsonb) returns boolean
language plpgsql security definer set search_path=public,pg_temp as $$
declare i public.items; j public.object_intelligence_jobs; k text;
begin
  if jsonb_typeof(expected) is distinct from 'object' or not expected ?& array['type','url','title','description','summary','content','supplemental_note','page_body','file_path','mime_type','attributes']
    or jsonb_typeof(intelligence) is distinct from 'object' or octet_length(intelligence::text)>48000
    or intelligence->'version' is distinct from '1'::jsonb or intelligence->'beta' is distinct from 'true'::jsonb
    or intelligence->>'extraction_version' is distinct from 'object-intelligence-v1'
    or coalesce(intelligence->>'source_fingerprint','') !~ '^[a-f0-9]{64}$'
    or coalesce(intelligence->>'processed_at','') !~ '^\d{4}-\d{2}-\d{2}T'
    or jsonb_typeof(intelligence->'interpretation') is distinct from 'object'
    or jsonb_typeof(intelligence->'facts') is distinct from 'object'
    or jsonb_typeof(intelligence->'evidence') is distinct from 'array'
    or jsonb_typeof(intelligence->'capabilities') is distinct from 'array' then return false; end if;
  -- Item before queue matches the source-update trigger's lock order.
  select * into i from items where id=target_id for update;
  if not found or not object_intelligence_item_eligible(i)
    or i.attributes#>'{enrichment,protected_fields,object_intelligence}'='true'::jsonb then return false; end if;
  select * into j from object_intelligence_jobs where item_id=target_id for update;
  if not found or j.lease_token is distinct from token or j.leased_until is null or j.leased_until<=now() or j.status<>'processing'
    or j.leased_revision is distinct from j.revision
    or not exists(select 1 from object_intelligence_control c where c.singleton and c.run_token=j.run_token and c.leased_until>now()) then return false; end if;
  for k in select jsonb_object_keys(expected) loop
    if to_jsonb(i)->k is distinct from expected->k then return false; end if;
  end loop;
  update items set attributes=jsonb_set(case when jsonb_typeof(attributes)='object' then attributes else '{}'::jsonb end,'{object_intelligence}',intelligence,true) where id=target_id;
  update object_intelligence_jobs set last_source_hash=intelligence->>'source_fingerprint',updated_at=now() where item_id=target_id;
  return true;
end $$;
create function public.finish_object_intelligence_job(target_id uuid,token uuid,expected_revision bigint,
  outcome text,delay_seconds integer default 300,failure_code text default null) returns boolean
language plpgsql security definer set search_path=public,pg_temp as $$
declare n integer;
begin
  if outcome is null or outcome not in ('complete','no_evidence','protected','unsupported','retry','failed','deferred') then return false; end if;
  update object_intelligence_jobs set status=case when outcome='retry' and failure_count+1>=5 then 'failed' when outcome in ('retry','deferred') then 'queued' else outcome end,
    failure_count=case when outcome='retry' then least(failure_count+1,5) else failure_count end,
    next_run_at=case when outcome in ('retry','deferred') and not (outcome='retry' and failure_count+1>=5) then now()+make_interval(secs=>greatest(60,least(coalesce(delay_seconds,300),86400))) else 'infinity'::timestamptz end,
    last_status=case when outcome='retry' and failure_count+1>=5 then 'failed' else outcome end,last_error=case when failure_code is null then null
      when failure_code ~ '^object_intelligence_provider_http_[1-5][0-9]{2}$' then failure_code
      when failure_code in ('provider_error','provider_timeout','invalid_result','invalid_json','source_changed','index_failed','budget_exhausted','worker_error','attempts_exhausted','no_source','transcript_pending','item_changed','object_intelligence_extraction_failed','object_intelligence_index_failed','object_intelligence_persistence_failed') then failure_code else 'worker_error' end,
    lease_token=null,leased_until=null,leased_revision=null,run_token=null,updated_at=now()
    where item_id=target_id and lease_token=token and leased_until>now() and revision=expected_revision and leased_revision=expected_revision;
  get diagnostics n=row_count; return n=1;
end $$;
create function public.end_object_intelligence_run(token uuid) returns void
language sql security definer set search_path=public,pg_temp as $$
  update object_intelligence_control set run_token=null,leased_until=null where singleton and run_token=token;
$$;

revoke all on function public.object_intelligence_item_eligible(public.items),public.object_intelligence_source_fields(public.items),
  public.enqueue_object_intelligence(),public.begin_object_intelligence_run(),public.claim_object_intelligence_jobs(uuid,integer),
  public.reserve_object_intelligence_call(uuid,uuid,uuid,integer,integer),public.commit_object_intelligence(uuid,uuid,jsonb,jsonb),
  public.finish_object_intelligence_job(uuid,uuid,bigint,text,integer,text),public.end_object_intelligence_run(uuid) from public,anon,authenticated;
grant execute on function public.object_intelligence_item_eligible(public.items),public.object_intelligence_source_fields(public.items),
  public.begin_object_intelligence_run(),public.claim_object_intelligence_jobs(uuid,integer),
  public.reserve_object_intelligence_call(uuid,uuid,uuid,integer,integer),public.commit_object_intelligence(uuid,uuid,jsonb,jsonb),
  public.finish_object_intelligence_job(uuid,uuid,bigint,text,integer,text),public.end_object_intelligence_run(uuid) to service_role;

-- A small starting cohort; later source saves/changes enter automatically through the trigger.
insert into public.object_intelligence_jobs(item_id)
  select id from public.items i where object_intelligence_item_eligible(i)
  order by created_at desc,id limit 100 on conflict do nothing;

-- The endpoint defaults OBJECT_INTELLIGENCE_ENABLED=false, so deployment can safely precede activation.
-- pg_cron/pg_net and cron_secret were installed by Stash's existing hosted cron migrations.
select cron.schedule('object-intelligence-worker','*/5 * * * *',$job$
  select net.http_post(
    url := 'https://uqqsgmwkvslaomzxptnp.supabase.co/functions/v1/object-intelligence-worker',
    headers := jsonb_build_object('Content-Type','application/json','x-cron-secret',
      (select decrypted_secret from vault.decrypted_secrets where name='cron_secret' limit 1)),
    body := '{}'::jsonb, timeout_milliseconds := 120000
  );
$job$);
