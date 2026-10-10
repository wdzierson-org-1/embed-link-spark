-- Publisher facts are additive, owner-scoped, and compared before writing.
create function public.set_item_object_facts(target_id uuid, expected_url text, expected_facts jsonb, facts jsonb) returns boolean
language plpgsql security definer set search_path=public as $$
declare current_item public.items;
begin
  if jsonb_typeof(facts) is distinct from 'object' or octet_length(facts::text)>16000
    or facts->'version' is distinct from '1'::jsonb or facts->'beta' is distinct from 'true'::jsonb
    or coalesce(facts->>'kind','') not in ('product','place')
    or jsonb_typeof(facts->'evidence') is distinct from 'object'
    or facts#>>'{evidence,source_url}' is distinct from expected_url
    or facts#>>'{evidence,method}' is distinct from 'json-ld'
    or facts#>>'{evidence,extraction_version}' is distinct from 'object-facts-v1'
    or coalesce(facts#>>'{evidence,observed_at}','') !~ '^\d{4}-\d{2}-\d{2}T'
    or jsonb_typeof(facts->(facts->>'kind')) is distinct from 'object' then return false; end if;
  select * into current_item from public.items where id=target_id
    and (user_id=auth.uid() or auth.role()='service_role') for update;
  if not found or current_item.type<>'link' or current_item.url is distinct from expected_url
    or current_item.attributes#>'{enrichment,protected_fields,object_facts}'='true'::jsonb
    or coalesce(current_item.attributes->'object_facts','null'::jsonb) is distinct from coalesce(expected_facts,'null'::jsonb)
    then return false; end if;
  update public.items set attributes=jsonb_set(coalesce(attributes,'{}'::jsonb),'{object_facts}',facts,true) where id=target_id;
  -- Refresh searchable evidence even when no title/body changes were necessary.
  insert into public.enrichment_jobs(item_id,next_run_at) values(target_id,now()+interval '2 minutes')
  on conflict(item_id) do update set next_run_at=now()+interval '2 minutes',revision=enrichment_jobs.revision+1,
    attempts=0,provider_state='{}',last_error=null,updated_at=now();
  return true;
end $$;
revoke all on function public.set_item_object_facts(uuid,text,jsonb,jsonb) from public,anon;
grant execute on function public.set_item_object_facts(uuid,text,jsonb,jsonb) to authenticated,service_role;

-- Only known validator codes become model retry instructions, never arbitrary error text.
create or replace function public.claim_hosted_quality_job() returns jsonb
language plpgsql security definer set search_path=public as $$
declare j hosted_quality_jobs;
begin
  update hosted_quality_jobs set status='failed',last_error='lease_expired_after_max_attempts'
    where status='running' and (lease_expires_at<=now() or deadline_at<=now()) and attempts>=3;
  select * into j from hosted_quality_jobs
    where attempts<3 and ((status='queued' and available_at<=now()) or
      (status='running' and (lease_expires_at<=now() or deadline_at<=now()) and available_at<=now()))
    order by created_at,id for update skip locked limit 1;
  if not found then return null; end if;
  update hosted_quality_jobs set status='running',attempts=attempts+1,fence=fence+1,lease_token=gen_random_uuid(),
    lease_expires_at=now()+interval '60 seconds',deadline_at=now()+interval '90 seconds',model_calls=0
    where id=j.id returning * into j;
  return jsonb_build_object('id',j.id,'kind',j.kind,'input',j.input,'input_hash',j.input_hash,
    'lease_token',j.lease_token,'fence',j.fence,'lease_expires_at',j.lease_expires_at,'deadline_at',j.deadline_at,
    'previous_error',case when j.last_error in ('invalid_fields','evidence_required','quote_not_in_source','evidence_out_of_scope','invalid_result','invalid_json') then j.last_error else null end,
    'budget',jsonb_build_object('max_turns',6,'run_seconds',90));
end $$;

