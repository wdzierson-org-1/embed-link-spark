# Stash MCP server — design

**Date:** 2026-09-05 · **Status:** approved by Will 2026-09-05 (with the added
requirement: broadest client compatibility and directory discoverability —
see "Compatibility & discoverability") ·
**Implements:** Workstream C (MCP server) + Workstream D minimal (grants, audit,
revocation, the "answers not copies" fence) from
`docs/superpowers/specs/2026-08-28-retention-loop-and-context-layer-spec.md`.
Plan: `docs/superpowers/plans/2026-09-05-mcp-server.md`.

## Goal

Any agent the user trusts — Claude (web, desktop, mobile, Claude Code),
ChatGPT, Cursor, anything that speaks remote MCP with OAuth — can search the
user's stash and read saved items, with the user's explicit consent, a scope
record, a human-readable activity log, and one-tap revocation. Read-only. The
server owns no new intelligence: it is a thin wrapper over the retrieval
stack that already exists (`search-items`, the item read the Ask agent does).

What users see: **Settings → Connected agents** shows one URL
(`https://www.gostash.it/mcp`), how to paste it into Claude, the agents that
are connected, and what each one did. Connecting an agent lands on a consent
page (`/oauth/consent`) that says exactly what the agent can and cannot do.

## Decisions (approve or override)

1. **OAuth 2.1 via Supabase Auth's OAuth server, no personal tokens.**
   Claude's hosted surfaces only support OAuth with dynamic client
   registration (static bearer headers are an org-admin beta feature), so OAuth
   is the only way this works in claude.ai / Claude Desktop / mobile. Supabase
   Auth ships an OAuth 2.1 server built for exactly this: discovery endpoints,
   dynamic client registration, PKCE, refresh rotation, a consent-page API,
   per-client grants, and revocation that kills the client's sessions and
   refresh tokens. We enable it (currently disabled on the project) and build
   nothing of that ourselves. It is beta on Supabase's side.
2. **Branded endpoint `https://www.gostash.it/mcp`** via a Vercel external
   rewrite to the `mcp` edge function. Task 1 of the plan verifies the rewrite
   proxies POST bodies and `Authorization` headers; if it doesn't, the raw
   Supabase function URL becomes the endpoint (one constant changes). The
   protected-resource metadata `resource` field must equal whatever URL users
   paste, so the constant lives in one place.
3. **Read-only v1: two tools, `search_stash` and `get_item`.** Capture over
   MCP (`save_to_stash`) is v1.1 and must reuse the canonical capture path
   (C3); it is not in this spec.
4. **The "no copies" fence ships with v1.** A Supabase OAuth access token is a
   full user JWT: without a fence, an agent token could read the whole `items`
   table through PostgREST or call every edge function. D says copies are
   unsupported *by architecture*, so v1 adds (a) restrictive RLS policies that
   deny agent tokens on every user-data table and on storage, and (b) an
   edge-function guard that rejects agent tokens everywhere except the MCP
   endpoint. An agent token can therefore reach exactly one door, and that
   door returns answers.
5. **Scope vocabulary is `read` only,** stored in our own grants table
   (Supabase only supports the standard `openid/email/profile/phone` scopes
   today, no custom scopes). The column is `text[]` so `write` and topic
   scopes can be added without a migration of shape.
6. **Metering:** per-grant rate limits (60 tool calls per minute, 2,000 per
   day) enforced from the access log. Cheap, and it is the "metered answers"
   primitive the monetization posture assumes.
7. **Supabase auth config changes:** `site_url` becomes
   `https://www.gostash.it` (it is `http://localhost:3000` today, a Lovable-era
   leftover; the OAuth consent URL is site URL + authorization path, so this
   must be right), `https://www.gostash.it/**` and `https://gostash.it/**`
   join the redirect allow list, and the OAuth server is enabled with dynamic
   registration on and authorization path `/oauth/consent`. Every web flow
   already passes explicit redirect URLs (`emailRedirectTo`), so the site URL
   change only fixes the fallback.
