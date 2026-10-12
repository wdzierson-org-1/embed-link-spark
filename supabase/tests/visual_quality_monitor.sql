-- Run in a rolled-back transaction after the migration. No real user item is changed.
begin;
do $$
declare uid uuid; jid uuid; j jsonb; n integer; p jsonb; item uuid:=gen_random_uuid();
begin
 if has_function_privilege('authenticated','public.claim_hosted_visual_job()','EXECUTE') then raise exception 'client can claim'; end if;
 if has_table_privilege('authenticated','public.hosted_visual_jobs','SELECT') then raise exception 'client can read jobs'; end if;
 select id into uid from auth.users order by created_at limit 1;
 if uid is null then raise exception 'test needs one existing Auth identity'; end if;
 insert into hosted_visual_jobs(kind,dedupe_key,owner_id,item_id,checked_url) values('sample','test-visual-budget',uid,item,'https://example.org/test') returning id into jid;
 j:=claim_hosted_visual_job();
 -- Existing queued work may precede our fixture. Use the test row explicitly, in this rollback only.
 update hosted_visual_jobs set status='running',lease_token=gen_random_uuid(),fence=1,lease_expires_at=now()+interval '120 seconds' where id=jid;
 select to_jsonb(x) into j from hosted_visual_jobs x where id=jid;
 if authorize_hosted_visual_model(jid,gen_random_uuid(),1) then raise exception 'wrong token authorized'; end if;
 -- Isolate existing day budget in rollback only, never remove live usage on commit.
 delete from hosted_visual_model_calls;
 if not authorize_hosted_visual_model(jid,(j->>'lease_token')::uuid,1) then raise exception 'first reservation denied'; end if;
 if not authorize_hosted_visual_model(jid,(j->>'lease_token')::uuid,1) then raise exception 'second reservation denied'; end if;
 if authorize_hosted_visual_model(jid,(j->>'lease_token')::uuid,1) then raise exception 'per-job cap exceeded'; end if;
 if complete_hosted_visual_job(jid,gen_random_uuid(),1,'{"schema_version":1,"checks":[]}',null) then raise exception 'stale result accepted'; end if;
 if complete_hosted_visual_job(jid,(j->>'lease_token')::uuid,1,'{"schema_version":1,"checks":[{"outcome":"bogus"}]}',null) then raise exception 'invalid result accepted'; end if;
 if not complete_hosted_visual_job(jid,(j->>'lease_token')::uuid,1,'{"schema_version":1,"checked_at":"2026-10-12T00:00:00Z","checks":[{"surface":"card","mode":"image","outcome":"mismatch","reason":"test","comparison":{"summary":"private secret"}}]}',null) then raise exception 'valid completion refused'; end if;
 p:=hosted_visual_report(now()-interval '1 minute',now()+interval '1 minute');
 if p::text like '%private secret%' then raise exception 'private content leaked to report'; end if;
 if (p->>'private_findings')::int<1 then raise exception 'private finding omitted from counts'; end if;
 if exists(select 1 from hosted_visual_jobs where id=jid and status<>'completed') then raise exception 'completion not durable'; end if;
 -- Baseline source bytes/identity cannot be updated in place.
 insert into hosted_visual_baselines(id,version,title,source_url,image_path,sha256,description,provenance)
 values('test-visual',1,'test','https://example.org/test','test-visual/v1.png',repeat('a',64),'approved test', '{}');
 begin
   update hosted_visual_baselines set sha256=repeat('b',64) where id='test-visual';
   raise exception 'baseline mutation allowed';
 exception when check_violation then null; end;
 if purge_hosted_visual_canary(jid,null) then raise exception 'sample deletion allowed'; end if;
 raise notice 'visual monitor SQL assertions passed';
end $$;

