import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, writeFile, rm, readFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { loadConfig, childEnvironment } from './config.mjs';
import { runHermes } from './runner.mjs';

test('audit configuration explicitly disables all tools', async () => {
 const template = await readFile(new URL('./hermes-config.yaml', import.meta.url), 'utf8');
 assert.match(template, /disabled_toolsets:\s*(?:\[all\]|- all)(?:\n|$)/);
});
test('audit provider selects the chat-completions protocol supported by its proxy', async () => {
 const template = await readFile(new URL('./hermes-config.yaml', import.meta.url), 'utf8');
 assert.match(template, /model:\s*\n\s+provider: openai-api\s*\n\s+api_mode: chat_completions/);
});

const job = () => ({ id: '22222222-2222-4222-8222-222222222222', kind: 'audit', lease_token: '33333333-3333-4333-8333-333333333333', fence: 1,
 input: { schema_version: 1, items: [] }, budget: { max_turns: 6, run_seconds: 90 }, deadline_at: new Date(Date.now() + 90_000).toISOString() });
const env = () => ({ NODE_ENV: 'production', QUALITY_API_URL: 'https://project.supabase.co/functions/v1/quality-worker',
 QUALITY_WORKER_TOKEN: 'w'.repeat(40), QUALITY_WAKE_TOKEN: 'a'.repeat(40), QUALITY_MODEL_BASE_URL: 'https://project.supabase.co/functions/v1/quality-model',
 HERMES_MODEL: 'test-model', HERMES_UID: '1001', HERMES_GID: '1001', HERMES_EXECUTABLE: '/opt/stash/hermes/.venv/bin/hermes',
 HERMES_CONFIG_TEMPLATE: '/etc/stash-quality/hermes-config.yaml', QUALITY_JOBS_DIR: '/var/lib/stash-quality/jobs' });
test('production readiness fails closed without isolated UID or configured proxy', () => {
 assert.equal(loadConfig(env(), 0).ready, true);
 const e = env(); delete e.HERMES_UID; assert.equal(loadConfig(e, 0).ready, false);
 assert.equal(loadConfig({ ...env(), HERMES_UID: '0' }, 0).ready, false);
 assert.equal(loadConfig(env(), 1001).ready, false);
 assert.equal(loadConfig({ ...env(), QUALITY_MODEL_BASE_URL: '' }, 0).ready, false);
 assert.equal(loadConfig({ ...env(), QUALITY_MODEL_BASE_URL: 'https://user:secret@example.com/x' }, 0).ready, false);
 const implicit = env(); delete implicit.NODE_ENV; delete implicit.HERMES_UID;
 assert.equal(loadConfig(implicit, 0).ready, false);
});
test('child environment contains only per-job model capability and no supervisor credentials', () => {
 const e = env(); e.FLY_API_TOKEN = 'fly-secret'; e.SUPABASE_SERVICE_ROLE_KEY = 'service-secret'; e.OPENAI_API_KEY = 'standing-provider-secret';
 const c = loadConfig(e, 0); const j = job(); const child = childEnvironment(c, j, '/workspace/job');
 assert.equal(child.OPENAI_API_KEY, j.lease_token);
 assert.equal(child.OPENAI_BASE_URL, `${e.QUALITY_MODEL_BASE_URL}/${j.id}/1/v1`);
 assert.equal(child.HERMES_HOME, '/workspace/job/profile');
 assert.equal(child.HOME, '/workspace/job/home');
 assert.ok(!JSON.stringify(child).includes('secret'));
 assert.equal(child.QUALITY_WORKER_TOKEN, undefined);
 assert.equal(child.QUALITY_WAKE_TOKEN, undefined);
});
async function fixture(t, body) {
 const dir = await mkdtemp(join(tmpdir(), 'stash-hermes-test-'));
 t.after(() => rm(dir, { recursive: true, force: true }));
 const executable = join(dir, 'fake-hermes');
 await writeFile(executable, `#!${process.execPath}\n${body}`, { mode: 0o755 });
 const template = join(dir, 'config.yaml'); await writeFile(template, 'memory:\n  memory_enabled: false\n');
 return { ready: true, production: false, executable, configTemplate: template, jobsDir: dir, model: 'test-model', modelBaseUrl: 'https://project.supabase.co/functions/v1/quality-model' };
}
test('one-shot process receives bounded flags, stdin prompt, clean home and structured result', async t => {
 const c = await fixture(t, `let prompt='';process.stdin.on('data',x=>prompt+=x);process.stdin.on('end',()=>{if(!prompt.includes('untrusted')||!process.argv.includes('--oneshot')||process.argv[process.argv.indexOf('--toolsets')+1]!=='all')process.exit(2);console.log(JSON.stringify({type:'result',exit_code:0,text:JSON.stringify({schema_version:1,summary:'No evidence of a defect.',findings:[],proposals:[],uncertainties:[]}),tokens:{input:3,output:4}}));});`);
 const output = await runHermes(c, job(), { maxTurns: 6, runMs: 1000 });
 assert.equal(output.result.summary, 'No evidence of a defect.'); assert.equal(output.usage.input_tokens, 3);
 const { readdir } = await import('node:fs/promises'); assert.deepEqual((await readdir(c.jobsDir)).sort(), ['config.yaml', 'fake-hermes']);
});
test('outer timeout kills a hanging child and cleans its per-job directory', async t => {
 const c = await fixture(t, `process.stdin.resume();setInterval(()=>{},1000);`);
 const start = Date.now();
 await assert.rejects(runHermes(c, job(), { maxTurns: 6, runMs: 60 }), /run_timeout/);
 assert.ok(Date.now() - start < 3000);
});
test('lease cancellation terminates the child without waiting for model response', async t => {
 const c = await fixture(t, `process.stdin.resume();setInterval(()=>{},1000);`);
 const controller = new AbortController(); setTimeout(() => controller.abort(new Error('lease_lost')), 50);
 await assert.rejects(runHermes(c, job(), { maxTurns: 6, runMs: 5000, signal: controller.signal }), /lease_lost/);
});
test('malformed or excessive output is rejected without exposing content in the error', async t => {
 const c = await fixture(t, `process.stdin.resume();console.log('PRIVATE SOURCE');`);
 await assert.rejects(runHermes(c, job(), { maxTurns: 6, runMs: 1000 }), e => e.message === 'invalid_stream');
 const c2 = await fixture(t, `process.stdin.resume();process.stdout.write('x'.repeat(2100000));setInterval(()=>{},1000);`);
 await assert.rejects(runHermes(c2, job(), { maxTurns: 6, runMs: 1000 }), /output_limit/);
});
