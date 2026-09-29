-- Transcription sweep (spec docs/superpowers/specs/2026-09-09-long-audio-transcription-design.md).
-- Every 10 minutes, transcribe-audio { sweep: true } resumes or retries audio/
-- video items whose transcript job is pending, stalled, or failed (attempts < 3)
-- — the safety net behind the fire-and-forget job that capture starts.
-- Same shape as reminder-digest: the shared secret comes from Vault at run time.
CREATE EXTENSION IF NOT EXISTS pg_cron;
CREATE EXTENSION IF NOT EXISTS pg_net;

SELECT cron.schedule(
  'transcribe-audio-sweep',
  '*/10 * * * *',
  $$
  SELECT net.http_post(
    url := 'https://uqqsgmwkvslaomzxptnp.supabase.co/functions/v1/transcribe-audio',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-cron-secret', (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'cron_secret' LIMIT 1)
    ),
    body := '{"sweep":true}'::jsonb
  );
  $$
);
