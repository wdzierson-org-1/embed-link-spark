-- Sign in with Apple revocation that survives account deletion (AS-APPLE-REVOCATION, 2026-10-12).
--
-- delete-account used to read apple_sign_in_tokens, ask Apple once, count failures and delete the
-- auth user anyway; the token row cascaded away with the user, so a transient Apple failure (or a
-- stalled read) lost the only material that could ever revoke the grant. Now every stored token is
-- copied here as `pending` BEFORE Apple is asked and before the user is deleted. There is NO foreign
-- key to auth.users on purpose: the row must outlive the account so apple-revocation-sweep can
-- retry. Service role only: RLS on with no policies, API-role grants revoked.
--
-- Lifecycle: pending → revoked | invalid (Apple: invalid_grant, terminal) | exhausted (20 retries).
-- The refresh token is nulled the moment a row leaves `pending` (enforced below); non-pending rows
-- are purged after 30 days by the sweep.
create table if not exists public.apple_revocations (
  user_id uuid not null,
  client_id text not null,
  refresh_token text,
  status text not null default 'pending' check (status in ('pending', 'revoked', 'invalid', 'exhausted')),
  attempts integer not null default 0,
  last_error text,
  next_attempt_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  revoked_at timestamptz,
  primary key (user_id, client_id),
  constraint apple_revocations_token_only_while_pending check (status = 'pending' or refresh_token is null)
);
create index if not exists apple_revocations_due on public.apple_revocations (next_attempt_at) where status = 'pending';
alter table public.apple_revocations enable row level security;
revoke all on public.apple_revocations from anon, authenticated;

-- Retry sweep every 15 minutes; pg_cron 1.6 upserts by job name. Reuses the reminder job's vault
-- secret. Deploy apple-revocation-sweep BEFORE applying this migration.
create extension if not exists pg_cron;
create extension if not exists pg_net;
select cron.schedule('apple-revocation-sweep', '*/15 * * * *', $job$
  select net.http_post(
    url := 'https://uqqsgmwkvslaomzxptnp.supabase.co/functions/v1/apple-revocation-sweep',
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-cron-secret',
      (select decrypted_secret from vault.decrypted_secrets where name = 'cron_secret' limit 1)),
    body := '{}'::jsonb, timeout_milliseconds := 120000
  );
$job$);
