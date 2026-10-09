-- Disposable PostgreSQL only. All schema and fixtures roll back.
begin;
create role anon; create role authenticated; create role service_role;
create schema extensions;
create table items(id uuid primary key,user_id uuid,type text,url text,title text,description text,summary text,page_body text,created_at timestamptz default now());
create table enrichment_quality(item_id uuid,status text,reasons text[],evaluated_at timestamptz);
create table enrichment_attempts(item_id uuid,strategy text,outcome text,reasons text[],elapsed_ms integer,cost_usd numeric,created_at timestamptz);
\ir ../../migrations/20261009120000_hosted_quality.sql
\ir ../../migrations/20261009130000_hosted_quality_delivery_receipts.sql
\ir ../../migrations/20261009150000_hosted_quality_live_evidence.sql
\ir ../../migrations/20261009160000_hosted_quality_fleet.sql
create function pg_temp.assert(ok boolean,label text) returns void language plpgsql as $$ begin
 if ok is distinct from true then raise exception 'ASSERTION FAILED: %',label; end if; end $$;
insert into items(id,user_id,type,url,title,page_body,created_at)
select ('00000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,
 case when n<=6 then '11111111-1111-4111-8111-111111111111'::uuid else '22222222-2222-4222-8222-222222222222'::uuid end,
 'link','https://example.org/story-'||n,'Story '||n,'Grounded source text',
 now()-case when n in (3,9) then interval '2 days' else interval '10 minutes' end from generate_series(1,12) n;
insert into items values('00000000-0000-4000-8000-000000000013','11111111-1111-4111-8111-111111111111','text',null,'Private note',null,null,null,now());
insert into items values('00000000-0000-4000-8000-000000000014','11111111-1111-4111-8111-111111111111','link','https://example.org/private?token=secret','Secret link',null,null,null,now());
insert into enrichment_quality select id,case when right(id::text,2)='01' then 'ready' when right(id::text,2)='02' then 'blocked' else 'partial' end,'{}',now() from items where right(id::text,2) in ('01','02','03','07','09');
insert into enrichment_attempts select id,'jina_reader','failed','{}',120,null,now() from items where right(id::text,2)='02';
insert into enrichment_attempts select id,'jina_reader','improved','{}',80,0.01,now() from items where right(id::text,2)='01';
select pg_temp.assert(not has_function_privilege('authenticated','enqueue_hosted_quality_jobs_all_users(boolean,uuid[])','execute'),'fleet enqueue service only');
select pg_temp.assert(not has_function_privilege('anon','hosted_quality_pipeline_metrics(timestamptz,timestamptz)','execute'),'metrics service only');
select pg_temp.assert(not hosted_quality_url_eligible('https://example.org/story?secret=canary') and not hosted_quality_url_eligible('https://example.org/story?session=canary') and not hosted_quality_url_eligible('https://example.org/story#access_token=canary') and not hosted_quality_url_eligible('https://example.org/story?%74oken=canary'),'credential variants never sampled');
select pg_temp.assert(not hosted_quality_valid_attempts('[{"strategy":"invented","outcome":"retrieved","reason":"x","duration_ms":1}]') and not hosted_quality_valid_attempts('[]') and not hosted_quality_valid_attempts('[{"strategy":"jina_reader","outcome":"retrieved","reason":"x","duration_ms":-1}]'),'attempt bounds and codes validated');
select pg_temp.assert(hosted_quality_valid_attempts('[{"strategy":"firecrawl_rendered","outcome":"blocked","reason":"access_wall","duration_ms":1},{"strategy":"jina_reader","outcome":"retrieved","reason":"reader_source","duration_ms":2}]'),'valid bounded escalation accepted');
select enqueue_hosted_quality_jobs_all_users(true,array['11111111-1111-4111-8111-111111111111'::uuid]);
select pg_temp.assert((select count(*)=2 from hosted_quality_jobs),'one hourly audit and daily research');
select pg_temp.assert((select bool_and(jsonb_array_length(input->'items')=3) from hosted_quality_jobs),'bounded three item jobs');
select pg_temp.assert((select count(distinct i.user_id)=1 from hosted_quality_jobs j cross join lateral jsonb_array_elements(j.input->'items') s join items i on i.id::text=s->>'id'),'each job contains one account');
select pg_temp.assert(not exists(select 1 from hosted_quality_jobs where input::text like '%token=secret%' or input::text like '%Private note%'),'excluded notes and credential-bearing URLs');
select enqueue_hosted_quality_jobs_all_users(true,'{}');
select pg_temp.assert((select count(*)=2 from hosted_quality_jobs),'same hour/day idempotent');
-- Simulate a later hour without waiting or altering the database clock.
update hosted_quality_jobs set dedupe_key='previous:'||dedupe_key;
select enqueue_hosted_quality_jobs_all_users(false,'{}');
select pg_temp.assert((select count(distinct i.user_id)=2 from hosted_quality_jobs j cross join lateral jsonb_array_elements(j.input->'items') s join items i on i.id::text=s->>'id'),'next audit rotates account');
update hosted_quality_jobs set dedupe_key='previous:'||dedupe_key;
select enqueue_hosted_quality_jobs_all_users(false,'{}');
select pg_temp.assert((select count(distinct s->>'id')>6 from hosted_quality_jobs j cross join lateral jsonb_array_elements(j.input->'items') s),'later review rotates items rather than repeating the same three');
do $$ declare m jsonb; begin
 m:=hosted_quality_pipeline_metrics(now()-interval '1 hour',now()+interval '1 hour');
 perform pg_temp.assert((m->>'saved_items')::int=12,'all object saves in window, not only samples');
 perform pg_temp.assert((m->>'assessed')::int=3 and (m->>'ready')::int=1 and (m->>'partial')::int=1 and (m->>'blocked')::int=1 and (m->>'unassessed')::int=9,'honest status denominators');
 perform pg_temp.assert(m->'strategies' @> '[{"strategy":"jina_reader","attempts":2,"failed":1,"improved":1,"avg_ms":100,"cost_known":1,"cost_usd":0.01}]','strategy attempts and partial cost coverage');
end $$;
-- Fleet report hides model free text/URLs from accounts without detail permission.
insert into hosted_quality_results(job_id,fence,lease_token,result,payload_hash)
select id,1,gen_random_uuid(),jsonb_build_object('schema_version',1,'summary','PRIVATE SUMMARY',
 'findings',jsonb_build_array(jsonb_build_object('category','identity','severity','warning','claim','PRIVATE CLAIM','item_id',input->'items'->0->>'id','evidence',jsonb_build_array(jsonb_build_object('url','https://private.example/saved')))),
 'proposals',jsonb_build_array(jsonb_build_object('title','PRIVATE PROPOSAL'))),'test' from hosted_quality_jobs;
select pg_temp.assert(not exists(select 1 from jsonb_array_elements(hosted_quality_report_results(now()-interval '1 hour',now()+interval '1 hour')) r where r->>'redacted'='true' and r::text ~ 'PRIVATE|private.example'),'non-allowlisted private details absent');
select pg_temp.assert(exists(select 1 from jsonb_array_elements(hosted_quality_report_results(now()-interval '1 hour',now()+interval '1 hour')) r where r->>'redacted'='true' and r->'finding_counts' @> '[{"category":"identity","severity":"warning","count":1}]'),'redacted fleet categories preserved');
insert into hosted_quality_reports(recipient,report_day,payload) values('owner@example.org',current_date,
 jsonb_build_object('results',hosted_quality_report_results(now()-interval '1 hour',now()+interval '1 hour')));
delete from items where id=(select (input->'items'->0->>'id')::uuid from hosted_quality_jobs where input->>'report_detail_allowed'='false' limit 1);
select pg_temp.assert(not exists(select 1 from hosted_quality_reports where recipient='owner@example.org'),'deleting item also purges redacted report and findings');
rollback;
