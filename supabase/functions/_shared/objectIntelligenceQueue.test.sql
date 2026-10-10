-- Disposable, empty PostgreSQL 14+ only. Entire fixture rolls back.
\set ON_ERROR_STOP on
begin;
create role anon; create role authenticated; create role service_role;
create table public.items (
 id uuid primary key,user_id uuid,type text,url text,title text,description text,summary text,
 content text,supplemental_note text,page_body text,file_path text,mime_type text,
 created_at timestamptz default now(),attributes jsonb,archived_at timestamptz
);
-- Existing production extension; avoid requiring pg_cron on the disposable host.
create schema cron;
create table cron.job(jobname text,schedule text,command text);
create function cron.schedule(text,text,text) returns bigint language plpgsql as $$ begin
 insert into cron.job values($1,$2,$3); return 1; end $$;
insert into items(id,type,page_body,created_at) select gen_random_uuid(),'link','Captured source',now()-make_interval(secs=>n) from generate_series(1,105) n;
insert into items(id,type,page_body,archived_at) values(gen_random_uuid(),'link','Archived source',now()),(gen_random_uuid(),'collection','Collection source',null);
\ir ../../migrations/20261011120000_object_intelligence_queue.sql
create function pg_temp.assert(ok boolean,label text) returns void language plpgsql as $$ begin
 if ok is distinct from true then raise exception 'ASSERTION FAILED: %',label; end if; end $$;
create function pg_temp.snapshot(target uuid) returns jsonb language sql as $$
 select jsonb_build_object('type',type,'url',url,'title',title,'description',description,'summary',summary,
 'content',content,'supplemental_note',supplemental_note,'page_body',page_body,'file_path',file_path,'mime_type',mime_type,'attributes',attributes)
 from items where id=target $$;
select pg_temp.assert((select count(*)=100 from object_intelligence_jobs),'bounded seed');
select pg_temp.assert((select bool_and(i.type<>'collection' and i.archived_at is null) from object_intelligence_jobs j join items i on i.id=j.item_id),'only current real objects seeded');
select pg_temp.assert((select count(*)=1 from cron.job where jobname='object-intelligence-worker' and schedule='*/5 * * * *'),'hosted five minute cron registered');
select pg_temp.assert(not has_table_privilege('authenticated','object_intelligence_jobs','select'),'users cannot read queue');
select pg_temp.assert(not has_table_privilege('anon','object_intelligence_control','select'),'anonymous cannot read budget');
select pg_temp.assert((select bool_and(relrowsecurity) from pg_class where relname in ('object_intelligence_jobs','object_intelligence_control')),'internal tables RLS');
select pg_temp.assert(not has_function_privilege('authenticated','claim_object_intelligence_jobs(uuid,integer)','execute'),'claim service-only');
select pg_temp.assert(not has_function_privilege('anon','commit_object_intelligence(uuid,uuid,jsonb,jsonb)','execute'),'commit service-only');
select pg_temp.assert(has_function_privilege('service_role','begin_object_intelligence_run()','execute'),'service can begin');
truncate object_intelligence_jobs;

