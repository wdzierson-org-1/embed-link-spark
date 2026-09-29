-- Hourly dispatch; healthy sources and ready objects are reviewed daily by the worker.
-- Reuses the reminder job's vault secret. Deploy the endpoint before applying this migration.
create extension if not exists pg_cron;
create extension if not exists pg_net;
do $$ declare job record; begin
  for job in select jobid from cron.job where jobname in ('retry-pending-scrapes','enrichment-maintenance') loop
    perform cron.unschedule(job.jobid);
  end loop;
end $$;
select cron.schedule('enrichment-maintenance','17 * * * *',$job$
  select net.http_post(
    url := 'https://uqqsgmwkvslaomzxptnp.supabase.co/functions/v1/enrichment-maintenance',
    headers := jsonb_build_object('Content-Type','application/json','x-cron-secret',
      (select decrypted_secret from vault.decrypted_secrets where name='cron_secret' limit 1)),
    body := '{}'::jsonb, timeout_milliseconds := 180000
  );
$job$);
