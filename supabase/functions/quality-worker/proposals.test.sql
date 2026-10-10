-- Disposable PostgreSQL only. All schema, fixtures and changes roll back.
begin;
create role anon; create role authenticated; create role service_role;
create schema extensions;
create table items(id uuid primary key,user_id uuid,type text,url text,title text,description text,summary text,page_body text,created_at timestamptz default now());
create table admin_users(user_id uuid primary key);
create table enrichment_quality(item_id uuid,status text,reasons text[],evaluated_at timestamptz);
create table enrichment_attempts(item_id uuid,strategy text,outcome text,reasons text[],elapsed_ms integer,cost_usd numeric,created_at timestamptz);
\ir ../../migrations/20261009120000_hosted_quality.sql
\ir ../../migrations/20261009130000_hosted_quality_delivery_receipts.sql
\ir ../../migrations/20261009150000_hosted_quality_live_evidence.sql
\ir ../../migrations/20261009160000_hosted_quality_fleet.sql
create function pg_temp.assert(ok boolean,label text) returns void language plpgsql as $$ begin
 if ok is distinct from true then raise exception 'ASSERTION FAILED: %',label; end if; end $$;
insert into admin_users values('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
insert into items(id,user_id,type,url,title,page_body,created_at) values
 ('00000000-0000-4000-8000-000000000001','11111111-1111-4111-8111-111111111111','link','https://example.org/story','Story','PRIVATE BODY',now()-interval '1 hour'),
 ('00000000-0000-4000-8000-000000000002','22222222-2222-4222-8222-222222222222','link','https://example.org/other','Other','OTHER BODY',now()-interval '2 hours'),
 ('00000000-0000-4000-8000-000000000003','11111111-1111-4111-8111-111111111111','link','https://example.org/private?token=secret','Private URL','SECRET BODY',now()-interval '3 hours'),
 ('00000000-0000-4000-8000-000000000004','11111111-1111-4111-8111-111111111111','text',null,'Note title','PRIVATE NOTE',now()-interval '4 hours'),
 ('00000000-0000-4000-8000-000000000005','11111111-1111-4111-8111-111111111111','link','https://example.org/old','Older story','OLDER BODY',now()-interval '3 days');
insert into enrichment_quality values
 ('00000000-0000-4000-8000-000000000001','partial',array['missing_preview'],now()),
 ('00000000-0000-4000-8000-000000000002','ready','{}',now()),
 ('00000000-0000-4000-8000-000000000003','blocked',array['access_wall'],now()),
 ('00000000-0000-4000-8000-000000000005','partial',array['missing_preview'],now());
insert into enrichment_attempts select '00000000-0000-4000-8000-000000000001','jina_reader','failed',array['access_wall'],n*10,null,now()-make_interval(mins=>n) from generate_series(1,8) n;
insert into hosted_quality_jobs(id,kind,dedupe_key,input,input_hash,status,completed_at,created_at,last_error) values
 ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','research','legacy-proposal',jsonb_build_object('items',jsonb_build_array(jsonb_build_object('id','00000000-0000-4000-8000-000000000001','url','https://example.org/story'))),'hash','completed',now(),now()-interval '5 minutes','quote_not_in_source');
insert into hosted_quality_results(job_id,fence,lease_token,result,payload_hash) values
 ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',1,gen_random_uuid(),'{"schema_version":1,"proposals":[{"title":"Try source artwork","rationale":"A hypothesis needing a labelled image comparison.","evidence_urls":["https://example.org/story"]}]}','hash');

-- The migration belongs here after the pre-existing result: this tests backfill.
\ir ../../migrations/20261010160000_hosted_quality_proposals.sql
select pg_temp.assert(to_regclass('public.hosted_quality_proposals') is not null,'proposal ledger exists');
select pg_temp.assert((select count(*)=1 from hosted_quality_proposals),'retained proposals backfilled once');
select pg_temp.assert(not has_table_privilege('authenticated','hosted_quality_proposals','select') and not has_table_privilege('anon','hosted_quality_proposal_reviews','insert'),'clients cannot directly access ledger or history');
select pg_temp.assert(not has_function_privilege('authenticated','admin_enrichment_quality(uuid,integer,text,integer)','execute') and not has_function_privilege('anon','review_hosted_quality_proposal(uuid,uuid,bigint,text,text,uuid)','execute'),'RPCs service only');

do $$ declare p hosted_quality_proposals; r jsonb; view jsonb; request uuid:=gen_random_uuid(); begin
 select * into p from hosted_quality_proposals;
 perform pg_temp.assert(p.status='new' and p.revision=0 and p.source_item_ids=array['00000000-0000-4000-8000-000000000001'::uuid],'new proposal source identity and version');
 begin
  perform admin_enrichment_quality('99999999-9999-4999-8999-999999999999');
  raise exception 'Nonadmin read was allowed';
 exception when insufficient_privilege then null; end;
 begin
  perform review_hosted_quality_proposal('99999999-9999-4999-8999-999999999999',p.id,0,'planned','Unauthorized',request);
  raise exception 'Nonadmin review was allowed';
 exception when insufficient_privilege then null; end;
 begin
  perform admin_enrichment_quality('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',25);
  raise exception 'Unbounded window allowed';
 exception when invalid_parameter_value then null; end;
 begin
  perform review_hosted_quality_proposal('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',p.id,0,'deployed','Cannot promote',request);
  raise exception 'Automatic promotion state allowed';
 exception when invalid_parameter_value then null; end;
 begin
  perform review_hosted_quality_proposal('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',p.id,0,'planned',' ',request);
  raise exception 'Empty decision reason allowed';
 exception when invalid_parameter_value then null; end;
 r:=review_hosted_quality_proposal('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',p.id,0,'needs_evidence','  Need an independently labelled example.  ',request);
 perform pg_temp.assert(r->>'ok'='true' and r->>'status'='needs_evidence' and r->>'revision'='1' and r->>'idempotent'='false','review records decision and increments version');
 perform pg_temp.assert((select count(*)=1 and min(note)='Need an independently labelled example.' from hosted_quality_proposal_reviews),'review history captures trimmed decision');
 r:=review_hosted_quality_proposal('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',p.id,0,'needs_evidence','Need an independently labelled example.',request);
 perform pg_temp.assert(r->>'ok'='true' and r->>'idempotent'='true' and (select count(*)=1 from hosted_quality_proposal_reviews),'same request idempotent after revision changed');
 r:=review_hosted_quality_proposal('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',p.id,0,'planned','Different payload',request);
 perform pg_temp.assert(r->>'error'='request_conflict','reused request cannot change a decision');
 r:=review_hosted_quality_proposal('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',p.id,0,'planned','Stale tab',gen_random_uuid());
 perform pg_temp.assert(r->>'error'='version_conflict' and r->>'revision'='1','stale reviewer does not overwrite a decision');
 perform review_hosted_quality_proposal('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',p.id,1,'planned','Repro case documented.',gen_random_uuid());
 perform review_hosted_quality_proposal('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',p.id,2,'planned','Add a test before implementation.',gen_random_uuid());
 perform review_hosted_quality_proposal('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',p.id,3,'dismissed','Evidence did not support the proposed change.',gen_random_uuid());
 view:=admin_enrichment_quality('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',24);
 perform pg_temp.assert(view->'pipeline'->>'saved_items'='4' and view->'pipeline'->>'unassessed'='1','cohort denominators include unassessed without counting success');
 perform pg_temp.assert((select sum((d->>'saved_items')::int)=4 from jsonb_array_elements(view->'daily') d),'daily New York cohorts partition current window');
 perform pg_temp.assert(jsonb_array_length(view->'proposals')=1 and jsonb_array_length(view->'proposals'->0->'reviews')=3 and view->'proposal_counts'->>'dismissed'='1','dashboard state and three newest reviews');
 perform pg_temp.assert(jsonb_array_length(view->'incomplete_items')=3,'partial blocked and unassessed cohort only');
 perform pg_temp.assert((select jsonb_array_length(i->'attempts')=5 from jsonb_array_elements(view->'incomplete_items') i where i->>'item_id'='00000000-0000-4000-8000-000000000001'),'only five latest strategy attempts');
 perform pg_temp.assert((select i->'url'='null'::jsonb and i->'source'='null'::jsonb from jsonb_array_elements(view->'incomplete_items') i where i->>'item_id'='00000000-0000-4000-8000-000000000003'),'unsafe URL and host redacted');
 perform pg_temp.assert(view::text !~ 'PRIVATE BODY|OTHER BODY|PRIVATE NOTE|SECRET BODY|token=secret','dashboard excludes source body and secret URLs');
 perform pg_temp.assert(view->'jobs'->>'completed'='1' and view->'delivery'='null'::jsonb,'job totals and honest absent email status');
 perform pg_temp.assert(view->'jobs'->'error_counts'='[]'::jsonb,'recovered job retry errors are not terminal failures');
 perform pg_temp.assert(jsonb_array_length(admin_enrichment_quality('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',24,'new')->'proposals')=0,'status filtering');
 perform pg_temp.assert(admin_enrichment_quality('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',168)->'pipeline'->>'saved_items'='5','seven-day cohort');
end $$;

-- Failed jobs expose only reason codes, and delivery status never exposes provider credentials or recipient.
insert into hosted_quality_jobs(kind,dedupe_key,input,input_hash,status,created_at,last_error) values
 ('audit','failed-code','{}','hash','failed',now()-interval '10 minutes','quote_not_in_source'),
 ('audit','failed-private','{}','hash','failed',now()-interval '10 minutes','PRIVATE ERROR https://example.org/?token=secret');
insert into hosted_quality_reports(id,recipient,report_day,payload) values('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee','PRIVATE-RECIPIENT@example.org',current_date-1,
 '{"results":[{"item_ids":["00000000-0000-4000-8000-000000000001"]}]}');
insert into hosted_quality_outbox(report_id,idempotency_key,status,accepted_at,provider_id) values('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee','test-key','accepted',now(),'PRIVATE-PROVIDER-ID');
insert into hosted_quality_delivery_receipts(recipient,report_day,version,idempotency_key,accepted_at) values('private-recipient@example.org',current_date-1,'hosted-v1','test-key',now());
do $$ declare view jsonb; begin
 view:=admin_enrichment_quality('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',24);
 perform pg_temp.assert(view->'jobs'->'error_counts' @> '[{"reason":"quote_not_in_source","count":1},{"reason":"other_error","count":1}]','only terminal failures count and free text is redacted');
 perform pg_temp.assert(view->'delivery'->>'status'='accepted' and view->'delivery'->>'accepted_at' is not null,'provider acceptance displayed');
 perform pg_temp.assert(view::text !~ 'PRIVATE ERROR|PRIVATE-RECIPIENT|PRIVATE-PROVIDER-ID|token=secret','private operational fields stay out of dashboard');
end $$;

-- An accepted result projects its proposals in the same transaction, with no worker schema change.
insert into hosted_quality_jobs(id,kind,dedupe_key,input,input_hash,status,lease_token,fence,lease_expires_at,deadline_at) values
 ('cccccccc-cccc-4ccc-8ccc-cccccccccccc','audit','new-proposal',jsonb_build_object('items',jsonb_build_array(jsonb_build_object('id','00000000-0000-4000-8000-000000000002','url','https://example.org/other'))),'hash','running','dddddddd-dddd-4ddd-8ddd-dddddddddddd',1,now()+interval '1 minute',now()+interval '90 seconds');
select complete_hosted_quality_job('cccccccc-cccc-4ccc-8ccc-cccccccccccc','dddddddd-dddd-4ddd-8ddd-dddddddddddd',1,'{"schema_version":1,"proposals":[{"title":"Another hypothesis","rationale":"Try exact source evidence first.","evidence_urls":["https://example.org/other"]}]}');
select complete_hosted_quality_job('cccccccc-cccc-4ccc-8ccc-cccccccccccc','dddddddd-dddd-4ddd-8ddd-dddddddddddd',1,'{"schema_version":1,"proposals":[{"title":"Another hypothesis","rationale":"Try exact source evidence first.","evidence_urls":["https://example.org/other"]}]}');
select pg_temp.assert((select count(*)=2 from hosted_quality_proposals),'idempotent completion creates one proposal per position');

-- Exact item URLs alone do not make arbitrary historical JSON safe to display.
savepoint intake_bounds;
insert into hosted_quality_jobs(id,kind,dedupe_key,input,input_hash) values
 ('ffffffff-ffff-4fff-8fff-ffffffffffff','audit','malformed-proposals',jsonb_build_object('items',jsonb_build_array(jsonb_build_object('id','00000000-0000-4000-8000-000000000002','url','https://example.org/other'))),'hash');
insert into hosted_quality_results(job_id,fence,lease_token,result,payload_hash) values
 ('ffffffff-ffff-4fff-8fff-ffffffffffff',1,gen_random_uuid(),'{"schema_version":1,"proposals":[{"title":"Wrong source","rationale":"Not in this snapshot","evidence_urls":["https://elsewhere.example/wrong"]},{"title":"Missing rationale","evidence_urls":["https://example.org/other"]},{"title":"Wrong URL shape","rationale":"Not an array","evidence_urls":"https://example.org/other"},null]}','hash');
select pg_temp.assert((select count(*)=2 from hosted_quality_proposals),'invalid historical proposals never enter the ledger');
do $$ declare snapshot jsonb; job uuid; begin
 foreach snapshot in array array['{"items":null}'::jsonb,'{"items":{}}'::jsonb,'{"items":"invalid"}'::jsonb] loop
  job:=gen_random_uuid();
  insert into hosted_quality_jobs(id,kind,dedupe_key,input,input_hash) values(job,'audit',job::text,snapshot,'hash');
  insert into hosted_quality_results(job_id,fence,lease_token,result,payload_hash) values(job,1,gen_random_uuid(),
   '{"schema_version":1,"proposals":[{"title":"Malformed snapshot","rationale":"This cannot establish item scope.","evidence_urls":["https://example.org/other"]}]}','hash');
 end loop;
 perform pg_temp.assert((select count(*)=2 from hosted_quality_proposals),'malformed historical item arrays do not abort completion or enter ledger');
end $$;
insert into hosted_quality_jobs(id,kind,dedupe_key,input,input_hash)
 select ('00000000-1111-4000-8000-'||lpad(n::text,12,'0'))::uuid,'audit','bounded-'||n,
 jsonb_build_object('items',jsonb_build_array(jsonb_build_object('id','00000000-0000-4000-8000-000000000002','url','https://example.org/other'))),'hash' from generate_series(1,55) n;
insert into hosted_quality_results(job_id,fence,lease_token,result,payload_hash)
 select id,1,gen_random_uuid(),'{"schema_version":1,"proposals":[{"title":"Bounded hypothesis","rationale":"Waiting for independent review.","evidence_urls":["https://example.org/other"]}]}','hash'
 from hosted_quality_jobs where dedupe_key like 'bounded-%';
select pg_temp.assert(jsonb_array_length(admin_enrichment_quality('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa')->'proposals')=50,'dashboard proposal payload bounded even when backlog grows');
select pg_temp.assert(jsonb_array_length(admin_enrichment_quality('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',24,null,2)->'proposals')=2,'caller can request smaller proposal page');
rollback to intake_bounds;

delete from items where id='00000000-0000-4000-8000-000000000001';
select pg_temp.assert((select count(*)=1 from hosted_quality_proposals) and not exists(select 1 from hosted_quality_proposal_reviews),'source deletion cascades proposal text and all review notes');
select pg_temp.assert(admin_enrichment_quality('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa')->'delivery'->>'status'='accepted','provider acceptance receipt remains visible after source report purge');
insert into hosted_quality_delivery_receipts(recipient,report_day,version,idempotency_key) values('private-recipient@example.org',current_date,'hosted-v1','uncertain-key');
select pg_temp.assert(admin_enrichment_quality('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa')->'delivery'->>'status'='uncertain','a newer receipt without provider acceptance stays uncertain');
update hosted_quality_jobs set created_at=now()-interval '36 days' where id='cccccccc-cccc-4ccc-8ccc-cccccccccccc';
select prune_hosted_quality_data();
select pg_temp.assert(not exists(select 1 from hosted_quality_proposals),'35-day retention cascades proposal ledger');
select 'hosted quality proposal SQL assertions passed' as result;
rollback;
