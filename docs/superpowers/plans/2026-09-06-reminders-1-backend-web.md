# Reminders — Plan 1 of 3: backend + web

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the reminder data model, the capture-endpoint `remind_at` parameter, the daily maintenance job, and the complete web experience (due-first ordering, card chip and pill, set/dismiss from the card menu).

**Architecture:** Three nullable columns on `items` carry the reminder; "due" and "expired" are derived from `remind_at` + `reminder_cleared_at` with a 24-hour window, never stored. Web computes state client-side from a single ticking clock provided by the grid; writes are ordinary PostgREST updates through the existing `saveItem` path and realtime refetch does the rest. A cron-triggered edge function back-fills `reminder_cleared_at` for expired rows (email lands in Plan 3).

**Tech Stack:** Postgres (Supabase, pg_cron + pg_net + Vault), Deno edge functions, Vite + React + TS + shadcn, vitest, Supabase Management API for SQL.

**Spec:** `docs/superpowers/specs/2026-09-06-reminders-design.md`

## Global Constraints

- `DUE_WINDOW` is exactly 24 hours on every surface. Derived state: `none` (no `remind_at`), `cleared` (`reminder_cleared_at` set, or `now ≥ remind_at + 24h`), `scheduled` (`now < remind_at`), `due` (otherwise).
- Presets are 1, 3, 5 days. Clients send an absolute ISO-8601 `remind_at`.
- Set / re-set writes `{ remind_at, reminder_cleared_at: null, reminder_notified_at: null }`. Dismiss writes `{ reminder_cleared_at: now }`. Clients never write `reminder_notified_at`.
- Capture never fails over `remind_at`: invalid or older than `now − 1h` is ignored with a `console.warn`, the item still saves.
- Reminder UI never appears in public/shared views (`isPublicView`).
- Due-first ordering is skipped while a server search rank is active.
- Project: `uqqsgmwkvslaomzxptnp`. Deep link format: `https://www.gostash.it/home#item=<uuid>`.
- Work on a branch in a worktree (`superpowers:using-git-worktrees`); Will commits in the same checkout. `git push` of `main` deploys the web app to Vercel; edge functions deploy only via `supabase functions deploy`.
- Test commands: `npm test` (vitest), `npx tsc --noEmit -p tsconfig.app.json` (typecheck; `vite build` does not typecheck). Lint baseline is dirty; compare counts to `main`.
- Management API SQL recipe (from memory `deploy-process`): token from macOS keychain `security find-generic-password -s "Supabase CLI" -a "supabase" -w`, strip `go-keyring-base64:`, base64-decode, `POST https://api.supabase.com/v1/projects/uqqsgmwkvslaomzxptnp/database/query` with `{"query": "..."}`. Never paste the token into a file that gets committed.

---

## File map

| File | Responsibility |
|---|---|
| `supabase/migrations/20260906120000_item_reminders.sql` | Columns, index, preference column, `reminders_expire()` SQL function |
| `supabase/migrations/20260906121000_reminder_digest_cron.sql` | pg_cron schedule reading the secret from Vault |
| `supabase/functions/_shared/reminders.ts` (+ `.test.ts`) | `parseRemindAt` validator shared by the three capture functions |
| `supabase/functions/add-note/index.ts`, `add-url/index.ts`, `add-file/index.ts` | Accept `remind_at` |
| `supabase/functions/reminder-digest/index.ts` | Cron entry point: secret check, hygiene step, digest placeholder |
| `supabase/config.toml` | `verify_jwt = false` for `reminder-digest` |
| `src/integrations/supabase/types.ts` | Three new columns on `items`, `reminder_emails` on `user_preferences` |
| `src/utils/reminders.ts` (+ `.test.ts`) | Pure logic: state, ordering, presets, labels, patch builders |
| `src/hooks/useNow.tsx` | `NowProvider` (one 60 s ticker per grid) + `useNow()` |
| `src/hooks/useItems.ts` | Select the two new columns |
| `src/components/ContentGrid.tsx` (+ `.test.tsx`) | Due-first ordering, wraps cards in `NowProvider` |
| `src/components/cards/ReminderChip.tsx` | Footer chip (scheduled / due + dismiss) |
| `src/components/ContentItemFooter.tsx` | Chip placement, "Remind me…" submenu, writes |
| `src/components/ContentItemHeader.tsx` | "Due" corner pill |
| `src/components/ContentItem.tsx` | Type additions only |
| `docs/PLATFORM_API.md`, `docs/ui-changes.md`, `DESIGN.md` | Contracts and design amendment |

---

### Task 1: Schema migration, applied to production

**Files:**
- Create: `supabase/migrations/20260906120000_item_reminders.sql`
- Modify: `src/integrations/supabase/types.ts:353-430` (items Row/Insert/Update) and the `user_preferences` block

**Interfaces:**
- Produces: columns `items.remind_at`, `items.reminder_cleared_at`, `items.reminder_notified_at` (all `timestamptz null`), `user_preferences.reminder_emails boolean not null default true`, SQL function `public.reminders_expire() returns integer` (service role only).

- [ ] **Step 1: Write the migration**

```sql
-- Explicit reminders (spec: docs/superpowers/specs/2026-09-06-reminders-design.md).
-- "Due" and "expired" are derived from remind_at + reminder_cleared_at with a
-- 24h window; nothing here stores a due flag.
ALTER TABLE public.items
  ADD COLUMN IF NOT EXISTS remind_at timestamptz,
  ADD COLUMN IF NOT EXISTS reminder_cleared_at timestamptz,
  ADD COLUMN IF NOT EXISTS reminder_notified_at timestamptz;

COMMENT ON COLUMN public.items.remind_at IS
  'User-set "bring this back" time. Due for 24h from this instant unless cleared.';
COMMENT ON COLUMN public.items.reminder_cleared_at IS
  'Set by user dismissal, or by reminders_expire() 24h after remind_at. Null = still active.';
COMMENT ON COLUMN public.items.reminder_notified_at IS
  'When the reminder digest email included this item. Idempotency for the daily job.';

CREATE INDEX IF NOT EXISTS items_reminder_active
  ON public.items (user_id, remind_at)
  WHERE remind_at IS NOT NULL AND reminder_cleared_at IS NULL;

ALTER TABLE public.user_preferences
  ADD COLUMN IF NOT EXISTS reminder_emails boolean NOT NULL DEFAULT true;

-- Hygiene for the daily job: make expiry explicit in the data. Clients never
-- depend on this; they derive expiry from the 24h window themselves.
CREATE OR REPLACE FUNCTION public.reminders_expire()
RETURNS integer
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  WITH done AS (
    UPDATE public.items
       SET reminder_cleared_at = remind_at + interval '24 hours'
     WHERE remind_at IS NOT NULL
       AND reminder_cleared_at IS NULL
       AND remind_at + interval '24 hours' <= now()
    RETURNING 1
  )
  SELECT count(*)::integer FROM done;
$$;

REVOKE EXECUTE ON FUNCTION public.reminders_expire() FROM public, anon, authenticated;
```

