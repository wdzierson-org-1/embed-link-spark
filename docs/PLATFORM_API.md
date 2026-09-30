# Stash platform API

The contract for every Stash client — web app, chat mole, menubar widget,
browser extension, iOS. All capture and retrieval intelligence lives server-side
in Supabase edge functions; clients stay thin and platform-independent.

Base URL: `https://uqqsgmwkvslaomzxptnp.supabase.co/functions/v1`

## Auth

Every request sends two headers:

```
Authorization: Bearer <user JWT (session access_token)>
apikey: <anon key>
```

Get a JWT with supabase-js (`auth.signInWithPassword` / OAuth) on any platform,
or the raw REST endpoint `POST /auth/v1/token?grant_type=password`. The item
owner is always derived from the JWT server-side — never sent by the client.

## Capture

Every capture endpoint (`add-url`, `add-note`, `add-file`) accepts an optional
`attributes` object in the request body — structured facts about the item
(location, link metadata, media info; shapes defined in
`src/types/itemAttributes.ts`) that aren't its content. It's stored whole-blob
on `items.attributes` (jsonb): omit it, send `{}`, or send anything that
isn't a plain object (e.g. an array) and it's treated as `{}` — never a 500.
`add-url` additionally guarantees `attributes.link.flavor` on every saved
link: a caller-supplied flavor wins, otherwise the server classifies one from
the URL alone (`article` / `video` / `repo` / `book` / `social` / `generic`).

Every capture endpoint also accepts an optional top-level `remind_at`
(ISO-8601 timestamp): "bring this back to me then". It must parse and be no
older than one hour before now; anything else is ignored — the item still
saves with `remind_at: null` and a warning is logged. Never a 4xx. The
returned item includes `remind_at`, `reminder_cleared_at`,
`reminder_notified_at`. See **Reminders** below.

### `POST /add-url` — save a link

```json
{ "url": "https://…", "content": "optional note about it", "is_public": false }
```

Returns `{ success, item }` fast (title/description from a quick fetch).
Everything else continues server-side after the response: deep metadata with
the blocked-site rescue cascade (crawler UA → Jina Reader → Wayback → URL
inference), preview image storage, full-page scrape into `page_body`, and
embeddings. Clients never wait on enrichment — realtime (below) delivers the
upgrades.

`tags: …` at the end of `content` becomes item tags.

### `POST /add-note` — save a text note

```json
{ "content": "the note", "title": "optional", "is_public": false }
```

Returns `{ success, note }` immediately with a derived title; AI title +
description + re-embed land asynchronously.

### `POST /add-file` — save an uploaded file

Upload to Storage first (`stash-media/<userId>/<name>.<ext>`), then:

```json
{ "file_path": "<userId>/…", "mime_type": "image/png", "file_size": 1234,
  "content": "optional note", "title": "optional", "is_public": false }
```

Returns `{ success, item }` fast. Type derives from MIME (image/audio/video,
else document). Enrichment continues server-side after the response: vision
description + OCR for images, Whisper transcript into `page_body` for
audio/video, embeddings for all. Documents branch by exact MIME: `application/
pdf` gets quick summary + full text extraction into `page_body`; Office Open
XML (`.pptx`/`.docx`/`.xlsx`) gets text extraction via the same page_body/
summary/description contract; anything else settles immediately with an AI
description (`summary` mirrors `description` — no `page_body`). Realtime
delivers the upgrades. `file_path` must sit inside the caller's own folder
(403 otherwise).

### `POST /capture` — idempotent capture (iOS)

One entry point that wraps the three endpoints above and makes every capture
safe to retry. The client generates a `capture_id` (UUID) once per capture and
sends the same id on every attempt, from any process, at any time; the server
never creates a second item for it. **iOS routes every capture through
`capture`** (its Outbox entry id is the `capture_id`, so foreground sends,
background transfers and later drains can all retry blindly). **Web, the
browser extension and macOS still call `add-*` directly** — those endpoints are
unchanged, and `capture` forwards to them with the caller's own JWT, so
enrichment, paywall and every other server behavior are identical.

Standard auth headers. The body is either `application/json` (the meta object)
or `multipart/form-data` with a `meta` part (the JSON string) and a `file` part
(the bytes). Meta:

