-- Run ONLY against an empty disposable PostgreSQL14+ database: psql -v ON_ERROR_STOP=1 -f queue.test.sql.
-- Minimal pre-existing Stash schema stubs; the actual new migration runs below. Everything rolls back.
begin;
create role anon; create role authenticated; create role service_role;
create schema extensions;
create table public.items(id uuid primary key,user_id uuid,type text,url text,title text,description text,summary text,page_body text,created_at timestamptz default now());
create table public.enrichment_quality(item_id uuid,status text,reasons text[],evaluated_at timestamptz);
create table public.enrichment_attempts(item_id uuid,strategy text,outcome text,reasons text[],created_at timestamptz);
\ir ../../migrations/20261009120000_hosted_quality.sql
insert into hosted_quality_reports(id,recipient,report_day,payload) values('99999999-9999-4999-8999-999999999999','legacy@example.org',current_date,'{}');
insert into hosted_quality_outbox(report_id,idempotency_key,status,attempts,first_attempt_at,accepted_at)
  values('99999999-9999-4999-8999-999999999999','legacy-key','accepted',1,now(),now());
\ir ../../migrations/20261009130000_hosted_quality_delivery_receipts.sql
\ir ../../migrations/20261009150000_hosted_quality_live_evidence.sql
delete from hosted_quality_reports where id='99999999-9999-4999-8999-999999999999';
create function pg_temp.assert(ok boolean,label text) returns void language plpgsql as $$ begin
  if ok is distinct from true then raise exception 'ASSERTION FAILED: %',label; end if;
end $$;

select pg_temp.assert(not has_table_privilege('authenticated','hosted_quality_jobs','select'),'authenticated cannot read queue');
select pg_temp.assert(not has_table_privilege('anon','hosted_quality_results','select'),'anon cannot read results');
select pg_temp.assert(not has_function_privilege('authenticated','claim_hosted_quality_job()','execute'),'worker RPC not exposed to users');
select pg_temp.assert(has_function_privilege('service_role','claim_hosted_quality_job()','execute'),'service can claim');
select pg_temp.assert(not has_table_privilege('authenticated','hosted_quality_delivery_receipts','select'),'receipts service-only');
select pg_temp.assert((select relrowsecurity from pg_class where relname='hosted_quality_delivery_receipts'),'receipts RLS');
select pg_temp.assert(exists(select 1 from hosted_quality_delivery_receipts where recipient='legacy@example.org' and accepted_at is not null),'backfill keeps accepted receipt after private payload removed');
select pg_temp.assert((select bool_and(relrowsecurity) from pg_class where relname in ('hosted_quality_jobs','hosted_quality_results','hosted_quality_reports','hosted_quality_outbox')),'RLS on all new tables');

