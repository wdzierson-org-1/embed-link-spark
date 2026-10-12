# Google and Apple sign-in — phase 1 (backend + web + docs) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A person creates or opens a Stash account with Google or Apple on `/auth`, gets a confirmed @handle, and every account path (profile trigger, Apple token revocation on deletion) keeps working for password users.

**Architecture:** The id-token flow everywhere — Google Identity Services and Apple JS hand the browser an identity token, the browser calls `supabase.auth.signInWithIdToken` (raw nonce; the provider got its SHA-256), and Supabase holds only Client IDs. A Postgres trigger generates handles for sign-ups without one and marks them unconfirmed; the way in shows a one-step confirm. Two small edge functions (Apple code exchange, Apple revoke inside `delete-account`) complete the Apple story.

**Tech Stack:** Vite + React 18 + TS, supabase-js 2.50.2 (`signInWithIdToken`), vitest + Testing Library (jsdom), Postgres (plpgsql triggers) via the Supabase Management API, Deno edge functions (`https://esm.sh/@supabase/supabase-js@2.57.2`, Web Crypto ES256), Google Identity Services (`gsi/client`), Apple JS (`appleid.auth.js`).

**Spec:** `docs/superpowers/specs/2026-10-11-google-apple-sign-in-design.md` (§0 decisions, §4 contract, §5 backend, §6 web, §9 errors, §12 phase 0 results — the Google/Apple identifiers below come from there).