```json
{ "capture_id": "1b9d6bcd-bbfd-4b2d-9b5d-ab8dfbbd4bed", "kind": "note | url | file",
  "content": "optional", "title": "optional (note/file; ignored for url)",
  "url": "required for url", "is_public": false,
  "attributes": { }, "remind_at": "ISO-8601",
  "mime_type": "required for file", "file_name": "IMG_0042.jpg", "file_size": 1234,
  "file_path": "<uid>/… — file kind without a file part only" }
```

- `capture_id` is required and must be a UUID. Case doesn't matter (it's
  normalized to lowercase), but always send the same id.
- `note` needs non-blank `content`. `url` needs a parseable `url`. `file`
  needs `mime_type` plus exactly one of a multipart `file` part or a
  `file_path` inside the caller's own folder (`<uid>/…`, no empty/`..` segments).
- `attributes` and `remind_at` are forwarded as-is and follow the `add-*`
  rules above. A non-object `attributes`, a non-string `remind_at`, or a bad
  `file_size` is dropped with a logged warning. Metadata never causes a 4xx, and
  `attributes: {}` is never forwarded.
- Forwarded bodies: url → `{url, content?, is_public, attributes?, remind_at?}`;
  note → `{content, title?, is_public, attributes?, remind_at?}`; file →
  `{file_path, mime_type, file_size?, content?, title?, is_public, attributes?, remind_at?}`.
  `file_name` only picks the storage extension. The server doesn't turn it into a
  title, so keep the original name in `attributes.media.file_name`.
- The meta is capped at **1 MiB**: the whole body of a JSON request, or the
  `meta` part of a multipart one. Anything larger gets
  `413 { "error": "meta_too_large", "max_bytes": 1048576 }`. That means the
  request itself is too big (usually an enormous note), so don't switch to two-step.

**Files: one-shot or two-step.** A file of up to **45 MiB (47,185,920 bytes)**
goes in ONE multipart request. The server stores it at
`stash-media/<uid>/<capture_id>.<ext>` (upsert, so a retry overwrites instead of
piling up), with the object's content type set to `mime_type` whatever the
part header says. `<ext>` comes from `file_name`'s extension, else from a MIME
map, else `bin`. The server then calls `add-file`, and `file_size` defaults to
the uploaded byte count. Put `meta` first. The `file` part **must** carry a
`filename` in its `Content-Disposition` (any name), because a part without one
is read as text and refused with 400. A multipart request whose
`Content-Length` exceeds 46 MiB (the file limit plus 1 MiB for `meta` and
boundaries) gets `413` without being parsed. Larger files use **two steps**:
upload to Storage yourself at the same deterministic path
(`POST /storage/v1/object/stash-media/<uid>/<capture_id>.<ext>` with
`x-upsert: true`), then send JSON meta with that `file_path`. Measured
2026-09-27: 45 MiB one-shot → 200 in ~16 s end-to-end on a ~24 Mbps uplink
(~2.7 s in-function). The gateway buffers the whole request before the function
runs, and Supabase caps edge-function requests at 150 s, so on a slow uplink a
large file is safer in two steps.

**Idempotency** (`capture_receipts`, one row per user + `capture_id`, owner RLS):

| receipt state when a request arrives | result |
|---|---|
| none | reserve (`pending`), capture, then mark `done` with the item id |
| `done` | `200 { item, duplicate: true }`. `item` is the row as it is now (`select *`), or `null` if the user deleted it. Nothing new is created |
| `pending`, touched < 120 s ago | `409 { "error": "capture_in_progress" }`. A live attempt owns it and re-stamps it every 30 s while it waits on `add-*` |
| `pending`, untouched ≥ 120 s | that attempt stalled, so this one takes it over (compare-and-set, under a fresh `attempt_id`) and proceeds |

**Fencing.** Every reservation and takeover stamps the receipt with a fresh
`attempt_id`. That attempt's later receipt writes (heartbeat, done, release)
are filtered by it. If a stalled attempt resumes after being taken over, its
writes match nothing, so it can't overwrite or delete its successor's receipt.
If it finishes anyway, the item it created is a duplicate: it deletes that item
(as the user) and answers `409 capture_in_progress`. The client's next retry
then gets the successor's result.

