import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.50.2';

// Daily job (pg_cron 13:00 UTC → pg_net → here). Two steps:
//  1. hygiene: materialise reminder_cleared_at for reminders past their 24h window
//  2. digest:  email each user their due reminders (Plan 3; skipped until
//              RESEND_API_KEY exists)
// Auth is a shared secret, not a JWT: the caller is Postgres, not a person.

const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } });

serve(async (req) => {
  const expected = Deno.env.get('CRON_SECRET');
  if (!expected || req.headers.get('x-cron-secret') !== expected) {
    return json(401, { error: 'unauthorized' });
  }
  const url = new URL(req.url);
  const dryRun = url.searchParams.get('dry_run') === '1';

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  );

  let expired = 0;
  if (dryRun) {
    const cutoff = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();
    const { count, error } = await supabase
      .from('items')
      .select('id', { count: 'exact', head: true })
      .not('remind_at', 'is', null)
      .is('reminder_cleared_at', null)
      .lte('remind_at', cutoff);
    if (error) return json(500, { error: error.message });
    expired = count ?? 0;
  } else {
    const { data, error } = await supabase.rpc('reminders_expire');
    if (error) return json(500, { error: error.message });
    expired = typeof data === 'number' ? data : 0;
  }

  const digest = Deno.env.get('RESEND_API_KEY')
    ? { status: 'skipped', reason: 'digest step lands in plan 3' }
    : { status: 'skipped', reason: 'RESEND_API_KEY unset' };

  console.log('reminder-digest', { dryRun, expired, digest });
  return json(200, { expired, digest });
});