8. **Hand-rolled MCP protocol core, no SDK.** A stateless tools-only server
   over Streamable HTTP is five JSON-RPC methods; a dependency-free module is
   testable under the existing vitest setup and avoids betting on the
   week-old SDK v2 running under Deno. Revisit if resources/prompts/elicitation
   are ever needed.
9. **Compatibility is a v1 requirement, not a follow-up** (Will, 2026-09-05):
   every tool carries a `title` and read-only annotations (Claude directory
   requirement); ChatGPT's `search`/`fetch` contract is exposed alongside our
   tools; the four protocol versions clients send today are all accepted;
   discovery documents (protected-resource metadata, server card, registry
   `server.json`) are published at the standard paths; and the OAuth setup
   supports pre-registered confidential clients for directories that hold
   credentials. Details in "Compatibility & discoverability".

## Architecture

```
Agent (Claude, Cursor, …)
   │  POST https://www.gostash.it/mcp   (JSON-RPC, Bearer <OAuth access token>)
   ▼
Vercel rewrite  /mcp, /mcp/*  ──►  Supabase edge function `mcp`  (verify_jwt=false)
                                       │  1. bearer → auth.getUser → JWT must carry client_id
                                       │  2. agent_grants(user_id, client_id) active? else 403
                                       │  3. rate limit from agent_access_log
                                       │  4. dispatch tool → _shared/search.ts / items read
                                       │  5. write agent_access_log, bump last_used_at
                                       ▼
                                   Postgres (service role)

OAuth (handled by Supabase Auth, https://uqqsgmwkvslaomzxptnp.supabase.co/auth/v1):
  discovery ─ /.well-known/oauth-authorization-server/auth/v1
  register  ─ dynamic client registration (Claude registers itself)
  authorize ─ redirects the user to https://www.gostash.it/oauth/consent?authorization_id=…
  consent   ─ our React page: sign in if needed → show client + permissions → approve/deny
              (approve also upserts agent_grants) → back to the agent with a code
  token     ─ code + PKCE → access token (1h) + refresh token
```

Unauthenticated requests to `/mcp` get `401` with
`WWW-Authenticate: Bearer resource_metadata="https://www.gostash.it/mcp/.well-known/oauth-protected-resource", scope="email"`.
That metadata document (served by the function, plus a best-effort static copy
at `/.well-known/oauth-protected-resource/mcp` on Vercel for clients that
probe) is:

```json
{
  "resource": "https://www.gostash.it/mcp",
  "authorization_servers": ["https://uqqsgmwkvslaomzxptnp.supabase.co/auth/v1"],
  "scopes_supported": ["email"],
  "bearer_methods_supported": ["header"],
  "resource_name": "Stash"
}
```

`scope="email"` is pinned deliberately: Supabase's default scope is `email`,
and requesting `openid` would make token issuance fail while the project signs
JWTs with HS256 (ID tokens need asymmetric keys). Migrating signing keys is
out of scope; it is the fallback if a client insists on `openid`.

## The `mcp` edge function

`supabase/functions/mcp/index.ts` (HTTP shell) + `supabase/functions/_shared/`:

- `mcpProtocol.ts` — pure JSON-RPC/MCP core, no imports. Handles
  `initialize` (negotiates `2025-11-25` / `2025-06-18` / `2025-03-26`;
  capabilities `{ tools: {} }`; `serverInfo { name: "stash", version }`;
  short `instructions`), `notifications/*` (→ HTTP 202, empty), `ping`,
  `tools/list`, `tools/call`; single messages and arrays; JSON-RPC errors
  `-32700/-32600/-32601/-32602/-32603`. Tool-level failures (bad input, not
  found, rate limit) are `isError: true` results, not protocol errors.
- `agentAuth.ts` — `authenticateAgent(req)`: bearer → `auth.getUser` →
  decode payload → require `client_id` (plain session tokens are refused, so
  every agent request is attributable) → load the active `agent_grants` row →
  returns `{ user, grant, supabaseAdmin }` or a typed failure that the shell
  maps to `401 + WWW-Authenticate` (no/invalid token) or `403` (no grant /
  revoked; message tells the user to reconnect from Settings).