- [ ] **Step 2: Apply it to production via the Management API**

Write `/tmp/apply-reminders-migration.sh` (the worktree Bash guard refuses loops/heredocs inline; a script file is fine):

```zsh
#!/bin/zsh
set -e
RAW=$(security find-generic-password -s "Supabase CLI" -a "supabase" -w)
TOKEN=$(echo "${RAW#go-keyring-base64:}" | base64 -d)
SQL=$(python3 -c 'import json,sys; print(json.dumps({"query": open(sys.argv[1]).read()}))' supabase/migrations/20260906120000_item_reminders.sql)
curl -s -X POST "https://api.supabase.com/v1/projects/uqqsgmwkvslaomzxptnp/database/query" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" --data-binary "$SQL"
echo
printf '%s' '{"query":"insert into supabase_migrations.schema_migrations (version, name) values ($$20260906120000$$, $$item_reminders$$) on conflict do nothing"}' | \
curl -s -X POST "https://api.supabase.com/v1/projects/uqqsgmwkvslaomzxptnp/database/query" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" --data-binary @-
echo
printf '%s' '{"query":"select column_name, data_type from information_schema.columns where table_name = $$items$$ and column_name like $$remind%$$ order by 1"}' | \
curl -s -X POST "https://api.supabase.com/v1/projects/uqqsgmwkvslaomzxptnp/database/query" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" --data-binary @-
echo
```

Run: `zsh /tmp/apply-reminders-migration.sh`
Expected: first call returns `[]`, insert returns `[]`, last call lists `remind_at`, `reminder_cleared_at`, `reminder_notified_at` as `timestamp with time zone`.

- [ ] **Step 3: Add the columns to the generated types by hand**

In `src/integrations/supabase/types.ts`, inside `items`: add to `Row`

```ts
          remind_at: string | null
          reminder_cleared_at: string | null
          reminder_notified_at: string | null
```

and to both `Insert` and `Update` the same three keys with `?:`. In `user_preferences` add `reminder_emails: boolean` to `Row` and `reminder_emails?: boolean` to `Insert`/`Update`. Keep keys alphabetical to match the generator's output.

- [ ] **Step 4: Typecheck**

Run: `npx tsc --noEmit -p tsconfig.app.json`
Expected: no new errors.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/20260906120000_item_reminders.sql src/integrations/supabase/types.ts
git commit -m "feat(reminders): items.remind_at / reminder_cleared_at / reminder_notified_at + reminders_expire()"
```

---

### Task 2: `parseRemindAt` shared validator, wired into the three capture functions

**Files:**
- Create: `supabase/functions/_shared/reminders.ts`, `supabase/functions/_shared/reminders.test.ts`
- Modify: `supabase/functions/add-note/index.ts:66-96`, `supabase/functions/add-url/index.ts:245-388`, `supabase/functions/add-file/index.ts:98-133`

**Interfaces:**
- Produces: `parseRemindAt(value: unknown, now?: Date): string | null` (canonical ISO string or null), `DUE_WINDOW_MS = 86_400_000`.

- [ ] **Step 1: Write the failing test**

`supabase/functions/_shared/reminders.test.ts`:

```ts
import { describe, expect, it } from 'vitest';
import { DUE_WINDOW_MS, parseRemindAt } from './reminders';

const now = new Date('2026-09-06T12:00:00.000Z');

describe('parseRemindAt', () => {
  it('returns a canonical ISO string for a valid future timestamp', () => {
    expect(parseRemindAt('2026-09-09T12:00:00Z', now)).toBe('2026-09-09T12:00:00.000Z');
  });
  it('accepts offsets and normalises to UTC', () => {
    expect(parseRemindAt('2026-09-09T08:00:00-04:00', now)).toBe('2026-09-09T12:00:00.000Z');
  });
  it('tolerates up to one hour in the past (clock skew, outbox drains)', () => {
    expect(parseRemindAt('2026-09-06T11:30:00Z', now)).toBe('2026-09-06T11:30:00.000Z');
    expect(parseRemindAt('2026-09-06T10:59:00Z', now)).toBeNull();
  });
  it('ignores garbage without throwing', () => {
    expect(parseRemindAt(undefined, now)).toBeNull();
    expect(parseRemindAt(null, now)).toBeNull();
    expect(parseRemindAt('', now)).toBeNull();
    expect(parseRemindAt('soon', now)).toBeNull();
    expect(parseRemindAt(1757160000000, now)).toBeNull();
    expect(parseRemindAt({ at: '2026-09-09' }, now)).toBeNull();
  });
  it('exports the shared 24h window', () => {
    expect(DUE_WINDOW_MS).toBe(24 * 60 * 60 * 1000);
  });
});
```

- [ ] **Step 2: Run it to verify it fails**

Run: `npx vitest run supabase/functions/_shared/reminders.test.ts`
Expected: FAIL, cannot resolve `./reminders`.

- [ ] **Step 3: Implement**

`supabase/functions/_shared/reminders.ts`:

```ts
// supabase/functions/_shared/reminders.ts
//
// Reminder contract shared by the capture endpoints and the daily job.
// Import-free so it runs under Deno and vitest. Spec:
// docs/superpowers/specs/2026-09-06-reminders-design.md

/** A reminder is "due" for exactly this long after remind_at unless cleared. */
export const DUE_WINDOW_MS = 24 * 60 * 60 * 1000;

/** How far in the past a client-supplied remind_at may sit and still count. */
const PAST_TOLERANCE_MS = 60 * 60 * 1000;

