# Reminders — explicit "bring this back to me" on stashed items

**Status:** design for review (2026-09-06). Written from Will's requirement
"Reminders and Resurfacing for Stashed Items"; this spec covers the
explicit-reminder foundation only. Intelligent (inferred) resurfacing stays
in `2026-08-28-retention-loop-and-context-layer-spec.md` Workstream A and
builds on the state defined here.

## What ships

A user can say "bring this back in 1 / 3 / 5 days" about one item. When the
time comes the item is **due** for 24 hours: it sorts to the top on web and in
the iOS View tab, the View tab shows a badge with the due count, and a daily
email lists everything due. The user can remove the reminder from the card at
any time; if they do nothing it clears itself 24 hours after becoming due. The
item is never moved, hidden, or deleted by any of this.

Four deliverables, in order:

1. **Backend + contract** — three columns on `items`, `remind_at` accepted by
   the capture endpoints, one daily maintenance/digest job.
2. **Web** — due-first ordering, card indicator, "Remind me…" in the card
   menu, dismiss control.
3. **iOS** — reminder chips in the share sheet, View tab badge, due-first
   ordering, card indicator + dismiss.
4. **Email** — daily reminder digest (needs a transactional email provider,
   which does not exist yet; see Prerequisites).

## Decisions taken (each reversible on review)

| Question | Decision | Why |
|---|---|---|
| Where does reminder state live? | **Three nullable columns on `items`**: `remind_at`, `reminder_cleared_at`, `reminder_notified_at`. Not inside `attributes`. | `attributes` is written whole-blob by every client and by server enrichment; a reminder inside it could be silently wiped by an older iOS build or an enrichment pass. Columns give atomic writes, ordinary indexes, plain PostgREST filters, and a trivially correct daily SQL job. Reminders are user intent, not object facts, so the `attributes` lane isn't the right home anyway. This supersedes B2 of the 2026-08-28 spec (`attributes.resurface`). |
| Who decides "due" and "expired"? | **Derived, never stored.** `due = remind_at ≤ now < remind_at + 24h and reminder_cleared_at is null`. | No cron is needed for correctness; every surface computes the same state from the same two columns. The daily job materializes `reminder_cleared_at` for expired rows as hygiene only. |
| Pre-save or post-save control in the share sheet? | **Pre-save chip row, default off, never gating Save.** | The requirement asks for it "before completing the save." The compose card already offers optional pre-save controls (note, location pin) with zero cost to ignore; the chips join that class. This departs from B1 of the 2026-08-28 spec (post-save chips), which is noted there. |
| Presets | 1 day · 3 days · 5 days. Client sends an absolute `remind_at`. | Absolute time survives the iOS offline outbox draining days later. |
| Email cadence | **One email per user per day**, 13:00 UTC, only when ≥1 reminder is due and not yet emailed. Never one email per reminder. | Every due reminder lives in a 24h window, so one daily run sees each exactly once. Per-user timezone is a later refinement. |
| Dismiss vs delete the reminder | Dismiss sets `reminder_cleared_at`; the timestamp stays. | Keeps "set and cleared" history queryable (future taste-graph signal, spec A5) at zero cost. Re-setting a reminder resets both cleared and notified. |
| Where can a reminder be set? | iOS share sheet (required), web card menu (cheap, and the only way to QA web end-to-end). In-app iOS composer and card-level "remind me" on iOS are **later**. | Scope discipline; the View tab work is already the largest iOS piece. |
| MCP tools | Unchanged. | `remind_at` can be exposed through `get_item` later; not part of this cut. |

## Data model

Migration `supabase/migrations/20260906120000_item_reminders.sql`:

