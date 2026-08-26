// Auth + Stash platform API calls (docs/PLATFORM_API.md). No dependencies:
// auth uses the raw GoTrue REST endpoints the platform doc sanctions, and the
// session lives in chrome.storage.local so it survives service-worker sleeps.

import {
  MAX_IMAGE_MB,
  extForMime,
  resolveImageMime,
  sessionIsFresh,
  storageName,
} from './lib.js';

// Same project + publishable key as src/integrations/supabase/client.ts.
const SUPABASE_URL = 'https://uqqsgmwkvslaomzxptnp.supabase.co';
const ANON_KEY =
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVxcXNnbXdrdnNsYW9tenhwdG5wIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTA2MjU0ODcsImV4cCI6MjA2NjIwMTQ4N30.vGWb1EdshtLFLpUHQ54Vy2CDmuPVCTbvc8UYW6_cvmE';

export class NotSignedInError extends Error {}

async function getStored() {
  const { session } = await chrome.storage.local.get('session');
  return session ?? null;
}

async function setStored(session) {
  await chrome.storage.local.set({ session });
}

export async function clearSession() {
  await chrome.storage.local.remove('session');
}

/** For the sign-in page: who's signed in, or null. */
export async function getSessionInfo() {
  const session = await getStored();
  return session ? { email: session.email, userId: session.user_id } : null;
}

function toStoredSession(tokenResponse) {
  return {
    access_token: tokenResponse.access_token,
    refresh_token: tokenResponse.refresh_token,
    expires_at:
      tokenResponse.expires_at ??
      Math.floor(Date.now() / 1000) + (tokenResponse.expires_in ?? 3600),
    user_id: tokenResponse.user?.id,
    email: tokenResponse.user?.email,
  };
}

async function tokenRequest(query, body) {
  const res = await fetch(`${SUPABASE_URL}/auth/v1/token?${query}`, {
    method: 'POST',
    headers: { apikey: ANON_KEY, 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
  const data = await res.json().catch(() => ({}));
  return { ok: res.ok, status: res.status, data };
}

export async function signIn(email, password) {
  const { ok, status, data } = await tokenRequest('grant_type=password', { email, password });
  if (!ok) {
    throw new Error(data.error_description || data.msg || `Sign-in failed (${status})`);
  }
  await setStored(toStoredSession(data));
}

// Single-flight: concurrent saves waking a stale session share one refresh so
// the (single-use) refresh token is only spent once.
let refreshInFlight = null;

function refresh() {
  refreshInFlight ??= doRefresh().finally(() => {
    refreshInFlight = null;
  });
  return refreshInFlight;
}

async function doRefresh() {
  const session = await getStored(); // re-read: another caller may have rotated it
  if (!session?.refresh_token) throw new NotSignedInError('Not signed in');
  const { ok, data } = await tokenRequest('grant_type=refresh_token', {
    refresh_token: session.refresh_token,
  });
  if (!ok) {
    await clearSession();
    throw new NotSignedInError('Session expired — sign in again');
  }
  const next = toStoredSession(data);
  // Refresh responses may omit the user object; keep what we knew.
  next.user_id ??= session.user_id;
  next.email ??= session.email;
  await setStored(next);
  return next;
}

async function requireSession() {
  const session = await getStored();
  if (!session?.refresh_token) throw new NotSignedInError('Not signed in');
  if (sessionIsFresh(session, Math.floor(Date.now() / 1000))) return session;
  return refresh();
}

async function callFn(name, body, session, retried = false) {
  const res = await fetch(`${SUPABASE_URL}/functions/v1/${name}`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${session.access_token}`,
      apikey: ANON_KEY,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(body),
  });
  if (res.status === 401 && !retried) {
    return callFn(name, body, await refresh(), true);
  }
  if (!res.ok) {
    const text = await res.text().catch(() => '');
    throw new Error(`${name} failed (${res.status}): ${text.slice(0, 300)}`);
  }
  return res.json();
}

/** Toolbar button: save the current page as a link item. */
export async function stashUrl(url) {
  return callFn('add-url', { url }, await requireSession());
}

/** "Stash it" on a selection: save the selected text as a note item. */
export async function stashNote(content) {
  return callFn('add-note', { content }, await requireSession());
}

/** "Stash it" on an image: fetch the bytes, upload to Storage, add-file. */
export async function stashImage(srcUrl) {
  const session = await requireSession();

  const res = await fetch(srcUrl, { credentials: 'include' });
  if (!res.ok) throw new Error(`Image fetch failed (${res.status})`);
  const blob = await res.blob();
  if (blob.size === 0) throw new Error('Image fetch returned no data');
  if (blob.size > MAX_IMAGE_MB * 1024 * 1024) {
    throw new Error(`Image is ${(blob.size / 1048576).toFixed(1)}MB — max ${MAX_IMAGE_MB}MB`);
  }

  const mime = resolveImageMime(srcUrl, res.headers.get('content-type'));
  if (!mime) throw new Error('Could not determine image type');

  const path = `${session.user_id}/${storageName(Date.now(), extForMime(mime))}`;
  const upload = await fetch(`${SUPABASE_URL}/storage/v1/object/stash-media/${path}`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${session.access_token}`,
      apikey: ANON_KEY,
      'Content-Type': mime,
    },
    body: blob,
  });
  if (!upload.ok) {
    const text = await upload.text().catch(() => '');
    throw new Error(`Upload failed (${upload.status}): ${text.slice(0, 200)}`);
  }

  return callFn(
    'add-file',
    { file_path: path, mime_type: mime, file_size: blob.size },
    session,
  );
}