/**
 * Validate a caller-supplied `remind_at`. Returns a canonical ISO-8601 UTC
 * string, or null for anything unusable — capture never fails over metadata,
 * so callers treat null as "no reminder" and log, never 4xx.
 */
export function parseRemindAt(value: unknown, now: Date = new Date()): string | null {
  if (typeof value !== 'string' || value.trim() === '') return null;
  const ms = Date.parse(value);
  if (Number.isNaN(ms)) return null;
  if (ms < now.getTime() - PAST_TOLERANCE_MS) return null;
  return new Date(ms).toISOString();
}
```

- [ ] **Step 4: Run the test**

Run: `npx vitest run supabase/functions/_shared/reminders.test.ts`
Expected: 5 passed.

- [ ] **Step 5: Wire into `add-note`**

At the top of `supabase/functions/add-note/index.ts` add `import { parseRemindAt } from '../_shared/reminders.ts';`. Replace the destructuring at line 66 and add the validator:

```ts
    const { content, title, is_public = false, attributes, remind_at } = body;
    const safeAttributes =
      attributes && typeof attributes === 'object' && !Array.isArray(attributes) ? attributes : {};
    const remindAt = parseRemindAt(remind_at);
    if (remind_at !== undefined && remindAt === null) {
      console.warn('add-note: ignoring invalid remind_at', { remind_at });
    }
```

and add `remind_at: remindAt,` to the `.insert({ ... })` object after `attributes: safeAttributes`.

- [ ] **Step 6: Wire into `add-url`**

Same import. At line 245 add `remind_at` to the destructured body, add the two `remindAt` lines right after `safeAttributes`, and add `remind_at: remindAt,` to the insert at line ~375 after `attributes: safeAttributes`.

- [ ] **Step 7: Wire into `add-file`**

Same import. Line 98: `const { file_path, mime_type, file_size, content, title, is_public = false, attributes, remind_at } = await req.json();` then the two `remindAt` lines after `safeAttributes`, and `remind_at: remindAt,` in the insert after `attributes: safeAttributes,`.

- [ ] **Step 8: Deploy and probe**

```bash
supabase functions deploy add-note --project-ref uqqsgmwkvslaomzxptnp
supabase functions deploy add-url --project-ref uqqsgmwkvslaomzxptnp
supabase functions deploy add-file --project-ref uqqsgmwkvslaomzxptnp
supabase functions list --project-ref uqqsgmwkvslaomzxptnp | grep -E "add-note|add-url|add-file"
```

Then, using the `will+uitest` test account JWT (recipe: memory `web-qa-playwright-recipe` / `ios-app-plan`; obtain via `POST /auth/v1/token?grant_type=password`), POST to `add-note` with `{"content":"reminder probe","remind_at":"<now+3d ISO>"}` and confirm the response `note.remind_at` equals the sent instant; POST again with `"remind_at":"soon"` and confirm the item saves with `remind_at: null`. Delete both probe items afterwards.

- [ ] **Step 9: Commit**

```bash
git add supabase/functions/_shared/reminders.ts supabase/functions/_shared/reminders.test.ts supabase/functions/add-note/index.ts supabase/functions/add-url/index.ts supabase/functions/add-file/index.ts
git commit -m "feat(reminders): capture endpoints accept remind_at (ignored when invalid)"
```

---

### Task 3: `reminder-digest` edge function (hygiene step) + cron schedule + secrets

**Files:**
- Create: `supabase/functions/reminder-digest/index.ts`, `supabase/migrations/20260906121000_reminder_digest_cron.sql`
- Modify: `supabase/config.toml` (append a `[functions.reminder-digest]` block)

**Interfaces:**
- Produces: `POST /functions/v1/reminder-digest` with header `x-cron-secret`; optional `?dry_run=1`. Response `{ expired: number, digest: { status: 'skipped', reason: string } }` in this plan; Plan 3 replaces `digest`.
- Consumes: `public.reminders_expire()` from Task 1.

- [ ] **Step 1: Write the function**

```ts
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.50.2';

// Daily job (pg_cron 13:00 UTC → pg_net → here). Two steps:
//  1. hygiene: materialise reminder_cleared_at for reminders past their 24h window
//  2. digest:  email each user their due reminders (Plan 3; skipped until
//              RESEND_API_KEY exists)
// Auth is a shared secret, not a JWT: the caller is Postgres, not a person.

const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } });

serve(async (req) => {
  const expected = Deno.env.get('CRON_SECRET');
  if (!expected || req.headers.get('x-cron-secret') !== expected) {
    return json(401, { error: 'unauthorized' });
  }
  const url = new URL(req.url);
  const dryRun = url.searchParams.get('dry_run') === '1';

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  );

  let expired = 0;
  if (dryRun) {
    const cutoff = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();
    const { count, error } = await supabase
      .from('items')
      .select('id', { count: 'exact', head: true })
      .not('remind_at', 'is', null)
      .is('reminder_cleared_at', null)
      .lte('remind_at', cutoff);
    if (error) return json(500, { error: error.message });
    expired = count ?? 0;
  } else {
    const { data, error } = await supabase.rpc('reminders_expire');
    if (error) return json(500, { error: error.message });
    expired = typeof data === 'number' ? data : 0;
  }

  const digest = Deno.env.get('RESEND_API_KEY')
    ? { status: 'skipped', reason: 'digest step lands in plan 3' }
    : { status: 'skipped', reason: 'RESEND_API_KEY unset' };

  console.log('reminder-digest', { dryRun, expired, digest });
  return json(200, { expired, digest });
});
```

- [ ] **Step 2: Register the function in `supabase/config.toml`**

Append:

```toml
# Cron-invoked (pg_cron → pg_net). Auth is the x-cron-secret header checked
# in-function; there is no user JWT on this path.
[functions.reminder-digest]
verify_jwt = false
```

- [ ] **Step 3: Generate and store the secret**

```bash
openssl rand -hex 32
```

Copy the value once into two places (never into a file in the repo):

```bash
supabase secrets set CRON_SECRET=<value> --project-ref uqqsgmwkvslaomzxptnp
```

and into Vault via the Management API. Write `/tmp/vault-cron-secret.sh` with the keychain-token preamble from Task 1 and this query (substitute the value):

```zsh
printf '%s' '{"query":"select vault.create_secret($$<value>$$, $$cron_secret$$, $$reminder-digest x-cron-secret header$$)"}' | \
curl -s -X POST "https://api.supabase.com/v1/projects/uqqsgmwkvslaomzxptnp/database/query" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" --data-binary @-
```

Run it, then `rm /tmp/vault-cron-secret.sh`. Verify with the query `select name from vault.secrets` → `cron_secret`.

- [ ] **Step 4: Deploy and invoke by hand**

```bash
supabase functions deploy reminder-digest --project-ref uqqsgmwkvslaomzxptnp
supabase functions list --project-ref uqqsgmwkvslaomzxptnp | grep reminder-digest
curl -s -X POST "https://uqqsgmwkvslaomzxptnp.supabase.co/functions/v1/reminder-digest?dry_run=1" -H "x-cron-secret: <value>"
curl -s -X POST "https://uqqsgmwkvslaomzxptnp.supabase.co/functions/v1/reminder-digest?dry_run=1" -H "x-cron-secret: wrong"
```

Expected: first returns `{"expired":0,"digest":{"status":"skipped","reason":"RESEND_API_KEY unset"}}`; second returns 401.

- [ ] **Step 5: Write the cron migration**

`supabase/migrations/20260906121000_reminder_digest_cron.sql`:

```sql
-- Daily reminder job. pg_cron 1.6: cron.schedule(name, …) upserts by name.
-- The shared secret is read from Vault at run time so nothing sensitive is
-- committed (the older retry-pending-scrapes job embeds its token instead).
SELECT cron.schedule(
  'reminder-digest',
  '0 13 * * *',
  $$
  SELECT net.http_post(
    url := 'https://uqqsgmwkvslaomzxptnp.supabase.co/functions/v1/reminder-digest',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-cron-secret', (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'cron_secret' LIMIT 1)
    ),
    body := '{}'::jsonb
  );
  $$
);
```

- [ ] **Step 6: Apply the cron migration and verify the job exists**

Reuse the Task 1 script pattern with this file, record version `20260906121000` / name `reminder_digest_cron` in `schema_migrations`, then query `select jobname, schedule from cron.job` → contains `reminder-digest | 0 13 * * *`. Trigger one real run without waiting for 13:00: query `select cron.schedule('reminder-digest-once', '* * * * *', (select command from cron.job where jobname = 'reminder-digest'))`, wait ~90 s, check `select status, return_message from cron.job_run_details where jobid = (select jobid from cron.job where jobname='reminder-digest-once') order by start_time desc limit 1` shows `succeeded`, then `select cron.unschedule('reminder-digest-once')`. Also confirm the edge function log (Supabase dashboard or `supabase functions logs` if available) shows a `reminder-digest` line with `dryRun: false`.

- [ ] **Step 7: Commit**

```bash
git add supabase/functions/reminder-digest/index.ts supabase/migrations/20260906121000_reminder_digest_cron.sql supabase/config.toml
git commit -m "feat(reminders): reminder-digest cron function (hygiene step) + versioned pg_cron schedule"
```

---

### Task 4: Web reminder logic (pure)

**Files:**
- Create: `src/utils/reminders.ts`, `src/utils/reminders.test.ts`

**Interfaces:**
- Produces:
  - `DUE_WINDOW_MS`, `REMINDER_PRESETS: readonly [1, 3, 5]`, `type ReminderPreset = 1 | 3 | 5`
  - `type ReminderState = 'none' | 'scheduled' | 'due' | 'cleared'`
  - `interface ReminderFields { remind_at?: string | null; reminder_cleared_at?: string | null }`
  - `reminderState(item: ReminderFields, now: Date): ReminderState`
  - `remindAtForPreset(days: ReminderPreset, now: Date): string`
  - `orderDueFirst<T extends ReminderFields>(items: T[], now: Date): T[]`
  - `reminderLabel(item: ReminderFields, now: Date): string | null` — `"Due"`, `"in 5h"`, `"in 3d"`, else null
  - `setReminderPatch(remindAt: string)` → `{ remind_at, reminder_cleared_at: null, reminder_notified_at: null }`
  - `clearReminderPatch(now: Date)` → `{ reminder_cleared_at: string }`

- [ ] **Step 1: Write the failing tests**

`src/utils/reminders.test.ts`:

```ts
import {
  clearReminderPatch,
  orderDueFirst,
  remindAtForPreset,
  reminderLabel,
  reminderState,
  setReminderPatch,
} from './reminders';

const now = new Date('2026-09-06T12:00:00.000Z');
const at = (iso: string) => ({ remind_at: iso, reminder_cleared_at: null });

describe('reminderState', () => {
  it('is none without remind_at', () => {
    expect(reminderState({}, now)).toBe('none');
    expect(reminderState({ remind_at: null }, now)).toBe('none');
  });
  it('is scheduled before remind_at', () => {
    expect(reminderState(at('2026-09-06T12:00:01Z'), now)).toBe('scheduled');
  });
  it('is due from remind_at up to (not including) remind_at + 24h', () => {
    expect(reminderState(at('2026-09-06T12:00:00Z'), now)).toBe('due');
    expect(reminderState(at('2026-09-05T12:00:01Z'), now)).toBe('due');
    expect(reminderState(at('2026-09-05T12:00:00Z'), now)).toBe('cleared');
  });
  it('cleared_at wins over everything', () => {
    expect(reminderState({ remind_at: '2026-09-06T12:00:00Z', reminder_cleared_at: '2026-09-06T12:30:00Z' }, now)).toBe('cleared');
    expect(reminderState({ remind_at: '2026-09-09T12:00:00Z', reminder_cleared_at: '2026-09-06T12:30:00Z' }, now)).toBe('cleared');
  });
});

describe('remindAtForPreset', () => {
  it('adds whole days', () => {
    expect(remindAtForPreset(1, now)).toBe('2026-09-07T12:00:00.000Z');
    expect(remindAtForPreset(3, now)).toBe('2026-09-09T12:00:00.000Z');
    expect(remindAtForPreset(5, now)).toBe('2026-09-11T12:00:00.000Z');
  });
});