- `search.ts` — the body of `search-items` extracted as
  `normalizeSearchRequest(body)` + `searchItems(admin, userId, req, deps)`.
  `search-items/index.ts` becomes a shell around it, so the web toolbar, Ask
  fallbacks, and MCP stay one implementation.
- `auth.ts` (existing) — `authenticateUser` additionally rejects agent tokens
  (`isAgentToken(token)` exported for functions that call `getUser` directly).

Routes on the function (path relative to `/mcp`):

| Method · path | Behavior |
|---|---|
| `OPTIONS *` | CORS preflight; allow `authorization, content-type, accept, mcp-protocol-version, mcp-session-id` |
| `GET /.well-known/oauth-protected-resource` | metadata JSON, public, cacheable 1h |
| `POST /` | authenticate → JSON-RPC; responses are `application/json` (no SSE), `Cache-Control: no-store` |
| `GET /`, `DELETE /` | `405` (no server-initiated stream, no sessions) |

Tools:

**`search_stash`** — inputs (all optional): `query` string; `types`
array of `text|link|image|audio|video|document`; `tags` string array;
`after`/`before` ISO timestamps; `limit` 1–50 (default 20). With `query`:
hybrid semantic + keyword search, one hit per item, relevance-ordered. Without:
newest-first listing under the same filters. Output: text block per hit
(`[n] Title (type/flavor · saved YYYY-MM-DD) id:<uuid>` + snippet) plus
`structuredContent: { results: [{ id, title, type, url, created_at,
description, snippet, score }], count }` (the `search-items` shape verbatim).
Empty → "No matches…" guidance text. Description tells the model this is the
user's personal saved material, that type filters are guesses (web videos are
links), and to call `get_item` before quoting.

**`get_item`** — input `id` (uuid, required). Reads the item scoped to the
user; not found → `isError`. Output text sections in this order: title line
(type · saved date), URL, "Saved at" location label, description, user's notes
(HTML stripped, cap 4,000 chars), sticky note, summary, captured text (cap
12,000 chars). `structuredContent` carries the same fields plus
`attributes.link.flavor` and `attributes.location.label` only. Same lanes as
everywhere: `content` = user's words, `description`/`summary` = AI text,
`page_body` = captured source.

Every `tools/call` writes one `agent_access_log` row and bumps
`agent_grants.last_used_at`. Rate limit: count log rows for the grant in the
last 60s (>60 → refuse) and 24h (>2,000 → refuse); refusals are `isError`
results and are not logged.

## Compatibility & discoverability

Goal: any MCP client that speaks remote Streamable HTTP with OAuth connects
without special-casing, and Stash can be listed in the directories that
matter (Claude connectors directory, ChatGPT connectors, the official MCP
Registry, and URL-based catalogs such as Smithery/Glama/PulseMCP).

**Transport.** Streamable HTTP only. Protocol versions accepted and echoed:
`2025-11-25`, `2025-06-18`, `2025-03-26`, `2024-11-05` (anything else →
latest). JSON responses for every POST (all Streamable HTTP clients must
accept JSON or SSE); JSON-RPC batches accepted; `Mcp-Session-Id` never
issued and ignored if sent; `MCP-Protocol-Version` header accepted;
`tools/list` tolerates `cursor`. The deprecated HTTP+SSE transport (`GET /sse`
+ `POST /messages`) is not offered: it needs long-lived streams that don't fit
edge functions, and every current client speaks Streamable HTTP.

**Tool annotations.** Every tool: `title` plus
`annotations: { readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false }`.
The Claude directory groups tools by these hints and rejects tools missing a
title or the read-only/destructive hint.

**ChatGPT contract.** ChatGPT connectors and deep research require two tools
named exactly `search` and `fetch`. Both are exposed as thin aliases over the
same code as `search_stash`/`get_item`, with OpenAI's exact shapes returned
both as `structuredContent` and as a JSON string in the text content item:

