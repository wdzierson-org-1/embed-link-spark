#!/usr/bin/env node
/**
 * Render the social card (brand/og-src.html, 1200x630) to public/og-v2.jpg with headless Chrome,
 * the way brand/build.mjs renders the icons. The site's pages and the app shell name it in their
 * og:image tags; bump the file name when the card changes, because social networks cache by URL.
 *
 *   node scripts/render-og.mjs
 */
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const chrome = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const source = path.join(root, 'brand', 'og-src.html');
const png = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'og-')), 'og.png');
const out = path.join(root, 'public', 'og-v2.jpg');

execFileSync(chrome, [
  '--headless=new', '--disable-gpu', '--hide-scrollbars', '--allow-file-access-from-files',
  '--virtual-time-budget=4000', '--force-device-scale-factor=1', '--window-size=1200,630',
  `--screenshot=${png}`, `file://${source}`,
], { stdio: 'ignore' });
execFileSync('sips', ['-s', 'format', 'jpeg', '-s', 'formatOptions', '86', png, '--out', out], { stdio: 'ignore' });
console.log(`render-og: wrote ${path.relative(root, out)} (${Math.round(fs.statSync(out).size / 1024)} KB)`);