describe('orderDueFirst', () => {
  const items = [
    { id: 'newest', ...at('2026-09-10T00:00:00Z') },           // scheduled
    { id: 'plain' },                                            // none
    { id: 'due-later', ...at('2026-09-06T09:00:00Z') },        // due
    { id: 'expired', ...at('2026-09-01T00:00:00Z') },          // cleared by window
    { id: 'due-earlier', ...at('2026-09-05T20:00:00Z') },      // due, waiting longest
    { id: 'dismissed', remind_at: '2026-09-06T01:00:00Z', reminder_cleared_at: '2026-09-06T02:00:00Z' },
  ];
  it('puts due items first by remind_at asc and keeps the rest in incoming order', () => {
    expect(orderDueFirst(items, now).map((i) => i.id)).toEqual([
      'due-earlier', 'due-later', 'newest', 'plain', 'expired', 'dismissed',
    ]);
  });
  it('does not mutate its input', () => {
    const copy = [...items];
    orderDueFirst(items, now);
    expect(items).toEqual(copy);
  });
});

describe('reminderLabel', () => {
  it('describes each state', () => {
    expect(reminderLabel({}, now)).toBeNull();
    expect(reminderLabel(at('2026-09-06T12:00:00Z'), now)).toBe('Due');
    expect(reminderLabel(at('2026-09-06T17:00:00Z'), now)).toBe('in 5h');
    expect(reminderLabel(at('2026-09-06T12:10:00Z'), now)).toBe('in 1h');
    expect(reminderLabel(at('2026-09-09T12:00:00Z'), now)).toBe('in 3d');
    expect(reminderLabel(at('2026-09-08T18:00:00Z'), now)).toBe('in 3d');
    expect(reminderLabel(at('2026-09-01T00:00:00Z'), now)).toBeNull();
  });
});

describe('patches', () => {
  it('setReminderPatch resets cleared and notified', () => {
    expect(setReminderPatch('2026-09-09T12:00:00.000Z')).toEqual({
      remind_at: '2026-09-09T12:00:00.000Z', reminder_cleared_at: null, reminder_notified_at: null,
    });
  });
  it('clearReminderPatch stamps now', () => {
    expect(clearReminderPatch(now)).toEqual({ reminder_cleared_at: '2026-09-06T12:00:00.000Z' });
  });
});
```

- [ ] **Step 2: Run to verify failure**

Run: `npx vitest run src/utils/reminders.test.ts`
Expected: FAIL, module not found.

- [ ] **Step 3: Implement**

`src/utils/reminders.ts`:

```ts
// Explicit reminders — pure logic shared by the grid, the card and the menu.
// Contract: docs/superpowers/specs/2026-09-06-reminders-design.md. iOS mirrors
// this in StashKit's ReminderRules; keep the two in step.

export const DUE_WINDOW_MS = 24 * 60 * 60 * 1000;
const HOUR_MS = 60 * 60 * 1000;
const DAY_MS = 24 * HOUR_MS;

export const REMINDER_PRESETS = [1, 3, 5] as const;
export type ReminderPreset = (typeof REMINDER_PRESETS)[number];

export type ReminderState = 'none' | 'scheduled' | 'due' | 'cleared';

export interface ReminderFields {
  remind_at?: string | null;
  reminder_cleared_at?: string | null;
}

export function reminderState(item: ReminderFields, now: Date): ReminderState {
  if (!item.remind_at) return 'none';
  if (item.reminder_cleared_at) return 'cleared';
  const remindAt = Date.parse(item.remind_at);
  if (Number.isNaN(remindAt)) return 'none';
  const t = now.getTime();
  if (t < remindAt) return 'scheduled';
  if (t < remindAt + DUE_WINDOW_MS) return 'due';
  return 'cleared';
}

export function remindAtForPreset(days: ReminderPreset, now: Date): string {
  return new Date(now.getTime() + days * DAY_MS).toISOString();
}

/** Due items first (longest-waiting first), everything else in incoming order. */
export function orderDueFirst<T extends ReminderFields>(items: T[], now: Date): T[] {
  const due: T[] = [];
  const rest: T[] = [];
  for (const item of items) (reminderState(item, now) === 'due' ? due : rest).push(item);
  due.sort((a, b) => Date.parse(a.remind_at!) - Date.parse(b.remind_at!));
  return [...due, ...rest];
}

export function reminderLabel(item: ReminderFields, now: Date): string | null {
  const state = reminderState(item, now);
  if (state === 'due') return 'Due';
  if (state !== 'scheduled') return null;
  const ms = Date.parse(item.remind_at!) - now.getTime();
  if (ms < DAY_MS) return `in ${Math.max(1, Math.ceil(ms / HOUR_MS))}h`;
  return `in ${Math.ceil(ms / DAY_MS)}d`;
}

export const setReminderPatch = (remindAt: string) => ({
  remind_at: remindAt,
  reminder_cleared_at: null,
  reminder_notified_at: null,
});

export const clearReminderPatch = (now: Date) => ({
  reminder_cleared_at: now.toISOString(),
});
```

- [ ] **Step 4: Run tests**

Run: `npx vitest run src/utils/reminders.test.ts`
Expected: all pass. (If `reminderLabel` for `2026-09-08T18:00:00Z` yields `in 3d`: 54 h / 24 = 2.25 → ceil 3. Correct.)

- [ ] **Step 5: Commit**

```bash
git add src/utils/reminders.ts src/utils/reminders.test.ts
git commit -m "feat(reminders): web reminder state/ordering/label logic"
```

---

### Task 5: Clock provider, list columns, due-first grid ordering

**Files:**
- Create: `src/hooks/useNow.tsx`
- Modify: `src/hooks/useItems.ts:7-21`, `src/components/ContentGrid.tsx:1-10, 252-258, 283-286`, `src/components/ContentGrid.test.tsx`

**Interfaces:**
- Produces: `NowProvider({ children, tickMs = 60_000 })`, `useNow(): Date` (falls back to `new Date()` outside a provider).
- Consumes: `orderDueFirst` from Task 4.

- [ ] **Step 1: Write the failing grid test**

Append to `src/components/ContentGrid.test.tsx`:

```tsx
describe('ContentGrid reminders', () => {
  const dueItems = [
    { id: 'n', title: 'Newest plain', type: 'text', created_at: '2026-09-06T10:00:00Z' },
    { id: 'd', title: 'Due card', type: 'text', created_at: '2026-08-01T00:00:00Z',
      remind_at: new Date(Date.now() - 60_000).toISOString(), reminder_cleared_at: null },
    { id: 's', title: 'Scheduled card', type: 'text', created_at: '2026-08-02T00:00:00Z',
      remind_at: new Date(Date.now() + 86_400_000).toISOString(), reminder_cleared_at: null },
  ];

  it('lifts due cards above the chronological list', () => {
    render(<ContentGrid {...baseProps} items={dueItems} />);
    const titles = screen.getAllByTestId('card').map(el => el.textContent);
    expect(titles).toEqual(['Due card', 'Newest plain', 'Scheduled card']);
  });

  it('leaves server relevance order alone during a search', () => {
    render(<ContentGrid {...baseProps} items={dueItems} serverResultIds={['n', 'd']} searchQuery="x" />);
    const titles = screen.getAllByTestId('card').map(el => el.textContent);
    expect(titles).toEqual(['Newest plain', 'Due card']);
  });
});
```

- [ ] **Step 2: Run to verify failure**

Run: `npx vitest run src/components/ContentGrid.test.tsx`
Expected: first new test fails (order is `Newest plain, Due card, Scheduled card`).

- [ ] **Step 3: Write `useNow`**

`src/hooks/useNow.tsx`:

```tsx
import React, { createContext, useContext, useEffect, useState } from 'react';