- `search({ query: string })` → `{ results: [{ id, title, url }] }`
- `fetch({ id: string })` → `{ id, title, text, url, metadata }` where `text` is
  the same rendering `get_item` produces and `metadata` carries `type`,
  `created_at`, `flavor`, `location`, `description`, `summary`.

`url` must be a non-empty string for ChatGPT to create a citation, so it is
the item's own URL when it has one, otherwise the item's web deep link.
Four tools total; models are told via descriptions that `search`/`fetch` and
`search_stash`/`get_item` are the same capability.

**Discovery documents** (all `application/json`, CORS `*`, cacheable 1h):

| Path | Served by | Content |
|---|---|---|
| `https://www.gostash.it/.well-known/oauth-protected-resource/mcp` | Vercel static | RFC 9728 metadata (path-specific probe) |
| `https://www.gostash.it/.well-known/oauth-protected-resource` | Vercel static | same (root probe) |
| `https://www.gostash.it/mcp/.well-known/oauth-protected-resource` | `mcp` function | same (authoritative; pointed to by the 401) |
| `https://www.gostash.it/.well-known/mcp-server-card` | Vercel static | SEP-2127 server card |
| `https://www.gostash.it/mcp/.well-known/mcp-server-card` | `mcp` function | same |
| `mcp/server.json` (repo) | published with `mcp-publisher` | MCP Registry entry, namespace `it.gostash/stash` |

Server card fields: `$schema` (`https://static.modelcontextprotocol.io/schemas/v1/server-card.schema.json`),
`name: "it.gostash/stash"`, `title: "Stash"`, `description`, `version`,
`websiteUrl`, `icons` (existing `/icon-192.png`, `/icon-512.png`),
`remotes: [{ type: "streamable-http", url, supportedProtocolVersions }]`.
Registry `server.json` uses the `2025-12-11` schema with the same name and
`remotes`. Both documents deliberately omit tool lists (dynamic per spec).

