import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  cleanMime,
  dataUrlMime,
  displayNameFromUrl,
  urlExt,
  resolveImageMime,
  extForMime,
  isStashableUrl,
  storageName,
  sessionIsFresh,
} from '../lib.js';

test('cleanMime strips parameters and normalizes case', () => {
  assert.equal(cleanMime('image/JPEG; charset=utf-8'), 'image/jpeg');
  assert.equal(cleanMime('image/png'), 'image/png');
  assert.equal(cleanMime(''), null);
  assert.equal(cleanMime(null), null);
});

test('dataUrlMime reads data: URLs only', () => {
  assert.equal(dataUrlMime('data:image/png;base64,iVBOR'), 'image/png');
  assert.equal(dataUrlMime('data:image/svg+xml,<svg/>'), 'image/svg+xml');
  assert.equal(dataUrlMime('https://x.com/a.png'), null);
});

test('urlExt handles queries, hashes, and missing extensions', () => {
  assert.equal(urlExt('https://cdn.x.com/photos/IMG_1.JPG?w=800#frag'), 'jpg');
  assert.equal(urlExt('https://x.com/img'), null);
  assert.equal(urlExt('https://x.com/.hidden'), null);
  assert.equal(urlExt('https://x.com/file.'), null);
  assert.equal(urlExt('not a url'), null);
});

test('resolveImageMime: image/* header wins', () => {
  assert.equal(resolveImageMime('https://x.com/a.png', 'image/webp'), 'image/webp');
});

test('resolveImageMime: data URL declaration wins over everything', () => {
  assert.equal(resolveImageMime('data:image/gif;base64,R0lGOD', 'text/plain'), 'image/gif');
});

test('resolveImageMime: generic header falls back to URL extension', () => {
  assert.equal(resolveImageMime('https://x.com/a.jpeg?s=1', 'application/octet-stream'), 'image/jpeg');
  assert.equal(resolveImageMime('https://x.com/a.webp', null), 'image/webp');
});

test('resolveImageMime: non-image header is a hard failure (CDN error pages)', () => {
  assert.equal(resolveImageMime('https://x.com/a.jpg', 'text/html; charset=utf-8'), null);
  assert.equal(resolveImageMime('https://x.com/a.jpg', 'text/plain'), null);
});

test('resolveImageMime: no signal at all fails', () => {
  assert.equal(resolveImageMime('https://x.com/image', null), null);
});

test('extForMime maps known types and derives unknown ones', () => {
  assert.equal(extForMime('image/jpeg'), 'jpg');
  assert.equal(extForMime('image/svg+xml'), 'svg');
  assert.equal(extForMime('image/jxl'), 'jxl');
  assert.equal(extForMime(undefined), 'img');
});

test('isStashableUrl accepts only http(s)', () => {
  assert.equal(isStashableUrl('https://gostash.it'), true);
  assert.equal(isStashableUrl('http://localhost:8080/page'), true);
  assert.equal(isStashableUrl('chrome://extensions'), false);
  assert.equal(isStashableUrl('about:blank'), false);
  assert.equal(isStashableUrl('file:///tmp/a.html'), false);
  assert.equal(isStashableUrl('data:text/html,<p>'), false);
  assert.equal(isStashableUrl(undefined), false);
});

test('displayNameFromUrl keeps real image filenames', () => {
  assert.equal(displayNameFromUrl('https://cdn.x.com/photos/golden%20gate.jpg?w=800'), 'golden gate.jpg');
  assert.equal(displayNameFromUrl('https://x.com/IMG_2041.HEIC'), 'IMG_2041.HEIC');
});

test('displayNameFromUrl synthesizes a name from the path + resolved format', () => {
  assert.equal(displayNameFromUrl('https://x.com/render.php', 'jpg'), 'render.jpg');
  assert.equal(displayNameFromUrl('https://x.com/image', 'webp'), 'image.webp');
  assert.equal(displayNameFromUrl('https://cdn.x.com/photo-14556789?auto=format', 'avif'), 'photo-14556789.avif');
  // Root path: hostname is the only name the URL offers
  assert.equal(displayNameFromUrl('https://www.x.com/a/', 'png'), 'x.com.png');
});

test('displayNameFromUrl still returns null when it has nothing to name', () => {
  assert.equal(displayNameFromUrl('https://x.com/render.php'), null); // no fallback ext
  assert.equal(displayNameFromUrl('https://x.com/image'), null);
  assert.equal(displayNameFromUrl('data:image/png;base64,iVBOR', 'png'), null);
  assert.equal(displayNameFromUrl('https://x.com/a/'), null);
});

test('storageName matches the web app convention', () => {
  assert.equal(storageName(1756200000000, 'png'), '1756200000000.png');
});

test('sessionIsFresh requires a token and >60s of life', () => {
  const now = 1_000_000;
  assert.equal(sessionIsFresh({ access_token: 't', expires_at: now + 120 }, now), true);
  assert.equal(sessionIsFresh({ access_token: 't', expires_at: now + 30 }, now), false);
  assert.equal(sessionIsFresh({ access_token: 't' }, now), false);
  assert.equal(sessionIsFresh(null, now), false);
  assert.equal(sessionIsFresh({ expires_at: now + 120 }, now), false);
});