insert into items(id,user_id,type,url,title,summary,description,page_body)
  select ('00000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,'11111111-1111-4111-8111-111111111111','link',
  'https://example.org/article/'||n,'Article '||n,repeat('s',4000),repeat('d',1500),repeat('p',7000) from generate_series(1,4) n;
insert into items values('00000000-0000-4000-8000-000000000005','22222222-2222-4222-8222-222222222222','link','https://example.org/private','Other user',null,null,'must not enter job',now());
insert into items values('00000000-0000-4000-8000-000000000006','11111111-1111-4111-8111-111111111111','link','https://127.0.0.1/private','Private host',null,null,'must not enter job',now());
insert into items values('00000000-0000-4000-8000-000000000007','11111111-1111-4111-8111-111111111111','link','https://example.org/older','Older incomplete',repeat('d',1500),repeat('s',4000),repeat('p',7000),now()-interval '3 days');
insert into enrichment_quality values('00000000-0000-4000-8000-000000000007','partial',array['missing_summary'],now()-interval '2 days');
select pg_temp.assert((enqueue_hosted_quality_jobs(array['11111111-1111-4111-8111-111111111111']::uuid[])->>'enqueued')::int=1,'hourly audit only by default');
select pg_temp.assert((enqueue_hosted_quality_jobs(array['11111111-1111-4111-8111-111111111111']::uuid[])->>'enqueued')::int=0,'hour bucket dedupes');
select pg_temp.assert((select count(*)=1 from hosted_quality_jobs),'no accidental research');
select pg_temp.assert((select jsonb_array_length(input->'items')=3 from hosted_quality_jobs),'three source maximum');
select pg_temp.assert((select input->'items' @> '[{"id":"00000000-0000-4000-8000-000000000007"}]' from hosted_quality_jobs),'older unresolved card sampled');
select pg_temp.assert((select bool_and(length(i->>'page_body')=6000 and length(i->>'summary')=3000 and length(i->>'description')=1200 and (i->>'source_truncated')::boolean) from hosted_quality_jobs j,jsonb_array_elements(j.input->'items') i),'bounded source snapshots');
select pg_temp.assert((select bool_and(input::text not like '%must not enter job%') from hosted_quality_jobs),'source scope boundary');
select pg_temp.assert((enqueue_hosted_quality_jobs(array['11111111-1111-4111-8111-111111111111']::uuid[],true)->>'enqueued')::int=1,'research explicit capability gate');

do $$ declare j jsonb; old_token uuid; target uuid; old_fence bigint; r jsonb; payload jsonb := '{"schema_version":1,"summary":"Bounded audit","findings":[],"proposals":[],"uncertainties":[]}'; begin
  j:=claim_hosted_quality_job(); target:=(j->>'id')::uuid; old_token:=(j->>'lease_token')::uuid; old_fence:=(j->>'fence')::bigint;
  perform pg_temp.assert(j->'budget'='{"max_turns":6,"run_seconds":90}'::jsonb,'pilot budget returned');
  perform pg_temp.assert((heartbeat_hosted_quality_job(target,old_token,old_fence)->>'ok')::boolean,'active heartbeat');
  for n in 1..6 loop perform pg_temp.assert((quality_authorize_model(target,old_token,old_fence)->>'ok')::boolean,'model budget allows six'); end loop;
  perform pg_temp.assert(quality_authorize_model(target,old_token,old_fence)->>'error'='model_budget_exhausted','seventh call denied');
  update hosted_quality_jobs set lease_expires_at=now()-interval '1 second' where id=target;
  perform pg_temp.assert(heartbeat_hosted_quality_job(target,old_token,old_fence)->>'error'='lease_lost','expired lease cannot resurrect');
  perform pg_temp.assert(complete_hosted_quality_job(target,old_token,old_fence,payload)->>'error'='lease_lost','expired worker cannot complete');
  -- Make the expired job first so claim reclaims this specific attempt.
  update hosted_quality_jobs set available_at=now()+interval '1 hour' where id<>target;
  j:=claim_hosted_quality_job(); perform pg_temp.assert((j->>'id')::uuid=target and (j->>'fence')::bigint=old_fence+1,'reclaim increments fence');
  perform pg_temp.assert(quality_authorize_model(target,old_token,old_fence)->>'error'='lease_lost','stale model request fenced');
  perform pg_temp.assert(complete_hosted_quality_job(target,old_token,old_fence,payload)->>'error'='lease_lost','stale result fenced');
  old_token:=(j->>'lease_token')::uuid; old_fence:=(j->>'fence')::bigint;
  r:=complete_hosted_quality_job(target,old_token,old_fence,payload,'{"output_tokens":7,"input_tokens":10}');
  perform pg_temp.assert((r->>'ok')::boolean and not (r->>'idempotent')::boolean,'first completion accepted');
  -- jsonb canonicalization dedupes differing JSON key order without hashing in the client.
  r:=complete_hosted_quality_job(target,old_token,old_fence,'{"uncertainties":[],"findings":[],"summary":"Bounded audit","proposals":[],"schema_version":1}','{"input_tokens":10,"output_tokens":7}');
  perform pg_temp.assert((r->>'idempotent')::boolean,'identical completion retry accepted');
  perform pg_temp.assert(complete_hosted_quality_job(target,old_token,old_fence,payload||'{"summary":"Changed"}') ->>'error'='completion_conflict','changed retry refused');
  perform pg_temp.assert((select count(*)=1 from hosted_quality_results where job_id=target),'single immutable result');
  update hosted_quality_jobs set available_at=now() where status='queued';
  j:=claim_hosted_quality_job();target:=(j->>'id')::uuid;
  update hosted_quality_jobs set attempts=3 where id=target;
  r:=fail_hosted_quality_job(target,(j->>'lease_token')::uuid,(j->>'fence')::bigint,'worker_timeout');
  perform pg_temp.assert(r->>'status'='failed','bounded retries terminal after third attempt');
end $$;

do $$ declare rid uuid; message jsonb; first_key text; tok uuid; begin
  insert into hosted_quality_reports(recipient,report_day,payload) values('will@example.org',current_date,'{"results":[]}') returning id into rid;
  insert into hosted_quality_outbox(report_id,idempotency_key) values(rid,'hosted-quality/'||rid::text);
  message:=claim_hosted_quality_email();first_key:=message->>'idempotency_key';tok:=(message->>'lease_token')::uuid;
  perform pg_temp.assert(claim_hosted_quality_email() is null,'concurrent sender cannot claim leased email');
  perform pg_temp.assert(finish_hosted_quality_email((message->>'id')::uuid,tok,false,null,'transport_uncertain'),'uncertain send queued');
  update hosted_quality_outbox set next_attempt_at=now();
  message:=claim_hosted_quality_email();
  perform pg_temp.assert(message->>'idempotency_key'=first_key,'retry keeps same provider idempotency key');
  perform pg_temp.assert(not finish_hosted_quality_email((message->>'id')::uuid,tok,true,'wrong-worker'),'stale email sender fenced');
  perform pg_temp.assert(finish_hosted_quality_email((message->>'id')::uuid,(message->>'lease_token')::uuid,true,'provider-id'),'accepted delivery persisted');
  perform pg_temp.assert(claim_hosted_quality_email() is null,'accepted report never resent');
  update hosted_quality_outbox set status='sending',first_attempt_at=now()-interval '24 hours',lease_expires_at=now()-interval '1 minute';
  perform pg_temp.assert(claim_hosted_quality_email() is null,'provider idempotency window expiry stops blind resend');
  perform pg_temp.assert((select status='uncertain' from hosted_quality_outbox),'uncertain delivery visible');
end $$;
select pg_temp.assert((select count(*)=7 from items),'saved items never modified or removed');
do $$ declare affected uuid; unaffected uuid; removed_report uuid; kept_report uuid; begin
  select id into affected from hosted_quality_jobs limit 1;
  insert into hosted_quality_jobs(kind,dedupe_key,input,input_hash) values('audit','unrelated',jsonb_build_object('items',jsonb_build_array(jsonb_build_object('id','00000000-0000-4000-8000-000000000005'))),'hash') returning id into unaffected;
  insert into hosted_quality_reports(recipient,report_day,payload) values('delete@example.org',current_date,jsonb_build_object('results',jsonb_build_array(jsonb_build_object('job_id',affected)))) returning id into removed_report;
  insert into hosted_quality_outbox(report_id,idempotency_key) values(removed_report,'delete-me');
  insert into hosted_quality_reports(recipient,report_day,payload) values('keep@example.org',current_date,jsonb_build_object('results',jsonb_build_array(jsonb_build_object('job_id',unaffected)))) returning id into kept_report;
  delete from items where id='00000000-0000-4000-8000-000000000007';
  perform pg_temp.assert(not exists(select 1 from hosted_quality_jobs where id=affected),'deleting item removes snapshots');
  perform pg_temp.assert(not exists(select 1 from hosted_quality_reports where id=removed_report),'deleting item removes report copy');
  perform pg_temp.assert(not exists(select 1 from hosted_quality_outbox where report_id=removed_report),'deleting item removes report outbox');
  perform pg_temp.assert(exists(select 1 from hosted_quality_jobs where id=unaffected) and exists(select 1 from hosted_quality_reports where id=kept_report),'unrelated user data preserved');
  update hosted_quality_jobs set created_at=now()-interval '36 days' where id=unaffected;
  update hosted_quality_reports set created_at=now()-interval '36 days' where id=kept_report;
  perform prune_hosted_quality_data();
  perform pg_temp.assert(not exists(select 1 from hosted_quality_jobs where id=unaffected) and not exists(select 1 from hosted_quality_reports where id=kept_report),'35 day retention');
  insert into hosted_quality_reports(recipient,report_day,payload) values('retained@example.org',current_date,
    jsonb_build_object('results',jsonb_build_array(jsonb_build_object('job_id',unaffected,'item_ids',jsonb_build_array('00000000-0000-4000-8000-000000000005'))))) returning id into kept_report;
  delete from items where id='00000000-0000-4000-8000-000000000005';
  perform pg_temp.assert(not exists(select 1 from hosted_quality_reports where id=kept_report),'item deletion purges report even after source job aged out');
end $$;
do $$ declare scenario text; iid uuid; rid uuid; message jsonb; sample_recipient text; begin
  foreach scenario in array array['accepted','possibly_sent'] loop
    iid:=gen_random_uuid();sample_recipient:=scenario||'@example.org';
    insert into items(id,user_id,type,url) values(iid,'11111111-1111-4111-8111-111111111111','link','https://example.org/deleted');
    insert into hosted_quality_reports(recipient,report_day,payload) values(sample_recipient,current_date,
      jsonb_build_object('results',jsonb_build_array(jsonb_build_object('item_ids',jsonb_build_array(iid::text))))) returning id into rid;
    insert into hosted_quality_outbox(report_id,idempotency_key) values(rid,'hosted-quality/'||rid::text);
    message:=claim_hosted_quality_email();
    perform pg_temp.assert(message->>'recipient'=sample_recipient,'claim deletion fixture');
    if scenario='accepted' then
      perform finish_hosted_quality_email((message->>'id')::uuid,(message->>'lease_token')::uuid,true,'provider-id');
    end if;
    delete from items where id=iid;
    perform pg_temp.assert(not exists(select 1 from hosted_quality_reports where id=rid),'delete private report payload');
    perform pg_temp.assert(exists(select 1 from hosted_quality_delivery_receipts d where d.recipient=sample_recipient),'delivery receipt survives payload purge');
    -- Even a recreated outbox with a new UUID/key must not authorize a second daily send.
    insert into hosted_quality_reports(recipient,report_day,payload) values(sample_recipient,current_date,'{"results":[]}') returning id into rid;
    insert into hosted_quality_outbox(report_id,idempotency_key) values(rid,'hosted-quality/'||rid::text);
    perform pg_temp.assert(claim_hosted_quality_email() is null,'deletion must not authorize another daily email: '||scenario);
    delete from hosted_quality_reports where id=rid;
  end loop;
  update hosted_quality_delivery_receipts set first_attempt_at=now()-interval '36 days' where recipient='legacy@example.org';
  perform prune_hosted_quality_data();
  perform pg_temp.assert(not exists(select 1 from hosted_quality_delivery_receipts where recipient='legacy@example.org'),'delivery receipts expire after35days');
  perform pg_temp.assert(exists(select 1 from hosted_quality_delivery_receipts where recipient='accepted@example.org'),'recent receipt preserved');
end $$;
select 'hosted quality SQL assertions passed' as result;
rollback;
