#!/usr/bin/env node
// scripts/mcp-smoke.mjs — end-to-end check of the Stash MCP server.
//
//   node scripts/mcp-smoke.mjs                 # full run: discovery → DCR → PKCE authorize (you approve in a browser) → tools → fence
//   node scripts/mcp-smoke.mjs --reuse         # re-run the tool + fence calls with the saved token (e.g. after revoking in Settings)
//   node scripts/mcp-smoke.mjs --server https://uqqsgmwkvslaomzxptnp.supabase.co/functions/v1/mcp
//
// Node 18+, no dependencies. Mirrors what Claude does: reads the 401 challenge,
// fetches protected-resource + authorization-server metadata, registers a
// public client with a loopback redirect, and exchanges the code with PKCE.
import http from 'node:http';
import { createHash, randomBytes } from 'node:crypto';
import { readFileSync, writeFileSync } from 'node:fs';

const args = process.argv.slice(2);
const opt = (name, dflt) => { const i = args.indexOf(name); return i >= 0 ? args[i + 1] : dflt; };
const SERVER = opt('--server', 'https://www.gostash.it/mcp');
const QUERY = opt('--query', 'design');
const PORT = Number(opt('--port', '8765'));
const REUSE = args.includes('--reuse');
const STATE_FILE = '/tmp/stash-mcp-smoke.json';
const ANON = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVxcXNnbXdrdnNsYW9tenhwdG5wIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTA2MjU0ODcsImV4cCI6MjA2NjIwMTQ4N30.vGWb1EdshtLFLpUHQ54Vy2CDmuPVCTbvc8UYW6_cvmE';
const SUPABASE = 'https://uqqsgmwkvslaomzxptnp.supabase.co';

const b64url = (buf) => buf.toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
const ok = (label, cond, detail = '') => { console.log(`${cond ? 'PASS' : 'FAIL'}  ${label}${detail ? ` — ${detail}` : ''}`); if (!cond) process.exitCode = 1; };
const warn = (label, cond, detail = '') => console.log(`${cond ? 'PASS' : 'WARN'}  ${label}${detail ? ` — ${detail}` : ''}`);

async function rpc(token, id, method, params) {
  const res = await fetch(SERVER, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Accept: 'application/json', Authorization: `Bearer ${token}` },
    body: JSON.stringify({ jsonrpc: '2.0', ...(id === undefined ? {} : { id }), method, ...(params ? { params } : {}) }),
  });
  return { status: res.status, body: res.status === 202 ? null : await res.json().catch(() => null), www: res.headers.get('www-authenticate') };
}

async function oauth() {
  const first = await fetch(SERVER, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: '{}' });
  ok('unauthenticated POST → 401', first.status === 401, String(first.status));
  const www = first.headers.get('www-authenticate') || '';
  const prmUrl = /resource_metadata="([^"]+)"/.exec(www)?.[1];
  ok('401 carries resource_metadata', !!prmUrl, www);
  const prm = await (await fetch(prmUrl)).json();
  ok('resource matches server URL', prm.resource === SERVER, `${prm.resource} vs ${SERVER}`);
  const fnCard = await fetch(`${SERVER}/.well-known/mcp-server-card`);
  const fnCardBody = await fnCard.json().catch(() => null);
  ok('server card from the function', fnCard.status === 200 && fnCardBody?.name === 'it.gostash/stash', String(fnCard.status));
  const siteCard = await fetch(`${new URL(SERVER).origin}/.well-known/mcp-server-card`);
  warn('server card at site root (Vercel .well-known)', (siteCard.headers.get('content-type') || '').includes('json'), `${siteCard.status} ${siteCard.headers.get('content-type')}`);
  const issuer = new URL(prm.authorization_servers[0]);
  const asMeta = await (await fetch(`${issuer.origin}/.well-known/oauth-authorization-server${issuer.pathname}`)).json();
  ok('authorization server metadata', !!asMeta.registration_endpoint && !!asMeta.token_endpoint, JSON.stringify(Object.keys(asMeta)));

  const redirectUri = `http://127.0.0.1:${PORT}/callback`;
  const reg = await (await fetch(asMeta.registration_endpoint, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      client_name: 'Stash MCP smoke test', client_uri: 'https://www.gostash.it',
      redirect_uris: [redirectUri], grant_types: ['authorization_code', 'refresh_token'],
      response_types: ['code'], token_endpoint_auth_method: 'none',
    }),
  })).json();
  ok('dynamic client registration', !!reg.client_id, JSON.stringify(reg).slice(0, 200));

  const verifier = b64url(randomBytes(32));
  const challenge = b64url(createHash('sha256').update(verifier).digest());
  const state = b64url(randomBytes(12));
  const authorizeUrl = `${asMeta.authorization_endpoint}?${new URLSearchParams({
    response_type: 'code', client_id: reg.client_id, redirect_uri: redirectUri, state,
    code_challenge: challenge, code_challenge_method: 'S256', scope: 'email',
  })}`;

  const code = await new Promise((resolve, reject) => {
    const server = http.createServer((req, res) => {
      const u = new URL(req.url, `http://127.0.0.1:${PORT}`);
      if (u.pathname !== '/callback') { res.writeHead(404).end(); return; }
      res.writeHead(200, { 'Content-Type': 'text/plain' }).end('Stash smoke test: you can close this tab.');
      server.close();
      if (u.searchParams.get('state') !== state) return reject(new Error('state mismatch'));
      if (u.searchParams.get('error')) return reject(new Error(`${u.searchParams.get('error')}: ${u.searchParams.get('error_description')}`));
      resolve(u.searchParams.get('code'));
    });
    server.listen(PORT, '127.0.0.1', () => {
      console.log(`\nOpen this URL, sign in as the test account, and approve:\n\n${authorizeUrl}\n`);
    });
  });

  const tokens = await (await fetch(asMeta.token_endpoint, {
    method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ grant_type: 'authorization_code', code, client_id: reg.client_id, redirect_uri: redirectUri, code_verifier: verifier }),
  })).json();
  ok('token exchange', !!tokens.access_token, JSON.stringify(tokens).slice(0, 160));
  writeFileSync(STATE_FILE, JSON.stringify({ client_id: reg.client_id, ...tokens }, null, 2));
  return tokens.access_token;
}

