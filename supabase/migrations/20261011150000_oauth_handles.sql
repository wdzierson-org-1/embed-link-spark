-- Google and Apple sign-in, phase 1 (docs/superpowers/specs/2026-10-11-google-apple-sign-in-design.md
-- §4.3–4.4, §5.2). Applied to prod through the Management API and recorded in
-- supabase_migrations.schema_migrations by hand (see the plan's Task 2).

-- 1. The handle flag. Existing rows chose theirs, so the default is true; the trigger below sets
--    false only when it had to generate one.
alter table public.user_profiles
  add column if not exists handle_confirmed boolean not null default true;

-- 2. handle_new_user v3. The email forms (web + iOS) send `username` in the metadata → used as-is,
--    confirmed. Anything else (Google, Apple, anonymous) gets a readable handle:
--    anonymous → guest-<8 chars of id>; otherwise full_name → name → the email local part (unless
--    the address is Apple's private relay) → 'stash'; sanitized to [a-z0-9], padded to 3, cut to
--    20, deduped with a numeric suffix. The insert retries on unique_violation so two sign-ups
--    racing for the same base both succeed.
--    A metadata username that fails the handle format is ignored rather than locked in.
--
--    Rollback = the v2 body from 20260821200000_anon_user_profiles.sql:
--      insert into public.user_profiles (id, username, display_name, created_at, updated_at)
--      values (new.id,
--              coalesce(new.raw_user_meta_data->>'username', 'guest-' || substr(new.id::text, 1, 8)),
--              coalesce(new.raw_user_meta_data->>'display_name', split_part(new.email, '@', 1)),
--              new.created_at, now());
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  meta jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
  chosen text := nullif(trim(meta->>'username'), '');
  local_part text := nullif(split_part(coalesce(new.email, ''), '@', 1), '');
  relay boolean := lower(split_part(coalesce(new.email, ''), '@', 2)) = 'privaterelay.appleid.com';
  avatar text := coalesce(meta->>'avatar_url', meta->>'picture');
  base text;
  candidate text;
  display text;
  i integer := 2;
begin
  if chosen is not null and chosen !~ '^[a-z0-9]{3,20}$' then chosen := null; end if;
  if chosen is not null then
    insert into public.user_profiles (id, username, display_name, avatar_url, handle_confirmed, created_at, updated_at)
    values (new.id, chosen,
            coalesce(meta->>'display_name', meta->>'full_name', meta->>'name', local_part, chosen),
            avatar, true, new.created_at, now());
    return new;
  end if;

  if coalesce(new.is_anonymous, false) then
    base := 'guest-' || substr(new.id::text, 1, 8);
  else
    base := regexp_replace(lower(coalesce(nullif(meta->>'full_name', ''), nullif(meta->>'name', ''),
                                          case when relay then null else local_part end, 'stash')),
                           '[^a-z0-9]', '', 'g');
    if length(base) < 3 then
      base := base || substr(regexp_replace(new.id::text, '[^0-9]', '', 'g') || '000', 1, 3 - length(base));
    end if;
    base := left(base, 20);
  end if;

  -- A display name from the metadata or the email; when there is none, the handle itself (the
  -- final candidate, suffix included), so a relay-address Apple sign-up reads "stash2" not "stash".
  display := coalesce(meta->>'display_name', meta->>'full_name', meta->>'name',
                      case when relay then null else local_part end);
  candidate := base;
  loop
    begin
      insert into public.user_profiles (id, username, display_name, avatar_url, handle_confirmed, created_at, updated_at)
      values (new.id, candidate, coalesce(display, candidate), avatar, false, new.created_at, now());
      return new;
    exception when unique_violation then
      if i > 50 then
        candidate := left(base, 15) || substr(md5(new.id::text || i::text), 1, 5);
      else
        candidate := left(base, 20 - length(i::text)) || i::text;
      end if;
      i := i + 1;
      if i > 60 then raise; end if;
    end;
  end loop;
end;
$$;

-- 3. Immutability, server-side: once confirmed, a handle never changes, and the flag never goes
--    back to false. A handle that does change (the confirm step) must be 3–20 [a-z0-9].
create or replace function public.user_profiles_lock_handle()
returns trigger
language plpgsql
as $$
begin
  if new.username is distinct from old.username then
    if old.handle_confirmed then
      raise exception 'username is immutable once confirmed' using errcode = 'check_violation';
    end if;
    if new.username !~ '^[a-z0-9]{3,20}$' then
      raise exception 'username must be 3-20 lowercase letters or digits' using errcode = 'check_violation';
    end if;
  end if;
  if old.handle_confirmed and not new.handle_confirmed then
    raise exception 'handle_confirmed cannot be unset' using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

drop trigger if exists user_profiles_lock_handle on public.user_profiles;
create trigger user_profiles_lock_handle
  before update of username, handle_confirmed on public.user_profiles
  for each row execute function public.user_profiles_lock_handle();

-- 4. Apple refresh tokens, kept only so account deletion can revoke them (spec §5.3). Service
--    role only: RLS on with no policies, and the API roles' default grants revoked.
create table if not exists public.apple_sign_in_tokens (
  user_id uuid not null references auth.users(id) on delete cascade,
  client_id text not null,
  refresh_token text not null,
  created_at timestamptz not null default now(),
  primary key (user_id, client_id)
);
alter table public.apple_sign_in_tokens enable row level security;
revoke all on public.apple_sign_in_tokens from anon, authenticated;
