-- Disposable PostgreSQL only; everything rolls back.
begin;
create role anon; create role authenticated; create role service_role;
create schema auth;
create function auth.uid() returns uuid language sql as $$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
create function auth.role() returns text language sql as $$ select current_setting('request.jwt.claim.role',true) $$;
create schema extensions;
create table items(id uuid primary key,user_id uuid,type text,url text,title text,description text,summary text,page_body text,created_at timestamptz default now(),attributes jsonb);
create table enrichment_quality(item_id uuid,status text,reasons text[],evaluated_at timestamptz);
create table enrichment_jobs(item_id uuid primary key,next_run_at timestamptz,revision int default 0,attempts int default 0,provider_state jsonb,last_error text,updated_at timestamptz);
\ir ../../migrations/20261009120000_hosted_quality.sql
\ir ../../migrations/20261010120000_object_facts_and_quality_retry.sql
create function pg_temp.assert(ok boolean,label text) returns void language plpgsql as $$ begin
 if ok is distinct from true then raise exception 'ASSERTION FAILED: %',label; end if; end $$;
insert into items(id,user_id,type,url,attributes) values('00000000-0000-4000-8000-000000000001','11111111-1111-4111-8111-111111111111','link','https://shop.example/jacket','{"custom":{"keep":true},"location":{"name":"capture location"}}');
select set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true),set_config('request.jwt.claim.role','authenticated',true);
do $$ declare f jsonb := '{"version":1,"beta":true,"kind":"product","product":{"brand":"Example"},"evidence":{"source_url":"https://shop.example/jacket","observed_at":"2026-10-10T04:00:00Z","method":"json-ld","extraction_version":"object-facts-v1","schema_type":"Product"}}'; fixture_id uuid := '00000000-0000-4000-8000-000000000001'; begin
 perform pg_temp.assert(not has_function_privilege('anon','set_item_object_facts(uuid,text,jsonb,jsonb)','execute'),'anonymous cannot write facts');
 perform pg_temp.assert(set_item_object_facts(fixture_id,'https://shop.example/jacket','null',f),'owner can save facts');
 perform pg_temp.assert((select attributes @> '{"custom":{"keep":true},"location":{"name":"capture location"}}' from items where items.id=fixture_id),'unrelated attributes preserved');
 perform pg_temp.assert(not set_item_object_facts(fixture_id,'https://shop.example/jacket','null',f),'stale facts cannot overwrite');
 perform pg_temp.assert(not set_item_object_facts(fixture_id,'https://other.example/',f,f),'changed source cannot overwrite');
 perform pg_temp.assert(not set_item_object_facts(fixture_id,'https://shop.example/jacket',f,'{}'),'malformed facts rejected');
 perform pg_temp.assert(not set_item_object_facts(fixture_id,'https://shop.example/jacket',f,null),'null facts rejected');
 perform set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',true);
 perform pg_temp.assert(not set_item_object_facts(fixture_id,'https://shop.example/jacket',f,f),'other owner cannot write');
 perform set_config('request.jwt.claim.role','service_role',true);
 perform pg_temp.assert(set_item_object_facts(fixture_id,'https://shop.example/jacket',f,f),'service can write matching facts');
 update items set attributes=attributes||'{"enrichment":{"protected_fields":{"object_facts":true}}}' where items.id=fixture_id;
 perform pg_temp.assert(not set_item_object_facts(fixture_id,'https://shop.example/jacket',f,f),'field lock preserved');
end $$;
insert into hosted_quality_jobs(kind,dedupe_key,input,input_hash,last_error) values('audit','retry','{"schema_version":1,"items":[]}','hash','quote_not_in_source');
select pg_temp.assert(claim_hosted_quality_job()->>'previous_error'='quote_not_in_source','retry receives closed validation code');
update hosted_quality_jobs set status='queued',last_error='UNTRUSTED INSTRUCTION',available_at=now();
select pg_temp.assert(claim_hosted_quality_job()->'previous_error'='null'::jsonb,'untrusted error string is never forwarded');
rollback;
