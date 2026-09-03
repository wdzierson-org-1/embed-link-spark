// One-off backfill (2026-09-03): decode HTML entities and strip markdown
// emphasis from link titles/descriptions that were stored raw before ingest
// started cleaning them. Runs against the Supabase Management API with the
// CLI's keychain token (see memory: deploy-process).
//
//   node scripts/backfill-text-hygiene.ts          # dry run: prints the diff
//   node scripts/backfill-text-hygiene.ts --apply  # writes the cleaned rows
import { execSync } from 'node:child_process';
import { cleanMetaText } from '../src/utils/textHygiene.ts';

const PROJECT = 'uqqsgmwkvslaomzxptnp';
const apply = process.argv.includes('--apply');

const token = execSync('security find-generic-password -s "Supabase CLI" -a "supabase" -w', { encoding: 'utf8' })
  .trim()
  .replace(/^go-keyring-base64:/, '');
const accessToken = Buffer.from(token, 'base64').toString('utf8').trim();

const sql = async (query: string) => {
  const res = await fetch(`https://api.supabase.com/v1/projects/${PROJECT}/database/query`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${accessToken}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ query }),
  });
  if (!res.ok) throw new Error(`${res.status} ${await res.text()}`);
  return res.json() as Promise<Array<Record<string, string | null>>>;
};

// Dollar-quote with a tag that cannot appear in the value
const lit = (value: string) => {
  let tag = 'q';
  while (value.includes(`$${tag}$`)) tag += 'q';
  return `$${tag}$${value}$${tag}$`;
};

const ENTITY = String.raw`&(#[0-9]+|#x[0-9a-fA-F]+|[a-zA-Z]+);`;
const rows = await sql(
  `select id, title, description from items
   where type = 'link'
     and (title ~ '${ENTITY}' or description ~ '${ENTITY}' or title ~ '\\*\\*' or description ~ '\\*\\*')
   order by created_at desc`,
);

let changed = 0;
for (const row of rows) {
  const sets: string[] = [];
  const nextTitle = row.title === null ? null : cleanMetaText(row.title);
  const nextDesc = row.description === null ? null : cleanMetaText(row.description);
  if (nextTitle !== null && nextTitle !== row.title) sets.push(`title = ${lit(nextTitle)}`);
  if (nextDesc !== null && nextDesc !== row.description) sets.push(`description = ${lit(nextDesc)}`);
  if (sets.length === 0) continue;
  changed += 1;
  console.log(`\n${row.id}`);
  if (nextTitle !== row.title) console.log(`  title: ${JSON.stringify(row.title)}\n      -> ${JSON.stringify(nextTitle)}`);
  if (nextDesc !== row.description) {
    console.log(`  desc:  ${JSON.stringify(row.description?.slice(0, 140))}\n      -> ${JSON.stringify(nextDesc?.slice(0, 140))}`);
  }
  if (apply) await sql(`update items set ${sets.join(', ')} where id = ${lit(row.id as string)}`);
}
console.log(`\n${rows.length} candidate rows, ${changed} ${apply ? 'updated' : 'would change'}${apply ? '' : ' (dry run; pass --apply to write)'}`);
