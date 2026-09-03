// Review card feedback (ui-changes.md 2026-09-03). Prints the newest reports
// with the card's current title/url beside the snapshot, so a "looks wrong"
// report can be triaged without opening the app. Uses the Management API
// with the CLI's keychain token (see memory: deploy-process).
//
//   node scripts/card-feedback-report.ts            # last 50
//   node scripts/card-feedback-report.ts --days 7   # last week
import { execSync } from 'node:child_process';

const PROJECT = 'uqqsgmwkvslaomzxptnp';
const daysArg = process.argv.indexOf('--days');
const days = daysArg > -1 ? Number(process.argv[daysArg + 1]) : null;

const token = execSync('security find-generic-password -s "Supabase CLI" -a "supabase" -w', { encoding: 'utf8' })
  .trim()
  .replace(/^go-keyring-base64:/, '');
const accessToken = Buffer.from(token, 'base64').toString('utf8').trim();

const res = await fetch(`https://api.supabase.com/v1/projects/${PROJECT}/database/query`, {
  method: 'POST',
  headers: { Authorization: `Bearer ${accessToken}`, 'Content-Type': 'application/json' },
  body: JSON.stringify({
    query: `select f.created_at, f.client, f.issues, f.note, f.snapshot, f.item_id,
                   i.title as current_title, i.url as current_url, i.type as current_type
            from card_feedback f left join items i on i.id = f.item_id
            ${days ? `where f.created_at > now() - interval '${days} days'` : ''}
            order by f.created_at desc limit 50`,
  }),
});
if (!res.ok) throw new Error(`${res.status} ${await res.text()}`);
const rows = (await res.json()) as Array<Record<string, unknown>>;

for (const r of rows) {
  const snap = (r.snapshot ?? {}) as Record<string, unknown>;
  console.log(`\n${String(r.created_at).slice(0, 16)}  [${r.client}]  ${(r.issues as string[]).join(', ')}`);
  console.log(`  item   ${r.item_id ?? '(deleted)'}  ${r.current_type ?? snap.type ?? ''}`);
  console.log(`  title  ${JSON.stringify(r.current_title ?? snap.title ?? '')}`);
  if (snap.title && snap.title !== r.current_title) console.log(`  was    ${JSON.stringify(snap.title)}`);
  if (r.current_url ?? snap.url) console.log(`  url    ${r.current_url ?? snap.url}`);
  if (snap.file_path) console.log(`  image  ${snap.file_path}`);
  if (r.note) console.log(`  note   ${JSON.stringify(r.note)}`);
}
console.log(`\n${rows.length} report(s)`);