-- Separate hour/day budgets from per-job limits. Deleting a sampled save must
-- erase its private inspection while preserving already consumed spend.
do $$
declare uid uuid; ids uuid[]:='{}'; tokens uuid[]:='{}'; jid uuid; tok uuid; iid uuid:=gen_random_uuid();
 n integer; hour_start timestamptz:=date_trunc('hour',now());
 day_start timestamptz:=date_trunc('day',now() at time zone 'UTC') at time zone 'UTC';
begin
 select id into uid from auth.users order by created_at limit 1;
 delete from hosted_visual_model_calls; -- Only inside this transaction, always rolled back.
 for n in 1..3 loop
   tok:=gen_random_uuid();
   insert into hosted_visual_jobs(kind,dedupe_key,owner_id,checked_url,status,lease_token,fence,lease_expires_at)
   values('sample','test-budget-'||gen_random_uuid(),uid,'https://example.org/budget','running',tok,1,now()+interval '2 minutes') returning id into jid;
   ids:=array_append(ids,jid); tokens:=array_append(tokens,tok);
 end loop;
 if authorize_hosted_visual_model(ids[1],tokens[1],2) then raise exception 'stale fence spent budget'; end if;
 update hosted_visual_jobs set lease_expires_at=now()-interval '1 second' where id=ids[1];
 if authorize_hosted_visual_model(ids[1],tokens[1],1) then raise exception 'expired lease spent budget'; end if;
 update hosted_visual_jobs set lease_expires_at=now()+interval '2 minutes' where id=ids[1];
 for n in 1..2 loop
   if not authorize_hosted_visual_model(ids[n],tokens[n],1) or not authorize_hosted_visual_model(ids[n],tokens[n],1)
     then raise exception 'hour reservation % refused before cap',n; end if;
 end loop;
 if authorize_hosted_visual_model(ids[3],tokens[3],1) then raise exception 'fifth hourly call allowed'; end if;
 if (select count(*) from hosted_visual_model_calls where reserved_at>=hour_start)<>4 then raise exception 'hour reservations not durable'; end if;

 -- At midnight the four-call hourly cap necessarily subsumes the daily cap.
 -- At every later UTC hour this independently proves the 48th passes and 49th
 -- fails, with only one reservation in the current hour and one on this job.
 if hour_start>day_start then
   delete from hosted_visual_model_calls;
   insert into hosted_visual_model_calls(reserved_at) select day_start from generate_series(1,47);
   if not authorize_hosted_visual_model(ids[3],tokens[3],1) then raise exception '48th daily reservation refused'; end if;
   if authorize_hosted_visual_model(ids[3],tokens[3],1) then raise exception '49th daily reservation allowed'; end if;
   if (select count(*) from hosted_visual_model_calls where reserved_at>=hour_start)<>1 then raise exception 'daily cap test did not isolate hourly budget'; end if;
 else raise notice 'Independent daily cap boundary test skipped in first UTC hour; stricter hourly cap asserted'; end if;

 delete from hosted_visual_model_calls;
 update hosted_visual_jobs set model_calls=0 where id=any(ids);
 insert into items(id,user_id,type,url,title,is_public,visibility,attributes)
 values(iid,uid,'link','https://example.org/budget','Visual monitor rollback budget fixture',false,'private','{"enrichment":{"status":"complete"}}');
 update hosted_visual_jobs set item_id=iid where id=ids[1];
 if not authorize_hosted_visual_model(ids[1],tokens[1],1) or not authorize_hosted_visual_model(ids[1],tokens[1],1)
 then raise exception 'sample reservations refused'; end if;
 delete from items where id=iid;
 if exists(select 1 from hosted_visual_jobs where id=ids[1]) then raise exception 'private sample survives item deletion'; end if;
 if (select count(*) from hosted_visual_model_calls where job_id is null)<>2 then raise exception 'item deletion erased paid reservations'; end if;
 if not authorize_hosted_visual_model(ids[2],tokens[2],1) or not authorize_hosted_visual_model(ids[2],tokens[2],1)
 then raise exception 'remaining hourly reservations refused'; end if;
 if authorize_hosted_visual_model(ids[3],tokens[3],1) then raise exception 'item deletion reset hourly budget'; end if;
 if hour_start>day_start then
   update hosted_visual_model_calls set reserved_at=day_start;
   insert into hosted_visual_model_calls(reserved_at) select day_start from generate_series(1,43);
   if not authorize_hosted_visual_model(ids[3],tokens[3],1) then raise exception '48th call after deletion refused'; end if;
   if authorize_hosted_visual_model(ids[3],tokens[3],1) then raise exception 'item deletion reset daily budget'; end if;
 end if;
 raise notice 'visual budget and privacy deletion assertions passed';
