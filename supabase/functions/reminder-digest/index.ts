import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.50.2';
import { renderReminderDigest, type DigestItem } from '../_shared/reminderDigest.ts';
import { signEmailLinkToken } from '../_shared/emailLinkToken.ts';

// Daily job (pg_cron 13:00 UTC → pg_net → here). Two steps:
//  1. hygiene: materialise reminder_cleared_at for reminders past their 24h window
//  2. digest:  email each user their due reminders via Resend, idempotent via
//              reminder_notified_at
// Auth is a shared secret, not a JWT: the caller is Postgres, not a person.

const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } });

const DUE_WINDOW_MS = 24 * 60 * 60 * 1000;
const UNSUB_TTL_MS = 30 * 24 * 60 * 60 * 1000;
const FROM = 'Stash <reminders@mail.gostash.it>';
const PREFS_URL = `${Deno.env.get('SUPABASE_URL')}/functions/v1/reminder-email-prefs`;

type Row = DigestItem & { user_id: string };

async function runDigest(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  opts: { dryRun: boolean; now: Date; onlyUserId: string | null },
) {
  const resendKey = Deno.env.get('RESEND_API_KEY');
  const linkSecret = Deno.env.get('EMAIL_LINK_SECRET');
  if (!opts.dryRun && !resendKey) return { status: 'skipped', reason: 'RESEND_API_KEY unset', users: 0, items: 0, failures: 0 };
  if (!linkSecret) return { status: 'skipped', reason: 'EMAIL_LINK_SECRET unset', users: 0, items: 0, failures: 0 };

  const nowIso = opts.now.toISOString();
  const windowStart = new Date(opts.now.getTime() - DUE_WINDOW_MS).toISOString();
  let query = supabase
    .from('items')
    .select('id,user_id,title,content,url,type,created_at,remind_at')
    .is('reminder_cleared_at', null)
    .is('reminder_notified_at', null)
    .lte('remind_at', nowIso)
    .gt('remind_at', windowStart)
    .order('remind_at', { ascending: true });
  if (opts.onlyUserId) query = query.eq('user_id', opts.onlyUserId);
  const { data: rows, error } = await query;
  if (error) throw error;

  const byUser = new Map<string, Row[]>();
  for (const row of (rows ?? []) as Row[]) byUser.set(row.user_id, [...(byUser.get(row.user_id) ?? []), row]);
  if (byUser.size === 0) return { status: opts.dryRun ? 'dry_run' : 'sent', users: 0, items: 0, failures: 0 };

  const { data: prefs } = await supabase
    .from('user_preferences')
    .select('user_id, reminder_emails')
    .in('user_id', [...byUser.keys()]);
  const optedOut = new Set((prefs ?? []).filter((p: { reminder_emails: boolean }) => p.reminder_emails === false).map((p: { user_id: string }) => p.user_id));

  let users = 0, items = 0, failures = 0;
  const previews: Array<{ user_id: string; to: string; subject: string; text: string }> = [];

  for (const [userId, userRows] of byUser) {
    if (optedOut.has(userId)) continue;
    const { data: userData, error: userError } = await supabase.auth.admin.getUserById(userId);
    const to = userData?.user?.email;
    if (userError || !to) { console.warn('reminder-digest: no email for user', { userId }); continue; }

    const token = await signEmailLinkToken(userId, linkSecret, new Date(opts.now.getTime() + UNSUB_TTL_MS));
    const rendered = renderReminderDigest({ items: userRows, unsubscribeUrl: `${PREFS_URL}?token=${token}`, now: opts.now });

    if (opts.dryRun) {
      previews.push({ user_id: userId, to, subject: rendered.subject, text: rendered.text });
      users += 1; items += userRows.length;
      continue;
    }

    const res = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: { Authorization: `Bearer ${resendKey}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ from: FROM, to: [to], subject: rendered.subject, html: rendered.html, text: rendered.text }),
    });
    if (!res.ok) {
      failures += 1;
      console.error('reminder-digest: send failed', { userId, status: res.status, body: (await res.text()).slice(0, 300) });
      continue;   // rows stay un-notified; next run retries while still in window
    }
    const { error: markError } = await supabase
      .from('items')
      .update({ reminder_notified_at: nowIso })
      .in('id', userRows.map((r) => r.id));
    if (markError) console.error('reminder-digest: sent but failed to stamp', { userId, error: markError.message });
    users += 1; items += userRows.length;
  }

  return { status: opts.dryRun ? 'dry_run' : 'sent', users, items, failures, ...(opts.dryRun ? { previews } : {}) };
}

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

  const digest = await runDigest(supabase, { dryRun, now: new Date(), onlyUserId: url.searchParams.get('user_id') });
  console.log('reminder-digest', { dryRun, expired, digest: { ...digest, previews: undefined } });
  return json(200, { expired, digest });
});
