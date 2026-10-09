import { isAbsolute, dirname, join } from 'node:path';

function endpoint(value) {
  try {
    const u = new URL(value);
    return u.protocol === 'https:' && !u.username && !u.password && !u.search && !u.hash && (!u.port || u.port === '443');
  } catch { return false; }
}
export function loadConfig(env = process.env, parentUid = process.getuid?.()) {
  const issues = [];
  const production = env.NODE_ENV !== 'test';
  const uid = Number(env.HERMES_UID); const gid = Number(env.HERMES_GID);
  if (!endpoint(env.QUALITY_API_URL)) issues.push('api_url_unconfigured');
  if (!endpoint(env.QUALITY_MODEL_BASE_URL)) issues.push('model_proxy_unconfigured');
  for (const key of ['QUALITY_WORKER_TOKEN', 'QUALITY_WAKE_TOKEN']) if (!env[key] || env[key].length < 32 || env[key].length > 256) issues.push(`${key.toLowerCase()}_unconfigured`);
  if (!env.HERMES_MODEL || env.HERMES_MODEL.length > 100 || /[\r\n]/.test(env.HERMES_MODEL)) issues.push('model_unconfigured');
  for (const key of ['HERMES_EXECUTABLE', 'HERMES_CONFIG_TEMPLATE', 'QUALITY_JOBS_DIR']) if (!env[key] || !isAbsolute(env[key])) issues.push(`${key.toLowerCase()}_unconfigured`);
  if (production && (parentUid !== 0 || !Number.isSafeInteger(uid) || uid <= 0 || uid === parentUid || !Number.isSafeInteger(gid) || gid <= 0)) issues.push('uid_isolation_unconfigured');
  const port = Number(env.PORT || 8080);
  if (!Number.isInteger(port) || port < 1 || port > 65535) issues.push('invalid_port');
  return { ready: issues.length === 0, issues, production, uid, gid, port,
    apiUrl: env.QUALITY_API_URL, workerToken: env.QUALITY_WORKER_TOKEN, wakeToken: env.QUALITY_WAKE_TOKEN,
    modelBaseUrl: env.QUALITY_MODEL_BASE_URL?.replace(/\/+$/, ''), model: env.HERMES_MODEL,
    executable: env.HERMES_EXECUTABLE, configTemplate: env.HERMES_CONFIG_TEMPLATE, jobsDir: env.QUALITY_JOBS_DIR };
}

// Deliberately do not spread process.env. The only credential crossing the UID
// boundary is a short-lived lease token accepted by the bounded model proxy.
export function childEnvironment(config, job, workspace) {
  return {
    PATH: `${dirname(config.executable)}:/usr/local/bin:/usr/bin:/bin`, LANG: 'C.UTF-8', LC_ALL: 'C.UTF-8', TERM: 'dumb',
    HOME: join(workspace, 'home'), HERMES_HOME: join(workspace, 'profile'), TMPDIR: join(workspace, 'tmp'),
    XDG_CACHE_HOME: join(workspace, 'cache'), XDG_CONFIG_HOME: join(workspace, 'config'),
    PYTHONUNBUFFERED: '1', PYTHONNOUSERSITE: '1', HERMES_SIGTERM_GRACE: '1',
    OPENAI_API_KEY: job.lease_token, OPENAI_BASE_URL: `${config.modelBaseUrl}/${job.id}/${job.fence}/v1`,
  };
}