end $$;

-- An hourly receipt is independent of the deletable job and its private data.
do $$
declare uid uuid; first_result jsonb; next_result jsonb; bucket text:=to_char(now() at time zone 'UTC','YYYY-MM-DD"T"HH24');
 keys text[]; before_count integer;
begin
 select id into uid from auth.users order by created_at limit 1;
 insert into hosted_visual_config(singleton,monitor_user_id) values(true,uid)
 on conflict(singleton) do update set monitor_user_id=excluded.monitor_user_id;
 update hosted_visual_baselines set enabled=true where id='test-visual' and version=1;
 keys:=array['visual-v1:canary:'||bucket,'visual-v1:sample:'||bucket];
 delete from hosted_visual_jobs where dedupe_key=any(keys);
 delete from hosted_visual_dispatch_receipts where dedupe_key=any(keys);
 first_result:=enqueue_hosted_visual_jobs();
 if not exists(select 1 from hosted_visual_jobs where dedupe_key=keys[1]) then raise exception 'eligible canary did not enqueue'; end if;
 select count(*) into before_count from hosted_visual_dispatch_receipts where dedupe_key=any(keys);
 delete from hosted_visual_jobs where dedupe_key=any(keys);
 if (select count(*) from hosted_visual_dispatch_receipts where dedupe_key=any(keys))<>before_count then raise exception 'job deletion erased hourly dispatch receipt'; end if;
 next_result:=enqueue_hosted_visual_jobs();
 if (next_result->>'enqueued')::integer<>0 then raise exception 'deleted jobs were enqueued again in the same hour'; end if;
 raise notice 'visual hourly dispatch dedupe assertions passed';
end $$;

-- A process can die after capture commits but before registration. Recover only
-- the exact done receipt, owner and private fixture, then retain cleanup evidence
-- even after the item is gone so a storage retry is still possible.
do $$
declare uid uuid; jid uuid:=gen_random_uuid(); iid uuid:=gen_random_uuid(); foreign_owner uuid:=gen_random_uuid();
 wrong_receipt uuid:=gen_random_uuid(); preview text; cleanup jsonb; ignored jsonb;
 public_item uuid:=gen_random_uuid(); public_job uuid:=gen_random_uuid(); foreign_job uuid:=gen_random_uuid();
