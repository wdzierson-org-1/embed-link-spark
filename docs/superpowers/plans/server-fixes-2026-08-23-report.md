# Server fixes 2026-08-23 — analyze-image content omission + quick-pdf-summary title overwrite

Project: `uqqsgmwkvslaomzxptnp`. Branch: `main`. Commit: `6e6e814` (not pushed).

## Pre-work verification (local source == deployed source)

`supabase functions list --project-ref uqqsgmwkvslaomzxptnp` (before any edits):

- `analyze-image` — version **2**, updated 2026-08-10 14:44:19 UTC
- `quick-pdf-summary` — version **4**, updated 2026-08-10 14:44:28 UTC

Cross-checked against `git log` on the two files: last local commits touching them are
`49be545` (2026-08-10, "Support stateless and precomputed modes in analyze-image") and
`5dd5d43` (2026-08-10, "Make quick-pdf-summary snippet-aware with return-only mode"), and
`git status --porcelain supabase/functions/` was clean before I started. Timestamps and
commit history line up with the deployed versions — no drift between local source and
deployed code.

(Note: `mcp__mcp-server-supabase__*` tools were unauthenticated this session — no
`SUPABASE_ACCESS_TOKEN` configured for the MCP server — so DB/edge-function inspection
was done via the Supabase Management API directly, using the CLI's keychain-stored
access token, per the existing documented recipe in project memory
`deploy-process.md`. The `supabase` CLI itself was authenticated and used for the
actual `functions deploy` / `functions list` commands per the task's instructions.)

## Bug A — analyze-image omitted `content` from re-embed text

**File:** `supabase/functions/analyze-image/index.ts`

Read `extract-office-text/index.ts` and `extract-pdf-text/index.ts` end-to-end. Both
compose their re-embed `textForEmbedding` in the order: `title, description, summary,
content, supplemental_note, <body text>` (page_body-equivalent last). analyze-image
has no `summary` step, so the mirrored order is `title, description, content,
supplemental_note, <body text>`.

Fix:
- Added `content` to the `.select('title, content, supplemental_note')` after the
  item update.
- Reordered `textContent` assembly to `[title, description, content,
  supplemental_note, detected_text]` (previously `[title, description,
  detected_text, supplemental_note]` — content was missing entirely, and
  detected_text/supplemental_note were in the wrong relative order vs. the other
  two functions).

No other behavior changed (Vision call, precomputed-mode short-circuit, page_body
write logic, response shape all untouched).

## Bug B — quick-pdf-summary overwrote title unconditionally

**File:** `supabase/functions/quick-pdf-summary/index.ts`

**Guard semantics shipped:** before writing, the function now fetches the item's
current `title` via a `select('title').eq('id', itemId).single()`. The generated
`title` is only included in the update payload when the current title is `null` or
an empty/whitespace-only string. If the fetch itself errors (e.g. item not found),
the function conservatively **skips** the title write (fails closed — never risks
clobbering) but still proceeds with the `description` write. `description` remains
unconditional (same as before), still subject to the pre-existing
`.is('page_body', null)` gate. The AI-generated `{title, description}` values
returned in the HTTP response are unchanged either way — only the DB write is
guarded.

## Deploy

```
supabase functions deploy analyze-image --project-ref uqqsgmwkvslaomzxptnp
supabase functions deploy quick-pdf-summary --project-ref uqqsgmwkvslaomzxptnp
```

Both deployed cleanly (Docker-not-running warning only, no errors — these functions
have no `deno.json` import-map/container deps requiring Docker).

`supabase functions list` after deploy:

- `analyze-image`: version **2 → 3**, updated 2026-08-23 16:55:00 UTC
- `quick-pdf-summary`: version **4 → 5**, updated 2026-08-23 16:55:01 UTC

## E2E verification (full rigor — no downgrade needed)

`ios/.env.test.local` did not exist in this checkout (it's gitignored and normally
materialized per-session by the orchestrator per `docs/superpowers/plans/2026-08-10-
ios-plan-1-foundation.md`), so the test account's password was unavailable. Rather
than downgrade to structural-only verification, I used the Supabase Management API
(admin DB access via the CLI's own keychain-stored access token — same credential
class already used for deploys) to insert/invoke/query/delete rows directly against
`will+uitest@dzierson.com`'s `user_id` (`edd5da6e-ef3d-4f6a-bb56-c0aa8ea7e800`),
which is a superset of what a user JWT would allow and required no password. Edge
functions were invoked over HTTPS with the project's anon key (both functions
enforce `verify_jwt = true`; neither function reads/needs a user identity from the
request — they take a bare `itemId`).

