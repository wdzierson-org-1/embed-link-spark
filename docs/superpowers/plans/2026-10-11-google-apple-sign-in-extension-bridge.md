# Google and Apple sign-in — phase 2 (extension bridge) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The Chrome extension signs people in through gostash.it — Google, Apple or password, whatever the web way-in offers — and ends up with a session of its own.

**Architecture:** The extension opens `https://www.gostash.it/extension/connect`. Once signed in there, the page asks a new edge function (`extension-session`) for a one-time magic-link `token_hash`, hands it to the extension over `chrome.runtime.sendMessage` (allowed by the extension's `externally_connectable` for our origins only), and the extension's service worker redeems it at GoTrue's `/auth/v1/verify` — minting its **own** session, so a web tab and the extension never fight over refresh-token rotation. No `identity` permission, no provider secrets, no raw Supabase domain on any provider screen.

**Tech Stack:** Deno edge function (`https://esm.sh/@supabase/supabase-js@2.57.2`, `auth.admin.generateLink`), Chrome MV3 (`externally_connectable`, `onMessageExternal`, pinned `key`), plain-JS extension with `node --test`, Vite + React page in the app shell, vitest.

**Spec:** `docs/superpowers/specs/2026-10-11-google-apple-sign-in-design.md` (§0.4, §4.6 copy, §5.3 `extension-session`, §6.4 the connect page, §7 the extension, §9, §10). Phase 1 (`2026-10-11-google-apple-sign-in-web.md`) must have shipped: this plan assumes `AuthShell`, `useAuth().handle`, and the handle gate on `/auth`.

**Deviation from the spec:** `extension-session` returns `{ token_hash }` only — the function cannot read the project's OTP expiry, so the spec's `expires_in` would have been a guess. The page redeems the hash within seconds anyway.

## Global Constraints

- The web → extension message is `{ type: 'stash.session', token_hash: string }`; the reply is `{ ok: true, email: string | null }` or `{ ok: false, error: string }`. Both sides use exactly these shapes.
- The page sends only to the pinned extension id (`EXTENSION_ID` in `src/utils/extensionBridge.ts`); the extension accepts only senders whose origin is in `extension/bridge.js` `ALLOWED_ORIGINS` (`https://www.gostash.it`, `https://gostash.it`, `http://localhost:8080`).
- `extension-session` verifies with `admin.auth.getUser(token)`, refuses agent tokens (`isAgentToken`) and anonymous users, never emails anything, and never logs the hash.
- The extension stays dependency-free, no build step (`extension/README.md`); its tests are `node --test test/*.test.mjs`; the private key for the manifest `key` lives **outside the repo**.
- Copy verbatim from spec §4.6 (connect page: `stash://extension`, **The extension is connected.** / `> signed in as <email> — you can close this tab.`; **Install the extension first.**; **That didn't take.** / **Try again**; extension page: **Sign in at gostash.it** + "Sign in once in your browser — with Google, Apple or your email. The extension connects itself.").
- Deploys: `supabase functions deploy extension-session --project-ref uqqsgmwkvslaomzxptnp`; the web ships with `main`; the hosted zip via `cd extension && ./scripts/publish-hosted-zip.sh` then commit `public/stash-it-extension.zip`, `public/extension/index.html`, `public/extension/icon128.png`.
- The worktree Bash guard refuses loops, heredocs, `$(...)`, `awk`, `git -C` and variable-built paths — helper scripts go to `/tmp/pw/` via the Write tool and run as one plain command.

## Review Focus

1. **A stranger's page** — a message from `https://evil.example` (or a `sender` with no origin) must be ignored outright, never answered (Task 5 test "ignores other origins").
2. **A stranger's extension** — the page must address only `EXTENSION_ID`; another installed extension never receives the hash (Task 2 test "sends to the pinned id").
3. **A used or expired hash** — GoTrue's 4xx becomes `{ ok: false, error }` and the page offers **Try again**, which mints a fresh hash (Task 5 test "a refused verify fails closed"; Task 3 test "a failed handoff offers Try again").
4. **An anonymous try-stash session** — `extension-session` answers `403 { error: 'anonymous' }` and the page explains instead of looping (Task 1 test; Task 3 test "an anonymous session is sent to the way in").
5. **Not Chrome, or not installed** — no `chrome.runtime` means **Install the extension first.**, not a spinner (Task 3 test "says to install when no extension is listening").

---

### Task 1: `extension-session` — a one-time `token_hash` for the signed-in person

**Files:**
- Create: `supabase/functions/extension-session/index.ts`, `supabase/functions/extension-session/index.test.ts`
- Modify: `supabase/config.toml` (add `[functions.extension-session]` `verify_jwt = true` after `[functions.apple-token-exchange]`)

**Interfaces:**
- Produces: `POST /functions/v1/extension-session` (standard auth headers, no body) → `200 { token_hash }` | `401 { error }` | `403 { error: 'agent' | 'anonymous' }` | `500 { error }`.

- [ ] **Step 1: Write the failing test**

```ts
// supabase/functions/extension-session/index.test.ts
// @vitest-environment node
import { beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';

const state = vi.hoisted(() => ({
  handler: null as null | ((req: Request) => Promise<Response>),
  user: null as null | { id: string; email?: string; is_anonymous?: boolean },
  generateLink: vi.fn(),
}));

vi.mock('https://esm.sh/@supabase/supabase-js@2.57.2', () => ({
  createClient: () => ({
    auth: {
      getUser: async () => ({ data: { user: state.user }, error: state.user ? null : { message: 'nope' } }),
      admin: { generateLink: state.generateLink },
    },
  }),
}));

const b64url = (s: string) => btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
const jwt = (payload: Record<string, unknown>) => `${b64url('{"alg":"HS256"}')}.${b64url(JSON.stringify(payload))}.sig`;
const call = (token: string | null) =>
  state.handler!(new Request('https://x/extension-session', { method: 'POST', headers: token ? { Authorization: `Bearer ${token}` } : {} }));

beforeAll(async () => {
  vi.stubGlobal('Deno', { env: { get: () => 'x' }, serve: (h: typeof state.handler) => { state.handler = h; } });
  await import('./index.ts');
});

beforeEach(() => {
  state.user = { id: 'user-1', email: 'will@example.com' };
  state.generateLink.mockReset();
  state.generateLink.mockResolvedValue({ data: { properties: { hashed_token: 'hash-1' } }, error: null });
});

describe('extension-session', () => {
  it('mints a magic-link hash for the signed-in person without sending mail', async () => {
    const res = await call(jwt({ sub: 'user-1' }));
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ token_hash: 'hash-1' });
    expect(state.generateLink).toHaveBeenCalledWith({ type: 'magiclink', email: 'will@example.com' });
  });

  it('refuses no token, an agent token, a dead session, and an anonymous user', async () => {
    expect((await call(null)).status).toBe(401);
    expect((await call(jwt({ sub: 'user-1', client_id: 'agent' }))).status).toBe(403);
    state.user = null;
    expect((await call(jwt({ sub: 'user-1' }))).status).toBe(401);
    state.user = { id: 'anon', is_anonymous: true };
    const res = await call(jwt({ sub: 'anon' }));
    expect(res.status).toBe(403);
    expect(await res.json()).toEqual({ error: 'anonymous' });
    expect(state.generateLink).not.toHaveBeenCalled();
  });

  it('reports a GoTrue failure as 500', async () => {
    state.generateLink.mockResolvedValue({ data: null, error: { message: 'boom' } });
    const res = await call(jwt({ sub: 'user-1' }));
    expect(res.status).toBe(500);
    expect(await res.json()).toEqual({ error: 'boom' });
  });
});
```

- [ ] **Step 2: Run it to see it fail** — `npx vitest run supabase/functions/extension-session/index.test.ts` → FAIL (module missing).

- [ ] **Step 3: Write the function**

```ts
// supabase/functions/extension-session/index.ts
//
// The web → extension sign-in bridge (spec §5.3, §7). The signed-in page asks for a one-time
// magic-link token hash; it hands it to the Chrome extension, which redeems it at /auth/v1/verify
// and so gets a session of its own. Nothing is emailed; the hash is single-use and short-lived;
// the person must already hold a real (non-anonymous) session to ask.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.57.2";
import { isAgentToken } from "../_shared/agentToken.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};
const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, "Content-Type": "application/json" } });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });
  if (req.method !== "POST") return json(405, { error: "POST only" });

  const token = req.headers.get("Authorization")?.replace(/^Bearer\s+/i, "").trim();
  if (!token) return json(401, { error: "Missing authorization token" });
  if (isAgentToken(token)) return json(403, { error: "agent" });

  const admin = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    { auth: { persistSession: false } },
  );
  const { data: userData, error: userError } = await admin.auth.getUser(token);
  const user = userData?.user as { id: string; email?: string | null; is_anonymous?: boolean } | null | undefined;
  if (userError || !user) return json(401, { error: "Invalid or expired token" });
  if (user.is_anonymous || !user.email) return json(403, { error: "anonymous" });

  const { data, error } = await admin.auth.admin.generateLink({ type: "magiclink", email: user.email });
  const hash = data?.properties?.hashed_token;
  if (error || !hash) return json(500, { error: error?.message ?? "no token" });
  return json(200, { token_hash: hash });
});
```

- [ ] **Step 4: Run the test** — `npx vitest run supabase/functions/extension-session/index.test.ts` → 3 PASS.

- [ ] **Step 5: Register in `supabase/config.toml`**

```toml
# Web → extension sign-in handoff (plan 2026-10-11-google-apple-sign-in-extension-bridge Task 1).
[functions.extension-session]
verify_jwt = true
```

- [ ] **Step 6: Deploy and smoke** — `supabase functions deploy extension-session --project-ref uqqsgmwkvslaomzxptnp`, then with the uitest account's JWT (sign in via `POST /auth/v1/token?grant_type=password` with the anon key — the fixture credentials are in the auth-testing notes) `curl -s -X POST https://uqqsgmwkvslaomzxptnp.supabase.co/functions/v1/extension-session -H "apikey: <anon>" -H "Authorization: Bearer <jwt>"` → `{"token_hash":"…"}`; without the Authorization header → `401`.

- [ ] **Step 7: Commit**

```bash
git add supabase/functions/extension-session supabase/config.toml
git commit -m "feat(functions): extension-session mints a one-time hash for the extension bridge"
```

---

### Task 2: `extensionBridge.ts` — the page's half of the handoff

**Files:**
- Create: `src/utils/extensionBridge.ts`, `src/utils/extensionBridge.test.ts`

**Interfaces:**
- Produces: `EXTENSION_ID: string` (the id printed by Task 4's `extension/scripts/extension-id.mjs` — a 32-letter `a–p` string; set it in Task 4 Step 4), `extensionAvailable(): boolean`, `connectExtension(tokenHash: string, timeoutMs = 8000): Promise<{ ok: boolean; email?: string | null; error?: string }>`.

- [ ] **Step 1: Write the failing test**

```ts
// src/utils/extensionBridge.test.ts
import { EXTENSION_ID, connectExtension, extensionAvailable } from './extensionBridge';

type Cb = (reply: unknown) => void;
const chrome = { runtime: { lastError: undefined as undefined | { message: string }, sendMessage: vi.fn() } };

describe('extensionBridge', () => {
  beforeEach(() => {
    chrome.runtime.lastError = undefined;
    chrome.runtime.sendMessage.mockReset();
    (window as unknown as { chrome?: unknown }).chrome = chrome;
  });
  afterEach(() => { delete (window as unknown as { chrome?: unknown }).chrome; });

  it('knows when no extension is listening', () => {
    delete (window as unknown as { chrome?: unknown }).chrome;
    expect(extensionAvailable()).toBe(false);
  });

  it('sends to the pinned id and relays the reply', async () => {
    chrome.runtime.sendMessage.mockImplementation((_id: string, _msg: unknown, cb: Cb) => cb({ ok: true, email: 'will@example.com' }));
    await expect(connectExtension('hash-1')).resolves.toEqual({ ok: true, email: 'will@example.com' });
    expect(chrome.runtime.sendMessage).toHaveBeenCalledWith(EXTENSION_ID, { type: 'stash.session', token_hash: 'hash-1' }, expect.any(Function));
    expect(EXTENSION_ID).toMatch(/^[a-p]{32}$/);
  });

  it('turns a missing receiver into a failure', async () => {
    chrome.runtime.sendMessage.mockImplementation((_id: string, _msg: unknown, cb: Cb) => { chrome.runtime.lastError = { message: 'Could not establish connection' }; cb(undefined); });
    await expect(connectExtension('hash-1')).resolves.toEqual({ ok: false, error: 'Could not establish connection' });
  });

  it('gives up after the timeout', async () => {
    vi.useFakeTimers();
    chrome.runtime.sendMessage.mockImplementation(() => {});
    const pending = connectExtension('hash-1', 1000);
    vi.advanceTimersByTime(1001);
    await expect(pending).resolves.toEqual({ ok: false, error: 'timeout' });
    vi.useRealTimers();
  });
});
```

- [ ] **Step 2: Run it to see it fail** — `npx vitest run src/utils/extensionBridge.test.ts` → FAIL (module missing).

- [ ] **Step 3: Write the module** (the id below is the one Task 4 prints; until then any 32 `a–p` letters keep the tests honest — Task 4 Step 4 replaces it):

```ts
// src/utils/extensionBridge.ts
// The page's half of the web → extension sign-in bridge (spec §6.4, §7). Chrome exposes
// `chrome.runtime.sendMessage` to a normal page only when an installed extension lists this
// origin in `externally_connectable` — so "no runtime" means "not installed (or not Chrome)".
// The hash goes to our extension id and nowhere else.
export const EXTENSION_ID = 'abcdefghijklmnopabcdefghijklmnop';

type Runtime = { sendMessage: (id: string, message: unknown, callback: (reply: unknown) => void) => void; lastError?: { message?: string } };
export type BridgeReply = { ok: boolean; email?: string | null; error?: string };

const runtime = (): Runtime | undefined => (window as unknown as { chrome?: { runtime?: Runtime } }).chrome?.runtime;

export const extensionAvailable = () => typeof runtime()?.sendMessage === 'function';

export function connectExtension(tokenHash: string, timeoutMs = 8000): Promise<BridgeReply> {
  return new Promise((resolve) => {
    const rt = runtime();
    if (!rt) return resolve({ ok: false, error: 'not-installed' });
    const timer = setTimeout(() => resolve({ ok: false, error: 'timeout' }), timeoutMs);
    try {
      rt.sendMessage(EXTENSION_ID, { type: 'stash.session', token_hash: tokenHash }, (reply) => {
        clearTimeout(timer);
        const refused = rt.lastError?.message;
        if (refused || !reply) return resolve({ ok: false, error: refused ?? 'no-reply' });
        resolve(reply as BridgeReply);
      });
    } catch (e) {
      clearTimeout(timer);
      resolve({ ok: false, error: e instanceof Error ? e.message : String(e) });
    }
  });
}
```

- [ ] **Step 4: Run it** — `npx vitest run src/utils/extensionBridge.test.ts` → 4 PASS.

- [ ] **Step 5: Commit**

```bash
git add src/utils/extensionBridge.ts src/utils/extensionBridge.test.ts
git commit -m "feat(web): the page's half of the extension sign-in bridge"
```

---

### Task 3: `/extension/connect` — the page

**Files:**
- Create: `src/pages/ExtensionConnect.tsx`, `src/pages/ExtensionConnect.test.tsx`
- Modify: `src/App.tsx` (import + `<Route path="/extension/connect" element={<ExtensionConnect />} />` next to `/auth`)

**Interfaces:**
- Consumes: `useAuth()` (`user`, `loading`, `handle`), `AuthShell`, `SubmitButton`-free layout (plain ink `Button`), `extensionAvailable` / `connectExtension` (Task 2), `supabase.functions.invoke('extension-session')` (Task 1).
- Produces: states `checking → not-installed | connecting → connected | failed` with the §4.6 copy. Signed out → `/auth?returnTo=/extension/connect`; anonymous → the same; an unconfirmed handle is handled by `/auth` itself (the gate) before the person comes back.

- [ ] **Step 1: Write the failing test**

```tsx
// src/pages/ExtensionConnect.test.tsx
import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import { MemoryRouter, Route, Routes } from 'react-router-dom';
import ExtensionConnect from './ExtensionConnect';

const auth = vi.hoisted(() => ({ user: null as null | { id: string; email: string; is_anonymous?: boolean }, loading: false, handle: null as null | { username: string; confirmed: boolean } }));
vi.mock('@/hooks/useAuth', () => ({ useAuth: () => auth }));

const fn = vi.hoisted(() => ({ invoke: vi.fn(async () => ({ data: { token_hash: 'hash-1' }, error: null as null | { message: string } })) }));
vi.mock('@/integrations/supabase/client', () => ({ supabase: { functions: { invoke: fn.invoke } } }));

const bridge = vi.hoisted(() => ({ available: true, reply: { ok: true, email: 'will@example.com' } as { ok: boolean; email?: string | null; error?: string } }));
vi.mock('@/utils/extensionBridge', () => ({ extensionAvailable: () => bridge.available, connectExtension: vi.fn(async () => bridge.reply) }));

const renderPage = () =>
  render(
    <MemoryRouter initialEntries={['/extension/connect']}>
      <Routes>
        <Route path="/extension/connect" element={<ExtensionConnect />} />
        <Route path="/auth" element={<div>WAY IN</div>} />
      </Routes>
    </MemoryRouter>,
  );

describe('ExtensionConnect', () => {
  beforeEach(() => {
    auth.user = { id: 'u1', email: 'will@example.com' };
    auth.handle = { username: 'will', confirmed: true };
    bridge.available = true;
    bridge.reply = { ok: true, email: 'will@example.com' };
    fn.invoke.mockClear();
  });

  it('sends a signed-out visitor to the way in and back', async () => {
    auth.user = null;
    renderPage();
    expect(await screen.findByText('WAY IN')).toBeInTheDocument();
  });

  it('an anonymous session is sent to the way in', async () => {
    auth.user = { id: 'anon', email: '', is_anonymous: true };
    renderPage();
    expect(await screen.findByText('WAY IN')).toBeInTheDocument();
  });

  it('says to install when no extension is listening', async () => {
    bridge.available = false;
    renderPage();
    expect(await screen.findByText('Install the extension first.')).toBeInTheDocument();
    expect(screen.getByRole('link', { name: /extension/i })).toHaveAttribute('href', '/extension');
    expect(fn.invoke).not.toHaveBeenCalled();
  });

  it('connects: mints a hash, hands it over, shows who is signed in', async () => {
    renderPage();
    expect(await screen.findByText('The extension is connected.')).toBeInTheDocument();
    expect(fn.invoke).toHaveBeenCalledWith('extension-session', { body: {} });
    expect(screen.getByText(/signed in as will@example.com — you can close this tab\./)).toBeInTheDocument();
  });

  it('a failed handoff offers Try again, which mints a fresh hash', async () => {
    bridge.reply = { ok: false, error: 'otp_expired' };
    renderPage();
    expect(await screen.findByText("That didn't take.")).toBeInTheDocument();
    bridge.reply = { ok: true, email: 'will@example.com' };
    fireEvent.click(screen.getByRole('button', { name: /try again/i }));
    expect(await screen.findByText('The extension is connected.')).toBeInTheDocument();
    expect(fn.invoke).toHaveBeenCalledTimes(2);
  });
});
```

- [ ] **Step 2: Run it to see it fail** — `npx vitest run src/pages/ExtensionConnect.test.tsx` → FAIL (module missing).

- [ ] **Step 3: Write the page and the route**

```tsx
// src/pages/ExtensionConnect.tsx
import { useCallback, useEffect, useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { useAuth } from '@/hooks/useAuth';
import { supabase } from '@/integrations/supabase/client';
import { AuthShell } from '@/components/auth/AuthShell';
import { Button } from '@/components/ui/button';
import { connectExtension, extensionAvailable } from '@/utils/extensionBridge';

type State = 'checking' | 'not-installed' | 'connecting' | 'connected' | 'failed';

const COPY = {
  checking: { title: 'Connecting the extension.', prompt: 'one moment.' },
  connecting: { title: 'Connecting the extension.', prompt: 'handing over a key…' },
  connected: { title: 'The extension is connected.', prompt: '' },
  'not-installed': { title: 'Install the extension first.', prompt: 'then come back here.' },
  failed: { title: "That didn't take.", prompt: 'try once more.' },
} as const;

/**
 * The web half of the extension sign-in bridge (spec §6.4): the extension opens this page; the
 * signed-in person's session mints a one-time token hash (`extension-session`); the page hands it
 * to the extension, which redeems it for a session of its own.
 */
const ExtensionConnect = () => {
  const { user, loading } = useAuth();
  const navigate = useNavigate();
  const [state, setState] = useState<State>('checking');
  const [email, setEmail] = useState<string>('');
  const [error, setError] = useState<string>('');

  const isRealUser = !!user && !(user as { is_anonymous?: boolean }).is_anonymous;

  useEffect(() => {
    if (!loading && !isRealUser) navigate('/auth?returnTo=/extension/connect');
  }, [loading, isRealUser, navigate]);

  const attempt = useCallback(async () => {
    if (!extensionAvailable()) {
      setState('not-installed');
      return;
    }
    setState('connecting');
    const { data, error: fnError } = await supabase.functions.invoke('extension-session', { body: {} });
    const hash = (data as { token_hash?: string } | null)?.token_hash;
    if (fnError || !hash) {
      setError(fnError?.message ?? 'no token');
      setState('failed');
      return;
    }
    const reply = await connectExtension(hash);
    if (reply.ok) {
      setEmail(reply.email ?? user?.email ?? '');
      setState('connected');
    } else {
      setError(reply.error ?? 'unknown');
      setState('failed');
    }
  }, [user?.email]);

  useEffect(() => {
    if (isRealUser && state === 'checking') void attempt();
  }, [isRealUser, state, attempt]);

  const copy = COPY[state];
  const prompt = state === 'connected' ? `signed in as ${email} — you can close this tab.` : copy.prompt;

  return (
    <AuthShell address="stash://extension" title={copy.title} prompt={prompt} busy={state === 'connecting' ? 'connecting…' : null}>
      {state === 'not-installed' && (
        <p className="text-[15px] leading-[1.55] text-muted-foreground">
          Get it at{' '}
          <Link to="/extension" className="font-code text-[14px] text-ink underline underline-offset-[3px]">
            gostash.it/extension
          </Link>
          , then click its toolbar button again.
        </p>
      )}
      {state === 'failed' && (
        <div className="space-y-5">
          <p className="font-pixel text-pixel text-muted-foreground">✕ {error}</p>
          <Button type="button" onClick={() => void attempt()} className="h-11 w-full justify-between px-4 text-[15px] font-medium">
            Try again
          </Button>
        </div>
      )}
    </AuthShell>
  );
};

export default ExtensionConnect;
```

In `src/App.tsx`: `import ExtensionConnect from '@/pages/ExtensionConnect';` and, after the `/auth` route, `<Route path="/extension/connect" element={<ExtensionConnect />} />`. (`/extension` itself is the static install page in `public/extension/index.html`; a deeper path falls through Vercel's catch-all to the app shell, so no `vercel.json` change.)

- [ ] **Step 4: Run the tests and the typecheck** — `npx vitest run src/pages/ExtensionConnect.test.tsx && npx tsc --noEmit -p tsconfig.app.json` → 5 PASS, no type errors. `npx vitest run` → whole suite green.

- [ ] **Step 5: Commit**

```bash
git add src/pages/ExtensionConnect.tsx src/pages/ExtensionConnect.test.tsx src/App.tsx
git commit -m "feat(web): /extension/connect hands the extension a session of its own"
```

---

### Task 4: A stable extension id — key pair, `manifest.json`, `extension-id.mjs`

**Files:**
- Create: `extension/scripts/extension-id.mjs`, `extension/test/extension-id.test.mjs`
- Modify: `extension/manifest.json` (`version` → `1.3.0`, add `key`, add `externally_connectable`)
- Modify: `src/utils/extensionBridge.ts` (`EXTENSION_ID` → the printed id)
- Outside the repo: `~/Library/Application Support/stash-it-extension/key.pem` (the private key; also to be stored in 1Password)

**Interfaces:**
- Produces: `extensionIdFromKey(keyBase64: string): string` (exported for tests; the CLI prints the id for `manifest.json`'s `key`).

- [ ] **Step 1: Generate the key pair once, outside the repo** (the public half becomes the manifest `key`; Chrome derives the id from it, so unpacked, hosted-zip and Web Store builds share one id):

Run: `mkdir -p "/Users/will/Library/Application Support/stash-it-extension" && openssl genrsa -out "/Users/will/Library/Application Support/stash-it-extension/key.pem" 2048 && openssl rsa -in "/Users/will/Library/Application Support/stash-it-extension/key.pem" -pubout -outform DER -out /tmp/pw/stash-it-pub.der && base64 -i /tmp/pw/stash-it-pub.der | tr -d '\n' > /tmp/pw/stash-it-key.b64 && wc -c /tmp/pw/stash-it-key.b64`
Expected: a byte count around 392 (a 2048-bit SPKI in base64). Tell Will to copy `key.pem` into 1Password — it is the only copy and a lost key means a new extension id.

- [ ] **Step 2: Write the failing id test**

```js
// extension/test/extension-id.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { extensionIdFromKey } from '../scripts/extension-id.mjs';

test('derives Chrome\'s a–p id from the manifest key', () => {
  // Chrome: id = sha256(DER public key)[0..32 hex] with each hex digit mapped 0→a … f→p
  const der = Buffer.from([0x30, 0x0d, 0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01, 0x05, 0x00]);
  const id = extensionIdFromKey(der.toString('base64'));
  assert.match(id, /^[a-p]{32}$/);
  assert.equal(id, extensionIdFromKey(der.toString('base64'))); // deterministic
  assert.notEqual(id, extensionIdFromKey(Buffer.from([1, 2, 3]).toString('base64')));
});
```

- [ ] **Step 3: Run it to see it fail** — `cd extension && npm test` → FAIL (module missing). (`cd` into `extension/` is fine; stay inside the worktree.)

- [ ] **Step 4: Write the script**

```js
#!/usr/bin/env node
// extension/scripts/extension-id.mjs — print the extension id Chrome derives from manifest.json's
// `key` (the base64 SPKI public key): sha256 of the DER, first 32 hex digits, 0–f → a–p.
// Usage: node scripts/extension-id.mjs            (reads ../manifest.json)
//        node scripts/extension-id.mjs <base64>   (any key)
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

export function extensionIdFromKey(keyBase64) {
  const der = Buffer.from(keyBase64, 'base64');
  const hex = createHash('sha256').update(der).digest('hex').slice(0, 32);
  return [...hex].map((c) => String.fromCharCode('a'.charCodeAt(0) + parseInt(c, 16))).join('');
}

const isMain = process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1];
if (isMain) {
  const key = process.argv[2] ?? JSON.parse(readFileSync(join(dirname(fileURLToPath(import.meta.url)), '..', 'manifest.json'), 'utf8')).key;
  if (!key) { console.error('manifest.json has no "key"'); process.exit(1); }
  console.log(extensionIdFromKey(key));
}
```

Run: `cd extension && npm test` → PASS.

- [ ] **Step 5: Put the key in the manifest and bump the version** — in `extension/manifest.json` set `"version": "1.3.0"`, and add (top level, after `"description"`):

```json
  "key": "<the contents of /tmp/pw/stash-it-key.b64>",
  "externally_connectable": {
    "matches": ["https://www.gostash.it/*", "https://gostash.it/*", "http://localhost:8080/*"]
  },
```

Run: `cd extension && node scripts/extension-id.mjs` → prints the id (32 letters a–p). Paste it into `src/utils/extensionBridge.ts` as `EXTENSION_ID`. Run: `npx vitest run src/utils/extensionBridge.test.ts` → still PASS.

- [ ] **Step 6: Load it in Chrome to prove the manifest and the id** — `chrome://extensions` → Developer mode → Load unpacked → `extension/`. Expected: it loads without a manifest error and the card shows **ID: <the printed id>**. If Chrome rejects the `http://localhost:8080/*` pattern, change it to `http://localhost/*` (and the same string in `extension/bridge.js` `ALLOWED_ORIGINS` stays `http://localhost:8080` — origins carry the port, match patterns may not) and reload.

- [ ] **Step 7: Commit**

```bash
git add extension/manifest.json extension/scripts/extension-id.mjs extension/test/extension-id.test.mjs src/utils/extensionBridge.ts
git commit -m "feat(extension): a pinned id, externally_connectable for gostash.it, version 1.3.0"
```

---

### Task 5: The extension's half — `bridge.js`, `adoptTokenHash`, the external-message listener

**Files:**
- Create: `extension/bridge.js`, `extension/test/bridge.test.mjs`
- Modify: `extension/stash-api.js` (export `adoptTokenHash`)
- Modify: `extension/background.js` (register `onMessageExternal`)

**Interfaces:**
- Consumes: `toStoredSession`, `setStored` (module-private in `stash-api.js`, used by the new export).
- Produces: `adoptTokenHash(tokenHash: string): Promise<StoredSession>` (verifies at `/auth/v1/verify`, stores, returns the stored session `{ access_token, refresh_token, expires_at, user_id, email }`); `ALLOWED_ORIGINS: Set<string>`; `senderOrigin(sender): string | null`; `handleExternalMessage(message, sender, { adoptTokenHash }): Promise<Reply> | null` (null = not for us, do not answer).

- [ ] **Step 1: Write the failing test**

```js
// extension/test/bridge.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { ALLOWED_ORIGINS, handleExternalMessage, senderOrigin } from '../bridge.js';

const msg = { type: 'stash.session', token_hash: 'hash-1' };
const ok = { adoptTokenHash: async () => ({ email: 'will@example.com' }) };

test('senderOrigin prefers sender.origin and falls back to the url', () => {
  assert.equal(senderOrigin({ origin: 'https://www.gostash.it' }), 'https://www.gostash.it');
  assert.equal(senderOrigin({ url: 'https://gostash.it/extension/connect' }), 'https://gostash.it');
  assert.equal(senderOrigin({}), null);
  assert.ok(ALLOWED_ORIGINS.has('https://www.gostash.it'));
});

test('ignores other origins — returns null so nothing is answered', () => {
  assert.equal(handleExternalMessage(msg, { origin: 'https://evil.example' }, ok), null);
  assert.equal(handleExternalMessage(msg, {}, ok), null);
});

test('refuses a malformed message from our page', async () => {
  const reply = await handleExternalMessage({ type: 'stash.session' }, { origin: 'https://www.gostash.it' }, ok);
  assert.deepEqual(reply, { ok: false, error: 'bad-message' });
});

test('adopts the session and answers with the email', async () => {
  let seen = null;
  const reply = await handleExternalMessage(msg, { origin: 'https://www.gostash.it' }, { adoptTokenHash: async (h) => { seen = h; return { email: 'will@example.com' }; } });
  assert.equal(seen, 'hash-1');
  assert.deepEqual(reply, { ok: true, email: 'will@example.com' });
});

test('a refused verify fails closed with the reason', async () => {
  const reply = await handleExternalMessage(msg, { origin: 'http://localhost:8080' }, { adoptTokenHash: async () => { throw new Error('otp_expired'); } });
  assert.deepEqual(reply, { ok: false, error: 'otp_expired' });
});
```

And the `adoptTokenHash` test, appended to the same file (it stubs `fetch` and `chrome.storage`):

```js
import { adoptTokenHash } from '../stash-api.js';

test('adoptTokenHash redeems the hash at /auth/v1/verify and stores the session', async () => {
  const stored = {};
  globalThis.chrome = { storage: { local: { get: async () => stored, set: async (v) => Object.assign(stored, v), remove: async () => {} } } };
  let request = null;
  globalThis.fetch = async (url, init) => {
    request = { url, body: JSON.parse(init.body), apikey: init.headers.apikey };
    return { ok: true, status: 200, json: async () => ({ access_token: 'a', refresh_token: 'r', expires_in: 3600, user: { id: 'u1', email: 'will@example.com' } }) };
  };
  const session = await adoptTokenHash('hash-1');
  assert.match(request.url, /\/auth\/v1\/verify$/);
  assert.deepEqual(request.body, { type: 'magiclink', token_hash: 'hash-1' });
  assert.ok(request.apikey);
  assert.equal(session.email, 'will@example.com');
  assert.equal(stored.session.refresh_token, 'r');
});

test('adoptTokenHash throws GoTrue\'s reason on a 4xx', async () => {
  globalThis.fetch = async () => ({ ok: false, status: 403, json: async () => ({ error_code: 'otp_expired', msg: 'Token has expired or is invalid' }) });
  await assert.rejects(adoptTokenHash('old'), /Token has expired/);
});
```

- [ ] **Step 2: Run it to see it fail** — `cd extension && npm test` → FAIL (`../bridge.js` missing; `adoptTokenHash` not exported).

- [ ] **Step 3: Write `bridge.js`**

```js
// extension/bridge.js
// The extension's half of the web → extension sign-in handoff (spec §7). Pure: node-testable.
// The page at gostash.it sends { type: 'stash.session', token_hash } over chrome.runtime.sendMessage;
// Chrome only lets pages listed in manifest externally_connectable do that, and this checks the
// origin again. Anything from elsewhere is ignored — not answered — so nothing leaks about us.
export const ALLOWED_ORIGINS = new Set(['https://www.gostash.it', 'https://gostash.it', 'http://localhost:8080']);

export function senderOrigin(sender) {
  if (sender?.origin) return sender.origin;
  try {
    return new URL(sender?.url ?? '').origin;
  } catch {
    return null;
  }
}

/** Returns a promise of the reply, or null when the message is not ours (then do not respond). */
export function handleExternalMessage(message, sender, { adoptTokenHash }) {
  const origin = senderOrigin(sender);
  if (!origin || !ALLOWED_ORIGINS.has(origin)) return null;
  if (message?.type !== 'stash.session' || typeof message.token_hash !== 'string') {
    return Promise.resolve({ ok: false, error: 'bad-message' });
  }
  return adoptTokenHash(message.token_hash).then(
    (session) => ({ ok: true, email: session.email ?? null }),
    (error) => ({ ok: false, error: error?.message ?? String(error) }),
  );
}
```

- [ ] **Step 4: Export `adoptTokenHash` from `stash-api.js`** — after `signIn`:

```js
// The bridge (bridge.js): the gostash.it page minted a one-time magic-link token hash for the
// signed-in person; redeeming it here gives this extension a session of its own, so it never
// shares (and never races) a refresh token with a browser tab.
export async function adoptTokenHash(tokenHash) {
  const res = await fetch(`${SUPABASE_URL}/auth/v1/verify`, {
    method: 'POST',
    headers: { apikey: ANON_KEY, 'Content-Type': 'application/json' },
    body: JSON.stringify({ type: 'magiclink', token_hash: tokenHash }),
  });
  const data = await res.json().catch(() => ({}));
  if (!res.ok || !data.access_token) {
    throw new Error(data.msg || data.error_description || data.error_code || `Could not connect (${res.status})`);
  }
  const session = toStoredSession(data);
  await setStored(session);
  return session;
}
```

- [ ] **Step 5: Register the listener in `background.js`** — change the import line to `import { NotSignedInError, adoptTokenHash, stashImage, stashNote, stashUrl } from './stash-api.js';`, add `import { handleExternalMessage } from './bridge.js';`, and append:

```js
// Sign-in handoff from gostash.it/extension/connect (bridge.js). `true` keeps the channel open for
// the async reply; a message that isn't ours gets no reply at all.
chrome.runtime.onMessageExternal.addListener((message, sender, sendResponse) => {
  const pending = handleExternalMessage(message, sender, { adoptTokenHash });
  if (!pending) return false;
  pending.then(sendResponse);
  return true;
});
```

- [ ] **Step 6: Run the extension tests** — `cd extension && npm test` → all PASS (the previous `lib` tests plus 8 new).

- [ ] **Step 7: Commit**

```bash
git add extension/bridge.js extension/test/bridge.test.mjs extension/stash-api.js extension/background.js
git commit -m "feat(extension): adopt a session handed over by gostash.it"
```

---

### Task 6: The sign-in page says "Sign in at gostash.it"; README, install page, hosted zip, docs

**Files:**
- Modify: `extension/signin.html`, `extension/signin.js`, `extension/README.md`
- Modify: `public/extension/index.html` (the sign-in sentence), then the publish script regenerates the zip and stamps the page
- Modify: `docs/ui-changes.md` (new entry), `docs/PLATFORM_API.md` (`### POST /extension-session` under `## Account deletion`'s neighbour `## Agents (MCP)` — put it right before `## Account deletion`)

- [ ] **Step 1: `signin.html`** — in `<section id="signed-out">`, replace the first `<p class="sub">` and put the bridge first; the password form stays below as the secondary path:

```html
        <p class="sub">Sign in once in your browser — with Google, Apple or your email. The extension connects itself.</p>
        <button id="connect" type="button">Sign in at gostash.it</button>
        <p class="fine">Or with your Stash email and password:</p>
        <form id="signin-form">
          …unchanged…
        </form>
```

(Give `#connect` the same look as `#submit` in `signin.css`: copy the `#submit` rule's selector to `#submit, #connect`.)

- [ ] **Step 2: `signin.js`** — add, after the `signout` listener:

```js
el('connect').addEventListener('click', () => {
  chrome.tabs.create({ url: 'https://www.gostash.it/extension/connect' });
});

// The bridge stores the session from the service worker; reflect it here without a reload.
chrome.storage.onChanged.addListener((changes, area) => {
  if (area === 'local' && 'session' in changes) render();
});
```

- [ ] **Step 3: README** — in "Install (unpacked)" step 4 replace "Sign in with your Stash email/password." with "Click **Sign in at gostash.it** — sign in there with Google, Apple or your email, and the extension connects itself (the email/password form on the same page still works)."; in the Architecture table add `| \`bridge.js\` | The gostash.it → extension sign-in handoff (externally_connectable + onMessageExternal); node-testable |`; mention `scripts/extension-id.mjs` under `scripts/`.

- [ ] **Step 4: Install page + hosted zip** — in `public/extension/index.html` change the sentence that tells people to sign in with email/password to: "Click the toolbar button once, then **Sign in at gostash.it** — Google, Apple or your email." Then run `cd extension && ./scripts/publish-hosted-zip.sh` → it rebuilds `stash-it-1.3.0.zip`, copies it to `public/stash-it-extension.zip`, and stamps version + size into the page. Expected output ends with the stamped version `1.3.0`. Check the zip carries the new files: `unzip -l public/stash-it-extension.zip | grep -c "bridge.js\|manifest.json"` → `2`.

- [ ] **Step 5: `docs/ui-changes.md`** — newest entry:

```markdown
## 2026-10-11 · The extension signs in through gostash.it

- **Contract:** `POST /functions/v1/extension-session` (standard auth headers; agent tokens and
  anonymous sessions refused with 403) answers `{ token_hash }` — a one-time magic-link hash for
  the caller. A client redeems it with `POST /auth/v1/verify { type: 'magiclink', token_hash }`
  (apikey header) and receives a session of its own. The macOS wrapper can use the same bridge.
- **Web:** `/extension/connect` (app shell; signed out → `/auth?returnTo=/extension/connect`)
  mints the hash and hands it to the pinned extension id over `chrome.runtime.sendMessage`
  (`{ type: 'stash.session', token_hash }` → `{ ok, email } | { ok: false, error }`). States:
  `stash://extension` **The extension is connected.** / `> signed in as <email> — you can close
  this tab.`; **Install the extension first.** (no `chrome.runtime`); **That didn't take.** +
  **Try again** (a fresh hash).
- **Extension 1.3.0:** pinned `key` (stable id), `externally_connectable` for `www.gostash.it`,
  `gostash.it`, `localhost:8080`; the sign-in page leads with **Sign in at gostash.it**; the
  password form stays as the secondary path. `bridge.js` ignores any other origin and never
  answers it. Hosted zip and install page refreshed.
```

- [ ] **Step 6: `docs/PLATFORM_API.md`** — before `## Account deletion`:

```markdown
### `POST /extension-session` — a one-time session hash for a companion client

Standard auth headers; agent tokens → `403 { error: 'agent' }`, anonymous sessions → `403
{ error: 'anonymous' }`. No body. `200 { token_hash }`: a single-use magic-link hash for the
caller's account, valid for the project's OTP lifetime, never emailed. Redeem it with
`POST /auth/v1/verify` body `{ "type": "magiclink", "token_hash": "…" }` and the `apikey` header to
receive an independent session (access + refresh token). This is how the Chrome extension signs
in through the web way-in (spec `2026-10-11-google-apple-sign-in-design.md` §7); any client that
can't run the id-token flows itself may use it.
```

- [ ] **Step 7: Tests and commit**

Run: `cd extension && npm test` → PASS; `npx vitest run` (repo root) → PASS (`scripts/publish-site.test.ts` checks the committed site output, which this does not touch).

```bash
git add extension/signin.html extension/signin.js extension/signin.css extension/README.md public/extension/index.html public/stash-it-extension.zip public/extension/icon128.png docs/ui-changes.md docs/PLATFORM_API.md
git commit -m "feat(extension): sign in at gostash.it; hosted zip 1.3.0; bridge contract documented"
```

---

### Task 7: Walk it end to end, then ship

**Files:** none.

- [ ] **Step 1: Dev walk (localhost origin)** — `npm run dev`; in Chrome load the unpacked `extension/` (Task 4 Step 6) in a profile signed **out** of gostash.it; click the toolbar button on any page → `signin.html` opens → **Sign in at gostash.it** → (dev: change the URL to `http://localhost:8080/extension/connect`) → `/auth?returnTo=/extension/connect` → **Continue with Google** (throwaway account) → the handle step if new → back on `/extension/connect` → **The extension is connected.** `> signed in as … — you can close this tab.` The `signin.html` tab flips to "Signed in as …" by itself. Click the toolbar button on an article → `✓`; the save appears at `localhost:8080/home`.

- [ ] **Step 2: Prove the two sessions are independent** — in the web tab, Settings → sign out. Click the toolbar button again → still `✓` (the extension's session survived; it was never the tab's).

- [ ] **Step 3: Failure paths** — a profile without the extension: `/extension/connect` → **Install the extension first.** with the link. With the extension but the service worker killed (`chrome://extensions` → stop), the page's **Try again** recovers once the worker wakes.

- [ ] **Step 4: Ship** — finish the branch per the project routine (merge to `main`, push); `supabase functions list --project-ref uqqsgmwkvslaomzxptnp | grep extension-session` → `ACTIVE`; then with the **hosted zip** from `https://www.gostash.it/extension`, install fresh and repeat Step 1 against production.

- [ ] **Step 5: Report** — the extension id, the function version, the three walks' outcomes; update the workstream memory and the spec's §12 phase-2 line.

---

## Self-review notes (writer's pass, 2026-10-11)

- Spec coverage: §5.3 `extension-session` (T1), §6.4 the page (T3), §7 manifest/sign-in page/background/README/hosted zip (T4–T6), §4.6 copy (T3, T6), §9 bridge error rows (T3, T5), §10 security (origin checks T5, pinned id T2/T4), docs (T6), walk (T7).
- Review Focus → tests: 1 → T5 "ignores other origins"; 2 → T2 "sends to the pinned id"; 3 → T5 "a refused verify fails closed" + T3 "a failed handoff offers Try again"; 4 → T1 anonymous 403 + T3 "an anonymous session is sent to the way in"; 5 → T3 "says to install when no extension is listening".
- Type consistency: the message `{ type: 'stash.session', token_hash }` and reply `{ ok, email } | { ok: false, error }` are identical in T2 (`extensionBridge.ts`), T3 (page), T5 (`bridge.js`); `adoptTokenHash` returns the stored session whose `email` the reply carries; `EXTENSION_ID` is produced by T4's script and consumed by T2.