If the downstream call (or the multipart Storage upload) fails, the attempt
deletes its own receipt (with bounded retry), so a retry starts fresh. When
`add-*` answers non-2xx, the server also removes the one-shot object it
uploaded. It does that only after proving it still owns the receipt, because
the path is shared with any successor. A two-step object is the client's and
stays put. The first response's `item` is exactly what `add-*` returned
(normalized from `item` / `note`; `add-url` adds `metadata` + `previewImagePath`).
A duplicate's `item` is the plain row.

| status | body | meaning / client action |
|---|---|---|
| 200 | `{ "item": {…}, "duplicate": false }` | created now |
| 200 | `{ "item": {…} \| null, "duplicate": true }` | already captured. Treat as success |
| 400 | `{ "error": "invalid_request", "message": "…" }` | bad Content-Type, JSON, multipart, or meta. Don't retry unchanged |
| 401 | gateway `{ "code": "UNAUTHORIZED_…", "message" }` or `{ "error": "Invalid or expired token" }` | refresh the session, then retry |
| 403 | `{ "error": "Agent tokens are only accepted by the MCP endpoint" }` | agent (MCP) token |
| 405 | `{ "error": "Method not allowed" }` | POST only |
| 409 | `{ "error": "capture_in_progress" }` | another attempt with this id is live, or this one was superseded and removed its duplicate. Retry later. Not a failure (don't count an attempt) |
| 413 | `{ "error": "file_too_large", "max_bytes": 47185920 }` | switch to two-step |
| 413 | `{ "error": "meta_too_large", "max_bytes": 1048576 }` | the meta itself is too big. Don't retry unchanged |
| 500 | `{ "error": "receipt_failed", "message" }` · `{ "error": "Internal server error" }` | transient, retry |
| 502 | `{ "error": "storage_upload_failed" \| "downstream_unreachable", "message" }` | transient, retry |
| any other | the `add-*` endpoint's status and body, **verbatim** | e.g. a lapsed account: `403 {"error":"subscription_required","message":"…","status":"paused"}` from `add-note` (and from `add-url`/`add-file` since 2026-09-29, below) |

Known gateway quirk (measured 2026-09-27): `add-note` returns its
`subscription_required` 403 before reading the request body. For bodies larger
than about 0.5 MiB, Supabase's gateway then holds the request for ~160 s and
answers `504` instead of the 403. Up to 512 KiB answered promptly; 900 KiB and
1 MiB stalled. This hits direct `add-note` callers too, and the fix belongs in
`add-note`. Through `capture`, only a lapsed account's very large note sees it,
as a 504 (transient).

**Paywall on every capture kind (production since the 2026-09-29 redeploy).**
`add-url` and `add-file` now refuse a lapsed account exactly like `add-note`:
`403 {"error":"subscription_required","message":"…","status":"<stripe status>"}`
(one shared server gate; a blocking Stripe status — `past_due`, `unpaid`,
`canceled`, `incomplete`, `incomplete_expired`, `paused` — is refused, anything
else passes). `capture` forwards it verbatim, so a lapsed account gets that 403
for notes, links and files alike; iOS parks the Outbox entry until the
entitlement returns. `chat-with-all-content` (see Ask) refuses a lapsed account
with the same 403 before streaming. Before 2026-09-29 only `add-note` did.

## Ask

### `POST /chat-with-all-content` — streaming Q&A over the user's stash

```json
{ "message": "…", "conversationHistory": [{ "role": "user"|"assistant", "content": "…" }] }
```

Responds with Server-Sent Events:

```
data: {"delta":"token"}          ← repeatedly
data: {"status":"searching","query":"…"}   ← optional, while a tool runs
data: {"status":"browsing"}                ← optional (2026-08-30: catalog scan)
data: {"status":"reading"}                 ← optional
data: {"done":true,"sources":[{"id","title","type","url","n"}]}
```

Retrieval is **agentic**: the model drives search itself through internal
tools (`search_stash` — hybrid pgvector + full-text, RRF-fused, with
type/date/tag filters; `get_item` — full notes/summary/captured text), so it
rewrites queries from conversation context, searches more than once for
multi-part questions, and reads items in full before quoting them. `status`
frames are informational — clients may render a "searching…" indicator or
ignore unknown keys entirely (every frame is valid JSON). Sources are the
items the answer cites (fallback: items it read in full). History is capped
server-side at 10 turns.

Citations in the answer text: item titles appear as markdown links targeting
their citation number (`[Title](#3)`), bare `[3]` markers otherwise. Each
sources entry carries that number as `n` — at stream end, clients rewrite
`(#n)` targets into durable item links (`(#item=<uuid>)`), persist the baked
text, and render those links as open-this-card actions. Show a bottom sources
row only for entries not already linked inline (reference:
`src/utils/chatCitations.ts`).

Sessions: conversations are time-gap sessions — a client convention. Pick the
user's latest conversation by `last_message_at`; continue it if the last
message is under 3 hours old, otherwise insert a new `conversations` row
(title null; auto-title it from the first question via `generate-title`).
Send only the current session's messages as `conversationHistory`. A DB
trigger maintains `last_message_at`; `list_conversations()` (SECURITY
INVOKER, RLS-scoped) returns the history list with counts and previews.

### `POST /search-items` — direct search (no LLM answer)

```json
{ "query": "…", "types": ["link"], "tags": ["…"], "after": "ISO", "before": "ISO", "limit": 20 }
```

All fields optional. With `query`: hybrid relevance-ranked search (one result
per item, `snippet` = best matching chunk). Without: newest-first listing
under the same filters. Returns
`{ "results": [{ id, title, type, url, created_at, description, snippet, score }] }`.
This is the canonical search surface — library search boxes, future MCP
tools, and Siri/Shortcuts should all call it rather than hitting the DB.

## Agents (MCP)

Remote MCP server (Streamable HTTP, JSON responses, stateless):
`https://www.gostash.it/mcp` (a Vercel rewrite to the `mcp` edge function).
Read-only. Spec: `docs/superpowers/specs/2026-09-05-mcp-server-design.md`.

**Auth** is OAuth 2.1 through Supabase Auth's OAuth server — not the session
JWT used everywhere else. Unauthenticated requests get
`401` + `WWW-Authenticate: Bearer resource_metadata="https://www.gostash.it/mcp/.well-known/oauth-protected-resource", scope="email"`;
clients discover the authorization server
(`https://uqqsgmwkvslaomzxptnp.supabase.co/auth/v1`), register dynamically,
and send the user to `https://www.gostash.it/oauth/consent` to approve. The
consent page records an `agent_grants` row; the server refuses tokens whose
client has no active row. Session JWTs are refused on `/mcp`; agent tokens
(JWTs carrying a `client_id` claim) are refused on every other endpoint and
get zero rows through PostgREST/Storage (restrictive RLS) — agents receive
answers, never copies.

**Tools** (all read-only, annotated `readOnlyHint: true`): `search_stash`
(same request/response shape as `POST /search-items`, plus a readable text
rendering) and `get_item` (`{ id }` → notes, description, summary, captured
text capped at 12k chars, `attributes.link.flavor`,
`attributes.location.label`); plus ChatGPT's required `search`
(`{ query }` → `{ results: [{ id, title, url }] }`) and `fetch`
(`{ id }` → `{ id, title, text, url, metadata }`) — aliases over the same code,
returned as `structuredContent` and as a JSON string in the text item. Every
call is logged to `agent_access_log` (Settings → Connected agents → Activity)
and rate-limited per grant (60/min, 2,000/day → `isError` result).

**Discovery:** protected-resource metadata at
`/.well-known/oauth-protected-resource[/mcp]` and a server card at
`/.well-known/mcp-server-card` (site root, static) and under
`/mcp/.well-known/…` (function). Registry entry: `mcp/server.json`
(`it.gostash/stash`). Directory runbook: `docs/mcp/DIRECTORIES.md`.
Protocol versions: `2025-11-25`, `2025-06-18`, `2025-03-26`, `2024-11-05`.

**Client contracts** (any surface adding a "Connected agents" screen):
active grants = `agent_grants` where `revoked_at is null` (owner RLS);
activity = last 50 `agent_access_log` rows, rendered per
`src/utils/agentActivity.ts`; revoke = `DELETE /auth/v1/user/oauth/grants?client_id=…`
(session JWT) **then** set `agent_grants.revoked_at`. Item deep link:
`https://www.gostash.it/home#item=<uuid>` opens that card in the web library.

## Account deletion

`POST /functions/v1/delete-account` — no body. Standard auth headers; the
target account is always the JWT's owner, and agent (MCP) tokens are refused
with `403`. Irreversible, so clients gate it behind an explicit
type-to-confirm step (web: type `DELETE`).

Server order, chosen so that a failure part-way leaves the account intact
and the call can simply be retried:

1. Stripe — every live subscription on the customer(s) with the user's email
   is canceled (customer record kept for invoice history, tagged
   `stash_account_deleted_at`).
2. Storage — every object under `stash-media/<user_id>/` is removed.
3. `auth.admin.deleteUser` — DB cascades take items, embeddings, tags,
   conversations, messages, phone number, profile, agent grants, feedback,
   logs and all `auth.*` rows (migration `20260907120000`).

```
200 { "deleted": true, "storageObjects": 42, "stripe": { "customers": 1, "canceled": 1 } }
401 { "error": "Invalid or expired token" }
403 { "error": "Agent tokens cannot delete an account" }
500 { "deleted": false, "error": "<step>: <reason>" }   ← nothing irreversible happened
```

After `200` the JWT is dead server-side: clients drop the local session
(`signOut({ scope: 'local' })` / clear the keychain) and return to sign-in.

## Delete contract

PostgREST's `DELETE` (the underlying call behind `supabase-swift`'s
`.delete()`, and equivalent in every `postgrest-js`-based client) matching
**zero rows** — a stale/already-deleted id, or an id RLS silently excludes —
still returns a `2xx` status. Under `Prefer: return=representation`
(supabase-swift's default for `.delete()`), the body is an empty JSON array
`[]`, not an error. A client that only checks the HTTP status treats this
identically to a real delete of one row — the failure is invisible. Clients
**must** inspect the response body: zero elements means nothing was actually
removed. iOS decodes the returned array and throws
`ItemEditorError.deleteMatchedNoRows` when it's empty, which the UI surfaces
as "Couldn't delete this item — it may not exist anymore or you may not have
permission." (`ios/StashKit/Sources/StashKit/ItemEditor.swift`,
`ios/Stash/Detail/ItemDetailView.swift`). Any other client implementing
delete should apply the same check.