```sql
ALTER TABLE public.items
  ADD COLUMN remind_at timestamptz,
  ADD COLUMN reminder_cleared_at timestamptz,
  ADD COLUMN reminder_notified_at timestamptz;

COMMENT ON COLUMN public.items.remind_at IS
  'User-set "bring this back" time. Due for 24h from this instant unless cleared.';
COMMENT ON COLUMN public.items.reminder_cleared_at IS
  'Set by user dismissal, or by the daily job 24h after remind_at. Null = still active.';
COMMENT ON COLUMN public.items.reminder_notified_at IS
  'When the reminder digest email included this item. Idempotency for the daily job.';

CREATE INDEX items_reminder_active
  ON public.items (user_id, remind_at)
  WHERE remind_at IS NOT NULL AND reminder_cleared_at IS NULL;

ALTER TABLE public.user_preferences
  ADD COLUMN reminder_emails boolean NOT NULL DEFAULT true;
```

RLS is unchanged: owners already select/update their own rows, so clients set
and clear reminders through ordinary PostgREST updates. The daily job uses the
service role.

### Derived state (the contract every surface implements)

```
DUE_WINDOW = 24 hours

state(item, now):
  remind_at == null                      → none
  reminder_cleared_at != null            → cleared
  now <  remind_at                       → scheduled
  now <  remind_at + DUE_WINDOW          → due
  otherwise                              → cleared   (expired; job back-fills the column)
```

`now` is the device clock on clients and `now()` in SQL. Surfaces that show
state must re-evaluate on a timer (60 s) and on foreground/visibility, because
crossing `remind_at` or `remind_at + 24h` does not produce a realtime event.

### Writes

| Action | Statement (owner, via PostgREST) |
|---|---|
| Set / re-set | `update items set remind_at = $ts, reminder_cleared_at = null, reminder_notified_at = null where id = $id` |
| Dismiss | `update items set reminder_cleared_at = now() where id = $id` |

Both go through the existing item-update paths (`saveItem` on web,
`SupabaseItemPatcher` on iOS) with the new fields added to their patch types.

## Platform API changes (`docs/PLATFORM_API.md`)

- `add-url`, `add-note`, `add-file` accept an optional top-level
  `remind_at` (ISO-8601 timestamp). Shared validator in
  `supabase/functions/_shared/reminders.ts`: must parse, must be later than
  `now − 1h`. Anything else is **ignored** (item saves, `remind_at` stays
  null, a warning is logged). Capture never fails over metadata, same rule as
  `attributes`.
- The returned item includes `remind_at`, `reminder_cleared_at`,
  `reminder_notified_at`.
- New section "Reminders" documenting the three columns, the derived-state
  table above, the two write statements, the due-items query below, and the
  daily job. Clients never write `reminder_notified_at`.

Due-items query (used by iOS for the badge and the top-of-list block; web
derives the same from its full list):

```
GET /rest/v1/items?select=<list columns>
  &user_id=eq.<uid>
  &reminder_cleared_at=is.null
  &remind_at=lte.<now ISO>
  &remind_at=gt.<now − 24h ISO>
  &order=remind_at.asc
```

## Daily job — `reminder-digest` edge function

One function, two steps, so it can ship in deliverable 1 and light up email in
deliverable 4.

1. **Hygiene:** `update items set reminder_cleared_at = remind_at + interval
   '24 hours' where remind_at is not null and reminder_cleared_at is null and
   remind_at + interval '24 hours' <= now()`. Makes expiry explicit in the
   data; clients never depend on it.
2. **Digest:** select `(item, user)` where due now, `reminder_cleared_at` null,
   `reminder_notified_at` null, and `coalesce(user_preferences.reminder_emails,
   true)`. Group by user; look up the address with
   `auth.admin.getUserById`; render; send; then set `reminder_notified_at =
   now()` for the items in that email. A send failure leaves the rows
   untouched, so the next run retries if they are still inside the window.
   If `RESEND_API_KEY` is unset the step logs and exits (deliverable 1 state).

Trigger: `pg_cron` at `0 13 * * *` calling the function through `pg_net` with
an `x-cron-secret` header. The function has `verify_jwt = false` and compares
the header to env `CRON_SECRET`. The cron SQL lives in a migration and reads
the secret from Supabase Vault (`vault.decrypted_secrets` name `cron_secret`),
so nothing sensitive is committed. Unlike `retry-pending-scrapes`, whose
schedule was created by hand, this one is version-controlled. Manual/QA
invocation: `POST ?dry_run=1&user_id=<uuid>` returns the rendered email(s)
without sending or marking.