begin
 select id into uid from auth.users order by created_at limit 1;
 preview:=uid::text||'/previews/preview_123456789.png';
 insert into items(id,user_id,type,url,title,is_public,visibility,file_path,attributes)
 values(iid,uid,'link','https://example.org/test','Visual monitor rollback cleanup fixture',false,'private',preview,'{"enrichment":{"status":"complete"}}');
 insert into hosted_visual_jobs(id,kind,dedupe_key,owner_id,checked_url,fixture_id,fixture_version,created_at)
 values(jid,'canary','test-cleanup-'||jid,uid,'https://example.org/test','test-visual',1,now()-interval '31 minutes');
 insert into capture_receipts(user_id,capture_id,item_id,status) values(uid,jid,iid,'done');
 ignored:=claim_hosted_visual_job();
 if not exists(select 1 from hosted_visual_jobs where id=jid and item_id=iid and status='failed' and last_error='job_expired')
 then raise exception 'lost-registration receipt was not recovered before expiry'; end if;
 cleanup:=list_hosted_visual_cleanup();
 if not cleanup @> jsonb_build_array(jsonb_build_object('job_id',jid,'item_id',iid,'file_path',preview)) then raise exception 'recovered canary missing from cleanup'; end if;

 if purge_hosted_visual_canary(jid,preview||'.changed') then raise exception 'changed preview deletion accepted'; end if;
 update items set is_public=true where id=iid;
 if purge_hosted_visual_canary(jid,preview) then raise exception 'public canary deletion accepted'; end if;
 update items set is_public=false where id=iid;
 update hosted_visual_jobs set owner_id=foreign_owner where id=jid;
 if purge_hosted_visual_canary(jid,preview) then raise exception 'foreign canary deletion accepted'; end if;
 update hosted_visual_jobs set owner_id=uid where id=jid;
 update capture_receipts set capture_id=wrong_receipt where capture_id=jid and user_id=uid;
 if purge_hosted_visual_canary(jid,preview) then raise exception 'wrong capture receipt deletion accepted'; end if;
 update capture_receipts set capture_id=jid,status='pending' where capture_id=wrong_receipt and user_id=uid;
 if purge_hosted_visual_canary(jid,preview) then raise exception 'unfinished capture receipt deletion accepted'; end if;
 update capture_receipts set status='done' where capture_id=jid and user_id=uid;
 if not exists(select 1 from items where id=iid) then raise exception 'rejected cleanup still deleted item'; end if;

 if not purge_hosted_visual_canary(jid,preview) then raise exception 'registered settled canary deletion refused'; end if;
 if exists(select 1 from items where id=iid) then raise exception 'canary row still exists'; end if;
 if not exists(select 1 from hosted_visual_jobs where id=jid and cleanup_file_path=preview and cleaned_item_at is not null and cleaned_media_at is null)
 then raise exception 'media cleanup tombstone not durable'; end if;
 if not purge_hosted_visual_canary(jid,preview) then raise exception 'cleanup retry lost after row deletion'; end if;
 if purge_hosted_visual_canary(jid,preview||'.changed') then raise exception 'cleanup retry accepted a different path'; end if;
 cleanup:=list_hosted_visual_cleanup();
 if not cleanup @> jsonb_build_array(jsonb_build_object('job_id',jid,'file_path',preview)) then raise exception 'media retry no longer listed'; end if;
 if finish_hosted_visual_cleanup(jid,preview||'.changed') then raise exception 'wrong media cleanup path accepted'; end if;
 if not finish_hosted_visual_cleanup(jid,preview) then raise exception 'media cleanup acknowledgement refused'; end if;
 if list_hosted_visual_cleanup() @> jsonb_build_array(jsonb_build_object('job_id',jid)) then raise exception 'finished cleanup still queued'; end if;

 insert into items(id,user_id,type,url,title,is_public,visibility,attributes)
 values(public_item,uid,'link','https://example.org/test','Visual monitor rollback public fixture',true,'public','{"enrichment":{"status":"complete"}}');
 insert into hosted_visual_jobs(id,kind,dedupe_key,owner_id,checked_url,fixture_id,fixture_version,created_at)
 values(public_job,'canary','test-public-'||public_job,uid,'https://example.org/test','test-visual',1,now()-interval '31 minutes'),
 (foreign_job,'canary','test-foreign-'||foreign_job,foreign_owner,'https://example.org/test','test-visual',1,now()-interval '31 minutes');
 insert into capture_receipts(user_id,capture_id,item_id,status) values(uid,public_job,public_item,'done'),(uid,foreign_job,public_item,'done');
 ignored:=claim_hosted_visual_job();
 if exists(select 1 from hosted_visual_jobs where id in(public_job,foreign_job) and item_id is not null)
 then raise exception 'receipt reconciliation adopted a public or foreign save'; end if;
 if not exists(select 1 from items where id=public_item) then raise exception 'receipt reconciliation deleted public save'; end if;
 raise notice 'visual private canary recovery and cleanup retry assertions passed';
end $$;
select 'visual_monitor_sql_assertions_passed' as assertion;
rollback;
