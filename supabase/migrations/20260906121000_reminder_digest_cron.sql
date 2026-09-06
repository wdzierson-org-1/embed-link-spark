-- Daily reminder job. pg_cron 1.6: cron.schedule(name, …) upserts by name.
-- The shared secret is read from Vault at run time so nothing sensitive is
-- committed (the older retry-pending-scrapes job embeds its token instead).
--
-- pg_cron/pg_net are already enabled in production; these IF NOT EXISTS
-- guards only matter so `supabase db reset` can replay this migration
-- locally without failing on a fresh database.
CREATE EXTENSION IF NOT EXISTS pg_cron;
CREATE EXTENSION IF NOT EXISTS pg_net;

SELECT cron.schedule(
  'reminder-digest',
  '0 13 * * *',
  $$
  SELECT net.http_post(
    url := 'https://uqqsgmwkvslaomzxptnp.supabase.co/functions/v1/reminder-digest',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-cron-secret', (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'cron_secret' LIMIT 1)
    ),
    body := '{}'::jsonb
  );
  $$
);