Known miss: a reminder whose `remind_at` falls in the seconds between "24h
before this run" and the previous run's actual start is skipped. Only
reminders set within that same clock-minute are affected; accepted.

### Email content

Rendering is a pure function `renderReminderDigest({ items, unsubscribeUrl })
→ { subject, html, text }` in `_shared/reminderDigest.ts`, unit-tested with
vitest, separate from delivery (spec A6).

- Subject: `1 item you asked to see again` / `N items you asked to see again`.
- One line up top: "You asked Stash to remind you about these."
- Per item: title (fallback: first 80 chars of `content`, else the URL host,
  else the type name), type, "Saved Sep 3 · reminder for today", and a link to
  `https://www.gostash.it/home#item=<id>` (the existing deep link, which opens
  the card).
- Footer: "Turn off reminder emails" → `reminder-email-prefs?token=…`.
  Token = base64url(`<user_id>.<expires>`) + HMAC-SHA256 with env
  `EMAIL_LINK_SECRET`, 30-day expiry. That endpoint (`verify_jwt = false`)
  sets `user_preferences.reminder_emails = false` and returns a one-line HTML
  page. Web Settings → Account gets a matching switch "Email me when
  reminders are due" through `useUserPreferences`.
- Provider: Resend, from `Stash <reminders@gostash.it>`. Plain HTML, DESIGN.md
  type ramp and violet-600 for the single link colour, no images.

## Web

**Data:** `ITEM_LIST_COLUMNS` in `src/hooks/useItems.ts` gains `remind_at,
reminder_cleared_at`. Regenerate `src/integrations/supabase/types.ts`.

**Logic:** `src/lib/reminders.ts` — `reminderState(item, now)`,
`remindAtForPreset(preset, now)`, `orderDueFirst(items, now)` (due items by
`remind_at` asc, then everything else in the incoming order). Pure, vitest.
`src/hooks/useNow.ts` — ticks every 60 s and on `visibilitychange`.

**Ordering:** `ContentGrid.tsx` applies `orderDueFirst` to the filtered list
unless a search rank is active (relevance still wins during search).

**Card:**
- Footer (`ContentItemFooter.tsx`), after the date: a reminder chip.
  Scheduled: clock icon + relative time ("in 3d"), muted, `title` shows the
  absolute date. Due: bell icon + "Due" in violet-600 and a `×` button,
  `aria-label="Remove reminder"`, 24px hit target, hover only reveals the
  stronger colour, never the control itself.
- Due only: a "Due" pill in the hero corner badge zone
  (`ContentItemHeader.tsx`, next to "Processing…"/"PUBLICLY SHARED"; the
  hero-less inline path gets it too). Violet-600 background, white text,
  999px radius.
- Menu: "Remind me…" submenu with 1 day / 3 days / 5 days; when a reminder is
  scheduled or due the item reads "Change reminder…" and a "Remove reminder"
  item appears. Writes go through `saveItem(id, patch, { showSuccessToast:
  false })`; realtime refetch does the rest.
- Public feed and shared views show no reminder UI.

**DESIGN.md amendment** (same branch): card footer anatomy becomes "date ·
reminder chip · location pin (left) / overflow (right)"; the "Due" pill is
added to the corner-badge list. Chips-row grammar is untouched.

## iOS

**Model:** `Item` gains `remindAt`, `reminderClearedAt` (`listColumns` and
`detailColumns` updated to match web). `ItemPatch` gains both fields.
`ReminderState` enum + `Item.reminderState(now:)` in StashKit, mirroring the
web logic; `swift test` covers the boundaries.

