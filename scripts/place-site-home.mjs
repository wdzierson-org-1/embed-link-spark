#!/usr/bin/env node
/**
 * After `vite build`: make gostash.it/ the marketing homepage. On Vercel a file beats a rewrite,
 * so whatever sits at dist/index.html is what / serves. The app shell moves to dist/app.html
 * (vercel.json rewrites every route that isn't a file to it), and the published homepage
 * (public/site/home.html, from scripts/publish-site.mjs) takes dist/index.html. Fails the build if
 * either is missing, rather than shipping a site whose / is the wrong page.
 */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const dist = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', 'dist');
const shell = path.join(dist, 'index.html');
const app = path.join(dist, 'app.html');
const home = path.join(dist, 'site', 'home.html');

const fail = (message) => {
  console.error(`place-site-home: ${message}`);
  process.exit(1);
};

if (!fs.existsSync(shell)) fail('dist/index.html (the app shell vite builds) is missing');
if (!fs.existsSync(home)) fail('dist/site/home.html is missing: run node scripts/publish-site.mjs and commit public/site');
if (!fs.readFileSync(shell, 'utf8').includes('id="root"')) fail('dist/index.html is not the app shell; was this run twice?');

fs.renameSync(shell, app);
fs.copyFileSync(home, shell);
console.log('place-site-home: dist/index.html is the homepage; dist/app.html is the app shell');
