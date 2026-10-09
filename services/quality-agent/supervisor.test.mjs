import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createSupervisor } from './supervisor.mjs';
import { createServer } from './server.mjs';

const config = { ready: true, wakeToken: 'w'.repeat(40), model: 'test-model' };
const job = () => ({ id: '22222222-2222-4222-8222-222222222222', kind: 'audit', input_hash: 'abc', input: { schema_version: 1, items: [] },
 lease_token: '33333333-3333-4333-8333-333333333333', fence: 1, lease_expires_at: new Date(Date.now() + 60_000).toISOString(),
 deadline_at: new Date(Date.now() + 90_000).toISOString(), budget: { max_turns: 6, run_seconds: 90 } });
const output = { result: { schema_version: 1, summary: 'No issue found.', findings: [], proposals: [], uncertainties: [] }, usage: { input_tokens: 1 } };
test('one held run serializes claims and an idle claim releases the lock', async () => {
 let release; const pending = new Promise(r => { release = r; }); let claims = 0;
 const s = createSupervisor(config, { call: async body => { if (body.action === 'claim') { claims++; await pending; return { job: null }; } } });
 const first = s.runOnce();
 assert.equal(s.busy, true); assert.equal((await s.runOnce()).status, 'busy'); assert.equal(claims, 1);
 release(); assert.equal((await first).status, 'idle'); assert.equal(s.busy, false);
});
test('a lost completion response is retried with exactly the same payload', async () => {
 const completions = [];
 const s = createSupervisor(config, { run: async () => output, retryDelayMs: 1, call: async body => {
  if (body.action === 'claim') return { job: job() };
  if (body.action === 'complete') { completions.push(JSON.stringify(body)); if (completions.length === 1) throw Object.assign(new Error('network_error'), { retryable: true }); return { ok: true, status: 'completed', idempotent: true }; }
  throw new Error('unexpected_action');
 } });
 assert.equal((await s.runOnce()).status, 'completed'); assert.equal(completions.length, 2); assert.equal(completions[0], completions[1]);
});
test('heartbeat409 cancels the running model and prevents completion/failure writes', async () => {
 const actions = []; let cancelled = false;
 const s = createSupervisor(config, { heartbeatMs: 10, call: async body => {
  actions.push(body.action); if (body.action === 'claim') return { job: job() };
  if (body.action === 'heartbeat') throw Object.assign(new Error('lease_lost'), { status: 409 });
 }, run: (_c, _j, { signal }) => new Promise((_resolve, reject) => signal.addEventListener('abort', () => { cancelled = true; reject(signal.reason); }, { once: true })) });
 assert.equal((await s.runOnce()).status, 'lease_lost'); assert.equal(cancelled, true); assert.deepEqual(actions, ['claim', 'heartbeat']);
});
test('failure sends a safe reason and releases lock; unknown completion stays uncertain', async () => {
 const bodies = [];
 const s = createSupervisor(config, { run: async () => { throw new Error('PRIVATE SOURCE'); }, call: async body => {
  bodies.push(body); if (body.action === 'claim') return { job: job() }; return { ok: true, status: 'queued' };
 } });
 assert.equal((await s.runOnce()).status, 'failed'); assert.equal(bodies.at(-1).reason, 'runner_failed'); assert.equal(s.busy, false);
 const uncertain = createSupervisor(config, { retryDelayMs: 1, run: async () => output, call: async body => {
  if (body.action === 'claim') return { job: job() };
  if (body.action === 'fail') assert.fail('must not contradict a possibly successful completion');
  throw Object.assign(new Error('network_error'), { retryable: true });
 } });
 assert.equal((await uncertain.runOnce()).status, 'completion_unconfirmed');
});
test('HTTP service redacts health, rejects unauthorized wake and holds authorized response', async t => {
 let release; const pending = new Promise(r => { release = r; });
 const s = createSupervisor(config, { call: async () => { await pending; return { job: null }; } });
 const server = createServer(config, s); await new Promise(r => server.listen(0, '127.0.0.1', r));
 t.after(() => new Promise(r => server.close(r))); const url = `http://127.0.0.1:${server.address().port}`;
 const health = await fetch(`${url}/health`); assert.deepEqual(await health.json(), { ok: true, ready: true, busy: false, mode: 'audit_only' });
 assert.equal((await fetch(`${url}/run`, { method: 'POST' })).status, 401);
 let resolved = false; const first = fetch(`${url}/run`, { method: 'POST', headers: { Authorization: `Bearer ${config.wakeToken}` } }).then(r => { resolved = true; return r; });
 await new Promise(r => setTimeout(r, 25)); assert.equal(resolved, false);
 assert.equal((await fetch(`${url}/run`, { method: 'POST', headers: { Authorization: `Bearer ${config.wakeToken}` } })).status, 409);
 release(); assert.equal((await first).status, 200);
});
test('unconfigured HTTP service cannot claim work', async t => {
 const c = { ...config, ready: false }; const server = createServer(c, { busy: false, runOnce: () => assert.fail('no claim') });
 await new Promise(r => server.listen(0, '127.0.0.1', r)); t.after(() => new Promise(r => server.close(r)));
 const url = `http://127.0.0.1:${server.address().port}`;
 assert.equal((await fetch(`${url}/health`)).status, 503);
 assert.equal((await fetch(`${url}/run`, { method: 'POST', headers: { Authorization: `Bearer ${c.wakeToken}` } })).status, 503);
});
