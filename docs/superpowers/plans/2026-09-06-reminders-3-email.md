# Reminders — Plan 3 of 3: daily reminder email

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One daily email per user listing their due reminders, sent through Resend, idempotent via `reminder_notified_at`, with a signed one-click opt-out and a Settings switch.

**Architecture:** The `reminder-digest` edge function from Plan 1 gains its second step: select due, un-notified rows for users who haven't opted out, group by user, render with a pure `renderReminderDigest`, send via Resend's REST API, then stamp `reminder_notified_at`. Opt-out is a `user_preferences.reminder_emails` flag flipped either from Settings or by a `reminder-email-prefs` endpoint that verifies an HMAC-signed link token.

**Tech Stack:** Deno edge functions, Web Crypto HMAC (Deno + Node ≥ 18 for vitest), Resend REST API, Vercel Marketplace (Resend resource on the `embed-link-spark` project), React Settings.

**Spec:** `docs/superpowers/specs/2026-09-06-reminders-design.md`

## Global Constraints

- Requires Plan 1 fully deployed (columns, `reminder-digest` function, cron, `CRON_SECRET`).
- Cadence: one run per day at 13:00 UTC; one email per user per run; no email when nothing is due. Never one email per reminder.
- Selection: `remind_at ≤ now`, `remind_at > now − 24h`, `reminder_cleared_at is null`, `reminder_notified_at is null`, `coalesce(user_preferences.reminder_emails, true)`.
- `reminder_notified_at` is stamped only after a successful send; a failed send leaves rows untouched for the next run.
- Sender: `Stash <reminders@gostash.it>`. Item link: `https://www.gostash.it/home#item=<id>`.
- Secrets: `RESEND_API_KEY` (from the Vercel Marketplace resource), `EMAIL_LINK_SECRET` (new, `openssl rand -hex 32`). Never echo either.
- Render (`renderReminderDigest`) is a pure function, separate from delivery (spec A6).
- Test commands: `npm test`, `npx tsc --noEmit -p tsconfig.app.json`.

## Prerequisites Will owns (do these before Task 4)

1. **Accept the Resend Marketplace terms** in the browser: `https://vercel.com/wdzierson-s-team/~/integrations/accept-terms/resend?source=cli`. The repo is already linked to `wdzierson-s-team/embed-link-spark` and the CLI is at 59.11.7. After acceptance the executor runs Task 4 Step 1 to finish provisioning.
2. **Verify the sending domain at GoDaddy.** gostash.it's nameservers are `ns81/ns82.domaincontrol.com` (GoDaddy), so the DNS records have to be added there. In the Resend dashboard (`vercel integration open resend`), Domains → Add `gostash.it` → copy the records it shows (a DKIM `TXT` at `resend._domainkey`, plus `MX` + `TXT` on the `send` subdomain for the return path). They do not collide with the existing root SPF (`v=spf1 include:dc-aa8e722993._spfm.gostash.it ~all`) or Google MX. Wait for Resend to show "Verified".

Until both are done, Tasks 1–3 and 5 can ship; Task 4 sends nothing (the function keeps skipping while `RESEND_API_KEY` is unset).

---

## File map

| File | Responsibility |
|---|---|
| `supabase/functions/_shared/reminderDigest.ts` (+ `.test.ts`) | Pure renderer: subject, html, text |
| `supabase/functions/_shared/emailLinkToken.ts` (+ `.test.ts`) | HMAC-signed, expiring opt-out token |
| `supabase/functions/reminder-email-prefs/index.ts` | GET `?token=` → sets `reminder_emails = false` → HTML page |
| `supabase/functions/reminder-digest/index.ts` | Digest step (select → group → render → send → stamp) |
| `supabase/config.toml` | `verify_jwt = false` for `reminder-email-prefs` |
| `src/hooks/useUserPreferences.ts` | `reminderEmails` + `updateReminderEmails` |
| `src/components/settings/AccountSettings.tsx` | "Reminder emails" switch |
| `docs/ui-changes.md`, `docs/PLATFORM_API.md` | Email cadence, opt-out endpoint |

