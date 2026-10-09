-- Run against an empty disposable PostgreSQL14+ database. All changes roll back.
begin;
create role anon; create role authenticated; create role service_role;
create schema extensions;
create table public.items(id uuid primary key,user_id uuid,type text,url text,title text,description text,summary text,page_body text,created_at timestamptz default now());
create table public.enrichment_quality(item_id uuid,status text,reasons text[],evaluated_at timestamptz);
create table public.enrichment_attempts(item_id uuid,strategy text,outcome text,reasons text[],created_at timestamptz);
\ir ../../migrations/20261009120000_hosted_quality.sql
\ir ../../migrations/20261009130000_hosted_quality_delivery_receipts.sql
\ir ../../migrations/20261009150000_hosted_quality_live_evidence.sql
create function pg_temp.assert(ok boolean,label text) returns void language plpgsql as $$ begin
  if ok is distinct from true then raise exception 'ASSERTION FAILED: %',label; end if;
end $$;
insert into items(id,user_id,type,url,title) values
 ('00000000-0000-4000-8000-000000000001','11111111-1111-4111-8111-111111111111','link','https://example.org/first','First'),
 ('00000000-0000-4000-8000-000000000002','11111111-1111-4111-8111-111111111111','link','https://example.org/partial','Partial');
insert into hosted_quality_jobs(id,kind,dedupe_key,input,input_hash,status,lease_token,fence,lease_expires_at,deadline_at) values
 ('22222222-2222-4222-8222-222222222222','research','research-fixture','{"items":[{"id":"00000000-0000-4000-8000-000000000001","url":"https://example.org/first","page_body":""},{"id":"00000000-0000-4000-8000-000000000002","url":"https://example.org/partial","page_body":"existing body","quality":{"status":"partial"}}]}','test','running','33333333-3333-4333-8333-333333333333',1,now()+interval '60 seconds',now()+interval '90 seconds');

do $$ declare
 target uuid:='22222222-2222-4222-8222-222222222222'; token uuid:='33333333-3333-4333-8333-333333333333';
 reservation jsonb; next_reservation jsonb; observed jsonb; receipt jsonb; old_attempt uuid; report_results jsonb;
begin
 update hosted_quality_jobs set kind='audit' where id=target;
 perform pg_temp.assert(reserve_hosted_quality_investigation(target,token,1)->>'error'='unsupported_job_kind','snapshot audits cannot perform live retrieval');
 update hosted_quality_jobs set kind='research' where id=target;
 perform pg_temp.assert(finish_hosted_quality_investigation(target,token,1,null,'{}')->>'error'='investigation_lost','cannot finish without acquiring a reservation');
 reservation:=reserve_hosted_quality_investigation(target,token,1);
 perform pg_temp.assert((reservation->>'ok')::boolean,'first reservation allowed');
 perform pg_temp.assert(reservation->'item'->>'id'='00000000-0000-4000-8000-000000000002','partial item preferred over first missing source');
 old_attempt:=(reservation->>'attempt_token')::uuid;
 perform pg_temp.assert(reserve_hosted_quality_investigation(target,token,1)->>'error'='investigation_busy','concurrent duplicate cannot buy another scrape');
 perform pg_temp.assert(reserve_hosted_quality_investigation(target,token,2)->>'error'='lease_lost','stale fence rejected');
 observed:=jsonb_build_object('schema_version',1,'item_id',reservation->'item'->>'id','url',reservation->'item'->>'url','captured_at',now(),'outcome','retrieved','title','Partial','text','private fetched source','source_truncated',false,'image_candidates','[]'::jsonb,'attempts','[{"strategy":"firecrawl","outcome":"retrieved","reason":"page_read","duration_ms":123}]'::jsonb,'limitations','[]'::jsonb);
 perform pg_temp.assert(finish_hosted_quality_investigation(target,token,1,old_attempt,observed||'{"url":"https://foreign.example/"}')->>'error'='observation_out_of_scope','cannot store foreign evidence');
 -- A lost response can be retried after its reservation expires, without resetting total spend.
 update hosted_quality_jobs set investigation_started_at=now()-interval '31 seconds' where id=target;
 next_reservation:=reserve_hosted_quality_investigation(target,token,1);
 perform pg_temp.assert((next_reservation->>'ok')::boolean,'expired reservation can retry');
 perform pg_temp.assert(finish_hosted_quality_investigation(target,token,1,old_attempt,observed)->>'error'='investigation_lost','late first response cannot overwrite newer reservation');
 receipt:=finish_hosted_quality_investigation(target,token,1,(next_reservation->>'attempt_token')::uuid,observed);
 perform pg_temp.assert(receipt->'observation'=observed,'persist exact observation');
 perform pg_temp.assert((finish_hosted_quality_investigation(target,token,1,(next_reservation->>'attempt_token')::uuid,observed)->>'ok')::boolean,'same completion is idempotent');
 perform pg_temp.assert(finish_hosted_quality_investigation(target,token,1,(next_reservation->>'attempt_token')::uuid,observed||'{"text":"changed"}')->>'error'='observation_conflict','durable evidence immutable');
 perform pg_temp.assert((reserve_hosted_quality_investigation(target,token,1)->>'cached')::boolean,'durable evidence skips paid retrieval');
 perform pg_temp.assert((select investigation_attempts=2 from hosted_quality_jobs where id=target),'cached request does not spend');
 perform pg_temp.assert(hosted_quality_job_context(target,token,1)->'observation'=observed,'analysis context includes durable evidence');
 report_results:=hosted_quality_report_results(now()-interval '1 day',now()+interval '1 day');
 perform pg_temp.assert(report_results->0->'retrieval'->>'outcome'='retrieved','report contains collected evidence even if model analysis not complete');
 perform pg_temp.assert(report_results->0->'retrieval'->'attempts'->0->>'strategy'='firecrawl','report exposes attempted retrieval strategy');
 perform pg_temp.assert(report_results::text not like '%private fetched source%','report omits source body');
 update hosted_quality_jobs set fence=2,lease_token=gen_random_uuid() where id=target;
 perform pg_temp.assert(reserve_hosted_quality_investigation(target,token,1)->>'error'='lease_lost','cached evidence still requires active fence');