async function tools(token) {
  const init = await rpc(token, 1, 'initialize', { protocolVersion: '2025-06-18', capabilities: {}, clientInfo: { name: 'smoke', version: '0' } });
  ok('initialize', init.status === 200 && init.body?.result?.serverInfo?.name === 'stash', JSON.stringify(init.body).slice(0, 200));
  const note = await rpc(token, undefined, 'notifications/initialized');
  ok('notifications/initialized → 202', note.status === 202, String(note.status));
  const list = await rpc(token, 2, 'tools/list');
  const toolDefs = list.body?.result?.tools ?? [];
  const names = toolDefs.map((t) => t.name);
  ok('tools/list', ['search_stash', 'get_item', 'search', 'fetch'].every((n) => names.includes(n)), names.join(','));
  ok('every tool has title + read-only annotations', toolDefs.every((t) => t.title && t.annotations?.readOnlyHint === true && t.annotations?.destructiveHint === false));
  const search = await rpc(token, 3, 'tools/call', { name: 'search_stash', arguments: { query: QUERY, limit: 3 } });
  const results = search.body?.result?.structuredContent?.results ?? [];
  ok('search_stash returns results', search.status === 200 && !search.body?.result?.isError && results.length > 0, (search.body?.result?.content?.[0]?.text ?? '').slice(0, 200));
  if (results[0]) {
    const item = await rpc(token, 4, 'tools/call', { name: 'get_item', arguments: { id: results[0].id } });
    ok('get_item reads the first hit', item.status === 200 && !item.body?.result?.isError, (item.body?.result?.content?.[0]?.text ?? '').slice(0, 160));
  }
  const missing = await rpc(token, 5, 'tools/call', { name: 'get_item', arguments: { id: '00000000-0000-0000-0000-000000000000' } });
  ok('get_item unknown id → isError', missing.body?.result?.isError === true);
  const listing = await rpc(token, 6, 'tools/call', { name: 'search_stash', arguments: { types: ['link'], limit: 2 } });
  ok('search_stash without query lists', !listing.body?.result?.isError, String(listing.body?.result?.structuredContent?.count));

  // ChatGPT contract: search → { results: [{ id, title, url }] }, fetch → { id, title, text, url, metadata },
  // each as structuredContent AND as a JSON string in the text content item; url never empty.
  const s = await rpc(token, 7, 'tools/call', { name: 'search', arguments: { query: QUERY } });
  const sr = s.body?.result?.structuredContent?.results ?? [];
  const sText = JSON.parse(s.body?.result?.content?.[0]?.text ?? '{}');
  ok('ChatGPT search shape', sr.length > 0 && sr.every((r) => typeof r.id === 'string' && typeof r.title === 'string' && typeof r.url === 'string' && r.url.length > 0) && sText.results?.length === sr.length, JSON.stringify(sr[0]));
  if (sr[0]) {
    const f = await rpc(token, 8, 'tools/call', { name: 'fetch', arguments: { id: sr[0].id } });
    const fr = f.body?.result?.structuredContent ?? {};
    const fText = JSON.parse(f.body?.result?.content?.[0]?.text ?? '{}');
    ok('ChatGPT fetch shape', ['id', 'title', 'text', 'url'].every((k) => typeof fr[k] === 'string') && fr.url.length > 0 && typeof fr.metadata === 'object' && fText.id === fr.id, JSON.stringify(fr).slice(0, 120));
  }
  const oldInit = await rpc(token, 9, 'initialize', { protocolVersion: '2024-11-05', capabilities: {}, clientInfo: { name: 'old', version: '0' } });
  ok('initialize echoes 2024-11-05', oldInit.body?.result?.protocolVersion === '2024-11-05');
}

async function fence(token) {
  const rest = await fetch(`${SUPABASE}/rest/v1/items?select=id&limit=1`, { headers: { apikey: ANON, Authorization: `Bearer ${token}` } });
  const rows = await rest.json().catch(() => null);
  ok('fence: PostgREST items → no rows for agent token', Array.isArray(rows) && rows.length === 0, `${rest.status} ${JSON.stringify(rows).slice(0, 80)}`);
  const fn = await fetch(`${SUPABASE}/functions/v1/search-items`, { method: 'POST', headers: { apikey: ANON, Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' }, body: '{"limit":1}' });
  ok('fence: search-items refuses agent token', fn.status === 401 || fn.status === 403, String(fn.status));
  const add = await fetch(`${SUPABASE}/functions/v1/add-note`, { method: 'POST', headers: { apikey: ANON, Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' }, body: '{"content":"smoke"}' });
  ok('fence: add-note refuses agent token', add.status === 403, String(add.status));
}

const token = REUSE ? JSON.parse(readFileSync(STATE_FILE, 'utf8')).access_token : await oauth();
if (REUSE) {
  const ping = await rpc(token, 1, 'ping');
  console.log(`reuse: ping → ${ping.status} ${JSON.stringify(ping.body)} ${ping.www ?? ''}`);
}
await tools(token);
await fence(token);