**Deviations from the spec, decided while planning:** (1) `apple-token-exchange` and the `delete-account` revoke step are built here (spec §12 listed them under phase 3) because the **web** Apple flow (§6.2) calls the exchange — shipping the web without it would log a failure on every Apple sign-in. (2) The Supabase provider Client IDs are set as **comma-separated lists in `external_*_client_id`** (what Supabase's own docs say the dashboard field maps to), not in `additional_client_ids`; the read-back step proves whichever shape the API kept.

## Global Constraints

- Nonce rule (spec §4.1): per attempt a random nonce; the provider receives its **SHA-256 hex**, Supabase receives the **raw** value; single use.
- **No provider client secret** is ever stored in Supabase auth config or any client (§0.3). The only Apple credential is the `.p8`, already in edge-function secrets as `APPLE_SIGNIN_PRIVATE_KEY_B64` (base64 PEM) with `APPLE_TEAM_ID`, `APPLE_KEY_ID`, `APPLE_SERVICES_ID`, `APPLE_BUNDLE_ID` (§5.4).
- Identifiers (§12 "Done"): Google web client `772942709290-2j03nu08hnumh6jfe2h0j6jkh9bnrbta.apps.googleusercontent.com`; Google iOS client `772942709290-ha25d35f942l5blept0aiv30aculahsn.apps.googleusercontent.com`; Apple Services ID `it.gostash.web`; Apple bundle `it.gostash.stash`; Apple web return URL `https://www.gostash.it/auth`.
- Handles: `^[a-z0-9]{3,20}$` for anything a person types or confirms; the anonymous `guest-xxxxxxxx` shape stays server-generated only (§4.3).
- Copy is **verbatim** from spec §4.6 (machine voice, lowercase, `✕ ` prefix on field errors).
- Edge functions: import `https://esm.sh/@supabase/supabase-js@2.57.2`, verify with `admin.auth.getUser(token)` (never a bare `getUser()`), refuse agent tokens with `isAgentToken` from `../_shared/agentToken.ts`, answer JSON with the `corsHeaders` pattern of `delete-account`.
- Web tests: vitest + `@testing-library/react`, jsdom, `src/test/setup.ts` (jest-dom matchers, `ResizeObserver` stub). Edge-function tests: vitest with `// @vitest-environment node` at the top, URL imports mocked with `vi.mock('https://esm.sh/…')`, `Deno` stubbed (see `supabase/functions/add-note/index.test.ts`).
- Production: web ships by pushing `main` (Vercel); edge functions ship **only** via `supabase functions deploy <name> --project-ref uqqsgmwkvslaomzxptnp`; SQL and auth config go through the Management API with the keychain token (`security find-generic-password -s "Supabase CLI" -a "supabase" -w`, strip `go-keyring-base64:`, base64-decode) and every applied migration is recorded in `supabase_migrations.schema_migrations`.
- This worktree's Bash guard refuses loops, heredocs, `$(...)`, `awk`, `git -C` and variable-built paths: write helper scripts to `/tmp/pw/` with the Write tool and run each as one plain command.
- Commit after every task; `npm test` (worktree baseline 1591 green) must stay green.

## Review Focus

1. **Two credentials in flight** — a double-click or a second tab delivering a Google credential while the first `signInWithIdToken` is pending must not start a second sign-in or a second toast (Task 8 test "ignores a second credential while one is in flight").
2. **Profile row not yet visible** — a sign-in whose `user_profiles` row is still being written must not be routed to `/home` as confirmed nor stuck forever: one retry after 500 ms, then fail open (Task 5 test "retries once, then fails open").
3. **`returnTo` through the handle step** — a person sent from `/oauth/consent` who then has to claim a handle must land back on the consent page, not `/home` (Task 10 test "routes to returnTo after the handle is claimed").
4. **Pasted handles** — `@Will Dzierson!` pasted into the handle field becomes `willdzierson`; `ab` is refused with `✕ 3–20 letters and numbers.` (Task 9 tests).
5. **Provider refused by Supabase** — a `signInWithIdToken` error such as "Unsupported provider: provider is not enabled" surfaces as the toast **Sign-in didn't complete.** with that message, and the email form remains usable (Task 10 test "surfaces a Supabase refusal").

---

### Task 1: Migration — `handle_confirmed`, trigger v3, handle lock, `apple_sign_in_tokens`

**Files:**
- Create: `supabase/migrations/20261011150000_oauth_handles.sql`

**Interfaces:**
- Produces: column `public.user_profiles.handle_confirmed boolean not null default true`; trigger function `public.handle_new_user()` v3; trigger `user_profiles_lock_handle`; table `public.apple_sign_in_tokens(user_id, client_id, refresh_token, created_at)`.

- [ ] **Step 1: Write the migration**

```sql
-- Google and Apple sign-in, phase 1 (docs/superpowers/specs/2026-10-11-google-apple-sign-in-design.md
-- §4.3–4.4, §5.2). Applied to prod through the Management API and recorded in
-- supabase_migrations.schema_migrations by hand (see the plan's Task 2).

-- 1. The handle flag. Existing rows chose theirs, so the default is true; the trigger below sets
--    false only when it had to generate one.
alter table public.user_profiles
  add column if not exists handle_confirmed boolean not null default true;

-- 2. handle_new_user v3. The email forms (web + iOS) send `username` in the metadata → used as-is,
--    confirmed. Anything else (Google, Apple, anonymous) gets a readable handle:
--    anonymous → guest-<8 chars of id>; otherwise full_name → name → the email local part (unless
--    the address is Apple's private relay) → 'stash'; sanitized to [a-z0-9], padded to 3, cut to
--    20, deduped with a numeric suffix. The insert retries on unique_violation so two sign-ups
--    racing for the same base both succeed.
--
--    Rollback = the v2 body from 20260821200000_anon_user_profiles.sql:
--      insert into public.user_profiles (id, username, display_name, created_at, updated_at)
--      values (new.id,
--              coalesce(new.raw_user_meta_data->>'username', 'guest-' || substr(new.id::text, 1, 8)),
--              coalesce(new.raw_user_meta_data->>'display_name', split_part(new.email, '@', 1)),
--              new.created_at, now());
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  meta jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
  chosen text := nullif(trim(meta->>'username'), '');
  local_part text := nullif(split_part(coalesce(new.email, ''), '@', 1), '');
  relay boolean := lower(split_part(coalesce(new.email, ''), '@', 2)) = 'privaterelay.appleid.com';
  avatar text := coalesce(meta->>'avatar_url', meta->>'picture');
  base text;
  candidate text;
  display text;
  i integer := 2;
begin
  if chosen is not null then
    insert into public.user_profiles (id, username, display_name, avatar_url, handle_confirmed, created_at, updated_at)
    values (new.id, chosen,
            coalesce(meta->>'display_name', meta->>'full_name', meta->>'name', local_part, chosen),
            avatar, true, new.created_at, now());
    return new;
  end if;

  if coalesce(new.is_anonymous, false) then
    base := 'guest-' || substr(new.id::text, 1, 8);
  else
    base := regexp_replace(lower(coalesce(nullif(meta->>'full_name', ''), nullif(meta->>'name', ''),
                                          case when relay then null else local_part end, 'stash')),
                           '[^a-z0-9]', '', 'g');
    if length(base) < 3 then
      base := base || substr(regexp_replace(new.id::text, '[^0-9]', '', 'g') || '000', 1, 3 - length(base));
    end if;
    base := left(base, 20);
  end if;

  -- A display name from the metadata or the email; when there is none, the handle itself (the
  -- final candidate, suffix included), so a relay-address Apple sign-up reads "stash2" not "stash".
  display := coalesce(meta->>'display_name', meta->>'full_name', meta->>'name',
                      case when relay then null else local_part end);
  candidate := base;
  loop
    begin
      insert into public.user_profiles (id, username, display_name, avatar_url, handle_confirmed, created_at, updated_at)
      values (new.id, candidate, coalesce(display, candidate), avatar, false, new.created_at, now());
      return new;
    exception when unique_violation then
      if i > 50 then
        candidate := left(base, 15) || substr(md5(new.id::text || i::text), 1, 5);
      else
        candidate := left(base, 20 - length(i::text)) || i::text;
      end if;
      i := i + 1;
      if i > 60 then raise; end if;
    end;
  end loop;
end;
$$;

-- 3. Immutability, server-side: once confirmed, a handle never changes, and the flag never goes
--    back to false. A handle that does change (the confirm step) must be 3–20 [a-z0-9].
create or replace function public.user_profiles_lock_handle()
returns trigger
language plpgsql
as $$
begin
  if new.username is distinct from old.username then
    if old.handle_confirmed then
      raise exception 'username is immutable once confirmed' using errcode = 'check_violation';
    end if;
    if new.username !~ '^[a-z0-9]{3,20}$' then
      raise exception 'username must be 3-20 lowercase letters or digits' using errcode = 'check_violation';
    end if;
  end if;
  if old.handle_confirmed and not new.handle_confirmed then
    raise exception 'handle_confirmed cannot be unset' using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

drop trigger if exists user_profiles_lock_handle on public.user_profiles;
create trigger user_profiles_lock_handle
  before update of username, handle_confirmed on public.user_profiles
  for each row execute function public.user_profiles_lock_handle();

-- 4. Apple refresh tokens, kept only so account deletion can revoke them (spec §5.3). Service
--    role only: RLS on with no policies, and the API roles' default grants revoked.
create table if not exists public.apple_sign_in_tokens (
  user_id uuid not null references auth.users(id) on delete cascade,
  client_id text not null,
  refresh_token text not null,
  created_at timestamptz not null default now(),
  primary key (user_id, client_id)
);
alter table public.apple_sign_in_tokens enable row level security;
revoke all on public.apple_sign_in_tokens from anon, authenticated;
```

- [ ] **Step 2: Sanity-check the SQL parses (no local database here)**

Run: `cd /Users/will/Appdev/embed-link-spark/.claude/worktrees/google-apple-sign-in && grep -c "create or replace function\|create trigger\|create table" supabase/migrations/20261011150000_oauth_handles.sql`
Expected: `4` (two functions, one trigger, one table). Real validation happens in Task 2 against prod.

- [ ] **Step 3: Commit**

```bash
git add supabase/migrations/20261011150000_oauth_handles.sql
git commit -m "feat(db): generated handles with a one-time confirm, handle lock, apple_sign_in_tokens"
```

---

### Task 2: Apply the migration to prod and prove the trigger with throwaway users

**Files:**
- Create (outside the repo): `/tmp/pw/sbq.py`, `/tmp/pw/handle_trigger_check.py`

**Interfaces:**
- Consumes: Task 1's SQL.
- Produces: the live schema every later task assumes; `/tmp/pw/sbq.py run(sql)` reused by Task 3 and Task 15.

- [ ] **Step 1: Write the SQL runner (curl-backed — Python urllib gets 403 from the Management API)**

```python
#!/usr/bin/env python3
"""Run SQL on prod through the Supabase Management API.
usage: sbq.py "<sql>"  |  sbq.py -f file.sql
A multi-statement query returns only the last statement's rows."""
import base64, json, subprocess, sys, tempfile

REF = "uqqsgmwkvslaomzxptnp"

def token() -> str:
    raw = subprocess.check_output(
        ["security", "find-generic-password", "-s", "Supabase CLI", "-a", "supabase", "-w"], text=True
    ).strip()
    if raw.startswith("go-keyring-base64:"):
        raw = base64.b64decode(raw[len("go-keyring-base64:"):]).decode()
    return raw

def run(sql: str):
    with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
        json.dump({"query": sql}, f)
        body = f.name
    out = subprocess.check_output([
        "curl", "-s", "-X", "POST",
        f"https://api.supabase.com/v1/projects/{REF}/database/query",
        "-H", f"Authorization: Bearer {token()}", "-H", "Content-Type: application/json",
        "--data-binary", f"@{body}",
    ], text=True)
    return json.loads(out) if out.strip() else None

if __name__ == "__main__":
    sql = open(sys.argv[2]).read() if sys.argv[1] == "-f" else sys.argv[1]
    print(json.dumps(run(sql), indent=1)[:6000])
```

- [ ] **Step 2: Apply and record**

Run: `python3 /tmp/pw/sbq.py -f /Users/will/Appdev/embed-link-spark/.claude/worktrees/google-apple-sign-in/supabase/migrations/20261011150000_oauth_handles.sql`
Expected: `[]` or `null` (DDL returns no rows). An error body means the SQL failed — fix Task 1 before going on.

Run: `python3 /tmp/pw/sbq.py "insert into supabase_migrations.schema_migrations (version, name) values ('20261011150000', 'oauth_handles') on conflict (version) do nothing; select version, name from supabase_migrations.schema_migrations where version = '20261011150000'"`
Expected: one row `{"version": "20261011150000", "name": "oauth_handles"}`.

Run: `python3 /tmp/pw/sbq.py "select column_name, column_default from information_schema.columns where table_schema='public' and table_name='user_profiles' and column_name='handle_confirmed'"`
Expected: one row with default `true`.

- [ ] **Step 3: Write the trigger check (admin API creates users; SQL reads their profiles; admin API deletes them)**

```python
#!/usr/bin/env python3
"""Prove handle_new_user v3 and user_profiles_lock_handle on prod with throwaway users."""
import json, subprocess, sys, time, urllib.request
sys.path.insert(0, "/tmp/pw")
from sbq import run, REF

URL = f"https://{REF}.supabase.co"
ts = str(int(time.time()))

def service_key() -> str:
    keys = json.loads(subprocess.check_output(
        ["supabase", "projects", "api-keys", "--project-ref", REF, "-o", "json"], text=True))
    return next(k["api_key"] for k in keys if k["name"] == "service_role")

KEY = service_key()
HDR = {"apikey": KEY, "Authorization": f"Bearer {KEY}", "Content-Type": "application/json"}

def admin(method, path, body=None):
    req = urllib.request.Request(URL + path, data=json.dumps(body).encode() if body else None, headers=HDR, method=method)
    with urllib.request.urlopen(req) as r:
        raw = r.read()
        return json.loads(raw) if raw else None

def profile(uid):
    rows = run(f"select username, display_name, avatar_url, handle_confirmed from public.user_profiles where id = '{uid}'")
    return rows[0] if rows else None

created = []
def make(email, meta):
    u = admin("POST", "/auth/v1/admin/users", {"email": email, "email_confirm": True, "user_metadata": meta})
    created.append(u["id"]); return u["id"]

results = []
def check(name, cond, got):
    results.append((name, "PASS" if cond else "FAIL", got)); return cond

try:
    a = make(f"will+smoke-handle-a-{ts}@dzierson.com", {"username": f"smokea{ts[-4:]}", "display_name": "Smoke A"})
    pa = profile(a)
    check("A email form keeps its username, confirmed", pa and pa["username"] == f"smokea{ts[-4:]}" and pa["handle_confirmed"] is True, pa)

    b = make(f"will+smoke-handle-b-{ts}@dzierson.com", {"full_name": "Smoke Handle B", "name": "Smoke Handle B", "picture": "https://example.com/p.png"})
    pb = profile(b)
    check("B Google-shaped metadata → name handle, unconfirmed, display + avatar", pb and pb["username"] == "smokehandleb" and pb["handle_confirmed"] is False and pb["display_name"] == "Smoke Handle B" and pb["avatar_url"] == "https://example.com/p.png", pb)

    d = make(f"will+smoke-handle-d-{ts}@dzierson.com", {"full_name": "Smoke Handle B"})
    pd = profile(d)
    check("D same name → numeric suffix", pd and pd["username"] == "smokehandleb2" and pd["handle_confirmed"] is False, pd)

    c = make(f"xq{ts}@privaterelay.appleid.com", {})
    pc = profile(c)
    check("C relay email, no name → stash… handle, display = handle", pc and pc["username"].startswith("stash") and pc["handle_confirmed"] is False and pc["display_name"] == pc["username"], pc)

    lock1 = run(f"do $$ begin update public.user_profiles set username = 'nope{ts[-4:]}' where id = '{a}'; exception when check_violation then raise notice 'locked'; end $$; select username from public.user_profiles where id = '{a}'")
    check("lock: a confirmed handle refuses to change", lock1 and lock1[0]["username"] == f"smokea{ts[-4:]}", lock1)

    claim = run(f"update public.user_profiles set username = 'smokeb{ts[-4:]}', handle_confirmed = true where id = '{b}' returning username, handle_confirmed")
    check("confirm step: unconfirmed handle can change once", claim and claim[0]["username"] == f"smokeb{ts[-4:]}" and claim[0]["handle_confirmed"] is True, claim)

    lock2 = run(f"do $$ begin update public.user_profiles set username = 'again{ts[-4:]}' where id = '{b}'; exception when check_violation then raise notice 'locked'; end $$; select username from public.user_profiles where id = '{b}'")
    check("lock: after confirming, the handle is immutable", lock2 and lock2[0]["username"] == f"smokeb{ts[-4:]}", lock2)

    bad = run(f"do $$ begin update public.user_profiles set username = 'Bad Name!' where id = '{d}'; exception when check_violation then raise notice 'format'; end $$; select username from public.user_profiles where id = '{d}'")
    check("lock: a malformed handle is refused", bad and bad[0]["username"] == "smokehandleb2", bad)
finally:
    for uid in created:
        admin("DELETE", f"/auth/v1/admin/users/{uid}")
    left = run("select count(*)::int as n from public.user_profiles where id in (" + ",".join(f"'{u}'" for u in created) + ")") if created else [{"n": 0}]
    results.append(("cleanup: throwaway profiles gone", "PASS" if left and left[0]["n"] == 0 else "FAIL", left))

for name, status, got in results:
    print(f"{status}  {name}  {json.dumps(got)[:160]}")
sys.exit(0 if all(s == "PASS" for _, s, _ in results) else 1)
```

- [ ] **Step 4: Run it**

Run: `python3 /tmp/pw/handle_trigger_check.py`
Expected: nine `PASS` lines (A, B, D, C, three lock checks, the confirm step, cleanup) and exit code 0. A `FAIL` on B/D/C means the generator differs from §4.3 — fix the function in the migration file, re-run `sbq.py -f` (the `create or replace` is idempotent), and re-run this check.

- [ ] **Step 5: Commit nothing (the migration file is already committed); note the run in the final report.**

---

### Task 3: Turn the providers on in Supabase auth config; mirror in `config.toml`

**Files:**
- Create (outside the repo): `/tmp/pw/auth_providers_patch.py`
- Modify: `supabase/config.toml` (after the `[auth.oauth_server]` block)

**Interfaces:**
- Produces: live `external_google_*` / `external_apple_*` config that `signInWithIdToken` validates against.

- [ ] **Step 1: Write the PATCH + read-back script**

```python
#!/usr/bin/env python3
"""Enable Google + Apple (Client IDs only — no secrets) and read the result back."""
import json, subprocess, sys, tempfile
sys.path.insert(0, "/tmp/pw")
from sbq import token, REF

GOOGLE_WEB = "772942709290-2j03nu08hnumh6jfe2h0j6jkh9bnrbta.apps.googleusercontent.com"
GOOGLE_IOS = "772942709290-ha25d35f942l5blept0aiv30aculahsn.apps.googleusercontent.com"
patch = {
    "external_google_enabled": True,
    "external_google_client_id": f"{GOOGLE_WEB},{GOOGLE_IOS}",
    "external_google_skip_nonce_check": False,
    "external_apple_enabled": True,
    "external_apple_client_id": "it.gostash.web,it.gostash.stash",
}
with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
    json.dump(patch, f); body = f.name
url = f"https://api.supabase.com/v1/projects/{REF}/config/auth"
hdr = ["-H", f"Authorization: Bearer {token()}", "-H", "Content-Type: application/json"]
subprocess.run(["curl", "-s", "-o", "/dev/null", "-w", "PATCH %{http_code}\n", "-X", "PATCH", url, *hdr, "--data-binary", f"@{body}"], check=True)
cfg = json.loads(subprocess.check_output(["curl", "-s", url, *hdr], text=True))
for k in sorted(cfg):
    if k.startswith(("external_google", "external_apple")) and "secret" not in k:
        print(f"{k} = {cfg[k]!r}")
print("secrets set?", {k: bool(cfg.get(k)) for k in ("external_google_secret", "external_apple_secret")})
```

- [ ] **Step 2: Run it**

Run: `python3 /tmp/pw/auth_providers_patch.py`
Expected: `PATCH 200`; `external_google_enabled = True`; `external_google_client_id` containing both Google ids; `external_apple_enabled = True`; `external_apple_client_id = 'it.gostash.web,it.gostash.stash'`; `secrets set? {'external_google_secret': False, 'external_apple_secret': False}`. If the API split the list into `*_additional_client_ids` on read-back, that is fine — record the shape it kept in the final report.

- [ ] **Step 3: Mirror in `supabase/config.toml`** — insert after the `[auth.oauth_server]` block:

```toml
# Hosted project has the same values (set 2026-10-11 via the Management API, plan
# docs/superpowers/plans/2026-10-11-google-apple-sign-in-web.md Task 3). Id-token sign-in only:
# the clients get the token from Google/Apple themselves, so no provider secret exists anywhere.
[auth.external.google]
enabled = true
client_id = "772942709290-2j03nu08hnumh6jfe2h0j6jkh9bnrbta.apps.googleusercontent.com,772942709290-ha25d35f942l5blept0aiv30aculahsn.apps.googleusercontent.com"
secret = ""
skip_nonce_check = false

[auth.external.apple]
enabled = true
client_id = "it.gostash.web,it.gostash.stash"
secret = ""
```

- [ ] **Step 4: Commit**

```bash
git add supabase/config.toml
git commit -m "chore(auth): Google and Apple providers on, Client IDs only"
```

---

### Task 4: Types, provider constants, and the nonce helper

**Files:**
- Modify: `src/integrations/supabase/types.ts` (the `user_profiles` block, around line 655)
- Create: `src/integrations/auth/providers.ts`
- Create: `src/utils/nonce.ts`, `src/utils/nonce.test.ts`

**Interfaces:**
- Produces: `GOOGLE_WEB_CLIENT_ID`, `APPLE_SERVICES_ID`, `appleRedirectUri(): string`, `GIS_SRC`, `APPLE_JS_SRC`; `makeNonce(): Promise<{ raw: string; hashed: string }>`, `sha256Hex(text: string): Promise<string>`; typed `handle_confirmed` on `user_profiles`.

- [ ] **Step 1: Add `handle_confirmed` to the generated types** — in `src/integrations/supabase/types.ts`, inside `user_profiles`, add to `Row` the line `handle_confirmed: boolean`, and to both `Insert` and `Update` the line `handle_confirmed?: boolean`, each in alphabetical position (after `first_name`). The file says "automatically generated"; `share_token` was added the same way by hand on 2026-10-09.

- [ ] **Step 2: Write the provider constants**

```ts
// src/integrations/auth/providers.ts
// Public identifiers for the id-token sign-in flows (spec §5.1 and §12 "Done 2026-10-11"). These
// are audiences, not secrets: Supabase accepts a Google/Apple identity token only when its `aud`
// is one of the Client IDs configured on the project, and the browser never holds a secret.
export const GOOGLE_WEB_CLIENT_ID = '772942709290-2j03nu08hnumh6jfe2h0j6jkh9bnrbta.apps.googleusercontent.com';
export const APPLE_SERVICES_ID = 'it.gostash.web';
/** Apple requires the registered return URL even for the popup flow: `/auth` on this origin. */
export const appleRedirectUri = () => `${window.location.origin}/auth`;
export const GIS_SRC = 'https://accounts.google.com/gsi/client';
export const APPLE_JS_SRC = 'https://appleid.cdn-apple.com/appleauth/static/jsapi/appleid/1/en_US/appleid.auth.js';
```

- [ ] **Step 3: Write the failing nonce test**

```ts
// src/utils/nonce.test.ts
import { webcrypto } from 'node:crypto';
import { makeNonce, sha256Hex } from './nonce';

// jsdom has no subtle crypto; the browser does
if (!globalThis.crypto?.subtle) vi.stubGlobal('crypto', webcrypto);

describe('nonce', () => {
  it('hashes with SHA-256 as lowercase hex', async () => {
    expect(await sha256Hex('abc')).toBe('ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
  });

  it('makes a fresh base64url raw nonce whose hash is what the provider gets', async () => {
    const a = await makeNonce();
    const b = await makeNonce();
    expect(a.raw).toMatch(/^[A-Za-z0-9_-]{43}$/);
    expect(a.hashed).toBe(await sha256Hex(a.raw));
    expect(a.raw).not.toBe(b.raw);
  });
});
```

- [ ] **Step 4: Run it to see it fail**

Run: `npx vitest run src/utils/nonce.test.ts`
Expected: FAIL — `Cannot find module './nonce'`.

- [ ] **Step 5: Write the helper**

```ts
// src/utils/nonce.ts
// The id-token rule (spec §4.1): the provider receives the SHA-256 of a random nonce and signs
// it into the identity token; Supabase receives the raw nonce and checks the hash matches.
const toHex = (bytes: Uint8Array) => Array.from(bytes, (b) => b.toString(16).padStart(2, '0')).join('');
const toBase64Url = (bytes: Uint8Array) =>
  btoa(String.fromCharCode(...bytes)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');

export const sha256Hex = async (text: string) =>
  toHex(new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(text))));

export type Nonce = { raw: string; hashed: string };

export const makeNonce = async (): Promise<Nonce> => {
  const raw = toBase64Url(crypto.getRandomValues(new Uint8Array(32)));
  return { raw, hashed: await sha256Hex(raw) };
};
```

- [ ] **Step 6: Run the test and the typecheck**

Run: `npx vitest run src/utils/nonce.test.ts && npx tsc --noEmit -p tsconfig.app.json`
Expected: 2 tests PASS; tsc prints nothing.

- [ ] **Step 7: Commit**

```bash
git add src/integrations/supabase/types.ts src/integrations/auth/providers.ts src/utils/nonce.ts src/utils/nonce.test.ts
git commit -m "feat(auth): provider identifiers, nonce helper, handle_confirmed type"
```

---

### Task 5: `useAuth` learns id-token sign-in and the handle state

**Files:**
- Modify: `src/hooks/useAuth.tsx`
- Create: `src/hooks/useAuth.test.tsx`

**Interfaces:**
- Produces (added to the context):
  - `signInWithIdToken(args: { provider: 'google' | 'apple'; token: string; nonce: string }): Promise<{ error: AuthError | null }>`
  - `handle: { username: string; confirmed: boolean } | null` — null while signed out, anonymous, or not yet loaded
  - `refreshHandle(): Promise<void>` — re-reads the row (the confirm step calls it)
  - exported types `HandleState`, `IdTokenArgs`
- Existing tests mock `useAuth` with objects lacking these fields; consumers must treat `handle === undefined` like `null` (only an explicit `confirmed === false` redirects).

- [ ] **Step 1: Write the failing test**

```tsx
// src/hooks/useAuth.test.tsx
import { render, screen, waitFor, act } from '@testing-library/react';
import { AuthProvider, useAuth } from './useAuth';

const state = vi.hoisted(() => ({
  profileRows: [] as Array<Record<string, unknown> | null>, // consumed in order by maybeSingle
  session: null as null | { user: { id: string; email: string; is_anonymous?: boolean }; access_token: string },
  signInWithIdToken: vi.fn(async () => ({ data: {}, error: null })),
}));

vi.mock('@/integrations/supabase/client', () => ({
  supabase: {
    auth: {
      onAuthStateChange: () => ({ data: { subscription: { unsubscribe: vi.fn() } } }),
      getSession: async () => ({ data: { session: state.session } }),
      signInWithIdToken: state.signInWithIdToken,
      signOut: vi.fn(),
    },
    from: () => ({
      select: () => ({
        eq: () => ({
          maybeSingle: async () => ({ data: state.profileRows.shift() ?? null, error: null }),
        }),
      }),
    }),
  },
}));

const Probe = () => {
  const { handle, loading, signInWithIdToken } = useAuth();
  return (
    <div>
      <span data-testid="loading">{String(loading)}</span>
      <span data-testid="handle">{handle ? `${handle.username}:${handle.confirmed}` : 'null'}</span>
      <button onClick={() => signInWithIdToken({ provider: 'google', token: 'tok', nonce: 'raw' })}>go</button>
    </div>
  );
};

const renderProbe = () => render(<AuthProvider><Probe /></AuthProvider>);

describe('useAuth — handle + id-token', () => {
  beforeEach(() => {
    vi.useFakeTimers({ shouldAdvanceTime: true });
    state.profileRows = [];
    state.session = { user: { id: 'u1', email: 'will@example.com' }, access_token: 't' };
    state.signInWithIdToken.mockClear();
  });
  afterEach(() => vi.useRealTimers());

  it('loads the handle for a real user', async () => {
    state.profileRows = [{ username: 'will', handle_confirmed: false }];
    renderProbe();
    await waitFor(() => expect(screen.getByTestId('handle')).toHaveTextContent('will:false'));
  });

  it('keeps the handle null for an anonymous session', async () => {
    state.session = { user: { id: 'anon', email: '', is_anonymous: true }, access_token: 't' };
    renderProbe();
    await waitFor(() => expect(screen.getByTestId('loading')).toHaveTextContent('false'));
    expect(screen.getByTestId('handle')).toHaveTextContent('null');
  });

  it('retries once, then fails open when the profile row is missing', async () => {
    state.profileRows = [null, null];
    renderProbe();
    await act(async () => { await vi.advanceTimersByTimeAsync(600); });
    await waitFor(() => expect(screen.getByTestId('handle')).toHaveTextContent(':true'));
  });

  it('passes the raw nonce and token through to Supabase', async () => {
    state.profileRows = [{ username: 'will', handle_confirmed: true }];
    renderProbe();
    await waitFor(() => expect(screen.getByTestId('handle')).toHaveTextContent('will:true'));
    screen.getByRole('button', { name: 'go' }).click();
    await waitFor(() => expect(state.signInWithIdToken).toHaveBeenCalledWith({ provider: 'google', token: 'tok', nonce: 'raw' }));
  });
});
```

- [ ] **Step 2: Run it to see it fail**

Run: `npx vitest run src/hooks/useAuth.test.tsx`
Expected: FAIL — `handle` shows `null` and `signInWithIdToken` is not a function.

- [ ] **Step 3: Extend the provider** — in `src/hooks/useAuth.tsx`:

Replace the imports and interface with:

```tsx
import { createContext, useCallback, useContext, useEffect, useState } from 'react';
import { AuthError, User, Session } from '@supabase/supabase-js';
import { supabase } from '@/integrations/supabase/client';

export type HandleState = { username: string; confirmed: boolean };
export type IdTokenArgs = { provider: 'google' | 'apple'; token: string; nonce: string };

interface AuthContextType {
  user: User | null;
  session: Session | null;
  signUp: (email: string, password: string, username: string) => Promise<{ error: any }>;
  signIn: (email: string, password: string) => Promise<{ error: any }>;
  /** Google / Apple: the provider's identity token plus the RAW nonce (its hash went to the provider) */
  signInWithIdToken: (args: IdTokenArgs) => Promise<{ error: AuthError | null }>;
  signOut: () => Promise<void>;
  loading: boolean;
  /** The person's @handle and whether they confirmed it; null while signed out, anonymous, or unknown */
  handle: HandleState | null;
  /** Re-read the handle row (the confirm step calls this after writing) */
  refreshHandle: () => Promise<void>;
}

const isRealUser = (u: User | null) => !!u && !(u as { is_anonymous?: boolean }).is_anonymous;
const HANDLE_RETRY_MS = 500;

async function fetchHandle(userId: string): Promise<HandleState | null> {
  const { data, error } = await supabase
    .from('user_profiles')
    .select('username, handle_confirmed')
    .eq('id', userId)
    .maybeSingle();
  if (error) {
    console.warn('[auth] handle lookup failed:', error.message);
    return null;
  }
  return data ? { username: data.username, confirmed: data.handle_confirmed } : null;
}
```

Inside `AuthProvider`, after the `loading` state, add:

```tsx
  const [handle, setHandle] = useState<HandleState | null>(null);

  const refreshHandle = useCallback(async () => {
    if (!isRealUser(user)) {
      setHandle(null);
      return;
    }
    let next = await fetchHandle(user!.id);
    if (!next) {
      // The row is written by the sign-up trigger in the same transaction as the auth user, but a
      // replica or a slow round can make it miss once. Try again, then fail open: nobody gets stuck
      // on the way in because of a lookup; the step simply shows next time.
      await new Promise((resolve) => setTimeout(resolve, HANDLE_RETRY_MS));
      next = await fetchHandle(user!.id);
    }
    setHandle(next ?? { username: '', confirmed: true });
  }, [user]);

  useEffect(() => {
    setHandle(null);
    if (isRealUser(user)) void refreshHandle();
  }, [user?.id, refreshHandle]);

  const signInWithIdToken = async ({ provider, token, nonce }: IdTokenArgs) => {
    const { error } = await supabase.auth.signInWithIdToken({ provider, token, nonce });
    return { error };
  };
```

and extend the provider value: `value={{ user, session, signUp, signIn, signInWithIdToken, signOut, loading, handle, refreshHandle }}`.

- [ ] **Step 4: Run the test and the typecheck**

Run: `npx vitest run src/hooks/useAuth.test.tsx && npx tsc --noEmit -p tsconfig.app.json`
Expected: 4 tests PASS; tsc prints nothing (the `select('username, handle_confirmed')` typing needs Task 4's `types.ts` change).

- [ ] **Step 5: Run the whole suite** — `npx vitest run` → still green (existing `useAuth` mocks don't need the new fields yet).

- [ ] **Step 6: Commit**

```bash
git add src/hooks/useAuth.tsx src/hooks/useAuth.test.tsx
git commit -m "feat(auth): id-token sign-in and the handle state in useAuth"
```

---

### Task 6: Username helpers shared by sign-up and the handle step; extract the form controls

**Files:**
- Create: `src/components/auth/usernameAvailability.ts`, `src/components/auth/usernameAvailability.test.ts`
- Create: `src/components/auth/AuthControls.tsx` (moves `SubmitButton` and the `field` class string out of `Auth.tsx`)
- Modify: `src/pages/Auth.tsx` (import the two; replace the inline `checkUsernameUniqueness` body and the onChange sanitizer)

**Interfaces:**
- Produces: `USERNAME_RE`, `sanitizeUsername(input: string): string`, `suggestHandle(fullName?: string | null): string | null`, `isUsernameTaken(username: string, exceptUserId?: string): Promise<boolean>`; `SubmitButton`, `field` from `AuthControls`.

- [ ] **Step 1: Write the failing test**

```ts
// src/components/auth/usernameAvailability.test.ts
import { USERNAME_RE, isUsernameTaken, sanitizeUsername, suggestHandle } from './usernameAvailability';

const probe = vi.hoisted(() => ({ row: null as null | { id: string } }));
vi.mock('@/integrations/supabase/client', () => ({
  supabase: {
    from: () => ({ select: () => ({ eq: () => ({ maybeSingle: async () => ({ data: probe.row, error: null }) }) }) }),
  },
}));

describe('usernameAvailability', () => {
  it('sanitizes to lowercase [a-z0-9], max 20', () => {
    expect(sanitizeUsername('@Will Dzierson!')).toBe('willdzierson');
    expect(sanitizeUsername('a'.repeat(30))).toHaveLength(20);
    expect(USERNAME_RE.test('ab')).toBe(false);
    expect(USERNAME_RE.test('abc')).toBe(true);
  });

  it('suggests a handle from a name only when it is long enough', () => {
    expect(suggestHandle('Will Dzierson')).toBe('willdzierson');
    expect(suggestHandle('李')).toBeNull();
    expect(suggestHandle(undefined)).toBeNull();
  });

  it('treats the person\'s own row as available', async () => {
    probe.row = { id: 'u1' };
    expect(await isUsernameTaken('will')).toBe(true);
    expect(await isUsernameTaken('will', 'u1')).toBe(false);
    probe.row = null;
    expect(await isUsernameTaken('free')).toBe(false);
  });
});
```

- [ ] **Step 2: Run it to see it fail** — `npx vitest run src/components/auth/usernameAvailability.test.ts` → FAIL (module missing).

- [ ] **Step 3: Write the helpers and the extracted controls**

```ts
// src/components/auth/usernameAvailability.ts
import { supabase } from '@/integrations/supabase/client';

/** What the forms accept and the DB lock trigger enforces on change (spec §4.3) */
export const USERNAME_RE = /^[a-z0-9]{3,20}$/;

export const sanitizeUsername = (input: string) => input.toLowerCase().replace(/[^a-z0-9]/g, '').slice(0, 20);

/** A handle suggested from a provider name ("Will Dzierson" → willdzierson), or null if too short */
export const suggestHandle = (fullName?: string | null) => {
  const s = sanitizeUsername(fullName ?? '');
  return s.length >= 3 ? s : null;
};

/** Live availability probe; a person's own row never counts as taken */
export async function isUsernameTaken(username: string, exceptUserId?: string): Promise<boolean> {
  const { data, error } = await supabase.from('user_profiles').select('id').eq('username', username).maybeSingle();
  if (error) {
    console.error('Error checking username:', error);
    return false;
  }
  return !!data && data.id !== exceptUserId;
}
```

```tsx
// src/components/auth/AuthControls.tsx
import { ArrowRight } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Spinner } from '@/components/machine/Machine';

// DESIGN-v2 forms: Montreal labels over square white fields (ink edge and spot ring on focus,
// from the shared Input), one ink button, quiet machine-voice text actions
export const field = 'h-11 text-[15px] md:text-[15px]';

/** The one ink button: its label, or the machine at work with the spinner */
export const SubmitButton = ({ busy, busyLabel, children, disabled }: { busy: boolean; busyLabel: string; children: React.ReactNode; disabled?: boolean }) => (
  <Button type="submit" disabled={busy || disabled} className="h-11 w-full justify-between px-4 text-[15px] font-medium">
    {busy ? (
      <span className="flex items-baseline gap-[0.5ch] font-pixel text-pixel">
        <Spinner />
        {busyLabel}
      </span>
    ) : (
      <>
        <span>{children}</span>
        <ArrowRight className="h-4 w-4" />
      </>
    )}
  </Button>
);
```

In `src/pages/Auth.tsx`: delete the local `field` constant and `SubmitButton` component and the now-unused `ArrowRight`, `Button`, `Spinner` imports; add `import { SubmitButton, field } from '@/components/auth/AuthControls';` and `import { isUsernameTaken, sanitizeUsername } from '@/components/auth/usernameAvailability';`. Replace the body of `checkUsernameUniqueness` with:

```tsx
  const checkUsernameUniqueness = async (username: string) => {
    if (!username || username.length < 3) return;
    setUsernameError((await isUsernameTaken(username)) ? 'that username is taken. try another.' : '');
  };
```

and in the username `onChange`, replace `e.target.value.toLowerCase().replace(/[^a-z0-9]/g, '')` with `sanitizeUsername(e.target.value)`.

- [ ] **Step 4: Run the tests** — `npx vitest run src/components/auth src/pages/Auth.test.tsx && npx tsc --noEmit -p tsconfig.app.json` → PASS, no type errors (the `Auth.test.tsx` `from()` mock already answers the probe with `PGRST116`/null; `maybeSingle` must be added to that mock: change its `single:` key to `maybeSingle:` returning `{ data: null, error: null }`).

- [ ] **Step 5: Commit**

```bash
git add src/components/auth/usernameAvailability.ts src/components/auth/usernameAvailability.test.ts src/components/auth/AuthControls.tsx src/pages/Auth.tsx src/pages/Auth.test.tsx
git commit -m "refactor(auth): shared username helpers and form controls"
```

---

### Task 7: Load the two provider scripts once, and only on the way in

**Files:**
- Create: `src/components/auth/useProviderScripts.ts`, `src/components/auth/useProviderScripts.test.tsx`

**Interfaces:**
- Produces: `loadScript(src: string): Promise<void>`, `resetScriptCacheForTests(): void`, `type ScriptStatus = 'loading' | 'ready' | 'failed'`, `useProviderScripts(): { google: ScriptStatus; apple: ScriptStatus }`.

- [ ] **Step 1: Write the failing test**

```tsx
// src/components/auth/useProviderScripts.test.tsx
import { act, render, screen } from '@testing-library/react';
import { GIS_SRC, APPLE_JS_SRC } from '@/integrations/auth/providers';
import { resetScriptCacheForTests, useProviderScripts } from './useProviderScripts';

const Probe = () => {
  const s = useProviderScripts();
  return <span data-testid="s">{`${s.google}/${s.apple}`}</span>;
};
const tag = (src: string) => document.querySelector<HTMLScriptElement>(`script[src="${src}"]`)!;

describe('useProviderScripts', () => {
  beforeEach(() => {
    resetScriptCacheForTests();
    document.head.querySelectorAll('script').forEach((el) => el.remove());
  });

  it('injects each script once and reports load and failure separately', async () => {
    render(<Probe />);
    render(<Probe />);
    expect(document.querySelectorAll(`script[src="${GIS_SRC}"]`)).toHaveLength(1);
    expect(screen.getAllByTestId('s')[0]).toHaveTextContent('loading/loading');
    await act(async () => { tag(GIS_SRC).dispatchEvent(new Event('load')); });
    await act(async () => { tag(APPLE_JS_SRC).dispatchEvent(new Event('error')); });
    expect(screen.getAllByTestId('s')[0]).toHaveTextContent('ready/failed');
  });

  it('lets a blocked script be retried on the next mount', async () => {
    const first = render(<Probe />);
    await act(async () => { tag(APPLE_JS_SRC).dispatchEvent(new Event('error')); });
    first.unmount();
    document.head.querySelectorAll('script').forEach((el) => el.remove());
    render(<Probe />);
    expect(document.querySelectorAll(`script[src="${APPLE_JS_SRC}"]`)).toHaveLength(1);
  });
});
```

- [ ] **Step 2: Run it to see it fail** — `npx vitest run src/components/auth/useProviderScripts.test.tsx` → FAIL (module missing).

- [ ] **Step 3: Write the hook**

```ts
// src/components/auth/useProviderScripts.ts
import { useEffect, useState } from 'react';
import { APPLE_JS_SRC, GIS_SRC } from '@/integrations/auth/providers';

// The provider SDKs are third-party scripts; they load only on the way in, once per page session.
// A blocked script (privacy extensions) fails quietly: its button slot collapses and the email form
// is never affected (spec §6.1).
const cache = new Map<string, Promise<void>>();

export function loadScript(src: string): Promise<void> {
  const cached = cache.get(src);
  if (cached) return cached;
  const promise = new Promise<void>((resolve, reject) => {
    const existing = document.querySelector<HTMLScriptElement>(`script[src="${src}"]`);
    const el = existing ?? document.createElement('script');
    el.addEventListener('load', () => resolve(), { once: true });
    el.addEventListener('error', () => reject(new Error(`script failed: ${src}`)), { once: true });
    if (!existing) {
      el.src = src;
      el.async = true;
      document.head.appendChild(el);
    }
  });
  cache.set(src, promise);
  promise.catch(() => cache.delete(src)); // a blocked script can be tried again on the next mount
  return promise;
}

export const resetScriptCacheForTests = () => cache.clear();

export type ScriptStatus = 'loading' | 'ready' | 'failed';

export function useProviderScripts(): { google: ScriptStatus; apple: ScriptStatus } {
  const [google, setGoogle] = useState<ScriptStatus>('loading');
  const [apple, setApple] = useState<ScriptStatus>('loading');
  useEffect(() => {
    let mounted = true;
    loadScript(GIS_SRC).then(() => mounted && setGoogle('ready'), () => mounted && setGoogle('failed'));
    loadScript(APPLE_JS_SRC).then(() => mounted && setApple('ready'), () => mounted && setApple('failed'));
    return () => { mounted = false; };
  }, []);
  return { google, apple };
}
```

- [ ] **Step 4: Run the test** — `npx vitest run src/components/auth/useProviderScripts.test.tsx` → 2 PASS.

- [ ] **Step 5: Commit**

```bash
git add src/components/auth/useProviderScripts.ts src/components/auth/useProviderScripts.test.tsx
git commit -m "feat(auth): load the Google and Apple scripts once, on the way in only"
```

---

### Task 8: `ProviderButtons` — the Google-rendered and Apple-rendered pair

**Files:**
- Create: `src/components/auth/ProviderButtons.tsx`, `src/components/auth/ProviderButtons.test.tsx`

**Interfaces:**
- Consumes: `useProviderScripts`, `makeNonce`, the constants from Task 4.
- Produces: `type ProviderIdToken = { provider: 'google' | 'apple'; token: string; nonce: string; appleCode?: string; appleName?: { firstName?: string; lastName?: string } }` and `<ProviderButtons onToken={(t: ProviderIdToken) => Promise<void>} onError={(message: string) => void} />`. `onToken` is awaited; a second credential arriving while one is pending is dropped (Review Focus 1).

- [ ] **Step 1: Write the failing test**

```tsx
// src/components/auth/ProviderButtons.test.tsx
import { act, render, screen, waitFor } from '@testing-library/react';
import { webcrypto } from 'node:crypto';
import { GOOGLE_WEB_CLIENT_ID, APPLE_SERVICES_ID } from '@/integrations/auth/providers';
import { ProviderButtons, type ProviderIdToken } from './ProviderButtons';

if (!globalThis.crypto?.subtle) vi.stubGlobal('crypto', webcrypto);

const scripts = vi.hoisted(() => ({ google: 'ready', apple: 'ready' }));
vi.mock('./useProviderScripts', () => ({ useProviderScripts: () => scripts }));

type GoogleInit = { client_id: string; nonce: string; callback: (r: { credential: string }) => void };
const google = { init: null as GoogleInit | null, render: vi.fn() };
const apple = { init: null as null | { clientId: string; nonce: string; redirectURI: string; usePopup: boolean }, render: vi.fn() };

beforeEach(() => {
  scripts.google = 'ready';
  scripts.apple = 'ready';
  google.init = null;
  google.render.mockClear();
  apple.init = null;
  apple.render.mockClear();
  (window as any).google = { accounts: { id: { initialize: (cfg: GoogleInit) => { google.init = cfg; }, renderButton: google.render } } };
  (window as any).AppleID = { auth: { init: (cfg: typeof apple.init) => { apple.init = cfg; }, renderButton: apple.render } };
});

const sha256 = async (s: string) =>
  Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(s)))).map((b) => b.toString(16).padStart(2, '0')).join('');

const setup = (onToken = vi.fn(async (_t: ProviderIdToken) => {}), onError = vi.fn()) => {
  render(<ProviderButtons onToken={onToken} onError={onError} />);
  return { onToken, onError };
};

describe('ProviderButtons', () => {
  it('initializes Google with the hashed nonce and delivers the credential with the raw one', async () => {
    const { onToken } = setup();
    await waitFor(() => expect(google.init).not.toBeNull());
    expect(google.init!.client_id).toBe(GOOGLE_WEB_CLIENT_ID);
    expect(google.render).toHaveBeenCalledWith(expect.any(HTMLElement), expect.objectContaining({ theme: 'outline', shape: 'rectangular', text: 'continue_with', width: 356 }));
    await act(async () => { google.init!.callback({ credential: 'g.jwt' }); });
    expect(onToken).toHaveBeenCalledTimes(1);
    const t = onToken.mock.calls[0][0];
    expect(t).toMatchObject({ provider: 'google', token: 'g.jwt' });
    expect(google.init!.nonce).toBe(await sha256(t.nonce));
  });

  it('ignores a second credential while one is in flight', async () => {
    let release: () => void = () => {};
    const onToken = vi.fn(() => new Promise<void>((r) => { release = r; }));
    setup(onToken);
    await waitFor(() => expect(google.init).not.toBeNull());
    act(() => { google.init!.callback({ credential: 'one' }); });
    act(() => { google.init!.callback({ credential: 'two' }); });
    expect(onToken).toHaveBeenCalledTimes(1);
    await act(async () => { release(); });
  });

  it('initializes Apple as a popup against /auth and delivers the token, code and name', async () => {
    const { onToken } = setup();
    await waitFor(() => expect(apple.init).not.toBeNull());
    expect(apple.init).toMatchObject({ clientId: APPLE_SERVICES_ID, usePopup: true, redirectURI: `${window.location.origin}/auth` });
    expect(apple.render).toHaveBeenCalled();
    await act(async () => {
      document.dispatchEvent(new CustomEvent('AppleIDSignInOnSuccess', { detail: { authorization: { id_token: 'a.jwt', code: 'c0de' }, user: { name: { firstName: 'Will', lastName: 'D' } } } }));
    });
    const t = onToken.mock.calls[0][0];
    expect(t).toMatchObject({ provider: 'apple', token: 'a.jwt', appleCode: 'c0de', appleName: { firstName: 'Will', lastName: 'D' } });
    expect(apple.init!.nonce).toBe(await sha256(t.nonce));
  });

  it('is silent when the Apple popup is closed, loud on any other failure', async () => {
    const { onError } = setup();
    await waitFor(() => expect(apple.init).not.toBeNull());
    await act(async () => { document.dispatchEvent(new CustomEvent('AppleIDSignInOnFailure', { detail: { error: 'popup_closed_by_user' } })); });
    expect(onError).not.toHaveBeenCalled();
    await act(async () => { document.dispatchEvent(new CustomEvent('AppleIDSignInOnFailure', { detail: { error: 'invalid_request' } })); });
    expect(onError).toHaveBeenCalledWith('invalid_request');
  });

  it('collapses a slot whose script failed and keeps the other', async () => {
    scripts.apple = 'failed';
    setup();
    await waitFor(() => expect(google.init).not.toBeNull());
    expect(document.getElementById('appleid-signin')).toBeNull();
    expect(screen.getByTestId('google-slot')).toBeInTheDocument();
  });
});
```

- [ ] **Step 2: Run it to see it fail** — `npx vitest run src/components/auth/ProviderButtons.test.tsx` → FAIL (module missing).

- [ ] **Step 3: Write the component**

```tsx
// src/components/auth/ProviderButtons.tsx
import { useEffect, useRef, useState } from 'react';
import { APPLE_SERVICES_ID, GOOGLE_WEB_CLIENT_ID, appleRedirectUri } from '@/integrations/auth/providers';
import { makeNonce } from '@/utils/nonce';
import { useProviderScripts } from './useProviderScripts';

/** What a provider handed us: its identity token, the RAW nonce whose hash it signed, and Apple's extras */
export type ProviderIdToken = {
  provider: 'google' | 'apple';
  token: string;
  nonce: string;
  /** Apple's one-shot authorization code, exchanged server-side so deletion can revoke (spec §5.3) */
  appleCode?: string;
  /** Apple sends the name once, on first authorization, and never again (spec §4.4) */
  appleName?: { firstName?: string; lastName?: string };
};

type GoogleCredential = { credential: string };
declare global {
  interface Window {
    google?: {
      accounts: {
        id: {
          initialize: (cfg: { client_id: string; nonce: string; callback: (r: GoogleCredential) => void; use_fedcm_for_prompt?: boolean; auto_select?: boolean }) => void;
          renderButton: (el: HTMLElement, opts: Record<string, string | number>) => void;
        };
      };
    };
    AppleID?: {
      auth: {
        init: (cfg: { clientId: string; scope: string; redirectURI: string; usePopup: boolean; nonce: string }) => void;
        renderButton: () => void;
      };
    };
  }
}

const BUTTON_HEIGHT = 40; // GIS "large" is fixed at 40 px; Apple's is set to match (spec §6.1)
const clampWidth = (w: number) => Math.min(400, Math.max(200, w || 356));

/**
 * The provider pair (DESIGN-v2 §12.14): Google's rendered button, then Apple's, both square,
 * both "Continue with …", at the window body's measured width. Each attempt gets its own nonce.
 */
export const ProviderButtons = ({ onToken, onError }: { onToken: (t: ProviderIdToken) => Promise<void> | void; onError: (message: string) => void }) => {
  const scripts = useProviderScripts();
  const wrapRef = useRef<HTMLDivElement>(null);
  const googleRef = useRef<HTMLDivElement>(null);
  const [width, setWidth] = useState(0);
  const [attempt, setAttempt] = useState(0);
  const inFlight = useRef(false);

  // One credential at a time: a double-click or a second tab can't start a second sign-in
  const deliver = async (t: ProviderIdToken) => {
    if (inFlight.current) return;
    inFlight.current = true;
    try {
      await onToken(t);
    } finally {
      inFlight.current = false;
      setAttempt((a) => a + 1); // fresh nonces for the next try
    }
  };

  useEffect(() => {
    const el = wrapRef.current;
    if (!el) return;
    const measure = () => setWidth(clampWidth(el.clientWidth));
    measure();
    const ro = new ResizeObserver(measure);
    ro.observe(el);
    return () => ro.disconnect();
  }, []);

  useEffect(() => {
    if (scripts.google !== 'ready' || !width || !googleRef.current || !window.google) return;
    let cancelled = false;
    const slot = googleRef.current;
    void makeNonce().then((nonce) => {
      if (cancelled) return;
      window.google!.accounts.id.initialize({
        client_id: GOOGLE_WEB_CLIENT_ID,
        nonce: nonce.hashed,
        callback: (r) => void deliver({ provider: 'google', token: r.credential, nonce: nonce.raw }),
        use_fedcm_for_prompt: true,
        auto_select: false,
      });
      slot.innerHTML = '';
      window.google!.accounts.id.renderButton(slot, {
        type: 'standard', theme: 'outline', size: 'large', text: 'continue_with', shape: 'rectangular', logo_alignment: 'left', width,
      });
    });
    return () => { cancelled = true; };
  }, [scripts.google, width, attempt]);

  useEffect(() => {
    if (scripts.apple !== 'ready' || !width || !window.AppleID) return;
    let cancelled = false;
    let raw = '';
    const onSuccess = (e: Event) => {
      const d = (e as CustomEvent).detail ?? {};
      void deliver({ provider: 'apple', token: d.authorization?.id_token, nonce: raw, appleCode: d.authorization?.code, appleName: d.user?.name });
    };
    const onFailure = (e: Event) => {
      const err = (e as CustomEvent).detail?.error;
      if (err !== 'popup_closed_by_user') onError(String(err ?? 'Apple sign-in failed'));
    };
    void makeNonce().then((nonce) => {
      if (cancelled) return;
      raw = nonce.raw;
      window.AppleID!.auth.init({ clientId: APPLE_SERVICES_ID, scope: 'name email', redirectURI: appleRedirectUri(), usePopup: true, nonce: nonce.hashed });
      const slot = document.getElementById('appleid-signin');
      if (slot) slot.innerHTML = '';
      window.AppleID!.auth.renderButton();
      document.addEventListener('AppleIDSignInOnSuccess', onSuccess);
      document.addEventListener('AppleIDSignInOnFailure', onFailure);
    });
    return () => {
      cancelled = true;
      document.removeEventListener('AppleIDSignInOnSuccess', onSuccess);
      document.removeEventListener('AppleIDSignInOnFailure', onFailure);
    };
  }, [scripts.apple, width, attempt]);

  if (scripts.google === 'failed' && scripts.apple === 'failed') return null;
  return (
    <div ref={wrapRef} className="space-y-3">
      {scripts.google !== 'failed' && <div ref={googleRef} data-testid="google-slot" style={{ minHeight: BUTTON_HEIGHT }} />}
      {scripts.apple !== 'failed' && (
        <div
          id="appleid-signin"
          data-mode="center-align"
          data-type="continue"
          data-color="black"
          data-border="false"
          data-border-radius="0"
          data-width={String(width || 356)}
          data-height={String(BUTTON_HEIGHT)}
          style={{ minHeight: BUTTON_HEIGHT }}
        />
      )}
    </div>
  );
};
```

- [ ] **Step 4: Run the test and the typecheck** — `npx vitest run src/components/auth/ProviderButtons.test.tsx && npx tsc --noEmit -p tsconfig.app.json` → 5 PASS, no type errors.

- [ ] **Step 5: Commit**

```bash
git add src/components/auth/ProviderButtons.tsx src/components/auth/ProviderButtons.test.tsx
git commit -m "feat(auth): the Google and Apple button pair on the id-token flow"
```

---

### Task 9: `HandleStep` — claim your address

**Files:**
- Create: `src/components/auth/HandleStep.tsx`, `src/components/auth/HandleStep.test.tsx`

**Interfaces:**
- Consumes: `sanitizeUsername`, `USERNAME_RE`, `isUsernameTaken` (Task 6); `SubmitButton`, `field` (Task 6); `FieldError` from `AuthShell`.
- Produces: `<HandleStep userId initialUsername onClaimed />` — writes `user_profiles.{username, handle_confirmed: true}` and calls `onClaimed()`.

- [ ] **Step 1: Write the failing test**

```tsx
// src/components/auth/HandleStep.test.tsx
import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import { HandleStep } from './HandleStep';

const db = vi.hoisted(() => ({
  taken: null as null | { id: string },
  update: vi.fn(async () => ({ error: null as null | { code: string; message: string } })),
  updated: null as null | Record<string, unknown>,
}));
vi.mock('@/integrations/supabase/client', () => ({
  supabase: {
    from: () => ({
      select: () => ({ eq: () => ({ maybeSingle: async () => ({ data: db.taken, error: null }) }) }),
      update: (row: Record<string, unknown>) => { db.updated = row; return { eq: db.update }; },
    }),
  },
}));
const toast = vi.fn();
vi.mock('@/hooks/use-toast', () => ({ useToast: () => ({ toast }) }));

const setup = (initial = 'willdzierson') => {
  const onClaimed = vi.fn();
  render(<HandleStep userId="u1" initialUsername={initial} onClaimed={onClaimed} />);
  return { onClaimed, input: screen.getByLabelText('Username') as HTMLInputElement, button: screen.getByRole('button', { name: /continue/i }) };
};

describe('HandleStep', () => {
  beforeEach(() => { db.taken = null; db.updated = null; db.update.mockResolvedValue({ error: null }); toast.mockClear(); });

  it('prefills the handle and shows the address it makes', () => {
    const { input } = setup();
    expect(input.value).toBe('willdzierson');
    expect(screen.getByText('gostash.it/feed/willdzierson')).toBeInTheDocument();
  });

  it('sanitizes pasted text and refuses a short handle', async () => {
    const { input, button } = setup();
    fireEvent.change(input, { target: { value: '@Will Dzierson!' } });
    expect(input.value).toBe('willdzierson');
    fireEvent.change(input, { target: { value: 'ab' } });
    fireEvent.click(button);
    expect(await screen.findByText(/3–20 letters and numbers/)).toBeInTheDocument();
    expect(db.updated).toBeNull();
  });

  it('claims the handle and reports back', async () => {
    const { onClaimed, button } = setup();
    fireEvent.click(button);
    await waitFor(() => expect(onClaimed).toHaveBeenCalled());
    expect(db.updated).toEqual({ username: 'willdzierson', handle_confirmed: true });
  });

  it('turns a unique violation into the field error', async () => {
    db.update.mockResolvedValue({ error: { code: '23505', message: 'duplicate key' } });
    const { onClaimed, button } = setup();
    fireEvent.click(button);
    expect(await screen.findByText(/that username is taken/)).toBeInTheDocument();
    expect(onClaimed).not.toHaveBeenCalled();
  });

  it('warns live when a typed handle belongs to someone else', async () => {
    db.taken = { id: 'someone-else' };
    const { input } = setup();
    fireEvent.change(input, { target: { value: 'taken' } });
    expect(await screen.findByText(/that username is taken/)).toBeInTheDocument();
  });
});
```

- [ ] **Step 2: Run it to see it fail** — `npx vitest run src/components/auth/HandleStep.test.tsx` → FAIL (module missing).

- [ ] **Step 3: Write the component**

```tsx
// src/components/auth/HandleStep.tsx
import { useEffect, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { useToast } from '@/hooks/use-toast';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { FieldError } from '@/components/auth/AuthShell';
import { SubmitButton, field } from '@/components/auth/AuthControls';
import { USERNAME_RE, isUsernameTaken, sanitizeUsername } from '@/components/auth/usernameAvailability';

const TAKEN = 'that username is taken. try another.';
const FORMAT = '3–20 letters and numbers.';

/**
 * The one-time confirm for a server-generated handle (spec §4.3): prefilled, one ink Continue.
 * Continue with the prefill IS the skip. Writes username + handle_confirmed in one update; the DB
 * lock trigger makes this the only moment a handle can ever change.
 */
export const HandleStep = ({ userId, initialUsername, onClaimed }: { userId: string; initialUsername: string; onClaimed: () => void }) => {
  const [username, setUsername] = useState(initialUsername);
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);
  const { toast } = useToast();

  // Live availability, debounced; the person's own current handle never counts as taken
  useEffect(() => {
    if (username.length < 3 || username === initialUsername) return;
    const t = setTimeout(async () => {
      if (await isUsernameTaken(username, userId)) setError(TAKEN);
    }, 300);
    return () => clearTimeout(t);
  }, [username, initialUsername, userId]);

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!USERNAME_RE.test(username)) {
      setError(FORMAT);
      return;
    }
    setBusy(true);
    const { error: dbError } = await supabase
      .from('user_profiles')
      .update({ username, handle_confirmed: true })
      .eq('id', userId);
    setBusy(false);
    if (dbError) {
      if (dbError.code === '23505') setError(TAKEN);
      else toast({ title: "That didn't take.", description: dbError.message, variant: 'destructive' });
      return;
    }
    onClaimed();
  };

  return (
    <form onSubmit={submit} className="space-y-5">
      <div className="space-y-2">
        <Label htmlFor="handle-username">Username</Label>
        <div className="relative">
          <span className="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 font-code text-[14px] text-muted-foreground">@</span>
          <Input
            id="handle-username"
            type="text"
            autoComplete="off"
            value={username}
            onChange={(e) => { setUsername(sanitizeUsername(e.target.value)); setError(''); }}
            required
            minLength={3}
            maxLength={20}
            autoFocus
            aria-invalid={Boolean(error)}
            aria-describedby={error ? 'handle-username-error' : undefined}
            className={`${field} pl-7 font-code md:text-[14px] text-[14px] ${error ? 'v2:border-error' : ''}`}
          />
        </div>
        {error ? (
          <FieldError id="handle-username-error">{error}</FieldError>
        ) : (
          <p className="text-[13px] leading-snug text-muted-foreground">
            Your public feed: <span className="font-code text-[12.5px] text-ink">gostash.it/feed/{username || 'you'}</span>
          </p>
        )}
      </div>
      <SubmitButton busy={busy} busyLabel="claiming…" disabled={!!error}>
        Continue
      </SubmitButton>
    </form>
  );
};
```

- [ ] **Step 4: Run the test and the typecheck** — `npx vitest run src/components/auth/HandleStep.test.tsx && npx tsc --noEmit -p tsconfig.app.json` → 5 PASS, no type errors.

- [ ] **Step 5: Commit**

```bash
git add src/components/auth/HandleStep.tsx src/components/auth/HandleStep.test.tsx
git commit -m "feat(auth): the handle step — claim your address"
```

---

### Task 10: The way in — provider pair, handle view, gate, copy

**Files:**
- Create: `src/components/auth/appleName.ts`, `src/components/auth/appleName.test.ts`
- Modify: `src/pages/Auth.tsx`
- Modify: `src/pages/Auth.test.tsx`

**Interfaces:**
- Consumes: `ProviderButtons`/`ProviderIdToken` (Task 8), `HandleStep` (Task 9), `useAuth().signInWithIdToken / handle / refreshHandle` (Task 5), `suggestHandle` (Task 6).
- Produces: `writeAppleName(user: User, name: { firstName?: string; lastName?: string }): Promise<void>`, `isFallbackDisplayName(displayName, username, email): boolean`; the `/auth?mode=handle` deep link; the behaviour Task 11 and plan 2 rely on: a signed-in person never leaves `/auth` until `handle.confirmed` is true.

- [ ] **Step 1: Write the failing name-write test**

```ts
// src/components/auth/appleName.test.ts
import { isFallbackDisplayName, writeAppleName } from './appleName';

const db = vi.hoisted(() => ({
  profile: { username: 'stash3', display_name: 'stash3' } as Record<string, unknown> | null,
  updateUser: vi.fn(async () => ({ data: {}, error: null })),
  profileUpdate: null as null | Record<string, unknown>,
}));
vi.mock('@/integrations/supabase/client', () => ({
  supabase: {
    auth: { updateUser: db.updateUser },
    from: () => ({
      select: () => ({ eq: () => ({ maybeSingle: async () => ({ data: db.profile, error: null }) }) }),
      update: (row: Record<string, unknown>) => { db.profileUpdate = row; return { eq: async () => ({ error: null }) }; },
    }),
  },
}));

const user = { id: 'u1', email: 'kz8f3q2m@privaterelay.appleid.com' } as never;

describe('appleName', () => {
  beforeEach(() => { db.profileUpdate = null; db.updateUser.mockClear(); });

  it('knows a server fallback display name when it sees one', () => {
    expect(isFallbackDisplayName('stash3', 'stash3', 'x@privaterelay.appleid.com')).toBe(true);
    expect(isFallbackDisplayName('will', 'will7', 'will@gostash.it')).toBe(true);
    expect(isFallbackDisplayName(null, 'will7', 'will@gostash.it')).toBe(true);
    expect(isFallbackDisplayName('Will Dzierson', 'will7', 'will@gostash.it')).toBe(false);
  });

  it('writes the name to the user metadata and replaces a fallback display name', async () => {
    await writeAppleName(user, { firstName: 'Will', lastName: 'Dzierson' });
    expect(db.updateUser).toHaveBeenCalledWith({ data: { full_name: 'Will Dzierson', given_name: 'Will', family_name: 'Dzierson' } });
    expect(db.profileUpdate).toEqual({ display_name: 'Will Dzierson', first_name: 'Will', last_name: 'Dzierson' });
  });

  it('never overwrites a chosen display name, and does nothing without a name', async () => {
    db.profile = { username: 'stash3', display_name: 'Chosen Name' };
    await writeAppleName(user, { firstName: 'Will' });
    expect(db.profileUpdate).toBeNull();
    await writeAppleName(user, {});
    expect(db.updateUser).toHaveBeenCalledTimes(1);
  });
});
```

- [ ] **Step 2: Run it to see it fail** — `npx vitest run src/components/auth/appleName.test.ts` → FAIL (module missing).

- [ ] **Step 3: Write the helper**

```ts
// src/components/auth/appleName.ts
import type { User } from '@supabase/supabase-js';
import { supabase } from '@/integrations/supabase/client';

/** The trigger's fallbacks: the handle itself or the email's local part (spec §4.4) */
export const isFallbackDisplayName = (displayName: string | null | undefined, username: string, email: string | null | undefined) => {
  const local = (email ?? '').split('@')[0];
  return !displayName || displayName === username || (local !== '' && displayName === local);
};

/**
 * Apple sends the person's name once, on first authorization, and only to the client — so the
 * client writes it: into the user metadata, and onto the profile when the profile still carries a
 * server fallback. A display name the person chose is never overwritten.
 */
export async function writeAppleName(user: User, name: { firstName?: string; lastName?: string }): Promise<void> {
  const full = [name.firstName, name.lastName].filter(Boolean).join(' ').trim();
  if (!full) return;
  await supabase.auth.updateUser({ data: { full_name: full, given_name: name.firstName ?? null, family_name: name.lastName ?? null } });
  const { data } = await supabase.from('user_profiles').select('username, display_name').eq('id', user.id).maybeSingle();
  if (data && isFallbackDisplayName(data.display_name, data.username, user.email)) {
    await supabase
      .from('user_profiles')
      .update({ display_name: full, first_name: name.firstName ?? null, last_name: name.lastName ?? null })
      .eq('id', user.id);
  }
}
```

- [ ] **Step 4: Run it** — `npx vitest run src/components/auth/appleName.test.ts` → 3 PASS.

- [ ] **Step 5: Rewrite `Auth.test.tsx`'s mocks and add the new tests** — replace the file's `vi.mock('@/hooks/useAuth', …)` with a configurable object, stub the pair and the step, and render inside routes so navigation is observable:

```tsx
// replace the useAuth mock near the top of src/pages/Auth.test.tsx
const auth = vi.hoisted(() => ({
  user: null as null | { id: string; email: string; is_anonymous?: boolean; user_metadata?: Record<string, unknown> },
  handle: null as null | { username: string; confirmed: boolean },
  signIn: vi.fn(async () => ({ error: null as null | { message: string } })),
  signUp: vi.fn(async () => ({ error: null })),
  signInWithIdToken: vi.fn(async () => ({ error: null as null | { message: string } })),
  refreshHandle: vi.fn(async () => {}),
}));
vi.mock('@/hooks/useAuth', () => ({ useAuth: () => auth }));
vi.mock('@/components/auth/ProviderButtons', () => ({
  ProviderButtons: ({ onToken }: { onToken: (t: unknown) => void }) => (
    <button type="button" onClick={() => onToken({ provider: 'google', token: 'g.jwt', nonce: 'raw' })}>Continue with Google</button>
  ),
}));
vi.mock('@/components/auth/HandleStep', () => ({
  HandleStep: ({ onClaimed, initialUsername }: { onClaimed: () => void; initialUsername: string }) => (
    <button type="button" onClick={onClaimed}>Continue as {initialUsername}</button>
  ),
}));
vi.mock('@/components/auth/appleName', () => ({ writeAppleName: vi.fn(async () => {}) }));
```

Extend the supabase mock in that file with `auth: { resetPasswordForEmail: mockReset, getSession: async () => ({ data: { session: { user: auth.user } } }) }` and `functions: { invoke: vi.fn(async () => ({ data: { stored: true }, error: null })) }`. Change `renderAuth` to render routes:

```tsx
import { MemoryRouter, Route, Routes } from 'react-router-dom';
const renderAuth = (path = '/auth') =>
  render(
    <MemoryRouter initialEntries={[path]}>
      <Routes>
        <Route path="/auth" element={<Auth />} />
        <Route path="/home" element={<div>HOME PAGE</div>} />
        <Route path="/oauth/consent" element={<div>CONSENT PAGE</div>} />
      </Routes>
    </MemoryRouter>,
  );
```

Add a `beforeEach` that resets `auth.user = null; auth.handle = null;` and the mocks, then these tests:

```tsx
describe('Auth — Google and Apple', () => {
  it('shows the provider pair above both forms with the footnote and the rule', () => {
    renderAuth();
    expect(screen.getByRole('button', { name: /continue with google/i })).toBeInTheDocument();
    expect(screen.getByText('one account per email. sign in the same way each time.')).toBeInTheDocument();
    expect(screen.getByText('or with your email')).toBeInTheDocument();
    fireEvent.click(screen.getByRole('tab', { name: /sign up/i }));
    expect(screen.getByRole('button', { name: /continue with google/i })).toBeInTheDocument();
  });

  it('hands the token and the raw nonce to Supabase', async () => {
    renderAuth();
    fireEvent.click(screen.getByRole('button', { name: /continue with google/i }));
    await waitFor(() => expect(auth.signInWithIdToken).toHaveBeenCalledWith({ provider: 'google', token: 'g.jwt', nonce: 'raw' }));
  });

  it('surfaces a Supabase refusal and keeps the email form', async () => {
    auth.signInWithIdToken.mockResolvedValueOnce({ error: { message: 'Unsupported provider: provider is not enabled' } });
    renderAuth();
    fireEvent.click(screen.getByRole('button', { name: /continue with google/i }));
    await waitFor(() => expect(mockToast).toHaveBeenCalledWith(expect.objectContaining({ title: "Sign-in didn't complete.", description: 'Unsupported provider: provider is not enabled' })));
    expect(screen.getByLabelText('Email')).toBeInTheDocument();
  });

  it('says it is opening while the handle is unknown', () => {
    auth.user = { id: 'u1', email: 'will@example.com' };
    renderAuth();
    expect(screen.getByRole('status')).toHaveTextContent('opening…');
    expect(screen.queryByText('HOME PAGE')).toBeNull();
  });

  it('opens the handle step for an unconfirmed handle, then routes to returnTo after the claim', async () => {
    auth.user = { id: 'u1', email: 'will@example.com', user_metadata: { full_name: 'Will Dzierson' } };
    auth.handle = { username: 'stash3', confirmed: false };
    const view = renderAuth('/auth?returnTo=/oauth/consent');
    expect(screen.getByText('Claim your address.')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Continue as willdzierson' })).toBeInTheDocument();
    fireEvent.click(screen.getByRole('button', { name: /continue as/i }));
    await waitFor(() => expect(auth.refreshHandle).toHaveBeenCalled());
    auth.handle = { username: 'willdzierson', confirmed: true };
    view.rerender(
      <MemoryRouter initialEntries={['/auth?returnTo=/oauth/consent']}>
        <Routes>
          <Route path="/auth" element={<Auth />} />
          <Route path="/oauth/consent" element={<div>CONSENT PAGE</div>} />
        </Routes>
      </MemoryRouter>,
    );
    expect(await screen.findByText('CONSENT PAGE')).toBeInTheDocument();
  });

  it('routes a confirmed person home at once, including from ?mode=handle', async () => {
    auth.user = { id: 'u1', email: 'will@example.com' };
    auth.handle = { username: 'will', confirmed: true };
    renderAuth('/auth?mode=handle');
    expect(await screen.findByText('HOME PAGE')).toBeInTheDocument();
  });

  it('adds the provider hint to a failed password sign-in', async () => {
    auth.signIn.mockResolvedValueOnce({ error: { message: 'Invalid login credentials' } });
    renderAuth();
    fireEvent.change(screen.getByLabelText('Email'), { target: { value: 'will@example.com' } });
    fireEvent.change(screen.getByLabelText('Password'), { target: { value: 'nope' } });
    fireEvent.click(screen.getByRole('button', { name: /^sign in$/i }));
    await waitFor(() => expect(mockToast).toHaveBeenCalled());
    const call = mockToast.mock.calls.at(-1)![0] as { description: unknown };
    expect(JSON.stringify(call.description)).toContain('Signed up with Google or Apple? Use that button.');
  });
});
```

(The existing tests keep working: `signIn`/`signUp` are now on `auth`, and the password-form tests reference the same labels.)

- [ ] **Step 6: Run the file to see the new tests fail** — `npx vitest run src/pages/Auth.test.tsx` → the seven new tests FAIL.

- [ ] **Step 7: Change `src/pages/Auth.tsx`**

Imports — add:

```tsx
import { ProviderButtons, type ProviderIdToken } from '@/components/auth/ProviderButtons';
import { HandleStep } from '@/components/auth/HandleStep';
import { suggestHandle } from '@/components/auth/usernameAvailability';
import { writeAppleName } from '@/components/auth/appleName';
```

`COPY` — add the handle view: `handle: { address: 'stash://handle', title: 'Claim your address.', prompt: 'one more thing. pick your handle.' },`

State and hooks — change `view` to `useState<'tabs' | 'reset' | 'handle'>(...)`, destructure `const { signIn, signUp, signInWithIdToken, user, handle, refreshHandle } = useAuth();`, add `const [providerBusy, setProviderBusy] = useState(false);`.

Replace the "Redirect if already authenticated" effect with the gate (the anonymous-session guard stays as `isRealUser`):

```tsx
  // Where a signed-in person goes next: back to what sent them here, else the library
  const destination = () => {
    if (returnTo && commentItem) return `${returnTo}?openComment=${commentItem}`;
    return returnTo ?? '/home';
  };

  // The gate (spec §6.3): a real account leaves this page only once its handle is known. Unknown →
  // the bar says `| opening…`; unconfirmed → the claim step; confirmed → onward. `mode=handle`
  // (Index sends unconfirmed people here) needs nothing special — the same effect decides.
  useEffect(() => {
    if (!isRealUser || !handle) return;
    if (!handle.confirmed) {
      setView('handle');
      return;
    }
    navigate(destination());
  }, [isRealUser, handle, navigate, returnTo, commentItem]);
```

`handleSignIn` — the success branch keeps its toast but **drops the `navigate(...)` calls** (the gate routes); the error toast becomes:

```tsx
      toast({
        title: 'Sign in failed',
        description: (
          <>
            {error.message}
            <br />
            Signed up with Google or Apple? Use that button.
          </>
        ),
        variant: 'destructive',
      });
```

`handleSignUp` — same: keep the toast, drop the `navigate(...)` calls.

Add the provider handler:

```tsx
  // A provider's identity token → Supabase. Apple's extras ride along: the name (first time only)
  // and the one-shot authorization code the server exchanges so deletion can revoke (spec §6.2).
  const handleProviderToken = async (t: ProviderIdToken) => {
    setProviderBusy(true);
    const { error } = await signInWithIdToken({ provider: t.provider, token: t.token, nonce: t.nonce });
    if (error) {
      setProviderBusy(false);
      toast({ title: "Sign-in didn't complete.", description: error.message, variant: 'destructive' });
      return;
    }
    if (t.provider === 'apple') {
      const { data } = await supabase.auth.getSession();
      const signedIn = data.session?.user;
      if (signedIn && t.appleName) void writeAppleName(signedIn, t.appleName).catch((e) => console.warn('[auth] apple name', e));
      if (t.appleCode) {
        void supabase.functions
          .invoke('apple-token-exchange', { body: { code: t.appleCode, client: 'web' } })
          .then(({ error: fnError }) => { if (fnError) console.warn('[auth] apple-token-exchange', fnError.message); });
      }
    }
    // the gate routes once the handle is known
  };
```

`copy` — `const copy = view === 'handle' ? COPY.handle : view === 'reset' ? (resetSent ? COPY.sent : COPY.reset) : COPY[tab];`

`AuthShell` — pass the bar status: `<AuthShell address={copy.address} title={copy.title} prompt={copy.prompt} busy={isRealUser && !handle ? 'opening…' : providerBusy ? 'signing in…' : null}>`.

The handle view — first branch of the body:

```tsx
      {view === 'handle' && user && handle ? (
        <HandleStep
          userId={user.id}
          initialUsername={
            suggestHandle((user.user_metadata?.full_name as string | undefined) ?? (user.user_metadata?.name as string | undefined)) ?? handle.username
          }
          onClaimed={() => void refreshHandle()}
        />
      ) : view === 'reset' ? ( …existing reset branch… ) : ( …tabs… )}
```

The pair — a small local component placed at the top of **both** `TabsContent` blocks, before each `<form>`:

```tsx
  const providerPair = (
    <div className="mb-6 space-y-3">
      <ProviderButtons
        onToken={handleProviderToken}
        onError={(message) => toast({ title: "Sign-in didn't complete.", description: message, variant: 'destructive' })}
      />
      <p className="font-pixel text-pixel text-muted-foreground">one account per email. sign in the same way each time.</p>
      <div className="flex items-center gap-3 font-pixel text-pixel text-muted-foreground" aria-hidden>
        <span className="h-px flex-1 bg-ink/15" />
        <span>or with your email</span>
        <span className="h-px flex-1 bg-ink/15" />
      </div>
    </div>
  );
```

and `{providerPair}` as the first child of each `TabsContent` (Radix mounts only the active tab, so one GIS button and one `#appleid-signin` exist at a time).

- [ ] **Step 8: Run the tests and the typecheck** — `npx vitest run src/pages/Auth.test.tsx src/components/auth && npx tsc --noEmit -p tsconfig.app.json` → all PASS, no type errors. Then `npx vitest run` → whole suite green.

- [ ] **Step 9: Look at it** — `npm run dev` (port 8080), open `http://localhost:8080/auth`: the Google button renders (the Apple slot stays empty on localhost — Apple refuses non-registered origins; that is expected, see Task 17), the footnote and rule sit above the form on both tabs, nothing overlaps at 360 px width (DevTools device toolbar).

- [ ] **Step 10: Commit**

```bash
git add src/components/auth/appleName.ts src/components/auth/appleName.test.ts src/pages/Auth.tsx src/pages/Auth.test.tsx
git commit -m "feat(auth): Google and Apple on the way in, with the handle step and its gate"
```

---

### Task 11: `/home` sends an unconfirmed handle back to the way in

**Files:**
- Modify: `src/pages/Index.tsx` (the auth guard effect, around line 106)
- Modify: `src/pages/Index.test.tsx`

**Interfaces:**
- Consumes: `useAuth().handle` (Task 5). Only an explicit `handle.confirmed === false` redirects — existing tests mock `useAuth` without `handle`.

- [ ] **Step 1: Write the failing test** — in `src/pages/Index.test.tsx`, make the `useAuth` mock configurable and add a test:

```tsx
// replace the useAuth mock
const authState = vi.hoisted(() => ({ handle: undefined as undefined | { username: string; confirmed: boolean } }));
vi.mock("@/hooks/useAuth", () => ({
  useAuth: () => ({
    user: { id: "user-1", email: "test@example.com" },
    loading: false,
    session: { access_token: "token" },
    handle: authState.handle,
  }),
}));

// new test, inside the existing describe
  it("sends a person with an unconfirmed handle back to the way in", async () => {
    authState.handle = { username: "guest-12345678", confirmed: false };
    render(<Index />);
    await waitFor(() => expect(navigateMock).toHaveBeenCalledWith("/auth?mode=handle"));
    authState.handle = undefined;
  });

  it("leaves a confirmed person alone", async () => {
    authState.handle = { username: "will", confirmed: true };
    render(<Index />);
    await waitFor(() => expect(fetchItemsMock).not.toHaveBeenCalled());
    expect(navigateMock).not.toHaveBeenCalledWith("/auth?mode=handle");
    authState.handle = undefined;
  });
```

- [ ] **Step 2: Run it to see it fail** — `npx vitest run src/pages/Index.test.tsx` → the first new test FAILS (navigate never called with `/auth?mode=handle`).

- [ ] **Step 3: Add the gate** — in `src/pages/Index.tsx`, destructure `const { user, loading, handle } = useAuth();` and extend the existing guard effect:

```tsx
  useEffect(() => {
    if (!loading && !user) {
      navigate('/auth');
    }
    // Try-stash visitors (anonymous sessions) belong on the landing page —
    // the dashboard would self-heal a trial subscription for them otherwise
    if (!loading && user && (user as { is_anonymous?: boolean }).is_anonymous) {
      navigate('/');
    }
    // A handle the server generated (Google/Apple sign-up, a converted guest) is claimed once on
    // the way in before the library opens (spec §6.3)
    if (!loading && user && handle && !handle.confirmed) {
      navigate('/auth?mode=handle');
    }
  }, [loading, user, handle, navigate]);
```

- [ ] **Step 4: Run the tests** — `npx vitest run src/pages/Index.test.tsx && npx tsc --noEmit -p tsconfig.app.json` → PASS.

- [ ] **Step 5: Commit**

```bash
git add src/pages/Index.tsx src/pages/Index.test.tsx
git commit -m "feat(web): the library sends an unconfirmed handle back to the way in"
```

---

### Task 12: `_shared/appleClientSecret.ts` — Apple's ES256 client secret, minted per call

**Files:**
- Create: `supabase/functions/_shared/appleClientSecret.ts`, `supabase/functions/_shared/appleClientSecret.test.ts`

**Interfaces:**
- Produces: `makeAppleClientSecret({ teamId, keyId, clientId, privateKeyPem, now?, ttlSeconds? }): Promise<string>` (a JWT), `pemToPkcs8(pem): Uint8Array`, `decodeBase64Secret(b64): string`, `appleEnv(): { teamId; keyId; privateKeyPem; servicesId; bundleId }` (reads `APPLE_TEAM_ID`, `APPLE_KEY_ID`, `APPLE_SIGNIN_PRIVATE_KEY_B64`, `APPLE_SERVICES_ID`, `APPLE_BUNDLE_ID`; throws naming the missing one).
- Web Crypto only (like `emailLinkToken.ts`) so it runs under Deno and vitest; `Deno` is touched only inside `appleEnv()`.

- [ ] **Step 1: Write the failing test**

```ts
// supabase/functions/_shared/appleClientSecret.test.ts
// @vitest-environment node
import { describe, expect, it } from 'vitest';
import { decodeBase64Secret, makeAppleClientSecret, pemToPkcs8 } from './appleClientSecret';

const b64 = (bytes: Uint8Array) => btoa(String.fromCharCode(...bytes));
const fromB64url = (s: string) => Uint8Array.from(atob(s.replace(/-/g, '+').replace(/_/g, '/') + '='.repeat((4 - (s.length % 4)) % 4)), (c) => c.charCodeAt(0));

async function testKey() {
  const pair = await crypto.subtle.generateKey({ name: 'ECDSA', namedCurve: 'P-256' }, true, ['sign', 'verify']);
  const der = new Uint8Array(await crypto.subtle.exportKey('pkcs8', pair.privateKey));
  const pem = `-----BEGIN PRIVATE KEY-----\n${b64(der).replace(/(.{64})/g, '$1\n')}\n-----END PRIVATE KEY-----\n`;
  return { pair, pem, der };
}

describe('appleClientSecret', () => {
  it('reads a PEM back to its DER bytes and a base64 secret back to text', async () => {
    const { pem, der } = await testKey();
    expect(pemToPkcs8(pem)).toEqual(der);
    expect(decodeBase64Secret(btoa(pem))).toBe(pem);
  });

  it('mints an ES256 JWT Apple will accept: header kid, iss/sub/aud/iat/exp, valid signature', async () => {
    const { pair, pem } = await testKey();
    const now = new Date('2026-10-11T12:00:00Z');
    const jwt = await makeAppleClientSecret({ teamId: '3CH3K9NTT2', keyId: '3MDLB623WL', clientId: 'it.gostash.web', privateKeyPem: pem, now });
    const [h, p, s] = jwt.split('.');
    expect(JSON.parse(new TextDecoder().decode(fromB64url(h)))).toEqual({ alg: 'ES256', kid: '3MDLB623WL', typ: 'JWT' });
    const claims = JSON.parse(new TextDecoder().decode(fromB64url(p)));
    expect(claims).toEqual({ iss: '3CH3K9NTT2', iat: 1791720000, exp: 1791720600, aud: 'https://appleid.apple.com', sub: 'it.gostash.web' });
    const ok = await crypto.subtle.verify({ name: 'ECDSA', hash: 'SHA-256' }, pair.publicKey, fromB64url(s), new TextEncoder().encode(`${h}.${p}`));
    expect(ok).toBe(true);
  });
});
```

- [ ] **Step 2: Run it to see it fail** — `npx vitest run supabase/functions/_shared/appleClientSecret.test.ts` → FAIL (module missing).

- [ ] **Step 3: Write the helper**

```ts
// supabase/functions/_shared/appleClientSecret.ts
//
// Apple's "client secret" is a short-lived JWT signed with the team's Sign in with Apple key
// (ES256). Minting it per call means nothing long-lived is ever stored or rotated — the .p8 lives
// in APPLE_SIGNIN_PRIVATE_KEY_B64 (base64 of the PEM) and that is the only credential. Web Crypto
// only, so the same file runs under Deno and vitest.

const enc = new TextEncoder();
const b64url = (bytes: Uint8Array) =>
  btoa(String.fromCharCode(...bytes)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');

export function pemToPkcs8(pem: string): Uint8Array {
  const body = pem.replace(/-----(BEGIN|END) PRIVATE KEY-----/g, '').replace(/\s+/g, '');
  return Uint8Array.from(atob(body), (c) => c.charCodeAt(0));
}

export function decodeBase64Secret(b64: string): string {
  return new TextDecoder().decode(Uint8Array.from(atob(b64.replace(/\s+/g, '')), (c) => c.charCodeAt(0)));
}

export async function makeAppleClientSecret(opts: {
  teamId: string;
  keyId: string;
  clientId: string;
  privateKeyPem: string;
  now?: Date;
  ttlSeconds?: number;
}): Promise<string> {
  const iat = Math.floor((opts.now ?? new Date()).getTime() / 1000);
  const header = b64url(enc.encode(JSON.stringify({ alg: 'ES256', kid: opts.keyId, typ: 'JWT' })));
  const payload = b64url(enc.encode(JSON.stringify({
    iss: opts.teamId, iat, exp: iat + (opts.ttlSeconds ?? 600), aud: 'https://appleid.apple.com', sub: opts.clientId,
  })));
  const key = await crypto.subtle.importKey('pkcs8', pemToPkcs8(opts.privateKeyPem), { name: 'ECDSA', namedCurve: 'P-256' }, false, ['sign']);
  const signature = new Uint8Array(await crypto.subtle.sign({ name: 'ECDSA', hash: 'SHA-256' }, key, enc.encode(`${header}.${payload}`)));
  return `${header}.${payload}.${b64url(signature)}`;
}

export function appleEnv(): { teamId: string; keyId: string; privateKeyPem: string; servicesId: string; bundleId: string } {
  const get = (name: string) => {
    const value = Deno.env.get(name);
    if (!value) throw new Error(`${name} is not set`);
    return value;
  };
  return {
    teamId: get('APPLE_TEAM_ID'),
    keyId: get('APPLE_KEY_ID'),
    privateKeyPem: decodeBase64Secret(get('APPLE_SIGNIN_PRIVATE_KEY_B64')),
    servicesId: get('APPLE_SERVICES_ID'),
    bundleId: get('APPLE_BUNDLE_ID'),
  };
}
```

- [ ] **Step 4: Run it** — `npx vitest run supabase/functions/_shared/appleClientSecret.test.ts` → 2 PASS.

- [ ] **Step 5: Commit**

```bash
git add supabase/functions/_shared/appleClientSecret.ts supabase/functions/_shared/appleClientSecret.test.ts
git commit -m "feat(functions): Apple client-secret JWT minted per call from the .p8"
```

---

### Task 13: `apple-token-exchange` — swap Apple's code for a refresh token we can revoke later

**Files:**
- Create: `supabase/functions/apple-token-exchange/index.ts`, `supabase/functions/apple-token-exchange/index.test.ts`
- Modify: `supabase/config.toml` (add `[functions.apple-token-exchange]` `verify_jwt = true`, next to `[functions.delete-account]`)

**Interfaces:**
- Consumes: Task 12's helpers; the `apple_sign_in_tokens` table (Task 1).
- Produces: `POST /functions/v1/apple-token-exchange` with standard auth headers and body `{ code: string, client: 'web' | 'ios' }` → `200 { stored: true }` | `400 { error }` | `401` | `403` | `502 { stored: false, error }` | `500 { stored: false, error }`. Web clients send `client: 'web'` (audience = Services ID, `redirect_uri` = `https://www.gostash.it/auth`); iOS sends `client: 'ios'` (bundle id, no redirect_uri).

- [ ] **Step 1: Write the failing test**

```ts
// supabase/functions/apple-token-exchange/index.test.ts
// @vitest-environment node
import { beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';

const state = vi.hoisted(() => ({
  handler: null as null | ((req: Request) => Promise<Response>),
  user: { id: 'user-1', email: 'will@example.com' } as null | { id: string; email: string },
  upserted: null as null | { row: Record<string, unknown>; opts: Record<string, unknown> },
  apple: { status: 200, body: { refresh_token: 'r1', access_token: 'a1', id_token: 'i1' } as Record<string, unknown> },
  appleForm: null as null | URLSearchParams,
  env: {} as Record<string, string>,
}));

vi.mock('https://esm.sh/@supabase/supabase-js@2.57.2', () => ({
  createClient: () => ({
    auth: { getUser: async () => ({ data: { user: state.user }, error: state.user ? null : { message: 'nope' } }) },
    from: () => ({ upsert: async (row: Record<string, unknown>, opts: Record<string, unknown>) => { state.upserted = { row, opts }; return { error: null }; } }),
  }),
}));

const b64url = (s: string) => btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
const jwt = (payload: Record<string, unknown>) => `${b64url('{"alg":"HS256"}')}.${b64url(JSON.stringify(payload))}.sig`;
const sessionJwt = jwt({ sub: 'user-1' });
const agentJwt = jwt({ sub: 'user-1', client_id: 'agent-1' });

const call = (body: unknown, token: string | null = sessionJwt) =>
  state.handler!(new Request('https://x/apple-token-exchange', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) },
    body: typeof body === 'string' ? body : JSON.stringify(body),
  }));

beforeAll(async () => {
  const pair = await crypto.subtle.generateKey({ name: 'ECDSA', namedCurve: 'P-256' }, true, ['sign', 'verify']);
  const der = new Uint8Array(await crypto.subtle.exportKey('pkcs8', pair.privateKey));
  const pem = `-----BEGIN PRIVATE KEY-----\n${btoa(String.fromCharCode(...der))}\n-----END PRIVATE KEY-----\n`;
  state.env = {
    SUPABASE_URL: 'https://x.supabase.co', SUPABASE_SERVICE_ROLE_KEY: 'service',
    APPLE_TEAM_ID: '3CH3K9NTT2', APPLE_KEY_ID: '3MDLB623WL', APPLE_SIGNIN_PRIVATE_KEY_B64: btoa(pem),
    APPLE_SERVICES_ID: 'it.gostash.web', APPLE_BUNDLE_ID: 'it.gostash.stash',
  };
  vi.stubGlobal('Deno', { env: { get: (k: string) => state.env[k] }, serve: (h: typeof state.handler) => { state.handler = h; } });
  vi.stubGlobal('fetch', async (_url: string, init: RequestInit) => {
    state.appleForm = new URLSearchParams(String(init.body));
    return new Response(JSON.stringify(state.apple.body), { status: state.apple.status, headers: { 'Content-Type': 'application/json' } });
  });
  await import('./index.ts');
});

beforeEach(() => {
  state.user = { id: 'user-1', email: 'will@example.com' };
  state.upserted = null;
  state.appleForm = null;
  state.apple = { status: 200, body: { refresh_token: 'r1' } };
});

describe('apple-token-exchange', () => {
  it('refuses a missing token, an agent token, and a dead session', async () => {
    expect((await call({ code: 'c', client: 'web' }, null)).status).toBe(401);
    expect((await call({ code: 'c', client: 'web' }, agentJwt)).status).toBe(403);
    state.user = null;
    expect((await call({ code: 'c', client: 'web' })).status).toBe(401);
  });

  it('rejects a bad body', async () => {
    expect((await call('not json')).status).toBe(400);
    expect((await call({ code: '', client: 'web' })).status).toBe(400);
    expect((await call({ code: 'c', client: 'android' })).status).toBe(400);
  });

  it('exchanges a web code against the Services ID with the return URL and stores the refresh token', async () => {
    const res = await call({ code: 'c0de', client: 'web' });
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ stored: true });
    expect(state.appleForm!.get('client_id')).toBe('it.gostash.web');
    expect(state.appleForm!.get('grant_type')).toBe('authorization_code');
    expect(state.appleForm!.get('code')).toBe('c0de');
    expect(state.appleForm!.get('redirect_uri')).toBe('https://www.gostash.it/auth');
    expect(state.appleForm!.get('client_secret')!.split('.')).toHaveLength(3);
    expect(state.upserted).toEqual({ row: { user_id: 'user-1', client_id: 'it.gostash.web', refresh_token: 'r1' }, opts: { onConflict: 'user_id,client_id' } });
  });

  it('exchanges an iOS code against the bundle id without a return URL', async () => {
    await call({ code: 'c0de', client: 'ios' });
    expect(state.appleForm!.get('client_id')).toBe('it.gostash.stash');
    expect(state.appleForm!.has('redirect_uri')).toBe(false);
    expect(state.upserted!.row.client_id).toBe('it.gostash.stash');
  });

  it('reports Apple refusals without storing anything', async () => {
    state.apple = { status: 400, body: { error: 'invalid_grant' } };
    const res = await call({ code: 'stale', client: 'web' });
    expect(res.status).toBe(502);
    expect(await res.json()).toEqual({ stored: false, error: 'invalid_grant' });
    expect(state.upserted).toBeNull();
  });
});
```

- [ ] **Step 2: Run it to see it fail** — `npx vitest run supabase/functions/apple-token-exchange/index.test.ts` → FAIL (module missing).

- [ ] **Step 3: Write the function**

```ts
// supabase/functions/apple-token-exchange/index.ts
//
// Sign in with Apple hands the client a one-shot authorization code next to the identity token.
// Supabase never sees it (the id-token flow), so we exchange it here and keep Apple's refresh
// token — the only thing that lets delete-account revoke the person's Sign in with Apple grant
// later (spec §5.3). The code lives five minutes and works once, so clients call this right after
// sign-in; a failure is logged and never blocks the sign-in.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.57.2";
import { isAgentToken } from "../_shared/agentToken.ts";
import { appleEnv, makeAppleClientSecret } from "../_shared/appleClientSecret.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};
const APPLE_TOKEN_URL = "https://appleid.apple.com/auth/token";
const APPLE_WEB_REDIRECT_URI = "https://www.gostash.it/auth";

const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, "Content-Type": "application/json" } });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });
  if (req.method !== "POST") return json(405, { error: "POST only" });

  const token = req.headers.get("Authorization")?.replace(/^Bearer\s+/i, "").trim();
  if (!token) return json(401, { error: "Missing authorization token" });
  if (isAgentToken(token)) return json(403, { error: "Agent tokens are refused here" });

  const admin = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    { auth: { persistSession: false } },
  );
  const { data: userData, error: userError } = await admin.auth.getUser(token);
  const user = userData?.user;
  if (userError || !user) return json(401, { error: "Invalid or expired token" });

  let body: { code?: unknown; client?: unknown };
  try {
    body = await req.json();
  } catch {
    return json(400, { error: "JSON body required" });
  }
  const code = typeof body.code === "string" ? body.code.trim() : "";
  const client = body.client === "web" || body.client === "ios" ? body.client : null;
  if (!code || !client) return json(400, { error: "code and client ('web' | 'ios') are required" });

  const env = appleEnv();
  const clientId = client === "web" ? env.servicesId : env.bundleId;
  const clientSecret = await makeAppleClientSecret({ teamId: env.teamId, keyId: env.keyId, clientId, privateKeyPem: env.privateKeyPem });
  const form = new URLSearchParams({ client_id: clientId, client_secret: clientSecret, code, grant_type: "authorization_code" });
  if (client === "web") form.set("redirect_uri", APPLE_WEB_REDIRECT_URI);

  const res = await fetch(APPLE_TOKEN_URL, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: form.toString(),
  });
  const data = (await res.json().catch(() => ({}))) as { refresh_token?: unknown; error?: unknown };
  if (!res.ok || typeof data.refresh_token !== "string") {
    console.warn(`[APPLE-TOKEN-EXCHANGE] apple ${res.status} ${JSON.stringify(data).slice(0, 200)}`);
    return json(502, { stored: false, error: typeof data.error === "string" ? data.error : `apple ${res.status}` });
  }

  const { error } = await admin
    .from("apple_sign_in_tokens")
    .upsert({ user_id: user.id, client_id: clientId, refresh_token: data.refresh_token }, { onConflict: "user_id,client_id" });
  if (error) return json(500, { stored: false, error: error.message });
  return json(200, { stored: true });
});
```

- [ ] **Step 4: Run the test** — `npx vitest run supabase/functions/apple-token-exchange/index.test.ts` → 5 PASS.

- [ ] **Step 5: Register the function in `supabase/config.toml`** — after the `[functions.delete-account]` block add:

```toml
# Apple authorization code → refresh token (plan 2026-10-11-google-apple-sign-in-web Task 13).
[functions.apple-token-exchange]
verify_jwt = true
```

- [ ] **Step 6: Commit**

```bash
git add supabase/functions/apple-token-exchange supabase/config.toml
git commit -m "feat(functions): apple-token-exchange keeps Apple's refresh token for revocation"
```

---

### Task 14: `delete-account` revokes Sign in with Apple before deleting

**Files:**
- Modify: `supabase/functions/delete-account/index.ts`
- Create: `supabase/functions/delete-account/index.test.ts`

**Interfaces:**
- Consumes: Task 12's helpers, the `apple_sign_in_tokens` rows (Task 13 writes them).
- Produces: the same `200 { deleted: true, storageObjects, stripe }` response plus `apple: { revoked: number, failed: number }`. Revocation runs after storage and **before** `auth.admin.deleteUser` (the rows cascade away with the user); any revoke failure is logged and deletion proceeds (spec §5.3, §9).

- [ ] **Step 1: Write the failing test**

```ts
// supabase/functions/delete-account/index.test.ts
// @vitest-environment node
import { beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';

const state = vi.hoisted(() => ({
  handler: null as null | ((req: Request) => Promise<Response>),
  tokens: [] as Array<{ client_id: string; refresh_token: string }>,
  calls: [] as string[],
  revokeStatus: 200,
  env: {} as Record<string, string>,
}));

vi.mock('https://deno.land/std@0.190.0/http/server.ts', () => ({ serve: (h: typeof state.handler) => { state.handler = h; } }));
vi.mock('https://esm.sh/stripe@18.5.0', () => ({ default: class {} }));
vi.mock('https://esm.sh/@supabase/supabase-js@2.57.2', () => ({
  createClient: () => ({
    auth: {
      getUser: async () => ({ data: { user: { id: 'user-1', email: 'will@example.com' } }, error: null }),
      admin: { deleteUser: async () => { state.calls.push('deleteUser'); return { error: null }; } },
    },
    storage: { from: () => ({ list: async () => ({ data: [], error: null }), remove: async () => ({ error: null }) }) },
    from: () => ({ select: () => ({ eq: async () => ({ data: state.tokens, error: null }) }) }),
  }),
}));

const b64url = (s: string) => btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
const sessionJwt = `${b64url('{"alg":"HS256"}')}.${b64url('{"sub":"user-1"}')}.sig`;

beforeAll(async () => {
  const pair = await crypto.subtle.generateKey({ name: 'ECDSA', namedCurve: 'P-256' }, true, ['sign', 'verify']);
  const der = new Uint8Array(await crypto.subtle.exportKey('pkcs8', pair.privateKey));
  const pem = `-----BEGIN PRIVATE KEY-----\n${btoa(String.fromCharCode(...der))}\n-----END PRIVATE KEY-----\n`;
  state.env = { SUPABASE_URL: 'https://x.supabase.co', SUPABASE_SERVICE_ROLE_KEY: 'service', APPLE_TEAM_ID: 't', APPLE_KEY_ID: 'k', APPLE_SIGNIN_PRIVATE_KEY_B64: btoa(pem), APPLE_SERVICES_ID: 'it.gostash.web', APPLE_BUNDLE_ID: 'it.gostash.stash' };
  vi.stubGlobal('Deno', { env: { get: (k: string) => state.env[k] } }); // no STRIPE_SECRET_KEY → Stripe step skipped
  vi.stubGlobal('fetch', async (url: string, init: RequestInit) => {
    const form = new URLSearchParams(String(init.body));
    state.calls.push(`revoke:${form.get('client_id')}:${form.get('token')}:${form.get('token_type_hint')}:${url}`);
    return new Response('', { status: state.revokeStatus });
  });
  await import('./index.ts');
});

beforeEach(() => { state.tokens = []; state.calls = []; state.revokeStatus = 200; });

const del = () => state.handler!(new Request('https://x/delete-account', { method: 'POST', headers: { Authorization: `Bearer ${sessionJwt}` } }));

describe('delete-account — Apple revocation', () => {
  it('revokes every stored Apple token before deleting the user', async () => {
    state.tokens = [{ client_id: 'it.gostash.web', refresh_token: 'r-web' }, { client_id: 'it.gostash.stash', refresh_token: 'r-ios' }];
    const res = await del();
    expect(res.status).toBe(200);
    expect(await res.json()).toMatchObject({ deleted: true, apple: { revoked: 2, failed: 0 } });
    expect(state.calls).toEqual([
      'revoke:it.gostash.web:r-web:refresh_token:https://appleid.apple.com/auth/revoke',
      'revoke:it.gostash.stash:r-ios:refresh_token:https://appleid.apple.com/auth/revoke',
      'deleteUser',
    ]);
  });

  it('still deletes when Apple refuses the revoke', async () => {
    state.tokens = [{ client_id: 'it.gostash.web', refresh_token: 'r-web' }];
    state.revokeStatus = 400;
    const res = await del();
    expect(await res.json()).toMatchObject({ deleted: true, apple: { revoked: 0, failed: 1 } });
    expect(state.calls.at(-1)).toBe('deleteUser');
  });

  it('skips Apple entirely for an account without Apple tokens', async () => {
    const res = await del();
    expect(await res.json()).toMatchObject({ deleted: true, apple: { revoked: 0, failed: 0 } });
    expect(state.calls).toEqual(['deleteUser']);
  });
});
```

- [ ] **Step 2: Run it to see it fail** — `npx vitest run supabase/functions/delete-account/index.test.ts` → FAIL (`apple` missing from the response; revoke never called).

- [ ] **Step 3: Add the revoke step** — in `supabase/functions/delete-account/index.ts`:

Header comment: renumber the steps — insert `3. Sign in with Apple — revoke every refresh token apple-token-exchange stored for this user (Apple asks for this on account deletion); best effort, logged, never blocking.` before the auth delete, which becomes step 4.

Import: `import { appleEnv, makeAppleClientSecret } from "../_shared/appleClientSecret.ts";`

Add after `cancelStripeSubscriptions`:

```ts
const APPLE_REVOKE_URL = "https://appleid.apple.com/auth/revoke";

async function revokeAppleTokens(admin: SupabaseClient, userId: string): Promise<{ revoked: number; failed: number }> {
  const { data, error } = await admin.from("apple_sign_in_tokens").select("client_id, refresh_token").eq("user_id", userId);
  if (error) {
    log("Apple tokens unreadable", { message: error.message });
    return { revoked: 0, failed: 0 };
  }
  const rows = (data ?? []) as Array<{ client_id: string; refresh_token: string }>;
  if (rows.length === 0) return { revoked: 0, failed: 0 };
  let env: ReturnType<typeof appleEnv>;
  try {
    env = appleEnv();
  } catch (e) {
    log("Apple revoke skipped: secrets missing", { message: e instanceof Error ? e.message : String(e) });
    return { revoked: 0, failed: rows.length };
  }
  let revoked = 0;
  let failed = 0;
  for (const row of rows) {
    try {
      const clientSecret = await makeAppleClientSecret({ teamId: env.teamId, keyId: env.keyId, clientId: row.client_id, privateKeyPem: env.privateKeyPem });
      const res = await fetch(APPLE_REVOKE_URL, {
        method: "POST",
        headers: { "Content-Type": "application/x-www-form-urlencoded" },
        body: new URLSearchParams({ client_id: row.client_id, client_secret: clientSecret, token: row.refresh_token, token_type_hint: "refresh_token" }).toString(),
      });
      if (res.ok) revoked += 1;
      else {
        failed += 1;
        log("Apple revoke refused", { clientId: row.client_id, status: res.status });
      }
    } catch (e) {
      failed += 1;
      log("Apple revoke failed", { clientId: row.client_id, message: e instanceof Error ? e.message : String(e) });
    }
  }
  return { revoked, failed };
}
```

In the handler, between `log("Storage done", …)` and the auth delete:

```ts
    const apple = await revokeAppleTokens(admin, userId);
    log("Apple done", apple);
```

and return `json(200, { deleted: true, storageObjects: paths.length, stripe, apple })`.

- [ ] **Step 4: Run the test** — `npx vitest run supabase/functions/delete-account/index.test.ts` → 3 PASS. Then `npx vitest run` → whole suite green.

- [ ] **Step 5: Commit**

```bash
git add supabase/functions/delete-account/index.ts supabase/functions/delete-account/index.test.ts
git commit -m "feat(functions): delete-account revokes Sign in with Apple tokens first"
```

---

### Task 15: Deploy the two functions and smoke them against prod

**Files:**
- None in the repo (deploy + verification). Scripts: `/tmp/pw/fn_smoke_apple.py`.

**Interfaces:**
- Consumes: Tasks 13–14; the Apple secrets already set (§5.4); `/tmp/pw/sbq.py` (Task 2).
- Produces: `apple-token-exchange` v1 and `delete-account` vN live; evidence in the final report.

- [ ] **Step 1: Make sure the deployed `delete-account` is what `main` has** (other agents deploy from unmerged trees — never overwrite live work blind). Run: `python3 /tmp/pw/eszip_diff.py delete-account /Users/will/Appdev/embed-link-spark/.claude/worktrees/google-apple-sign-in` — Expected: the only differences are this plan's revoke additions. If the deployed source carries changes that are **not** in this worktree, STOP and report them to Will before deploying.

- [ ] **Step 2: Deploy**

Run: `supabase functions deploy apple-token-exchange --project-ref uqqsgmwkvslaomzxptnp && supabase functions deploy delete-account --project-ref uqqsgmwkvslaomzxptnp && supabase functions list --project-ref uqqsgmwkvslaomzxptnp 2>/dev/null | grep -i "apple-token-exchange\|delete-account"`
Expected: both listed, `apple-token-exchange` at version 1, `delete-account` one version higher than before; both `ACTIVE`.

- [ ] **Step 3: Write the smoke (throwaway user → bogus Apple code → 502; then delete-account → 200 with `apple`)**

```python
#!/usr/bin/env python3
"""Smoke apple-token-exchange + delete-account on prod with a throwaway user."""
import json, subprocess, sys, time, urllib.request
sys.path.insert(0, "/tmp/pw")
from sbq import REF

URL = f"https://{REF}.supabase.co"
keys = json.loads(subprocess.check_output(["supabase", "projects", "api-keys", "--project-ref", REF, "-o", "json"], text=True))
SERVICE = next(k["api_key"] for k in keys if k["name"] == "service_role")
ANON = next(k["api_key"] for k in keys if k["name"] == "anon")
ts = str(int(time.time()))
email, password = f"will+smoke-apple-{ts}@dzierson.com", f"Smoke-{ts}-pw!"

def req(method, path, body, headers):
    r = urllib.request.Request(URL + path, data=json.dumps(body).encode() if body is not None else None,
                               headers={"Content-Type": "application/json", **headers}, method=method)
    try:
        with urllib.request.urlopen(r) as resp: return resp.status, json.loads(resp.read() or b"null")
    except urllib.error.HTTPError as e: return e.code, json.loads(e.read() or b"null")

admin = {"apikey": SERVICE, "Authorization": f"Bearer {SERVICE}"}
status, user = req("POST", "/auth/v1/admin/users", {"email": email, "password": password, "email_confirm": True, "user_metadata": {"username": f"smokeapple{ts[-4:]}"}}, admin)
assert status == 200, (status, user)
status, session = req("POST", "/auth/v1/token?grant_type=password", {"email": email, "password": password}, {"apikey": ANON})
assert status == 200, (status, session)
bearer = {"apikey": ANON, "Authorization": f"Bearer {session['access_token']}"}

s1, b1 = req("POST", "/functions/v1/apple-token-exchange", {"code": "bogus-code", "client": "web"}, bearer)
print("exchange bogus code →", s1, b1)
s2, b2 = req("POST", "/functions/v1/delete-account", None, bearer)
print("delete-account →", s2, b2)
ok = s1 == 502 and b1.get("stored") is False and s2 == 200 and b2.get("deleted") is True and "apple" in b2
print("PASS" if ok else "FAIL")
sys.exit(0 if ok else 1)
```

- [ ] **Step 4: Run it**

Run: `python3 /tmp/pw/fn_smoke_apple.py`
Expected: `exchange bogus code → 502 {'stored': False, 'error': 'invalid_grant'}` (Apple rejecting a fake code proves the secret JWT, the key, and the Services ID are all accepted — Apple answers `invalid_client` when the client secret is wrong), `delete-account → 200 {... 'apple': {'revoked': 0, 'failed': 0}}`, `PASS`. An `invalid_client` here means the key/team/Services ID secrets don't match — check `supabase secrets list` names and the spec §12 identifiers.

- [ ] **Step 5: Nothing to commit; record both outputs in the final report.**

---

### Task 16: Documentation — the contract, the design system, the platform API

**Files:**
- Modify: `docs/ui-changes.md` (new entry at the top, after the `---` under the purpose paragraph)
- Modify: `DESIGN-v2.md` (§12.14 bullets, line ~976; the §10 copy table row "The way in (§12.14)", line ~542)
- Modify: `docs/PLATFORM_API.md` (the `## Auth` section, line 9; a new `### POST /apple-token-exchange` under `## Account deletion`, line ~561)

- [ ] **Step 1: `docs/ui-changes.md`** — insert this entry as the newest:

```markdown
## 2026-10-11 · Google and Apple sign-in; generated handles confirmed once

Will: "let's get google and apple sign up implemented." Spec:
`docs/superpowers/specs/2026-10-11-google-apple-sign-in-design.md`.

- **Contract (all platforms): id-token sign-in.** The client obtains an identity token from
  Google or Apple and calls `auth.signInWithIdToken({ provider, token, nonce })`. Nonce rule: the
  provider gets the SHA-256 hex of a random nonce, Supabase gets the raw value, one nonce per
  attempt. Supabase holds Client IDs only (Google web
  `772942709290-2j03nu08hnumh6jfe2h0j6jkh9bnrbta…`, iOS `772942709290-ha25d35f942l5blept0aiv30aculahsn…`;
  Apple `it.gostash.web` for the web, `it.gostash.stash` native) — there is no provider secret
  anywhere. Same verified email → the same account (automatic linking). Apple's Hide My Email
  makes a separate account; the footnote says so.
- **Contract: `user_profiles.handle_confirmed`.** Sign-ups without a `username` in the metadata
  get a server-generated handle (name → email local part unless `@privaterelay.appleid.com` →
  `stash`; `[a-z0-9]`, 3–20, numeric suffix on collision) and `handle_confirmed = false`. The
  first surface with the step shows it once: prefilled handle + **Continue** writes `username` +
  `handle_confirmed = true`. A DB trigger refuses any later username change and any reset of the
  flag. iOS: read `handle_confirmed` with the profile and show the same step before the tabs.
- **Contract: Apple extras.** Apple sends the name only on first authorization → the client writes
  `full_name`/`given_name`/`family_name` to the user metadata and `display_name`/`first_name`/
  `last_name` to the profile when the profile still shows the server fallback. Apple's one-shot
  authorization code → `POST /functions/v1/apple-token-exchange { code, client: 'web' | 'ios' }`
  right after sign-in (five-minute, single-use code; failure never blocks). `delete-account` now
  revokes every stored Apple refresh token before deleting and answers `apple: { revoked, failed }`.
- **Web (`/auth`):** a Google-rendered and an Apple-rendered button above both forms, both square,
  "Continue with …", then `one account per email. sign in the same way each time.` and the rule
  `or with your email`. New view `stash://handle` — **Claim your address.** / `> one more thing.
  pick your handle.` / **Continue** (`claiming…`). Gate: a signed-in person stays on `/auth`
  (`| opening…`) until the handle is known; `/home` sends an unconfirmed handle to
  `/auth?mode=handle`. A failed password sign-in adds `Signed up with Google or Apple? Use that
  button.` Provider errors toast **Sign-in didn't complete.**; a closed Apple popup is silent.
- **Implementation:** `src/components/auth/{ProviderButtons,HandleStep,useProviderScripts,
  usernameAvailability,appleName,AuthControls}.tsx`, `src/utils/nonce.ts`, `useAuth.handle`,
  migration `20261011150000_oauth_handles.sql`, `supabase/functions/{apple-token-exchange,
  delete-account}`, `_shared/appleClientSecret.ts`.
```

- [ ] **Step 2: `DESIGN-v2.md` §12.14** — after the "**Fields:**" bullet add:

```markdown
- **The provider pair** (2026-10-11): above the fields on both tabs, Google's rendered button then
  Apple's — `outline` / black, square corners, 40 px, "Continue with …", at the body's width. Under
  them the footnote `one account per email. sign in the same way each time.` and a 1 px rule with
  `or with your email` in the machine voice. Scripts load on this page only; a blocked one collapses
  its slot. The bar says `| signing in…` while a provider token is with Supabase.
- **The handle step:** `stash://handle`, "Claim your address.", `> one more thing. pick your handle.`
  Prefilled (a name-derived handle, else the server's), the sign-up username field, the feed-address
  helper, one ink **Continue** (`claiming…`). Shown once, to anyone whose handle the server made;
  Continue with the prefill is the skip. Errors: `✕ that username is taken. try another.`,
  `✕ 3–20 letters and numbers.`
```

and in the "Behaviour is unchanged" bullet add ", and a signed-in person waits on `| opening…` until their handle is known". In the §10 copy table, extend the "The way in (§12.14)" row's first cell with `| opening…`, `| claiming…` and its prompts cell with `> one more thing. pick your handle.`; field errors gain `✕ 3–20 letters and numbers.`.

- [ ] **Step 3: `docs/PLATFORM_API.md`** — in `## Auth`, after "Get a JWT with supabase-js (`auth.signInWithPassword` / OAuth) on any platform," add a paragraph:

```markdown
**Google and Apple** use the id-token flow on every platform: get an identity token from the
provider's own SDK (Google Identity Services / GoogleSignIn; Apple JS / AuthenticationServices)
with the SHA-256 of a fresh nonce, then `auth.signInWithIdToken({ provider, token, nonce })` with
the raw nonce. Nothing else is needed — no redirect, no client secret. The accepted audiences are
the project's Client IDs (spec `2026-10-11-google-apple-sign-in-design.md` §5.1). Right after an
Apple sign-in, send Apple's authorization code to `POST /apple-token-exchange` (below) so account
deletion can revoke the grant; on first authorization also write the person's name
(`updateUser({ data: { full_name, given_name, family_name } })`). Read
`user_profiles.handle_confirmed`: when false, show the one-time handle step before the app.
```

and under `## Account deletion`, before `## Delete contract`:

```markdown
### `POST /apple-token-exchange` — keep Apple's refresh token for revocation

Standard auth headers (agent tokens refused). Body `{ "code": "<Apple authorization code>",
"client": "web" | "ios" }` — `web` = the Services ID audience with return URL
`https://www.gostash.it/auth`, `ios` = the bundle id. `200 { stored: true }`; `400` bad body;
`502 { stored: false, error }` when Apple refuses (expired or reused code: `invalid_grant`).
Call it immediately after `signInWithIdToken` — Apple's code lives five minutes and works once —
and never block the sign-in on it. `delete-account` revokes every stored token first and reports
`apple: { revoked, failed }`.
```

- [ ] **Step 4: Commit**

```bash
git add docs/ui-changes.md DESIGN-v2.md docs/PLATFORM_API.md
git commit -m "docs: Google and Apple sign-in contract, the way in's provider pair and handle step"
```

---

### Task 17: Provider walks on dev and prod, then ship

**Files:**
- None (verification, then the branch is ready for the finishing workflow).

**Interfaces:**
- Consumes: everything above. Google works on `localhost:8080` (an authorized origin); Apple's popup needs a registered origin, so Apple is walked on production after the push (the branch-preview host is not registered — spec §6.2).

- [ ] **Step 1: Google on dev** — `npm run dev`; open `http://localhost:8080/auth`; **Continue with Google** with a throwaway Google account (not Will's): the popup says "Continue to Stash", the way in shows `| opening…`, then **Claim your address.** prefilled with the name-derived handle; **Continue** → `/home`, the trial self-heals. Evidence: `python3 /tmp/pw/sbq.py "select u.email, p.username, p.display_name, p.handle_confirmed, (select array_agg(provider) from auth.identities i where i.user_id = u.id) providers from auth.users u join public.user_profiles p on p.id = u.id order by u.created_at desc limit 3"` shows the row with `providers = {google}` and `handle_confirmed = true`.

- [ ] **Step 2: Same email, existing password account** — sign the throwaway Google account's address up by email/password first (a second throwaway), then sign in with Google using that address: the same `auth.users.id` gains a second `auth.identities` row (`{email,google}`), no duplicate profile, straight to `/home` (its handle was confirmed at sign-up).

- [ ] **Step 3: Ship the web** — finish the branch with the project's usual routine (merge into `main`, push; Vercel deploys), then confirm the bundle carries the change: `curl -s https://www.gostash.it/app.html | grep -o 'src="[^"]*index[^"]*\.js"'` and `curl -s https://www.gostash.it<that path> | grep -c "appleid-signin"` → `1`.

- [ ] **Step 4: Apple on prod** — `https://www.gostash.it/auth` → **Continue with Apple** with Will's Apple ID, **Hide My Email** on: Apple's sheet names Stash, the handle step prefills `willdzierson` (from the name) over the server's `stash…`, **Continue** → `/home`. Evidence (same query): `providers = {apple}`, the relay email, `display_name = 'Will Dzierson'`, `handle_confirmed = true`; and `python3 /tmp/pw/sbq.py "select client_id from public.apple_sign_in_tokens where user_id = '<that id>'"` → `it.gostash.web` (the code exchange landed). Then delete that test account from Settings → the row is gone and the `delete-account` log shows `Apple done {"revoked":1,"failed":0}`.

- [ ] **Step 5: Regression** — password sign-in, sign-up with a typed username (handle confirmed at once, no step), reset-password walk, `/oauth/consent` bounce via `/auth?returnTo=…` with Google, iOS app sign-in with password (untouched).

- [ ] **Step 6: Report** — paste the two SQL evidence rows, the function versions, and the auth-config read-back into the final report; update the workstream memory and the spec's §12 phase-1 line.

---

## Self-review notes (writer's pass, 2026-10-11)

- Spec coverage: §4.1 nonce (T4, T8), §4.2 linking (T17 walk), §4.3 handle + trigger + lock + step (T1, T2, T5, T9, T10, T11), §4.4 names (T1, T10), §4.6 copy (T10, T16), §5.1 config (T3), §5.2 migration (T1–T2), §5.3 functions (T12–T15), §5.4 secrets (already set; name `_B64`), §6.1–6.3 web (T7–T11), §6.5 docs (T16), §6.6 tests (per task), §9 errors (T8 silent popup, T10 toasts, T13/T14 Apple failures), §11 verification (T2, T15, T17). §6.4 and §7 are plan 2.
- Review Focus → tests: 1 → T8 "ignores a second credential"; 2 → T5 "retries once, then fails open"; 3 → T10 "routes to returnTo after the claim"; 4 → T9 "sanitizes pasted text and refuses a short handle"; 5 → T10 "surfaces a Supabase refusal".
- Type consistency: `ProviderIdToken` (T8) is what T10 consumes; `HandleState`/`handle`/`refreshHandle`/`signInWithIdToken` (T5) are what T10/T11 read; `SubmitButton`/`field` (T6) are what T9/T10 import; `makeAppleClientSecret`/`appleEnv` (T12) are what T13/T14 call.