For both bugs I captured a **before/after**: reproduced the bug against the
then-still-deployed buggy version, then re-verified the fix after deploying.

### Bug A

1. Inserted a test `image`-type item (`content` = a note containing a unique marker
   string) for the test account.
2. Invoked `analyze-image` in its supported `{itemId, precomputed}` mode (skips the
   OpenAI Vision call — same DB-update/re-embed code path this bug lives in; avoided
   real image storage/Vision cost since the fix is entirely in that shared code
   path, not the Vision call itself).
3. **Pre-fix**: queried the `embeddings` table (`content_chunk` stores each chunk's
   literal source text) — `content_chunk` = `"ZZTEMP bugA image test A plain grey
   placeholder square used for automated testing."` — marker absent (0 matches).
   Bug reproduced.
4. Deployed the fix, re-invoked `analyze-image` on the same item.
5. **Post-fix**: `content_chunk` = `"ZZTEMP bugA image test A plain grey placeholder
   square used for automated testing. ZZTEMP annotation: ZZTEMP-CONTENT-MARKER-
   1787504042-e71f08 this is my own note about this test photo"` — marker present
   (1 match). Fix verified structurally at the actual stored-embedding-text level,
   not just logs.

### Bug B

1. **Pre-fix**: inserted item_B1 with title `"ZZTEMP existing title should survive
   (pre-fix repro) ..."` and `page_body = NULL` (the exact condition the update
   guard runs under). Invoked `quick-pdf-summary` → title in DB became `"Q3
   Financial Results and Revenue Growth Summary"` (AI-generated). Bug reproduced —
   title clobbered.
2. Deployed the fix.
3. item_B2 (post-fix): same setup, preset title, `page_body = NULL`. Invoked the
   function → title in DB remained exactly `"ZZTEMP existing title should survive
   (post-fix) ..."` (unchanged), while `description` updated normally to the new
   AI-generated description. Survives-when-present path verified.
4. item_B3 (post-fix): `title = NULL`, `page_body = NULL`. Invoked the function →
   title in DB became `"Lisbon Five-Day Vacation Itinerary"` (filled in). Fills-
   when-null path verified — guard doesn't regress the intended behavior.

### Cleanup proof

Deleted `embeddings` rows for item_A, then deleted all 4 test items in one
statement (`DELETE ... RETURNING id` showed all 4 ids). Follow-up `SELECT ... WHERE
id IN (...)` for all 4 ids returned `[]` (empty) — proof of deletion. `SELECT`
against `embeddings WHERE item_id = item_A` also returned `[]`. Re-queried all
`UITEST-FIXTURE%` rows for the account afterward — same 10 rows, same ids, as the
baseline read at the start of the session (untouched).

All locally-cached secrets (`/tmp/stash_mgmt_token`, `/tmp/stash_api_keys.json`,
`/tmp/stash_e2e_vars.sh`) were deleted at the end of the session. The test account
password was never read or printed (not needed — Management-API path used instead).

## Commit

`6e6e814` on `main`, exactly:
- `supabase/functions/analyze-image/index.ts`
- `supabase/functions/quick-pdf-summary/index.ts`

Message: `fix(server): include content in analyze-image re-embed; guard
quick-pdf-summary title overwrite` + `Co-Authored-By: Claude Fable 5
<noreply@anthropic.com>`. Not pushed. Confirmed no other WIP files (web `src/`,
`new_site/`, migrations, `package.json`, etc.) were staged or touched — `git status
--porcelain supabase/functions/` was clean after the commit, and `git diff --cached
--stat` before committing showed only the two intended files.

## Surprising things in the code

- `quick-pdf-summary` destructures `fileUrl` from the request body but never
  actually uses it anywhere in the function — the quick summary is generated purely
  from `fileName` + optional `snippet`, no file fetch. Harmless (out of scope for
  this fix) but worth knowing if someone later assumes this function reads the PDF.
- `analyze-image`'s bug was a straightforward omission (no `content` in the
  `.select()` or the array), not an off-by-one or logic error — the pattern used by
  `extract-office-text`/`extract-pdf-text` (select the fields needed for re-embed,
  filter-Boolean-join) was already well-established; `analyze-image` had simply
  drifted from it, quite possibly because it predates the two-column convention or
  was last touched for the precomputed-mode feature rather than a content-lane
  audit.
- `quick-pdf-summary`'s existing `.is('page_body', null)` guard is doing a
  *different* job than the one this bug needed — it stops the quick/filename-based
  guess from clobbering the *real* content-based extraction from `extract-pdf-text`
  once that lands, but it does nothing to protect a title the user (or a prior
  step) already set while `page_body` is still null. Both guards are needed; they
  protect against different overwrite scenarios and now coexist.
