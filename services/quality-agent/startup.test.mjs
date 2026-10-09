import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, mkdir, writeFile, readdir, rm, symlink } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { cleanupStaleWorkspaces, acquireSingleton } from './startup.mjs';

async function fixture(t) {
 const dir = await mkdtemp(join(tmpdir(), 'stash-startup-'));
 t.after(() => rm(dir, { recursive: true, force: true }));
 return { jobsDir: dir, production: false, uid: process.getuid() };
}
test('startup deletes only matching owned attempt directories and never follows symlinks', async t => {
 const c = await fixture(t);
 await mkdir(join(c.jobsDir, 'attempt-abc123')); await writeFile(join(c.jobsDir, 'attempt-abc123', 'source'), 'private');
 await mkdir(join(c.jobsDir, 'keep')); await writeFile(join(c.jobsDir, 'keep', 'source'), 'keep');
 await symlink(join(c.jobsDir, 'keep'), join(c.jobsDir, 'attempt-def456'));
 assert.equal(await cleanupStaleWorkspaces(c, async () => false), 1);
 assert.deepEqual((await readdir(c.jobsDir)).sort(), ['attempt-def456', 'keep']);
});
test('an active child or mismatched UID prevents stale directory deletion', async t => {
 const c = await fixture(t); await mkdir(join(c.jobsDir, 'attempt-abc123'));
 await assert.rejects(cleanupStaleWorkspaces(c, async () => true), /orphan_child_present/);
 assert.equal(await cleanupStaleWorkspaces({ ...c, uid: c.uid + 1 }, async () => false), 0);
 assert.deepEqual(await readdir(c.jobsDir), ['attempt-abc123']);
});
test('singleton lock refuses a live owner and is released explicitly', async t => {
 const c = await fixture(t); const release = await acquireSingleton(c);
 await assert.rejects(acquireSingleton(c), /supervisor_already_running/);
 release(); const releaseAgain = await acquireSingleton(c); releaseAgain();
 assert.deepEqual(await readdir(c.jobsDir), []);
});