---

### Task 1: `renderReminderDigest`

**Files:**
- Create: `supabase/functions/_shared/reminderDigest.ts`, `supabase/functions/_shared/reminderDigest.test.ts`

**Interfaces:**
- Produces:
  ```ts
  interface DigestItem { id: string; title: string | null; content: string | null; url: string | null; type: string; created_at: string; remind_at: string }
  interface DigestInput { items: DigestItem[]; unsubscribeUrl: string; now?: Date }
  renderReminderDigest(input: DigestInput): { subject: string; html: string; text: string }
  digestItemTitle(item: DigestItem): string
  ```

- [ ] **Step 1: Failing test**

```ts
import { describe, expect, it } from 'vitest';
import { digestItemTitle, renderReminderDigest } from './reminderDigest';

const base = { type: 'link', created_at: '2026-09-03T15:00:00Z', remind_at: '2026-09-06T15:00:00Z', content: null, url: null, title: null };
const now = new Date('2026-09-06T13:00:00Z');

describe('digestItemTitle', () => {
  it('prefers title, then content excerpt, then host, then type', () => {
    expect(digestItemTitle({ ...base, id: 'a', title: 'A page' })).toBe('A page');
    expect(digestItemTitle({ ...base, id: 'b', content: 'x'.repeat(100) })).toBe('x'.repeat(80) + '…');
    expect(digestItemTitle({ ...base, id: 'c', url: 'https://www.example.com/path' })).toBe('example.com');
    expect(digestItemTitle({ ...base, id: 'd', type: 'image' })).toBe('Saved image');
  });
});

describe('renderReminderDigest', () => {
  it('pluralises the subject', () => {
    expect(renderReminderDigest({ items: [{ ...base, id: 'a', title: 'A' }], unsubscribeUrl: 'https://u', now }).subject)
      .toBe('1 item you asked to see again');
    expect(renderReminderDigest({ items: [{ ...base, id: 'a', title: 'A' }, { ...base, id: 'b', title: 'B' }], unsubscribeUrl: 'https://u', now }).subject)
      .toBe('2 items you asked to see again');
  });
  it('links each item to the web deep link and escapes html', () => {
    const { html, text } = renderReminderDigest({ items: [{ ...base, id: '11111111-1111-4111-8111-111111111111', title: 'Tom & <Jerry>' }], unsubscribeUrl: 'https://u?token=t', now });
    expect(html).toContain('https://www.gostash.it/home#item=11111111-1111-4111-8111-111111111111');
    expect(html).toContain('Tom &amp; &lt;Jerry&gt;');
    expect(html).not.toContain('<Jerry>');
    expect(text).toContain('Tom & <Jerry>');
    expect(text).toContain('https://www.gostash.it/home#item=11111111-1111-4111-8111-111111111111');
  });
  it('says why the email exists and how to stop it', () => {
    const { html, text } = renderReminderDigest({ items: [{ ...base, id: 'a', title: 'A' }], unsubscribeUrl: 'https://u?token=t', now });
    expect(html).toContain('You asked Stash to remind you about these.');
    expect(html).toContain('href="https://u?token=t"');
    expect(text).toContain('Turn off reminder emails: https://u?token=t');
    expect(html).toContain('Saved Sep 3 · reminder for today');
  });
});
```

- [ ] **Step 2: Run to verify failure**

Run: `npx vitest run supabase/functions/_shared/reminderDigest.test.ts`
Expected: module not found.

- [ ] **Step 3: Implement**

