-- Rate limiting for the public homepage enrichment demo (edge function `homepage-enrich`).
--
-- The demo is unauthenticated, so every call is admitted here first: per-IP caps (burst and
-- daily) and a global hourly cap that bounds model spend. Only a salted SHA-256 of the
-- caller's IP and a timestamp are kept; rows older than two days are pruned opportunistically.
-- RLS is on with no policies, and the admit function is executable by service_role only.

create table if not exists public.homepage_enrich_hits (
  id bigint generated always as identity primary key,
  ip_hash text not null,
  kind text not null,
  created_at timestamptz not null default now()
);

create index if not exists homepage_enrich_hits_ip_time
  on public.homepage_enrich_hits (ip_hash, created_at desc);
create index if not exists homepage_enrich_hits_time
  on public.homepage_enrich_hits (created_at desc);

alter table public.homepage_enrich_hits enable row level security;

comment on table public.homepage_enrich_hits is
  'Admission log for the public homepage enrichment demo (homepage-enrich): salted IP hash + time only. Service role only.';

-- Returns 'ok' (and records the hit) or the name of the limit that refused it:
-- 'ip' (burst), 'ip_day', or 'global'.
create or replace function public.homepage_enrich_admit(p_ip_hash text, p_kind text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  ip_burst int;
  ip_day int;
  global_hour int;
begin
  select count(*) into ip_burst from homepage_enrich_hits
   where ip_hash = p_ip_hash and created_at > now() - interval '10 minutes';
  if ip_burst >= 15 then return 'ip'; end if;

  select count(*) into ip_day from homepage_enrich_hits
   where ip_hash = p_ip_hash and created_at > now() - interval '1 day';
  if ip_day >= 60 then return 'ip_day'; end if;

  select count(*) into global_hour from homepage_enrich_hits
   where created_at > now() - interval '1 hour';
  if global_hour >= 400 then return 'global'; end if;

  insert into homepage_enrich_hits (ip_hash, kind) values (p_ip_hash, left(p_kind, 16));

  if random() < 0.02 then
    delete from homepage_enrich_hits where created_at < now() - interval '2 days';
  end if;

  return 'ok';
end;
$$;

revoke all on function public.homepage_enrich_admit(text, text) from public, anon, authenticated;
grant execute on function public.homepage_enrich_admit(text, text) to service_role;
