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