// One ticking clock per grid so every card derives reminder state from the
// same instant, and crossing remind_at / remind_at + 24h (which produce no
// realtime event) re-renders without a per-card timer.
const NowContext = createContext<Date | null>(null);

export const NowProvider = ({ children, tickMs = 60_000 }: { children: React.ReactNode; tickMs?: number }) => {
  const [now, setNow] = useState(() => new Date());
  useEffect(() => {
    const tick = () => setNow(new Date());
    const id = setInterval(tick, tickMs);
    const onVisible = () => { if (document.visibilityState === 'visible') tick(); };
    document.addEventListener('visibilitychange', onVisible);
    return () => {
      clearInterval(id);
      document.removeEventListener('visibilitychange', onVisible);
    };
  }, [tickMs]);
  return <NowContext.Provider value={now}>{children}</NowContext.Provider>;
};

export const useNow = (): Date => useContext(NowContext) ?? new Date();
```

- [ ] **Step 4: Select the columns**

In `src/hooks/useItems.ts` add `'remind_at',` and `'reminder_cleared_at',` to `ITEM_LIST_COLUMNS` after `'attributes'`.

- [ ] **Step 5: Order the grid**

In `src/components/ContentGrid.tsx`:
- imports: `import { orderDueFirst } from '@/utils/reminders';` and `import { NowProvider, useNow } from '@/hooks/useNow';`
- inside the component, first line after the props destructure: `const now = useNow();`
- replace the block at lines 252-258 with:

```ts
  // Separate optimistic and real items
  const optimisticItems = filteredItems.filter(item => item.isOptimistic);
  let visibleRealItems = filteredItems.filter(item => !item.isOptimistic);
  if (searchRank) {
    // Relevance order while a server search is active (grid is otherwise chronological)
    visibleRealItems.sort((a, b) => searchRank.get(a.id)! - searchRank.get(b.id)!);
  } else {
    // Due reminders surface above the chronological list
    visibleRealItems = orderDueFirst(visibleRealItems, now);
  }
```

- wrap the returned grid `<div className="grid …">…</div>` in `<NowProvider>…</NowProvider>` so the cards below share the clock. (`useNow()` at the top of `ContentGrid` itself runs outside that provider and falls back to `new Date()` per render, which is fine: the grid re-renders on realtime refetches and on every card-level state change; the provider is for the cards' chips.)

Simpler and fully consistent alternative, use this one: wrap `ContentGrid` at its call site in `src/pages/Index.tsx:213-222` with `<NowProvider>` and in `ContentGrid` keep only `useNow()` (no inner provider). Then the grid ordering and the card chips share one clock. Do this.

- [ ] **Step 6: Run the grid tests and typecheck**

Run: `npx vitest run src/components/ContentGrid.test.tsx && npx tsc --noEmit -p tsconfig.app.json`
Expected: all pass, no new type errors.

- [ ] **Step 7: Commit**

```bash
git add src/hooks/useNow.tsx src/hooks/useItems.ts src/components/ContentGrid.tsx src/components/ContentGrid.test.tsx src/pages/Index.tsx
git commit -m "feat(reminders): due-first ordering in the web grid with a shared ticking clock"
```

---

### Task 6: Card UI — footer chip with dismiss, "Remind me…" menu, "Due" corner pill

**Files:**
- Create: `src/components/cards/ReminderChip.tsx`
- Modify: `src/components/ContentItemFooter.tsx:1-40, 75-90, 100-177`, `src/components/ContentItemHeader.tsx:26-40, 176-224`, `src/components/ContentItem.tsx:25-41`

**Interfaces:**
- Consumes: `reminderState`, `reminderLabel`, `remindAtForPreset`, `setReminderPatch`, `clearReminderPatch`, `REMINDER_PRESETS` (Task 4); `useNow` (Task 5); `saveItem` from `src/utils/itemOperations.ts:78`.
- Produces: `ReminderChip({ state, label, remindAt, onDismiss })`.

- [ ] **Step 1: Add the fields to the three local `ContentItem` interfaces**

In `ContentItem.tsx`, `ContentItemFooter.tsx`, `ContentItemHeader.tsx` add to each local `interface ContentItem`:

```ts
  remind_at?: string | null;
  reminder_cleared_at?: string | null;
```

- [ ] **Step 2: Write the chip**

`src/components/cards/ReminderChip.tsx`:

```tsx
import React from 'react';
import { Bell, Clock, X } from 'lucide-react';
import { format } from 'date-fns';
import type { ReminderState } from '@/utils/reminders';

/**
 * Footer reminder indicator. Scheduled reads quiet ("in 3d"); due reads in the
 * interactive violet with an always-visible remove control (DESIGN.md: the
 * control is never hover-only; hover only strengthens colour).
 */
