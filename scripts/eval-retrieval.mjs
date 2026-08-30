#!/usr/bin/env node
// Replay the golden retrieval set (supabase/evals/golden-retrieval.json)
// against the live hybrid_search_content RPC, mimicking the edge function's
// soft-filter merge (chat-with-all-content/runSearchStash): a filtered
// primary pass plus an unfiltered backstop, backstop hits appended after.
//
// Usage:
//   SUPABASE_ACCESS_TOKEN=sbp_... OPENAI_API_KEY=sk-... node scripts/eval-retrieval.mjs
//
// SUPABASE_ACCESS_TOKEN is a management-API token (`supabase login` stores
// one in the macOS keychain under "Supabase CLI"). Queries run through the
// management API, so no DB password or service key is needed.

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const PROJECT_REF = process.env.SUPABASE_PROJECT_REF || 'uqqsgmwkvslaomzxptnp';
const ACCESS_TOKEN = process.env.SUPABASE_ACCESS_TOKEN;
const OPENAI_KEY = process.env.OPENAI_API_KEY;
const LIMIT = 8;          // SEARCH_DEFAULT_LIMIT in the edge function
const EXTRA_LIMIT = 4;    // SEARCH_EXTRA_LIMIT in the edge function

if (!ACCESS_TOKEN || !OPENAI_KEY) {
  console.error('Set SUPABASE_ACCESS_TOKEN and OPENAI_API_KEY.');
  process.exit(2);
}

const root = dirname(dirname(fileURLToPath(import.meta.url)));
const golden = JSON.parse(readFileSync(join(root, 'supabase/evals/golden-retrieval.json'), 'utf8'));

const sql = async (query) => {
  const res = await fetch(`https://api.supabase.com/v1/projects/${PROJECT_REF}/database/query`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${ACCESS_TOKEN}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ query }),
  });
  if (!res.ok) throw new Error(`management API ${res.status}: ${(await res.text()).slice(0, 200)}`);
  return res.json();
};

const embed = async (texts) => {
  const res = await fetch('https://api.openai.com/v1/embeddings', {
    method: 'POST',
    headers: { Authorization: `Bearer ${OPENAI_KEY}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ model: 'text-embedding-3-small', input: texts }),
  });
  const data = await res.json();
  if (!data.data) throw new Error(`embeddings failed: ${JSON.stringify(data).slice(0, 200)}`);
  return data.data.map((d) => d.embedding);
};

const lit = (s) => `'${String(s).replace(/'/g, "''")}'`;

const search = async (uid, embedding, query, types, tags) => {
  const typesSql = types?.length ? `ARRAY[${types.map(lit).join(',')}]::item_type[]` : 'NULL';
  const tagsSql = tags?.length ? `ARRAY[${tags.map((t) => lit(t.toLowerCase())).join(',')}]::text[]` : 'NULL';
  const rows = await sql(
    `SELECT item_id, item_type, item_flavor, score FROM hybrid_search_content(
       ${lit(query)}, ${lit(JSON.stringify(embedding))}::vector, ${lit(uid)}::uuid,
       ${LIMIT * 2}, 50, ${typesSql}, NULL, NULL, ${tagsSql}, 0.3)`,
  );
  return rows;
};

// Same merge as runSearchStash: up to LIMIT primary hits + up to EXTRA_LIMIT
// backstop-only hits, the union ranked by score.
const mergedRanking = (primary, backstop) => {
  const seen = new Set();
  const chosen = [];
  for (const hit of primary) {
    if (chosen.length >= LIMIT) break;
    if (seen.has(hit.item_id)) continue;
    seen.add(hit.item_id);
    chosen.push(hit);
  }
  let extras = 0;
  for (const hit of backstop ?? []) {
    if (extras >= EXTRA_LIMIT) break;
    if (seen.has(hit.item_id)) continue;
    seen.add(hit.item_id);
    chosen.push(hit);
    extras++;
  }
  chosen.sort((a, b) => b.score - a.score);
  return chosen.map((h) => h.item_id);
};

const userIds = new Map();
const userId = async (email) => {
  if (!userIds.has(email)) {
    const rows = await sql(`SELECT id FROM auth.users WHERE email = ${lit(email)}`);
    if (!rows.length) throw new Error(`no user for ${email}`);
    userIds.set(email, rows[0].id);
  }
  return userIds.get(email);
};

let failures = 0;
const embeddings = await embed(golden.cases.map((c) => c.query));

for (let i = 0; i < golden.cases.length; i++) {
  const c = golden.cases[i];
  const uid = await userId(c.user_email);
  const types = c.filters?.types ?? null;
  const tags = c.filters?.tags ?? null;
  const hasSoft = Boolean(types?.length || tags?.length);
  const [primary, backstop] = await Promise.all([
    search(uid, embeddings[i], c.query, types, tags),
    hasSoft ? search(uid, embeddings[i], c.query, null, null) : Promise.resolve(null),
  ]);
  const ranking = mergedRanking(primary, backstop);
  const rank = ranking.indexOf(c.expect_item) + 1;
  const pass = rank > 0 && rank <= c.expect_in_top;
  if (!pass) failures++;
  console.log(
    `${pass ? 'PASS' : 'FAIL'}  ${c.id.padEnd(32)} rank ${rank || '—'}/${c.expect_in_top}  (${c.class})`,
  );
}

console.log(failures ? `\n${failures} case(s) failing.` : '\nAll golden cases pass.');
process.exit(failures ? 1 : 0);
