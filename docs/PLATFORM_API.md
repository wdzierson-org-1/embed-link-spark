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