end $$;

select pg_temp.assert(not has_table_privilege('authenticated','hosted_quality_evidence','select'),'evidence service-only');
select pg_temp.assert((select relrowsecurity from pg_class where relname='hosted_quality_evidence'),'evidence RLS');
select pg_temp.assert(not has_function_privilege('anon','reserve_hosted_quality_investigation(uuid,uuid,bigint)','execute'),'reservation inaccessible to anonymous');
select pg_temp.assert(has_function_privilege('service_role','reserve_hosted_quality_investigation(uuid,uuid,bigint)','execute'),'service can reserve');
select pg_temp.assert(hosted_quality_investigation_item('{"items":[{"id":"has-body","page_body":"text"},{"id":"missing-body"}]}'::jsonb)->>'id'='missing-body','missing body preferred when quality is unknown');

-- Service-only failure records may retain the input URL for idempotency; email payloads must not.
update hosted_quality_evidence set observation=jsonb_build_object('schema_version',1,
  'item_id','00000000-0000-4000-8000-000000000002','url','https://example.org/partial?access_token=canary-secret-never-email',
  'outcome','unavailable','text','','title','','attempts','[{"strategy":"firecrawl_rendered","outcome":"unavailable","reason":"unsafe_url","duration_ms":0}]'::jsonb);
select pg_temp.assert(hosted_quality_report_results(now()-interval '1 day',now()+interval '1 day')::text not like '%canary-secret-never-email%','unsafe URL secret excluded from report outbox payload');
select pg_temp.assert(hosted_quality_report_results(now()-interval '1 day',now()+interval '1 day')->0->'retrieval'->>'url'='[redacted unsafe URL]','unsafe URL clearly marked redacted');

-- Retry reservation costs survive new leases and never exceed three total provider attempts.
delete from hosted_quality_evidence;
update hosted_quality_jobs set investigation_attempts=2,investigation_started_at=now()-interval '31 seconds',lease_token='33333333-3333-4333-8333-333333333333',fence=3;
select pg_temp.assert((reserve_hosted_quality_investigation('22222222-2222-4222-8222-222222222222','33333333-3333-4333-8333-333333333333',3)->>'ok')::boolean,'third total attempt allowed');
update hosted_quality_jobs set investigation_started_at=now()-interval '31 seconds',fence=4;
select pg_temp.assert(reserve_hosted_quality_investigation('22222222-2222-4222-8222-222222222222','33333333-3333-4333-8333-333333333333',4)->>'error'='retrieval_budget_exhausted','fourth total attempt forbidden');

-- Evidence is erased by the existing item-delete and retention paths through its job FK.
insert into hosted_quality_evidence(job_id,fence,attempt_token,observation) values('22222222-2222-4222-8222-222222222222',4,gen_random_uuid(),'{"schema_version":1,"item_id":"00000000-0000-4000-8000-000000000002","url":"https://example.org/partial","outcome":"retrieved","text":"private"}');
delete from items where id='00000000-0000-4000-8000-000000000002';
select pg_temp.assert(not exists(select from hosted_quality_evidence),'item delete purges evidence');
insert into hosted_quality_jobs(id,kind,dedupe_key,input,input_hash,created_at) values('55555555-5555-4555-8555-555555555555','research','expired','{"items":[]}','test',now()-interval '36 days');
insert into hosted_quality_evidence(job_id,fence,attempt_token,observation) values('55555555-5555-4555-8555-555555555555',1,gen_random_uuid(),'{"schema_version":1,"text":"old source"}');
select prune_hosted_quality_data();
select pg_temp.assert(not exists(select from hosted_quality_evidence),'retention purges evidence');
rollback;
