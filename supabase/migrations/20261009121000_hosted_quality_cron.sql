-- Only audit/research enqueue and outbox delivery. Existing :17 repair ownership is unchanged.
-- Deploy quality-dispatch first. QUALITY_ENABLED defaults false until pilot scope/secrets are configured.
create extension if not exists pg_cron;
create extension if not exists pg_net;
select cron.schedule('hosted-quality-dispatch','*/5 * * * *',$job$
  select net.http_post(
    url := 'https://uqqsgmwkvslaomzxptnp.supabase.co/functions/v1/quality-dispatch',
    headers := jsonb_build_object('Content-Type','application/json','x-cron-secret',
      (select decrypted_secret from vault.decrypted_secrets where name='cron_secret' limit 1)),
    body := '{}'::jsonb, timeout_milliseconds := 120000
  );
$job$);