do $$ declare iid uuid:=gen_random_uuid(); other_id uuid:=gen_random_uuid(); run_id uuid; j object_intelligence_jobs; old_j object_intelligence_jobs; exp jsonb;
 intelligence jsonb:='{"version":1,"beta":true,"extraction_version":"object-intelligence-v1","source_fingerprint":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","processed_at":"2026-10-11T01:00:00Z","interpretation":{"kind":"recipe","summary":"Tomato pasta","topics":[]},"facts":{},"evidence":[],"capabilities":[]}'; begin
 insert into items(id,user_id,type,url,page_body,attributes) values(iid,gen_random_uuid(),'link','https://example.org/pasta','Tomato pasta with basil','{"custom":{"keep":true}}');
 perform pg_temp.assert((select revision=1 and next_run_at=now()+interval '2 minutes' from object_intelligence_jobs where item_id=iid),'new save has settling delay');
 update items set summary='AI summary',description='AI description',title='Generated title',attributes=attributes||'{"object_intelligence":{},"enrichment":{"status":"complete"}}' where id=iid;
 perform pg_temp.assert((select revision=1 from object_intelligence_jobs where item_id=iid),'generated fields never loop');
 update items set attributes=jsonb_set(attributes,'{link}','{"author":"A cook"}') where id=iid;
 perform pg_temp.assert((select revision=2 from object_intelligence_jobs where item_id=iid),'creator is source-relevant');
 run_id:=begin_object_intelligence_run();
 perform pg_temp.assert(run_id is not null and begin_object_intelligence_run() is null,'global lease prevents overlap');
 perform pg_temp.assert((select count(*)=0 from claim_object_intelligence_jobs(gen_random_uuid(),10)),'wrong run cannot claim');
 perform pg_temp.assert((select count(*)=0 from claim_object_intelligence_jobs(run_id,10)),'settling delay honored');
 update object_intelligence_jobs set next_run_at=now() where item_id=iid;
 select * into j from claim_object_intelligence_jobs(run_id,10);
 perform pg_temp.assert(j.item_id=iid and j.leased_until=now()+interval '5 minutes','five minute item lease');
 perform pg_temp.assert((select count(*)=0 from claim_object_intelligence_jobs(run_id,10)),'claim isolation');
 exp:=pg_temp.snapshot(iid);
 perform pg_temp.assert(not commit_object_intelligence(iid,gen_random_uuid(),exp,intelligence),'wrong item lease denied');
 perform pg_temp.assert(not commit_object_intelligence(iid,j.lease_token,'{}',intelligence),'empty compare-and-swap denied');
 perform pg_temp.assert(not commit_object_intelligence(iid,j.lease_token,exp,'{}'),'invalid envelope rejected');
 update items set supplemental_note='New user note' where id=iid;
 perform pg_temp.assert(not commit_object_intelligence(iid,j.lease_token,exp,intelligence),'whole snapshot protects notes changed during provider call');
 exp:=pg_temp.snapshot(iid);
 perform pg_temp.assert(reserve_object_intelligence_call(run_id,iid,j.lease_token,200,24),'first paid call reserved');
 perform pg_temp.assert(commit_object_intelligence(iid,j.lease_token,exp,intelligence),'matching extraction persists');
 perform pg_temp.assert((select attributes#>'{custom,keep}'='true' from items where id=iid),'unrelated attrs preserved');
 perform pg_temp.assert((select revision=j.revision and last_source_hash=intelligence->>'source_fingerprint' from object_intelligence_jobs where item_id=iid),'commit no loop and fingerprint recorded');
 perform pg_temp.assert(finish_object_intelligence_job(iid,j.lease_token,j.revision,'complete'),'completion accepted');
 perform pg_temp.assert((select status='complete' and attempts=1 and last_status='complete' from object_intelligence_jobs where item_id=iid),'status and paid attempts retained');
 perform pg_temp.assert((select count(*)=0 from claim_object_intelligence_jobs(run_id,10)),'completed source not reprocessed');
 -- New transcript invalidates old claims and gets its own bounded source attempts.
 update items set page_body='New transcript with tomatoes' where id=iid;
 update object_intelligence_jobs set next_run_at=now() where item_id=iid;
 select * into old_j from claim_object_intelligence_jobs(run_id,10);
 update items set page_body='Corrected transcript' where id=iid;
 perform pg_temp.assert(not commit_object_intelligence(iid,old_j.lease_token,pg_temp.snapshot(iid),intelligence),'source revision fences stale worker even with fresh snapshot');
 perform pg_temp.assert(not finish_object_intelligence_job(iid,old_j.lease_token,old_j.revision,'complete'),'stale finish cannot close newer source');
 update object_intelligence_jobs set next_run_at=now() where item_id=iid;
 select * into j from claim_object_intelligence_jobs(run_id,10);
 update items set attributes=jsonb_set(attributes,'{enrichment}','{"protected_fields":{"object_intelligence":true}}') where id=iid;
 perform pg_temp.assert(not commit_object_intelligence(iid,j.lease_token,pg_temp.snapshot(iid),intelligence),'user field protection honored');
 perform pg_temp.assert(not finish_object_intelligence_job(iid,j.lease_token,j.revision,'protected'),'lock transition fences prior claim');
 update object_intelligence_jobs set next_run_at=now() where item_id=iid;
 select * into j from claim_object_intelligence_jobs(run_id,10);
 perform pg_temp.assert(finish_object_intelligence_job(iid,j.lease_token,j.revision,'protected'),'protected source terminal');
 insert into items(id,user_id,type,content) values(other_id,gen_random_uuid(),'text','Another user source');
 update object_intelligence_jobs set next_run_at=now() where item_id=other_id;
 select * into j from claim_object_intelligence_jobs(run_id,10);
 perform pg_temp.assert(not commit_object_intelligence(iid,j.lease_token,pg_temp.snapshot(iid),intelligence),'lease cannot target another user item');
 perform pg_temp.assert(reserve_object_intelligence_call(run_id,other_id,j.lease_token,200,24),'second run call allowed');
 perform pg_temp.assert(not reserve_object_intelligence_call(run_id,other_id,j.lease_token,200,24),'third run call denied');
 perform pg_temp.assert(finish_object_intelligence_job(other_id,j.lease_token,j.revision,'retry',60,'secret token example'),'retry accepted');
 perform pg_temp.assert((select last_error='worker_error' from object_intelligence_jobs where item_id=other_id),'arbitrary sensitive errors never stored');
 perform end_object_intelligence_run(run_id);
 -- Hourly and daily budgets persist across run leases.
 run_id:=begin_object_intelligence_run();
 update object_intelligence_jobs set next_run_at=now() where item_id=other_id;
 select * into j from claim_object_intelligence_jobs(run_id,10);
 perform pg_temp.assert(not reserve_object_intelligence_call(run_id,other_id,j.lease_token,200,2),'hourly budget enforced');
 perform pg_temp.assert(not reserve_object_intelligence_call(run_id,other_id,j.lease_token,2,24),'daily budget enforced');
 perform pg_temp.assert(reserve_object_intelligence_call(run_id,other_id,j.lease_token,200,24),'unused budget can be reserved');
 perform pg_temp.assert(reserve_object_intelligence_call(run_id,other_id,j.lease_token,200,24),'third source attempt allowed');
 perform end_object_intelligence_run(run_id);
 run_id:=begin_object_intelligence_run();
 perform pg_temp.assert(not reserve_object_intelligence_call(run_id,other_id,j.lease_token,200,24),'old run cannot reuse item lease');
 perform pg_temp.assert(finish_object_intelligence_job(other_id,j.lease_token,j.revision,'retry',60),'index retry still allowed at provider attempt cap');
 update object_intelligence_jobs set next_run_at=now() where item_id=other_id;
 select * into j from claim_object_intelligence_jobs(run_id,10);
 perform pg_temp.assert(j.item_id=other_id,'existing envelope may be indexed at call cap');
 perform pg_temp.assert(not reserve_object_intelligence_call(run_id,other_id,j.lease_token,200,24),'fourth source call denied');
 update object_intelligence_jobs set leased_until=now()-interval '1 second' where item_id=other_id;
 perform pg_temp.assert(not commit_object_intelligence(other_id,j.lease_token,pg_temp.snapshot(other_id),intelligence),'expired worker cannot persist');
 select * into old_j from claim_object_intelligence_jobs(run_id,10);
 perform pg_temp.assert(old_j.lease_token is distinct from j.lease_token,'expired job reclaimed with new token');
 perform pg_temp.assert(not finish_object_intelligence_job(other_id,j.lease_token,j.revision,'complete'),'expired finish fenced');
 delete from items where id=other_id;
 perform pg_temp.assert(not exists(select 1 from object_intelligence_jobs where item_id=other_id),'account/item deletion removes queue');
 perform end_object_intelligence_run(run_id);
end $$;

-- Provider-free index retries and repeated worker crashes have their own finite ceiling.
truncate object_intelligence_jobs;
do $$ declare iid uuid:=gen_random_uuid(); run_id uuid; j object_intelligence_jobs; n int; before_revision bigint; begin
 insert into items(id,type,content,attributes) values(iid,'text','A recipe with tomatoes','{}');
 run_id:=begin_object_intelligence_run();
 for n in 1..5 loop
   update object_intelligence_jobs set next_run_at=now() where item_id=iid;
   select * into j from claim_object_intelligence_jobs(run_id,10);
   perform pg_temp.assert(j.item_id=iid,'index retry can be claimed before ceiling');
   perform pg_temp.assert(finish_object_intelligence_job(iid,j.lease_token,j.revision,'retry',300,'index_failed'),'index failure recorded');
 end loop;
 perform pg_temp.assert((select status='failed' and failure_count=5 and attempts=0 from object_intelligence_jobs where item_id=iid),'fifth index failure terminal without charging model allowance');
 update object_intelligence_jobs set next_run_at=now() where item_id=iid;
 perform pg_temp.assert((select count(*)=0 from claim_object_intelligence_jobs(run_id,10)),'terminal failed job is not reclaimed');
 update items set content='Changed source recipe' where id=iid;
 perform pg_temp.assert((select status='queued' and failure_count=0 and attempts=0 from object_intelligence_jobs where item_id=iid),'source revision resets only its retry allowance');
 select revision into before_revision from object_intelligence_jobs where item_id=iid;
 update items set attributes='{"media":{"transcript":{"status":"processing"}}}' where id=iid;
 update items set attributes='{"media":{"transcript":{"status":"complete"}}}' where id=iid;
 perform pg_temp.assert((select revision=before_revision+2 from object_intelligence_jobs where item_id=iid),'transcript completion wakes extraction');
 update object_intelligence_jobs set next_run_at=now() where item_id=iid;
 select * into j from claim_object_intelligence_jobs(run_id,10);
 for n in 1..5 loop
   update object_intelligence_jobs set leased_until=now()-interval '1 second' where item_id=iid;
   perform * from claim_object_intelligence_jobs(run_id,10);
 end loop;
 perform pg_temp.assert((select status='failed' and failure_count=5 from object_intelligence_jobs where item_id=iid),'fifth abandoned lease terminal');
 -- UTC rollover resets both budget windows, independent of run token generation.
 update items set content='New valid source' where id=iid;
 update object_intelligence_jobs set next_run_at=now() where item_id=iid;
 select * into j from claim_object_intelligence_jobs(run_id,10);
 update object_intelligence_control set budget_day=current_date-1,daily_calls=500,budget_hour=now()-interval '2 hours',hourly_calls=24,run_calls=0;
 perform pg_temp.assert(reserve_object_intelligence_call(run_id,iid,j.lease_token,200,24),'elapsed budget windows reset');
 perform pg_temp.assert((select daily_calls=1 and hourly_calls=1 from object_intelligence_control),'first rollover reservation counted once');
 update object_intelligence_control set daily_calls=500;
 perform pg_temp.assert(not reserve_object_intelligence_call(run_id,iid,j.lease_token,100000,100000),'caller cannot exceed daily hard cap');
 update object_intelligence_control set daily_calls=0,hourly_calls=24;
 perform pg_temp.assert(not reserve_object_intelligence_call(run_id,iid,j.lease_token,100000,100000),'caller cannot exceed hourly hard cap');
 perform end_object_intelligence_run(run_id);
end $$;
truncate object_intelligence_jobs;
insert into items(id,type,content) select gen_random_uuid(),'text','Captured note' from generate_series(1,15);
update object_intelligence_jobs set next_run_at=now();
do $$ declare run_id uuid; begin
 run_id:=begin_object_intelligence_run();
 perform pg_temp.assert((select count(*)=10 from claim_object_intelligence_jobs(run_id,1000)),'claim batch hard cap ten');
 perform end_object_intelligence_run(run_id);
end $$;
rollback;
