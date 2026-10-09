import { readdir, readFile, lstat, rm, open, unlink } from 'node:fs/promises';
import { lstatSync, unlinkSync } from 'node:fs';
import { join } from 'node:path';

async function checkParent(config) {
  const stat = await lstat(config.jobsDir);
  if (!stat.isDirectory() || stat.isSymbolicLink() || (config.production && (stat.uid !== 0 || (stat.mode & 0o022)))) throw new Error('unsafe_jobs_directory');
}
async function hasActiveChild(uid) {
  // A dedicated UID is required: surviving child processes make cleanup unsafe.
  for (const pid of await readdir('/proc')) {
    if (!/^\d+$/.test(pid)) continue;
    try {
      const status = await readFile(`/proc/${pid}/status`, 'utf8');
      const ids = status.match(/^Uid:\s+(.+)$/m)?.[1].trim().split(/\s+/).map(Number);
      if (ids?.includes(uid)) return true;
    } catch (error) { if (error.code !== 'ENOENT' && error.code !== 'ESRCH') throw error; }
  }
  return false;
}
export async function cleanupStaleWorkspaces(config, activeChild = hasActiveChild) {
  await checkParent(config);
  if (!Number.isSafeInteger(config.uid) || config.uid < 0 || (config.production && config.uid === 0)) throw new Error('invalid_child_uid');
  if (await activeChild(config.uid)) throw new Error('orphan_child_present');
  let count = 0;
  for (const name of await readdir(config.jobsDir)) {
    if (!/^attempt-[a-zA-Z0-9]{6}$/.test(name)) continue;
    const path = join(config.jobsDir, name); const stat = await lstat(path);
    if (!stat.isDirectory() || stat.isSymbolicLink() || stat.uid !== config.uid) continue;
    await rm(path, { recursive: true }); count++;
  }
  return count;
}

// The Sprite service is the sole managed instance. This additional PID guard
// rejects accidental double starts before startup cleanup touches workspaces.
export async function acquireSingleton(config) {
  await checkParent(config);
  const path = join(config.jobsDir, '.supervisor.lock');
  for (let attempt = 0; attempt < 2; attempt++) {
    try {
      const handle = await open(path, 'wx', 0o600);
      try { await handle.writeFile(String(process.pid)); } finally { await handle.close(); }
      const owned = await lstat(path); let released = false;
      return () => {
        if (released) return; released = true;
        try { const current = lstatSync(path); if (current.ino === owned.ino && current.dev === owned.dev) unlinkSync(path); } catch (error) { if (error.code !== 'ENOENT') throw error; }
      };
    } catch (error) {
      if (error.code !== 'EEXIST') throw error;
      const stat = await lstat(path);
      if (!stat.isFile() || stat.isSymbolicLink() || stat.size > 32 || stat.uid !== process.getuid()) throw new Error('unsafe_supervisor_lock');
      const owner = await readFile(path, 'utf8');
      if (!/^[1-9]\d*$/.test(owner)) throw new Error('unsafe_supervisor_lock');
      try { process.kill(Number(owner), 0); throw new Error('supervisor_already_running'); }
      catch (probe) { if (probe.code !== 'ESRCH') throw probe; }
      const current = await lstat(path);
      if (current.ino !== stat.ino || current.dev !== stat.dev) throw new Error('supervisor_already_running');
      await unlink(path);
    }
  }
  throw new Error('supervisor_already_running');
}