**Directory readiness (Will's actions, runbook in `docs/mcp/DIRECTORIES.md`):**
MCP Registry needs DNS verification of `gostash.it` (`mcp-publisher login
dns`, a TXT record) then `mcp-publisher publish` from `mcp/`. Claude directory
needs a Team/Enterprise org, a privacy policy URL (`https://www.gostash.it/privacy`),
a documentation URL, an icon, a test account, and "reads data only"; auth mode
"OAuth with dynamic client registration". For directories that prefer a fixed
client (Claude's Anthropic-held credentials, admin-supplied client IDs),
Supabase's admin API creates a confidential client
(`POST /auth/v1/admin/oauth/clients` with the service role) — the runbook has
the command. ChatGPT: add as a custom connector (developer mode) with the same
URL; OAuth + DCR is what it requires.

## Data model (one migration)

```sql
create table public.agent_grants (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references auth.users(id) on delete cascade,
  client_id    text not null,                 -- JWT client_id claim (Supabase OAuth client)
  client_name  text not null,
  client_uri   text,
  scopes       text[] not null default '{read}',
  created_at   timestamptz not null default now(),
  last_used_at timestamptz,
  revoked_at   timestamptz,
  unique (user_id, client_id)
);
-- RLS: owner may select/insert/update own rows (the consent page writes the
-- row; Settings revokes it). No delete policy — history stays. Service role
-- (the mcp function) bypasses RLS.

create table public.agent_access_log (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null,
  grant_id     uuid not null references public.agent_grants(id) on delete cascade,
  client_id    text not null,
  tool         text not null,                 -- 'search_stash' | 'get_item'
  query        text,
  filters      jsonb,
  item_id      uuid,
  item_title   text,                          -- snapshot; items get deleted
  result_count int,
  created_at   timestamptz not null default now()
);
-- indexes: (user_id, created_at desc), (grant_id, created_at desc)
-- RLS: owner select only. Writes come from the mcp function (service role).

create function public.is_agent_token() returns boolean
  language sql stable as $$ select coalesce(auth.jwt() ->> 'client_id', '') <> '' $$;

-- The fence: one RESTRICTIVE policy per user-data table (items, embeddings,
-- tags, item_tags, item_attachments, conversations, messages, comments,
-- card_feedback, chat_feedback, sms_conversations, user_follows,
-- user_phone_numbers, user_preferences, user_profiles, agent_grants,
-- agent_access_log) and on storage.objects:
--   as restrictive for all to authenticated
--   using (not public.is_agent_token()) with check (not public.is_agent_token());
```

Restrictive policies AND with the existing permissive ones, so nothing changes
for normal sessions; an agent token gets zero rows everywhere through
PostgREST and Storage. `retrieval_log` (Ask observability) is not written by
MCP calls — the agent log is a separate, user-facing concern.

## Web surfaces

**`/oauth/consent`** (`src/pages/OAuthConsent.tsx`, REST helpers in
`src/utils/oauthConsent.ts`). Our supabase-js (2.50) predates the
`auth.oauth.*` methods and a jump to 2.115 is an unrelated risk, so the page
calls the four GoTrue endpoints directly with the session JWT + anon key:
`GET /auth/v1/oauth/authorizations/{id}`, `POST …/{id}/consent`
`{ action: "approve" | "deny" }` (returns `{ redirect_url }`),
`GET /auth/v1/user/oauth/grants`, `DELETE /auth/v1/user/oauth/grants?client_id=`.

Flow: no `authorization_id` → error card. Not signed in →
`/auth?returnTo=<encoded /oauth/consent?authorization_id=…>` (the Auth page
already honors `returnTo`). Details call may return `{ redirect_url }`
directly when Supabase already holds consent → redirect straight away (that
response carries no client info, so the page can't touch our grant row there;
it needn't, because revocation always deletes the Supabase grant *before*
marking ours revoked, so a Supabase auto-approve implies our row is still
active). Otherwise render one centered card: "**{client.name}** wants
to connect to your Stash" · client site host · **Can:** search your stash,
read saved items in full · **Can't:** add, edit or delete anything; export
your stash; see your account or billing · signed-in email · "Returns to
{redirect host}", with an explicit warning when the host is
`localhost`/`127.0.0.1` ("a program running on your computer — continue only
if you started this from an app you trust"; the MCP spec requires showing
loopback redirects). Buttons: **Allow access** / **Deny**. Approve = upsert
`agent_grants` (revoked_at → null) then consent → redirect. Deny = consent
deny → redirect. Static wash, no ambient animation (not one of the three
sanctioned surfaces). Voice per DESIGN.md: plain verbs, no apology.

**Settings → Connected agents** (`src/components/settings/ConnectedAgentsSettings.tsx`,
data via `src/hooks/useConnectedAgents.ts`, sentence rendering in
`src/utils/agentActivity.ts`). Fifth tab (icon: lucide `Bot`). Three cards:

1. *Connect an agent* — one paragraph ("Let an AI agent you trust search your
   stash. Agents get answers, never copies: they can search and read items one
   at a time, can't change anything, and every request is logged here."), the
   URL with a copy button, and three short how-tos: Claude web/desktop
   (Settings → Connectors → Add custom connector → paste URL), Claude Code
   (`claude mcp add --transport http stash https://www.gostash.it/mcp`), other
   MCP clients (any remote-MCP client with OAuth).
2. *Connected* — active grants: name, connected date, last used (relative),
   **Revoke** (confirm dialog). Revoke = Supabase grant delete (kills its
   sessions/refresh tokens) + `revoked_at = now()`. Empty state invites
   connecting.
3. *Activity* — last 50 log rows as sentences: "Claude searched for
   “restaurants in Saratoga” · 3 results", "Claude read “Beyond the Basics”",
   "Claude listed recent saves (links)", each with a relative time. Empty
   state: "No activity yet. Once an agent connects, every search and read
   shows up here."

No subscription gate in v1 (reading your own data). No iOS/macOS screens now;
the `ui-changes.md` entry carries the contracts for later.

**`vercel.json`**: rewrites for `/mcp` and `/mcp/:path*` to the function
(before the SPA catch-all); static `public/.well-known/oauth-protected-resource/mcp`
with a `headers` rule forcing `Content-Type: application/json` (best-effort:
Vercel treats `/.well-known` specially; the 401 pointer is the authoritative
path, and we verify the static one after deploy).

## Error handling

- Function: every failure returns proper JSON (never an empty 500);
  unexpected exceptions become JSON-RPC `-32603` with a generic message and a
  server-side `console.error` with detail. Auth failures carry the
  `WWW-Authenticate` challenge so clients start (or refresh) OAuth instead of
  surfacing a tool error. Revoked grant → `403` whose description tells the
  user where to reconnect.
- Consent page: every REST failure renders what happened and what to do
  ("This connection request expired. Start again from your agent."). Grant
  upsert failure blocks approval (never approve without a grant row).
- Settings: revoke is two writes; if the Supabase revoke succeeds and ours
  fails, the MCP door is still open until the token expires (≤1h) — the hook
  retries our update and shows an error; the reverse order is worse, so
  Supabase first.

## Testing

- **vitest** (existing `npm test`): `mcpProtocol.test.ts` (initialize
  negotiation, notifications → 202, batch handling, unknown method, tool
  errors as results), `search.test.ts` (request normalization: limits, type
  filtering, tag lowercasing, timestamps), `oauthConsent.test.ts` (auto-approve
  detection, loopback detection, return-to URL building),
  `agentActivity.test.ts` (sentence rendering per tool). Pure modules only;
  Deno-flavored imports stay in the shells.
- **Live verification** (all against production, since the OAuth consent URL
  is site URL + path and cannot point at a preview): `scripts/mcp-smoke.mjs`
  performs discovery → dynamic registration → PKCE authorize (operator or
  Playwright approves on the consent page) → token → `initialize`,
  `tools/list`, `search_stash`, `get_item`, then proves the fence (agent
  token against PostgREST `items` → no rows; against `search-items` → 403),
  then revocation (Settings → Revoke → next call fails). Claude Code as a real
  client (`claude mcp add … /mcp`) is the final manual check.

## Config & deploy sequence

1. Web (inert until OAuth is on): consent page, settings tab, rewrite,
   static metadata → push to `main` → Vercel.
2. Migration via Management API SQL; record in `schema_migrations`.
3. Deploy `mcp`, `search-items`, and every function that gained the agent
   guard (`add-note`, `add-url`, `add-file`, `check-subscription`,
   `create-checkout`, `create-trial-subscription`, `customer-portal`,
   `chat-with-content`, `summarize-content`, `post-comment`,
   `chat-with-all-content`, `get-discover-feed`). `config.toml` gains
   `[functions.mcp] verify_jwt = false` and `[auth.oauth_server]`.
4. Enable the OAuth server (Management API `PATCH /config/auth`: site URL,
   allow list, `oauth_server_enabled`, `oauth_server_allow_dynamic_registration`,
   `oauth_server_authorization_path`). This is the switch that makes it live.
5. Smoke test, fence test, revocation test, Claude Code check.
6. Docs: `PLATFORM_API.md` "Agents (MCP)" section; `ui-changes.md` entry;
   memory note.

## Out of scope (decided, not now)

`save_to_stash` (v1.1, via the canonical capture path); `get_taste_profile`
(needs Workstream E); topic-level scopes; personal access tokens / static
header auth; asymmetric JWT signing keys; iOS/macOS Connected-agents screens;
local (`supabase start`) OAuth development; MCP resources/prompts/SSE streams.

## Risks

- Vercel rewrite may not proxy POST + `Authorization` → fall back to the raw
  function URL (task 1 decides before anything depends on it).
- Claude Code registers with a loopback redirect (`http://localhost:<port>/callback`);
  Supabase's registration validation of `http` loopback URIs is undocumented.
  If it refuses, hosted Claude still works and Claude Code is reported as a
  gap.
- Supabase OAuth server is beta; dynamic registration is open by design
  (registration grants nothing without consent).
- Redeploying twelve functions for the guard means shipping whatever is on
  `main` for each; the repo's rule that `config.toml` matches deployed state
  keeps `verify_jwt` from flipping.