```ts
// supabase/functions/_shared/reminderDigest.ts
//
// Pure renderer for the daily reminder email — no I/O, so delivery can change
// (Resend today) without touching content (spec A6). Import-free: Deno + vitest.

export interface DigestItem {
  id: string;
  title: string | null;
  content: string | null;
  url: string | null;
  type: string;
  created_at: string;
  remind_at: string;
}

export interface DigestInput {
  items: DigestItem[];
  unsubscribeUrl: string;
  now?: Date;
}

const ITEM_LINK_BASE = 'https://www.gostash.it/home#item=';
const TYPE_LABEL: Record<string, string> = {
  link: 'Saved link', text: 'Saved note', image: 'Saved image', audio: 'Saved recording',
  video: 'Saved video', document: 'Saved document',
};

const escapeHtml = (s: string) =>
  s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');

const monthDay = (iso: string) =>
  new Date(iso).toLocaleDateString('en-US', { month: 'short', day: 'numeric', timeZone: 'UTC' });

export function digestItemTitle(item: DigestItem): string {
  const title = item.title?.trim();
  if (title) return title;
  const content = item.content?.replace(/\s+/g, ' ').trim();
  if (content) return content.length > 80 ? content.slice(0, 80) + '…' : content;
  if (item.url) {
    try { return new URL(item.url).hostname.replace(/^www\./, ''); } catch { /* fall through */ }
  }
  return TYPE_LABEL[item.type] ?? 'Saved item';
}

export function renderReminderDigest({ items, unsubscribeUrl, now = new Date() }: DigestInput) {
  const n = items.length;
  const subject = `${n} ${n === 1 ? 'item' : 'items'} you asked to see again`;
  const intro = 'You asked Stash to remind you about these.';
  const today = monthDay(now.toISOString());

  const rows = items.map((item) => {
    const title = digestItemTitle(item);
    const link = ITEM_LINK_BASE + item.id;
    const when = monthDay(item.remind_at) === today ? 'reminder for today' : `reminder for ${monthDay(item.remind_at)}`;
    const meta = `Saved ${monthDay(item.created_at)} · ${when}`;
    return { title, link, meta, type: TYPE_LABEL[item.type] ?? 'Saved item' };
  });

  const html = `<!doctype html>
<html><body style="margin:0;padding:24px;background:#ffffff;color:#22262f;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;font-size:15px;line-height:1.5">
  <p style="margin:0 0 20px 0">${intro}</p>
  ${rows.map((r) => `<div style="margin:0 0 18px 0">
    <a href="${r.link}" style="color:#6d5bd0;font-weight:500;text-decoration:none">${escapeHtml(r.title)}</a><br>
    <span style="color:#646b76;font-size:13px">${escapeHtml(r.type)} · ${escapeHtml(r.meta)}</span>
  </div>`).join('\n')}
  <p style="margin:28px 0 0 0;color:#959ba6;font-size:12px">
    <a href="${escapeHtml(unsubscribeUrl)}" style="color:#959ba6">Turn off reminder emails</a>
  </p>
</body></html>`;

  const text = [
    intro, '',
    ...rows.flatMap((r) => [r.title, `${r.type} · ${r.meta}`, r.link, '']),
    `Turn off reminder emails: ${unsubscribeUrl}`,
  ].join('\n');

  return { subject, html, text };
}
```

- [ ] **Step 4: Run tests**

Run: `npx vitest run supabase/functions/_shared/reminderDigest.test.ts`
Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add supabase/functions/_shared/reminderDigest.ts supabase/functions/_shared/reminderDigest.test.ts
git commit -m "feat(reminders): pure reminder-digest email renderer"
```

---

### Task 2: Signed opt-out link token

**Files:**
- Create: `supabase/functions/_shared/emailLinkToken.ts`, `supabase/functions/_shared/emailLinkToken.test.ts`

**Interfaces:**
- Produces: `signEmailLinkToken(userId: string, secret: string, expiresAt: Date): Promise<string>`, `verifyEmailLinkToken(token: string, secret: string, now?: Date): Promise<string | null>` (user id or null). Token = base64url(`${userId}.${expiresEpochSeconds}`) + `.` + base64url(HMAC-SHA256).

- [ ] **Step 1: Failing test**

```ts
import { describe, expect, it } from 'vitest';
import { signEmailLinkToken, verifyEmailLinkToken } from './emailLinkToken';

