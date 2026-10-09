import { createServer as httpServer } from 'node:http';
import { pathToFileURL } from 'node:url';
import { lstat, access } from 'node:fs/promises';
import { constants } from 'node:fs';
import { authorized } from './protocol.mjs';
import { loadConfig } from './config.mjs';
import { createSupervisor } from './supervisor.mjs';
import { acquireSingleton, cleanupStaleWorkspaces } from './startup.mjs';

function reply(res, status, value) {
  if (res.destroyed) return;
  res.writeHead(status, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' }); res.end(JSON.stringify(value));
}
export function createServer(config, supervisor) {
  const server = httpServer({ requestTimeout: 5000, headersTimeout: 5000 }, async (req, res) => {
    if (req.method === 'GET' && req.url === '/health') return reply(res, config.ready ? 200 : 503,
      { ok: config.ready, ready: config.ready, busy: supervisor.busy, mode: 'evidence_review' });
    if (req.method !== 'POST' || req.url !== '/run') return reply(res, 404, { error: 'not_found' });
    if (!authorized(req.headers.authorization, config.wakeToken)) { req.resume(); return reply(res, 401, { error: 'unauthorized' }); }
    if (!config.ready) { req.resume(); return reply(res, 503, { error: 'unconfigured' }); }
    // Wake requests carry no prompts or job IDs; all work comes from the backend.
    let size = 0;
    try { for await (const chunk of req) { size += chunk.length; if (size > 1024) return reply(res, 413, { error: 'body_too_large' }); } }
    catch { return; }
    const disconnected = () => { if (!res.writableEnded) supervisor.cancel('client_disconnected'); };
    // A rejected parallel wake must not gain cancellation control of the active job.
    if (supervisor.busy) return reply(res, 409, { error: 'busy' });
    res.on('close', disconnected);
    try {
      const outcome = await supervisor.runOnce();
      const status = outcome.status === 'busy' ? 409 : ['failed', 'completion_unconfirmed', 'lease_lost'].includes(outcome.status) ? 503 : outcome.status === 'unconfigured' ? 503 : 200;
      reply(res, status, { ok: status === 200, ...outcome });
    } catch { reply(res, 503, { error: 'worker_failed' }); }
    finally { res.off('close', disconnected); }
  });
  server.timeout = 100_000;
  return server;
}

export async function preflight(config) {
  if (!config.ready) return;
  try {
    await access(config.executable, constants.X_OK);
    const [template, jobs] = await Promise.all([lstat(config.configTemplate), lstat(config.jobsDir)]);
    if (!template.isFile() || !jobs.isDirectory() || template.isSymbolicLink() || jobs.isSymbolicLink()) throw new Error('invalid_paths');
    if (config.production && (template.uid !== 0 || (template.mode & 0o022) || jobs.uid !== 0 || (jobs.mode & 0o022))) throw new Error('unsafe_paths');
  } catch { config.ready = false; config.issues.push('runtime_unconfigured'); }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const config = loadConfig();
  if (config.production && process.getuid?.() === 0) process.setgroups([]);
  await preflight(config);
  let release;
  if (config.ready) {
    try {
      release = await acquireSingleton(config);
      await cleanupStaleWorkspaces(config);
      process.once('exit', release);
    } catch {
      release?.(); config.ready = false; config.issues.push('startup_recovery_required');
    }
  }
  const supervisor = createSupervisor(config); const server = createServer(config, supervisor);
  server.listen(config.port, '0.0.0.0', () => console.log(JSON.stringify({ event: 'quality_agent_started', ready: config.ready, mode: 'evidence_review' })));
  for (const signal of ['SIGTERM', 'SIGINT']) process.on(signal, () => { supervisor.cancel('shutdown'); server.close(); setTimeout(() => process.exit(0), 5000).unref(); });
}