export const ReminderChip = ({
  state,
  label,
  remindAt,
  onDismiss,
}: {
  state: ReminderState;
  label: string;
  remindAt: string;
  onDismiss: () => void;
}) => {
  const absolute = format(new Date(remindAt), 'MMM d, h:mm a');
  if (state === 'due') {
    return (
      <span
        className="inline-flex items-center gap-1 rounded-full bg-violet-600/10 pl-2 pr-0.5 py-0.5 text-[11px] font-medium text-violet-700"
        title={`Reminder was set for ${absolute}`}
        data-testid="reminder-chip-due"
      >
        <Bell className="h-3 w-3 flex-none" />
        {label}
        <button
          type="button"
          onClick={(e) => { e.stopPropagation(); onDismiss(); }}
          aria-label="Remove reminder"
          className="ml-0.5 inline-flex h-5 w-5 items-center justify-center rounded-full text-violet-700/70 hover:bg-violet-600/15 hover:text-violet-800 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-violet-600"
        >
          <X className="h-3 w-3" />
        </button>
      </span>
    );
  }
  return (
    <span
      className="inline-flex items-center gap-1 text-[11px] text-muted-foreground"
      title={`Reminder ${absolute}`}
      data-testid="reminder-chip-scheduled"
    >
      <Clock className="h-3 w-3 flex-none" />
      {label}
    </span>
  );
};
```

- [ ] **Step 3: Footer — chip, submenu, writes**

In `src/components/ContentItemFooter.tsx`:

imports to add:

```ts
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuSeparator, DropdownMenuSub, DropdownMenuSubContent, DropdownMenuSubTrigger, DropdownMenuTrigger } from '@/components/ui/dropdown-menu';
import { Bell, BellOff } from 'lucide-react';
import { useToast } from '@/hooks/use-toast';
import { useNow } from '@/hooks/useNow';
import { saveItem } from '@/utils/itemOperations';
import { ReminderChip } from '@/components/cards/ReminderChip';
import { REMINDER_PRESETS, clearReminderPatch, remindAtForPreset, reminderLabel, reminderState, setReminderPatch, type ReminderPreset } from '@/utils/reminders';
```

(merge the dropdown import with the existing one on line 3.)

inside the component, after `const [reportOpen, setReportOpen] = useState(false);`:

```ts
  const now = useNow();
  const { toast } = useToast();
  const reminder = reminderState(item, now);
  const reminderText = reminderLabel(item, now);
  const hasActiveReminder = reminder === 'scheduled' || reminder === 'due';

  // Writes go straight through the items PATCH path; the realtime subscription
  // in useItems refetches the list, so no local refresh is needed.
  const noRefresh = async () => {};
  const setReminder = (days: ReminderPreset) =>
    saveItem(item.id, setReminderPatch(remindAtForPreset(days, new Date())), noRefresh, toast, { showSuccessToast: false, refreshItems: false });
  const removeReminder = () =>
    saveItem(item.id, clearReminderPatch(new Date()), noRefresh, toast, { showSuccessToast: false, refreshItems: false });
```

In the left footer group, after the date `<p>` and before the location block, add:

```tsx
        {!isPublicView && hasActiveReminder && reminderText && item.remind_at && (
          <ReminderChip state={reminder} label={reminderText} remindAt={item.remind_at} onDismiss={removeReminder} />
        )}
```

In the `{!isPublicView && (<> … </>)}` menu block, before the `Edit` item, add:

```tsx
                <DropdownMenuSub>
                  <DropdownMenuSubTrigger>
                    <Bell className="h-4 w-4 mr-2" />
                    {hasActiveReminder ? 'Change reminder…' : 'Remind me…'}
                  </DropdownMenuSubTrigger>
                  <DropdownMenuSubContent>
                    {REMINDER_PRESETS.map((days) => (
                      <DropdownMenuItem key={days} onClick={() => setReminder(days)}>
                        {days === 1 ? 'In 1 day' : `In ${days} days`}
                      </DropdownMenuItem>
                    ))}
                  </DropdownMenuSubContent>
                </DropdownMenuSub>
                {hasActiveReminder && (
                  <DropdownMenuItem onClick={removeReminder}>
                    <BellOff className="h-4 w-4 mr-2" />
                    Remove reminder
                  </DropdownMenuItem>
                )}
                <DropdownMenuSeparator />
```

- [ ] **Step 4: Header — "Due" pill**

In `src/components/ContentItemHeader.tsx`: import `useNow` and `reminderState`; inside the component compute `const isDue = !isPublicView && reminderState(item, useNow()) === 'due';` (call `useNow()` unconditionally at the top, then compute). Change `const showInlineBadges = !hero && !isPublicView && (isProcessing || item.is_public);` to include `|| isDue`. In both badge zones (the absolute overlay and the inline fallback) add, after the `PUBLICLY SHARED` element:

```tsx
                {isDue && (
                  <span className="rounded-full bg-violet-600 px-2 py-0.5 text-[11px] font-medium text-white shadow-sm" data-testid="due-pill">
                    Due
                  </span>
                )}
```

- [ ] **Step 5: Typecheck, full test run**

Run: `npx tsc --noEmit -p tsconfig.app.json && npm test`
Expected: no new type errors; all suites green (baseline count from `main` + the new tests).

- [ ] **Step 6: Manual QA on the dev server (Playwright recipe from memory `web-qa-playwright-recipe`)**

1. `npm run dev`, log in as `will+uitest`.
2. On any card: menu → Remind me… → In 3 days. Expect the footer to show a clock chip `in 3d` within a second (realtime refetch).
3. Back-date it with the Management API: `update items set remind_at = now() - interval '5 minutes' where id = '<id>'`. Expect: card moves to the top, `Due` pill in the corner, violet `Due` chip with ×.
4. Click ×. Expect: chip and pill disappear, card returns to its chronological slot.
5. Set again, then `update items set remind_at = now() - interval '25 hours'`. Expect: no chip, no pill (expired by window) even before the daily job runs.
6. Keyboard: Tab to the × and press Enter; confirm `aria-label="Remove reminder"` is announced.

- [ ] **Step 7: Commit**

```bash
git add src/components/cards/ReminderChip.tsx src/components/ContentItemFooter.tsx src/components/ContentItemHeader.tsx src/components/ContentItem.tsx
git commit -m "feat(reminders): card chip, Due pill, Remind me… menu and dismiss on web"
```

---

### Task 7: Contracts and docs

**Files:**
- Modify: `docs/PLATFORM_API.md` (Capture preamble at :22-32; new section before `## Live updates` at :204), `docs/ui-changes.md` (new top entry after the header at :9), `DESIGN.md:187-190, 214-217`

- [ ] **Step 1: PLATFORM_API — capture parameter**

After the `attributes` paragraph in `## Capture` add:

```markdown
Every capture endpoint also accepts an optional top-level `remind_at`
(ISO-8601 timestamp): "bring this back to me then". It must parse and be no
older than one hour before now; anything else is ignored — the item still
saves with `remind_at: null` and a warning is logged. Never a 4xx. The
returned item includes `remind_at`, `reminder_cleared_at`,
`reminder_notified_at`. See **Reminders** below.
```

- [ ] **Step 2: PLATFORM_API — Reminders section**

Insert before `## Live updates`:

```markdown
## Reminders

Spec: `docs/superpowers/specs/2026-09-06-reminders-design.md`.

Three nullable `timestamptz` columns on `items`: `remind_at`,
`reminder_cleared_at`, `reminder_notified_at`. State is **derived**, never
stored, with `DUE_WINDOW = 24h`:

| condition | state |
|---|---|
| `remind_at` is null | none |
| `reminder_cleared_at` is set | cleared |
| `now < remind_at` | scheduled |
| `remind_at ≤ now < remind_at + 24h` | due |
| otherwise | cleared (expired; the daily job back-fills `reminder_cleared_at`) |

`now` is the device clock on clients; re-evaluate on a 60 s tick and on
foreground, because crossing either boundary emits no realtime event.

Writes (owner, ordinary PostgREST `PATCH /rest/v1/items?id=eq.<id>`):

- set / re-set: `{ "remind_at": "<ISO>", "reminder_cleared_at": null, "reminder_notified_at": null }`
- dismiss: `{ "reminder_cleared_at": "<now ISO>" }`

Clients never write `reminder_notified_at`. Presets are 1 / 3 / 5 days;
clients send the absolute instant.

Due items for a badge or a top-of-list block:

```
GET /rest/v1/items?select=<list columns>&user_id=eq.<uid>
  &reminder_cleared_at=is.null&remind_at=lte.<now>&remind_at=gt.<now-24h>
  &order=remind_at.asc
```

Ordering rule on every surface: due items first (`remind_at` asc), then the
normal chronological list; a server search's relevance order wins while
active.

Daily job: `reminder-digest` (pg_cron 13:00 UTC → pg_net → edge function,
`x-cron-secret` header). Step 1 expires stale reminders; step 2 emails each
user their due, un-notified reminders once (one email per user per day,
never one per reminder) and stamps `reminder_notified_at`.
```

- [ ] **Step 3: ui-changes entry**

Insert directly under the `---` at line 9:

```markdown
## 2026-09-06 · Reminders: "bring this back in 1 / 3 / 5 days" — web + platform (iOS + email follow)

Spec `docs/superpowers/specs/2026-09-06-reminders-design.md`; plans
`docs/superpowers/plans/2026-09-06-reminders-{1-backend-web,2-ios,3-email}.md`.

- **Contract (all clients):** three columns on `items` — `remind_at`,
  `reminder_cleared_at`, `reminder_notified_at`. State is derived with a 24h
  window (`none / scheduled / due / cleared`); see `docs/PLATFORM_API.md`
  → Reminders for the table, the two write shapes, and the due-items query.
  Capture endpoints accept an optional top-level `remind_at`; invalid values
  are ignored, never a 4xx.
- **Ordering rule:** due items first (`remind_at` asc), then chronological.
  Skipped while a server search rank is active.
- **Web:** footer chip after the date — scheduled `in 3d` (muted, clock),
  due `Due` (violet, bell) with an always-visible × "Remove reminder"; a
  violet `Due` pill joins the hero-corner badge zone. Card menu gains
  "Remind me…" (In 1 / 3 / 5 days), "Change reminder…" and "Remove reminder"
  when one is active. None of it renders in public views. One `NowProvider`
  clock per grid (60 s tick + visibilitychange) drives state.
- **Backend:** `reminder-digest` edge function on a version-controlled
  pg_cron schedule (13:00 UTC, secret from Vault). Today it only expires
  stale reminders; the email step ships with plan 3.
- **iOS (plan 2):** share-sheet chips `1 day · 3 days · 5 days` above Save;
  View tab badge = due count; due block at the top of the grid; same footer
  chip + Due overlay + dismiss.
- **Not in this cut:** inferred resurfacing, Keep/Done/Let go, push, custom
  dates, per-user timezone, controls in the in-app composer / extension /
  web capture box.

---
```

- [ ] **Step 4: DESIGN.md amendment**

Line 187-190 card anatomy: change `→ chips → footer (date left; overflow \`more-horizontal\` right).` to `→ chips → footer (date · reminder chip · location pin left; overflow \`more-horizontal\` right).`

After the chips-grammar paragraph (line 217) add:

```markdown
**Reminder chip** (footer, after the date; both platforms): scheduled = clock
icon + relative time in the muted meta style; due = bell + "Due" in
violet-600 on a 10 % violet field with an always-visible × ("Remove
reminder", ≥24 px hit area). Due cards also carry a violet-600 "Due" pill in
the hero-corner badge zone next to "Processing…" / "PUBLICLY SHARED". Neither
belongs in the chips row.
```

- [ ] **Step 5: Commit and hand off**

```bash
git add docs/PLATFORM_API.md docs/ui-changes.md DESIGN.md
git commit -m "docs(reminders): platform contract, ui-changes entry, DESIGN footer/pill amendment"
```

Then follow `superpowers:finishing-a-development-branch`: merge to `main`, push (Vercel deploys), and confirm the served bundle contains the marker string `Remove reminder` (`curl -s https://www.gostash.it | grep -o 'assets/index-[^"]*\.js'` then grep the asset).

---

## Self-review

- Spec coverage: data model (T1), capture parameter (T2), daily job hygiene + cron + Vault (T3), derived state / ordering / labels (T4), grid ordering + clock (T5), card chip / pill / menu / dismiss / no public UI (T6), PLATFORM_API + ui-changes + DESIGN (T7). Email content, unsubscribe, settings toggle → Plan 3. iOS → Plan 2.
- Names used across tasks: `parseRemindAt`, `DUE_WINDOW_MS`, `reminders_expire`, `reminderState`, `reminderLabel`, `orderDueFirst`, `remindAtForPreset`, `setReminderPatch`, `clearReminderPatch`, `REMINDER_PRESETS`, `useNow`, `NowProvider`, `ReminderChip` — consistent.