const uid = '11111111-1111-4111-8111-111111111111';
const secret = 'test-secret';
const future = new Date('2026-10-06T00:00:00Z');
const now = new Date('2026-09-06T00:00:00Z');

describe('email link token', () => {
  it('round-trips', async () => {
    const token = await signEmailLinkToken(uid, secret, future);
    expect(await verifyEmailLinkToken(token, secret, now)).toBe(uid);
    expect(token).not.toContain('+');
    expect(token).not.toContain('/');
    expect(token).not.toContain('=');
  });
  it('rejects tampering, wrong secret, expiry, garbage', async () => {
    const token = await signEmailLinkToken(uid, secret, future);
    const [payload, sig] = token.split('.');
    expect(await verifyEmailLinkToken(`${payload}x.${sig}`, secret, now)).toBeNull();
    expect(await verifyEmailLinkToken(token, 'other', now)).toBeNull();
    expect(await verifyEmailLinkToken(token, secret, new Date('2026-11-01T00:00:00Z'))).toBeNull();
    expect(await verifyEmailLinkToken('nope', secret, now)).toBeNull();
    expect(await verifyEmailLinkToken('', secret, now)).toBeNull();
  });
});
```

- [ ] **Step 2: Run to verify failure**

Run: `npx vitest run supabase/functions/_shared/emailLinkToken.test.ts`
Expected: module not found.

- [ ] **Step 3: Implement**

```ts
// supabase/functions/_shared/emailLinkToken.ts
//
// Signed, expiring link for one-click email actions (opt-out today). Web
// Crypto only, so the same file runs under Deno and vitest (Node ≥ 18).

const enc = new TextEncoder();

