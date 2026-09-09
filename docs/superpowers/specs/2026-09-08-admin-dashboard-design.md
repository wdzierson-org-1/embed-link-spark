# Admin dashboard (temporary) — design

**Status:** built 2026-09-08 from Will's ask; decisions below were made without a
live review round (autonomous session) and are flagged where they are
judgment calls. **Lifetime:** until Stash has a critical mass of members, then
switched off (see *Kill switch*).

## Why

While the first members are getting up and running, Will wants to see who is
signing in, how often, and what kinds of things they save — so onboarding
problems and capture patterns are visible without pulling SQL by hand. This is
an internal, admin-only view; members never see it and nothing about the
product changes for them.

Privacy posture: the admin views a member's library *as they see it*. That is
a deliberate, time-boxed exception to the "only you see your stash" promise,
taken now because the member count is tiny and every member is a known
early tester. The whole feature is behind one table (`admin_users`) whose
rows can be deleted in one statement to switch everything off.

## Access control

- **`public.admin_users (user_id uuid pk → auth.users, created_at)`.** RLS on;
  the only policy is `SELECT` of your own row (so the web app can decide
  whether to show the Admin menu item). No insert/update/delete policies —
  only the service role writes. Also fenced from agent (MCP) tokens like every
  other table.
- The migration seeds Will's row (`INSERT … SELECT id FROM auth.users WHERE
  email = 'will@dzierson.com' ON CONFLICT DO NOTHING`), so a fresh `db reset`
  and production both end up consistent without a manual step.
- **Server side** every admin call authenticates the JWT (`_shared/auth.ts`
  → `authenticateUser`), then requires an `admin_users` row for that user
  (403 otherwise). Client-side gating is only a convenience.
- **Stats SQL** runs in `public.admin_user_stats()`, `SECURITY DEFINER`, with
  EXECUTE revoked from `anon`/`authenticated` and granted to `service_role`
  only — it reads `auth.users` and `auth.audit_log_entries`, which PostgREST
  never exposes.

### Kill switch

```sql
DELETE FROM public.admin_users;
```

That single statement hides the menu item, and every admin endpoint returns
403. Nothing else needs to change or deploy. To remove the feature entirely
afterwards: drop the `/admin` routes, the `admin-stats` function, then
`DROP FUNCTION admin_user_stats(); DROP TABLE admin_users;`.

## Data

`admin_user_stats()` returns one row per `auth.users` row:

| Column | Source / definition |
|---|---|
| `user_id`, `email`, `is_anonymous`, `created_at`, `last_sign_in_at` | `auth.users` |
| `username`, `display_name` | `public.user_profiles` (left join) |
| `total_logins` | count of `auth.audit_log_entries` with `payload.action = 'login'` and `payload.actor_id = user_id` (the audit log predates every account, so this is complete) |
| `active_days` | distinct UTC days with a `login` **or** `token_refreshed` audit entry — a refreshed token means the app was open that day, which matters because web/iOS sessions persist for weeks and explicit logins undercount use |
| `last_active_at` | latest of those entries |
| `item_count`, `items_last_7d`, `last_item_at` | `public.items` |
| `items_by_type` | jsonb `{ "link": 12, "text": 3, … }` |

Derived on the client (`src/utils/adminStats.ts`, unit-tested):

- **Logins per day** = `total_logins ÷ max(1, whole days since created_at)`.
- **Summary tiles:** members (non-anonymous users), active in the last 7 days
  (`last_active_at`), items saved (all rows, anonymous included), items saved
  in the last 7 days (sum of `items_last_7d`).
- **Test accounts:** plus-addressed `will+…` emails are Will's own fixtures
  (they exist on several domains). The table hides them by default behind a
  checkbox. Anonymous "try Stash" sessions are never listed (no name, no
  email); their count appears as a footnote under the members tile.

## Endpoint

`POST /functions/v1/admin-stats` — user JWT + anon `apikey`, like every other
function (`verify_jwt = true` at the gateway *and* the in-function admin check).

| Body | 200 response |
|---|---|
| `{ "action": "users" }` | `{ "users": AdminUserRow[] }` (ordered `created_at` desc) |
| `{ "action": "items", "user_id": "<uuid>" }` | `{ "user": { user_id, email, username, display_name, created_at }, "items": Item[] }` — the same column list the library grid loads (`ITEM_LIST_COLUMNS` in `useItems`), newest first |

Errors: `401` missing/invalid JWT · `403` caller not an admin · `400` unknown
action or malformed `user_id` · `404` no such user. Always JSON `{ error }`.

Not added to `docs/PLATFORM_API.md`: this is not a client contract and will
be removed.

## Web UI

Two routes, both lazy-loaded, both rendered under the normal `HeaderSection`
so the admin never leaves the app's chrome. Non-admins (and signed-out
visitors) are redirected to `/home` / `/auth`.

**Menu entry.** The avatar menu gains "Admin" (Lucide `Gauge`) between
Discover and Preview public feed, only when `useIsAdmin()` resolves true.

**`/admin` — Members.**
- Eyebrow `ADMIN · TEMPORARY` + display header "Members" + one-line note that
  the view is internal and will be switched off.
- Four stat tiles (neutral chrome per `DESIGN.md`: number in ink, label in
  faint caps; no decorative color — color is information and these are
  counts).
- Toolbar: search (name / email / username), "Hide test accounts" checkbox
  (on by default).
- Table (shadcn `Table`): Member (display name, `@username` under it), Email,
  Joined, Last login, Logins, Per day, Active days, Items, Last saved. Header
  click sorts (default: Last active desc — the people to look at first).
  Member and Email cells are violet links to the user page. Items cell
  carries a small type breakdown (`12 links · 3 notes`) in the faint style.
- Times are compact relative strings (`45m ago`, `3mo ago`, `Never`) with the
  absolute timestamp in `title`; the per-day rate shows two decimals under 1,
  one under 10, none above.

**`/admin/users/:userId` — a member's library.**
- Back link "Members", then an identity strip: initial avatar, display name
  or username, email, joined date, item count, and one neutral chip per type
  with its count.
- Search box (client substring filter — same predicate as the library) and
  type pills (All / Links / Notes / Docs / Media → `ContentGrid.typeFilter`).
- `ContentGrid` in **public-view mode** (`isPublicView`): this is what the
  member's grid looks like minus owner-only chrome — no card menu, no
  reminder chips, no delete/edit, no comment or privacy controls (those
  callbacks are simply not passed). Link titles open the URL, like the public
  feed. Media renders straight from the public `stash-media` bucket, so
  photos, players and documents look exactly as they do to the member.
- Explicitly *not* the edit sheet: opening a member's item for editing is
  out of scope and would write to their data.

## Testing

- `src/utils/adminStats.test.ts` — logins-per-day rounding/zero-day guard,
  summary tiles, test-account predicate, sort comparator.
- `supabase/functions/_shared/adminDashboard.test.ts` — request parsing
  (`users` / `items` / bad input) and a parity check that the admin item
  column list equals `useItems`' `ITEM_LIST_COLUMNS` (so the recreated grid
  never drifts from the real one).
- `src/hooks/useIsAdmin.test.tsx`, `src/components/HeaderSection.test.tsx`
  (menu item shown only for admins), `src/pages/Admin.test.tsx`,
  `src/pages/AdminUser.test.tsx` — rendering with the endpoint mocked.
- Live verification after deploy: the fixture account `will+uitest` is added
  to `admin_users` for the smoke run and removed afterwards; anon → 401,
  non-admin → 403, admin → rows.

## Out of scope

Editing members' items, impersonation, exports, charts over time, per-item
enrichment status, Stripe/subscription state (lives in Stripe; the
`check-subscription` path is per-user and slow), iOS/macOS/extension
surfaces.

## Implementation order

1. Migration `20260908120000_admin_dashboard.sql` (table, policies, RPC).
2. `_shared/adminDashboard.ts` + tests; `admin-stats` edge function.
3. `types.ts` entries; `useIsAdmin`; header menu item; `adminStats` utils.
4. `Admin` and `AdminUser` pages; routes.
5. Docs: this spec, `docs/ui-changes.md` entry.
6. Apply migration, deploy function, merge, verify on production.