**Share extension (`ShareComposeView`):** inside `pinnedSaveBar`, above the
Save button: a row "Remind me" + three chips `1 day · 3 days · 5 days`
(`share.remind.1d/3d/5d`). Tap selects, tap again deselects, nothing
selected by default, Save is never blocked. The chosen preset becomes an
absolute `remind_at` at submit time and travels with the unit through
`ShareIntake` → `CaptureAPI` (new parameter) and, on the offline path,
through the outbox payload key `remind_at` which `Outbox.drain` forwards. Done
copy when a reminder was chosen: "Saved · back in 3 days" (queued: "Saved —
will sync · back in 3 days"). Hidden when `canAddContent` is false, like the
rest of the bar.

**View tab:**
- `ReminderStore` (StashKit, `@MainActor @Observable`): `dueItems`,
  `dueCount`, `refresh()` (the due-items query above), `dismiss(id)` and
  `set(id, remindAt)` via `SupabaseItemPatcher`. Owned by `MainTabView` as
  `@State`, injected with `.environment`, so the badge exists before the tab
  is ever opened.
- Badge: `.badge(reminders.dueCount)` on the View tab; SwiftUI hides it at
  zero.
- Refresh triggers: `MainTabView.task`, `scenePhase == .active`, a 60 s tick,
  and a realtime subscription. `RealtimeObserver.observeItems` gains an
  optional channel-name suffix so `MainTabView` can hold its own channel
  alongside `LibraryView`'s.
- Ordering in `LibraryView`: `reminders.dueItems` (already `remind_at` asc)
  followed by `store.items` minus those ids. The local search filter applies
  to the combined list. Keyset pagination on `created_at` is untouched.
- `ItemCardView`: footer reminder chip (same two states as web) and, when
  due, a "Due" overlay at `.topTrailing` using the `stickyBadge` precedent.
  The `×` on a due chip calls `reminders.dismiss`; because the card is itself
  a `Button`, the chip uses its own `Button` with `.buttonStyle(.plain)` and
  a raised hit area so the tap does not open the card.

## Cross-platform consistency

- All three surfaces compute state from `remind_at` + `reminder_cleared_at`
  with the same 24h constant; nothing reads `reminder_notified_at` except the
  job.
- Dismiss is one statement everywhere; set/re-set is one statement everywhere.
- One `docs/ui-changes.md` entry, contracts first, covering the columns, the
  derived-state table, the capture parameter, the ordering rule, the badge
  rule, and the email cadence.
- The 2026-08-28 spec gets a short note under Workstream B pointing here for
  the storage and share-sheet decisions it supersedes.

## Testing

- **vitest:** `reminders.ts` (state boundaries at `remind_at`, `+24h`, cleared
  wins, ordering with mixed lists and search-rank bypass); `reminderDigest`
  renderer (subject pluralisation, title fallbacks, link format, unsubscribe
  URL present); capture validator (bad/absent/past `remind_at` ignored).
- **Deno/edge:** `reminder-digest` with `dry_run` against a seeded test user
  (`will+uitest`), asserting hygiene back-fill and the selected item set;
  idempotency (second run selects nothing).
- **Swift:** `ReminderState`, due-first merge, outbox payload round-trip,
  `Item` decoding with and without the new columns.
- **UI:** XCUITest for the share sheet chips (select, deselect, saved copy);
  Playwright pass on web using the existing QA recipe (set via menu, card
  shows chip, dismiss clears it, due item sorts to top after backdating
  `remind_at` in SQL).

## Prerequisites Will owns

- **Email provider:** a Resend account, `gostash.it` sender domain verified
  (DNS records), `RESEND_API_KEY` set as an edge-function secret. Until then
  deliverable 4 cannot send; everything else ships.
- **Vault secret** `cron_secret` and edge secrets `CRON_SECRET`,
  `EMAIL_LINK_SECRET` (one-time; runbook in the plan).
- `pg_cron` 1.6, `pg_net` 0.14 and `supabase_vault` are already enabled on
  the project (checked 2026-09-06 via the management API). Vault holds no
  secrets yet. The existing `retry-pending-scrapes` job embeds its bearer
  token in the cron command itself; the new job reads from Vault instead.

## Out of scope (recorded so they are not lost)

- Inferred resurfacing, Keep / Done / Let go, "Someday" (Workstream A).
- Push notifications, app-icon badge.
- Reminder controls in the in-app iOS composer, the iOS card menu, the Chrome
  extension, and the web capture box.
- Custom dates, per-user timezone for the digest, digest content beyond due
  reminders.
- Exposing reminders through MCP tools.
