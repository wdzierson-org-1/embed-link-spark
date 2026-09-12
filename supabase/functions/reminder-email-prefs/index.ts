import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.50.2';
import { verifyEmailLinkToken } from '../_shared/emailLinkToken.ts';

// Opt-out from the reminder digest. No session: the signed token in the
// email link is the authorisation (30-day expiry, set at send time).
//
// R8: GET only *shows* a confirmation page; the change is applied on POST.
// Mail-security scanners prefetch every link in inbound mail, so a GET that
// applied the change would silently unsubscribe users whose mail provider
// scans their inbox. The POST form doubles as the target for mail clients'
// native RFC 8058 one-click ("List-Unsubscribe-Post: List-Unsubscribe=One-Click").

const escapeHtml = (s: string) =>
  s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');

const page = (status: number, title: string, body: string, extra = '') =>
  new Response(
    `<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${title}</title></head>
<body style="margin:0;padding:48px 24px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;color:#22262f;text-align:center">
<h1 style="font-size:20px;font-weight:500;margin:0 0 8px 0">${title}</h1>
<p style="color:#646b76;margin:0">${body}</p>
${extra}
<p style="margin-top:24px"><a href="https://www.gostash.it/settings" style="color:#6d5bd0">Open Stash settings</a></p>
</body></html>`,
    { status, headers: { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store' } },
  );

const confirmForm = (token: string) => `<p style="margin-top:24px">
<form method="post" action="?token=${escapeHtml(token)}">
<button type="submit" style="background:#6d5bd0;color:#ffffff;border:none;border-radius:999px;padding:12px 20px;font-size:15px;font-weight:500;cursor:pointer">Turn off reminder emails</button>
</form>
</p>`;

async function resolveUserId(token: string): Promise<string | null> {
  const secret = Deno.env.get('EMAIL_LINK_SECRET');
  if (!secret) {
    console.error('reminder-email-prefs: EMAIL_LINK_SECRET unset');
    return null;
  }
  return await verifyEmailLinkToken(token, secret);
}

serve(async (req) => {
  const token = new URL(req.url).searchParams.get('token') ?? '';

  if (req.method === 'GET') {
    const userId = await resolveUserId(token);
    if (!userId) return page(400, 'This link has expired', 'Turn reminder emails off from Settings instead.');
    return page(
      200,
      'Turn off reminder emails?',
      "You'll stop getting the daily reminder digest. You can turn it back on any time in Settings.",
      confirmForm(token),
    );
  }

  if (req.method === 'POST') {
    // A form submit from the confirmation page above, or a mail client's
    // native RFC 8058 one-click POST (body may be `List-Unsubscribe=One-Click`);
    // either way the body is never parsed — only the query-string token counts.
    const userId = await resolveUserId(token);
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
  }

  return page(405, 'Not allowed', 'This link only accepts GET and POST.');
});
