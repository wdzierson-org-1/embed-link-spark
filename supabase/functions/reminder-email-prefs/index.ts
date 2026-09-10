import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.50.2';
import { verifyEmailLinkToken } from '../_shared/emailLinkToken.ts';

// One-click opt-out from the reminder digest. No session: the signed token in
// the email link is the authorisation (30-day expiry, set at send time).

const page = (status: number, title: string, body: string) =>
  new Response(
    `<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${title}</title></head>
<body style="margin:0;padding:48px 24px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;color:#22262f;text-align:center">
<h1 style="font-size:20px;font-weight:500;margin:0 0 8px 0">${title}</h1>
<p style="color:#646b76;margin:0">${body}</p>
<p style="margin-top:24px"><a href="https://www.gostash.it/settings" style="color:#6d5bd0">Open Stash settings</a></p>
</body></html>`,
    { status, headers: { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store' } },
  );

serve(async (req) => {
  if (req.method !== 'GET') return page(405, 'Not allowed', 'This link only accepts GET.');
  const secret = Deno.env.get('EMAIL_LINK_SECRET');
  const token = new URL(req.url).searchParams.get('token') ?? '';
  const userId = secret ? await verifyEmailLinkToken(token, secret) : null;
  if (!userId) return page(400, 'This link has expired', 'Turn reminder emails off from Settings instead.');

  const supabase = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
  const { error } = await supabase
    .from('user_preferences')
    .upsert({ user_id: userId, reminder_emails: false, updated_at: new Date().toISOString() }, { onConflict: 'user_id' });
  if (error) {
    console.error('reminder-email-prefs upsert failed', { userId, error: error.message });
    return page(500, 'Something went wrong', 'Please try again, or turn reminder emails off from Settings.');
  }
  console.log('reminder-email-prefs: opted out', { userId });
  return page(200, 'Reminder emails are off', 'You can turn them back on any time in Settings.');
});
