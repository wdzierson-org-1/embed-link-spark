-- Apple revocations: an exhausted row keeps its token so recovery is possible (2026-10-12, Codex review).
--
-- 20261012210000 nulled the refresh token the moment a row left `pending`, which made the
-- "revoke manually" instruction on exhausted rows impossible to follow. Now `exhausted` rows keep
-- the token for a bounded time (apple-revocation-sweep purges them after 90 days and logs the
-- failure as irrevocable); an operator recovers one by re-queueing it after fixing the cause:
--
--   update public.apple_revocations
--      set status = 'pending', attempts = 0, next_attempt_at = now(), last_error = null
--    where status = 'exhausted' and user_id = '<user id>' and client_id = '<audience>';
--
-- `revoked` and `invalid` rows still never carry a token. Service role only, as before.
alter table public.apple_revocations
  drop constraint if exists apple_revocations_token_only_while_pending;
alter table public.apple_revocations
  add constraint apple_revocations_token_only_while_recoverable
  check (status in ('pending', 'exhausted') or refresh_token is null);