## Message routing convention — RETIRED 2026-08-27

Chat composers are retrieval-only on every platform: all input goes to
`chat-with-all-content`. The old convention (URL → `add-url`,
`remember:`/`save:`/`note:` → `add-note`) is retired; capture belongs to
capture surfaces (input panel, share sheets, extension, SMS). Web has removed
`moleRouting.ts`; iOS should remove `StashKit/MessageRouting.swift` usage from
its Ask composer to match. Do not build new clients on message routing.

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
`x-cron-secret` header). Step 1 (expire stale reminders) is live. Step 2 —
one email per user per day listing their due, un-notified reminders (never
one per reminder), then stamping `reminder_notified_at` — is specified but
not yet built: it ships with plan 3 and is currently skipped.

## Live updates

Subscribe to Postgres changes to reflect async enrichment without polling:

```js
supabase.channel(`items-${userId}`)
  .on('postgres_changes',
      { event: '*', schema: 'public', table: 'items', filter: `user_id=eq.${userId}` },
      handler)
  .subscribe()
```

## Other channels

- WhatsApp/SMS: Twilio webhook (`/twilio-webhook`, Twilio-signature-verified);
  registration via `user_phone_numbers`.
- Public feeds: `GET /get-public-feed/<username>`, `GET /get-discover-feed`
  (anon key works for both).

## Notes for future clients

- Menubar widget / extension: `add-url` + `add-note` are sufficient for v1
  capture; JWT can be obtained via a one-time device sign-in with supabase-js.
- Voice: the web app uses the Web Speech API client-side and sends the final
  transcript through the normal chat routing; `/transcribe-audio`
  (Whisper) exists for platforms without native speech recognition.