const b64url = (bytes: Uint8Array) =>
  btoa(String.fromCharCode(...bytes)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');

const fromB64url = (s: string): Uint8Array | null => {
  try {
    const b64 = s.replace(/-/g, '+').replace(/_/g, '/') + '='.repeat((4 - (s.length % 4)) % 4);
    return Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
  } catch {
    return null;
  }
};

async function hmac(secret: string, payload: string): Promise<Uint8Array> {
  const key = await crypto.subtle.importKey('raw', enc.encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  return new Uint8Array(await crypto.subtle.sign('HMAC', key, enc.encode(payload)));
}

export async function signEmailLinkToken(userId: string, secret: string, expiresAt: Date): Promise<string> {
  const payload = b64url(enc.encode(`${userId}.${Math.floor(expiresAt.getTime() / 1000)}`));
  return `${payload}.${b64url(await hmac(secret, payload))}`;
}

export async function verifyEmailLinkToken(token: string, secret: string, now: Date = new Date()): Promise<string | null> {
  const parts = token.split('.');
  if (parts.length !== 2) return null;
  const [payload, sig] = parts;
  const expected = b64url(await hmac(secret, payload));
  if (expected.length !== sig.length) return null;
  let diff = 0;
  for (let i = 0; i < expected.length; i++) diff |= expected.charCodeAt(i) ^ sig.charCodeAt(i);
  if (diff !== 0) return null;
  const raw = fromB64url(payload);
  if (!raw) return null;
  const [userId, exp] = new TextDecoder().decode(raw).split('.');
  if (!userId || !/^\d+$/.test(exp ?? '')) return null;
  if (Number(exp) * 1000 < now.getTime()) return null;
  return userId;
}
```

- [ ] **Step 4: Run tests**

Run: `npx vitest run supabase/functions/_shared/emailLinkToken.test.ts`
Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add supabase/functions/_shared/emailLinkToken.ts supabase/functions/_shared/emailLinkToken.test.ts
git commit -m "feat(reminders): HMAC-signed email link token"
```

---

### Task 3: `reminder-email-prefs` endpoint + `EMAIL_LINK_SECRET`

**Files:**
- Create: `supabase/functions/reminder-email-prefs/index.ts`
- Modify: `supabase/config.toml`

**Interfaces:**
- Produces: `GET /functions/v1/reminder-email-prefs?token=<t>` → `200 text/html` "Reminder emails are off." after upserting `user_preferences.reminder_emails = false`; `400` on a bad/expired token.
- Consumes: `verifyEmailLinkToken` (Task 2).

- [ ] **Step 1: Write the function**

```ts
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
```

- [ ] **Step 2: Config + secret + deploy**

Append to `supabase/config.toml`:

```toml
# Signed-link opt-out from the reminder digest; the token is the auth.
[functions.reminder-email-prefs]
verify_jwt = false
```

```bash
supabase secrets set EMAIL_LINK_SECRET=$(openssl rand -hex 32) --project-ref uqqsgmwkvslaomzxptnp
supabase functions deploy reminder-email-prefs --project-ref uqqsgmwkvslaomzxptnp
supabase functions list --project-ref uqqsgmwkvslaomzxptnp | grep reminder-email-prefs
curl -s -o /dev/null -w '%{http_code}\n' "https://uqqsgmwkvslaomzxptnp.supabase.co/functions/v1/reminder-email-prefs?token=nope"
```

Expected: `400`. (A valid-token check happens in Task 4's dry run, which prints the unsubscribe URL.)

- [ ] **Step 3: Commit**

```bash
git add supabase/functions/reminder-email-prefs/index.ts supabase/config.toml
git commit -m "feat(reminders): one-click reminder-email opt-out endpoint"
```

---

### Task 4: Provision Resend, then the digest step

**Files:**
- Modify: `supabase/functions/reminder-digest/index.ts` (replace the `digest` placeholder from Plan 1)

**Interfaces:**
- Consumes: `renderReminderDigest`, `DigestItem` (Task 1); `signEmailLinkToken` (Task 2); `reminder-email-prefs` URL (Task 3).
- Produces: response `{ expired, digest: { status: 'sent' | 'skipped' | 'dry_run', users: number, items: number, failures: number, previews?: [...] } }`.

- [ ] **Step 1: Finish the Marketplace install (after Will accepts terms)**

```bash
vercel --non-interactive integration add resend --format=json --no-env-pull
vercel env ls production | grep -i resend
```

Expected: the resource installs and `RESEND_API_KEY` appears on the project. Move it to Supabase without printing it:

```bash
vercel env pull /tmp/resend.env --environment production --yes
grep -q '^RESEND_API_KEY=' /tmp/resend.env && supabase secrets set --env-file <(grep '^RESEND_API_KEY=' /tmp/resend.env) --project-ref uqqsgmwkvslaomzxptnp
rm /tmp/resend.env
supabase secrets list --project-ref uqqsgmwkvslaomzxptnp | grep RESEND_API_KEY
```

If `vercel integration add` reports another `action_required`, follow its `next[]` command; if it needs the dashboard, run `vercel integration open resend` and stop for Will.

- [ ] **Step 2: Implement the digest step**

Replace the placeholder block (`const digest = …` through `return json(200, …)`) in `reminder-digest/index.ts` with:

```ts
  const digest = await runDigest(supabase, { dryRun, now: new Date(), onlyUserId: url.searchParams.get('user_id') });
  console.log('reminder-digest', { dryRun, expired, digest: { ...digest, previews: undefined } });
  return json(200, { expired, digest });
```

and add above `serve(`:

```ts
import { renderReminderDigest, type DigestItem } from '../_shared/reminderDigest.ts';
import { signEmailLinkToken } from '../_shared/emailLinkToken.ts';

const DUE_WINDOW_MS = 24 * 60 * 60 * 1000;
const UNSUB_TTL_MS = 30 * 24 * 60 * 60 * 1000;
const FROM = 'Stash <reminders@gostash.it>';
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
```

- [ ] **Step 3: Deploy, dry-run against the test account, then a real send to it**

```bash
supabase functions deploy reminder-digest --project-ref uqqsgmwkvslaomzxptnp
```

Seed: with the Management API, on one `will+uitest` item run `update items set remind_at = now() - interval '10 minutes', reminder_cleared_at = null, reminder_notified_at = null where id = '<id>'`.

```bash
curl -s -X POST "https://uqqsgmwkvslaomzxptnp.supabase.co/functions/v1/reminder-digest?dry_run=1&user_id=<uitest uid>" -H "x-cron-secret: <value>"
```

Expected: `digest.status = "dry_run"`, `users: 1`, `items: 1`, a preview whose `text` contains the item title, the deep link, and an unsubscribe URL. Open that unsubscribe URL in a browser → "Reminder emails are off" page; confirm `select reminder_emails from user_preferences where user_id = '<uid>'` is `false`; set it back to `true` with SQL.

Real send (after the domain is verified):

```bash
curl -s -X POST "https://uqqsgmwkvslaomzxptnp.supabase.co/functions/v1/reminder-digest?user_id=<uitest uid>" -H "x-cron-secret: <value>"
```

Expected: `status: "sent", users: 1, items: 1, failures: 0`; the email arrives in the test inbox; `reminder_notified_at` is set on the row; a second identical call returns `users: 0`.

- [ ] **Step 4: Commit**

```bash
git add supabase/functions/reminder-digest/index.ts
git commit -m "feat(reminders): daily reminder digest via Resend, idempotent via reminder_notified_at"
```

---

### Task 5: Settings switch

**Files:**
- Modify: `src/hooks/useUserPreferences.ts`, `src/components/settings/AccountSettings.tsx`
- Test: create `src/hooks/useUserPreferences.test.ts`

**Interfaces:**
- Produces: `useUserPreferences()` returns additionally `reminderEmails: boolean` and `updateReminderEmails(enabled: boolean): Promise<void>`.

- [ ] **Step 1: Failing hook test**

```ts
import { renderHook, waitFor, act } from '@testing-library/react';
import { useUserPreferences } from './useUserPreferences';

const { single, upsert } = vi.hoisted(() => ({
  single: vi.fn(() => Promise.resolve({ data: { hide_add_section: false, reminder_emails: false }, error: null })),
  upsert: vi.fn(() => Promise.resolve({ error: null })),
}));

vi.mock('@/integrations/supabase/client', () => ({
  supabase: { from: () => ({ select: () => ({ eq: () => ({ single }) }), upsert }) },
}));
vi.mock('@/hooks/useAuth', () => ({ useAuth: () => ({ user: { id: 'u1' } }) }));
vi.mock('@/hooks/use-toast', () => ({ useToast: () => ({ toast: vi.fn() }) }));

describe('useUserPreferences reminder emails', () => {
  it('reads reminder_emails and writes it back through upsert', async () => {
    const { result } = renderHook(() => useUserPreferences());
    await waitFor(() => expect(result.current.loading).toBe(false));
    expect(result.current.reminderEmails).toBe(false);
    await act(() => result.current.updateReminderEmails(true));
    expect(upsert).toHaveBeenCalledWith(
      expect.objectContaining({ user_id: 'u1', reminder_emails: true }),
      { onConflict: 'user_id' },
    );
    expect(result.current.reminderEmails).toBe(true);
  });
});
```

- [ ] **Step 2: Run to verify failure**

Run: `npx vitest run src/hooks/useUserPreferences.test.ts`
Expected: `reminderEmails` undefined / `updateReminderEmails` not a function.

- [ ] **Step 3: Extend the hook**

In `src/hooks/useUserPreferences.ts`: select `'hide_add_section, reminder_emails'`; add `const [reminderEmails, setReminderEmails] = useState(true);` set from `data.reminder_emails ?? true`; add:

```ts
  const updateReminderEmails = async (enabled: boolean) => {
    if (!user) return;
    const { error } = await supabase
      .from('user_preferences')
      .upsert({ user_id: user.id, reminder_emails: enabled, updated_at: new Date().toISOString() }, { onConflict: 'user_id' });
    if (error) {
      console.error('Error updating reminder_emails:', error);
      toast({ title: 'Error', description: 'Failed to save preference', variant: 'destructive' });
      return;
    }
    setReminderEmails(enabled);
  };
```

and return `reminderEmails, updateReminderEmails`. Keep `hide_add_section` in the existing upsert untouched (the two upserts write different columns; both include `user_id`, so neither wipes the other).

- [ ] **Step 4: Settings card**

In `AccountSettings.tsx` import `Switch` from `@/components/ui/switch` (shadcn; if the file is missing, `npx shadcn@latest add switch`) and `useUserPreferences`. Add a card after the profile card:

```tsx
      <Card>
        <CardHeader>
          <CardTitle>Reminder emails</CardTitle>
          <CardDescription>One email a day listing the items whose reminder came due. Nothing is sent on days with no reminders.</CardDescription>
        </CardHeader>
        <CardContent className="flex items-center justify-between">
          <Label htmlFor="reminder-emails">Email me when reminders are due</Label>
          <Switch id="reminder-emails" checked={reminderEmails} onCheckedChange={updateReminderEmails} disabled={prefsLoading} />
        </CardContent>
      </Card>
```

with `const { reminderEmails, updateReminderEmails, loading: prefsLoading } = useUserPreferences();` at the top.

- [ ] **Step 5: Tests + typecheck**

Run: `npx vitest run src/hooks/useUserPreferences.test.ts && npx tsc --noEmit -p tsconfig.app.json && npm test`
Expected: green.

- [ ] **Step 6: Commit**

```bash
git add src/hooks/useUserPreferences.ts src/hooks/useUserPreferences.test.ts src/components/settings/AccountSettings.tsx
git commit -m "feat(reminders): Settings switch for reminder emails"
```

---

### Task 6: Docs + hand-off

**Files:**
- Modify: `docs/PLATFORM_API.md` (Reminders section, daily-job paragraph), `docs/ui-changes.md` (2026-09-06 reminders entry)

- [ ] **Step 1: PLATFORM_API**

Replace the "Daily job" paragraph with:

```markdown
Daily job: `reminder-digest` (pg_cron 13:00 UTC → pg_net → edge function,
`x-cron-secret`). Step 1 expires stale reminders (`reminders_expire()`).
Step 2 selects due, uncleared, un-notified rows for users with
`user_preferences.reminder_emails` not false, sends **one** email per user
via Resend (`Stash <reminders@gostash.it>`), then stamps
`reminder_notified_at`. Each item links to `/home#item=<id>`. The footer's
"Turn off reminder emails" is `GET /reminder-email-prefs?token=<signed,
30-day>` — no session needed. Clients that want their own toggle write
`user_preferences.reminder_emails` directly (owner RLS).
```

- [ ] **Step 2: ui-changes**

Replace the Backend bullet in the entry with:

```markdown
- **Backend + email (shipped):** `reminder-digest` runs 13:00 UTC; one email
  per user per day listing due reminders (title → content excerpt → host →
  type fallback; "Saved Sep 3 · reminder for today"; deep link per item);
  signed one-click opt-out + Settings → Account "Email me when reminders are
  due" switch (`user_preferences.reminder_emails`). Sent through Resend from
  `reminders@gostash.it`. Per-user timezone is a later refinement.
```

- [ ] **Step 3: Commit and finish**

```bash
git add docs/PLATFORM_API.md docs/ui-changes.md
git commit -m "docs(reminders): email cadence, opt-out endpoint, settings switch"
```

Then `superpowers:finishing-a-development-branch`; push deploys the Settings switch. Confirm the next 13:00 UTC run in `cron.job_run_details` and the function log the following day.

---

## Self-review

- Spec coverage: renderer + subject/title/link/footer (T1), signed link (T2), opt-out endpoint (T3), selection/grouping/send/stamp/idempotency/dry run + provider provisioning + secret hand-off (T4), Settings switch (T5), docs (T6). Cadence and "never per reminder" are structural (one loop iteration per user).
- Names: `renderReminderDigest`, `digestItemTitle`, `DigestItem`, `signEmailLinkToken`, `verifyEmailLinkToken`, `reminder-email-prefs`, `reminder_emails`, `reminderEmails`, `updateReminderEmails`, `runDigest` — consistent.
